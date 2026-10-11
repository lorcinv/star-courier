# Final-fuel tick explicit intent oracle

Small test-only supplement to Library `libfile_d8b383953a108191bb43b8900d2e0aa4`.
No runtime module, solver, old package or public game file was modified.

## Native observation

Official Godot 4.6.3 (`4.6.3.stable.official.7d41c59c4`) passed this one bounded
run, exit 0, empty stderr. The test reaches the state by normal API calls rather
than editing fuel or charge history.

| Call order | Observed state / returned output |
| --- | --- |
| Precondition at tick 238 | 59 charges, 1000mJ fuel left, HP25 |
| `advance(239)` | Returns `[paid actor_force_intent, resource_exhausted cancellation]` in that order. Force spans fraction 0..1; cancellation is at fraction 1. Final 1000mJ is already reserved. Fuel0, total reserved60000mJ, 60 charges. |
| Segment query 0..0.25 | Saved live segment, HP25 |
| External lethal `rebase(239, 0.25, revision1)` | HP0; returns no intents because helper warning phase was already cancelled. Existing exhaustion notice remains at fraction1. |
| Segment query 0.25..1 | Same retained actor, HP0, supplied wreck velocity (-1.5,0.25); existing linear query produces sliding endpoints. |
| Duplicate identical rebase | Inert, no new notice, refund or debit |
| Typed restore | All state bits and post-death segment hash match exactly |
| `advance(240)` | Wreck retained; no new intent or fee |

## Required future-owner behavior (oracle, not a simulated solver result)

The common chronology owner must distinguish return order from event time:

1. Keep the already returned paid force eligible before the earlier HP0 event.
   A phase already marked cancelled for fraction1 must not erase that return.
2. At fraction0.25, stop force on this source because its HP reached zero.
   Absence of another cancellation intent does not authorize continuing force.
3. Preserve the wreck body and its authoritative saved movement after death.
4. Keep the final 1000mJ reservation: refund0, additional debit0. The test does
   not compute actual applied work, contact impulses or prorated refunds.
5. The previously returned exhaustion notice remains a fraction1 notice; do
   not manufacture an additional helper cancellation.

`ORACLE.json` keeps eight ordered calls with actual intents and segment returns.
`ORACLE_TYPED.json` preserves their float64 bits. Two complete typed snapshots
show the paid state and the earlier-death state. Raw stdout prints each stage;
all logs are the unedited output of this single native run.

## Exact sources

Test SHA-256:
`e8134f62d562564ea73f2013642beff5055528b0e6e4eb69ae9227b1e01141f2`

Unchanged actor module SHA-256:
`d00aec1b65d49159f7b95ab0e73939d2d049d3aa85867425a87b66aae7f66455`

The source manifest contains all six exact tested files. Oracle typed hash:
`960b8f91303e203206e8e463d45881580a0321d5d9f84ffd95f4d13892d81d41`.

## Re-run

Create a writable evidence directory, set SC_GROUND_QA_DIR to its absolute path,
and use official Godot 4.6.3 with isolated user data:

```text
GODOT --headless --path source --script res://final_fuel_oracle/test_final_fuel_tick.gd
```

Require exit0, final passed=true, nonempty oracle_hash and no engine diagnostics.
No complete-game or common-solver integration result is claimed.
