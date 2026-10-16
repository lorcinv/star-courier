#!/usr/bin/env python3
"""Fresh natural three-business-day cloud XTest gate, normal wall time.

No fixture, save editing, injected progress/cargo/inventory, live gameplay calls,
fixed FPS, or time scaling. A read-only process-tagged observer suggests W/S.
An independent offline copy replays the exact actual input to audit each bill.
This is automated keyboard QA, never a human-fairness or physical-pad test.
"""
import argparse
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import time

import qa_v5_native_extreme as native
import qa_v5_native_grounded as grounded
import qa_v5_native_ground_day as ground
import qa_v5_native_handoff as handoff

ROOT=Path(__file__).resolve().parents[1]
BASE_OUT=ROOT/'docs/qa/v5/three-day-native'
QA_FILES=['tests/qa_v5_native_three_day.py','tools/qa_three_day_observer.gd',
          'tests/test_three_day_progression.gd','tools/pilot_wormhole_guidance.gd',
          'tests/qa_v5_native_extreme.py','tests/qa_v5_native_ground_day.py','tests/qa_v5_native_grounded.py']

def dump(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def hashes():
    result=handoff.hashes()
    for name in QA_FILES:result[name]=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
    return result

def persistence(state):
    return {key:state.get(key) for key in handoff.LEDGER_KEYS+['day','phase','reputation','workshop_tier',
        'designs','contracts','active_contract_id','in_flight','story_state','settings']}

class ThreeDay(native.NativeExtreme):
    click_hub=ground.GroundDay.click_hub
    finish_dialogue=ground.GroundDay.finish_dialogue
    screenshot=ground.GroundDay.screenshot
    reference_spec=ground.GroundDay.reference_spec
    archive_telemetry=ground.GroundDay.archive_telemetry
    focus=grounded.NativeGrounded.focus

    def __init__(self,args):
        native.BASE_OUT=BASE_OUT;native.QA_ENTRY='res://tools/qa_three_day_observer.gd';native.hashes=hashes
        args.fixture='starter-route'
        self.status='running';self.results={};self.current_pid=None;self.last_pid=None;self.started_at=time.monotonic()
        super().__init__(args)
        self.current_pid=self.ready['pid']
        self.x11.XDefaultRootWindow.argtypes=[C.c_void_p];self.x11.XDefaultRootWindow.restype=C.c_ulong
        self.x11.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
        self.focus_events=[]
        dump(self.out/'source-hashes-before.json',self.started_hashes)
        (self.out/'qa-source-snapshot').mkdir()
        for name in QA_FILES:(self.out/'qa-source-snapshot'/Path(name).name).write_bytes((ROOT/name).read_bytes())
        dump(self.out/'natural-start-provenance.json',{'fresh_production_game':True,'save_preseeded':False,
            'starting_save_existed':False,'runtime':os.environ['SC_QA_RUN'],'qa_endowment':0,
            'live_gameplay_actions':'Actual XTest keyboard/pointer and native window closure only',
            'observer':'Read-only, process PID and run ID checked on every read','reference':'Separate offline copies only',
            'guidance':'Automated W/S keyboard; not human play or fairness testing'})

    def _metadata(self):
        super()._metadata()
        for name in ['extreme-source-metadata.json','extreme-validation-summary.json']:
            path=self.out/name
            if path.exists():
                data=json.loads(path.read_text())
                data.update(method='Fresh natural production game; actual XTest; read-only runtime observer and saves',
                    qa_endowment=0,preseeded=False,save_mutation='No save authoring or editing; game-written saves read only')
                dump(path,data)

    def execute(self,command):
        command=dict(command);target=command.pop("focus",None)
        if target:self.focus(target)
        return super().execute(command)

    def observe(self):
        data=json.loads((self.out/'three-day-latest.json').read_text())
        if data['run_id']!=os.environ['SC_QA_RUN']:raise RuntimeError('Wrong observer run')
        if self.current_pid is not None and data['observer_pid']!=self.current_pid:raise RuntimeError('Wrong observer process')
        if time.time()-data['unix_seconds']>3:raise RuntimeError('Read-only observer is stale')
        return data

    def wait(self,predicate,label,timeout=45):
        deadline=time.monotonic()+timeout;o={}
        while time.monotonic()<deadline:
            try:o=self.observe()
            except (FileNotFoundError,RuntimeError):time.sleep(.03);continue
            if predicate(o):return o
            time.sleep(.012)
        dump(self.out/'timeout-observation.json',o)
        raise AssertionError('Native wait timed out: '+label)

    def check(self,name,condition,detail=None):
        row={'test':name,'passed':bool(condition),'detail':detail};self.checks.append(row)
        dump(self.out/'three-day-checks.json',self.checks);print(json.dumps(row,ensure_ascii=False),flush=True)
        if not condition:raise AssertionError(name)

    def click_view(self,key,sleep=.25,repeat=1,text=None):
        previous=None;stable_since=0.0;deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            o=self.observe()
            found=[b for b in o['buttons'] if b['view_key']==key and not b['disabled'] and (text is None or b['text']==text)]
            if len(found)!=1:
                previous=None;time.sleep(.04);continue
            button=found[0];x,y,w,h=button['rect'];cx,cy,cw,ch=button['clip_rect']
            if cw<min(w,12) or ch<min(h,12) or cy+ch/2<0 or cy+ch/2>=o['window_size'][1]:
                direction=5 if y+h/2>o['window_size'][1]/2 else 4
                self.execute({'click':[o['window_size'][0]-50,o['window_size'][1]/2,direction],'sleep':.12})
                previous=None;continue
            geometry=(button['rect'],button['clip_rect'],o['page'])
            if geometry!=previous:previous=geometry;stable_since=time.monotonic()
            elif time.monotonic()-stable_since>=.20:
                point=[cx+cw/2,cy+ch/2]
                if repeat>1:return self.execute({'actions':[{'click':point,'sleep':0} for _ in range(repeat)],'sleep':sleep})
                return self.execute({'click':point,'sleep':sleep})
            time.sleep(.025)
        dump(self.out/'button-timeout-observation.json',self.observe())
        raise AssertionError('No stable unclipped native button '+key)

    def state(self):return self.send({'state':True,'sleep':0})['state']

    def restart(self,label,expected=None,flight=False):
        self.set_keys(set());old_pid=self.current_pid
        self.execute({'close':True,'snapshot':label+'-closed','sleep':0});closed=self.state()
        self.current_pid=None
        self.execute({'start':5,'sleep':.1})
        restored=self.wait(lambda o:o['observer_pid']!=old_pid and (o['page']=='flight' and o['paused'] if flight else True),'new process '+label)
        self.current_pid=restored['observer_pid']
        after=self.state()
        self.check(label+' new native process preserves exact save, appearance, story, orders and blueprint',
            persistence(after)==persistence(closed) and (expected is None or persistence(closed)==persistence(expected)),
            {'old_pid':old_pid,'new_pid':self.current_pid,'day':after['day'],'reputation':after['reputation']})
        self.screenshot(label+'-restored')
        return restored

    def clear_dialogues(self,label):
        deadline=time.monotonic()+60;count=0;quiet_since=None
        while time.monotonic()<deadline:
            o=self.observe()
            if o['dialogue_open']:
                self.finish_dialogue(label+'-'+str(count));count+=1;quiet_since=None
            elif o['pending_story']:
                quiet_since=None;time.sleep(.03)
            else:
                if quiet_since is None:quiet_since=time.monotonic()
                if time.monotonic()-quiet_since>=.3:return
                time.sleep(.025)
        raise AssertionError('Pending dialogue did not settle '+label)

    def to_counter(self,label):
        self.clear_dialogues(label+'-pending')
        o=self.observe()
        if o['page']=='report':self.click_view('action:next_contract:null',.05)
        elif o['page']=='hub':self.click_hub(0,.05)
        elif o['page']!='contracts':
            self.click_view('action:close_drawer:null',text='‹  返回店铺');self.clear_dialogues(label+'-return');self.click_hub(0,.05)
        deadline=time.monotonic()+50
        while True:
            o=self.observe()
            if o['dialogue_open']:self.finish_dialogue(label+'-counter-greeting')
            elif o['page']=='contracts':break
            if time.monotonic()>deadline:raise AssertionError('Counter arrival failed')
            time.sleep(.02)
        self.check(label+' contract UI reached at actual counter proximity',o['at_counter'],o['locomotion'])

    def accept(self,cid,natural_loading=False):
        self.to_counter(cid)
        before=self.state();self.click_view('action:accept_contract:'+json.dumps(cid),.05)
        self.finish_dialogue(cid+'-accept')
        o=self.wait(lambda o:o['overlay_open'] or o['cargo_loaded'],'actual cooperative loading '+cid)
        self.screenshot(cid+'-loading')
        if not natural_loading and o['overlay_open']:self.execute({'key':'Escape','sleep':.15})
        loaded=self.wait(lambda o:o['cargo_loaded'] and o['page']=='workshop' and not o['overlay_open'],'durable cargo '+cid,60)
        after=self.state()
        self.check(cid+' accepted dialogue and '+('natural robot loading' if natural_loading else 'native loading skip')+' persist actual cargo',
            after['active_contract_id']==cid and loaded['cargo_loaded'] and after['credits']==before['credits']
            and after['settled_ids']==before['settled_ids'] and loaded['input']['shop_axis']==0 and not loaded['input']['held_keys'],
            {'loading':loaded['loading'],'active':after['active_contract_id']})
        return after

    def reference(self,spec,label):
        path=self.out/(label+'-reference-spec.json');dump(path,spec)
        runtime=self.out/'offline-reference-runtime'
        for name in ['home','data','config','cache']:(runtime/name).mkdir(parents=True,exist_ok=True)
        env=dict(os.environ,HOME=str(runtime/'home'),XDG_DATA_HOME=str(runtime/'data'),XDG_CONFIG_HOME=str(runtime/'config'),XDG_CACHE_HOME=str(runtime/'cache'))
        p=subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://tests/test_three_day_progression.gd','--','--spec',str(path)],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=80)
        (self.out/(label+'-reference.log')).write_text(p.stdout);p.check_returncode()
        result=json.loads(next(x.split(':',1)[1] for x in p.stdout.splitlines() if x.startswith('THREE_DAY_REFERENCE_JSON:')))
        if result.get('error'):raise AssertionError(result['error'])
        dump(self.out/(label+'-reference.json'),result);return result

    def formal_review(self,cid,test_cancel=False):
        before=self.state()
        if test_cancel:
            self.click_view('action:dispatch:null');self.wait(lambda o:o['dispatch_confirm'],'formal review')
            self.screenshot(cid+'-formal-review')
            self.execute({'actions':[{'key':'Return'},{'key':'Return'},{'key':'Escape'}],'sleep':.1})
            self.check(cid+' modal default Enter/cancel cannot silently dispatch or charge',persistence(self.state())==persistence(before) and not self.observe()['dispatch_confirm'])
        self.click_view('action:dispatch:null');self.wait(lambda o:o['dispatch_confirm'],'formal review open')
        self.click_view('dispatch:confirm',.01,repeat=2)
        self.wait(lambda o:o['page']=='flight' and not o['trial'],'formal flight '+cid)
        self.check(cid+' repeated pointer confirm creates only its own in-flight commitment',self.state()['in_flight']['contract_id']==cid and self.state()['settled_ids']==before['settled_ids'])

    def drive(self,cid,stop_tick=None,capture=False):
        started=time.monotonic();next_tick=-1;last_tick=-1;trace=[];shots=set();capture_started=False
        while time.monotonic()-started<150:
            o=self.observe();tick=o['completed_ticks'];pos=o.get('position',[0,0]);x=pos[0]
            if o['page']!='flight':raise AssertionError('Unexpected page during '+cid+': '+o['page'])
            if tick<last_tick:raise AssertionError('Native ticks moved backward')
            last_tick=tick
            if o.get('sim_status')!='running':
                self.set_keys(set());dump(self.out/(cid+'-terminal-observation.json'),o)
                if capture_started:self.execute({'capture_stop':True,'sleep':0})
                self.screenshot(cid+'-receiver')
                self.check(cid+' actual native receiver succeeds',o['sim_status']=='success',{'time':o['sim_elapsed'],'position':pos,'integrity':o['telemetry']['integrity'],'events':o['events']})
                break
            if stop_tick is not None and tick>=stop_tick:
                self.execute({'key':'p','sleep':.1});self.set_keys(set());o=self.wait(lambda o:o['paused'],'P pause')
                break
            if capture and x>=535 and not capture_started:
                self.execute({'capture_start':'naturally-earned-D3-B-wormhole','sleep':0});capture_started=True
            if tick>=next_tick and not o['paused']:
                axis=int(o.get('guidance_axis_q',0));keys={'w'} if axis<0 else ({'s'} if axis>0 else set())
                self.set_keys(keys);trace.append({'tick':tick,'unix_seconds':time.time(),'axis_q':axis,'keys':sorted(keys),'position':pos});next_tick=tick+12
            for threshold,name in ([(560,'gate-approach'),(1005,'otherworld')] if capture else []):
                if x>=threshold and name not in shots:self.screenshot(cid+'-'+name);shots.add(name)
            time.sleep(.008)
        else:raise AssertionError('Native route exceeded 150 real seconds '+cid)
        dump(self.out/(cid+('-partial' if stop_tick else '')+'-os-guidance.json'),trace)
        return o

    def audit(self,cid,terminal,accepted):
        self.wait(lambda o:o['page']=='report','report '+cid)
        state=self.state();receipt=state['settled_ids'][cid]
        replay=self.reference({'snapshot':terminal['flight_snapshot'],'mode':'replay'},cid+'-exact-input')
        self.check(cid+' exact recorded input reproduces native physics',replay['status']==terminal['sim_status'] and replay['position']==terminal['position'] and replay['elapsed']==terminal['sim_elapsed'] and replay['energy_used']==terminal['telemetry']['energy_used'])
        costs={key:math.ceil(replay['telemetry'].get(source,0)) for key,source in [('ammo','ammo_cost'),('repairs','repair_cost'),('lost','lost_cost')]}
        costs['energy']=math.ceil(replay['energy_used']*receipt['energy_tariff'])
        self.check(cid+' one intact on-time receipt has exact replayed costs and balance',receipt['success'] and receipt['integrity']==100 and receipt['elapsed']<receipt['deadline'] and all(receipt[k]==v for k,v in costs.items()) and receipt['profit']==receipt['income']-sum(costs.values()) and state['credits']==accepted['credits']+receipt['profit'] and len(state['settled_ids'])==len(accepted['settled_ids'])+1 and len(state['history'])==len(state['settled_ids']) and state['reputation']==accepted['reputation']+2 and not state['in_flight'],receipt)
        self.check(cid+' original craft, inventory and previous receipts remain unchanged',state['design']==accepted['design'] and state['launcher']==accepted['launcher'] and state['inventory']==accepted['inventory'] and all(state['settled_ids'][k]==v for k,v in accepted['settled_ids'].items()))
        if cid=='D3-B':
            self.check('naturally earned D3-B has one actual portal crossing and otherworld receiver',len(terminal['wormhole_events'])==1 and terminal['otherworld']['phase']=='otherworld' and receipt['wormhole_transits']==1 and receipt['wormhole_energy_j']==terminal['telemetry']['wormhole_energy_used'],terminal['wormhole_events'])
        self.results[cid]={'receipt':receipt,'position':terminal['position'],'elapsed':terminal['sim_elapsed'],'exact_replay':True,'remaining_energy':replay['remaining_energy']}
        dump(self.out/(cid+'-settled-ledger.json'),state)
        return state

    def night(self,day):
        self.clear_dialogues('D%d-result'%day)
        self.click_view('action:close_drawer:null',text='返回店铺');self.clear_dialogues('D%d-return'%day)
        self.click_hub(2,.1);self.wait(lambda o:o['page']=='supply','night supply')
        before=self.state();self.click_view('action:close_day:null');night=self.state()
        self.check('Day %d closes with no hidden charge'%day,night['phase']=='night' and night['credits']==before['credits'] and night['settled_ids']==before['settled_ids'])
        if day==1:
            self.check('Day 1 earned balance covers selected 225-credit purchases',night['credits']>=225)
            self.click_view('action:workshop_upgrade:1');up=self.state()
            self.check('Natural night workshop purchase costs exactly 180',up['workshop_tier']==1 and up['credits']==night['credits']-180)
            self.click_view('action:buy:"battery"');bought=self.state()
            self.check('Natural night spare battery costs exactly 45',bought['credits']==up['credits']-45 and bought['inventory']['battery']==up['inventory']['battery']+1)
        elif day==2:
            self.click_view('action:buy:"beam"');bought=self.state()
            self.check('Natural night spare beam costs exactly 10',bought['credits']==night['credits']-10 and bought['inventory']['beam']==night['inventory']['beam']+1)
        else:bought=night
        self.screenshot('day-%d-night-purchases'%day);self.click_view('action:next_day:null');after=self.state()
        self.check('Day %d advances while preserving all receipts, inventory and balance'%day,after['day']==day+1 and after['jobs_today']==0 and after['phase']=='morning' and after['credits']==bought['credits'] and after['inventory']==bought['inventory'] and after['settled_ids']==bought['settled_ids'])
        dump(self.out/('day-%d-next-morning-ledger.json'%(day+1)),after)
        return after

    def run(self):
        first=self.state()
        self.check('Fresh isolated game starts naturally at day one and reputation zero',not self.fixture['preseeded'] and first['day']==1 and first['reputation']==0 and first['credits']==260 and first['settled_ids']=={} and first['jobs_today']==0 and not first['active_contract_id'])
        self.check('Fresh ground offers and ordinary eight-part single-cell craft',all(o.get('route_profile')=='ground-city-v1' for o in first['contracts']) and len(first['design'])==8 and sum(p['type']=='battery' for p in first['design'])==1)
        self.check('No physical gamepad claimed',not self.observe()['connected_joypads'])
        for day in range(1,4):
            morning=self.state();offers=morning['contracts']
            self.check('Day %d begins with entirely earned reputation %d'%(day,(day-1)*4),morning['day']==day and morning['reputation']==(day-1)*4)
            self.check('Day %d fresh route progression matches earned unlock'%day,
                all(o['control_version']=='pilot-v3' for o in offers) if day<3 else offers[0]['control_version']=='pilot-v3' and offers[1]['control_version']=='pilot-v4-wormhole',
                [{'id':o['contract_id'],'rep':o['rep'],'version':o['control_version'],'profile':o.get('route_profile',''),'destination':o['destination_name']} for o in offers])
            for slot in ['A','B']:
                cid='D%d-%s'%(day,slot);accepted=self.accept(cid,natural_loading=slot=='A')
                if cid=='D1-A':
                    self.click_view('action:save_blueprint:null');saved=self.state()
                    self.check('Blueprint saved through real workshop button',saved['designs']['workbench']=={'design':saved['design'],'launcher':saved['launcher']})
                    self.restart('first-loaded-blueprint',saved)
                    self.check('Loaded cargo restart does not repeat loading',self.observe()['cargo_loaded'] and not self.observe()['overlay_open'])
                    self.clear_dialogues('first-loaded-restart')
                    if self.observe()['page']=='hub':self.click_hub(1,.1);self.wait(lambda o:o['page']=='workshop','workshop after loaded restart')
                    accepted=self.state()
                if cid=='D2-A':
                    self.click_view('action:load_blueprint:null');loaded=self.state()
                    self.check('Saved starter blueprint loads through actual workshop controls',loaded['design']==accepted['design'] and loaded['launcher']==accepted['launcher'] and loaded['credits']==accepted['credits'] and loaded['designs']==accepted['designs'])
                reference=self.reference(self.reference_spec(accepted),cid+'-plan')
                self.check(cid+' offline copied route is feasible without modifying actual ship',reference['status']=='success',{'elapsed':reference['elapsed'],'remaining_energy':reference['remaining_energy']})
                self.formal_review(cid,test_cancel=cid in ['D1-A','D3-B'])
                if cid=='D1-A':
                    paused=self.drive(cid,stop_tick=480);ticks=paused['completed_ticks']
                    self.execute({'focus':'root','sleep':.3});self.set_keys(set());time.sleep(.4)
                    self.check('Actual focus loss keeps paused simulation stable and clears pilot input',self.observe()['completed_ticks']==ticks and self.observe()['paused'] and not self.held)
                    self.execute({'focus':'game','sleep':.1})
                    restored=self.restart('first-ground-checkpoint',flight=True)
                    self.check('Ground checkpoint restores exact ticks, energy and position',restored['completed_ticks']==ticks and restored['position']==paused['position'] and restored['telemetry']['energy_used']==paused['telemetry']['energy_used'])
                    self.execute({'key':'p','sleep':.01})
                terminal=self.drive(cid,capture=cid=='D3-B');self.audit(cid,terminal,accepted)
                self.finish_dialogue(cid+'-result')
            next_morning=self.night(day)
            if day in [2,3]:self.restart('day-%d-morning'%(day+1),next_morning)
        final=self.state();self.check('Three natural business days end with six unique successful settlements',final['day']==4 and final['deliveries']==6 and final['reputation']==12 and len(final['settled_ids'])==6 and len(final['history'])==6 and final['design']==first['design'] and final['launcher']==first['launcher'])
        identity_keys=['appearance_id','appearance_seed','species','accessory_id','story_id']
        self.check('All original appearance identities persist into recurring customers',final['story_state']['world_seed']==first['story_state']['world_seed'] and all(all(final['story_state']['roster'][actor][key]==value[key] for key in identity_keys) for actor,value in first['story_state']['roster'].items()))
        self.check('Final balance equals six exact receipts minus only authorized natural purchases',final['credits']==260+sum(r['profit'] for r in final['settled_ids'].values())-180-45-10)
        self.check('Story commits each receipt once and retains original route destinations',set(final['story_state']['committed_contract_ids'])==set(final['settled_ids']) and final['story_state']['committed_contract_ids']['D1-A']['route_context']['destination_name']=='屋顶收件台' and final['story_state']['committed_contract_ids']['D3-B']['route_context']['destination_name']=='苔光驿站')
        dump(self.out/'final-natural-ledger.json',final);self.screenshot('final-day-four-six-deliveries')
        self.results['final']={k:final[k] for k in ['credits','day','reputation','deliveries','workshop_tier','inventory','designs','settled_ids']}
        self.check('All production, artwork and QA source hashes unchanged during run',hashes()==self.started_hashes)
        self.status='three_day_natural_pass'
        self.execute({'close':True,'sleep':0})

    def close(self):
        super().close();after=hashes();dump(self.out/'source-hashes-after.json',after)
        dump(self.out/'three-day-validation-summary.json',{'status':self.status,'checks':self.checks,'results':self.results,'captures':self.captures,'telemetry_sessions':self.telemetry_sessions,'source_unchanged':after==self.started_hashes,'release_note':self.release_note,'wall_seconds':time.monotonic()-self.started_at,'method':'Fresh natural three-day cloud XTest progression; read-only automated guidance and separate exact-input replay','preseeded':False,'qa_endowment':0,'live_state_mutation':False,'time_scale':1,'human_fairness_claim':False,'physical_pad_claim':False,'subjective_audio_claim':False,'native_windows_claim':False})


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ready',action='store_true');p.add_argument('--release-note',required=True);p.add_argument('--out',required=True);p.add_argument('--display',type=int,default=650)
    args=p.parse_args();out=Path(args.out).resolve()
    if not args.ready:p.error('Exclusive native-slot release required')
    if not out.is_relative_to(BASE_OUT.resolve()) or out.exists():p.error('Use a fresh evidence directory under three-day-native')
    if args.display<650:p.error('Use isolated unused display >=650')
    run='natural-three-day-'+str(time.time_ns())
    os.environ.update(SC_QA_RUN=run,SC_QA_OUT=str(out),SC_QA_DISPLAY=str(args.display),SC_QA_RESOLUTION='1920x1080',SC_QA_XORG_CONFIG=str(ROOT/'tools/xorg_native_1920.conf'),SC_QA_START_WAIT='5')
    c=ThreeDay(args)
    try:c.run()
    except Exception as exc:
        c.status='failed';dump(c.out/'three-day-error.json',{'error':repr(exc)})
        try:c.execute({'shot':'failure-screen','snapshot':'failure-save','sleep':0})
        except Exception:pass
        raise
    finally:c.close()

if __name__=='__main__':main()
