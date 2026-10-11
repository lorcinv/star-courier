#!/usr/bin/env python3
"""Prepared native XTest/whole-frame proof. DO NOT RUN before exclusive GPU approval.
Runs an isolated candidate and disposable QA save. Sixteen disclosed synthetic
formal outcomes are saved BEFORE the graphical game starts. Runtime gameplay is
controlled only by XTest; the Godot observer reads state and saves screenshots.
No physical-controller, human-play, naturally earned economy, or FPS claims.
"""
import argparse, ctypes as C, ctypes.util, hashlib, json, os
from pathlib import Path
import subprocess, time

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--approved',action='store_true');ap.add_argument('--release-note',required=True)
    ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--display',required=True)
    args=ap.parse_args()
    if not args.approved:ap.error('Exclusive graphical/GPU approval required')
    root=args.candidate.resolve();out=args.out.resolve()
    if out.exists():raise RuntimeError('Use a fresh output directory')
    out.mkdir(parents=True);env=dict(os.environ,DISPLAY=args.display)
    for kind in ['data','config','cache']:
        path=out/'runtime'/kind;path.mkdir(parents=True);env['XDG_'+kind.upper()+'_HOME']=str(path)
    names=['main','world_view_2d','courier_input','game_hud','workshop_input_2d','customer_review_phone','economy','customer_reviews',
           'clerk_single_walk_2d','clerk_rigid_motion_2d','clerk_rigid_pose_2d']
    paths=[root/'scripts'/f'{name}.gd' for name in names if (root/'scripts'/f'{name}.gd').is_file()]
    rig_manifest=root/'assets/2d_v5/actors/rig_motion_v1/rig-registration.json'
    if rig_manifest.is_file():
        paths.append(rig_manifest)
        paths.extend(root/record['path'] for record in json.loads(rig_manifest.read_text())['parts'].values())
    def source_hashes():
        return {str(path.relative_to(root)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    hashes=source_hashes()
    seed=subprocess.run(['godot','--headless','--path',str(root),'-s','res://tools/customer_review_phone_seed.gd'],env=env,text=True,capture_output=True,timeout=30)
    (out/'seed.log').write_text(seed.stdout+seed.stderr);seed.check_returncode()
    if 'SCRIPT ERROR' in seed.stdout+seed.stderr or 'ERROR:' in seed.stdout+seed.stderr:raise RuntimeError('Seed validation failed')
    x=C.CDLL(ctypes.util.find_library('X11'));xt=C.CDLL(ctypes.util.find_library('Xtst'))
    x.XOpenDisplay.argtypes=[C.c_char_p];x.XOpenDisplay.restype=C.c_void_p
    x.XStringToKeysym.argtypes=[C.c_char_p];x.XStringToKeysym.restype=C.c_ulong
    x.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];x.XKeysymToKeycode.restype=C.c_uint
    x.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
    x.XResizeWindow.argtypes=[C.c_void_p,C.c_ulong,C.c_uint,C.c_uint]
    x.XDefaultRootWindow.argtypes=[C.c_void_p];x.XDefaultRootWindow.restype=C.c_ulong
    x.XFlush.argtypes=[C.c_void_p];x.XCloseDisplay.argtypes=[C.c_void_p]
    xt.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
    xt.XTestFakeButtonEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
    xt.XTestFakeMotionEvent.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_ulong]
    d=x.XOpenDisplay(args.display.encode())
    if not d:raise RuntimeError('Approved display unavailable')
    log=(out/'game.log').open('w');events=[];checks=[]
    game=subprocess.Popen(['godot','--audio-driver','Dummy','--path',str(root),'--position','0,0','--resolution','1280x800','-s','res://tools/customer_review_phone_observer.gd','--',str(out)],env=env,stdout=log,stderr=subprocess.STDOUT)
    def read():
        try:
            value=json.loads((out/'latest.json').read_text())
            return value if time.time()-value['unix_seconds']<3 else None
        except (OSError,ValueError):return None
    def wait(test,timeout=12):
        until=time.monotonic()+timeout
        while time.monotonic()<until:
            s=read()
            if s and test(s):return s
            if game.poll() is not None:raise RuntimeError('Candidate exited; see game.log')
            time.sleep(.03)
        raise RuntimeError('Native observation timed out: '+repr(read()))
    def event(kind,data):events.append({'time':time.time(),'kind':kind,'data':data})
    def key(name,down):
        code=x.XKeysymToKeycode(d,x.XStringToKeysym(name.encode()))
        if not code:raise RuntimeError('Unknown native keysym '+name)
        xt.XTestFakeKeyEvent(d,code,int(down),0);x.XFlush(d);event('key',[name,down]);time.sleep(.06)
    def tap(name):key(name,True);key(name,False)
    def click(rect):
        s=read();px,py=s['window_position'];a,b,w,h=rect
        xt.XTestFakeMotionEvent(d,-1,round(px+a+w/2),round(py+b+h/2),0);x.XFlush(d);time.sleep(.06)
        xt.XTestFakeButtonEvent(d,1,1,0);x.XFlush(d);time.sleep(.06)
        xt.XTestFakeButtonEvent(d,1,0,0);x.XFlush(d);event('click',rect);time.sleep(.12)
    def open_phone():
        s=wait(lambda a:not a['phone']);controls=[b for b in s['buttons'] if b['key']=='action:customer_reviews:null']
        if len(controls)!=1:raise RuntimeError('Expected one visible explicit phone action')
        before=s;click(controls[0]['rect']);after=wait(lambda a:a['phone'])
        a=after['draw_registration'];b=before['draw_registration']
        check(after['position']==before['position'] and after['depth']==before['depth'] and a['draw_scale']==b['draw_scale'] and abs(a['body_height']-210.0)<.001 and a['head_registered'] and a['single_representation'] and a['facing_right']==b['facing_right']==a['rendered_facing_right'],'native entry preserves root, actual draw scale, registered head, depth, facing and single representation')
        return after
    def check(ok,label):
        checks.append({'label':label,'passed':bool(ok),'state':read()})
        if not ok:raise AssertionError(label)
    try:
        s=wait(lambda a:len(a['buttons'])>0);win=s['native_handle'];x.XSetInputFocus(d,win,2,0);x.XFlush(d)
        time.sleep(.5);s=read();base=(s['credits'],s['reputation'],s['reviews'])
        check(not s['phone'] and s['reviews']==16,'restored feed starts closed')
        s=open_phone();position=s['position'];scale=s['draw_registration']['draw_scale'];depth=s['depth'];key('d',True);tap('e');time.sleep(.5);s=read()
        check(s['phone'] and s['pose']=='align' and s['position']==position and s['draw_registration']['draw_scale']==scale and s['draw_registration']['head_registered'] and s['draw_registration']['single_representation'] and s['depth']==depth,'native held movement/interaction preserves tablet root and owner')
        tap('Escape');s=wait(lambda a:not a['phone']);time.sleep(.4);s=read()
        check(s['page']=='hub' and s['position']==position and s['pose']=='idle','native Escape closes only phone and quarantines held direction')
        a=s['draw_registration']
        check(a['draw_scale']==scale and abs(a['body_height']-210.0)<.001 and a['head_registered'] and a['single_representation'] and a['facing_right']==a['rendered_facing_right'] and s['depth']==depth,'native exit restores registered empty-hand scale, depth, facing and single representation')
        key('d',False);time.sleep(.15);key('d',True);time.sleep(.5);key('d',False);time.sleep(.4)
        check(read()['position']!=position,'fresh native movement resumes after release')
        key('d',True);time.sleep(2.2);key('d',False);time.sleep(.4)
        check(read()['position'][0]>600 and read()['position'][1]==496,'native movement exposes front-lane clerk for tablet entry/exit inspection')
        open_phone();tap('Down');tap('Next');time.sleep(.2);check(read()['scroll']>0,'native arrow/PageDown remain on phone and scroll feed')
        click(read()['close_rect']);wait(lambda a:not a['phone'])
        # Native Tab navigation finds the explicit action without any engine focus setter.
        for _ in range(18):
            if read()['focus_key']=='action:customer_reviews:null':break
            tap('Tab');time.sleep(.08)
        check(read()['focus_key']=='action:customer_reviews:null','native Tab reaches explicit phone action')
        tap('Return');wait(lambda a:a['phone']);tap('Escape');wait(lambda a:not a['phone'])
        open_phone();key('d',True);x.XSetInputFocus(d,x.XDefaultRootWindow(d),2,0);x.XFlush(d);event('focus','root')
        wait(lambda a:not a['focused']);check(not read()['phone'],'native focus loss closes phone')
        x.XSetInputFocus(d,win,2,0);x.XFlush(d);wait(lambda a:a['focused']);before=read()['position'];time.sleep(.4)
        check(read()['position']==before and not read()['phone'],'native focus return does not reopen or resume velocity');key('d',False)
        for size in [(1280,800),(1920,1080),(3840,2160)]:
            x.XResizeWindow(d,win,*size);x.XFlush(d);event('resize',size);wait(lambda a:a['size']==list(size));time.sleep(.5)
            s=open_phone();time.sleep(.7);s=read();r=s['phone_rect']
            check(r[0]>=0 and r[1]>=0 and r[0]+r[2]<=size[0] and r[1]+r[3]<=size[1],'native whole-frame phone fits '+str(size))
            tap('Escape');wait(lambda a:not a['phone']);time.sleep(.5)
        s=read();check((s['credits'],s['reputation'],s['reviews'])==base,'native phone interactions preserve published and financial state')
    finally:
        for name in ['d','e','Escape','Return','Tab','Down','Next']:
            key(name,False)
        if game.poll() is None:game.terminate();game.wait(timeout=10)
        log.close();x.XCloseDisplay(d)
        after=source_hashes()
        report={'release_note':args.release_note,'candidate':str(root),'native_XTest':True,'physical_controller':False,'human_play':False,'synthetic_offline_delivery_outcomes':True,'source_unchanged':hashes==after,'hashes':hashes,'checks':checks,'events':events}
        (out/'native-proof.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({'checks':len(checks),'out':str(out)}))
if __name__=='__main__':main()
