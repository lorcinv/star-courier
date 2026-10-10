#!/usr/bin/env python3
"""Actual keyboard/mouse shop locomotion QA on an isolated Xorg display.

Only use after production freeze. The Godot sidecar is read-only; this driver
never injects engine events, edits saves, or claims a physical gamepad test.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

import qa_v5_native_cooperative as cooperative

ROOT = Path(__file__).resolve().parents[1]
BASE_OUT = ROOT / 'docs/qa/v5/locomotion-native'
_original_hashes = cooperative.hashes


def hashes():
    values = _original_hashes()
    for name in ('tests/qa_v5_native_locomotion.py', 'tools/qa_locomotion_observer.gd'):
        values[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    return values


def lookup(observation, path):
    value = observation
    for key in path:
        value = value[key]
    return value


def compare(value, specification):
    if 'equals' in specification:
        return value == specification['equals']
    if 'between' in specification:
        low, high = specification['between']
        return low <= value <= high
    if 'greater_than' in specification:
        return value > specification['greater_than']
    if 'less_than' in specification:
        return value < specification['less_than']
    raise ValueError('Observation condition must specify equals, between, greater_than or less_than')


class NativeLocomotion(cooperative.NativeCooperative):
    def __init__(self, args):
        cooperative.BASE_OUT = BASE_OUT
        cooperative.QA_ENTRY = 'res://tools/qa_locomotion_observer.gd'
        cooperative.hashes = hashes
        target = Path(os.environ['SC_QA_OUT'])
        if not target.is_absolute():
            target = ROOT / target
        if target.exists():
            raise RuntimeError('Use a new output directory; historical captures are immutable')
        super().__init__(args)
        (self.out / 'source-hashes-before.json').write_text(json.dumps(self.started_hashes, indent=2) + '\n')

    def execute(self, command):
        forwarded = dict(command)
        wait = forwarded.pop('wait_motion', None)
        checks = forwarded.pop('check_motion', [])
        if wait:
            deadline = time.monotonic() + wait.get('timeout', 30)
            while True:
                observed = self.observe()
                if compare(lookup(observed, wait['path']), wait):
                    break
                if time.monotonic() >= deadline:
                    raise AssertionError('Native motion wait timed out: ' + repr(wait))
                time.sleep(.025)
        result = super().execute(forwarded)
        if checks:
            observed = self.observe()
            outcomes = []
            for check in checks:
                value = lookup(observed, check['path'])
                outcomes.append({'test': check['test'], 'passed': compare(value, check), 'observed': value})
            self.checks.extend(outcomes)
            result['motion_checks'] = outcomes
            if any(not item['passed'] for item in outcomes):
                with (self.out / 'motion-failures.jsonl').open('a') as stream:
                    stream.write(json.dumps({'command': command, 'result': result}, ensure_ascii=False) + '\n')
                raise AssertionError('Native motion observation failed; see motion-failures.jsonl')
        with (self.out / 'locomotion-native-events.jsonl').open('a') as stream:
            stream.write(json.dumps({'unix_seconds': time.time(), 'command': command, 'result': result}, ensure_ascii=False) + '\n')
        return result

    def close(self):
        super().close()
        summary_path = self.out / 'cooperative-validation-summary.json'
        if summary_path.exists():
            summary = json.loads(summary_path.read_text())
            summary.update({
                'method': 'Fresh ordinary production starter; actual XTest keyboard/mouse; read-only observer and game-written saves',
                'physical_gamepad_test': False,
                'master_audio_recorded': any(Path(c.get('actual_master_pcm', '')).is_file() for c in summary.get('captures', [])),
            })
            summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
        final = hashes()
        (self.out / 'source-hashes-after.json').write_text(json.dumps(final, indent=2) + '\n')
        changed = sorted(key for key in self.started_hashes.keys() | final.keys()
                         if self.started_hashes.get(key) != final.get(key))
        (self.out / 'source-freeze-verification.json').write_text(json.dumps({
            'source_unchanged': not changed, 'changed': changed,
            'status': 'current_frozen_run' if not changed else 'historical_source_changed_during_run',
            'release_note': self.release_note,
            'physical_gamepad_test': False,
        }, indent=2) + '\n')


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
    os.environ.setdefault('SC_QA_RUN', 'locomotion-native-' + str(time.time_ns()))
    os.environ.setdefault('SC_QA_DISPLAY', '545')
    capture = NativeLocomotion(args)
    try:
        print(json.dumps(capture.ready, ensure_ascii=False), flush=True)
        commands = json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for command in commands:
            print(json.dumps(capture.execute(command), ensure_ascii=False), flush=True)
            if command.get('quit'):
                break
    finally:
        capture.close()


if __name__ == '__main__':
    main()
