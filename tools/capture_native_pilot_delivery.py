#!/usr/bin/env python3
"""Reproducible automated native OS-input capture, not human play or FPS proof.

Requires Godot 4.6.3, Xorg's dummy driver, libX11, libXtst, xwininfo, ImageMagick,
and ffmpeg. Optional SC_QA_USE_WM=1 uses xfwm4 and actual Alt+F4 to close.
Run with a unique SC_QA_RUN (a fresh game save) and unused SC_QA_DISPLAY.
JSON commands pass through to qa_native_regression.py. A delivery command builds
its offline reference from the supplied route/weight/seed or read-only game save;
no ignored reference or runtime config is required. The live game sees only real
XTest keyboard/pointer input, with normal wall time, never live gameplay APIs,
fixed FPS, or save mutation. The offline reference never touches the live process.
"""
import ctypes as C
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]

class NativePilotCapture:
    def __init__(self):
        self.out=ROOT/os.environ.get('SC_QA_OUT','docs/qa/v5/pilot-native-delivery')
        self.out.mkdir(parents=True,exist_ok=True)
        self.env=dict(os.environ,SC_QA_DISPLAY=os.environ.get('SC_QA_DISPLAY','370'),
            SC_QA_RUN=os.environ.get('SC_QA_RUN','pilot-native-delivery-'+str(time.time_ns())),
            SC_QA_OUT=str(self.out),SC_QA_XORG_CONFIG=os.environ.get('SC_QA_XORG_CONFIG',str(ROOT/'tools/xorg_native_1920.conf')),
            SC_QA_RESOLUTION=os.environ.get('SC_QA_RESOLUTION','1280x800'),SC_QA_START_WAIT='5')
        self.child=subprocess.Popen([sys.executable,str(ROOT/'tools/qa_native_regression.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1,env=self.env)
        self.display=None;self.held=set()
        self.x11=C.CDLL('libX11.so.6');self.xtst=C.CDLL('libXtst.so.6')
        self.x11.XOpenDisplay.argtypes=[C.c_char_p];self.x11.XOpenDisplay.restype=C.c_void_p
        self.x11.XStringToKeysym.argtypes=[C.c_char_p];self.x11.XStringToKeysym.restype=C.c_ulong
        self.x11.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];self.x11.XKeysymToKeycode.restype=C.c_uint
        self.x11.XFlush.argtypes=[C.c_void_p];self.x11.XCloseDisplay.argtypes=[C.c_void_p]
        self.xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
        self.ready=self.receive()
        self.display=self.x11.XOpenDisplay(('localhost:'+self.env['SC_QA_DISPLAY']).encode())
        if not self.display:raise RuntimeError('Isolated native X display unavailable')

    def receive(self):
        line=self.child.stdout.readline()
        if not line:raise RuntimeError('Native driver exited before replying')
        result=json.loads(line)
        if 'error' in result:raise RuntimeError(result['error'])
        return result

    def send(self,command):
        # Keep Xorg alive until this wrapper releases its own X11 connection.
        # EOF in close() terminates the child after that, avoiding an XIO race.
        forwarded=dict(command);forwarded.pop('quit',None)
        self.child.stdin.write(json.dumps(forwarded)+'\n');self.child.stdin.flush();return self.receive()

    def set_keys(self,wanted):
        for name in sorted(self.held-wanted):self._key(name,False)
        for name in sorted(wanted-self.held):self._key(name,True)
        self.x11.XFlush(self.display);self.held=set(wanted)

    def _key(self,name,down):
        code=self.x11.XKeysymToKeycode(self.display,self.x11.XStringToKeysym(name.encode()))
        if not code:raise ValueError('Unknown keysym '+name)
        self.xtst.XTestFakeKeyEvent(self.display,code,int(down),0)

    def reference(self,spec,name):
        spec_path=self.out/(name+'-reference-spec.json')
        spec_path.write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n')
        runtime=self.out/'reference-runtime'
        for directory in ['home','data','config','cache']:(runtime/directory).mkdir(parents=True,exist_ok=True)
        env=dict(os.environ,HOME=str(runtime/'home'),XDG_DATA_HOME=str(runtime/'data'),XDG_CONFIG_HOME=str(runtime/'config'),XDG_CACHE_HOME=str(runtime/'cache'))
        completed=subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://tools/pilot_keyboard_reference.gd','--','--spec',str(spec_path)],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=40)
        (self.out/(name+'-reference.log')).write_text(completed.stdout)
        completed.check_returncode()
        result=json.loads(next(line.split('REFERENCE_JSON:',1)[1] for line in completed.stdout.splitlines() if line.startswith('REFERENCE_JSON:')))
        if result['status']!='success':raise RuntimeError('Offline reference did not clear')
        return result

    def deliver(self,spec):
        name=spec.get('name','native-delivery')
        reference_spec=dict(spec.get('reference',{}))
        if not reference_spec:
            state=self.send({'state':True,'sleep':0})['state']
            order=next(order for order in state['contracts'] if order['contract_id']==state['active_contract_id'])
            route=dict(order,battery_capacity_multiplier=1+.15*state['research'])
            reference_spec={'route':route,'design':state['design'],'launcher':state['launcher'],'seed':state['day']*100+int(order['id'])*3+int(order['contract_id'].endswith('B'))}
        reference=self.reference(reference_spec,name)
        if spec.get('record',True):self.send({'record':{'name':name,'seconds':spec.get('seconds',reference['elapsed']+6)},'sleep':.25})
        if 'resume' in spec:
            self.send({'key':spec['resume'],'sleep':0})
            countdown=0.0;offset=float(reference_spec['snapshot']['ticks'])/60.0
        else:
            self.send({'click':spec.get('launch',[790,619]),'sleep':0})
            countdown=float(spec.get('countdown',.7));offset=0.0
            if spec.get('repeat_launch'):
                repeat_start=time.monotonic()
                self.send({'click':spec.get('launch',[790,619]),'sleep':0})
                countdown=max(0.0,countdown-(time.monotonic()-repeat_start))
        start=time.monotonic();trace=[]
        stop_at=spec.get('stop_at')
        for index,item in enumerate(reference['commands']):
            if stop_at is not None and float(item['time'])>=float(stop_at):break
            target=float(item['time'])-offset+countdown
            if index==0:target=0.0
            time.sleep(max(0,start+target-time.monotonic()))
            wanted=set()
            if item['axis']<0:wanted.add('w')
            if item['axis']>0:wanted.add('s')
            if item['boost']:wanted.add('Shift_L')
            if item.get('active'):wanted.add('space')
            self.set_keys(wanted)
            trace.append({'wall_seconds':time.monotonic()-start,'planned_sim_seconds':item['time'],'held_os_keys':sorted(wanted),'reference_x':item['x'],'reference_y':item['y']})
        if stop_at is not None:
            time.sleep(max(0,start+float(stop_at)-offset+countdown-time.monotonic()))
            result=self.send({'key':'p','sleep':.15,'shot':name+'-paused','state':True})
            self.set_keys(set())
        else:
            # Hold the last command; wait for an autosave containing it. This is
            # read-only evidence for exact offline replay and energy-bill audit.
            time.sleep(1.35)
            checkpoint=self.send({'snapshot':name+'-last-input','state':True,'sleep':0})
            if not checkpoint['state'].get('in_flight'):raise RuntimeError('No final-input checkpoint before settlement')
            time.sleep(max(0,start+float(spec.get('wait_until',reference['elapsed']+2.5))-offset-time.monotonic()))
            self.set_keys(set())
            result=self.send({'shot':name+'-receipt','snapshot':name+'-receipt','state':True,'sleep':0})
            result['last_input_checkpoint']=checkpoint['save_snapshot']
        (self.out/(name+'-os-input-trace.json')).write_text(json.dumps(trace,ensure_ascii=False,indent=2)+'\n')
        result['automated_native_input']=True;result['engine_fps_claim']=False
        return result

    def close(self):
        if self.display:self.set_keys(set());self.x11.XCloseDisplay(self.display);self.display=None
        if self.child.stdin:self.child.stdin.close()
        try:self.child.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.child.terminate()
            try:self.child.wait(timeout=5)
            except subprocess.TimeoutExpired:self.child.kill();self.child.wait(timeout=5)

if __name__=='__main__':
    capture=NativePilotCapture()
    try:
        print(json.dumps(capture.ready,ensure_ascii=False),flush=True)
        for line in sys.stdin:
            command=json.loads(line)
            if 'delivery' in command:result=capture.deliver(command['delivery'])
            elif 'reference' in command:result=capture.reference(command['reference'],command.get('name','offline'))
            else:
                wanted=capture.held-set(command.pop('release',[]))|set(command.pop('hold',[]))
                capture.set_keys(wanted);result=capture.send(command)
            print(json.dumps(result,ensure_ascii=False),flush=True)
            if command.get('quit'):break
    finally:capture.close()
