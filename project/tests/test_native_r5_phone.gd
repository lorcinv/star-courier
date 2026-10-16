extends SceneTree
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
const Adapter=preload("res://scripts/clerk_phone_r5_r3_2d.gd")
var diagnostic:Dictionary={}
var passed:int=0
var failed:int=0
var failures:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;failures.append(label);push_error(label)
func step(w,axis:float,seconds:float) -> void:
 var remaining:float=seconds
 while remaining>.000001:
  var dt:float=minf(1.0/60.0,remaining);remaining-=dt
  w.set_shop_input(axis,true);w._process(dt);w.assembly_feedback._process(dt)
func run() -> void:
 var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 var w=World.new();viewport.add_child(w);w.set_process(false);w.assembly_feedback.set_process(false)
 w._clerk_motion._rig.free();w._clerk_motion=Adapter.new(w.clerk,"clerk",210.0)
 w.show_design(Profile.starter_design());w.focus("hub",true);step(w,0,.03);step(w,1,.4)
 var motion=w._clerk_motion
 check(motion._observed_samples>0,"actual World consumed root slices")
 var root_owner:int=w._shop_motion.get_instance_id();var parcel:int=w.parcel.get_instance_id()
 diagnostic={"before_phone":motion._model.snapshot().duplicate(true)}
 check(w.acquire_review_phone(77),"real World phone ownership acquired")
 var at:Vector2=w.clerk.position;var frozen:Dictionary=motion._model.snapshot();var epoch:int=w._shop_motion.presentation_segments().reset_epoch
 check(w._shop_motion.presentation_segments().segments.is_empty(),"phone clears root history")
 for i in 18:w._process(.03)
 check(w.clerk.position==at,"phone-owned finite settle preserves exact root")
 check(motion._model.feet.far.planted and motion._model.feet.near.planted and motion._model.settled,"phone-owned settle reaches real double support")
 check(motion._phone_completed_seconds>=0.0 and motion._phone_completed_seconds<=.5,"phone-owned settle completes within500ms")
 check(motion._tablet_target==1.0,"phone raises tablet only after finite settle")
 diagnostic["after_phone_dwell"]=motion._model.snapshot().duplicate(true)
 diagnostic["completed_seconds"]=motion._phone_completed_seconds
 diagnostic["airborne_after_dwell"]=not motion._model.feet.far.planted or not motion._model.feet.near.planted
 w.release_review_phone(77);step(w,1,.15)
 check(w.clerk.position==at,"phone-held key cannot resume movement")
 step(w,0,.03);step(w,-1,.15)
 check(w.clerk.position.x<at.x and motion._rig_active,"fresh input resumes actual root and rig")
 check(motion._observed_owner==root_owner and motion._observed_reset_epoch>epoch,"root owner identity and new reset epoch consumed")
 # Return through actual navigation before testing counter dialogue ownership.
 w.request_shop_navigation("focus_counter")
 for i in 600:
  step(w,0,1.0/60.0)
  if w.is_at_shop_counter():break
 check(w.is_at_shop_counter(),"actual root returns to counter")
 w.set_dialogue_active(true);w.set_shop_input(0,false)
 check(not motion._rig_active,"counter dialogue owns original full-body raster")
 at=w.clerk.position;frozen=motion._model.snapshot()
 for i in 6:w._process(.03)
 check(w.clerk.position==at and motion._model.snapshot()==frozen,"counter dialogue does not replay a consumed walk")
 w.set_dialogue_active(false);step(w,0,.03);step(w,1,.15)
 check(w.clerk.position.x>at.x and motion._rig_active,"counter exit resumes fresh observed walk")
 # Hidden/focus cutscene ownership must clear histories and preserve the pose.
 w.set_focus_active(false);frozen=motion._model.snapshot();at=w.clerk.position;w._process(.5)
 check(w._shop_motion.presentation_segments().segments.is_empty() and motion._model.snapshot()==frozen and w.clerk.position==at,"focus cutscene clears history and freezes exact pose")
 w.set_focus_active(true);step(w,1,.1);check(w.clerk.position==at,"cutscene-held key remains neutral-gated")
 step(w,0,.03);step(w,-1,.12);check(w.clerk.position.x<at.x,"cutscene fresh input resumes")
 check(w.parcel.get_instance_id()==parcel,"ownership changes preserve the same single parcel instance")
 check(motion._observed_unsupported==0 and w._clerk_observation_rejections.is_empty(),"ownership paths need no unobserved movement")
 var report={"status":"PASS" if failed==0 else "FAIL","passed":passed,"failed":failed,"case_count":1,"cases":[{"case":"actual_Main_midstride_phone_ownership","failed":failed}],"failures":failures,"phone_diagnostic":j(diagnostic),"scope":"actual World root/phone/dialogue/focus ownership, no GUI or hardware-input claim"}
 var f=FileAccess.open(ProjectSettings.globalize_path("res://../qa/native-r5-phone-metrics.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n");f.close()
 w.queue_free();viewport.queue_free();await process_frame
 print("OBSERVED_OWNERSHIP ",report.status," passed=",passed," failed=",failed);quit(1 if failed else 0)

func j(value:Variant) -> Variant:
 if value is Vector2:return [value.x,value.y]
 if value is Dictionary:
  var out:Dictionary={}
  for key in value:out[str(key)]=j(value[key])
  return out
 if value is Array:
  var out:Array=[]
  for item in value:out.append(j(item))
  return out
 return value
