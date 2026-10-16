#!/usr/bin/env python3
"""Isolated native X11 input driver for the actual game; no debug gameplay calls."""
import ctypes as C, json, os, pathlib, subprocess, sys, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
DISPLAY='localhost:'+os.environ.get('SC_QA_DISPLAY','190')
RUNTIME=ROOT/'.runtime'/os.environ.get('SC_QA_RUN','native-hud-qa')
for d in ['home','data','config','cache']:(RUNTIME/d).mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DISPLAY=DISPLAY,HOME=str(RUNTIME/'home'),XDG_DATA_HOME=str(RUNTIME/'data'),XDG_CONFIG_HOME=str(RUNTIME/'config'),XDG_CACHE_HOME=str(RUNTIME/'cache'))
xlog=open('/tmp/native-qa-xorg190.stdout','w')
xorg=subprocess.Popen(['/usr/lib/xorg/Xorg',':'+DISPLAY.split(':')[-1],'-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac','-config','/workspace/shared/reaper-portable/xorg1440.conf','-logfile','/tmp/native-qa-xorg190.log'],stdout=xlog,stderr=subprocess.STDOUT)
time.sleep(1)
log=open(ROOT/'docs/qa/v2-native-game.log','w')
game_args=['godot','--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility']
if os.environ.get('SC_QA_RESOLUTION'):game_args+=['--resolution',os.environ['SC_QA_RESOLUTION'],'--position','0,0']
game=subprocess.Popen(game_args,env=env,stdout=log,stderr=subprocess.STDOUT)
x11=C.CDLL('libX11.so.6');xtst=C.CDLL('libXtst.so.6')
x11.XOpenDisplay.argtypes=[C.c_char_p];x11.XOpenDisplay.restype=C.c_void_p
x11.XFlush.argtypes=[C.c_void_p];x11.XStringToKeysym.argtypes=[C.c_char_p];x11.XStringToKeysym.restype=C.c_ulong
x11.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];x11.XKeysymToKeycode.restype=C.c_uint
xtst.XTestFakeMotionEvent.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_ulong]
xtst.XTestFakeButtonEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
display=x11.XOpenDisplay(DISPLAY.encode())
if not display:raise RuntimeError('Isolated native display unavailable')
def click(x,y,button=1):
 xtst.XTestFakeMotionEvent(display,-1,int(x),int(y),0);x11.XFlush(display);time.sleep(.06)
 xtst.XTestFakeButtonEvent(display,button,1,0);x11.XFlush(display);time.sleep(.06)
 xtst.XTestFakeButtonEvent(display,button,0,0);x11.XFlush(display)
def key(name):
 code=x11.XKeysymToKeycode(display,x11.XStringToKeysym(name.encode()))
 xtst.XTestFakeKeyEvent(display,code,1,0);x11.XFlush(display);time.sleep(.06)
 xtst.XTestFakeKeyEvent(display,code,0,0);x11.XFlush(display)
def chord(names):
 codes=[x11.XKeysymToKeycode(display,x11.XStringToKeysym(name.encode())) for name in names]
 for code in codes:xtst.XTestFakeKeyEvent(display,code,1,0)
 x11.XFlush(display);time.sleep(.07)
 for code in reversed(codes):xtst.XTestFakeKeyEvent(display,code,0,0)
 x11.XFlush(display)
def state():
 paths=list((RUNTIME/'data').rglob('savegame.json'))
 if not paths:return {'saved':False}
 data=json.loads(paths[0].read_text())
 return {k:data.get(k) for k in ['day','phase','credits','reputation','jobs_today','active_contract_id','in_flight','contracts','last_settlement','last_trials','design','inventory','settings']}
def shot(name):
 path=ROOT/'docs/qa'/('v2-native-'+name+'.png')
 subprocess.run(['/usr/bin/import','-window','root',str(path)],env=env,check=True)
 return str(path)
time.sleep(8)
print(json.dumps({'ready':True,'display':DISPLAY,'pid':game.pid,'screenshot':shot('01-hub'),'state':state()},ensure_ascii=False),flush=True)
try:
 if '--motion-proof' in sys.argv:
  # Capture real XTest input in one uncut 20-second interaction. This records
  # game output, not an engine movie mode or a claim about achieved game FPS.
  click(15,360);time.sleep(.3)
  if os.environ.get('SC_QA_QUALITY') in ['auto','low','standard','high']:
   click(459,49);time.sleep(.3);click(745,455);time.sleep(.2);key('Home')
   for _ in range(['auto','low','standard','high'].index(os.environ['SC_QA_QUALITY'])+1):key('Down')
   key('Return');time.sleep(.5);key('Escape');time.sleep(.3)
   actual_quality=state().get('settings',{}).get('quality','auto')
   if actual_quality!=os.environ['SC_QA_QUALITY']:raise RuntimeError('Native quality selection mismatch: '+actual_quality)
  click(150,830);time.sleep(1.0)
  video=ROOT/'docs/qa'/os.environ.get('SC_QA_VIDEO','astra-native-motion.mp4')
  ffmpeg_log=open(ROOT/'docs/qa/astra-native-video.log','w')
  recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','x11grab','-framerate','24','-video_size','1440x900','-i',DISPLAY+'.0','-t','20','-vf','scale=1280:800','-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],env=env,stdout=ffmpeg_log,stderr=subprocess.STDOUT)
  time.sleep(1.6);shot('astra-counter');click(1139,580);time.sleep(.6)
  click(492,834);time.sleep(1.0);click(677,453);time.sleep(.35);key('r');time.sleep(.5);shot('astra-workbench')
  click(1118,843);time.sleep(.4);shot('astra-charge');time.sleep(.5);shot('astra-ignition');time.sleep(3.0);shot('astra-flight')
  recorder.wait(timeout=35)
  shot('astra-report')
  print(json.dumps({'recorded':str(video),'bytes':video.stat().st_size,'state':state()},ensure_ascii=False),flush=True)
  sys.exit(0)
 if '--record' in sys.argv:
  click(15,360);time.sleep(.4)
  video=ROOT/'docs/qa'/os.environ.get('SC_QA_VIDEO','v2-gameplay-wip.mp4')
  ffmpeg_log=open(ROOT/'docs/qa/v2-native-video.log','w')
  recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','x11grab','-framerate','20','-video_size','1440x900','-i',DISPLAY+'.0','-t','30','-vf','scale=1280:800','-c:v','libx264','-preset','veryfast','-crf','24','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],env=env,stdout=ffmpeg_log,stderr=subprocess.STDOUT)
  time.sleep(1.5);click(150,830);time.sleep(1.5)
  shot('21-fresh-counter');click(1139,580);time.sleep(.8)
  shot('22-first-toast-fixed');print(json.dumps({'first_reveal_state':state()},ensure_ascii=False),flush=True)
  time.sleep(.8);click(492,834);time.sleep(1.8);click(677,453);time.sleep(.7)
  key('r');time.sleep(.8);shot('23-video-workbench')
  click(1118,843);time.sleep(4.0);shot('24-video-flight')
  time.sleep(8.0);shot('25-video-report');time.sleep(1)
  click(961,827);time.sleep(1.5);shot('26-video-dispatch-review');click(572,672)
  recorder.wait(timeout=45)
  print(json.dumps({'recorded':str(video),'bytes':video.stat().st_size,'state':state()},ensure_ascii=False),flush=True)
  sys.exit(0)
 for line in sys.stdin:
  try:
   cmd=json.loads(line)
   if 'click' in cmd:click(*cmd['click'])
   if 'key' in cmd:key(cmd['key'])
   if 'chord' in cmd:chord(cmd['chord'])
   time.sleep(float(cmd.get('sleep',.3)))
   result={'running':game.poll() is None}
   if 'shot' in cmd:result['screenshot']=shot(cmd['shot'])
   if cmd.get('state'):result['state']=state()
   with open(ROOT/'docs/qa/v2-native-input-events.jsonl','a') as trace:trace.write(json.dumps({'input':cmd,'result':result},ensure_ascii=False)+'\n')
   print(json.dumps(result,ensure_ascii=False),flush=True)
   if cmd.get('quit'):break
  except Exception as exc:print(json.dumps({'error':repr(exc)}),flush=True)
finally:
 game.terminate()
 try:game.wait(timeout=5)
 except subprocess.TimeoutExpired:game.kill()
 xorg.terminate();xorg.wait(timeout=5)
