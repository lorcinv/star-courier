#!/usr/bin/env python3
"""Prepared actual XTest/native-control proof. Requires explicit exclusive GPU grant.
No engine-synthesized events, scripted stills, physics loops, state seeding or save edits.
The observer only reads runtime state and captures the actual full viewport.
"""
import argparse,ctypes as C,ctypes.util,hashlib,json,os,subprocess,time
from pathlib import Path

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--approved',action='store_true');ap.add_argument('--release-note',required=True)
 ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);ap.add_argument('--display',required=True)
 a=ap.parse_args()
 if not a.approved:ap.error('Explicit shared renderer permission is required')
 root=a.candidate.resolve();out=a.out.resolve()
 if out.exists():raise RuntimeError('Choose a fresh output directory')
 out.mkdir(parents=True);env=dict(os.environ,DISPLAY=a.display)
 for kind in ['data','config','cache']:
  path=out/'runtime'/kind;path.mkdir(parents=True);env['XDG_'+kind.upper()+'_HOME']=str(path)
 paths=[root/'scripts'/f'{s}.gd' for s in ['main','world_view_2d','courier_input','shop_investigation','clerk_rigid_motion_2d','clerk_rigid_pose_2d','customer_review_phone']]
 paths+=[root/'assets/2d_v5/investigation/black-marble-pixel.png',root/'assets/fonts/ChineseSans.otf']
 hashes=lambda:{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
 before=hashes();events=[];checks=[]
 x=C.CDLL(ctypes.util.find_library('X11'));xt=C.CDLL(ctypes.util.find_library('Xtst'))
 for name,types,restype in [('XOpenDisplay',[C.c_char_p],C.c_void_p),('XStringToKeysym',[C.c_char_p],C.c_ulong),('XKeysymToKeycode',[C.c_void_p,C.c_ulong],C.c_uint),('XSetInputFocus',[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong],C.c_int),('XResizeWindow',[C.c_void_p,C.c_ulong,C.c_uint,C.c_uint],C.c_int),('XDefaultRootWindow',[C.c_void_p],C.c_ulong),('XFlush',[C.c_void_p],C.c_int),('XCloseDisplay',[C.c_void_p],C.c_int)]:
  fn=getattr(x,name);fn.argtypes=types;fn.restype=restype
 xt.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
 xt.XTestFakeButtonEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
 xt.XTestFakeMotionEvent.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_ulong]
 d=x.XOpenDisplay(a.display.encode())
 if not d:raise RuntimeError('Approved display unavailable')
 x.XInternAtom.argtypes=[C.c_void_p,C.c_char_p,C.c_int];x.XInternAtom.restype=C.c_ulong
 for atom in [b'WM_PROTOCOLS',b'WM_DELETE_WINDOW']:x.XInternAtom(d,atom,0)
 x.XFlush(d)
 log=(out/'game.log').open('w')
 game=subprocess.Popen(['godot','--audio-driver','Dummy','--path',str(root),'--position','0,0','--resolution','1280x800','-s','res://tools/marble_native_observer.gd','--',str(out)],env=env,stdout=log,stderr=subprocess.STDOUT)
 def read():
  try:
   s=json.loads((out/'latest.json').read_text());return s if time.time()-s['unix_seconds']<3 else None
  except (OSError,ValueError):return None
 def wait(fn,timeout=15):
  until=time.monotonic()+timeout
  while time.monotonic()<until:
   s=read()
   if s and fn(s):return s
   if game.poll() is not None:raise RuntimeError('Candidate exited; see game.log')
   time.sleep(.03)
  raise RuntimeError('Native observation timed out: '+repr(read()))
 def key(name,down):
  code=x.XKeysymToKeycode(d,x.XStringToKeysym(name.encode()))
  if not code:raise RuntimeError(name)
  xt.XTestFakeKeyEvent(d,code,int(down),0);x.XFlush(d);events.append({'time':time.time(),'key':name,'down':down});time.sleep(.06)
 def tap(name):key(name,True);key(name,False)
 def click(rect):
  s=read();px,py=s['window_position'];rx,ry,rw,rh=rect
  xt.XTestFakeMotionEvent(d,-1,round(px+rx+rw/2),round(py+ry+rh/2),0);x.XFlush(d);time.sleep(.06)
  xt.XTestFakeButtonEvent(d,1,1,0);x.XFlush(d);time.sleep(.06)
  xt.XTestFakeButtonEvent(d,1,0,0);x.XFlush(d);events.append({'time':time.time(),'click':rect});time.sleep(.15)
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label,'state':read()})
  if not ok:raise AssertionError(label)
 def visible_button(key_value):
  s=read();matches=[b for b in s['buttons'] if b['key']==key_value]
  if len(matches)!=1:raise RuntimeError('Expected native button '+key_value+' got '+repr(s['buttons']))
  return matches[0]['rect']
 def open_marble():
  tap('e');return wait(lambda s:s['open'])
 try:
  s=wait(lambda s:bool(s['buttons']));win=s['native_handle'];x.XSetInputFocus(d,win,2,0);x.XFlush(d);wait(lambda s:s['focused']);time.sleep(.4)
  original=read()['ledger'];check(not read()['open'] and not read()['hint'].endswith('查看黑色弹珠'),'fresh shop has no forced inspection or remote prompt')
  # Reach the authored object by genuine keyboard movement, not root placement.
  key('d',True);wait(lambda s:'弹珠' in s['hint'] and s['hint_visible'],timeout=8);key('d',False);time.sleep(.35)
  check('弹珠' in read()['hint'],'native walking reaches nearby-only optional prompt')
  s=open_marble();position=s['position'];rig=s['rig'];key('d',True);time.sleep(.45)
  check(read()['rig']==rig and read()['position']==position and read()['pose'] not in ['align','ready','farewell'],'native inspection freezes exact empty-hand rig and root')
  tap('Escape');wait(lambda s:not s['open']);time.sleep(.35)
  check(read()['position']==position and read()['page']=='hub','native close consumes Escape and quarantines held movement');key('d',False)
  for size in [(1280,800),(1920,1080),(3840,2160)]:
   x.XResizeWindow(d,win,*size);x.XFlush(d);events.append({'time':time.time(),'resize':size});wait(lambda s:s['size']==list(size));time.sleep(.4)
   check('弹珠' in read()['hint'],'actual nearby prompt at '+str(size))
   s=open_marble();time.sleep(.45);s=read();r=s['panel_rect']
   check(r[0]>=0 and r[1]>=0 and r[0]+r[2]<=size[0] and r[1]+r[3]<=size[1] and s['body_lines']<=3,'actual native panel and exact text fit '+str(size))
   check(s['inspection_owner']!=0 and s['phone_owner']==0,'exclusive inspection owner at '+str(size))
   click(s['close_rect']);wait(lambda s:not s['open']);time.sleep(.4)
   check(read()['position']==position and read()['page']=='hub','actual native Close returns to same place at '+str(size))
  # Native phone blocks examination, then ordinary explicit close restores it.
  click(visible_button('action:customer_reviews:null'));wait(lambda s:s['phone']);tap('e');time.sleep(.25)
  check(read()['phone'] and not read()['open'],'native E cannot open investigation through phone')
  tap('Escape');wait(lambda s:not s['phone']);open_marble();key('d',True)
  x.XSetInputFocus(d,x.XDefaultRootWindow(d),2,0);x.XFlush(d);wait(lambda s:not s['focused'])
  check(not read()['open'] and read()['inspection_owner']==0,'OS focus loss closes inspection and releases owner')
  x.XSetInputFocus(d,win,2,0);x.XFlush(d);wait(lambda s:s['focused']);time.sleep(.4)
  check(read()['position']==position and not read()['open'],'OS focus return cannot restore held movement or panel');key('d',False)
  open_marble();key('d',True);x.XResizeWindow(d,win,1280,800);x.XFlush(d);wait(lambda s:s['size']==[1280,800]);time.sleep(.4)
  check(read()['open'] and read()['position']==position,'OS resize preserves inspection owner and root')
  tap('Escape');wait(lambda s:not s['open']);time.sleep(.3);check(read()['position']==position,'resize then close still quarantines old direction');key('d',False)
  # Open settings using its actual visible native HUD action.
  settings=[b for b in read()['buttons'] if 'setting' in b['key']]
  if len(settings)!=1:raise RuntimeError('Could not resolve native settings action: '+repr(read()['buttons']))
  click(settings[0]['rect']);wait(lambda s:s['context']=='modal');tap('e');time.sleep(.2)
  check(not read()['open'] and read()['context']=='modal','native settings context blocks nearby E')
  tap('Escape');wait(lambda s:s['context']!='modal');time.sleep(.25)
  check(read()['ledger']==original,'all native inspections preserve economy story design and review state')
  key('a',True);time.sleep(.5);key('a',False);time.sleep(.3)
  check(read()['position']!=position and '弹珠' not in read()['hint'],'fresh native movement resumes and leaving removes optional prompt')
 finally:
  for name in ['d','a','e','Escape','Return','Tab']:
   key(name,False)
  if game.poll() is None:game.terminate();game.wait(timeout=10)
  log.close();x.XCloseDisplay(d)
  report={'release_note':a.release_note,'candidate':str(root),'native_XTest':True,'physical_gamepad':False,'human_play':False,'engine_synthetic_events':False,'scripted_still':False,'source_unchanged':before==hashes(),'hashes':before,'checks':checks,'events':events}
  (out/'native-proof.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 print(json.dumps({'checks':len(checks),'out':str(out)}))
if __name__=='__main__':main()
