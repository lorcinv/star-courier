extends SceneTree
## Real registered resources and original motion collaborators with test-only
## failing subclasses. No save/simulation changes, no native-rendering claim.
const Coupled=preload("res://tests/dev03_checkpoint/fault_coupled_bootstrap.gd")
const Standalone=preload("res://tests/dev03_checkpoint/fault_standalone_bootstrap.gd")
const Fault=preload("res://tests/dev03_checkpoint/fault_control.gd")
const STEP:float=1.0/120.0
var passed:int=0
var failures:Array[String]=[]
var results:Array=[]
var actor:Sprite2D
var motion
var owner:int=17
var candidate:bool=false
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> bool:
 if ok:passed+=1
 else:failures.append(message);push_error(message)
 return ok
func script_state(object:Object) -> Dictionary:
 var result:Dictionary={}
 for property in object.get_property_list():
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
   var value:Variant=object.get(property.name)
   result[property.name]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result
func states(coupled:bool) -> Dictionary:
 var result:Dictionary={"owner":script_state(motion),"body":script_state(motion._model),"presentation":script_state(motion._accepted_pose),"helper":script_state(motion._pose_helper)}
 if coupled:result.arms=script_state(motion._coupled_arms);result.walk=script_state(motion._coupled_arms._walk)
 return result
func draw_state() -> Array:
 var result:Array=[[actor.position,actor.transform,actor.visible,actor.texture]]
 for node in motion._rig.get_children():
  result.append([node.name,node.transform,node.visible,node.texture if node is Sprite2D else null,node.z_index])
 return result
func differences(before:Dictionary,after:Dictionary) -> Array[String]:
 var changed:Array[String]=[]
 for scope in before:
  for key in before[scope]:
   if not after[scope].has(key) or var_to_bytes(before[scope][key])!=var_to_bytes(after[scope][key]):changed.append(scope+"."+key)
  for key in after[scope]:
   if not before[scope].has(key):changed.append(scope+"."+key+"[added]")
 return changed
func stable(value:Variant) -> Variant:
 if value is float and not is_finite(value):return {"nonfinite_float":str(value)}
 if value is Dictionary:
  var out:Dictionary={}
  for key in value:out[key]=stable(value[key])
  return out
 if value is Array:
  var out:Array=[]
  for child in value:out.append(stable(child))
  return out
 if value is WeakRef:return {"weak_ref":stable(value.get_ref())}
 if value is Resource:return {"resource":value.resource_path,"class":value.get_class()}
 if value is Node:return {"node":str(value.get_path())}
 if value is Object:
  return {"class":value.get_class(),"script":value.get_script().resource_path if value.get_script()!=null else ""}
 return value
func cleanup() -> void:
 Fault.reset()
 if is_instance_valid(actor):actor.free()
 actor=null;motion=null
func setup(coupled:bool,kind:String,moving:bool=true) -> bool:
 cleanup();actor=Sprite2D.new();actor.name="FaultClerk";actor.position=Vector2(320,486);root.add_child(actor)
 var created:Dictionary=Coupled.create(actor,210.0) if coupled else Standalone.create(actor,210.0)
 if not check(bool(created.get("ok",false)),"real constructor "+str(created.get("error",""))):return false
 motion=created.motion
 var row:Dictionary={"position":actor.position,"velocity":0.0,"distance":0.0,"facing_right":true,"state":"idle","stop_age":0.0}
 var initialized:bool=motion.initialize_coupled_root(row,0.0) if coupled else motion.apply_player_pose("idle",0.0,true,true,0.0,0.0)
 if not check(initialized,"real initial owner sample"):return false
 if moving:
  actor.position+=Vector2(1,0)
  var after:Dictionary={"position":actor.position,"velocity":120.0,"distance":1.0,"facing_right":true,"state":"move","stop_age":0.0}
  if not check(motion.apply_observed_root({"owner":23,"reset_epoch":0,"sequence":1,"segments":[{"dt":STEP,"before":row,"after":after}]},STEP,true),"actual observed moving root segment"):return false
 var acquired:bool=motion.begin_review_phone(owner) if kind=="phone" else motion.apply_cooperative_gesture("reach",true,owner)
 if not check(acquired,"real "+kind+" owner acquisition"):return false
 motion._render_rig()
 return true
func call_slice(coupled:bool,kind:String,elapsed:float=STEP,frame_clock:float=STEP*2.0,slice_id:int=0,who:int=17) -> bool:
 if coupled:
  return motion.advance_coupled_owner(kind,who,elapsed,frame_clock,float(motion._coupled_arms.status().accepted_time)+elapsed,0.0,slice_id)
 return motion.advance_review_phone_slice(who,elapsed,frame_clock,slice_id) if kind=="phone" else motion.advance_cooperative_pose_slice(who,elapsed,frame_clock,slice_id)
func failure_case(coupled:bool,kind:String,fault:String) -> void:
 if not setup(coupled,kind):return
 var label:String=("coupled" if coupled else "standalone")+"/"+kind+"/"+fault
 var before:Dictionary=states(coupled);var drawing:Array=draw_state()
 Fault.reset(fault)
 var result:bool=call_slice(coupled,kind)
 var counts:Dictionary={"owner_checkpoints":Fault.checkpoint_calls,"coupled_checkpoints":Fault.coupled_calls,"property_copies":Fault.copy_calls,"hits":Fault.hits}
 var after:Dictionary=states(coupled);var changed:Array[String]=differences(before,after)
 var allowed:Array=["owner._coupled_status"] if coupled else []
 var unexpected:Array[String]=[]
 for field in changed:
  if field not in allowed:unexpected.append(field)
 check(not result,label+" returns false")
 check(Fault.hits>0,label+" injected real collaborator failure executed")
 check(unexpected.is_empty(),label+" complete per-field rollback: "+str(unexpected))
 check(var_to_bytes(draw_state())==var_to_bytes(drawing),label+" preserves/restores all actual draw-node transforms, textures and visibility")
 var expected_checkpoints:int=1 if candidate or not coupled else 2
 check(Fault.checkpoint_calls==expected_checkpoints,label+" retains exactly its responsible owner checkpoint")
 check(not coupled or motion._coupled_owner_input.is_empty(),label+" releases transaction context")
 results.append({"case":label,"return":result,"counts":counts,"changed_fields":changed,"unexpected_fields":unexpected,"after":stable(after),"draw":stable(draw_state())})
 cleanup()
func precondition_case(label:String,kind:String,elapsed:float=STEP,who:int=17,freeze:bool=false) -> void:
 if not setup(true,kind,false):return
 if freeze:motion.set_pose_focus_active(false)
 var before:Dictionary=states(true);var drawing:Array=draw_state();Fault.reset()
 var result:bool=call_slice(true,kind,elapsed,STEP*2.0,0,who)
 var after:Dictionary=states(true);var changed:Array[String]=differences(before,after);var unexpected:Array[String]=[]
 for field in changed:
  if field!="owner._coupled_status":unexpected.append(field)
 check(not result,label+" rejects")
 check(unexpected.is_empty(),label+" all original state fields unchanged")
 check(var_to_bytes(draw_state())==var_to_bytes(drawing),label+" draw state unchanged")
 results.append({"case":label,"return":result,"counts":{"owner_checkpoints":Fault.checkpoint_calls,"coupled_checkpoints":Fault.coupled_calls,"property_copies":Fault.copy_calls,"hits":Fault.hits},"changed_fields":changed,"unexpected_fields":unexpected,"after":stable(after),"draw":stable(draw_state())})
 cleanup()
func success_and_repeat(kind:String) -> void:
 if not setup(true,kind,false):return
 Fault.reset()
 check(call_slice(true,kind),kind+" valid coupled slice accepted")
 check(Fault.checkpoint_calls==(1 if candidate else 2),kind+" success removes only covered inner checkpoint")
 var before:Dictionary=states(true);var drawing:Array=draw_state();Fault.reset()
 var duplicate:bool=call_slice(true,kind)
 check(duplicate,kind+" duplicate token retains original idempotent return")
 check(differences(before,states(true)).is_empty(),kind+" duplicate token consumes no owner/provider/accepted time")
 check(var_to_bytes(draw_state())==var_to_bytes(drawing),kind+" duplicate leaves draw untouched")
 Fault.reset();var reversed:bool=call_slice(true,kind,STEP,0.0)
 var changed:Array[String]=differences(before,states(true));var unexpected:Array[String]=[]
 for field in changed:
  if field!="owner._coupled_status":unexpected.append(field)
 check(not reversed and unexpected.is_empty(),kind+" reversed frame rolls back without consuming a slice")
 results.append({"case":kind+"/duplicate_and_reversed","duplicate":duplicate,"reversed":reversed,"unexpected_fields":unexpected,"after":stable(states(true)),"draw":stable(draw_state())})
 cleanup()
func run() -> void:
 if OS.get_environment("STAR_COURIER_CHECKPOINT_FAULTS")!="1":quit(2);return
 candidate=OS.get_environment("STAR_COURIER_CHECKPOINT_KIND")=="candidate"
 for kind in ["phone","cooperative"]:
  for fault in ["body_before","body_after","provider_after",kind+"_after_slice"]:failure_case(true,kind,fault)
  for fault in ["body_before","body_after"]:failure_case(false,kind,fault)
  precondition_case(kind+"/invalid_elapsed",kind,0.0)
  precondition_case(kind+"/wrong_owner",kind,STEP,999)
  precondition_case(kind+"/focus_gate",kind,STEP,owner,true)
  success_and_repeat(kind)
 check(results.size()==20,"all 20 fault/precondition/repeat cases completed")
 var path:String=OS.get_environment("STAR_COURIER_CHECKPOINT_OUTPUT")
 if not path.is_empty():
  var file=FileAccess.open(path,FileAccess.WRITE)
  if file:file.store_string(JSON.stringify({"candidate":candidate,"passed":passed,"failures":failures,"results":results},"",true,true));file.close()
 print("DEV03_CHECKPOINT_FAULTS ",JSON.stringify({"candidate":candidate,"passed":passed,"failures":failures,"cases":results.size()}))
 cleanup();quit(0 if failures.is_empty() else 1)
