#!/usr/bin/env python3
"""Explicitly scheduled native full-Main fixture. Requires parent GPU release."""
from pathlib import Path
import argparse,ctypes as C,json,os,re,subprocess,time,signal
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--released',action='store_true');p.add_argument('--display',type=int,default=693);p.add_argument('--mode',choices=['evasion','neutral','drill','restore_destroyed'],default='evasion');p.add_argument('--name',required=True);p.add_argument('--lifecycle',action='store_true');a=p.parse_args()
if not a.released:p.error('Parent must release the GPU window first.')
O=R/'evidence'/a.name
if O.exists():p.error('Fresh evidence name required; failures are preserved.')
O.mkdir(parents=True)
rt=O/'runtime'
for s in ['home','data','config','cache']:(rt/s).mkdir(parents=True)
display='localhost:'+str(a.display)
env=dict(os.environ,DISPLAY=display,HOME=str(rt/'home'),XDG_DATA_HOME=str(rt/'data'),XDG_CONFIG_HOME=str(rt/'config'),XDG_CACHE_HOME=str(rt/'cache'))
fixture={'evasion':'evasion-tick-2010','neutral':'neutral-tick-2010','drill':'drill-tick-2568','restore_destroyed':'drill-tick-2646'}[a.mode]
logs=[];procs=[];events=[];held=False;x=None;x11=None

def log(name):
 f=open(O/name,'w');logs.append(f);return f

def observation():
 try:return json.loads((O/'native-latest.json').read_text())
 except (ValueError,FileNotFoundError):return None

try:
 xorg=subprocess.Popen(['/usr/lib/xorg/Xorg',':'+str(a.display),'-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac','-config',str(R/'tools/xorg_native_1920.conf'),'-logfile',str(O/'xorg.log')],stdout=log('xorg.stdout'),stderr=subprocess.STDOUT);procs.append(xorg);time.sleep(1)
 x11=C.CDLL('libX11.so.6');xtst=C.CDLL('libXtst.so.6')
 x11.XOpenDisplay.argtypes=[C.c_char_p];x11.XOpenDisplay.restype=C.c_void_p;x11.XFlush.argtypes=[C.c_void_p]
 x11.XInternAtom.argtypes=[C.c_void_p,C.c_char_p,C.c_int];x11.XInternAtom.restype=C.c_ulong
 x11.XStringToKeysym.argtypes=[C.c_char_p];x11.XStringToKeysym.restype=C.c_ulong
 x11.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];x11.XKeysymToKeycode.restype=C.c_uint
 x11.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
 x11.XDefaultRootWindow.argtypes=[C.c_void_p];x11.XDefaultRootWindow.restype=C.c_ulong
 x11.XResizeWindow.argtypes=[C.c_void_p,C.c_ulong,C.c_uint,C.c_uint]
 xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
 x=x11.XOpenDisplay(display.encode())
 if not x:raise RuntimeError('Scheduled same-exec TCP Xorg unavailable')
 for atom in [b'WM_PROTOCOLS',b'WM_DELETE_WINDOW']:x11.XInternAtom(x,atom,0)
 x11.XFlush(x)
 def key(name,down):
  code=x11.XKeysymToKeycode(x,x11.XStringToKeysym(name.encode()));xtst.XTestFakeKeyEvent(x,code,int(down),0);x11.XFlush(x)
  events.append({'action':'key','key':name,'held':down,'observed':observation(),'wall':time.monotonic()})
 def tap(name):key(name,True);time.sleep(.06);key(name,False)
 game=subprocess.Popen(['godot','--path',str(R),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--resolution','1280x720','--position','0,0','--script','res://tools/native_meteor_integration.gd','--','--output='+str(O),'--mode='+a.mode,'--fixture='+str(R/'evidence/trajectories'/f'{fixture}.json')],env=env,stdout=log('game.log'),stderr=subprocess.STDOUT);procs.append(game)
 started=time.monotonic();window=None
 while time.monotonic()-started<45:
  if game.poll() is not None:raise RuntimeError('Main closed during fixture replay')
  if observation():
   tree=subprocess.check_output(['xwininfo','-root','-tree'],env=env,text=True);match=re.search(r'(0x[0-9a-f]+) "Star Courier[^\"]*"',tree)
   if match:window=int(match.group(1),16);break
  time.sleep(.05)
 if not window:raise RuntimeError('Full Main fixture did not become ready')
 x11.XSetInputFocus(x,window,1,0);x11.XFlush(x);time.sleep(.2)
 recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','x11grab','-framerate','24','-video_size','1280x720','-i',display+'.0+0,0','-t','22','-an','-c:v','libx264','-preset','veryfast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(O/'full-hud-crossing.mp4')],env=env,stdout=log('ffmpeg.log'),stderr=subprocess.STDOUT);procs.append(recorder)
 tap('p');started=time.monotonic();lifecycle_done=False
 while game.poll() is None and time.monotonic()-started<30:
  if (O/'native-summary.json').exists():break
  o=observation()
  if not o:time.sleep(.01);continue
  if a.lifecycle and not lifecycle_done and o['time']>=34.7:
   tap('p');time.sleep(.2);before=observation()
   x11.XResizeWindow(x,window,1600,900);x11.XFlush(x);time.sleep(.4)
   subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','x11grab','-video_size','1600x900','-i',display+'.0+0,0','-frames:v','1',str(O/'paused-warning-1600x900.png')],env=env,check=True)
   after=observation();events.append({'action':'paused_resize','before':before,'after':after})
   x11.XResizeWindow(x,window,1280,720);x11.XFlush(x);time.sleep(.2)
   # Real focus-out/in; focus return alone must remain paused.
   x11.XSetInputFocus(x,x11.XDefaultRootWindow(x),1,0);x11.XFlush(x);time.sleep(.3);away=observation()
   x11.XSetInputFocus(x,window,1,0);x11.XFlush(x);time.sleep(.3);returned=observation()
   events.append({'action':'focus_restore','before':before,'away':away,'returned':returned})
   tap('p');lifecycle_done=True;o=observation()
  center=o['event']['center_crossing_seconds'];want=a.mode=='evasion' and center-2.6<=o['time']<center-.4
  if want!=held:key('w',want);held=want
  time.sleep(.008)
 if held:key('w',False);held=False
 if recorder.poll() is None:recorder.send_signal(signal.SIGINT)
 recorder.wait(timeout=10)
 summary=json.loads((O/'native-summary.json').read_text())
 summary.update({'driver':'full production Main with real XTest keyboard; scripted analog drill fixture only','fixture_replay':'saved production input timeline reconstructed from rest','native_actions':events,'native_video_silent':True,'display':a.display,'lifecycle_requested':a.lifecycle})
 (O/'capture-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:summary[k] for k in ['mode','max_event_nodes','max_fragments','final','frames']},ensure_ascii=False),flush=True)
finally:
 if held and x:key('w',False)
 for proc in reversed(procs):
  if proc.poll() is None:
   proc.terminate()
   try:proc.wait(timeout=5)
   except subprocess.TimeoutExpired:proc.kill();proc.wait()
 for f in logs:f.close()
 (O/'driver-actions.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n')
