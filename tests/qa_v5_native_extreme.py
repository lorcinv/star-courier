#!/usr/bin/env python3
"""Controlled pilot-v3 native QA at normal wall time.

Run only after explicit production/source-hash and exclusive GUI release:
  python tests/qa_v5_native_extreme.py --ready --fixture reinforced --release-note '...'

A separate QA save is generated BEFORE Xorg/game startup. It uses the actual
profile designs and real catalog purchases, backed by a disclosed QA-only
endowment. This is not a naturally earned player build, balanced delivery,
human-play test, or performance benchmark. Runtime inputs are real XTest events.
Production source, art, and existing drivers are never changed by this harness.

JSON commands: existing qa_native_regression inputs plus hold/release (OS keys),
capture_start/capture_stop (real Godot Master PCM), mark, ledger_baseline,
check_ledger, and check_saved. All runtime save access is read-only. This harness
cannot author or replace a save after the native game has started.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

import qa_v5_native_dialogue as dialogue
import qa_v5_native_handoff as handoff

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_OUT = ROOT / 'docs/qa/v5/extreme-native'
QA_ENTRY = 'res://tools/qa_native_observer.gd'
FIXTURES = ['standard', 'reinforced', 'drill-on', 'drill-off', 'shields-off', 'starter-route']


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def hashes():
    values = handoff.hashes()
    for name in ['tests/qa_v5_native_extreme.py', 'tools/capture_native_pilot_delivery.py',
                 'tools/qa_native_observer.gd','tools/drill_approach_probe.gd','tools/extreme_build_probe.gd']:
        values[name] = hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
    return values


def ledger(saved):
    # A completed trial may update last_trials; dialogue completion may update
    # story presentation. Neither is a business debit or formal settlement.
    keys = handoff.LEDGER_KEYS + ['day', 'phase', 'reputation', 'active_contract_id', 'in_flight', 'contracts']
    return {k: saved.get(k) for k in keys}


SEED_SCRIPT = r'''extends SceneTree
const Econ = preload("res://scripts/economy.gd")
const Profile = preload("res://scripts/pilot_extreme_profile.gd")
const Expanded = preload("res://scripts/parts_expanded.gd")
const DrillProbe = preload("res://tools/drill_approach_probe.gd")
func _initialize() -> void:
 var args = OS.get_cmdline_user_args()
 var fixture = args[0]
 var e = Econ.new();e.enable_extreme_mode()
 var design:Array = Profile.reinforced_design() if fixture == "reinforced" else Profile.starter_design()
 var launcher:Array = Profile.starter_launcher() if fixture == "starter-route" else []
 if fixture in ["drill-on", "drill-off", "shields-off"]:
  design=DrillProbe.design(fixture != "drill-off",fixture != "shields-off")
 e.starter_stock(design,launcher)
 e.credits=10000;e.phase="night"
 var costs:Array=[]
 var missing:Dictionary=e.missing_parts(design,launcher)
 for type in missing:
  for i in int(missing[type]):
   var spec:Dictionary=Expanded.catalog()[type]
   var purchase:Dictionary=e.buy_part(type,spec)
   if not purchase.ok:push_error("Fixture catalog purchase rejected");quit(2);return
   costs.append({"type":type,"cost":int(spec.price)})
 e.phase="morning"
 if fixture != "starter-route":
  for order in e.contracts:
   order.name="QA 对照跑道 · 非平衡配送";order.destination_name="QA 远端观测点"
   order.hazards=[];order.pilot_gates=[];order.distance=10000.0;order.boundary_y=10000.0
   order.pilot_altitude=0.0;order.destination_y=0.0;order.time_limit=60.0;order.deadline=60.0;order.pilot_drag=0.0
   order.qa_controlled_fixture=true
   if fixture in ["drill-on", "drill-off", "shields-off"]:
    order.merge(DrillProbe.course_route(),true)
    order.name="QA 钻切跑道";order.risk="测试专用 · 非平衡配送"
 var settings={"reduced_motion":false,"pixel_density":"balanced"}
 if not e.missing_parts(design,launcher).is_empty():push_error("Fixture inventory mismatch");quit(3);return
 if not e.save_state(design,launcher,settings):push_error(e.save_error);quit(4);return
 var info={"fixture":fixture,"save":ProjectSettings.globalize_path("user://savegame.json"),
  "qa_endowment":10000,"catalog_purchases":costs,"credits_after_purchases":e.credits,
  "inventory":e.inventory,"design":design,"launcher":launcher,"contracts":e.contracts,
  "mutations_before_native_process_only":true,"live_physics_mutation":false}
 var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(info,"  ",true,true));file.close()
 print("QA_FIXTURE_READY ",JSON.stringify(info));quit()
'''


def seed_fixture(out, runtime, fixture):
    if runtime.exists():
        raise RuntimeError('Use an entirely fresh runtime; refusing to replace an existing save: '+str(runtime))
    for subdir in ['home', 'data', 'config', 'cache']:
        (runtime/subdir).mkdir(parents=True)
    script = out/'seed-qa-fixture.gd'
    script.write_text(SEED_SCRIPT)
    env = dict(os.environ, HOME=str(runtime/'home'), XDG_DATA_HOME=str(runtime/'data'),
               XDG_CONFIG_HOME=str(runtime/'config'), XDG_CACHE_HOME=str(runtime/'cache'))
    args = ['godot', '--headless', '--path', str(ROOT), '--script', str(script), '--', fixture, str(out/'fixture.json')]
    result = subprocess.run(args, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    (out/'fixture-generation.log').write_text(result.stdout)
    result.check_returncode()
    fixture_info = json.loads((out/'fixture.json').read_text())
    seeded = pathlib.Path(fixture_info['save'])
    save_copy = out/'before-native-seeded-save.json'
    save_copy.write_bytes(seeded.read_bytes())
    fixture_info['seeded_save_sha256'] = hashlib.sha256(save_copy.read_bytes()).hexdigest()
    fixture_info['seeded_before_native_unix'] = time.time()
    dump(out/'fixture.json', fixture_info)
    return fixture_info


class NativeExtreme(dialogue.NativeDialogue):
    def __init__(self, args):
        run = os.environ.setdefault('SC_QA_RUN', 'v3-extreme-'+args.fixture+'-'+str(time.time_ns()))
        os.environ.setdefault('SC_QA_DISPLAY', '455')
        os.environ.setdefault('SC_QA_OUT', str(BASE_OUT/(args.fixture+'-'+str(time.time_ns()))))
        os.environ.setdefault('SC_QA_RESOLUTION', '1280x800')
        self.target = pathlib.Path(os.environ['SC_QA_OUT'])
        if not self.target.is_absolute():self.target=ROOT/self.target
        self.target = self.target.resolve()
        if not self.target.is_relative_to(BASE_OUT.resolve()):
            raise ValueError('Extreme evidence must stay under '+str(BASE_OUT))
        if int(os.environ['SC_QA_DISPLAY']) < 450:
            raise ValueError('Use a fresh dedicated display >=450')
        self.target.mkdir(parents=True, exist_ok=True)
        if args.fixture=='starter-route':
            if (ROOT/'.runtime'/run).exists():raise RuntimeError('Fresh production starter requires unused runtime')
            self.fixture={'fixture':'starter-route','fresh_production_game':True,'qa_endowment':0,'preseeded':False}
            dump(self.target/'fixture.json',self.fixture)
        else:
            self.fixture=seed_fixture(self.target,ROOT/'.runtime'/run,args.fixture)
        self.baselines={};self.held=set();self.key_trace=[];self.display=None;self.captured_this_process=False
        dialogue.hashes=hashes
        # Freeze a private byte-derived copy of the verified native driver.
        # Exactly two substitutions: repo root (copy is deeper) and one allowed
        # entry resource. The shared driver remains byte-for-byte untouched.
        original=(ROOT/'tools/qa_native_regression.py').read_text()
        root_line='ROOT = pathlib.Path(__file__).resolve().parents[1]'
        guard="if entry != 'res://tools/qa_audio_game.gd':"
        if original.count(root_line)!=1 or original.count(guard)!=1:
            raise RuntimeError('Verified native driver structure changed; review before adapting')
        private=original.replace(root_line,'ROOT = pathlib.Path('+repr(str(ROOT))+')').replace(guard,'if entry != '+repr(QA_ENTRY)+':')
        driver=self.target/'native-driver-snapshot.py';driver.write_text(private)
        env=dict(os.environ)
        env.setdefault('SC_QA_XORG_CONFIG',str(ROOT/'tests/xorg_v5_hud_4k.conf'))
        env['SC_QA_ENTRY_SCRIPT']=QA_ENTRY
        self.out=self.target;self.audio_path=self.out/'master-recording.wav'
        env['SC_QA_AUDIO_OUTPUT']=str(self.audio_path)
        env['SC_QA_TELEMETRY_OUTPUT']=str(self.out/'native-telemetry.json')
        self.env=env;self.started_hashes=hashes()
        self.checks=[];self.marks=[];self.commands=[];self.captures=[];self.capture=None
        self.child=subprocess.Popen([sys.executable,str(driver)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            text=True,bufsize=1,env=env)
        self.ready=self.receive()
        dump(self.out/'dialogue-source-metadata.json',{
            'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            'sha256':self.started_hashes,'runtime':run,'fixed_fps':False,'speedup':False,'human_play_claim':False,
            'qa_entry':QA_ENTRY,'native_driver_snapshot_sha256':hashlib.sha256(driver.read_bytes()).hexdigest(),
            'native_driver_substitutions':['absolute project root','single exact permitted read-only QA entry'],
            'telemetry':'20 Hz capped read-only samples in native process; one JSON write on process exit'})
        self.x11=C.CDLL('libX11.so.6');self.xtst=C.CDLL('libXtst.so.6')
        self.x11.XOpenDisplay.argtypes=[C.c_char_p];self.x11.XOpenDisplay.restype=C.c_void_p
        self.x11.XStringToKeysym.argtypes=[C.c_char_p];self.x11.XStringToKeysym.restype=C.c_ulong
        self.x11.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];self.x11.XKeysymToKeycode.restype=C.c_uint
        self.x11.XFlush.argtypes=[C.c_void_p];self.x11.XCloseDisplay.argtypes=[C.c_void_p]
        self.xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
        self.display=self.x11.XOpenDisplay(('localhost:'+self.env['SC_QA_DISPLAY']).encode())
        if not self.display:raise RuntimeError('Isolated native display unavailable')
        self.telemetry_sessions=[]
        self.release_note=args.release_note
        self._metadata()

    def _metadata(self):
        for suffix in ['source-metadata.json','validation-summary.json','command-events.jsonl']:
            old=self.out/('dialogue-'+suffix)
            if old.exists():old.replace(self.out/('extreme-'+suffix))
        path=self.out/'extreme-source-metadata.json'
        if path.exists():
            data=json.loads(path.read_text())
            data.update({'method':'Controlled offline QA fixture before startup; actual unchanged main scene; native XTest input; actual Master PCM',
                'fixture':self.fixture,'release_note':self.release_note,
                'claims_excluded':['human play fairness','balanced extreme delivery','native Windows performance','runtime state or velocity injection'],
                'save_mutation':'QA fixture only, completed before game process; runtime saves read-only'})
            dump(path,data)

    def send(self, command):
        forwarded=dict(command);forwarded.pop('quit',None)
        return super().send(forwarded)

    def set_keys(self,wanted):
        for name,down in [(x,False) for x in sorted(self.held-wanted)]+[(x,True) for x in sorted(wanted-self.held)]:
            code=self.x11.XKeysymToKeycode(self.display,self.x11.XStringToKeysym(name.encode()))
            if not code:raise ValueError('Unknown keysym '+name)
            at=time.time();self.xtst.XTestFakeKeyEvent(self.display,code,int(down),0)
            self.key_trace.append({'unix_seconds':at,'monotonic_seconds':time.monotonic(),'key':name,'down':down,'x_keycode':code})
        self.x11.XFlush(self.display);self.held=set(wanted)
        dump(self.out/'held-key-input-trace.json',self.key_trace)

    def execute(self, command):
        original=dict(command);begin=time.time()
        if 'capture_start' in command:
            if self.captured_this_process:raise RuntimeError('Restart game before another real Master tap')
            self.start_capture(command.pop('capture_start'));self.captured_this_process=True
        if 'mark' in command:self.marks.append({'label':command.pop('mark'),'unix_seconds':time.time()})
        wanted=(self.held-set(command.pop('release',[])))|set(command.pop('hold',[]))
        self.set_keys(wanted)
        checks={k:command.pop(k) for k in ['ledger_baseline','check_ledger','check_saved'] if k in command}
        stop=command.pop('capture_stop',False)
        result=self.send(command)
        if command.get('close'):result['telemetry']=self.archive_telemetry()
        if 'start' in command:self.captured_this_process=False
        if checks:
            saved=self.send({'state':True,'sleep':0})['state'];results=[]
            if 'ledger_baseline' in checks:
                key=str(checks['ledger_baseline']);self.baselines[key]=ledger(saved)
                dump(self.out/(key+'-ledger-baseline.json'),self.baselines[key]);result['ledger_baseline']=key
            if 'check_ledger' in checks:
                key=str(checks['check_ledger']);observed=ledger(saved);expected=self.baselines[key]
                results.append({'test':'Free trial ledger unchanged from '+key,'passed':observed==expected,
                    'changed_fields':[k for k in expected if expected[k]!=observed[k]],'observed':observed})
            if 'check_saved' in checks:
                spec=checks['check_saved'];value=saved;missing=None
                try:
                    for key in spec['path']:value=value[key]
                except (KeyError,IndexError,TypeError):value=None;missing=spec['path']
                results.append({'test':spec['test'],'passed':missing is None and value==spec['equals'],'observed':value,'missing_path':missing})
            self.checks.extend(results);result['checks']=results
        if stop:result['capture']=self.stop_capture()
        result['held_os_keys']=sorted(self.held)
        event={'begin_unix_seconds':begin,'end_unix_seconds':time.time(),'command':original,'result':result}
        self.commands.append(event)
        with (self.out/'extreme-command-events.jsonl').open('a') as stream:stream.write(json.dumps(event,ensure_ascii=False)+'\n')
        if any(not x['passed'] for x in result.get('checks',[])):
            raise AssertionError('Native evidence check failed; stop this run and inspect logged screenshot/save')
        return result

    def archive_telemetry(self):
        source=self.out/'native-telemetry.json'
        if not source.exists():return {'available':False}
        target=self.out/('native-telemetry-session-%02d.json'%(len(self.telemetry_sessions)+1))
        source.replace(target)
        data=json.loads(target.read_text())
        flight=[x for x in data['samples'] if 'elapsed' in x]
        running=[x for x in flight if x.get('page')=='flight' and x.get('status')=='running']
        nearest={}
        for at in [1,3,5,10,19.7,20,22,24]:
            if running:
                x=min(running,key=lambda row:abs(row['elapsed']-at))
                nearest[str(at)]={'actual_elapsed':x['elapsed'],'offset_seconds':x['elapsed']-at,
                    'completed_ticks':x['completed_ticks'],'telemetry':x['telemetry'],'parts':x['parts'],'obstacles':x['obstacles']}
        item={'path':str(target),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
            'samples':len(data['samples']),'capped':data['capped'],'nearest_observed_samples':nearest,
            'final_observed':flight[-1] if flight else None}
        self.telemetry_sessions.append(item)
        dump(self.out/'telemetry-observation-index.json',self.telemetry_sessions)
        return {k:v for k,v in item.items() if k not in ['nearest_observed_samples','final_observed']}

    def close(self):
        if self.display:
            self.set_keys(set());self.x11.XCloseDisplay(self.display);self.display=None
        super().close();self.archive_telemetry();self._metadata()
        path=self.out/'extreme-validation-summary.json'
        data=json.loads(path.read_text());data.update({'fixture':self.fixture,'release_note':self.release_note,
            'method':'Automated native XTest, QA fixture saved before startup, real Master audio, read-only runtime saves',
            'telemetry_sessions':self.telemetry_sessions,'runtime_state_mutation':False,'time_scale':1,'human_play_claim':False,'full_extreme_delivery_claim':False})
        dump(path,data)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready',action='store_true')
    parser.add_argument('--fixture',choices=FIXTURES,required=True)
    parser.add_argument('--release-note',required=True,help='Exact coordinating source/hash/GUI release reference')
    parser.add_argument('--replay',type=pathlib.Path)
    args=parser.parse_args()
    if not args.ready:parser.error('Explicit source/hash/GUI release required; preparation alone does not authorize launch')
    capture=NativeExtreme(args)
    try:
        print(json.dumps(capture.ready,ensure_ascii=False),flush=True)
        commands=json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for original in commands:
            result=capture.execute(dict(original));print(json.dumps(result,ensure_ascii=False),flush=True)
            if original.get('quit'):break
    finally:capture.close()


if __name__=='__main__':main()
