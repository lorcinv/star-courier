#!/usr/bin/env python3
"""Single-speed movement evidence through actual native XTest keyboard/mouse.

Launch only after explicit source freeze and GUI release. The ordinary starter
is isolated and unedited. Read-only observations select visible UI rectangles;
there are no game API actions, manual clocks, speedups or physical-pad claims.
Historical QA drivers are imported unchanged and their bytes are hashed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

import qa_v5_native_locomotion as locomotion
import qa_v5_native_cooperative as cooperative

ROOT = Path(__file__).resolve().parents[1]
BASE_OUT = ROOT / 'docs/qa/v5/single-movement-native'
_original_hashes = locomotion.hashes


def hashes():
    result = _original_hashes()
    for name in ('tests/qa_v5_native_single_movement.py', 'tools/qa_single_movement_observer.gd'):
        result[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    return result


class NativeSingleMovement(locomotion.NativeLocomotion):
    def __init__(self, args):
        # The legacy initializer hard-selects its observer. Initialize the same
        # cooperative/native base directly with our separate read-only observer.
        cooperative.BASE_OUT = BASE_OUT
        cooperative.QA_ENTRY = 'res://tools/qa_single_movement_observer.gd'
        cooperative.hashes = hashes
        target = Path(os.environ['SC_QA_OUT'])
        if not target.is_absolute():
            target = ROOT / target
        if target.exists():
            raise RuntimeError('Use a new output directory; historical captures are immutable')
        self.button_trace = []
        cooperative.NativeCooperative.__init__(self, args)
        (self.out / 'source-hashes-before.json').write_text(json.dumps(self.started_hashes, indent=2) + '\n')

    def execute(self, command):
        original = dict(command)
        forwarded = dict(command)
        selector = forwarded.pop('click_visible', None)
        if selector:
            observed = self.observe()
            if isinstance(selector, str):
                selector = {'text': selector}
            candidates = []
            for button in observed['buttons']:
                if button['disabled']:
                    continue
                if 'text' in selector and selector['text'] not in [button['text'], *button['labels']]:
                    continue
                if 'name' in selector and button['name'] != selector['name']:
                    continue
                if 'path_contains' in selector and selector['path_contains'] not in button['path']:
                    continue
                if 'tooltip' in selector and selector['tooltip'] != button['tooltip']:
                    continue
                candidates.append(button)
            if len(candidates) != 1:
                raise AssertionError('Expected exactly one visible button: ' + repr(selector) + '; found ' + repr(candidates))
            x, y, w, h = candidates[0]['visible_rect']
            point = [x + w / 2, y + h / 2]
            forwarded['click'] = point
            self.button_trace.append({'unix_seconds': time.time(), 'selector': selector, 'observed': candidates[0], 'clicked': point})
            (self.out / 'observed-button-inputs.json').write_text(json.dumps(self.button_trace, ensure_ascii=False, indent=2) + '\n')
        result = super().execute(forwarded)
        if selector:
            result['clicked_visible'] = self.button_trace[-1]
        with (self.out / 'single-movement-events.jsonl').open('a') as stream:
            stream.write(json.dumps({'unix_seconds': time.time(), 'command': original, 'result': result}, ensure_ascii=False) + '\n')
        return result

    def close(self):
        # Parent close uses locomotion.hashes for its final comparison.
        previous = locomotion.hashes
        locomotion.hashes = hashes
        try:
            super().close()
        finally:
            locomotion.hashes = previous
        for name in ('cooperative-source-metadata.json', 'cooperative-validation-summary.json'):
            path = self.out / name
            if not path.exists():
                continue
            value = json.loads(path.read_text())
            value.update({'evidence_subject': 'One 155 px/s movement cycle; neutral hands and canonical head scale',
                          'telemetry': '30 Hz capped read-only scene observation; current raster bounds, camera and UI geometry',
                          'physical_gamepad_test': False, 'speedup': False, 'fixed_fps': False})
            (self.out / name.replace('cooperative-', 'single-movement-')).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
        summarize(self.out)


def summarize(directory):
    telemetry = sorted(directory.glob('native-telemetry-session-*.json'))
    samples = []
    for source in telemetry:
        samples.extend(json.loads(source.read_text()).get('samples', []))
    if not samples:
        return
    states = sorted({row.get('locomotion', {}).get('state') for row in samples if row.get('locomotion', {}).get('state')})
    player = [row for row in samples if row.get('input', {}).get('context') == 'shop' and row.get('locomotion', {}).get('owns_clerk')]
    speed = max((abs(row['locomotion']['velocity']) for row in player), default=0)
    heads = {}
    for row in samples:
        head = row.get('head_measurement', {})
        if not head.get('available'):
            continue
        key = head['pose'] + '/' + head.get('head_view', 'upright')
        record = heads.setdefault(key, {'samples': 0, 'minimum_normalized': [float('inf')] * 2, 'maximum_normalized': [0, 0], 'camera_zoom_range': [float('inf'), 0], 'example': head})
        record['samples'] += 1
        for i, value in enumerate(head['head_camera_and_pixel_normalized']):
            record['minimum_normalized'][i] = min(record['minimum_normalized'][i], value)
            record['maximum_normalized'][i] = max(record['maximum_normalized'][i], value)
        record['camera_zoom_range'][0] = min(record['camera_zoom_range'][0], head['camera_zoom'][0])
        record['camera_zoom_range'][1] = max(record['camera_zoom_range'][1], head['camera_zoom'][0])
    stop_pairs = [(a,b) for a,b in zip(samples,samples[1:]) if a.get('locomotion',{}).get('state') == 'stop' and b.get('locomotion',{}).get('state') in ('stop','idle') and a.get('input',{}).get('context')=='shop' and b.get('input',{}).get('context')=='shop']
    stop_drift = max((abs(b['locomotion']['distance']-a['locomotion']['distance']) for a,b in stop_pairs), default=None)
    summary = {'samples':len(samples), 'states_seen':states, 'maximum_observed_player_speed_px_s':speed,
               'one_155_speed_cap_passed':speed<=155.000001 and speed>=154.9,
               'running_pose_seen':any(row.get('motion',{}).get('pose')=='run' for row in samples),
               'stop_stationary_pairs':len(stop_pairs), 'maximum_stop_distance_drift_px':stop_drift,
               'head_pose_measurements':heads,
               'loading_phases_seen':sorted({row['loading']['phase'] for row in samples}),
               'parcel_instance_ids':sorted({row['loading']['parcel_instance'] for row in samples}),
               'motion_failures':list({str(value) for row in samples for value in row.get('loading',{}).get('motion_failures',[])}),
               'physical_gamepad_test':False,
               'measurement_limit':'Head bounds come from the registered current raster region transformed through the live sprite/camera; this is not an independent face-segmentation measurement.'}
    (directory/'single-movement-observation-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')


def compact(result):
    if not result.get('observation'):
        return result
    value = dict(result)
    observed = value.pop('observation')
    value['observed'] = {key:observed.get(key) for key in ('page','dialogue_open','dialogue_line','dialogue_lines','dialogue_visible_chars','input','locomotion','head_measurement','buttons')}
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready', action='store_true')
    parser.add_argument('--release-note', required=True)
    parser.add_argument('--replay', type=Path)
    args = parser.parse_args()
    if not args.ready:
        parser.error('Explicit frozen-production/exclusive-GUI release required')
    if 'SC_QA_OUT' not in os.environ:
        parser.error('Set SC_QA_OUT to a fresh dated directory')
    os.environ.setdefault('SC_QA_RUN','single-movement-native-'+str(time.time_ns()))
    os.environ.setdefault('SC_QA_DISPLAY','575')
    os.environ.setdefault('SC_QA_RESOLUTION','1280x800')
    capture = NativeSingleMovement(args)
    try:
        print(json.dumps(capture.ready,ensure_ascii=False),flush=True)
        commands = json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for command in commands:
            try:
                result = capture.execute(command)
            except Exception as exc:
                result = {'harness_error':repr(exc),'command':command}
                with (capture.out/'harness-errors.jsonl').open('a') as stream:
                    stream.write(json.dumps(result,ensure_ascii=False)+'\n')
                print(json.dumps(result,ensure_ascii=False),flush=True)
                raise
            print(json.dumps(compact(result),ensure_ascii=False),flush=True)
            if command.get('quit'):
                break
    finally:
        capture.close()


if __name__=='__main__':
    main()
