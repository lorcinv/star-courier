#!/usr/bin/env python3
"""Native pilot-v2 acceptance capture, at ordinary wall time.

Run only after the final visual/physics build owns the exclusive GUI slot:
  SC_QA_DISPLAY=380 SC_QA_RUN=unique-name python tests/qa_v5_native_ascent.py --phase trial --ready
  SC_QA_DISPLAY=381 SC_QA_RUN=another-name python tests/qa_v5_native_ascent.py --phase formal --ready

A fresh native process receives real XTest keys/pointer events. Offline deterministic
simulation prepares an OS-key schedule and audits read-only, game-written saves.
It never controls the live game, changes a save, or sets engine/screen timing.
"""
import argparse
import hashlib
import json
import math
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from capture_native_pilot_delivery import NativePilotCapture


def ledger(state):
    # Trial history is deliberately excluded: a free trial should save its report.
    return {k: state[k] for k in ['credits', 'day', 'deliveries', 'jobs_today',
        'reputation', 'history', 'settled_ids', 'active_contract_id', 'in_flight',
        'inventory', 'research', 'contracts']}


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


class AscentRun:
    def __init__(self, phase):
        self.phase = phase
        self.checks = []
        self.results = {}
        self.c = NativePilotCapture()
        self.started = time.monotonic()
        sources = ['scripts/main.gd', 'scripts/economy.gd', 'scripts/game_hud.gd',
            'scripts/world_view_2d.gd', 'scripts/pilot_ascent_profile.gd',
            'scripts/pilot_ascent_simulation.gd', 'scripts/ascent_backdrop_2d.gd',
            'assets/2d_v5/ascent_background.gdshader', 'assets/2d_v5/ascent/atmosphere-tall.png',
            'assets/2d_v5/ascent/sky-palette-source256.json', 'tools/pilot_keyboard_reference.gd',
            'tools/capture_native_pilot_delivery.py', 'tests/qa_v5_native_ascent.py']
        self.hashes = {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}

    def check(self, label, condition, detail=None):
        item = {'test': label, 'passed': bool(condition), 'detail': detail}
        self.checks.append(item)
        print(json.dumps(item, ensure_ascii=False), flush=True)
        if not condition:
            raise AssertionError(label)

    def prepare(self):
        c = self.c
        self.check('fresh isolated save', c.ready['state'] == {'saved': False})
        c.send({'click': [90, 715], 'shot': '02-counter'})
        accepted = c.send({'click': [1010, 523], 'state': True, 'snapshot': '03-accepted'})['state']
        order = next(x for x in accepted['contracts'] if x['contract_id'] == accepted['active_contract_id'])
        self.check('new order uses genuine v2 ascent route',
            order['control_version'] == 'pilot-v2' and order['distance'] == 520 and order['destination_y'] == -150, order)
        self.check('starter craft has exactly eight modules', len(accepted['design']) == 8)
        c.send({'click': [270, 715], 'shot': '04-workbench', 'snapshot': '04-preflight'})
        route = dict(order, battery_capacity_multiplier=1 + .15 * accepted['research'])
        self.spec = {'route': route, 'design': accepted['design'], 'launcher': accepted['launcher'],
            'seed': accepted['day'] * 100 + int(order['id']) * 3 + int(order['contract_id'].endswith('B')),
            'boost_start_tick': 210, 'boost_end_tick': 240}
        # Select the existing Balanced setting through native UI, never a save edit.
        c.send({'click': [434, 83], 'shot': '04-settings-before'})
        c.send({'actions': [{'click': [650, 483]}, {'click': [650, 554]},
            {'key': 'Escape'}], 'snapshot': '04-balanced'})
        self.before = c.send({'state': True, 'sleep': 0})['state']
        self.check('balanced pixel density selected through native UI',
            self.before['settings']['pixel_density'] == 'balanced', self.before['settings'])
        if self.phase == 'trial':
            sized = c.send({'resize': [1920, 1080], 'sleep': .8, 'shot': '04-workbench-1080p'})
            self.check('full visual capture is 1920 by 1080',
                sized['geometry']['width'] == 1920 and sized['geometry']['height'] == 1080)
        self.trial_click = [1635, 1035] if self.phase == 'trial' else [995, 715]
        self.contract = order['contract_id']
        return accepted

    def trial(self):
        c = self.c
        reference = c.reference(self.spec, '05-free-ascent')
        save_json(c.out/'05-free-ascent-offline-reference.json', reference)
        self.check('offline OS-key schedule clears v2 route', reference['status'] == 'success')
        self.check('OS-key schedule contains climb, countersteer and brief boost',
            any(x['axis'] < 0 for x in reference['commands']) and
            any(x['axis'] > 0 for x in reference['commands']) and
            any(x['boost'] for x in reference['commands']))
        duration = max(42.0, reference['elapsed'] + 8.0)
        c.send({'record': {'name': '05-free-ascent-full', 'seconds': duration}, 'sleep': .3})
        c.send({'click': self.trial_click, 'sleep': 0})
        start = time.monotonic()
        trace = []
        for index, command in enumerate(reference['commands']):
            target = float(command['time']) + .7
            if index == 0:
                target = 0.0
            time.sleep(max(0, start + target - time.monotonic()))
            wanted = set()
            if command['axis'] < 0: wanted.add('w')
            if command['axis'] > 0: wanted.add('s')
            if command['boost']: wanted.add('Shift_L')
            if command.get('active'): wanted.add('space')
            c.set_keys(wanted)
            trace.append({'wall_seconds': time.monotonic() - start,
                'planned_wall_seconds': target, 'planned_sim_seconds': command['time'],
                'held_os_keys': sorted(wanted),
                'offline_reference_position': [command['x'], command['y']]})
        time.sleep(max(0, start + reference['elapsed'] + 3.0 - time.monotonic()))
        c.set_keys(set())
        result = c.send({'shot': '06-free-trial-receipt', 'snapshot': '06-free-trial-receipt', 'state': True, 'sleep': 0})
        save_json(c.out/'05-free-ascent-os-input-trace.json', trace)
        self.check('free trial preserves money, job quota, inventory and settlement ledger',
            ledger(result['state']) == ledger(self.before),
            {'before': ledger(self.before), 'after': ledger(result['state'])})
        report = result['state']['last_trials'].get(self.contract, {}).get('latest', {})
        self.check('native free trial succeeds intact before deadline',
            report.get('success') and report.get('integrity') == 100 and
            report.get('elapsed', 999) < self.spec['route']['deadline'], report)
        self.check('free trial report is labelled estimate with real energy use',
            report.get('trial') and report.get('energy_j', 0) > 0 and 'estimated_profit' in report, report)
        self.results['trial_report'] = report
        self.results['os_input_schedule_max_lateness_seconds'] = max(x['wall_seconds'] - x['planned_wall_seconds'] for x in trace)
        self.results['recordings'] = c.send({'finish_record': True, 'sleep': 0})['recordings']
        # A continuous 20 second window: no time rescaling or compositing.
        full = c.out/'05-free-ascent-full.mp4'
        excerpt = c.out/'05-free-ascent-continuous-20s.mp4'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(full),
            '-ss', '9', '-t', '20', '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18',
            '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(excerpt)], check=True)
        self.results['excerpt'] = {'path': str(excerpt), 'source_start_seconds': 9,
            'duration_seconds': 20, 'speed_multiplier': 1, 'continuous': True}
        for sec in [2, 8, 17, 26, 31, 36]:
            subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(sec),
                '-i', str(full), '-frames:v', '1', str(c.out/f'frame-{sec:02d}s.png')], check=True)
        self.results['capture_motion_observation'] = frame_holds(full, 1, 31)

    def formal(self):
        c = self.c
        c.send({'click': [1135, 713], 'shot': '05-formal-confirmation'})
        c.deliver({'name': '06-formal-launch-to-pause', 'reference': self.spec,
            'stop_at': 8.5, 'seconds': 15, 'repeat_launch': True})
        paused = c.send({'snapshot': '07-paused-checkpoint', 'state': True, 'sleep': 0})['state']['in_flight']
        self.check('native P leaves a valid v2 autosave checkpoint', paused.get('control_version') == 'pilot-v2' and paused.get('ticks', 0) > 400, {'ticks': paused.get('ticks'), 'elapsed': paused.get('elapsed')})
        c.send({'sleep': 1.2, 'snapshot': '08-paused-stable', 'shot': '08-paused-stable'})
        stable = c.send({'state': True, 'sleep': 0})['state']['in_flight']
        self.check('native pause holds exact input timeline and physics time', paused == stable)
        closed = c.send({'close': True, 'state': True, 'snapshot': '09-closed', 'sleep': 0})
        self.check('native close completes cleanly', not closed['running'])
        snapshot = closed['state']['in_flight']
        c.send({'start': 5, 'shot': '10-restart-paused', 'snapshot': '10-restart-paused', 'sleep': 1.0})
        resumed = c.send({'state': True, 'sleep': 0})['state']['in_flight']
        self.check('v2 native restart preserves the exact saved checkpoint', resumed == snapshot)
        self.finish_formal(resumed)

    def finish_formal(self, snapshot):
        c = self.c
        checkpoint_reference = c.reference({'snapshot': snapshot}, '11-saved-checkpoint-audit')
        self.results['replayed_pause_checkpoint'] = checkpoint_reference['checkpoint']
        result = c.deliver({'name': '12-formal-resumed-to-receipt', 'reference': {'snapshot': snapshot},
            'resume': 'p', 'seconds': 33})
        state = result['state']
        receipt = state['settled_ids'].get(self.contract, {})
        last_input = json.loads(pathlib.Path(result['last_input_checkpoint']).read_text())['in_flight']
        replay = c.reference({'snapshot': last_input, 'mode': 'replay'}, '13-exact-input-replay')
        save_json(c.out/'13-exact-input-replay-result.json', replay)
        tariff = float(last_input['route']['pilot_energy_tariff'])
        bill = math.ceil(replay['energy_used'] * tariff)
        self.check('native receipt equals exact recorded-input replay duration',
            abs(receipt.get('elapsed', -1) - replay['elapsed']) < 1e-8,
            {'native_receipt_seconds': receipt.get('elapsed'), 'replay_seconds': replay['elapsed']})
        self.check('v2 finite energy billed at authoritative route tariff',
            receipt.get('energy') == bill and tariff == .025,
            {'spent_joules': replay['energy_used'], 'tariff': tariff, 'expected_bill': bill, 'native_bill': receipt.get('energy')})
        self.check('formal native flight succeeds intact before deadline',
            receipt.get('success') and receipt.get('integrity') == 100 and
            receipt.get('elapsed', 999) < receipt.get('deadline', 0), receipt)
        self.check('formal flight settles exactly once',
            len(state['history']) == 1 and state['jobs_today'] == 1 and state['deliveries'] == 1 and
            state['credits'] == self.before['credits'] + receipt['profit'] and len(state['settled_ids']) == 1)
        audit = audit_native_timeline(c.out, last_input)
        self.results['exact_native_position_audit'] = audit
        self.check('recorded forces yield a real upward destination and cruise speed',
            -audit['final_position'][1] > 140 and audit['peak_speed'] > 14 and
            audit['capacity_j'] == 6000 and audit['remaining_energy_j'] > 0,
            audit)
        self.check('single physical launch impulse',
            sum('完成压缩供能' in event for event in replay['events']) == 1, replay['events'])
        self.results['formal_receipt'] = receipt
        self.results['formal_replay_telemetry'] = replay['telemetry']
        self.results['recordings'] = c.send({'finish_record': True, 'sleep': 0})['recordings']
        c.send({'close': True, 'snapshot': '14-final-close', 'state': True, 'sleep': 0})
        c.send({'start': 5, 'snapshot': '15-final-restart', 'shot': '15-final-restart'})
        final = c.send({'state': True, 'sleep': 0})['state']
        self.check('final native restart preserves unique settlement', ledger(final) == ledger(state))

    def close(self):
        self.c.close()
        save_json(self.c.out/'validation-summary.json', {
            'method': 'Automated native OS keyboard/pointer input via XTest; read-only exact-input replay audit',
            'phase': self.phase, 'human_play_claim': False, 'engine_fps_claim': False,
            'time_scale': 1, 'video_capture_fps': 24, 'no_fixed_fps_or_save_mutation': True,
            'source_sha256': self.hashes, 'wall_seconds': time.monotonic() - self.started,
            'checks': self.checks, 'results': self.results})


def audit_native_timeline(out, snapshot):
    """Independent read-only replay, so receiver cleanup cannot erase peak speed."""
    script = out/'audit-native-timeline.gd'
    spec = out/'audit-native-timeline.json'
    save_json(spec, snapshot)
    script.write_text('''extends SceneTree
const Sim = preload("res://scripts/pilot_ascent_simulation.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
func _initialize() -> void:
 var s = Sim.new()
 var data:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
 var timeline = Timeline.new()
 if not timeline.restore(data.input_commands, int(data.ticks)):quit(2);return
 s.configure(data.design, data.launcher, data.route, int(data.seed))
 var peak:float = 0.0
 var previous_speed:float = 0.0
 var samples:Array = []
 for tick in range(4800):
  var command:Dictionary = timeline.state_at(tick)
  s.set_pilot_input(int(command.axis_q), bool(command.boost), bool(command.active))
  previous_speed = float(s.telemetry.speed)
  s.step(1.0/60.0)
  peak = maxf(peak, float(s.telemetry.speed))
  if tick % 60 == 0:
   samples.append({"tick":tick+1,"elapsed":s.elapsed,"position":[s.cargo_position().x,s.cargo_position().y],"speed":s.telemetry.speed,"energy_used":s.telemetry.energy_used,"remaining_energy":s.total_energy(),"axis_q":command.axis_q,"boost":command.boost})
  if s.status != "running":break
 s.finalize_settlement()
 print("AUDIT_JSON:",JSON.stringify({"status":s.status,"elapsed":s.elapsed,"final_position":[s.cargo_position().x,s.cargo_position().y],"peak_speed":peak,"pre_receipt_speed":previous_speed,"capacity_j":s.telemetry.battery_capacity,"energy_used_j":s.telemetry.energy_used,"remaining_energy_j":s.total_energy(),"samples":samples}))
 quit(0 if s.status == "success" else 1)
''')
    runtime = out/'reference-runtime'
    env = dict(os.environ, HOME=str(runtime/'home'), XDG_DATA_HOME=str(runtime/'data'),
        XDG_CONFIG_HOME=str(runtime/'config'), XDG_CACHE_HOME=str(runtime/'cache'))
    result = subprocess.run(['godot', '--headless', '--path', str(ROOT), '--script', str(script), '--', str(spec)],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=40)
    (out/'audit-native-timeline.log').write_text(result.stdout)
    result.check_returncode()
    audit = json.loads(next(x.split('AUDIT_JSON:', 1)[1] for x in result.stdout.splitlines() if x.startswith('AUDIT_JSON:')))
    save_json(out/'audit-native-timeline-result.json', audit)
    return audit


def frame_holds(path, start, duration):
    """Identify long visually identical spans; capture rate is not engine FPS."""
    import numpy as np
    raw = subprocess.check_output(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-ss', str(start),
        '-i', str(path), '-t', str(duration), '-vf', 'scale=160:100,format=gray', '-f', 'rawvideo', '-'])
    frames = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 100, 160)
    diff = np.abs(frames[1:].astype(np.int16) - frames[:-1].astype(np.int16)).mean(axis=(1, 2))
    # Lossy encoding creates tiny pixel changes even during holds.
    held = diff < .05
    runs, run_start = [], None
    for i, value in enumerate(held.tolist() + [False]):
        if value and run_start is None: run_start = i
        if not value and run_start is not None:
            if i - run_start >= 12:
                runs.append({'start_seconds': start + run_start / 24,
                    'duration_seconds': (i - run_start) / 24})
            run_start = None
    return {'method': 'Consecutive decoded grayscale frame differences, threshold 0.05/255 at 160x100',
        'range_seconds': [start, start + duration], 'holds_at_least_half_second': runs,
        'capture_fps': 24, 'engine_fps_claim': False,
        'limitation': 'This detects visible holds in the captured scene; it is not an engine performance benchmark.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', choices=['trial', 'formal'], required=True)
    parser.add_argument('--ready', action='store_true', help='Explicitly assert final physics/visuals and exclusive GUI slot are ready')
    args = parser.parse_args()
    if not args.ready:
        parser.error('Wait for the parent to confirm final physics/visuals and the exclusive GUI slot, then pass --ready.')
    os.environ.setdefault('SC_QA_DISPLAY', '380' if args.phase == 'trial' else '381')
    os.environ.setdefault('SC_QA_RUN', 'ascent-native-' + args.phase + '-' + str(time.time_ns()))
    os.environ.setdefault('SC_QA_OUT', 'docs/qa/v5/ascent-native/' + args.phase + '-01')
    run = AscentRun(args.phase)
    try:
        run.prepare()
        getattr(run, args.phase)()
    finally:
        run.close()


if __name__ == '__main__':
    main()
