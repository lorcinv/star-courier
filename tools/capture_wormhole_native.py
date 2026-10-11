#!/usr/bin/env python3
"""Bounded cloud XTest QA for a disclosed offline DAY THREE heavy D3-B fixture.

Offline setup only: ordinary eight-part v3 starter, one ship cell, reputation 8,
current Economy-authored and accepted/loaded D3-B. It is not earned progression.
After native startup all game actions use actual XTest keys/pointer and native
window close. A read-only observer computes a steering suggestion from the
verified guidance formula; this is automated input, never a human-fairness test.
No physical controller, time scaling, gameplay API calls, or runtime save edits.
Use --prepare-only without GUI; --ready requires explicit coordinator release.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
import qa_v5_native_extreme as native
import qa_v5_native_handoff as handoff

BASE_OUT=ROOT/'docs/qa/v5/wormhole-native'
QA_ENTRY='res://tools/qa_wormhole_observer.gd'

def dump(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def hashes():
    result=handoff.hashes()
    for path in ['tools/capture_wormhole_native.py','tools/qa_wormhole_observer.gd',
                 'tools/pilot_wormhole_reference.gd','tools/pilot_wormhole_guidance.gd',
                 'tests/qa_v5_native_extreme.py']:
        result[path]=hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
    return result

FIXTURE_SCRIPT='''extends SceneTree
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Stories=preload("res://scripts/courier_stories.gd")
func _initialize() -> void:
 var args=OS.get_cmdline_user_args()
 var e=Econ.new();e.day=3;e.reputation=8;e.enable_extreme_mode()
 var design:Array=Profile.starter_design();var launcher:Array=Profile.starter_launcher()
 e.starter_stock(design,launcher)
 e.story_state=Stories.initial_state(202610103);e.enable_story_mode()
 if not e.accept_contract("D3-B").ok:push_error("Fixture accept rejected");quit(2);return
 e.mark_story_seen("D3-B","D3-B/accept")
 if not e.mark_cargo_loaded("D3-B").ok:push_error("Fixture load rejected");quit(3);return
 var order:Dictionary=e.active_contract()
 if order.control_version!="pilot-v4-wormhole" or order.weight!=3.72 or design.size()!=8:push_error("Wrong fixture identity");quit(4);return
 var settings={"pixel_density":"auto","quality":"auto","reduced_motion":false,"motion_blur":true}
 if not e.save_state(design,launcher,settings):push_error(e.save_error);quit(5);return
 var info={"fixture":"DAY THREE QA fixture; not earned progression","day":e.day,"reputation":e.reputation,
  "active_contract_id":e.active_contract_id,"cargo_weight_multiplier":order.weight,"ordinary_starter_parts":design.size(),
  "ship_cells":design.filter(func(p):return p.type=="battery").size(),"qa_endowment":0,"credits":e.credits,
  "preseeded":true,"mutations_before_native_process_only":true,"live_physics_mutation":false,
  "offline_authored_actions":["Set day 3 and reputation 8","Author current Economy offers","Accept D3-B","Mark acceptance seen and cargo loaded"],
  "route":order,"design":design,"launcher":launcher,"save":ProjectSettings.globalize_path("user://savegame.json")}
 var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(info,"  ",true,true));file.close()
 print("WORMHOLE_FIXTURE_READY ",JSON.stringify(info));quit()
'''

def seed_fixture(out,runtime,fixture):
    if runtime.exists():raise RuntimeError('Refusing to overwrite any existing runtime: '+str(runtime))
    for name in ['home','data','config','cache']:(runtime/name).mkdir(parents=True)
    script=out/'seed-wormhole-day-three-fixture.gd';script.write_text(FIXTURE_SCRIPT)
    env=dict(os.environ,HOME=str(runtime/'home'),XDG_DATA_HOME=str(runtime/'data'),
             XDG_CONFIG_HOME=str(runtime/'config'),XDG_CACHE_HOME=str(runtime/'cache'))
    p=subprocess.run(['godot','--headless','--path',str(ROOT),'--script',str(script),'--',fixture,str(out/'fixture.json')],
        env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
    (out/'fixture-generation.log').write_text(p.stdout);p.check_returncode()
    info=json.loads((out/'fixture.json').read_text());source=Path(info['save'])
    target=out/'before-native-seeded-save.json';target.write_bytes(source.read_bytes())
    info.update(seeded_save_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),seeded_before_native_unix=time.time())
    dump(out/'fixture.json',info);return info

class WormholeCapture(native.NativeExtreme):
    def __init__(self,args):
        native.BASE_OUT=BASE_OUT;native.QA_ENTRY=QA_ENTRY;native.hashes=hashes;native.seed_fixture=seed_fixture
        args.fixture='wormhole-day-three'
        super().__init__(args)
        self.results={};self.status='running';self.drive_trace=[]
        dump(self.out/'source-hashes-before.json',self.started_hashes)
        snapshot_dir=self.out/'qa-source-snapshot';snapshot_dir.mkdir()
        for name in ['capture_wormhole_native.py','qa_wormhole_observer.gd','pilot_wormhole_reference.gd','pilot_wormhole_guidance.gd']:
            (snapshot_dir/name).write_bytes((ROOT/'tools'/name).read_bytes())
    def observe(self):
        data=json.loads((self.out/'wormhole-latest.json').read_text())
        if time.time()-data['unix_seconds']>3:raise RuntimeError('Read-only observer is stale')
        return data
    def wait(self,predicate,label,timeout=40):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            try:o=self.observe()
            except RuntimeError as exc:
                if 'observer is stale' not in str(exc):raise
                time.sleep(.03);continue
            if predicate(o):return o
            time.sleep(.012)
        dump(self.out/'timeout-observation.json',o)
        raise AssertionError('Native observation timed out: '+label)
    def check(self,name,condition,detail=None):
        row={'test':name,'passed':bool(condition),'detail':detail};self.checks.append(row)
        dump(self.out/'wormhole-checks.json',self.checks);print(json.dumps(row,ensure_ascii=False),flush=True)
        if not condition:raise AssertionError(name)
    def state(self):return self.send({'state':True,'sleep':0})['state']
    def shot(self,name):return self.execute({'shot':name,'snapshot':name,'sleep':0})
    def click_view(self,key,sleep=.15):
        o=self.observe();found=[b for b in o['buttons'] if b['view_key']==key and not b['disabled']]
        if len(found)!=1:raise AssertionError('Expected one visible UI button '+key+': '+repr(found))
        x,y,w,h=found[0]['rect']
        if not (0<=x+w/2<o['window_size'][0] and 0<=y+h/2<o['window_size'][1]):raise AssertionError('UI button offscreen: '+key)
        return self.execute({'click':[x+w/2,y+h/2],'sleep':sleep})
    def open_workshop(self):
        o=self.observe()
        buttons=sorted([b for b in o['buttons'] if b['text']=='' and b['view_key']=='' and not b['disabled'] and b['rect'][2]>100],key=lambda b:b['rect'][0])
        if len(buttons)!=3:raise AssertionError('Expected actual three shop hotspot buttons')
        x,y,w,h=buttons[1]['rect'];self.execute({'click':[x+w/2,y+h/2],'sleep':.1})
        self.wait(lambda o:o['page']=='workshop' and not o['overlay_open'],'physical workbench arrival')
    def archive_telemetry(self):
        source=self.out/'native-telemetry.json'
        if not source.exists():return {'available':False}
        target=self.out/('wormhole-telemetry-session-%02d.json'%(len(self.telemetry_sessions)+1));source.replace(target)
        data=json.loads(target.read_text());item={'path':str(target),'samples':len(data['samples']),'capped':data['capped'],'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
        self.telemetry_sessions.append(item);dump(self.out/'telemetry-observation-index.json',self.telemetry_sessions);return item
    def drive(self,label,stop_x=None,start_capture_x=None):
        began=time.monotonic();next_tick=-1;last_tick=-1;shots=set();transitions=[]
        initial_x=self.observe().get('position',[0,0])[0]
        while time.monotonic()-began<120:
            o=self.observe();tick=o['completed_ticks'];pos=o.get('position',[0,0]);x=pos[0]
            if o['page']!='flight':raise AssertionError('Unexpected page during drive: '+o['page'])
            if tick<last_tick:raise AssertionError('Observed live ticks moved backwards')
            last_tick=tick
            if start_capture_x is not None and x>=start_capture_x and self.capture is None:
                self.execute({'capture_start':label+'-before-restart','sleep':0});start_capture_x=None
            if o.get('sim_status')!='running':
                self.set_keys(set());dump(self.out/(label+'-terminal-observation.json'),o)
                self.shot(label+'-receiver');self.check(label+' reaches actual receiver success',o['sim_status']=='success',{'elapsed':o['sim_elapsed'],'ticks':tick,'integrity':o['telemetry']['integrity']})
                break
            if stop_x is not None and x>=stop_x:
                self.execute({'key':'p','sleep':.15});self.set_keys(set())
                o=self.wait(lambda o:o['paused'],'actual P pause');dump(self.out/(label+'-paused-observation.json'),o);break
            if tick>=next_tick and not o['paused']:
                axis=int(o.get('guidance_axis_q',0));wanted={'w'} if axis<0 else ({'s'} if axis>0 else set())
                self.set_keys(wanted);transitions.append({'unix_seconds':time.time(),'observed_tick':tick,'axis_q':axis,'os_keys':sorted(wanted),'position':pos})
                next_tick=tick+12
            # Observer-led OS screenshot requests do not stop the running game.
            for threshold,name in [(1,'grounded-launch'),(180,'ascent'),(565,'aperture-approach'),(1005,'otherworld-exit'),(1190,'receiver-approach')]:
                if threshold<initial_x-10:shots.add(name)
                if x>=threshold and name not in shots:
                    self.shot(label+'-'+name);shots.add(name)
            time.sleep(.008)
        else:raise AssertionError('Bounded real-time route exceeded 120 seconds')
        dump(self.out/(label+'-os-guidance-trace.json'),transitions);self.drive_trace+=transitions;return o
    def reference(self,snapshot,name):
        spec=self.out/(name+'-exact-input-spec.json');dump(spec,{'snapshot':snapshot,'mode':'replay'})
        runtime=self.out/'offline-wormhole-reference-runtime'
        for namepart in ['home','data','config','cache']:(runtime/namepart).mkdir(parents=True,exist_ok=True)
        env=dict(os.environ,HOME=str(runtime/'home'),XDG_DATA_HOME=str(runtime/'data'),XDG_CONFIG_HOME=str(runtime/'config'),XDG_CACHE_HOME=str(runtime/'cache'))
        p=subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://tools/pilot_wormhole_reference.gd','--','--spec',str(spec)],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=80)
        (self.out/(name+'-exact-input-replay.log')).write_text(p.stdout);p.check_returncode()
        result=json.loads(next(line.split(':',1)[1] for line in p.stdout.splitlines() if line.startswith('WORMHOLE_REFERENCE_JSON:')))
        dump(self.out/(name+'-exact-input-replay.json'),result);return result
    def audit(self,o,label):
        replay=self.reference(o['flight_snapshot'],label)
        self.check(label+' exact actual-input replay matches native state',
            replay['status']==o['sim_status'] and replay['elapsed']==o['sim_elapsed'] and replay['position']==o['position'] and replay['energy_used']==o['telemetry']['energy_used'] and replay['wormhole_events']==o['wormhole_events'],
            {'ticks':o['completed_ticks'],'elapsed':o['sim_elapsed'],'energy_used':replay['energy_used'],'remaining_energy':replay['remaining_energy'],'station_energy':o['telemetry']['wormhole_energy_used']})
        events=o['wormhole_events']
        self.check(label+' one live portal crossing and otherworld presentation',len(events)==1 and events[0]['to'][0]-events[0]['from'][0]>390 and o['otherworld']['phase']=='otherworld',events)
        commands=o['flight_snapshot']['input_commands']
        self.check(label+' both W and S in actual input ticks',any(c['axis_q']<0 for c in commands) and any(c['axis_q']>0 for c in commands))
        self.results[label]={'terminal':str(self.out/(label+'-terminal-observation.json')),'elapsed':o['sim_elapsed'],'integrity':replay['integrity'],'remaining_energy':replay['remaining_energy'],'station_energy':o['telemetry']['wormhole_energy_used'],'exact_replay':True}
    def preflight(self):
        o=self.observe();saved=self.state();order=next(x for x in saved['contracts'] if x['contract_id']=='D3-B')
        self.check('explicit Day Three fixture and unmodified ordinary one-cell ship',saved['day']==3 and saved['reputation']==8 and order['weight']==3.72 and len(saved['design'])==8 and sum(p['type']=='battery' for p in saved['design'])==1,{'fixture':self.fixture['fixture'],'credits':saved['credits'],'not_earned_progression':True})
        self.check('native 1080p auto renders logical 960 with integer 2x',o['window_size']==[1920,1080] and o['canvas_size']==[960,540] and o['pixel_scale']==2,{'window':o['window_size'],'logical':o['canvas_size'],'scale':o['pixel_scale']})
        self.check('no physical gamepad is claimed',not o['connected_joypads'],o['connected_joypads'])
        self.open_workshop();self.shot('01-day-three-workshop')
        return saved
    def trial(self):
        baseline=self.preflight()
        self.execute({'capture_start':'01-wormhole-trial-full-route','sleep':.1})
        for index in [1,2]:
            self.click_view('action:dispatch:null');self.wait(lambda o:o['dispatch_confirm'],'formal modal opens')
            self.shot('02-formal-modal-'+str(index))
            self.click_view('dispatch:cancel');self.wait(lambda o:not o['dispatch_confirm'],'formal Cancel closes')
            self.check('formal modal Cancel '+str(index)+' has no dispatch or ledger effect',native.ledger(self.state())==native.ledger(baseline))
        self.click_view('action:trial:null',.02);self.wait(lambda o:o['page']=='flight','native free trial launch')
        terminal=self.drive('trial-wormhole')
        self.wait(lambda o:o['page']=='report','free trial report');time.sleep(.5)
        self.execute({'capture_stop':True,'shot':'trial-wormhole-report','sleep':0})
        self.check('successful free trial preserves full business ledger',native.ledger(self.state())==native.ledger(baseline))
        self.audit(terminal,'trial-wormhole');self.results['excerpt']=self.excerpt();self.status='trial_pass'
    def excerpt(self):
        source=self.captures[-1]['video']
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',source],text=True))
        duration=float(probe['format']['duration']);length=min(28.0,duration);start=max(0.0,duration-length)
        target=self.out/'02-wormhole-portal-to-receiver-28s.mp4'
        subprocess.run(['ffmpeg','-nostdin','-hide_banner','-loglevel','warning','-y','-ss',str(start),'-i',source,
            '-t',str(length),'-c:v','libx264','-preset','veryfast','-crf','18','-c:a','aac','-b:a','192k','-movflags','+faststart',str(target)],check=True)
        dump(self.out/'excerpt-metadata.json',{'video':str(target),'source_full_video':source,'source_start_seconds':start,
            'duration_seconds':length,'method':'One continuous unsped-up trim; no hidden cuts; actual Master mix retained',
            'fixture':'DAY THREE QA fixture; automated XTest keyboard, not human play','full_video_preserved':True})
        return str(target)
    def recovery(self):
        baseline=self.preflight()
        for index in [1,2]:
            self.click_view('action:dispatch:null');self.wait(lambda o:o['dispatch_confirm'],'formal modal opens')
            self.shot('02-formal-modal-'+str(index));self.click_view('dispatch:cancel')
            self.wait(lambda o:not o['dispatch_confirm'],'formal Cancel closes')
            self.check('formal modal Cancel '+str(index)+' has no ledger effect',native.ledger(self.state())==native.ledger(baseline))
        self.click_view('action:dispatch:null');self.wait(lambda o:o['dispatch_confirm'],'formal modal opens')
        self.click_view('dispatch:confirm',.02);self.wait(lambda o:o['page']=='flight' and not o['trial'],'formal dispatch starts')
        paused=self.drive('formal-wormhole',stop_x=1015,start_capture_x=540)
        ticks=paused['completed_ticks'];time.sleep(.7);held=self.observe()
        self.check('P pause freezes native otherworld simulation and blur',held['completed_ticks']==ticks and held['otherworld']['phase']=='otherworld' and held['otherworld']['blur_pixels']==0)
        self.execute({'key':'p','sleep':.4});self.wait(lambda o:not o['paused'] and o['completed_ticks']>ticks,'P unpause resumes')
        self.execute({'key':'p','sleep':.1});self.set_keys(set());paused=self.wait(lambda o:o['paused'],'pause before restart')
        self.shot('formal-otherworld-paused-before-restart');self.execute({'capture_stop':True,'sleep':0})
        self.execute({'close':True,'sleep':0});saved=self.state();dump(self.out/'formal-close-save.json',saved)
        self.check('native close persists v4 exact replay in otherworld',saved['in_flight']['control_version']=='pilot-v4-wormhole' and saved['in_flight']['ticks']==paused['completed_ticks'])
        self.execute({'start':5,'sleep':.15});restored=self.wait(lambda o:o['paused'] and o['page']=='flight','native restart restores paused')
        self.check('otherworld restart preserves state with no second live portal cut',restored['position']==paused['position'] and restored['completed_ticks']==paused['completed_ticks'] and restored['wormhole_events']==paused['wormhole_events'] and restored['otherworld']['phase']=='otherworld' and restored['otherworld']['last_cut_restored'] and restored['otherworld']['live_transitions']==0,{'before':paused['position'],'after':restored['position'],'otherworld':restored['otherworld']})
        self.execute({'capture_start':'03-wormhole-restarted-to-receiver','sleep':0});self.shot('formal-otherworld-restored')
        self.execute({'key':'p','sleep':0});self.wait(lambda o:not o['paused'],'resume after restart')
        terminal=self.drive('formal-wormhole-restored')
        self.wait(lambda o:o['page']=='report','formal receiver report');time.sleep(.4)
        self.execute({'capture_stop':True,'shot':'formal-wormhole-report','sleep':0})
        self.audit(terminal,'formal-wormhole-restored');saved=self.state();receipt=saved['settled_ids']['D3-B']
        self.check('formal success settles exactly one D3-B receipt',saved['jobs_today']==1 and saved['deliveries']==1 and len(saved['settled_ids'])==1 and receipt['success'] and not saved['in_flight'],receipt)
        self.status='recovery_pass'
    def close(self):
        super().close()
        summary={'status':self.status,'method':'Automated actual cloud XTest; normal wall time; read-only telemetry guidance; offline Day Three fixture before startup only',
            'human_play_claim':False,'physical_gamepad_claim':False,'native_windows_performance_claim':False,
            'fixture':self.fixture,'checks':self.checks,'results':self.results,'captures':self.captures,'telemetry_sessions':self.telemetry_sessions,
            'source_unchanged_during_capture':self.started_hashes==hashes(),'release_note':self.release_note}
        dump(self.out/'wormhole-validation-summary.json',summary)
        dump(self.out/'source-hashes-after.json',hashes())

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ready',action='store_true');p.add_argument('--prepare-only',action='store_true')
    p.add_argument('--release-note',default='');p.add_argument('--mode',choices=['trial','recovery'],default='trial');p.add_argument('--out',required=True);p.add_argument('--display',type=int,default=630)
    args=p.parse_args();out=Path(args.out).resolve()
    if not out.is_relative_to(BASE_OUT.resolve()):p.error('Evidence must remain under docs/qa/v5/wormhole-native')
    if out.exists():p.error('Use a new evidence directory')
    if args.display<630:p.error('Use unused isolated Xorg display >=630')
    if not args.prepare_only and (not args.ready or not args.release_note):p.error('Explicit GUI/source freeze release required')
    out.mkdir(parents=True)
    run='wormhole-'+args.mode+'-'+str(time.time_ns())
    os.environ.update(SC_QA_RUN=run,SC_QA_OUT=str(out),SC_QA_DISPLAY=str(args.display),SC_QA_RESOLUTION='1920x1080',SC_QA_XORG_CONFIG=str(ROOT/'tools/xorg_native_1920.conf'),SC_QA_START_WAIT='5')
    if args.prepare_only:
        info=seed_fixture(out,ROOT/'.runtime'/run,'wormhole-day-three');print(json.dumps(info,ensure_ascii=False));return
    capture=WormholeCapture(args)
    try:
        print(json.dumps({'ready':True,'out':str(out),'window':capture.ready['geometry']},ensure_ascii=False),flush=True)
        getattr(capture,args.mode)()
    except Exception as exc:
        capture.status='failed';dump(out/'wormhole-harness-error.json',{'error':repr(exc)})
        try:capture.shot('failure-last-window')
        except Exception:pass
        raise
    finally:capture.close()

if __name__=='__main__':main()
