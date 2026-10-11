#!/usr/bin/env python3
"""Compare freshly generated route artifacts to separately frozen exact-byte goldens."""
import argparse, hashlib, json
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument("xdg_data_home", type=Path)
p.add_argument("kind", choices=["legacy_1_0", "commercial_2_4"])
p.add_argument("--project", type=Path, default=Path.cwd())
a = p.parse_args()
base = a.project / "tests/fixtures/protected_bird_v1" / a.kind
if a.kind == "legacy_1_0": base = a.project / "tests/fixtures/protected_bird_v1/rayfix_v1/legacy_1_0"
prefix = "commercial-" if a.kind == "commercial_2_4" else ""
failures = []
for kind in (["route", "replay", "terminal-bits"] if a.kind == "legacy_1_0" else ["route", "replay"]):
    for result in ["safe", "harm"]:
        name = f"{prefix}{kind}-{result}.json"
        suffix = f"protected_bird_v1/{'rayfix_v1/' if a.kind == 'legacy_1_0' else ''}{a.kind}/{name}"
        matches = [path for path in a.xdg_data_home.rglob(name) if path.as_posix().endswith(suffix)]
        if len(matches) != 1:
            failures.append(f"expected one fresh {suffix}, found {len(matches)}")
            continue
        actual, expected = matches[0].read_bytes(), (base/name).read_bytes()
        if actual != expected:
            failures.append(f"golden byte mismatch: {name}; actual={hashlib.sha256(actual).hexdigest()} expected={hashlib.sha256(expected).hexdigest()}")
        else:
            print(f"PROTECTED_BIRD_FRESH_GOLDEN_OK: {name} sha256={hashlib.sha256(actual).hexdigest()}")
for message in failures: print("PROTECTED_BIRD_EVIDENCE_FAILURE: " + message)
raise SystemExit(1 if failures else 0)
