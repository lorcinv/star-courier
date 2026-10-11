#!/usr/bin/env python3
"""Source-only permanent preflight; never invokes Godot or changes the project."""
from pathlib import Path
import argparse, hashlib, json, re

def verify(project):
    base = project / "tests/fixtures/protected_bird_v1"
    contract = json.loads((base / "source_contract.json").read_text())
    failures = []
    count = 0
    for group in ["runtime", "fixtures", "ported_tests", "support"]:
        for name, expected in contract[group].items():
            path = project / name
            count += 1
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                failures.append(f"{group} hash mismatch: {name}")
    paths = [project / name for name in contract["ported_tests"]]
    paths.extend(project / name for name in contract["support"] if name.endswith(".gd"))
    for path in paths:
        text = path.read_text()
        if "res://reports" in text:
            failures.append(f"private report dependency remains: {path.name}")
        if path.name != "fixture_io.gd" and re.search(r"FileAccess\.(WRITE|WRITE_READ|READ_WRITE)|\.store_(?:string|buffer|var)|DirAccess\.(?:copy|rename)", text):
            failures.append(f"unchecked writer outside checked helper: {path.name}")
    helper = (base / "fixture_io.gd").read_text()
    required = [
        'const OUTPUT_ROOT = "user://protected_bird_v1/"',
        'if not allowed_path(path, true): return failure("write_path"',
        'DirAccess.make_dir_recursive_absolute(parent)',
        'if code != OK: return failure("create_parent"',
        'if file == null: return failure("write_open"',
        'file.flush()', 'file.close()',
        'if code != OK: return failure("write_flush"',
        'if verified.bytes != content.to_utf8_buffer()',
    ]
    for token in required:
        if token not in helper: failures.append(f"checked writer contract missing: {token}")
    for message in failures: print("PROTECTED_BIRD_SOURCE_FAILURE: " + message)
    if not failures: print(f"PROTECTED_BIRD_SOURCE_OK: {count} frozen hashes; no private report dependency or unchecked fixture writer")
    return failures

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    raise SystemExit(1 if verify(args.project.resolve()) else 0)
