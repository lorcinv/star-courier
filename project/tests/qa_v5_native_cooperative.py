#!/usr/bin/env python3
"""Cooperative-cutscene native QA: fresh ordinary player, real XTest and PCM.

Requires the lead's explicit production freeze and exclusive GUI release.
Read-only phase observations synchronize native input; never call gameplay APIs.
No seeded save, injected engine input, manual physics stepping, or video speedup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

import qa_v5_native_grounded as grounded
import qa_v5_native_handoff as handoff
import qa_v5_native_extreme as native

ROOT=Path(__file__).resolve().parents[1]
BASE_OUT=ROOT/'docs/qa/v5/cooperative-native'
QA_ENTRY='res://tools/qa_cooperative_observer.gd'

def hashes():
    result=handoff.hashes()
    for name in ['tests/qa_v5_native_cooperative.py','tests/qa_v5_native_grounded.py',
                 'tests/qa_v5_native_extreme.py','tools/qa_cooperative_observer.gd']:
        result[name]=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
    return result

class NativeCooperative(grounded.NativeGrounded):
    def __init__(self,args):
        grounded.BASE_OUT=BASE_OUT;grounded.QA_ENTRY=QA_ENTRY;grounded.hashes=hashes
        os.environ.setdefault('SC_QA_RUN','v5-native-cooperative-'+str(time.time_ns()))
        os.environ.setdefault('SC_QA_DISPLAY','519')
        os.environ.setdefault('SC_QA_OUT',str(BASE_OUT/('run-'+str(time.time_ns()))))
        super().__init__(args)
        self.observations=[]
        self.cooperative_commands=[]
    def observe(self):
        data=json.loads((self.out/'cooperative-latest.json').read_text())
        if time.time()-data['unix_seconds']>3:
            raise RuntimeError('Read-only observer is stale')
        return data
    def execute(self,command):
        original=dict(command);command=dict(command)
        expected=command.pop('check_observed',None)
        wait=command.pop('wait_for',None)
        observed=None
        if wait:
            deadline=time.monotonic()+wait.get('timeout',40)
            while True:
                observed=self.observe();value=observed
                for key in wait['path']:value=value[key]
                if value==wait['equals']:break
                if time.monotonic()>=deadline:
                    raise AssertionError('Native observation wait timed out: '+repr(wait)+'; observed '+repr(value))
                time.sleep(.025)
        label=command.pop('observe',None)
        click_button=command.pop('click_button',None)
        if click_button:
            observed=self.observe()
            found=[b for b in observed['buttons'] if (b['name']==click_button or b['text']==click_button) and not b['disabled']]
            if len(found)!=1:raise AssertionError('Expected one visible matching button: '+repr(found))
            x,y,w,h=found[0]['rect'];command['click']=[x+w/2,y+h/2]
        result=super().execute(command)
        if label or wait or click_button or expected:
            observed=self.observe()
            result['observation']=observed
            self.observations.append({'label':label or str(wait or click_button),'unix_seconds':time.time(),'state':observed})
            native.dump(self.out/'cooperative-observations.json',self.observations)
        if expected:
            results=[]
            for spec in expected:
                value=observed
                for key in spec['path']:value=value[key]
                results.append({'test':spec['test'],'passed':value==spec['equals'],'observed':value})
            self.checks.extend(results);result['observed_checks']=results
        with (self.out/'cooperative-native-events.jsonl').open('a') as stream:
            stream.write(json.dumps({'unix_seconds':time.time(),'command':original,'result':result},ensure_ascii=False)+'\n')
        self.cooperative_commands.append(original)
        if any(not x['passed'] for x in result.get('observed_checks',[])):
            raise AssertionError('Native read-only observed assertion failed; see cooperative-native-events.jsonl')
        return result
    def close(self):
        super().close()
        native.dump(self.out/'cooperative-replay.json',self.cooperative_commands)
        for prefix in ['grounded','extreme','dialogue']:
            for suffix in ['source-metadata.json','validation-summary.json']:
                source=self.out/(prefix+'-'+suffix)
                if source.exists():source.replace(self.out/('cooperative-'+suffix))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready',action='store_true')
    parser.add_argument('--release-note',required=True)
    parser.add_argument('--replay',type=Path)
    args=parser.parse_args()
    if not args.ready:parser.error('Explicit frozen-production/exclusive-GUI release required')
    capture=NativeCooperative(args)
    try:
        print(json.dumps(capture.ready,ensure_ascii=False),flush=True)
        commands=json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for original in commands:
            try:result=capture.execute(original)
            except Exception as exc:
                result={'harness_error':repr(exc),'command':original}
                with (capture.out/'harness-errors.jsonl').open('a') as stream:stream.write(json.dumps(result,ensure_ascii=False)+'\n')
                print(json.dumps(result,ensure_ascii=False),flush=True);raise
            print(json.dumps(result,ensure_ascii=False),flush=True)
            if original.get('quit'):break
    finally:capture.close()

if __name__=='__main__':main()
