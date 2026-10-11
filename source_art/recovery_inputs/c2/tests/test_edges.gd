extends SceneTree
const Pose=preload("res://scripts/clerk_rigid_pose_2d.gd")
const Root=preload("res://scripts/shop_locomotion_2d.gd")
var failures:Array[String]=[]
var checks:int=0
func check(ok:bool,label:String) -> void:
 checks+=1
 if not ok:failures.append(label)
func _initialize() -> void:
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://contract/candidate-rig-registration-fg01.json"))
 var root=Root.new();root.configure(10000);root.adopt_position(Vector2(2000,496));root.set_input(0,true)
 var pose=Pose.new();check(pose.configure(data,210),"configure")
 pose.reset(root.position,true,0,root.distance)
 data.legs.near.thigh_length=1.0
 check(absf(float(pose.config.legs.near.thigh_length)-44.38167261381662)<1e-9,"configuration owns its copy")
 for tick in range(120):
  root.set_input(1,true);root.step(1.0/120.0)
  if tick%2==0:pose.update(root.state,root.distance,root.position,root.facing_right,float(tick)/120,root.stop_age)
 # Adopt the exact current owner sample before pausing both presentation and root.
 pose.update(root.state,root.distance,root.position,root.facing_right,1.0,root.stop_age)
 var before:Dictionary=pose.snapshot()
 for clock in [5.0,9.0,15.0]:
  pose.freeze(clock,root.distance)
  check(pose.snapshot()==before,"hidden freeze visually exact at "+str(clock))
 check(pose.update(root.state,root.distance,root.position,root.facing_right,19.0,root.stop_age),"resume accepted")
 check(pose.snapshot()==before,"stationary resume visually exact including blink and upper body")
 var counter_before:int=pose.distance_rebases
 pose.update(root.state,0.0,root.position,root.facing_right,19.0,root.stop_age)
 var rebased:Dictionary=pose.snapshot();rebased.distance_rebases=before.distance_rebases
 check(pose.distance_rebases==counter_before+1,"distance reset recorded")
 check(rebased==before,"distance reset leaves visible pose exact")
 var snapshot:Dictionary=pose.snapshot();snapshot.feet.near.position=Vector2(999,999);snapshot.upper_body.shoulder_world.near=Vector2(999,999)
 check(pose.feet.near.position!=Vector2(999,999) and pose.upper_body.shoulder_world.near!=Vector2(999,999),"snapshot does not alias mutable state")
 var phase:float=pose.step_fraction;var distance:float=pose.step_distance
 for tick in range(120):pose.update("move",0.0,root.position,root.facing_right,19.0+float(tick)/120,0.0)
 check(pose.step_fraction==phase and pose.step_distance==distance,"zero displacement cannot march in place")
 var adapter:String=FileAccess.get_file_as_string("res://reference/scripts/clerk_rigid_motion_2d.gd")
 check(adapter.contains("func apply_run(distance_px:float, facing_right:bool = true) -> bool:\n return apply_walk(distance_px, facing_right)"),"provided legacy apply_run delegates to apply_walk: static source check only")
 check(root.MOVE_SPEED==155.0 and root.ACCELERATION==700.0 and root.BRAKING==750.0 and root.REVERSAL_BRAKING==1000.0 and root.STEP_SECONDS==1.0/120.0,"frozen root constants")
 print(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"scope":"pure API edge checks; adapter legacy alias is static only"}))
 quit(0 if failures.is_empty() else 1)
