#!/usr/bin/env python3
"""Run the existing isolated suite runner and retain a source-frozen QA record.

Run only in an allocated CPU window, never alongside a timed native capture.
Evidence belongs outside source Git (for example docs/qa/<new-run-directory>).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes() -> dict[str, str]:
    result = {}
    for folder in ("scripts", "assets", "scenes", "tests", "tools", "fixtures"):
        for path in (ROOT / folder).rglob("*"):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            # Engine-generated resource IDs/import cache descriptors are not
            # authored executable/art bytes and can appear on first import.
            if path.suffix in (".uid", ".import", ".pyc"):
                continue
            result[str(path.relative_to(ROOT))] = sha(path)
    # Some permanent asset tests verify their original imagegen inputs.
    # Freeze exactly those declared inputs, not large staging/evidence trees.
    # The two QA-report outputs are intentionally absent from this input list.
    support_path = ROOT / "tools/aggregate_source_support.json"
    if support_path.exists():
        support = json.loads(support_path.read_text())
        if support.get("schema") != "aggregate-immutable-source-support-v2":
            raise RuntimeError("Unknown aggregate source-support contract")
        seen = set()
        for entry in support["files"]:
            relative = entry["path"]
            path = Path(relative)
            if (path.is_absolute() or ".." in path.parts
                    or not path.parts or path.parts[0] != "source_art"
                    or relative in seen):
                raise RuntimeError("Invalid aggregate source-support path: " + relative)
            seen.add(relative)
            source = ROOT / path
            if not source.is_file() or not source.resolve().is_relative_to(ROOT.resolve()):
                raise RuntimeError("Missing aggregate source input: " + relative)
            actual = sha(source)
            if actual != entry["sha256"] or source.stat().st_size != entry["bytes"]:
                raise RuntimeError("Aggregate source input changed from its pinned original: " + relative)
            result[relative] = actual
        if len(seen) != support["file_count"]:
            raise RuntimeError("Aggregate source-support count mismatch")
    for name in ("project.godot", "export_presets.cfg"):
        path = ROOT / name
        if path.exists():
            result[name] = sha(path)
    return dict(sorted(result.items()))


def diagnostics(log: str) -> tuple[list[str], list[str]]:
    errors, failed_counts = [], []
    for line in log.splitlines():
        if re.match(r"^\s*(?:SCRIPT ERROR:|ERROR:|FAIL(?:[ :]|$))", line):
            errors.append(line)
        counts = re.findall(r"\bfailed\s*=\s*(\d+)\b", line, re.I)
        # Do not read the '18' in 'passed=18 failed=0' as '18 failed'.
        counts += re.findall(r"(?<![=\d])\b(\d+)\s+failed\b", line, re.I)
        if any(int(value) > 0 for value in counts):
            failed_counts.append(line)
    return errors, failed_counts


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        assert diagnostics("PASS\nMOON passed=18 failed=0\n18 passed; 0 failed") == ([], [])
        assert diagnostics("CASE passed=9 failed=2")[1] == ["CASE passed=9 failed=2"]
        assert diagnostics("8 passed; 2 failed")[1] == ["8 passed; 2 failed"]
        assert diagnostics("SCRIPT ERROR: bad\nERROR: bad\nFAIL bad")[0] == [
            "SCRIPT ERROR: bad", "ERROR: bad", "FAIL bad"
        ]
        print("REGRESSION_GATE_SELF_TEST checks=4 passed=4 failed=0")
        return 0
    if args.output is None:
        parser.error("--output is required for a full run")
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error("--output must be a new or empty directory; prior evidence is retained")
    out.mkdir(parents=True, exist_ok=True)
    runner = (ROOT / "tools/test.sh").read_text()
    match = re.search(r"for suite in (.*?); do", runner, re.S)
    if not match:
        raise RuntimeError("Cannot identify the explicit suite list in tools/test.sh")
    suites = match.group(1).split()
    plan = json.loads((ROOT / "tools/combined_suite_plan.json").read_text())
    if suites != plan["baseline_suite_names"] + plan["independent_additive_suite_names"]:
        raise RuntimeError("Aggregate suite plan disagrees with executable loop")
    expected_invocations = len(suites) + len(plan["fixture_commands"]) + len(plan["portable_commands"]) + 2
    if expected_invocations != plan["expected_godot_invocations_including_import_and_smoke"]:
        raise RuntimeError("Aggregate invocation accounting drift")
    before = source_hashes()
    write_json(out / "hashes-before.json", before)
    import tarfile
    with tarfile.open(out / "source-before.tar.gz", "w:gz") as archive:
        for relative in before:
            archive.add(ROOT / relative, arcname=relative, recursive=False)
    start = time.monotonic()
    import os
    context_root = out / "contexts"
    context_root.mkdir()
    env = os.environ.copy()
    env.update({"TMPDIR": str(context_root), "KEEP_TEST_ROOT": "1"})
    with (out / "full.log").open("w") as log_file:
        completed = subprocess.run(["bash", "tools/test.sh"], cwd=ROOT, env=env, stdout=log_file, stderr=subprocess.STDOUT)
    elapsed = time.monotonic() - start
    after = source_hashes()
    write_json(out / "hashes-after.json", after)
    changed = [name for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]
    log = (out / "full.log").read_text(errors="replace")
    errors, counts = diagnostics(log)
    invocations = len(re.findall(r"^Godot Engine v", log, re.M))
    npc = re.findall(r"^PASS:\s+(\d+) static NPC asset checks$", log, re.M)
    motion = re.findall(r"^PASS:\s+(\d+) actual motion asset checks$", log, re.M)
    complete = completed.returncode == 0 and not changed and not errors and not counts
    complete = complete and invocations == expected_invocations and "SMOKE_UI_COMPLETE" in log and len(npc) == 1 and len(motion) == 1
    report = {
        "verified": complete, "exit_code": completed.returncode, "suites": len(suites),
        "suite_names": suites, "suite_plan": plan, "expected_godot_invocations": expected_invocations, "source_files": len(before), "changed": changed,
        "diagnostics": errors, "nonzero_failed_counts": counts, "godot_invocations": invocations,
        "smoke_complete": "SMOKE_UI_COMPLETE" in log,
        "npc_asset_checks": int(npc[0]) if len(npc) == 1 else None,
        "historical_motion_asset_checks": int(motion[0]) if len(motion) == 1 else None,
        "wall_seconds": elapsed, "full_log_sha256": sha(out / "full.log"),
        "scope": "Isolated headless suites/smoke and asset checks. No native input, physical controller, human fairness, art approval or hardware FPS conclusion."
    }
    write_json(out / "freeze-result.json", report)
    print(json.dumps({key: report[key] for key in ("verified", "exit_code", "suites", "changed", "diagnostics", "nonzero_failed_counts", "wall_seconds", "full_log_sha256")}, ensure_ascii=False))
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
