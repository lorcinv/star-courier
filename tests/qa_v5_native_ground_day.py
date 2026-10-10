#!/usr/bin/env python3
"""Fresh ordinary ground-city-v1 native acceptance; all live actions are OS input.

Requires explicit frozen-source/exclusive-GUI release. The sidecar only observes.
Offline pilot-v3 uses the exact saved route, craft, launcher, seed and 60 Hz input
history; it never silently dispatches v3 through the v1 simulator. No endowed
fixture, live controller calls, save editing, fixed FPS, speedup, human-play
fairness claim or physical-gamepad claim. --trial-only captures the first flight.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

import qa_v5_native_cooperative as cooperative
import qa_v5_native_handoff as handoff

ROOT = Path(__file__).resolve().parents[1]
BASE_OUT = ROOT / 'docs/qa/v5/ground-native'
QA_FILES = ['tests/qa_v5_native_ground_day.py', 'tools/qa_ground_observer.gd',
            'tools/pilot_ground_reference.gd', 'tests/test_ground_route.gd',
            'tests/qa_v5_native_cooperative.py', 'tests/qa_v5_native_locomotion.py',
            'tools/qa_native_regression.py']


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def hashes():
    result = handoff.hashes()
    for name in QA_FILES:
        result[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    return result


def business_ledger(state):
    keys = handoff.LEDGER_KEYS + ['reputation', 'day', 'phase', 'workshop_tier',
                                 'contracts', 'active_contract_id', 'in_flight']
    return {key: state.get(key) for key in keys}


class GroundDay(cooperative.NativeCooperative):
    def __init__(self, args):
        cooperative.BASE_OUT = BASE_OUT
        cooperative.QA_ENTRY = 'res://tools/qa_ground_observer.gd'
        cooperative.hashes = hashes
        out = Path(os.environ['SC_QA_OUT'])
        if not out.is_absolute(): out = ROOT / out
        if out.exists(): raise RuntimeError('Use a fresh evidence directory; historical captures are immutable')
        super().__init__(args)
        self.started_at = time.monotonic()
        self.results = {}
        self.status = 'running'
        dump(self.out / 'source-hashes-before.json', self.started_hashes)

    def check(self, test, condition, detail=None):
        row = {'test': test, 'passed': bool(condition), 'detail': detail}
        self.checks.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        dump(self.out / 'ground-checks.json', self.checks)
        if not condition: raise AssertionError(test)

    def state(self):
        return self.execute({'state': True, 'sleep': 0})['state']

    def wait(self, predicate, label, timeout=40):
        deadline = time.monotonic() + timeout
        while True:
            observed = self.observe()
            if predicate(observed): return observed
            if time.monotonic() > deadline:
                dump(self.out / 'timed-out-observation.json', observed)
                raise AssertionError('Read-only native wait timed out: ' + label)
            time.sleep(.01)

    def click_view(self, key, sleep=.25, repeat=1, text=None):
        for attempt in range(14):
            observed = self.observe()
            found = [b for b in observed['buttons'] if b['view_key'] == key and not b['disabled']
                     and (text is None or b['text'] == text)]
            if len(found) != 1: raise AssertionError('Expected one active visible button: ' + key + '; ' + repr(found))
            x, y, w, h = found[0]['rect']
            if 0 <= y + h / 2 < observed['window_size'][1] and 0 <= x + w / 2 < observed['window_size'][0]:
                point = [x + w / 2, y + h / 2]
                if repeat > 1:
                    return self.execute({'actions': [{'click': point, 'sleep': 0} for _ in range(repeat)], 'sleep': sleep})
                return self.execute({'click': point, 'sleep': sleep})
            self.execute({'click': [observed['window_size'][0] - 50, observed['window_size'][1] / 2, 5 if y > 0 else 4], 'sleep': .08})
        raise AssertionError('Button remains outside viewport: ' + key)

    def click_hub(self, index, sleep=.25):
        observed = self.observe()
        if observed['page'] != 'hub' or observed['dialogue_open']:
            raise AssertionError('Hub navigation must be an actual unobstructed shop button')
        buttons = sorted([b for b in observed['buttons'] if b['text'] == '' and b['view_key'] == ''
                          and not b['disabled'] and b['rect'][2] > 100], key=lambda b: b['rect'][0])
        if len(buttons) != 3: raise AssertionError('Expected the three visible native shop navigation buttons')
        x, y, w, h = buttons[index]['rect']
        return self.execute({'click': [x + w / 2, y + h / 2], 'sleep': sleep})

    def screenshot(self, name):
        return self.execute({'shot': name, 'snapshot': name, 'sleep': .05})

    def archive_telemetry(self):
        source = self.out / 'native-telemetry.json'
        if not source.exists(): return {'available': False}
        target = self.out / ('native-telemetry-session-%02d.json' % (len(self.telemetry_sessions) + 1))
        source.replace(target)
        data = json.loads(target.read_text())
        item = {'path': str(target), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                'samples': len(data['samples']), 'capped': data['capped']}
        self.telemetry_sessions.append(item)
        dump(self.out / 'telemetry-observation-index.json', self.telemetry_sessions)
        return item

    def reference(self, spec, name):
        spec_path = self.out / (name + '-spec.json')
        dump(spec_path, spec)
        # Independent offline process and its own scratch HOME. No native save path.
        folder = self.out / 'offline-reference-runtime'
        for sub in ['home', 'data', 'config', 'cache']: (folder / sub).mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, HOME=str(folder / 'home'), XDG_DATA_HOME=str(folder / 'data'),
                   XDG_CONFIG_HOME=str(folder / 'config'), XDG_CACHE_HOME=str(folder / 'cache'))
        p = subprocess.run(['godot', '--headless', '--path', str(ROOT), '--script',
                            'res://tools/pilot_ground_reference.gd', '--', '--spec', str(spec_path)],
                           env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        (self.out / (name + '-reference.log')).write_text(p.stdout)
        p.check_returncode()
        line = next(line for line in p.stdout.splitlines() if line.startswith('GROUND_REFERENCE_JSON:'))
        result = json.loads(line.split(':', 1)[1])
        if result.get('error'): raise AssertionError(result['error'])
        dump(self.out / (name + '-reference.json'), result)
        return result

    def reference_spec(self, state):
        order = next(x for x in state['contracts'] if x['contract_id'] == state['active_contract_id'])
        seed = state['day'] * 100 + int(order['id']) * 3 + int(order['contract_id'].endswith('B'))
        route = dict(order, variation=float(order.get('variation', 1)),
                     battery_capacity_multiplier=1 + .15 * state['research'], seed=seed)
        return {'route': route, 'design': state['design'], 'launcher': state['launcher'], 'seed': seed}

    def finish_dialogue(self, label, timeout=35):
        observed = self.wait(lambda x: x['dialogue_open'], label + ' opens', timeout)
        dump(self.out / (label + '-dialogue.json'), observed)
        # Real customer dialogue is opened, then native Enter reads each line.
        for _ in range(24):
            if not self.observe()['dialogue_open']: break
            self.execute({'key': 'Return', 'sleep': .16})
        self.wait(lambda x: not x['dialogue_open'], label + ' closes', 5)

    def accept(self, contract):
        # A pending return can legitimately greet the player before the next order.
        deadline = time.monotonic() + 50
        while self.observe()['page'] != 'contracts' or self.observe()['dialogue_open']:
            if self.observe()['dialogue_open']:
                self.finish_dialogue(contract + '-prior-ground-return')
            if time.monotonic() > deadline: raise AssertionError('Physical counter arrival did not open contracts')
            time.sleep(.025)
        self.click_view('action:accept_contract:' + json.dumps(contract))
        self.finish_dialogue(contract + '-accept')
        self.wait(lambda x: x['overlay_open'] or x['cargo_loaded'], 'cooperative loading follows dialogue')
        self.screenshot(contract + '-cooperative-loading')
        if self.observe()['overlay_open']:
            self.execute({'key': 'Escape', 'sleep': .3})
        self.wait(lambda x: x['cargo_loaded'] and x['page'] == 'workshop' and not x['overlay_open'], 'cargo durably loaded')
        saved = self.state()
        self.check(contract + ' accepted and loaded by real dialogue/tablet UI',
                   saved['active_contract_id'] == contract and self.observe()['cargo_loaded'])
        return saved

    @staticmethod
    def wanted(command):
        result = set()
        if command['axis_q'] < 0: result.add('w')
        if command['axis_q'] > 0: result.add('s')
        if command['boost']: result.add('Shift_L')
        if command['active']: result.add('space')
        return result

    def drive(self, reference, label, stop_tick=None):
        self.check(label + ' offline schedule succeeds with actual ordinary build', reference['status'] == 'success',
                   {'elapsed': reference['elapsed'], 'energy': reference['energy_used']})
        commands = reference['commands']
        next_command = 0
        transitions = []
        started = time.monotonic()
        previous_ticks = -1
        receiver_shot = False
        while True:
            observed = self.observe()
            if observed['page'] != 'flight': raise AssertionError('Unexpected page during native drive: ' + observed['page'])
            ticks = observed['completed_ticks']
            if ticks < previous_ticks: raise AssertionError('Native simulation clock went backwards')
            previous_ticks = ticks
            if stop_tick is not None and ticks >= stop_tick:
                self.execute({'key': 'p', 'sleep': .15})
                self.set_keys(set())
                observed = self.wait(lambda x: x['paused'], 'native P pauses')
                break
            if observed.get('sim_status') != 'running':
                self.set_keys(set())
                dump(self.out / (label + '-terminal-observation.json'), observed)
                self.execute({'shot': label + '-receiver', 'sleep': 0})
                self.check(label + ' native flight succeeds', observed.get('sim_status') == 'success',
                           {'status': observed.get('sim_status'), 'position': observed.get('position'),
                            'telemetry': observed.get('telemetry'), 'events': observed.get('events')})
                break
            while next_command < len(commands) and commands[next_command]['tick'] <= ticks:
                command = commands[next_command]
                self.set_keys(self.wanted(command))
                transitions.append({'planned_tick': command['tick'], 'observed_tick': ticks,
                                    'unix_seconds': time.time(), 'keys': sorted(self.held)})
                next_command += 1
            if not receiver_shot and observed.get('position', [0])[0] > 335:
                # Screenshot is captured with OS input still held; clock-based scheduling resumes afterwards.
                self.execute({'shot': label + '-receiver-approach', 'sleep': 0})
                receiver_shot = True
            if time.monotonic() - started > 100:
                raise AssertionError('Native route did not reach a terminal state in 100 real seconds')
            time.sleep(.008)
        dump(self.out / (label + '-os-schedule.json'), transitions)
        return observed

    def audit(self, name, observed, receipt=None):
        snapshot = observed['flight_snapshot']
        replay = self.reference({'snapshot': snapshot, 'mode': 'replay'}, name + '-exact-input')
        self.check(name + ' exact recorded input reproduces native state',
                   replay['status'] == observed['sim_status'] and replay['elapsed'] == observed['sim_elapsed']
                   and replay['position'] == observed['position'] and replay['energy_used'] == observed['telemetry']['energy_used'],
                   {'ticks': snapshot['ticks'], 'energy': replay['energy_used'], 'elapsed': replay['elapsed']})
        self.check(name + ' W and S are both in the actual native input record',
                   any(x['axis_q'] < 0 for x in snapshot['input_commands']) and any(x['axis_q'] > 0 for x in snapshot['input_commands']))
        self.check(name + ' low local route uses real kiosk aperture and no orbital identity',
                   snapshot['route']['route_profile'] == 'ground-city-v1' and snapshot['control_version'] == 'pilot-v3'
                   and snapshot['route']['destination_y'] == -8 and observed['background']['background_route'] == 'city'
                   and abs(observed['position'][1] + 8) < snapshot['route']['delivery_radius']
                   and observed['receiver']['capture_center'] == [observed['flight_origin'][0] + 360 * observed['world_cell'],
                                                                  observed['flight_origin'][1] - 8 * observed['world_cell']])
        self.check(name + ' exactly one physical launch impulse',
                   sum('完成压缩供能' in event for event in replay['events']) == 1, replay['events'])
        if receipt:
            tariff = snapshot['route']['pilot_energy_tariff']
            costs = {key: math.ceil(replay['telemetry'].get(source, 0)) for key, source in
                     [('ammo', 'ammo_cost'), ('repairs', 'repair_cost'), ('lost', 'lost_cost')]}
            costs['energy'] = math.ceil(replay['energy_used'] * tariff)
            self.check(name + ' unique receipt and every billed cost match exact replay',
                       receipt['contract_id'] == snapshot['route']['contract_id'] and receipt['elapsed'] == replay['elapsed']
                       and receipt['energy_tariff'] == tariff and all(receipt[k] == v for k, v in costs.items())
                       and receipt['profit'] == receipt['income'] - sum(costs.values()), {'receipt': receipt, 'replayed_costs': costs})
            self.check(name + ' success is on time and intact', receipt['success'] and receipt['integrity'] == 100
                       and receipt['elapsed'] < receipt['deadline'])
        self.results[name] = {'terminal': str(self.out / (name + '-terminal-observation.json')), 'ticks': snapshot['ticks'],
                              'replay_energy': replay['energy_used'], 'elapsed': replay['elapsed'], 'receipt': receipt}

    def check_expanded_grid(self):
        self.click_view('action:close_drawer:null', text='‹  返回店铺')
        if self.observe()['dialogue_open']:
            self.finish_dialogue('ground-return-before-grid-check')
        self.click_hub(1, .3)
        self.wait(lambda x: x['page'] == 'workshop', 'expanded workbench opens')
        before = self.state()
        observed = self.observe()
        if not observed['workshop']['palette_open']:
            self.click_view('action:_palette:null')
        self.click_view('catalog:beam')
        self.click_view('action:fit_workshop:null')
        observed = self.observe()
        available = observed['workshop']['free_stock']['beam']
        self.check('expanded pointer check uses a genuinely stocked spare beam', available > 0)
        occupied = {(int(p['x']), int(p['y'])) for p in before['design']}
        candidates = [c for c in observed['workshop']['projected_new_cells']
                      if c['inside_art'] and not c['blocked_by_ui'] and c['cell'] == c['inverse_cell']
                      and tuple(c['cell']) not in occupied]
        if not candidates:
            self.screenshot('expanded-grid-offscreen')
            raise AssertionError('No new tier-one cell is pointer-accessible after real Fit; no picking bypass attempted')
        cell = candidates[0]
        self.execute({'click': cell['screen'], 'sleep': .25, 'shot': 'expanded-grid-beam-placed'})
        placed = self.state()
        added = [p for p in placed['design'] if p not in before['design']]
        self.check('actual pointer places a beam in a newly unlocked saved cell',
                   len(added) == 1 and added[0]['type'] == 'beam' and [added[0]['x'], added[0]['y']] == cell['cell']
                   and len(placed['design']) == len(before['design']) + 1
                   and placed['inventory'] == before['inventory']
                   and self.observe()['workshop']['free_stock']['beam'] == available - 1,
                   {'target': cell, 'added': added, 'ownership_model': 'Inventory total stays owned; uninstalled stock decreases by one'})
        self.click_view('action:undo:null')
        undone = self.state()
        self.check('real Undo restores exact design, launcher and inventory availability',
                   undone['design'] == before['design'] and undone['launcher'] == before['launcher']
                   and undone['inventory'] == before['inventory'] and undone['credits'] == before['credits']
                   and self.observe()['workshop']['free_stock']['beam'] == available)
        self.screenshot('expanded-grid-undo-restored')
        self.click_view('action:close_drawer:null', text='‹  返回店铺')
        self.click_hub(2, .3)
        self.wait(lambda x: x['page'] == 'supply', 'return to paid night supply')

    def run(self, trial_only=False):
        first = self.state()
        self.check('ordinary fresh game has no QA endowment or prior business', self.fixture['qa_endowment'] == 0
                   and not self.fixture['preseeded'] and first['day'] == 1 and first['jobs_today'] == 0
                   and first['settled_ids'] == {} and first['credits'] == 260, {'credits': first['credits']})
        self.check('fresh orders really are two ground-city-v1 contracts',
                   [x['contract_id'] for x in first['contracts']] == ['D1-A', 'D1-B']
                   and all(x.get('route_profile') == 'ground-city-v1' and x['control_version'] == 'pilot-v3'
                           and x['distance'] == 360 and x['destination_y'] == -8 for x in first['contracts']))
        self.click_hub(0, .2)
        accepted = self.accept('D1-A')
        spec = self.reference_spec(accepted)
        reference = self.reference(spec, 'trial-ground')
        self.execute({'ledger_baseline': 'before-trial', 'capture_start': '01-ground-trial-full-route', 'sleep': .1})
        self.click_view('action:trial:null', .02)
        self.wait(lambda x: x['page'] == 'flight', 'trial launch')
        terminal = self.drive(reference, 'trial-ground')
        self.wait(lambda x: x['page'] == 'report', 'trial report')
        self.execute({'capture_stop': True, 'check_ledger': 'before-trial', 'shot': 'trial-ground-report', 'sleep': .1})
        self.audit('trial-ground', terminal)
        self.check('successful first trial preserves entire business ledger', business_ledger(self.state()) == business_ledger(accepted))
        print(json.dumps({'trial_clip_ready': self.captures[-1]['video'], 'actual_master_audio': True}, ensure_ascii=False), flush=True)
        if trial_only:
            self.status = 'trial_only_pass'; return
        self.click_view('action:dispatch:null')
        self.wait(lambda x: x['dispatch_confirm'], 'formal confirmation opens')
        before_confirm = self.state()
        self.execute({'actions': [{'key': 'Return'}, {'key': 'Return'}, {'key': 'Escape'}], 'sleep': .15})
        self.check('repeated default confirm/cancel keys never dispatch or charge', business_ledger(self.state()) == business_ledger(before_confirm))
        self.click_view('action:dispatch:null')
        self.wait(lambda x: x['dispatch_confirm'], 'formal confirmation reopens')
        self.execute({'key': 'Escape', 'sleep': .15})
        self.check('explicit cancel leaves accepted contract intact', business_ledger(self.state()) == business_ledger(accepted))
        self.click_view('action:dispatch:null')
        self.click_view('dispatch:confirm', .01, repeat=2)
        self.wait(lambda x: x['page'] == 'flight', 'formal A launch')
        paused = self.drive(reference, 'formal-a-to-pause', stop_tick=480)
        self.execute({'focus': 'root', 'sleep': .35})
        focus_saved = self.state()['in_flight']
        self.check('P plus native focus loss saves real paused v3 checkpoint',
                   self.observe()['paused'] and focus_saved['ticks'] >= 480 and focus_saved['control_version'] == 'pilot-v3')
        self.execute({'sleep': .7})
        self.check('focus loss leaves simulation and saved checkpoint stable', self.state()['in_flight'] == focus_saved
                   and self.observe()['completed_ticks'] == paused['completed_ticks'])
        self.execute({'focus': 'game', 'sleep': .2})
        self.check('focus return never auto-resumes', self.observe()['paused'])
        self.execute({'close': True, 'sleep': 0})
        closed = self.state()['in_flight']
        self.check('native close preserves the exact focus-flushed checkpoint', closed == focus_saved)
        self.execute({'start': 5, 'sleep': .1})
        resumed = self.wait(lambda x: x['page'] == 'flight' and x['paused'], 'restart paused exact flight')
        self.check('restart restores exact tick, energy and position without countdown',
                   resumed['completed_ticks'] == closed['ticks'] and resumed['sim_elapsed'] == closed['elapsed']
                   and resumed['position'] == paused['position'] and resumed['telemetry']['energy_used'] == paused['telemetry']['energy_used']
                   and resumed['launch_countdown'] == 0 and self.state()['in_flight'] == closed)
        resumed_reference = self.reference({'snapshot': closed}, 'formal-a-resume')
        self.execute({'key': 'p', 'sleep': .005})
        terminal_a = self.drive(resumed_reference, 'formal-a')
        self.wait(lambda x: x['page'] == 'report', 'formal A report')
        a = self.state(); receipt_a = a['settled_ids']['D1-A']
        self.audit('formal-a', terminal_a, receipt_a)
        self.check('A settles once with exact credit balance', len(a['history']) == 1 and list(a['settled_ids']) == ['D1-A']
                   and a['credits'] == accepted['credits'] + receipt_a['profit'])
        self.finish_dialogue('D1-A-result')
        self.click_view('action:next_contract:null', .02)
        b_accepted = self.accept('D1-B')
        b_reference = self.reference(self.reference_spec(b_accepted), 'formal-b-guide')
        self.click_view('action:dispatch:null')
        self.click_view('dispatch:confirm', .02, repeat=2)
        self.wait(lambda x: x['page'] == 'flight', 'formal B launch')
        terminal_b = self.drive(b_reference, 'formal-b')
        self.wait(lambda x: x['page'] == 'report', 'formal B report')
        b = self.state(); receipt_b = b['settled_ids']['D1-B']
        self.audit('formal-b', terminal_b, receipt_b)
        self.check('two unique settlements and exact total balance', set(b['settled_ids']) == {'D1-A', 'D1-B'}
                   and b['settled_ids']['D1-A'] == receipt_a and len(b['history']) == 2
                   and b['jobs_today'] == 2 and b['deliveries'] == 2
                   and b['credits'] == accepted['credits'] + receipt_a['profit'] + receipt_b['profit']
                   and b['design'] == accepted['design'] and b['launcher'] == accepted['launcher'])
        self.finish_dialogue('D1-B-result')
        self.click_view('action:close_drawer:null', text='返回店铺')
        if self.observe()['dialogue_open']:
            # Preserve the actual return copy as evidence even if its normal UI
            # surfaces before closing time rather than waiting until tomorrow.
            self.finish_dialogue('D1-B-ground-return-before-night')
        self.click_hub(2, .3)
        self.click_view('action:close_day:null')
        night = self.state()
        self.check('night has no hidden business charge', night['phase'] == 'night' and night['credits'] == b['credits'])
        if night['credits'] >= 225:
            self.click_view('action:workshop_upgrade:1')
            upgraded = self.state()
            self.check('real night workshop upgrade charges 180 exactly', upgraded['workshop_tier'] == 1
                       and upgraded['credits'] == night['credits'] - 180 and upgraded['design'] == night['design'])
            self.click_view('action:buy:"battery"')
            purchased = self.state()
            self.check('real night battery purchase charges 45 exactly', purchased['credits'] == upgraded['credits'] - 45
                       and purchased['inventory']['battery'] == upgraded['inventory']['battery'] + 1)
        else:
            purchased = night
            self.results['night_purchase'] = 'Not affordable from this naturally earned balance'
        if purchased['workshop_tier'] == 1:
            self.check_expanded_grid()
        self.click_view('action:next_day:null')
        next_day = self.state()
        self.check('day two exposes genuine preexisting ascent contracts', next_day['day'] == 2 and next_day['jobs_today'] == 0
                   and all(x['distance'] == 520 and x['destination_y'] == -150 and not x.get('route_profile')
                           for x in next_day['contracts']))
        self.check('next day retains unique ground receipts, upgrade, purchase and balance',
                   next_day['settled_ids'] == b['settled_ids'] and next_day['history'] == b['history']
                   and next_day['credits'] == purchased['credits'] and next_day['inventory'] == purchased['inventory']
                   and next_day['workshop_tier'] == purchased['workshop_tier'])
        contexts = next_day['story_state']['committed_contract_ids']
        self.check('old ground receipt destination persists after next-day contract replacement',
                   all(contexts[cid]['route_context']['destination_name'] == '屋顶收件台'
                       and contexts[cid]['route_context']['route_profile'] == 'ground-city-v1' for cid in ['D1-A', 'D1-B']))
        self.execute({'sleep': .5})
        if self.observe()['dialogue_open']:
            return_story = self.observe()
            dump(self.out / 'day-two-ground-return-story.json', return_story)
            self.check('visible old ground return story retains its original destination',
                       '屋顶收件台' in json.dumps(return_story.get('dialogue_conversation', {}), ensure_ascii=False))
            self.screenshot('day-two-ground-return-story')
        else:
            self.results['day_two_return_dialogue'] = 'No pending return opened; actual earlier return copy and persistent receipt context are recorded separately'
        self.execute({'close': True, 'sleep': 0})
        self.execute({'start': 5, 'sleep': .1})
        self.check('final native restart preserves day-two business ledger', business_ledger(self.state()) == business_ledger(next_day))
        self.status = 'business_day_pass'

    def close(self):
        super().close()
        final = hashes()
        unchanged = final == self.started_hashes
        dump(self.out / 'source-hashes-after.json', final)
        dump(self.out / 'ground-validation-summary.json', {
            'status': self.status, 'method': 'Automated native XTest; fresh ordinary game; read-only sidecar and exact pilot-v3 input replay',
            'human_play_claim': False, 'physical_gamepad_test': False, 'qa_endowment': 0, 'save_editing': False,
            'fixed_fps': False, 'time_scale': 1, 'capture_fps': 24, 'engine_fps_claim': False,
            'source_unchanged': unchanged, 'changed_sources': [p for p in final if final[p] != self.started_hashes.get(p)],
            'release_note': self.release_note, 'wall_seconds': time.monotonic() - self.started_at,
            'checks': self.checks, 'results': self.results, 'captures': self.captures})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready', action='store_true')
    parser.add_argument('--release-note', required=True)
    parser.add_argument('--trial-only', action='store_true')
    parser.add_argument('--interactive', action='store_true')
    args = parser.parse_args()
    if not args.ready: parser.error('Explicit frozen-production/exclusive-GUI release required')
    if 'SC_QA_OUT' not in os.environ: parser.error('Set SC_QA_OUT to a fresh directory under docs/qa/v5/ground-native')
    os.environ.setdefault('SC_QA_RUN', 'ground-native-' + str(time.time_ns()))
    os.environ.setdefault('SC_QA_DISPLAY', '559')
    capture = GroundDay(args)
    try:
        print(json.dumps(capture.ready, ensure_ascii=False), flush=True)
        if args.interactive:
            for line in sys.stdin:
                command = json.loads(line)
                print(json.dumps(capture.execute(command), ensure_ascii=False), flush=True)
                if command.get('quit'): break
        else:
            capture.run(args.trial_only)
    except Exception as error:
        capture.status = 'failed'
        dump(capture.out / 'ground-harness-error.json', {'error': repr(error)})
        try: capture.execute({'shot': 'failure-screen', 'snapshot': 'failure-save', 'sleep': 0})
        except Exception: pass
        raise
    finally:
        capture.close()


if __name__ == '__main__':
    main()
