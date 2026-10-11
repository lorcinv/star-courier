#!/usr/bin/env python3
"""Require the exact physics completion marker as well as a clean engine log."""
import argparse, re
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument("log", type=Path)
p.add_argument("marker")
p.add_argument("checks", type=int)
p.add_argument("--mutations", type=int)
a = p.parse_args()
text = a.log.read_text(errors="replace")
failures = []
if re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:|FAIL(?:[ :]|$))", text):
    failures.append("engine diagnostic or test failure")
pattern = rf"(?m)^{re.escape(a.marker)} checks=(\d+)(?: mutations=(\d+))? failures=(\d+)$"
hits = re.findall(pattern, text)
if len(hits) != 1:
    failures.append(f"expected exactly one completion summary, observed {len(hits)}")
else:
    checks, mutations, count = hits[0]
    if int(checks) != a.checks or int(count) != 0:
        failures.append(f"expected checks={a.checks} failures=0, observed {hits[0]}")
    if a.mutations is not None and (not mutations or int(mutations) != a.mutations):
        failures.append(f"expected mutations={a.mutations}, observed {mutations}")
if failures:
    for failure in failures: print(f"PROTECTED_BIRD_LOG_FAILURE: {a.log}: {failure}")
    raise SystemExit(1)
print(f"PROTECTED_BIRD_LOG_OK: {a.marker} checks={a.checks}")
