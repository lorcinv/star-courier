extends SceneTree
## Actual Godot renderer at real process speed; programmatic route inputs.
## This is not OS-native keyboard/controller evidence or an engine FPS claim.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
const OUT:String="res://docs/qa/v5/shop-locomotion-route"
var world
var elapsed:float=0.0
var live:bool=false
var requested_return:bool=false
var observations:Array=[]
var sample_accumulator:float=0.0
var seen:Dictionary={}
var poses:Dictionary={}
var mismatches:int=0
func _initialize() -> void:run.call_deferred()
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 root.size=Vector2i(1280,720)
 world=World.new();root.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 world.show_design(Profile.starter_design());world.focus("hub",true);world.set_shop_input(0.0,true)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));live=true
func _process(delta:float) -> bool:
 if not live:return false
 elapsed+=delta
 var axis:float=0.0
 if elapsed<.4:axis=1.0
 elif elapsed>=.8 and elapsed<2.5:axis=1.0
 elif elapsed>=3.0 and elapsed<3.8:axis=-1.0
 elif elapsed>=3.8 and elapsed<4.55:axis=1.0
 world.set_shop_input(axis,true)
 if elapsed>=5.0 and not requested_return:
  requested_return=true;world.request_shop_navigation("focus_counter")
 world._process(delta);world.assembly_feedback._process(delta)
 sample_accumulator+=delta
 if sample_accumulator>=1.0/30.0:
  sample_accumulator=0.0
  var snap:Dictionary=world.shop_locomotion_snapshot()
  seen[str(snap.state)]=true;poses[str(snap.motion.pose)]=true
  if str(snap.state)=="run" and str(snap.motion.pose)!="run":mismatches+=1
  observations.append({"elapsed":elapsed,"axis":axis,"snapshot":snap})
 if elapsed>=10.0:
  var f=FileAccess.open(OUT+"/route-telemetry.json",FileAccess.WRITE)
  f.store_string(JSON.stringify({"renderer_fixture":true,"native_gameplay_input":false,"real_process_clock":true,"fixed_fps":false,"speedup":false,"elapsed":elapsed,"states":seen,"poses":poses,"run_mismatches":mismatches,"at_counter":world.is_at_shop_counter(),"observations":observations},"  "));f.close()
  live=false;quit(0 if world.is_at_shop_counter() and seen.has("run") and seen.has("walk") and poses.has("run") and mismatches==0 else 1)
 return false
