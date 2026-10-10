# pilot-v1 · City → orbital station

One controllable, fictional **128 m delivery lane**. Earth-to-orbit ascent, moon routes and wormholes are future work.

## Protocol and physical controls

`pilot_simulation.gd` subclasses the **unchanged** autonomous simulator. Old in-flight saves must instantiate `simulation.gd`. New snapshots explicitly carry `mode="pilot"`, `control_version="pilot-v1"`, blueprint, launcher, JSON-safe route, seed and input timeline.

Before each **60 Hz command frame**, call `set_pilot_input(axis_q, boost, active)`. Integer axis −1000…1000 means up…down; keyboard uses −1000/0/+1000. Each command is held for two **120 Hz physics ticks**; `pilot_tick` counts physics ticks. W/S or arrows steer, Shift boosts, Space supplies a held signal. Pause advances neither clock.

Only enabled, cargo-connected **real thrusters** provide pilot control. Their installation-relative gimbals cover ±90° at a finite 240°/s. Ordinary thrust is bounded by 72% of each nozzle's configured force; boost permits 100%. The allocator requests horizontal speed 4.8 m/s (boost 7.2), vertical speed up to 1.8, and attitude stabilization, then fits those requests to actual nozzle positions and directions. Targets never directly edit velocity or position. Reversed nozzles cannot push forward; bad lever arms, missing engines, mass and inertia change handling.

Thrust pays its positive translational/rotational kinetic work or **1.5 J/N·s**, whichever is greater. Gimbal motors cost **0.08 J/rad +0.04 J/s** per working nozzle. Both share one connected battery/valve budget, including partial-power slew. No free reaction wheel, lift or cruise is added. Environmental drag is 0.025 kg/s. Empty craft coast without steering; detached engines retain their last nozzle angle and own circuit's energy.

Cockpit source **−2** is valid only for input A/B, never targets. It becomes false across structural separation. It feeds the ordinary gates, delays and actuators; Space never triggers all devices. Dampers still dissipate motion, rotators turn targets, valves constrain flow, armor intercepts at its own position, shields spend electricity against attacks rather than impacts, and teleporters retain their 25 J cost.

## Starter, route and measured balance

**Eight modules, 10.2 kg, 300 J:** cargo(0,0), battery(−1,0), armor(1,0),12 N right-facing thrusters(0,−1)/(0,1), beams(1,−1)/(1,1), coupler(−1,1). Their vertical thrust passes through the horizontal center of mass. The supported launcher supplies 20 J once. Inventory counts and legacy specifications stay unchanged.

Gates at x=28/58/88/111, center y=−1.7/+1.7/−1.7/0, opening height 5.2. Station tractor collection field: center(128,0), radius 6, maximum entrance speed 10 m/s. **Deadline 42 s; timeout 65 s.** Camera telemetry requests at least 22 m or 3.5 s preview. Profile adaptation is idempotent and preserves commercial customer/reward/weight fields.

| Measured build/input | Time | Cargo | Battery left | Energy bill / net |
|---|---:|---:|---:|---:|
| Smooth quantized guidance, seed27 |26.917 s|100%|68.34 J|46 /119, reward165|
| Keyboard-only −1/0/+1, seed42 |27.033 s|100%|53.75 J|48 /117, reward165|
| Actual heavier order, weight1.55 |27.317 s|100%|14.19 J|56 /164, reward220|
| Balanced two extra armor,13.0 kg |27.483 s|100%|0 J|58 /107, reward165|

The armored build finishes by coasting with no reserve. Continuous boost is not promised to finish. Existing 0.18/J billing, prices and battery capacity remain unchanged.

## Collision and evidence

Each fixed step sweeps module circles against moving obstacles and separate bodies. Rotation uses subdivided arcs with conservative curvature inflation. First impact rewinds affected bodies, applies an impulse and conservatively discards their remaining substep motion. Spawns require whole-craft clearance. Teleports deliberately skip transit obstacles but require full endpoint clearance and 0.22 s linear exit clearance, preserving velocity. Swept station crossings still enforce speed limits. This is a circular-module approximation, not polygon friction or exact simultaneous-contact dynamics.

`tests/test_pilot_simulation.gd`: **59 assertions**, including complete keyboard/heavy routes, exact 60/120 Hz and JSON replay, finite power, valves, device distinctions, signal cuts, thin-obstacle/body-body/angular CCD, safe teleport, receiver speed and 40 s changing-input energy accounting. Unchanged legacy suites pass **76 simulation + 135 invariants**. Main/UI/pause/persistence/render integration is tested separately.
