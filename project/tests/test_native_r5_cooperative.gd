extends SceneTree
const World=preload("res://scripts/world_view_2d.gd")
const OriginalWorld=preload("res://tests/fixtures/world_original_2d.gd")
const Assembly=preload("res://scripts/assembly_2d.gd")
const Adapter=preload("res://scripts/clerk_tablet_r5_r3_2d.gd")
class NoRenderAdapter extends RefCounted:
 func apply_walk(_distance:float,_right:bool) -> bool:return true
var passed:int=0
var failed:int=0
var failures:Array=[]
var cases:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String,context:Dictionary={}) -> void:
 if ok:passed+=1
 else:
  failed+=1
  if failures.size()<48:failures.append({"check":label,"context":context})
func run() -> void:
 for height in [120.0,210.0,240.0]:
  for right in [true,false]:
   run_case(height,right)
   run_carryover(height,right)
 check(cases.size()==12,"exact12planned cooperative cases",{"actual":cases.size()})
 var report:Dictionary={"status":"PASS" if failed==0 else "FAIL","passed":passed,"failed":failed,"cases":cases,"first_failures":failures,"scope":"actual Main World cooperative call path versus frozen original World; analytic subpath observations and exact root endpoints/distance; no GUI approval"}
 var f=FileAccess.open(ProjectSettings.globalize_path("res://../qa/native-r5-cooperative-metrics.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n");f.close()
 print("OBSERVED_COOPERATIVE ",report.status," passed=",passed," failed=",failed);quit(1 if failed else 0)
func run_case(height:float,right:bool) -> void:
 var id:String="h%d/%s"%[int(height),"R" if right else "L"]
 var world=World.new();var original=OriginalWorld.new()
 var sprite:=Sprite2D.new();root.add_child(sprite);sprite.position=Vector2(276 if right else 650,486)
 var original_sprite:=Sprite2D.new();root.add_child(original_sprite);original_sprite.position=sprite.position
 world.clerk=sprite;original.clerk=original_sprite
 world.assembly_feedback=Assembly.new();original.assembly_feedback=Assembly.new()
 world._clerk_motion=Adapter.new(sprite,"clerk",height);original._clerk_motion=NoRenderAdapter.new()
 world._clerk_motion.set_visual_context(0,true,false);world._clerk_motion.apply_player_pose("idle",0,right,true,0)
 world._set_clerk_leg(650 if right else 276);original._set_clerk_leg(650 if right else 276)
 var hash_before=HashingContext.new();hash_before.start(HashingContext.HASH_SHA256)
 var hash_after=HashingContext.new();hash_after.start(HashingContext.HASH_SHA256)
 var intervals:Array[float]=[1.0/144.0,1.0/47.0,1.0/90.0,1.0/30.0,1.0/75.0,0.055,0.095,0.125]
 var time:float=0;var tick:int=0;var max_count:int=0;var before_failed:int=failed
 while time<world._clerk_leg_duration:
  var next:float=minf(time+intervals[tick%intervals.size()],world._clerk_leg_duration)
  world.visual_time=next;world._clerk_motion.set_visual_context(next,true,false)
  var observations:Array=world._clerk_leg_observations(time,next,world._clerk_leg_duration)
  max_count=maxi(max_count,observations.size());check(not observations.is_empty() and observations.size()<=32,"bounded analytic observations",{"case":id,"tick":tick})
  for observation in observations:
   check(observation.before.position.y==486 and observation.after.position.y==486,"observed path stays on actual horizontal floor",{"case":id,"tick":tick})
   check(observation.dt>0 and observation.dt<=1.0/120.0+0.000001,"bounded cooperative sample time",{"case":id,"tick":tick})
  var target:float=world.assembly_feedback.sample_transport_x(world._clerk_leg_from_x,world._clerk_leg_to_x,next,world._clerk_leg_duration)
  original._set_clerk_walk_x(target);world._set_clerk_walk_x(target,observations)
  check(world.clerk.position==original.clerk.position and world._clerk_walk_distance==original._clerk_walk_distance,"original World root endpoint and distance exact",{"case":id,"tick":tick})
  hash_before.update(JSON.stringify([original.clerk.position.x,original.clerk.position.y,original._clerk_walk_distance]).to_utf8_buffer());hash_after.update(JSON.stringify([world.clerk.position.x,world.clerk.position.y,world._clerk_walk_distance]).to_utf8_buffer())
  var pose:Dictionary=world._clerk_motion._model.snapshot()
  check(pose.max_reach_error<=.001 and pose.reach_feasible,"cooperative fixed chains reachable",{"case":id,"tick":tick})
  check(world._motion_failures.is_empty(),"World accepted observed adapter",{"case":id,"tick":tick})
  world._clerk_motion.advance_visual(next,true,false)
  check(world._clerk_motion._model.snapshot()==pose,"cooperative end-frame advance does not replay gait",{"case":id,"tick":tick})
  time=next;tick+=1
 check(world._clerk_motion._observed_unsupported==0,"no unobserved cooperative path",{"case":id})
 var before:Vector2=sprite.position;sprite.position.y+=10
 check(world._clerk_leg_observations(0,.05,1.0).is_empty(),"unknown corner path rejected",{"case":id});sprite.position=before
 cases.append({"case":id,"failed":failed-before_failed,"calls":tick,"max_history_count":max_count,"baseline_root_sha256":hash_before.finish().hex_encode(),"observed_root_sha256":hash_after.finish().hex_encode(),"unsupported_paths":world._clerk_motion._observed_unsupported})
 world.assembly_feedback.free();original.assembly_feedback.free();sprite.free();original_sprite.free();world.free();original.free()

func run_carryover(height:float,right:bool) -> void:
 var id:String="carryover/h%d/%s"%[int(height),"R" if right else "L"]
 var world=World.new();var original=OriginalWorld.new()
 var sprite:=Sprite2D.new();root.add_child(sprite);sprite.position=Vector2(350 if right else 650,486)
 var original_sprite:=Sprite2D.new();root.add_child(original_sprite);original_sprite.position=sprite.position
 world.clerk=sprite;original.clerk=original_sprite;world.assembly_feedback=Assembly.new();original.assembly_feedback=Assembly.new()
 original._clerk_motion=NoRenderAdapter.new()
 for w in [world,original]:
  w._clerk_return_requested=true;w._clerk_state="return_aisle";w._set_clerk_leg(452)
  w._clerk_return_age=w._clerk_leg_duration-.035
  w.clerk.position.x=w.assembly_feedback.sample_transport_x(w._clerk_leg_from_x,w._clerk_leg_to_x,w._clerk_return_age,w._clerk_leg_duration)
 world._clerk_motion=Adapter.new(sprite,"clerk",height);world._clerk_motion.set_visual_context(0,true,false);world._clerk_motion.apply_player_pose("idle",0,right,true,0)
 world.visual_time=.1;world._clerk_motion.set_visual_context(.1,true,false)
 original._step_clerk_return(.1);world._step_clerk_return(.1)
 check(world.clerk.position==original.clerk.position and world._clerk_walk_distance==original._clerk_walk_distance,"carryover original root endpoint/distance exact",{"case":id})
 check(world._clerk_state==original._clerk_state and world._clerk_return_age==original._clerk_return_age,"carryover phase/age exact",{"case":id})
 check(world._clerk_motion._observed_batches==2,"both actually consumed cooperative legs observed once",{"case":id})
 check(absf(world._clerk_motion._observed_clock-.1)<=.000001,"carryover consumes exactly100ms, not two full frames",{"case":id})
 check(world._clerk_motion._observed_unsupported==0 and world._motion_failures.is_empty(),"carryover has no unsupported path",{"case":id})
 var state:Dictionary=world._clerk_motion._model.snapshot();world._clerk_motion.advance_visual(.1,true,false)
 check(world._clerk_motion._model.snapshot()==state,"carryover no end-frame replay",{"case":id})
 check(world._clerk_leg_observations(0,.5,1).is_empty() and world._clerk_observation_rejections[-1].reason=="overlong_interval","overlong interval explicitly diagnosed",{"case":id})
 cases.append({"case":id,"scope":"actual phase-boundary carryover"})
 world.assembly_feedback.free();original.assembly_feedback.free();sprite.free();original_sprite.free();world.free();original.free()
