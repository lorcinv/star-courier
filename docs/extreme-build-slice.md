# pilot-v3: bounded extreme-build slice

Status: integrated development slice. New production runs select v3 in the controller, economy, world and HUD. Genuine committed v1/v2 snapshots still select their frozen simulators and saved route/fees. The six legacy simulation/profile/parts sources remain byte-for-byte unchanged. Actual-keyboard extreme-build comparison is still being validated.

This slice establishes assembly consequences, real overdrive, a contact drill and finite impact shielding. It retains the existing ascent-to-orbital-dock route. It does not implement additional ground, wormhole or otherworld routes, an export, or a delivery-balanced extreme route.

## Version and files

- `scripts/pilot_extreme_simulation.gd`: inherits the complete v2/v1/base simulation; stamps `pilot-v3` after all parent configure calls.
- `scripts/pilot_extreme_profile.gd`: retains the current ascent route and standard build; adds an explicit eight-engine test build. It does not modify the old profiles.
- `scripts/parts_expanded.gd`: returns all 25 original catalog entries, controls and parameters unchanged, plus one `drill` entry. The inherited base registry still has exactly 25 entries.
- `tests/test_extreme_builds.gd`: analytic loads, real graph breakage, work, circuits, contacts and replay fixtures, including adversarial same-tick interactions.
- `tools/extreme_build_probe.gd`: reproducible standard/eight-engine comparison from rest, without launch impulse or environmental drag.

A production integration must explicitly select v3, preserve its saved route and version, surface its shield/overdrive behavior in version-specific help, and continue routing older snapshots to their exact original simulator. The base catalog's old shield description remains correct for older protocols; v3 help must describe its extra collision behavior.

## Ordinary assistance and ungoverned overdrive

Ordinary control inherits the v2 route-tangent 18 m/s assistance, W/S lateral requests and 30 N requested net-force governor. A heavier many-engine craft therefore accelerates more slowly in ordinary mode. This remains the beginner-safe mode.

Shift changes the force request to the sum of all currently enabled and energized mounted engine ratings. It has no 22 m/s target and no fixed global thrust cap. W/S biases the overdrive heading up/down by up to 0.61 radians relative to the current route tangent. The torque allocator can trade some forward thrust for attitude control; actual nozzle output remains limited by each real engine, its installation angle, ±90° gimbal cone, paid slew rate, local circuit, valve and available energy.

Neither new control nor stress code assigns position, velocity, angle or angular velocity. The inherited integrator, contact response and explicit paid teleporter remain responsible for motion. Missing engines, disabled wiring, reversed mounting, cargo mass, asymmetric torque and exhausted cells remain meaningful. There is no added heat meter, free braking, invulnerability or velocity clamp.

### First measured comparison

Godot 4.6.3, seed 42, standard cargo weight, no research, open zero-drag route, no pad impulse, held neutral steering. The standard craft has 2 × 28 N engines, one 6,000 J cell, 8 modules and mass 10.2 kg. The practical reinforced craft has 8 × 28 N engines, two 6,000 J cells, 17 modules and mass 20.5 kg. It contains five ordinary 32 N beams; none has increased strength or hidden immunity.

| Build/mode | Speed at 1 s | Speed at 3 s | Speed at 5 s | Joules at 3 s | Joules at 5 s | Peak actual nozzle output | Structure damage |
|---|---:|---:|---:|---:|---:|---:|---:|
| Standard, ordinary | 2.941 m/s | 8.823 m/s | 14.687 m/s | 408.697 J | 1,111.915 J | 29.997 N | 0 HP |
| Eight engines, ordinary | 1.463 m/s | 4.390 m/s | 7.317 m/s | 221.583 J | 573.442 J | 30.000 N | 0 HP |
| Standard, overdrive | 5.289 m/s | 15.849 m/s | 26.416 m/s | 1,292.811 J | 3,570.584 J | 54.400 N | 0 HP |
| Eight engines, overdrive | 10.927 m/s | 32.780 m/s | 34.182 m/s | 11,038.256 J | 12,000.000 J | 224.000 N | 0 HP |

Average acceleration through 3 seconds is 5.283 m/s² for standard overdrive and 10.927 m/s² for eight-engine overdrive. All four comparisons retain one connected body and 100% cargo integrity. Peak socket loads for the overdrive builds are 13.023 N and 16.390 N. The eight-engine craft exhausts its finite cells shortly after 3 seconds and coasts at 34.182 m/s; adding engines does not provide free range. The measured kinetic-plus-stored-energy excess was zero (test tolerance 0.02 J).

These are propulsion comparisons, not successful extreme deliveries. Holding overdrive into the existing gates/receiver can crash or exceed the receiving platform's speed limit. Releasing Shift does not instantly brake the craft; real nozzle direction, available charge and route geometry still constrain recovery.

## Source-based socket loads

The frozen base applies almost all total body force to every beam. That makes extra parallel structural paths ineffective and breaks every beam when the whole craft exceeds about 32 N, regardless of placement.

Only v3 suppresses that old stress callback. At the same fixed step, it computes per-module rigid-body inertial demand minus actual applied force at that source module, including point rotational acceleration and centrifugal demand. A grounded, equal-stiffness socket-network Laplacian then finds the minimum squared edge-force solution. Real parallel paths share load; cut sockets are absent. Beam load is the greater of the largest incident socket force and half the sum of incident force magnitudes. Overload still costs `(load − actual strength) × dt × 6` HP, and destruction still removes real links, separates rigid bodies, and severs power/control circuits.

The solve is deterministic, uses stable ID ordering and at most 2N conjugate-gradient iterations, and accepts no more than 192 initial modules. Oversized input is rejected safely. Splitting still uses the inherited 192-module cap. This is a bounded game approximation, not elastic beam bending, material finite-element analysis or a six-degree-of-freedom mechanical solver.

Analytic fixtures establish that a 60 N series bridge transmits 60 N on both edges, while two equal parallel paths carry 30 N each. A heavy-payload single-bridge flight actually breaks its unchanged 32 N beam and splits. A rotating craft can fail centrifugally even without a large net translational force.

If a module acts before a same-tick split/rebuild, the inherited integrator redistributes its already-accumulated force by module mass. v3 mirrors that precise carried-force field before accumulating later sources; it does not leave the entire prepaid force attached to the departed engine. Tests verify source totals equal the force actually integrated on each resulting island.

## Contact drill

- Catalog type: `drill`; display name: 接触钻头; mass 1.8 kg; price 65; HP 60; ordinary non-beam socket strength 90 N.
- One input, no target, no tunable parameter. Unwired runs automatically; cockpit `-2` or ordinary logic wiring controls it through the existing living circuit rules.
- Motor draw: 60 J/s × actual output factor. Cutting budget: 100 HP/s × the funded output fraction. Partial energy or a power valve reduces both. Spinning in free space still costs motor energy.
- Cutter geometry: circle centered 0.30 m forward from the module center, radius 0.18 m, rotated with the actual module and scaled with its real size-ring scale. It fits the ordinary one-cell footprint. It is not a ray or an area-damage aura.
- It can cut only an intersecting forward-facing, living, destructible obstacle. It never cuts other ship modules or gravity hazards. `pilot_gate=true` and `destructible=false` obstacles are not cut. Ordinary impacts against them still happen.
- Each drill has at most one damage budget per physics tick. Multiple overlapping obstacles cannot multiply it. An already-powered drill split later in the same tick cannot duplicate prepaid work: the original retains only its reduced output, and its new clone has no paid motor entry until it can actually draw power on a later step.
- The forward head is swept across translation and rotation. Conservative arc broad-phase inflation is followed by an actual rotating-head overlap refinement; a near miss cannot cause damage merely because the conservative bound was large.
- Cutting that happens early enough can remove a sufficiently weak rock before the hull reaches it. Surviving rock still participates in inherited swept collision and knockback. A 1,000 m/s hit receives at most one fixed-step cutting budget, not enough damage to remove an arbitrary obstacle.

Cut and hull-contact events share one deterministic chronological event loop. All bodies advance to the next event together; after a real impact, remaining motion is predicted from the changed linear/angular velocities and swept again. Already-hit bodies stay in the solver. A later cut cannot erase an earlier collision, a destroyed hazard cannot cause a stale later hit, and one craft can bounce between multiple hazards within a single step. Equal-time events use stable type/module/target ordering. A swept whole-body broad phase avoids repeated module tests between unreachable pairs. Only the contact island containing the verified, physically touching seed participates in pooling. Simultaneous collinear free-body contact chains use a mass-weighted isotonic impulse solve: larger contact pools are inelastic and preserve momentum while dissipating kinetic energy; isolated two-body contacts retain the original restitution. This prevents a settled contact pile from recursively re-impacting at zero time. Cumulative momentum changes identify every active impulse-transmitting edge, including initially resting edges; those edges mark collision switches even when their initial approach speed was zero. Unrelated contact islands cannot veto or substitute for the seed event. The bounded event budget is 32–256 event rounds depending on assembly size. If a pathological pile exhausts it, the solver holds the last resolved poses for the remaining substep and reports `ccd_budget_holds`, rather than tunneling or capping velocity. The inherited resting-overlap fallback runs afterward with duplicate swept contacts and drag disabled only for that call.

Contact motor on/off fixture: 1 second of stationary front-head contact destroys an 80 HP rock while consuming 60 J; the disabled version leaves 80 HP and consumes zero. Reverse/side contact, empty charge, disconnected cockpit circuit, million-HP gate tower, partial motor power, high-speed contact, early clearing, and blocked-behind-an-earlier-impact cases are covered.

### Art/renderer contract

One 72×72 RGBA sprite represents one 1 m cell. Rotation/picking anchor is (36,36). Rotation 0 points right. The cutter head center is approximately (58,36), with diameter 26 px and front tip at x≈71. Keep it inside x45–71 and y23–49. Main housing stays inside the ordinary 0.43 m body circle (about 62 px diameter). Expected derivative path is `res://assets/2d_v5/modules/drill-pixel.png`; art registration is owned separately and is not validated by these physics tests.

Powered contact emits at most one short `drill` effect per 0.08 s per drill through the existing bounded effect pool. Production rendering must consume that effect and `drill_power_ratio`; no art or shader is required to pass these headless fixtures.

## Finite impact shields

Only v3 adds collision absorption. Legacy v1/v2 shields remain attack-only.

- Across all shields, no more than 65% of one collision's HP damage can be absorbed.
- One shield absorbs at most 24 HP × actual output factor in one 1/120 s tick, shared across all impacted modules.
- Every absorbed HP costs 1.5 J from that living circuit. Empty, disconnected, disabled or valve-blocked shields cannot protect it.
- Each shield/valve pair has one aggregate tick budget shared by repeated collision callbacks and attack absorption. This prevents repeated contacts from granting multiple J/s allowances to the same consumer. An untargeted valve adjacent to different modules retains the legacy per-consumer rate contract, so two distinct shield consumers are treated consistently with two thrusters.
- The collision impulse formula, separation and angular knockback remain physical; only the v3 event ordering/resweep is improved. Residual HP damage is always applied. Stress is not collision damage and is not shielded.

A 20 HP test hit leaves cargo at 93 HP with a powered shield (13 HP absorbed for 19.5 J), versus 80 HP with shield off. A 100 HP hit against one fully charged shield still deals 76 HP. Only 6 J buys 4 HP absorption. Actual on/off collision fixtures produce exactly equal linear and angular post-contact velocities.

## Verification

The final focused suite passes 122 assertions in 7.73 seconds on the current cloud executor. The comparison probe also passes unchanged after the contact-solver edits. All six frozen source hashes match the original checkpoint. It includes the 26-entry/unchanged-25 registry, analytic force sharing, real fracture and islands, overdrive output/energy/mass, empty/disabled/disconnected/valved controls, all inherited distinct device functions, drill geometry/rotation/temporal ordering, splitting paid drill output, finite shield absorption and combined valve accounting, swept collision, fast teleport exit clearance, bounded effects/module count, exact JSON build replay and 60 Hz versus two 120 Hz stepping.

Run with isolated writable Godot state:

```sh
mkdir -p /tmp/courier-extreme/{data,config,cache}
export XDG_DATA_HOME=/tmp/courier-extreme/data
export XDG_CONFIG_HOME=/tmp/courier-extreme/config
export XDG_CACHE_HOME=/tmp/courier-extreme/cache
godot --headless --path . --script tests/test_extreme_builds.gd
godot --headless --path . --script tools/extreme_build_probe.gd
```

### Dense-contact recovery and timing

A 24-body pathological fixture starts alternating bodies at ±1,000 m/s, only 0.001 m apart. High HP is confined to this collision-geometry test; no production part strength or HP is altered. Before the pooling fix, all eight tested ticks hit the 240-event bound and took 712–725 ms apiece without recovering. The final version resolves 260 active contact-constraint edges across 46 chronological event rounds during the first tick, then zero contacts on the next seven ticks, with zero budget holds. The round limit is 240; one simultaneous pool can legitimately contain multiple constraint edges. Bodies remain finite and ordered; momentum error is 7.1×10⁻¹¹ kg·m/s. Kinetic energy falls from 17,600,000 J to 37,233.595 J, so the simultaneous impulse solve creates no kinetic energy.

Final measured tick times are 45.232, 1.300, 1.199, 1.192, 1.226, 1.182, 1.164 and 1.172 ms (mean 6.708 ms). A second fixture adds an unrelated stationary oblique contact island; it also resolves with zero holds, at approximately 47.5 ms then 1.4 ms. That unrelated island keeps its original position, velocity and HP. This is a bounded stress-case recovery result on the current executor, not a Windows/RTX or general worst-case performance guarantee. Non-collinear pathological piles still retain the bounded safe-pose fallback, reported by `ccd_budget_holds`.

Run this probe separately with `godot --headless --path . --script tools/extreme_build_probe.gd -- --contacts-only`. It emits per-tick contacts, hold counts and timings as JSON. The main focused suite now permanently asserts that this formerly stuck case really runs, preserves order/momentum/energy, and settles on subsequent steps.

### Integration API

Use `ExtremeProfile.CONTROL_VERSION` or `ExtremeSim.EXTREME_VERSION`, both `pilot-v3`. Do not read the inherited `ExtremeSim.CONTROL_VERSION`: that constant is the frozen v1 constant. `configure(design, launcher, stored_route, seed)`, `set_pilot_input(axis_q, boost, active)`, `step(dt)` and existing public queries retain their signatures. Build new routes with `ExtremeProfile.route()`; replay the stored route verbatim.

Existing ascent telemetry remains present. New fields are `overdrive`, `thrust_requested`, `thrust_actual`, `drill_energy_used`, `drill_damage`, `drill_contacts`, `impact_absorbed`, `impact_shield_energy`, `peak_socket_load`, `structure_damage`, `ccd_budget_holds`, `ccd_contact_pools` and `ccd_event_rounds`. No HUD should describe Shift as a 22 m/s target in this protocol. A live drill carries `drill_power_ratio`; the registry supplies its one input, fixed zero parameter and no target.

Production controller integration now passes 127 checks, including genuine old-v1/v2 migration, full-power/drill input persistence, exact successful trial/formal replay, saved custom fee and unique settlement. Renderer/HUD passes 103 focused checks, with inspected scripted Godot frames at logical 960 and 1280. The complete 37-suite aggregate passes 3040 assertions plus 240 static NPC checks; normal starter smoke remains 32.7667 s, 100%, 2734.359 J. These checks are not native keyboard or Windows acceptance.


## Useful combined cutter build

`tools/drill_approach_probe.gd` uses the production simulator directly. The reinforced eight-engine frame plus a front cutter and four connected shields totals 22 modules. At a disclosed test initial speed of 18 m/s, it clears an ordinary 80 HP rock in 0.0667 s, preserving 100 cargo HP and 14.073 of the drill's 60 HP. Four shields absorb 85.293 HP for 127.9395 J. Momentum still causes visible recoil. With the motor disabled, the same build remains blocked after 4 seconds; with shields disabled, the cutter is destroyed. At 34 m/s the finite protection is overwhelmed and the cutter dies. The tool does not cut a gate tower.

A separate course starts from rest with no launch impulse or assigned velocity. Actual mounted engines reach 17.9845 m/s at an 80 HP rock at x220, clearing it at 19.7333 s while retaining cargo100%, drill14.151 HP and more than 6500 J at impact. The motor-off control reaches the same impact speed/damage but does not clear the residual rock. `tests/test_drill_shield_build.gd` adds 21 focused assertions for these on/off controls, charge, recoil, a no-hit lane, gates, slow approach, excessive-speed failure and full power after clearance.

A lone unprotected drill is a slow contact cutter, not a high-speed ram. With continued ordinary thrust it can cut an80HP rock from2–10m/s; at18m/s it is destroyed on first impact. The multi-shield combination is therefore a real assembly tradeoff, not immunity or a global reduction in obstacle health.
