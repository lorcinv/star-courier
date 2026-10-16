#!/usr/bin/env python3
"""Cloud XTest continuation of the immutable, naturally earned Day3-night save.

Only the exact verified save bytes are copied before startup. Day4 offers,
acceptance, loading, trial, formal dispatch, pause/restart and receipt use actual
OS input. No new money, reputation, parts, accepted order or input is authored.
An explicitly read-only observer suggests W/S; this is automated QA, not human
playability or physical-controller testing. Native capture requires --ready.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import time

import qa_v5_native_extreme as native
import qa_v5_native_handoff as handoff
from qa_v5_native_three_day import ThreeDay, persistence

ROOT=Path(__file__).resolve().parents[1]
BASE_OUT=ROOT/'docs/qa/v5/moon-native'
SOURCE=ROOT/'docs/qa/v5/three-day-native/natural-run-01/day-3-night-purchases-save.json'
SOURCE_SHA='3ca6146396dda2eb56f0f6bc97157c3bb750cb0062e35f6cdb606cd267740fe3'
QA_ENTRY='res://tools/qa_moon_observer.gd'
QA_FILES=['tests/qa_v5_native_moon.py','tools/qa_moon_observer.gd',
 'tools/moon_offline_guide.gd','tests/qa_v5_native_three_day.py',
 'tests/test_three_day_progression.gd','tests/qa_v5_native_extreme.py',
 'tests/qa_v5_native_ground_day.py','tests/qa_v5_native_grounded.py']

def dump(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def hashes():
    result=handoff.hashes()
    for name in QA_FILES:result[name]=digest(ROOT/name)
    return result

def copy_earned_save(out,runtime,_fixture):
    if runtime.exists():raise RuntimeError('Refusing to overwrite an existing runtime')
    if digest(SOURCE)!=SOURCE_SHA:raise RuntimeError('Earned source checkpoint changed')
    original=json.loads(SOURCE.read_text())
    assert original['day']==3 and original['phase']=='night' and original['reputation']==12
    assert original['credits']==1143 and original['deliveries']==6 and len(original['settled_ids'])==6
    assert not original['active_contract_id'] and not original['in_flight']
    assert all(c['status']=='settled' for c in original['contracts'])
    for name in ['home','data','config','cache']:(runtime/name).mkdir(parents=True)
    # project.godot uses the ordinary Linux Godot user directory and this exact
    # application name. Byte copy only; no parsed field is written back.
    save=runtime/'data/godot/app_userdata/星际快递/savegame.json'
    save.parent.mkdir(parents=True);save.write_bytes(SOURCE.read_bytes())
    (out/'before-native-earned-save.json').write_bytes(SOURCE.read_bytes())
    assert digest(save)==SOURCE_SHA
    info={'fixture':'Unmodified earned Day3-night checkpoint continuation',
      'source':str(SOURCE.relative_to(ROOT)),'source_sha256':SOURCE_SHA,
      'save':str(save),'copied_before_native_unix':time.time(),
      'preseeded':True,'earned_snapshot_continuation':True,'qa_endowment':0,
      'authored_state_fields':[],'live_state_mutation':False,
      'prior_natural_gate':'docs/qa/v5/three-day-native/natural-run-01/three-day-validation-summary.json'}
    dump(out/'fixture.json',info);return info

class MoonCapture(ThreeDay):
    def __init__(self,args):
        native.BASE_OUT=BASE_OUT;native.QA_ENTRY=QA_ENTRY
        native.hashes=hashes;native.seed_fixture=copy_earned_save
        args.fixture='earned-moon-continuation'
        self.status='running';self.results={};self.current_pid=None
        self.started_at=time.monotonic()
        native.NativeExtreme.__init__(self,args)
        self.current_pid=self.ready['pid']
        self.x11.XDefaultRootWindow.argtypes=[C.c_void_p];self.x11.XDefaultRootWindow.restype=C.c_ulong
        self.x11.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
        self.focus_events=[]
        dump(self.out/'source-hashes-before.json',self.started_hashes)
        snapshots=self.out/'qa-source-snapshot';snapshots.mkdir()
        for name in QA_FILES:(snapshots/Path(name).name).write_bytes((ROOT/name).read_bytes())

    def _metadata(self):
        native.NativeExtreme._metadata(self)
        for name in ['extreme-source-metadata.json','extreme-validation-summary.json']:
            p=self.out/name
            if p.exists():
                value=json.loads(p.read_text());value.update(
                  method='Actual XTest continuation of an unmodified earned Day3-night checkpoint',
                  qa_endowment=0,preseeded=True,earned_snapshot_continuation=True,
                  save_mutation='Exact archived save bytes copied before startup; no live edits',
                  authored_state_fields=[])
                dump(p,value)

    def check(self,name,condition,detail=None):
        row={'test':name,'passed':bool(condition),'detail':detail};self.checks.append(row)
        dump(self.out/'moon-checks.json',self.checks);print(json.dumps(row,ensure_ascii=False),flush=True)
        if not condition:raise AssertionError(name)

    def observe(self):
        d=json.loads((self.out/'moon-latest.json').read_text())
        if d['run_id']!=os.environ['SC_QA_RUN']:raise RuntimeError('Wrong observer run')
        if self.current_pid is not None and d['observer_pid']!=self.current_pid:raise RuntimeError('Wrong observer process')
        if time.time()-d['unix_seconds']>3:raise RuntimeError('Read-only observer is stale')
        return d

    def drive_moon(self,label,stop_x=None,capture=False):
        began=time.monotonic();next_tick=-1;last_tick=-1;trace=[];shots=set();capturing=False
        start_x=self.observe().get('position',[0,0])[0]
        while time.monotonic()-began<150:
            o=self.observe();tick=o['completed_ticks'];pos=o.get('position',[0,0]);x=pos[0]
            if o['page']!='flight':raise AssertionError('Unexpected page during '+label+': '+o['page'])
            if tick<last_tick:raise AssertionError('Native ticks moved backwards')
            last_tick=tick
            if o.get('sim_status')!='running':
                self.set_keys(set());dump(self.out/(label+'-terminal-observation.json'),o)
                if capturing:self.execute({'capture_stop':True,'sleep':0})
                self.screenshot(label+'-receiver')
                self.check(label+' reaches the actual Moon receiver',o['sim_status']=='success',
                  {'elapsed':o['sim_elapsed'],'position':pos,'integrity':o['telemetry']['integrity']})
                break
            if stop_x is not None and x>=stop_x:
                self.execute({'key':'p','sleep':.1});self.set_keys(set())
                o=self.wait(lambda d:d['paused'],'actual P pause')
                dump(self.out/(label+'-paused-observation.json'),o);break
            if capture and x>=535 and not capturing:
                self.execute({'capture_start':'earned-moon-trial','sleep':0});capturing=True
            if tick>=next_tick and not o['paused']:
                axis=int(o.get('guidance_axis_q',0));self.set_keys({'w'} if axis<0 else ({'s'} if axis>0 else set()))
                trace.append({'tick':tick,'unix_seconds':time.time(),'axis_q':axis,'position':pos});next_tick=tick+12
            for threshold,name in [(180,'city-ascent'),(575,'moon-transition'),(635,'north-crag'),(735,'south-crag'),(825,'airlock-approach')]:
                if threshold<start_x-10:shots.add(name)
                if x>=threshold and name not in shots:self.screenshot(label+'-'+name);shots.add(name)
            time.sleep(.008)
        else:raise AssertionError('Moon route exceeded 150 real seconds')
        dump(self.out/(label+'-os-guidance.json'),trace);return o

    def pause_restart(self,label,at_x):
        paused=self.drive_moon(label,stop_x=at_x);ticks=paused['completed_ticks']
        self.execute({'focus':'root','sleep':.3});self.set_keys(set());time.sleep(.3)
        self.check(label+' focus loss preserves paused ticks and clears held controls',
          self.observe()['completed_ticks']==ticks and self.observe()['paused'] and not self.held)
        self.execute({'focus':'game','sleep':.1})
        restored=self.restart(label,flight=True)
        self.check(label+' exact saved Moon route and authoritative checkpoint restore',
          restored['completed_ticks']==ticks and restored['position']==paused['position']
          and restored['telemetry']['energy_used']==paused['telemetry']['energy_used']
          and restored['flight_snapshot']['route']==paused['flight_snapshot']['route']
          and restored['timeline']==paused['timeline'],
          {'ticks':ticks,'position':restored['position'],'energy_used':restored['telemetry']['energy_used']})
        self.check(label+' restore skips ignition and preserves the Moon presentation route',
          restored['launch_phase'] not in ['move','charge','ignition','release']
          and restored['flight_order'].get('route_profile')=='moon-surface-v1')
        self.execute({'key':'p','sleep':.01})

    def run(self):
        original=json.loads(SOURCE.read_text());first=self.state()
        self.check('Exact earned checkpoint retains six receipts, inventory, design and balance',
          all(first[k]==original[k] for k in ['credits','day','phase','reputation','deliveries','settled_ids','inventory','design','launcher','workshop_tier']))
        self.clear_dialogues('earned-night-return')
        if self.observe()['page']!='hub':self.click_view('action:close_drawer:null',text='‹  返回店铺')
        self.click_hub(2,.1);self.wait(lambda o:o['page']=='supply','earned night supply')
        before=self.state();self.screenshot('01-earned-night');self.click_view('action:next_day:null')
        morning=self.state();offers={o['contract_id']:o for o in morning['contracts']}
        self.check('Real next-day action authors first Moon offer using earned reputation',
          morning['day']==4 and morning['reputation']==12 and morning['credits']==before['credits']
          and offers['D4-B'].get('route_profile')=='moon-surface-v1'
          and offers['D4-B']['weight']==4.34 and offers['D4-B']['reward']==465
          and morning['settled_ids']==before['settled_ids'],
          {'offers':[{k:o.get(k) for k in ['contract_id','route_profile','weight','reward']} for o in morning['contracts']]})
        accepted=self.accept('D4-B',natural_loading=True)
        self.check('Moon still uses the original single-cell eight-part ship and real pad',
          accepted['design']==original['design'] and accepted['launcher']==original['launcher']
          and len(accepted['design'])==8 and sum(p['type']=='battery' for p in accepted['design'])==1)
        self.click_view('action:trial:null',.05)
        self.wait(lambda o:o['page']=='flight' and o['trial'],'Moon free trial')
        terminal=self.drive_moon('trial',capture=True)
        self.wait(lambda o:o['page']=='report','Moon trial report')
        trial_state=self.state();replay=self.reference({'snapshot':terminal['flight_snapshot'],'mode':'replay'},'moon-trial-exact-input')
        self.check('Actual trial input replays exactly on its saved Moon route',
          replay['status']==terminal['sim_status'] and replay['position']==terminal['position']
          and replay['elapsed']==terminal['sim_elapsed'] and replay['energy_used']==terminal['telemetry']['energy_used'])
        self.check('Successful Moon trial does not settle, charge, change reputation or consume stock',
          native.ledger(trial_state)==native.ledger(accepted))
        self.screenshot('02-trial-report')
        self.formal_review('D4-B',test_cancel=True)
        self.pause_restart('moon-ascent-restart',210)
        self.pause_restart('moon-approach-restart',730)
        terminal=self.drive_moon('formal-after-two-restarts')
        self.audit('D4-B',terminal,trial_state)
        self.finish_dialogue('moon-result');final=self.state()
        self.check('Moon result story retains the actual Moon destination and original robot identity',
          final['story_state']['committed_contract_ids']['D4-B']['route_context']['destination_name']=='月面收件舱'
          and final['story_state']['contract_bindings']['D4-B']['appearance_id']=='robot_machinist')
        self.restart('moon-paid-receipt',final)
        saved=self.state()
        self.check('Moon receipt remains unique across final process restart',
          saved['settled_ids']==final['settled_ids'] and saved['credits']==final['credits']
          and len(saved['settled_ids'])==7 and saved['reputation']==14)
        self.check('Original earned archive and all frozen source/art remain unchanged',
          digest(SOURCE)==SOURCE_SHA and hashes()==self.started_hashes)
        dump(self.out/'final-moon-ledger.json',saved)
        self.results['trial']={'elapsed':replay['elapsed'],'remaining_energy':replay['remaining_energy'],'exact_replay':True}
        self.results['final']={k:saved[k] for k in ['credits','day','reputation','deliveries','settled_ids']}
        self.status='earned_moon_native_pass';self.execute({'close':True,'sleep':0})

    def close(self):
        native.NativeExtreme.close(self)
        after=hashes();dump(self.out/'source-hashes-after.json',after)
        dump(self.out/'moon-validation-summary.json',{'status':self.status,'checks':self.checks,
          'results':self.results,'captures':self.captures,'telemetry_sessions':self.telemetry_sessions,
          'source_unchanged':after==self.started_hashes,'release_note':self.release_note,
          'wall_seconds':time.monotonic()-self.started_at,'earned_snapshot_continuation':True,
          'source_checkpoint_sha256':SOURCE_SHA,'qa_endowment':0,'authored_state_fields':[],
          'live_state_mutation':False,'time_scale':1,'human_fairness_claim':False,
          'physical_pad_claim':False,'subjective_audio_claim':False,'native_windows_claim':False})

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ready',action='store_true');p.add_argument('--release-note',required=True)
    p.add_argument('--out',required=True);p.add_argument('--display',type=int,default=660)
    args=p.parse_args();out=Path(args.out).resolve()
    if not args.ready:p.error('Frozen source and exclusive native slot release required')
    if not out.is_relative_to(BASE_OUT.resolve()) or out.exists():p.error('Use a fresh Moon evidence directory')
    if args.display<660:p.error('Use a fresh display >=660')
    os.environ.update(SC_QA_RUN='earned-moon-'+str(time.time_ns()),SC_QA_OUT=str(out),
      SC_QA_DISPLAY=str(args.display),SC_QA_RESOLUTION='1920x1080',
      SC_QA_XORG_CONFIG=str(ROOT/'tools/xorg_native_1920.conf'),SC_QA_START_WAIT='5')
    capture=MoonCapture(args)
    try:capture.run()
    except Exception as exc:
        capture.status='failed';dump(capture.out/'moon-error.json',{'error':repr(exc)})
        try:capture.execute({'shot':'failure-screen','snapshot':'failure-save','sleep':0})
        except Exception:pass
        raise
    finally:capture.close()

if __name__=='__main__':main()
