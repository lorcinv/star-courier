#!/usr/bin/env python3
"""Fresh tablet/gait native QA; reuses the unchanged cooperative XTest driver.

Only launch after explicit production freeze and exclusive GUI release. Runtime
game state and saves remain read-only. Outputs must be new dated directories.
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
BASE_OUT = ROOT / 'docs/qa/v5/tablet-walk-native'
_original_hashes = cooperative.hashes


def hashes():
    values = _original_hashes()
    values['tests/qa_v5_native_tablet_walk.py'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    return values


class NativeTabletWalk(cooperative.NativeCooperative):
    def __init__(self, args):
        cooperative.BASE_OUT = BASE_OUT
        cooperative.hashes = hashes
        target = Path(os.environ['SC_QA_OUT'])
        if not target.is_absolute():
            target = ROOT / target
        if target.exists():
            raise RuntimeError('Historical outputs are immutable; use a fresh output directory')
        super().__init__(args)
        (self.out / 'source-hashes-before.json').write_text(json.dumps(self.started_hashes, indent=2) + '\n')

    def close(self):
        super().close()
        final = hashes()
        (self.out / 'source-hashes-after.json').write_text(json.dumps(final, indent=2) + '\n')
        changed = sorted(k for k in self.started_hashes.keys() | final.keys()
                         if self.started_hashes.get(k) != final.get(k))
        (self.out / 'source-freeze-verification.json').write_text(json.dumps({
            'source_unchanged': not changed, 'changed': changed,
            'status': 'current_frozen_run' if not changed else 'historical_source_changed_during_run',
            'release_note': self.release_note,
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
        parser.error('Set SC_QA_OUT to a new dated directory under tablet-walk-native')
    os.environ.setdefault('SC_QA_RUN', 'tablet-walk-native-' + str(time.time_ns()))
    os.environ.setdefault('SC_QA_DISPLAY', '539')
    capture = NativeTabletWalk(args)
    try:
        print(json.dumps(capture.ready, ensure_ascii=False), flush=True)
        commands = json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for command in commands:
            try:
                result = capture.execute(command)
            except Exception as exc:
                result = {'harness_error': repr(exc), 'command': command}
                with (capture.out / 'harness-errors.jsonl').open('a') as stream:
                    stream.write(json.dumps(result, ensure_ascii=False) + '\n')
                print(json.dumps(result, ensure_ascii=False), flush=True)
                raise
            print(json.dumps(result, ensure_ascii=False), flush=True)
            if command.get('quit'):
                break
    finally:
        capture.close()


if __name__ == '__main__':
    main()
