#!/usr/bin/env python3
"""Native renderer capture on an isolated dummy Xorg, preserving user saves."""
from pathlib import Path
import ctypes as C, hashlib, json, os, re, subprocess, time
ROOT=Path(__file__).resolve().parents[3];OUT=Path(__file__).resolve().parent
RUN=ROOT/'.runtime/ascent-layer-proof'
for sub in ['home','data','config','cache']:(RUN/sub).mkdir(parents=True,exist_ok=True)
display_number=os.environ.get('ASCENT_PROOF_DISPLAY','369')
env=dict(os.environ,DISPLAY='localhost:'+display_number,HOME=str(RUN/'home'),XDG_DATA_HOME=str(RUN/'data'),XDG_CONFIG_HOME=str(RUN/'config'),XDG_CACHE_HOME=str(RUN/'cache'))
xlog=open(RUN/'xorg-stdout.log','w');glog=open(OUT/'native-runtime.log','w');vlog=open(RUN/'capture.log','w')
xorg=subprocess.Popen(['/usr/lib/xorg/Xorg',':'+display_number,'-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac','-config',str(ROOT/'tools/xorg_native_1920.conf'),'-logfile',str(RUN/'xorg.log')],stdout=xlog,stderr=subprocess.STDOUT)
game=video=None
try:
 time.sleep(1)
 x11=C.CDLL('libX11.so.6');xtst=C.CDLL('libXtst.so.6')
 x11.XOpenDisplay.argtypes=[C.c_char_p];x11.XOpenDisplay.restype=C.c_void_p;x11.XFlush.argtypes=[C.c_void_p]
 x11.XStringToKeysym.argtypes=[C.c_char_p];x11.XStringToKeysym.restype=C.c_ulong
 x11.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];x11.XKeysymToKeycode.restype=C.c_uint
 x11.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
 xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
 display=x11.XOpenDisplay(env['DISPLAY'].encode());assert display
 game=subprocess.Popen(['godot','--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--resolution','1280x720','--position','0,0','-s','res://source_art/2d_v5/ascent/runtime_ascent_proof.gd'],env=env,stdout=glog,stderr=subprocess.STDOUT)
 time.sleep(2)
 tree=subprocess.check_output(['xwininfo','-root','-tree'],env=env).decode();match=re.search(r'(0x[0-9a-f]+) "Ascent Backdrop Native Proof',tree);assert match,tree
 window=int(match.group(1),16);x11.XSetInputFocus(display,window,1,0);x11.XFlush(display)
 video=subprocess.Popen(['ffmpeg','-y','-f','x11grab','-framerate','30','-video_size','1280x720','-i',env['DISPLAY']+'+0,0','-an','-c:v','libx264','-preset','ultrafast','-crf','19','-pix_fmt','yuv420p',str(OUT/'native-ascent-layers.mp4')],env=env,stdin=subprocess.PIPE,stdout=vlog,stderr=subprocess.STDOUT)
 time.sleep(.5)
 key=x11.XKeysymToKeycode(display,x11.XStringToKeysym(b'Return'))
 xtst.XTestFakeKeyEvent(display,key,1,0);x11.XFlush(display);time.sleep(.04)
 xtst.XTestFakeKeyEvent(display,key,0,0);x11.XFlush(display)
 game.wait(timeout=90)
 assert game.returncode==0,(OUT/'native-runtime.log').read_text()
 video.communicate(b'q',timeout=10)
 data=json.loads((OUT/'native-render-validation.json').read_text())
 data['asset_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'assets/2d_v5/ascent').glob('*.png'))}
 data['component_sha256']=hashlib.sha256((ROOT/'scripts/ascent_backdrop_2d.gd').read_bytes()).hexdigest()
 data['capture']={'source':'native X11 output of actual Godot GL Compatibility renderer','start':'native XTest Enter','recording_fps':30,'engine_fps':'Reported separately from engine samples and rendered frame/wall interval; recording FPS is not an engine performance claim.','video':'source_art/2d_v5/ascent/native-ascent-layers.mp4'}
 (OUT/'native-render-validation.json').write_text(json.dumps(data,indent=2)+'\n')
 print(json.dumps({k:v for k,v in data.items() if k not in ['snapshots','engine_fps_samples']},indent=2))
finally:
 if video and video.poll() is None:video.communicate(b'q',timeout=10)
 if game and game.poll() is None:game.terminate();game.wait(timeout=5)
 xorg.terminate();xorg.wait(timeout=5)
 glog.close();xlog.close();vlog.close()
