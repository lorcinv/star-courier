# Isolated FG01 full-body pose experiment

Baseline production commit:63b4855bcc32818b4b3a593a15fdea80eb74ebbc.
Read contract/local-pure-pose-contract.md and inspect its two comparison PNGs. This is a provisional measured raster geometry, not approved final art.

Write only a staged replacement for scripts/clerk_rigid_pose_2d.gd and your new pure tests/reports. scripts/shop_locomotion_2d.gd is the unchanged root-motion owner. Keep contract/candidate-rig-registration-fg01.json unchanged and configure the candidate sampler explicitly with that file. assets/.../rig-registration.json is the prior baseline for comparison, not the candidate. Reference renderer/tests are included for API reading only and their wider resource dependencies are intentionally not supplied.

The parent may authorize the existing Windows Godot4.6.3 for HEADLESS pure-pose tests only; this supplements the contract's cloud engine-lane restriction. No native window, full-game integration, controller or art edits, new software, or local quota polling is part of this task. Root owns the user's 30-minute quota monitor: near50% finish current bounded slice; at40% stop local and return work.

Required output: one staged sampler with explicit world-space upper-body outputs; reproducible exact tests; per-sample typed snapshots/metrics; original and new source hashes; minimally reproducible failing trace if immutable geometry cannot meet bounds. Head scale/asset changes remain cloud-owned. Stop after one candidate mechanical gate; no claim of visual approval.

Additional measured failure after the initial contract: the recorded join-to-escort transition at7.508s drops hip y to-63.761 native pixels versus nominal-94.463 (30.7px drop), with trailing upper-boot mount48.2 parent pixels behind its hip. Repeated ordinary steps still drop about15.2px. All158 moving observer samples keep head_angle0. Preserve this counterexample when evaluating transition/reach changes.

Package SOURCE-MANIFEST.json binds every other file. Verify it and do not overwrite the incoming directory; create a separate candidate work directory. No production/remote changes are authorized.
