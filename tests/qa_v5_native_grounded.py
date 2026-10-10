#!/usr/bin/env python3
"""Fresh ordinary-starter native QA for continuous grounded departure.
Requires an explicit frozen-production/exclusive-GUI release. Actual XTest input,
normal wall time, actual Master PCM, bounded read-only observer, unedited saves.
No endowed fixtures, live controller calls, fixed-FPS execution, or speedup.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import qa_v5_native_extreme as native
import qa_v5_native_handoff as handoff

ROOT=Path(__file__).resolve().parents[1]
BASE_OUT=ROOT/'docs/qa/v5/grounded-native'
QA_ENTRY='res://tools/qa_native_observer.gd'

def hashes():
    result=handoff.hashes()
    for name in ['tests/qa_v5_native_grounded.py','tests/qa_v5_native_extreme.py',
                 'tools/qa_native_observer.gd']:
        result[name]=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
    return result

class NativeGrounded(native.NativeExtreme):
    def __init__(self,args):
        native.BASE_OUT=BASE_OUT; native.QA_ENTRY=QA_ENTRY; native.hashes=hashes
        os.environ.setdefault('SC_QA_RUN','v5-native-grounded-'+str(time.time_ns()))
        os.environ.setdefault('SC_QA_DISPLAY','471')
        os.environ.setdefault('SC_QA_OUT',str(BASE_OUT/('run-'+str(time.time_ns()))))
        args.fixture='starter-route'
        super().__init__(args)
        self.x11.XDefaultRootWindow.argtypes=[C.c_void_p]
        self.x11.XDefaultRootWindow.restype=C.c_ulong
        self.x11.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
        self.focus_events=[];self.authoritative_commands=[]
        self._fresh_metadata()
    def _fresh_metadata(self):
        path=self.out/'extreme-source-metadata.json'
        if path.exists():
            data=json.loads(path.read_text())
            data.update({'method':'Fresh ordinary production starter; actual unchanged main scene; native XTest; actual Master PCM',
                'qa_endowment':0,'preseeded':False,'save_mutation':'No QA save authoring; only game-written saves read',
                'claims_excluded':['human play','native Windows performance','runtime state or velocity injection']})
            native.dump(path,data)
    def focus(self,target):
        if target=='root':window=self.x11.XDefaultRootWindow(self.display)
        elif target=='game':
            tree=subprocess.check_output(['xwininfo','-root','-tree'],env=dict(os.environ,DISPLAY='localhost:'+self.env['SC_QA_DISPLAY']),text=True)
            match=re.search(r'(0x[0-9a-f]+) "星际快递[^\"]*"',tree)
            if not match:raise RuntimeError('Cannot find existing game window')
            window=int(match.group(1),16)
        else:raise ValueError('Focus target must be root or game')
        self.x11.XSetInputFocus(self.display,window,1,0);self.x11.XFlush(self.display)
        event={'unix_seconds':time.time(),'target':target,'window':window}
        self.focus_events.append(event);native.dump(self.out/'native-focus-events.json',self.focus_events)
    def execute(self,command):
        original=dict(command)
        command=dict(command)
        target=command.pop('focus',None)
        if target:self.focus(target)
        result=super().execute(command)
        if target:result['native_focus']=target
        self.authoritative_commands.append(original)
        with (self.out/'grounded-authoritative-events.jsonl').open('a') as stream:
            stream.write(json.dumps({'unix_seconds':time.time(),'command':original,'result':result},ensure_ascii=False)+'\n')
        return result
    def close(self):
        super().close()
        self._fresh_metadata()
        native.dump(self.out/'native-replay.json',self.authoritative_commands)
        for suffix in ['source-metadata.json','validation-summary.json','command-events.jsonl']:
            src=self.out/('extreme-'+suffix)
            if src.exists():src.replace(self.out/('grounded-'+suffix))
        path=self.out/'grounded-validation-summary.json'
        data=json.loads(path.read_text())
        data.update({'method':'Fresh ordinary production starter; native XTest; real Master audio; read-only observer and runtime saves',
            'qa_endowment':0,'preseeded':False,'native_focus_events':self.focus_events})
        native.dump(path,data)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready',action='store_true')
    parser.add_argument('--release-note',required=True)
    parser.add_argument('--replay',type=Path)
    args=parser.parse_args()
    if not args.ready:parser.error('Explicit production freeze and exclusive GUI release required')
    capture=NativeGrounded(args)
    try:
        print(json.dumps(capture.ready,ensure_ascii=False),flush=True)
        commands=json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for original in commands:
            try:
                result=capture.execute(original)
            except Exception as exc:
                result={'harness_error':repr(exc),'command':original}
                with (capture.out/'harness-errors.jsonl').open('a') as stream:stream.write(json.dumps(result,ensure_ascii=False)+'\n')
                print(json.dumps(result,ensure_ascii=False),flush=True);raise
            print(json.dumps(result,ensure_ascii=False),flush=True)
            if original.get('quit'):break
    finally:capture.close()

if __name__=='__main__':main()
