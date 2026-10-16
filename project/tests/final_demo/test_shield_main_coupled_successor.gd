extends "res://tests/normal_pirate_shield_main/test_shield_main.gd"
## Named first-Demo successor of the already-passed 60-check paid shield chain.
## Only boot changes: bind the current factory before Main/World._ready and
## assert the coupled World is active. All original actions, physics, guide,
## accounting, loading, result/return and delayed-review checks are inherited.
## No old animation assertion is ported or relaxed. See ASSERTION-AMENDMENTS.md.
const DemoBootstrap=preload("res://scripts/clerk_runtime_bootstrap_observed_v4.gd")
func boot() -> bool:
 await dispose()
 game=Main.instantiate()
 game.clerk_pose_bootstrap_script=DemoBootstrap
 root.add_child(game);game.set_process(false)
 if is_instance_valid(game.world):
  game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames(4)
 if not check(not game.economy.review_load_blocked and not game.pilot_resume_blocked and is_instance_valid(game.world),"actual Main boots the private earned-save shop without recovery hold"):return false
 return check(game.world._clerk_pose_setup_error.is_empty() and game.world._clerk_pose_consumer_enabled and game.world._clerk_motion.world_consumer_contract_version()>=2,"merged Demo factory initializes coupled World before ready on every actual Main boot")
