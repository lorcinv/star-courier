#!/usr/bin/env python3
"""Independent native X11 QA driver. No gameplay methods, save writes, or debug input.

One JSON command per stdin line. XTest injects real mouse/keyboard events into an
isolated Xorg display; X11 supplies window resize/close requests. All observations
come from screenshots, process logs, and read-only copies of game-written saves.
"""
import ctypes as C
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUN_NAME = os.environ.get('SC_QA_RUN', 'astra-native-regression-20261010')
DISPLAY_NUMBER = os.environ.get('SC_QA_DISPLAY', '245')
DISPLAY = 'localhost:' + DISPLAY_NUMBER
OUT = ROOT / os.environ.get('SC_QA_OUT', 'docs/qa/astra-native-regression')
RUNTIME = ROOT / '.runtime' / RUN_NAME
OUT.mkdir(parents=True, exist_ok=True)
for d in ['home', 'data', 'config', 'cache']:
    (RUNTIME / d).mkdir(parents=True, exist_ok=True)
env = dict(os.environ, DISPLAY=DISPLAY, HOME=str(RUNTIME / 'home'),
           XDG_DATA_HOME=str(RUNTIME / 'data'), XDG_CONFIG_HOME=str(RUNTIME / 'config'),
           XDG_CACHE_HOME=str(RUNTIME / 'cache'))
log = open(OUT / 'game.log', 'a')
xlog = open(OUT / 'xorg.stdout', 'w')
xorg = subprocess.Popen(['/usr/lib/xorg/Xorg', ':' + DISPLAY_NUMBER, '-noreset', '-nolisten', 'unix',
                         '-nolisten', 'local', '-listen', 'tcp', '-ac', '-config',
                         os.environ.get('SC_QA_XORG_CONFIG','/workspace/shared/reaper-portable/xorg1440.conf'), '-logfile', str(OUT / 'xorg.log')],
                        stdout=xlog, stderr=subprocess.STDOUT)
time.sleep(1)
wm = None
if os.environ.get('SC_QA_USE_WM') == '1':
    wm_log = open(OUT / 'xfwm4.log', 'a')
    wm = subprocess.Popen(['dbus-run-session', '--', 'xfwm4', '--compositor=off', '--sm-client-disable'], env=env, stdout=wm_log, stderr=subprocess.STDOUT)
    time.sleep(.7)
x11 = C.CDLL('libX11.so.6')
xtst = C.CDLL('libXtst.so.6')
x11.XOpenDisplay.argtypes = [C.c_char_p]
x11.XOpenDisplay.restype = C.c_void_p
x11.XFlush.argtypes = [C.c_void_p]
x11.XStringToKeysym.argtypes = [C.c_char_p]
x11.XStringToKeysym.restype = C.c_ulong
x11.XKeysymToKeycode.argtypes = [C.c_void_p, C.c_ulong]
x11.XKeysymToKeycode.restype = C.c_uint
x11.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
x11.XResizeWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_uint, C.c_uint]
x11.XInternAtom.argtypes = [C.c_void_p, C.c_char_p, C.c_int]
x11.XInternAtom.restype = C.c_ulong
x11.XSendEvent.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
xtst.XTestFakeKeyEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
display = x11.XOpenDisplay(DISPLAY.encode())
if not display:
    raise RuntimeError('Isolated native Xorg unavailable')
# Bare Xorg has no window manager to create these atoms. Godot 4.6 looks up
# WM_DELETE_WINDOW with only_if_exists=true during X11 startup; creating it only
# on close leaves its stored atom as None. Register ordinary WM protocol atoms
# before launching the game. Source: Godot 4.6 display_server_x11.cpp, atom
# internment and request_close_embedded_process(), on the official Godot repo.
wm_atoms = {name: x11.XInternAtom(display, name.encode(), 0)
            for name in ['WM_PROTOCOLS', 'WM_DELETE_WINDOW']}
x11.XFlush(display)
game = None
window = None
sequence = 0
recorders = []

class ClientData(C.Union):
    _fields_ = [('b', C.c_char * 20), ('s', C.c_short * 10), ('l', C.c_long * 5)]

class XClientMessageEvent(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong),
                ('format', C.c_int), ('data', ClientData)]

class XEvent(C.Union):
    _fields_ = [('xclient', XClientMessageEvent), ('pad', C.c_long * 24)]

def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def game_window():
    tree = subprocess.check_output(['xwininfo', '-root', '-tree'], env=env).decode()
    match = re.search(r'(0x[0-9a-f]+) "星际快递[^"]*"', tree)
    if not match:
        raise RuntimeError('Game window not found: ' + tree)
    return int(match.group(1), 16)

def geometry():
    if not window or game.poll() is not None:
        return None
    raw = subprocess.check_output(['xwininfo', '-id', hex(window)], env=env).decode()
    return {key: int(re.search(pattern, raw).group(1)) for key, pattern in {
        'width': r'Width: (\d+)', 'height': r'Height: (\d+)',
        'x': r'Absolute upper-left X:\s+(-?\d+)', 'y': r'Absolute upper-left Y:\s+(-?\d+)'
    }.items()}

def start(wait=7):
    global game, window
    if game is not None and game.poll() is None:
        raise RuntimeError('Game is already running')
    args = ['godot', '--path', str(ROOT), '--audio-driver', 'Dummy', '--rendering-method',
            'gl_compatibility', '--resolution', os.environ.get('SC_QA_RESOLUTION', '1280x800'),
            '--position', '0,0']
    # Bounded opt-in instrumentation: the entry loads the unchanged main scene
    # and records its real Master bus on native F8. Never accept arbitrary code
    # or an output outside this run's evidence directory through this option.
    entry = os.environ.get('SC_QA_ENTRY_SCRIPT', '')
    if entry:
        if entry != 'res://tools/qa_audio_game.gd':
            raise ValueError('SC_QA_ENTRY_SCRIPT only permits res://tools/qa_audio_game.gd')
        audio = pathlib.Path(os.environ.get('SC_QA_AUDIO_OUTPUT', str(OUT/'integrated-audio.wav'))).resolve()
        if not audio.is_relative_to(OUT.resolve()) or audio.suffix != '.wav':
            raise ValueError('QA audio must be a .wav inside SC_QA_OUT')
        args += ['--script', entry, '--', '--qa-audio-output='+str(audio)]
    log.write('\nQA LAUNCH ' + timestamp() + '\n'); log.flush()
    game = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(wait)
    window = game_window()
    x11.XSetInputFocus(display, window, 1, 0); x11.XFlush(display)

def click(x, y, button=1):
    geom = geometry()
    x += geom['x']; y += geom['y']
    xtst.XTestFakeMotionEvent(display, -1, int(x), int(y), 0); x11.XFlush(display); time.sleep(.06)
    xtst.XTestFakeButtonEvent(display, button, 1, 0); x11.XFlush(display); time.sleep(.06)
    xtst.XTestFakeButtonEvent(display, button, 0, 0); x11.XFlush(display)

def key(name):
    code = x11.XKeysymToKeycode(display, x11.XStringToKeysym(name.encode()))
    if not code: raise ValueError('Unknown keysym ' + name)
    xtst.XTestFakeKeyEvent(display, code, 1, 0); x11.XFlush(display); time.sleep(.06)
    xtst.XTestFakeKeyEvent(display, code, 0, 0); x11.XFlush(display)

def chord(names):
    codes = [x11.XKeysymToKeycode(display, x11.XStringToKeysym(name.encode())) for name in names]
    for code in codes: xtst.XTestFakeKeyEvent(display, code, 1, 0)
    x11.XFlush(display); time.sleep(.07)
    for code in reversed(codes): xtst.XTestFakeKeyEvent(display, code, 0, 0)
    x11.XFlush(display)

def close():
    # A live WM receives actual Alt+F4. Without one, send the exact native
    # WM_DELETE_WINDOW client message that a window close button produces.
    # Neither route calls gameplay methods or writes the game's save.
    x11.XSetInputFocus(display, window, 1, 0); x11.XFlush(display)
    if wm is not None and wm.poll() is None:
        chord(['Alt_L', 'F4'])
    else:
        event = XEvent()
        event.xclient.type = 33  # ClientMessage
        event.xclient.display = display
        event.xclient.window = window
        event.xclient.message_type = x11.XInternAtom(display, b'WM_PROTOCOLS', 0)
        event.xclient.format = 32
        event.xclient.data.l[0] = x11.XInternAtom(display, b'WM_DELETE_WINDOW', 0)
        event.xclient.data.l[1] = 0  # CurrentTime
        if not x11.XSendEvent(display, window, 0, 0, C.byref(event)):
            raise RuntimeError('Native WM_DELETE_WINDOW delivery failed')
        x11.XFlush(display)
    game.wait(timeout=12)

def state():
    paths = list((RUNTIME / 'data').rglob('savegame.json'))
    if not paths: return {'saved': False}
    return json.loads(paths[0].read_text())

def snapshot(name):
    target = OUT / (name + '-save.json')
    target.write_text(json.dumps(state(), ensure_ascii=False, indent=2) + '\n')
    return str(target)

def shot(name):
    path = OUT / (name + '.png')
    subprocess.run(['/usr/bin/import', '-window', hex(window), str(path)], env=env, check=True)
    return str(path)

def execute(cmd):
    if 'record' in cmd:
        spec=cmd['record']; geom=geometry(); path=OUT/(spec.get('name','native-motion')+'.mp4')
        record_log=open(OUT/(path.stem+'-ffmpeg.log'),'w')
        recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','x11grab',
            '-framerate','24','-video_size',str(geom['width'])+'x'+str(geom['height']),
            '-i',DISPLAY+'.0+'+str(geom['x'])+','+str(geom['y']),'-t',str(spec.get('seconds',20)),
            '-c:v','libx264','-preset','veryfast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(path)],
            env=env,stdout=record_log,stderr=subprocess.STDOUT)
        recorders.append((recorder,path,record_log))
    if cmd.get('close'): close()
    if cmd.get('interrupt'):
        game.terminate(); game.wait(timeout=5)
    if 'start' in cmd: start(float(cmd['start']))
    if 'resize' in cmd:
        x11.XResizeWindow(display, window, *cmd['resize']); x11.XFlush(display)
    if 'click' in cmd: click(*cmd['click'])
    if 'key' in cmd: key(cmd['key'])
    if 'chord' in cmd: chord(cmd['chord'])
    for act in cmd.get('actions', []):
        execute(act)
    time.sleep(float(cmd.get('sleep', .3)))
    result = {'running': game.poll() is None, 'geometry': geometry()}
    if cmd.get('finish_record'):
        for recorder,path,record_log in recorders:recorder.wait(timeout=45);record_log.flush()
        result['recordings']=[{'path':str(path),'bytes':path.stat().st_size,'capture_fps':24,'audio':'silent X11 capture','engine_fps_claim':False} for recorder,path,_ in recorders]
    if 'shot' in cmd: result['screenshot'] = shot(cmd['shot'])
    if 'snapshot' in cmd: result['save_snapshot'] = snapshot(cmd['snapshot'])
    if cmd.get('state'): result['state'] = state()
    return result

try:
    start(float(os.environ.get('SC_QA_START_WAIT', '7')))
    if os.environ.get('SC_QA_PAUSE_ON_START') == '1':
        key('space'); time.sleep(.25)
    metadata = {'method': 'Native Godot window; libXTest mouse/keyboard; native X11 resize/close; no gameplay API calls or save mutation',
                'display': DISPLAY, 'runtime': str(RUNTIME), 'started_utc': timestamp(),
                'entry_script': os.environ.get('SC_QA_ENTRY_SCRIPT', 'project.godot main scene'),
                'wm_atoms_registered_before_game': wm_atoms,
                'engine': subprocess.check_output(['godot', '--version'], env=env).decode().strip(),
                'source_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                  for name in ['scripts/main.gd', 'scripts/game_hud.gd', 'scripts/world_view_2d.gd',
                                               'scripts/economy.gd', 'scripts/simulation.gd', 'scripts/pilot_simulation.gd',
                                               'scripts/pilot_profile.gd', 'scripts/pilot_timeline.gd',
                                               'scripts/flight_backdrop_2d.gd', 'scripts/assembly_2d.gd', 'project.godot']}}
    (OUT / ('run-metadata-' + os.environ.get('SC_QA_SESSION', 'initial') + '.json')).write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'ready': True, 'pid': game.pid, 'geometry': geometry(), 'screenshot': shot(os.environ.get('SC_QA_READY_SHOT', '01-hub')), 'state': state()}, ensure_ascii=False), flush=True)
    for line in sys.stdin:
        try:
            cmd = json.loads(line)
            result = execute(cmd)
        except Exception as exc:
            result = {'error': repr(exc)}
        sequence += 1
        event = {'sequence': sequence, 'session': os.environ.get('SC_QA_SESSION', 'initial'), 'at': timestamp(), 'input': cmd, 'result': result}
        with open(OUT / 'input-events.jsonl', 'a') as trace:
            trace.write(json.dumps(event, ensure_ascii=False) + '\n')
        print(json.dumps(result, ensure_ascii=False), flush=True)
        if cmd.get('quit'): break
finally:
    for recorder,path,record_log in recorders:
        if recorder.poll() is None:
            recorder.terminate()
            try:recorder.wait(timeout=5)
            except subprocess.TimeoutExpired:recorder.kill()
        record_log.close()
    if game is not None and game.poll() is None:
        try: close()
        except Exception:
            game.terminate()
            try: game.wait(timeout=5)
            except subprocess.TimeoutExpired: game.kill()
    if wm is not None and wm.poll() is None:
        wm.terminate()
        try: wm.wait(timeout=3)
        except subprocess.TimeoutExpired: wm.kill()
    xorg.terminate()
    xorg.wait(timeout=5)
