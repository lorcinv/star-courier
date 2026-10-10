# pilot-v2: physical city-to-station ascent

This is an additive versioned flight profile. Existing `pilot-v1` and autonomous-v5 saves must continue to instantiate their original simulators and replay their original stored route/build/input data. The new profile is a fictional 520 m flight lane with 150 m of actual vertical rise; it does not claim that 150 m is a realistic orbital altitude.

## Route and controls

- Coordinates remain metres. Up means negative world Y. The receiver is `(520, -150)`, with a 9 m reception radius and a real 24 m/s entrance-speed limit.
- Departure is level until nominal X=35. Between X=35 and X=410, `u=clamp((x-35)/375,0,1)` and the nominal lane is `y=-150*u²*(3-2u)`. Its tangent changes continuously, reaching about 31° upward in the middle, then leveling before the receiver.
- Automatic forward assistance requests 18 m/s along the current route tangent, or 22 m/s with boost. It never sets ship position, velocity, angle or angular velocity. There is no positional lane capture or automatic gate steering.
- W/Up requests -5 m/s across the tangent; S/Down requests +5 m/s. In this upward lane, these remain intuitive upward/downward corrections. Releasing the key requests zero across-tangent speed through the same real powered nozzles.
- Desired attitude follows the changing route tangent plus a small steering pitch. Actual torque comes from each nozzle's force crossed with its real lever arm. The inherited ±90° installation-relative gimbal cone, 240°/s slew, energy budget and valve limits still apply.
- A 30 N allocated-net-force governor protects the unmodified 32 N structural beams. It does not increase their strength or absorb impacts. Transient gimbal slew can make the instantaneous sum slightly different; the verified builds remain below damaging beam load. Raising the governor in a test makes the real beams break.
- The eight-module starter preserves v1 IDs, grid coordinates and module types. Its two engines are set to 28 N, within the existing 0–40 N editor schema. The one-support launch spring remains 20 J; raising it enough to benefit light cargo would overload that support on the heaviest cargo. The paid launch impulse is therefore mass-dependent.
- Cargo mass, reduced engine parameters, engine removal/reversal, circuit cuts, valves and empty cells all retain physical consequences. The governor also means that adding engines beyond the net limit primarily improves force allocation/torque authority rather than granting unlimited acceleration.

## Gates and useful preview

Physical gate centers are at X=105, 220, 330 and 465 m. Their lane-relative Y offsets are -9, +7, -7 and 0 m. Each opening is 20 m high, formed by two real 5 m radius circular towers whose centers are 15 m above/below the gate center. Generated static gate centers use a 1/1024 m binary grid so the complete saved route survives Godot JSON parsing exactly. Gate spacing is 110–135 m after departure, at least 5 seconds at nominal boost. The last gate has additional leveling distance for heavy cargo.

The first gate deliberately requires an upward correction. Holding neutral throughout is tested separately and does not deliver: physical gate contact changes/damages the craft and it misses the receiver. This is collision gameplay, not a scripted failure condition. Correct keyboard steering preserves the cargo and both beams.

Render the ship at a legible scale. `lookahead_m` is a predictive HUD range, not a demand to fit that entire distance in the camera. The presenter uses bounded speed-dependent zoom values .35/.30/.27/.24 and puts the ship about16% across the view. Pullback is monotonic within a flight so speed thresholds cannot cause camera hunting. A rendered-bounds probe at1280×800 sees at least one substantial real rock silhouette2.9–3.5 seconds before gate crossing. Both sides of an ascending gate are not necessarily visible that early; this is not a human-play fairness certification. Keep the off-screen next-gate cue and its time/altitude/direction as supplemental guidance. Use actual negative ship Y for altitude/background transitions, not horizontal route progress. The telemetry supplies a 3.5-second inertial forecast alongside the real gate data.

## Finite energy and billing integration

The larger kinetic energy requires an explicit route-only charge/storage rebalance:

| Field | Value / meaning |
|---|---|
| `control_version`, `pilot_profile` | `pilot-v2` |
| `pilot_battery_multiplier` | 20.0; a base 300 J cell holds a finite 6000 J for this profile |
| `battery_capacity_multiplier` | Existing independent station research, bounded 1.0–1.45 by the unchanged base simulator |
| `pilot_energy_tariff` | 0.025 credits per actual joule consumed |
| `pilot_net_force_limit` | 30 N requested allocated net thrust |
| `pilot_altitude` | 150 m fictional lane rise |
| `pilot_climb_start`, `pilot_climb_end` | 35 m, 410 m |

The subclass applies the 20× factor once when a battery is instantiated, including batteries on the anchored pad. A single flight cell thus holds 6000–8700 J depending on research. There is no mid-flight refill. Spring launch costs, kinetic work, idle exhaust costs, nozzle slew, and all other device costs still enter `energy_used` in real joules. Split cells retain divided energy and capacity. `telemetry.battery_capacity` reports the actual live flight-cell capacity; show it honestly rather than the unchanged global 300 J component spec.

For pilot-v2 settlement only, bill `ceil(energy_used * pilot_energy_tariff)`. Keep the prior 0.18 credits/J for all legacy protocols. Store the v2 route fields in the immutable dispatch snapshot. Do not reinterpret or migrate an already-launched v1 flight into v2. The simulator's `configure` explicitly restores `pilot-v2` after calling the parent, because the frozen parent stamps its own version.

## Rendering / HUD telemetry contract

Existing pilot keys remain, including integer `pilot_tick` (120 Hz substeps), `pilot_axis_q`, `pilot_boost`, `pilot_active`, `forward_speed`, `vertical_speed`, `route_progress`, `next_gate_distance`, and `next_gate_y`.

New fields:

- `speed`: actual velocity magnitude, m/s
- `altitude`: actual `-cargo_position.y`, m
- `target_altitude`: 150 m for the profile
- `route_heading`, `ship_heading`: radians, negative when pointing upward
- `lane_y`, `lane_offset`: current nominal Y and actual signed offset
- `flight_phase`: `city`, `climb`, `approach`, determined by the route's X transition positions; background blending should still use actual altitude
- `lookahead_seconds`, `lookahead_m`: predictive cue horizon/range, not compulsory camera zoom
- `predict_x`, `predict_y`: present position plus present velocity times the prediction horizon
- `battery_capacity`, `pilot_battery_multiplier`, `pilot_energy_tariff`
- `next_gate_index`: -1 after the last gate
- `next_gate_time`: estimated seconds using actual forward speed, -1 after the last gate
- `next_gate_altitude`, `next_gate_heading`, `next_gate_half_gap`
- `next_gate_dx`, `next_gate_dy`: actual displacement to that gate
- `next_gate_direction`: -1 up, +1 down, 0 aligned within 1 m of the tangent forecast. This is a HUD suggestion only; the simulator never feeds it into pilot input.

## Verification and reproducible keyboard sample

`tests/test_pilot_ascent.gd` uses held binary keyboard states, never analog steering. A test-only observer chooses W/release/S every 12 command ticks (0.2 s), using the gate's lane offset and a stopping-distance forecast based on actual mass and force. Its output is a sparse 60 Hz timeline; each held command is applied to both 120 Hz physical substeps. The live game must never call this observer.

Running the suite writes `/tmp/courier-ascent/keyboard-standard.json`: a reproducible standard-weight, seed-42 command schedule, with tick 0 immediately before the first 1/60 s step. For native OS-input QA, synchronize to the launch/physics start, apply W for `axis_q=-1000`, S for `+1000`, release both for 0, and apply each event at `tick/60` seconds. Boost and active are false in this sample. OS event timing is not expected to be bit-exact; the separate simulator JSON replay test is bit-exact. Real keyboard QA must verify it through the normal input path rather than injecting the observer into live simulation.

The focused suite covers actual altitude rise and level arrival, startup speed at 1/3/5 seconds, greater-than-3× v1 cruise, standard/day-one-heavy/max-weight binary delivery, boost, neutral-input failure, mass/engine changes, missing/reversed engines, finite work, empty-cell coasting, valve/servo accounting, real high-speed swept collision, spawn/teleport exit safety, all 25 distinct module functions, JSON input replay, and byte-preserved old replay sources.

### Measured headless results

The current profile passes84 focused physics assertions, with85 additional real-controller/save integration checks. The latter covers16 successive exact JSON route round trips, genuine v1 migration, custom v2 route/tariff preservation, and supported-but-conflicting protocol rejection. Values below use the fixed starter, seed 42, no research and held binary keys:

| Cargo weight multiplier | Mode | Delivery time | Actual altitude | Peak actual speed | Energy consumed, including pad | Flight-cell reserve |
|---|---|---:|---:|---:|---:|---:|
| 1.00 | Cruise | 32.833 s | 149.795 m | 19.721 m/s | 2627.189 J | 3392.811 J |
| 1.55 | Cruise | 33.583 s | 149.390 m | 19.290 m/s | 3032.903 J | 2987.097 J |
| 4.34 | Cruise | 38.083 s | 149.777 m | 18.366 m/s | 4520.702 J | 1499.298 J |
| 1.55 | Boost | 29.667 s | 150.060 m | 22.630 m/s | 3924.434 J | 2095.566 J |

All four runs preserve 100% cargo integrity. The cruise runs finish the level approach with vertical speed magnitudes 0.015, 0.028 and 0.154 m/s respectively. The 18/22 m/s values are force-controller requests; actual transient speed can overshoot because there is no magic velocity clamp or free braking.

Standard actual speed at 1/3/5 seconds is 4.717/10.063/14.861 m/s (forward 4.507/9.631/14.849). Day-one heavy actual speed at those times is 4.188/9.011/12.992 m/s. The maximum 20.22 kg loaded craft reaches 2.774/5.695/8.213 m/s: its slower acceleration is the real consequence of the same 30 N force limit, not a hidden exception.

The neutral run first contacts a physical gate at 8.075 s, damages structural modules and eventually misses the receiver at the70.000s route timeout after the binary-grid placement correction. It does not receive a special neutral-input penalty. The standard corrected run uses 24 sparse input events, each at least 0.2 s apart.

The standard seed-42 schedule is also recorded here as `command_tick:key`; `-` means release both W and S. All other controls remain released. The last event holds neutral through delivery at 32.833 s:

```text
0:W 156:- 348:W 384:- 396:W 408:- 420:W 444:-
468:W 492:- 516:W 528:- 540:W 552:- 564:S 708:-
972:W 1104:- 1116:S 1284:- 1380:S 1536:- 1584:S 1656:-
```

The unchanged `tests/test_pilot_simulation.gd` also passes all 59 pilot-v1 assertions, including its original 300 J physics and 128 m route. No graphical game process was started for these focused checks.

Run headlessly with writable XDG directories, for example:

```sh
mkdir -p /tmp/courier-ascent/{data,config,cache}
XDG_DATA_HOME=/tmp/courier-ascent/data \
XDG_CONFIG_HOME=/tmp/courier-ascent/config \
XDG_CACHE_HOME=/tmp/courier-ascent/cache \
godot --headless --path . --script tests/test_pilot_ascent.gd
```

The preserved source hashes are:

```text
41031fc568aa5aa2c37c023b5b162ff9f24dd3db97e2fd6dec14dadb207132dd  scripts/pilot_profile.gd
81b7d5bdb4514663d3d89c0ae7cf7a510344d53cecfcf05f205ae97af727acd6  scripts/pilot_simulation.gd
582e188f09949cb969a4f0a73dbd97d58f2df38ec17f76568eb229ecfecf369e  scripts/simulation.gd
```
