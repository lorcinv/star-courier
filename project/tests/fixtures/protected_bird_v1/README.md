# Protected-bird v1 permanent fixtures

These are immutable inputs. Generated observations belong only under
`user://protected_bird_v1/`, inside the aggregate runner's fresh writable data
context. Never overwrite these inputs when replaying or regenerating witnesses.

- `legacy_1_0/pre_validator_hardening/`: exact original D4 safe/harm JSON bytes,
  weight 1.0, seed 42. Validator mutation tests use this historic route and harm
  witness. They are not evidence for the commercial offer.
- `commercial_2_4/`: exact D5-A offer JSON bytes, id 3, rep 7, weight 2.4, reward
  340, required 90.0, seed 670371318, battery multiplier 1.0. Safe and harm
  generation must still produce all four exact frozen files.
- `fixture_io.gd`: test-only checked output/read helper. It creates parents,
  checks open/write/flush/readback errors, closes handles, rejects source writes
  and traversal, and reports failures as data for the harness to fail explicitly.
- `source_contract.json`: authoritative SHA-256 values for frozen runtime inputs,
  all eight ported tests, golden bytes and helper/runner files. It does not
  authorize a runtime change or regenerate goldens.

## Real paid negative-root regression

`test_protected_bird_rays.gd -- --repro` is a permanent 49-assertion gate covering
six actual paid shots: lance and arc, each with a wholly behind bird, rock, or
module. Ordinary shrink reaches emitter scale 0.2 before the gated paid shot.
Geometry and source checks are unchanged from the corrected authoritative test:
behind bird (-0.35, 0.35), radius 0.375; behind rock (-4, 4), radius 5; behind
module (-0.4, 0.4), radius 0.43. All shells clear the bird before the shot.
The full 216-assertion suite additionally retains tangent/range/inside boundaries,
real occlusion, power/circuit negatives, inherited ordinary beams and v4 parity.
The original solver failed 18 of these 49 repro assertions; the corrected runtime
must pass all of them. The original failed observation bytes and corrected source
manifest remain preserved in the portable overlay package's provenance archive.

## Replay contract

Run each route's generation and `--replay` in one freshly created HOME/XDG context.
Never copy immutable inputs into its output folder. Replay reads the freshly
written user-data report and snapshot. A missing or unreadable write is a failure,
not a reason to fall back to source reports. The runner still runs independent
suites after failures, requires exact completion counts and rejects diagnostics
from a zero-exit engine process. All processes retain the existing 300-second
limit; timeouts are failures and are not hidden by increasing the timeout.

## Exact numeric evidence revision 2

This assembled package additionally retains current ray-fix 1.0 kg witnesses in
`rayfix_v1/legacy_1_0/`. The original historical directory above remains unchanged.
The new reports and replay inputs were reconstructed twice in independent fresh
contexts before freezing. Terminal binary64 sidecars bind the exact native energy
and HP bytes to the complete report hash and simulator/sweep identities. Replay
must compare those bytes; Godot 4.6.3 parses one emitted decimal energy one ULP away
from its generating native value. No approximate comparison is permitted.

The numeric-witness negative suite retains that parser counterexample and proves
that actual one-ULP replay changes are rejected. Historical solver-source manifests
and the one-variable sweep proof are in the separate numeric-v2 provenance package.
This is test-evidence versioning only; no route, solver or save/replay schema changes.
