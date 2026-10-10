extends SceneTree
## Live-controller composition proof. Screenshots are labelled fixtures, not
## evidence of native pointer/keyboard interaction or an earned playthrough.
const Tier=preload("res://scripts/workshop_profile.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var game
var tag:String="workshop-scene"
func _initialize() -> void:run.call_deferred()
func fixture_design(tier:int) -> Array:
 var bounds:Rect2i=Tier.bounds(tier);var result:Array=[];var id:int=1
 for x in range(bounds.position.x,bounds.end.x):
  result.append(Profile.part(id,"battery" if x==bounds.position.x else "thruster" if x==bounds.position.x+1 else "beam",x,bounds.end.y-1));id+=1
 for y in range(bounds.position.y,bounds.end.y-1):
  result.append(Profile.part(id,"cargo" if y==bounds.position.y else "beam",bounds.end.x-1,y));id+=1
 return result
func capture(label:String) -> void:
 await create_timer(.30).timeout
 game.world.smooth_center=game.world.target_center;game.world.smooth_zoom=game.world.target_zoom;game.world._update_camera()
 await game._capture("v5/"+tag+"/"+label)
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--tag="):tag=arg.get_slice("=",1)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/v5/"+tag))
 root.size=Vector2i(1280,720)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 # Explicit isolated fixture inventory; this is not an earned-gameplay claim.
 for kind in ["beam","battery","thruster"]:game.economy.inventory[kind]=64
 game.settings.quality="standard";game.settings.reduced_motion=false;game._apply_quality()
 game.set_process(false);game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await process_frame
 game.navigate("hub");await capture("00-original-hub")
 for tier in [1,2]:
  game.economy.workshop_tier=tier;game.design=Profile.starter_design();game.navigate("hub")
  await capture("tier%d-hub-starter"%tier)
  game.navigate("workshop");await capture("tier%d-workshop-starter"%tier)
  game.design=fixture_design(tier);game.render();game.workshop_input.fit()
  await capture("tier%d-workshop-large"%tier)
  game.navigate("hub");await capture("tier%d-hub-large"%tier)
 game.economy.accept_contract("D1-A");game.economy.mark_story_seen("D1-A","D1-A/accept")
 game.navigate("hub")
 if game.world._parcel_tween!=null:game.world._parcel_tween.pause()
 for i in range(600):
  if game.world._parcel_tween!=null:game.world._parcel_tween.custom_step(1.0/120.0)
  game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0)
  if i in [160,320,485,512]:await capture("tier2-loading-%03d"%i)
 game.world.fastforward_loading();game.navigate("workshop");game.start_flight(true)
 if game.page!="flight":
  push_error("Large fixture could not start a trial");await game._quit_cleanly(1);return
 for progress in [0.0,.35,.65,1.0]:
  game.launch_transfer_remaining=game.world.launch_transfer_duration()*(1.0-progress);game._process(0.0)
  await capture("tier2-transfer-%03d"%int(progress*100))
 game.launch_transfer_remaining=0;game.launch_age=.5;game._process(0.0)
 await capture("tier2-grounded-charge")
 print("WORKSHOP_SCENE_PROOF_COMPLETE ",tag)
 await game._quit_cleanly()
