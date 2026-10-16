#!/usr/bin/env python3
"""Bounded real-clock shop route fixture, not OS-native gameplay input."""
from pathlib import Path
import hashlib, json, os, subprocess, time
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/qa/v5/shop-locomotion-route'
OUT.mkdir(parents=True, exist_ok=True)
RUNTIME = ROOT / '.runtime/shop-locomotion-route'
for item in ['home', 'data', 'config', 'cache']:
    (RUNTIME / item).mkdir(parents=True, exist_ok=True)
display = os.environ.get('SC_SHOP_ROUTE_DISPLAY', '541')
env = dict(os.environ, DISPLAY='localhost:' + display,
           HOME=str(RUNTIME / 'home'), XDG_DATA_HOME=str(RUNTIME / 'data'),
           XDG_CONFIG_HOME=str(RUNTIME / 'config'), XDG_CACHE_HOME=str(RUNTIME / 'cache'))
xlog = (OUT / 'xorg.stdout').open('w')
glog = (OUT / 'game.log').open('w')
flog = (OUT / 'ffmpeg.log').open('w')
xorg = subprocess.Popen(['/usr/lib/xorg/Xorg', ':' + display, '-noreset', '-nolisten', 'unix',
                         '-nolisten', 'local', '-listen', 'tcp', '-ac', '-config',
                         str(ROOT / 'tools/xorg_native_1920.conf'), '-logfile', str(OUT / 'xorg.log')],
                        stdout=xlog, stderr=subprocess.STDOUT)
game = capture = None
try:
    time.sleep(1)
    capture = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-y', '-f', 'x11grab',
                                '-framerate', '30', '-video_size', '1280x720', '-i', env['DISPLAY'] + '.0+0,0',
                                '-t', '12', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '17',
                                '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(OUT / 'shop-route-normal-speed.mp4')],
                               env=env, stdout=flog, stderr=subprocess.STDOUT)
    started = time.monotonic()
    game = subprocess.Popen(['godot', '--path', str(ROOT), '--audio-driver', 'Dummy', '--rendering-method',
                             'gl_compatibility', '--resolution', '1280x720', '--position', '0,0', '--script',
                             'res://tests/shop_locomotion_render_fixture.gd'],
                            env=env, stdout=glog, stderr=subprocess.STDOUT)
    game.wait(timeout=30)
    capture.wait(timeout=20)
    metadata = {'real_wall_seconds': time.monotonic() - started, 'game_exit': game.returncode,
                'capture_exit': capture.returncode, 'capture_fps': 30, 'engine_fps_claim': None,
                'fixed_fps': False, 'speedup': False, 'native_renderer': True, 'native_gameplay_input': False,
                'fixture': 'Real-clock walk, stop, held run, reversal, and automatic counter return.', 'sources': {}}
    for name in ['scripts/shop_locomotion_2d.gd', 'scripts/world_view_2d.gd', 'scripts/actor_motion_2d.gd',
                 'assets/2d_v5/actors/cooperative/motion-manifest.json', 'tests/shop_locomotion_render_fixture.gd']:
        metadata['sources'][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    (OUT / 'capture-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata, indent=2))
    if game.returncode or capture.returncode:
        raise RuntimeError('Shop route fixture or capture failed; inspect logs.')
finally:
    for process in [game, capture, xorg]:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
