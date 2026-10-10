"""Fixture setup is scripted; all reveal/advance/mute/skip inputs use native XTest.
Runs on independent :365 with isolated HOME/XDG. Never opens the user's save.
"""
from pathlib import Path
import ctypes as C, json, os, re, subprocess, time
ROOT=Path(__file__).resolve().parents[3];OUT=Path(__file__).resolve().parent
RUN=ROOT/'.runtime/dialogue-native-proof'
for sub in ['home','data','config','cache']:(RUN/sub).mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DISPLAY='localhost:365',HOME=str(RUN/'home'),XDG_DATA_HOME=str(RUN/'data'),XDG_CONFIG_HOME=str(RUN/'config'),XDG_CACHE_HOME=str(RUN/'cache'))
xlog=open(RUN/'xorg-stdout.log','w');glog=open(OUT/'native-runtime.log','w')
xorg=subprocess.Popen(['/usr/lib/xorg/Xorg',':365','-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac','-config','/workspace/shared/reaper-portable/xorg1440.conf','-logfile',str(RUN/'xorg.log')],stdout=xlog,stderr=subprocess.STDOUT)
game=None
try:
 time.sleep(1)
 x11=C.CDLL('libX11.so.6');xtst=C.CDLL('libXtst.so.6')
 x11.XOpenDisplay.argtypes=[C.c_char_p];x11.XOpenDisplay.restype=C.c_void_p
 x11.XFlush.argtypes=[C.c_void_p];x11.XStringToKeysym.argtypes=[C.c_char_p];x11.XStringToKeysym.restype=C.c_ulong
 x11.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];x11.XKeysymToKeycode.restype=C.c_uint
 x11.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
 xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
 xtst.XTestFakeMotionEvent.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_ulong];xtst.XTestFakeButtonEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
 display=x11.XOpenDisplay(env['DISPLAY'].encode());assert display
 game=subprocess.Popen(['godot','--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--resolution','1280x720','--position','0,0','-s','res://source_art/2d_v5/dialogue/runtime_dialogue_proof.gd'],env=env,stdout=glog,stderr=subprocess.STDOUT)
 time.sleep(4)
 tree=subprocess.check_output(['xwininfo','-root','-tree'],env=env).decode();match=re.search(r'(0x[0-9a-f]+) "Courier Dialogue Native Proof',tree);assert match,tree
 window=int(match.group(1),16);x11.XSetInputFocus(display,window,1,0);x11.XFlush(display)
 events=[]
 def shot(name):
  subprocess.run(['/usr/bin/import','-window',hex(window),str(OUT/(name+'.png'))],env=env,check=True)
 def key(name):
  code=x11.XKeysymToKeycode(display,x11.XStringToKeysym(name.encode()));assert code
  xtst.XTestFakeKeyEvent(display,code,1,0);x11.XFlush(display);time.sleep(.045)
  xtst.XTestFakeKeyEvent(display,code,0,0);x11.XFlush(display);events.append({'key':name,'native':'XTest'});time.sleep(.12)
 def click(x,y):
  xtst.XTestFakeMotionEvent(display,-1,x,y,0);x11.XFlush(display);time.sleep(.04)
  xtst.XTestFakeButtonEvent(display,1,1,0);x11.XFlush(display);time.sleep(.04)
  xtst.XTestFakeButtonEvent(display,1,0,0);x11.XFlush(display);events.append({'click':[x,y],'native':'XTest'});time.sleep(.12)
 shot('runtime-01-npc-left')
 for k in ['w','Left','p','Shift_L']:key(k)
 click(600,220) # A blank modal area; must never reach underlying scene.
 key('Return');time.sleep(1.1);shot('runtime-02-clerk-right')
 key('m');shot('runtime-03-muted')
 key('space');time.sleep(1.1);shot('runtime-04-npc-pleased')
 click(158,692);shot('runtime-05-pointer-audio')
 key('Escape');game.wait(timeout=6)
 assert game.returncode==0,(OUT/'native-runtime.log').read_text()
 result=json.loads((OUT/'native-result.json').read_text());assert result['skipped'] and result['leaked_keys']==0 and result['underlying_clicks']==0,result
 assert result['snapshot']['active_voices']==0 and result['snapshot']['queued_bleeps']==0,result
 (OUT/'native-input-events.json').write_text(json.dumps({'test':'isolated component fixture; native XTest events; no gameplay methods after setup','events':events,'result':result},indent=2)+'\n')
 print(json.dumps(result,indent=2))
finally:
 if game and game.poll() is None:game.terminate();game.wait(timeout=5)
 xorg.terminate();xorg.wait(timeout=5)
 glog.close();xlog.close()
