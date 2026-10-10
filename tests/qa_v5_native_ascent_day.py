#!/usr/bin/env python3
"""Fresh-profile native pilot-v2 business-day acceptance gate.

Only run with the parent's exclusive GUI-slot approval:
  SC_QA_DISPLAY=391 SC_QA_RUN=unique-name python tests/qa_v5_native_ascent_day.py --ready

Live gameplay uses XTest keyboard/pointer events and native window closure only.
The saved game is read only. An offline copy of the deterministic simulator builds
key schedules from the actual accepted route/design/launcher and audits the actual
recorded input timeline. There is no live control API, save mutation, fixed FPS,
time scaling, human-play claim, or engine-performance claim.
"""
import argparse
import hashlib
import json
import math
import os
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from capture_native_pilot_delivery import NativePilotCapture

SOURCES = ['scripts/main.gd', 'scripts/game_hud.gd', 'scripts/economy.gd',
    'scripts/world_view_2d.gd', 'scripts/pilot_ascent_profile.gd',
    'scripts/pilot_ascent_simulation.gd', 'scripts/pilot_timeline.gd',
    'scripts/ascent_backdrop_2d.gd', 'assets/2d_v5/ascent_background.gdshader',
    'assets/2d_v5/ascent/atmosphere-tall.png',
    'tools/capture_native_pilot_delivery.py', 'tools/pilot_keyboard_reference.gd',
    'tests/qa_v5_native_ascent_day.py']


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def ledger(state):
    return {key: state[key] for key in ['credits', 'day', 'phase', 'deliveries',
        'jobs_today', 'reputation', 'history', 'settled_ids', 'active_contract_id',
        'in_flight', 'last_settlement', 'inventory', 'research', 'contracts',
        'design', 'launcher']}


class BusinessDay:
    def __init__(self):
        self.started = time.monotonic()
        self.checks = []
        self.results = {}
        self.source_hashes = self.hash_sources()
        self.c = NativePilotCapture()

    def hash_sources(self):
        return {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in SOURCES}

    def check(self, test, condition, detail=None):
        row = {'test': test, 'passed': bool(condition), 'detail': detail}
        self.checks.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        if not condition:
            raise AssertionError(test)

    def read_state(self):
        return self.c.send({'state': True, 'sleep': 0})['state']

    def reference_spec(self, state):
        order = next(x for x in state['contracts'] if x['contract_id'] == state['active_contract_id'])
        return {'route': dict(order, battery_capacity_multiplier=1 + .15 * state['research']),
            'design': state['design'], 'launcher': state['launcher'],
            'seed': state['day'] * 100 + int(order['id']) * 3 + int(order['contract_id'].endswith('B')),
            'boost_start_tick': 210, 'boost_end_tick': 240}

    def deliver(self, name, reference_spec, **options):
        # Derive recording/wait durations from the actual reference, not v1 constants.
        reference = self.c.reference(reference_spec, name + '-duration')
        write_json(self.c.out/(name + '-offline-reference.json'), reference)
        self.check(name + ' offline route schedule clears', reference['status'] == 'success',
            {'elapsed': reference['elapsed'], 'weight': reference['weight'], 'seed': reference['seed']})
        offset = float(reference_spec.get('snapshot', {}).get('elapsed', 0))
        end = float(options.get('stop_at', reference['elapsed']))
        seconds = max(8.0, end - offset + 6.0)
        result = self.c.deliver({'name': name, 'reference': reference_spec,
            'seconds': seconds, **options})
        self.results[name] = {'reference_elapsed': reference['elapsed'],
            'recording_seconds': seconds, 'route_source': 'read-only game-written accepted order or in-flight snapshot'}
        return result

    def audit_bill(self, name, result, contract):
        state = result['state']
        receipt = state['settled_ids'].get(contract, {})
        self.check(name + ' has its unique matching receipt', receipt.get('contract_id') == contract)
        snapshot = json.loads(pathlib.Path(result['last_input_checkpoint']).read_text())['in_flight']
        replay = self.c.reference({'snapshot': snapshot, 'mode': 'replay'}, name + '-exact-input-bill-audit')
        write_json(self.c.out/(name + '-exact-input-replay-result.json'), replay)
        tariff = float(snapshot['route']['pilot_energy_tariff'])
        expected_energy = math.ceil(replay['energy_used'] * tariff)
        self.check(name + ' uses game-written v2 route and authoritative tariff',
            snapshot['control_version'] == 'pilot-v2' and snapshot['route']['control_version'] == 'pilot-v2'
            and tariff == .025 and receipt.get('energy_tariff') == tariff,
            {'tariff': tariff, 'receipt_tariff': receipt.get('energy_tariff')})
        self.check(name + ' exact input timeline reproduces native elapsed',
            abs(replay['elapsed'] - receipt['elapsed']) < 1e-8,
            {'native': receipt['elapsed'], 'replay': replay['elapsed']})
        self.check(name + ' exact replay energy bill', receipt['energy'] == expected_energy,
            {'joules': replay['energy_used'], 'bill': receipt['energy'], 'expected': expected_energy})
        expected_profit = receipt['income'] - expected_energy - sum(receipt[k] for k in ['ammo', 'repairs', 'lost'])
        self.check(name + ' exact net profit', receipt['profit'] == expected_profit, receipt)
        self.check(name + ' successful intact delivery before deadline',
            receipt['success'] and receipt['integrity'] == 100 and receipt['elapsed'] < receipt['deadline'])
        self.check(name + ' exactly one physical launch impulse',
            sum('完成压缩供能' in x for x in replay['events']) == 1, replay['events'])
        self.check(name + ' recorded native timeline contains steering both ways and boost',
            any(x['axis_q'] < 0 for x in snapshot['input_commands']) and
            any(x['axis_q'] > 0 for x in snapshot['input_commands']) and
            any(x['boost'] for x in snapshot['input_commands']))
        self.results[name + '_billing'] = {'receipt': receipt, 'route_tariff': tariff,
            'replay_energy_joules': replay['energy_used'], 'replay_elapsed': replay['elapsed'],
            'timeline_checkpoint': result['last_input_checkpoint']}
        return receipt

    def run(self):
        c = self.c
        self.check('fresh isolated profile', c.ready['state'] == {'saved': False})
        c.send({'click': [90, 715], 'shot': '02-counter'})
        accepted = c.send({'click': [1010, 523], 'shot': '03-first-accepted',
            'snapshot': '03-first-accepted', 'state': True})['state']
        self.check('first native accepted order is D1-A', accepted['active_contract_id'] == 'D1-A')
        self.start_state = accepted
        spec_a = self.reference_spec(accepted)
        self.check('fresh v2 route and eight-module design',
            spec_a['route']['control_version'] == 'pilot-v2' and
            spec_a['route']['distance'] == 520 and spec_a['route']['destination_y'] == -150 and
            len(spec_a['design']) == 8)
        c.send({'click': [270, 715], 'shot': '04-workbench'})
        c.send({'click': [1135, 713], 'shot': '05-confirmation', 'snapshot': '05-before-confirmation'})
        before = self.read_state()
        c.send({'actions': [{'key': 'Return'}, {'key': 'Return'}, {'click': [1135, 713]},
            {'key': 'Escape'}, {'click': [1223, 83]}, {'key': 'Escape'}],
            'shot': '06-confirm-cancel-guards', 'snapshot': '06-after-guards'})
        self.check('repeated confirm and cancel guards preserve complete saved state', self.read_state() == before)
        c.send({'click': [1135, 713], 'shot': '07-first-confirmation'})
        self.deliver('08-first-launch-to-pause', spec_a, stop_at=8.5, repeat_launch=True)
        paused = c.send({'snapshot': '09-paused', 'state': True, 'sleep': 0})['state']['in_flight']
        self.check('P pauses a valid v2 native input checkpoint',
            paused.get('control_version') == 'pilot-v2' and paused.get('ticks', 0) > 400,
            {'ticks': paused.get('ticks'), 'elapsed': paused.get('elapsed')})
        c.send({'sleep': 1.2, 'snapshot': '10-paused-stable', 'shot': '10-paused-stable'})
        self.check('paused game leaves its last written autosave unchanged', self.read_state()['in_flight'] == paused)
        closed = c.send({'close': True, 'snapshot': '11-graceful-close', 'state': True, 'sleep': 0})
        # Native P intentionally does not flush an immediate save. A graceful
        # native close writes the true paused tick, at most one autosave interval
        # newer than the read-only checkpoint above. Restart must match THIS.
        flushed = closed['state']['in_flight']
        self.check('native WM_DELETE closes cleanly and flushes the current paused checkpoint',
            not closed['running'] and 0 <= flushed['ticks'] - paused['ticks'] <= 61 and
            abs(flushed['elapsed'] - flushed['ticks'] / 60.0) < 1e-8 and
            all(flushed[k] == paused[k] for k in ['contract_id', 'control_version', 'route', 'design', 'launcher', 'seed']),
            {'previous_autosave_ticks': paused['ticks'], 'close_written_ticks': flushed['ticks'],
             'close_written_elapsed': flushed['elapsed']})
        paused = flushed
        c.send({'start': 5, 'shot': '12-restart-paused', 'snapshot': '12-restart-paused', 'sleep': 1.0})
        first = self.read_state()
        c.send({'sleep': 1.2, 'snapshot': '13-restart-paused-stable', 'shot': '13-restart-paused-stable'})
        self.check('native restart stays paused at exactly the saved checkpoint',
            first['in_flight'] == paused and self.read_state()['in_flight'] == paused)
        a = self.deliver('14-first-resumed-delivery', {'snapshot': paused}, resume='p')
        receipt_a = self.audit_bill('standard-a', a, 'D1-A')
        self.check('A settles once with exact credit balance',
            list(a['state']['settled_ids']) == ['D1-A'] and len(a['state']['history']) == 1 and
            a['state']['jobs_today'] == 1 and a['state']['deliveries'] == 1 and
            a['state']['credits'] == accepted['credits'] + receipt_a['profit'])
        self.check('A settlement restores the original craft and launcher',
            a['state']['design'] == accepted['design'] and a['state']['launcher'] == accepted['launcher'])
        c.send({'actions': [{'click': [800, 688]}, {'click': [800, 688]}],
            'shot': '15-repeat-next-contract', 'snapshot': '15-repeat-next-contract'})
        self.check('repeated receipt transitions cannot settle A twice', ledger(self.read_state()) == ledger(a['state']))
        heavy = c.send({'click': [1010, 523], 'shot': '16-heavy-accepted',
            'snapshot': '16-heavy-accepted', 'state': True})['state']
        self.check('native next order is heavy D1-B', heavy['active_contract_id'] == 'D1-B')
        spec_b = self.reference_spec(heavy)
        self.check('heavy reference derives higher weight and unique seed from the real order',
            spec_b['route']['control_version'] == 'pilot-v2' and
            spec_b['route']['weight'] > spec_a['route']['weight'] and spec_b['seed'] != spec_a['seed'],
            {'first_weight': spec_a['route']['weight'], 'heavy_weight': spec_b['route']['weight'],
             'first_seed': spec_a['seed'], 'heavy_seed': spec_b['seed']})
        c.send({'actions': [{'click': [270, 715]}, {'click': [1135, 713]}], 'shot': '17-heavy-confirmation'})
        b = self.deliver('18-heavy-delivery', spec_b, repeat_launch=True)
        receipt_b = self.audit_bill('heavy-b', b, 'D1-B')
        state = b['state']
        self.check('two unique receipts and exact total credits',
            set(state['settled_ids']) == {'D1-A', 'D1-B'} and len(state['history']) == 2 and
            {x['contract_id'] for x in state['history']} == {'D1-A', 'D1-B'} and
            state['jobs_today'] == 2 and state['deliveries'] == 2 and
            state['credits'] == accepted['credits'] + receipt_a['profit'] + receipt_b['profit'])
        self.check('heavy report is distinct and A report remains unchanged',
            state['settled_ids']['D1-A'] == receipt_a and state['last_settlement'] == receipt_b and
            receipt_b['contract_id'] != receipt_a['contract_id'] and receipt_b['income'] > receipt_a['income'])
        self.check('B settlement restores original craft and launcher',
            state['design'] == accepted['design'] and state['launcher'] == accepted['launcher'])
        c.send({'actions': [{'click': [450, 688]}, {'click': [450, 688]}],
            'shot': '19-repeat-return-hub', 'snapshot': '19-repeat-return-hub'})
        self.check('repeated return transition preserves both settlements', ledger(self.read_state()) == ledger(state))
        c.send({'click': [440, 715], 'shot': '20-closing-day'})
        night = c.send({'click': [1030, 700], 'shot': '21-night-supply',
            'snapshot': '21-night-supply', 'state': True})['state']
        self.check('native closing enters night without new charges',
            night['phase'] == 'night' and night['credits'] == state['credits'] and
            night['settled_ids'] == state['settled_ids'])
        purchased = c.send({'click': [1190, 285], 'shot': '22-night-purchase',
            'snapshot': '22-night-purchase', 'state': True})['state']
        changes = {k: purchased['inventory'].get(k, 0) - night['inventory'].get(k, 0)
            for k in set(purchased['inventory']) | set(night['inventory'])
            if purchased['inventory'].get(k, 0) != night['inventory'].get(k, 0)}
        self.check('one battery purchase charges exactly 45 and adds one item',
            changes == {'battery': 1} and purchased['credits'] == night['credits'] - 45,
            {'inventory_difference': changes, 'charge': night['credits'] - purchased['credits']})
        next_day = c.send({'click': [1030, 700], 'shot': '23-next-day',
            'snapshot': '23-next-day', 'state': True})['state']
        self.check('next day creates fresh v2 orders and resets daily quota',
            next_day['day'] == 2 and next_day['jobs_today'] == 0 and next_day['phase'] == 'morning' and
            {x['contract_id'] for x in next_day['contracts']} == {'D2-A', 'D2-B'} and
            all(x['status'] == 'available' and x['control_version'] == 'pilot-v2' for x in next_day['contracts']))
        self.check('next day preserves two receipts, purchase and exact balance',
            next_day['settled_ids'] == state['settled_ids'] and next_day['history'] == state['history'] and
            next_day['deliveries'] == 2 and next_day['inventory'] == purchased['inventory'] and
            next_day['credits'] == purchased['credits'])
        c.send({'close': True, 'snapshot': '24-final-close', 'sleep': 0})
        c.send({'start': 5, 'shot': '25-final-restart', 'snapshot': '25-final-restart'})
        final = self.read_state()
        self.check('final native restart exactly preserves next-day state and purchase', ledger(final) == ledger(next_day))
        self.results['final_state'] = {'credits': final['credits'], 'day': final['day'], 'phase': final['phase'],
            'jobs_today': final['jobs_today'], 'deliveries': final['deliveries'], 'inventory': final['inventory'],
            'settled_ids': list(final['settled_ids']), 'available_contracts': [x['contract_id'] for x in final['contracts']]}
        self.results['recordings'] = c.send({'finish_record': True, 'sleep': 0})['recordings']
        self.check('all three native capture files completed',
            len(self.results['recordings']) == 3 and all(x['bytes'] > 0 for x in self.results['recordings']))
        self.check('tested production and harness sources unchanged during native day', self.hash_sources() == self.source_hashes)
        c.send({'close': True, 'sleep': 0})

    def close(self):
        self.c.close()
        write_json(self.c.out/'validation-summary.json', {
            'method': 'Automated native XTest keyboard/pointer; native X11 window close; read-only exact-input replay audit',
            'human_play_claim': False, 'engine_fps_claim': False, 'capture_fps': 24,
            'no_fixed_fps_or_save_mutation': True, 'time_scale': 1,
            'source_sha256': self.source_hashes, 'wall_seconds': time.monotonic() - self.started,
            'checks': self.checks, 'results': self.results})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready', action='store_true', help='Parent explicitly granted the exclusive native GUI slot')
    args = parser.parse_args()
    if not args.ready:
        parser.error('Wait for the parent to grant the native GUI slot, then pass --ready.')
    os.environ.setdefault('SC_QA_DISPLAY', '391')
    os.environ.setdefault('SC_QA_RUN', 'ascent-native-day-' + str(time.time_ns()))
    os.environ.setdefault('SC_QA_OUT', 'docs/qa/v5/ascent-native-day/run-01')
    run = BusinessDay()
    try:
        run.run()
    finally:
        run.close()


if __name__ == '__main__':
    main()
