extends Node2D
## Presentation-only feedback for COMMITTED model edits. Never owns inventory,
## orders, part data, physics, input, deferred gameplay work, or a Tween.
## Bind the existing Part{id} sprites AFTER configuring the world. Invoke the
## commit hook AFTER show_design(), so the actual newly committed sprite aligns.
const ART_ROOT:String="res://assets/2d_v5/robot/"
const POSES:Array[String]=["idle","carry-parcel","offer-parcel","carry-part","offer-part","alert","carry-empty","offer-empty"]
const MAX_ACTIONS:int=4
const MAX_SPARKS:int=4
const ALIGN_DURATION:float=.18
const LATCH_DURATION:float=.16
const FLOOR_Y:float=486.0
const DOCK_X:float=516.0
const COUNTER_X:float=444.0
const MIN_X:float=436.0
const MAX_X:float=818.0
const ROBOT_SPEED:float=220.0
const ROBOT_ANCHOR:Vector2=Vector2(80,136)
const MOTION_RAMP_SECONDS:float=.14
const TRANSPORT_HAND:Vector2=Vector2(35,-52)
const TRANSPORT_SHOULDER:Vector2=Vector2(14,-35)
const MAX_TRAVEL_SECONDS:float=2.4

var reduced_motion:bool=false:
 set(value):
  if reduced_motion==value:return
  reduced_motion=value
  if is_instance_valid(robot_root):
   _clear_feedback();_stop_robot(false)
var assembly_origin:Vector2=Vector2(728,288)
var cell_size:float=72.0
var robot_root:Node2D
var robot:Sprite2D
var lift_arm:Node2D
var _lift_shaft:Sprite2D
var _lift_joint:Sprite2D
var _lift_claw:Sprite2D
var _lift_reach:float=0.0
var sparks_root:Node2D
var robot_state:String="idle"
var robot_pose:String="idle"
var order_id:String=""
var order_stage:String=""
var _part_root:WeakRef
var _textures:Dictionary={}
var _actions:Dictionary={}
var _sparks:Array[Sprite2D]=[]
var _spark_ages:Array[float]=[]
var _spark_part_ids:Array[int]=[]
var _robot_x:float=DOCK_X
var _robot_target_x:float=DOCK_X
var _robot_hold:float=0.0
var _robot_offer_right:bool=true
var _scene_visible:bool=true
var _serial:int=0
var _spark_serial:int=0
var _transport_owner:String=""
var _focus_active:bool=true
var _travel_min_x:float=MIN_X
var _travel_max_x:float=MAX_X
var _floor_y:float=FLOOR_Y
var _travel_speed:float=ROBOT_SPEED
var _max_travel_seconds:float=MAX_TRAVEL_SECONDS
var _travel_from_x:float=DOCK_X
var _travel_age:float=0.0
var _travel_duration:float=0.0
var _robot_velocity:float=0.0
var _transport_facing_right:bool=true
var _transport_turn:float=-1.0
var _return_turn_scale:float=1.0

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 z_index=4
 # Runtime poses share one manually body/foot-registered canvas. A single rooted
 # flip preserves the foot position, held objects, and gesture direction.
 for pose in POSES:
  var path:String=ART_ROOT+pose+".png"
  if ResourceLoader.exists(path):_textures[pose]=load(path)
 # Optional generated frontal inbetween shares the same unscaled foot anchor.
 if ResourceLoader.exists(ART_ROOT+"turn-front.png"):_textures["turn-front"]=load(ART_ROOT+"turn-front.png")
 robot_root=Node2D.new();robot_root.name="RegisteredCourierRobot";add_child(robot_root)
 robot=Sprite2D.new();robot.name="GeneratedRobotPose";robot.centered=false;robot.offset=-ROBOT_ANCHOR
 robot.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;robot_root.add_child(robot)
 lift_arm=Node2D.new();lift_arm.name="GeneratedTelescopingArm"
 # Counter z=8; parcel z=13. The rigid claw and connected shaft stay visibly
 # between them, independent of the behind-counter robot body's z=4.
 lift_arm.z_as_relative=false;lift_arm.z_index=9
 robot_root.add_child(lift_arm);lift_arm.hide()
 _lift_shaft=_arm_piece("lift-shaft",Vector2(0,-9));_lift_shaft.name="GeneratedTelescopingShaft"
 _lift_joint=_arm_piece("lift-joint",Vector2(-18,-19));_lift_joint.name="GeneratedShoulderJoint"
 _lift_claw=_arm_piece("lift-claw",Vector2(-45.74195,-26));_lift_claw.name="GeneratedRigidEmptyClaw"
 _lift_joint.scale=Vector2.ONE*.65;_lift_claw.scale=Vector2.ONE*.65
 sparks_root=Node2D.new();sparks_root.name="BoundedAssemblyLatchSparks";sparks_root.z_index=2;add_child(sparks_root)
 var spark_texture:Texture2D=load("res://assets/2d_v5/flight/impact.png") as Texture2D
 for i in range(MAX_SPARKS):
  var spark:Sprite2D=Sprite2D.new();spark.name="LatchSpark"+str(i);spark.texture=spark_texture
  spark.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  if spark_texture!=null:spark.scale=Vector2(22,20)/Vector2(spark_texture.get_size())
  sparks_root.add_child(spark);spark.hide();_sparks.append(spark);_spark_ages.append(-1.0);_spark_part_ids.append(-1)
 _set_pose("idle");_sync_robot_position()
 visibility_changed.connect(_on_visibility_changed)

func configure(origin:Vector2,new_cell_size:float) -> void:
 if not origin.is_finite() or not is_finite(new_cell_size) or new_cell_size<=0:return
 _clear_feedback()
 assembly_origin=origin;cell_size=new_cell_size

func configure_transport_bounds(min_x:float,max_x:float,floor_y:float=FLOOR_Y,speed:float=ROBOT_SPEED,max_leg_seconds:float=MAX_TRAVEL_SECONDS) -> void:
 if not is_finite(min_x) or not is_finite(max_x) or min_x>max_x:return
 if not is_finite(floor_y) or not is_finite(speed) or speed<=0:return
 if not is_finite(max_leg_seconds) or max_leg_seconds<.25:return
 _travel_min_x=min_x;_travel_max_x=max_x;_floor_y=floor_y
 _travel_speed=speed;_max_travel_seconds=max_leg_seconds
 _robot_x=clampf(_robot_x,min_x,max_x);_robot_target_x=clampf(_robot_target_x,min_x,max_x)
 _sync_robot_position()

func transport_dock_x(cargo_destination:Vector2) -> float:
 return clampf(cargo_destination.x-88.0,_travel_min_x,_travel_max_x)

func transport_travel_duration(from_x:float,to_x:float) -> float:
 # A finite presentation budget also covers a long expanded workshop. Short
 # routes retain their existing pace; long ones cruise faster without waiting.
 return clampf(absf(to_x-from_x)/_travel_speed+MOTION_RAMP_SECONDS,.25,_max_travel_seconds)

func sample_transport_x(from_x:float,to_x:float,age:float,duration:float) -> float:
 if duration<=0:return to_x
 return lerpf(from_x,to_x,_motion_progress(age,duration))

func sample_transport_velocity(from_x:float,to_x:float,age:float,duration:float) -> float:
 if duration<=0 or age<=0 or age>=duration:return 0.0
 var ramp:float=minf(MOTION_RAMP_SECONDS,duration*.35)
 var gain:float=1.0
 if age<ramp:gain=smoothstep(0.0,1.0,age/ramp)
 elif age>duration-ramp:gain=smoothstep(0.0,1.0,(duration-age)/ramp)
 return (to_x-from_x)*gain/(duration-ramp)

func _motion_progress(age:float,duration:float) -> float:
 var t:float=clampf(age,0.0,duration)
 var ramp:float=minf(MOTION_RAMP_SECONDS,duration*.35)
 if t>=duration:return 1.0
 if t>duration-ramp:return 1.0-_motion_progress(duration-t,duration)
 if t>=ramp:return (t-ramp*.5)/(duration-ramp)
 var u:float=t/ramp
 # Integral of smoothstep velocity: zero speed AND acceleration at each stop.
 return ramp*(u*u*u-.5*u*u*u*u)/(duration-ramp)

func bind_part_root(module_root:Node2D) -> void:
 _clear_feedback()
 _part_root=weakref(module_root) if is_instance_valid(module_root) else null

func on_committed_edit(kind:String,part:Dictionary) -> void:
 if not _scene_visible or not is_visible_in_tree():return
 if not part.has("id") or not part.has("x") or not part.has("y"):return
 var id:int=int(part.id)
 var coordinate:Vector2=Vector2(float(part.x),float(part.y))
 var committed_rotation:float=float(part.get("rot",0))*PI*.5
 if not coordinate.is_finite() or not is_finite(committed_rotation):return
 var normalized:String=kind.to_lower()
 if normalized=="add":normalized="place"
 if normalized in ["parameter","configure","input","target"]:normalized="tune"
 if not normalized in ["place","move","rotate","remove","tune"]:return
 # The latest action for a part replaces its old visual state immediately.
 _cancel_action(id)
 if reduced_motion:
  if not _transport_owner.is_empty():return
  _robot_target_x=_robot_x;robot_state="quiet_ack";_robot_hold=.18
  _face_offer(true);_set_pose("carry-part" if normalized=="remove" else "offer-part")
  return
 if normalized!="remove":
  var sprite:Sprite2D=_find_part(id)
  if sprite==null:return
  while _actions.size()>=MAX_ACTIONS:_evict_oldest_action()
  _serial+=1
  # Only copy scalar snapshot fields. No reference to the model dictionary is kept.
  _actions[id]={"id":id,"kind":normalized,"age":0.0,"serial":_serial,
   "position":coordinate*cell_size,"rotation":committed_rotation,
   "sprite":weakref(sprite),"scale":sprite.scale,"self_modulate":sprite.self_modulate,"latched":false}
  _apply_action(_actions[id])
 # Cargo owns robot intent until its single parcel has reached the ship.
 # Committed part feedback still runs, but edits cannot steal its gripper.
 if not _transport_owner.is_empty():return
 # A floor-level assistant can acknowledge work without pretending the commit
 # waited for a delivery. Robot intent is one replaceable slot, never a queue.
 _robot_target_x=clampf(assembly_origin.x+coordinate.x*cell_size-70.0,_travel_min_x,_travel_max_x)
 _robot_offer_right=assembly_origin.x+coordinate.x*cell_size>=_robot_target_x
 _start_robot_travel(_robot_target_x,"part_travel")
 _set_pose("carry-part")

func on_order_changed(new_order_id:String,stage:String) -> void:
 var normalized:String=stage.to_lower()
 if normalized in ["in_flight","launch","flight"]:normalized="dispatched"
 if new_order_id==order_id and normalized==order_stage:return
 var changed_order:bool=new_order_id!=order_id
 if changed_order:_clear_feedback();hold_transport_position()
 order_id=new_order_id;order_stage=normalized
 if not _scene_visible or not is_visible_in_tree():return
 if new_order_id.is_empty() or normalized in ["cancelled","declined","settled","failed","empty"]:
  _clear_feedback();hold_transport_position()
  if normalized in ["settled","failed"]:
   robot_state="quiet_ack";_robot_hold=.5;_set_pose("alert")
  return
 if normalized=="dispatched":
  _transport_owner="";_clear_feedback();_stop_robot(false)
 # Accepted/loaded snapshots are bookkeeping only. The world owns the real
 # parcel and explicitly drives pickup/carry/insertion; no fake baked boxes.

func acquire_transport(new_order_id:String) -> bool:
 if new_order_id.is_empty():return false
 if _transport_owner==new_order_id:return true
 _clear_feedback();_stop_robot(false)
 _transport_owner=new_order_id;order_id=new_order_id;order_stage="loading"
 return true

func transport_current_x() -> float:
 return _robot_x

func hold_transport_position(new_order_id:String="") -> void:
 # Cancellation invalidates intent, not the physical position. The world can
 # wait for the clerk to clear the aisle before asking for an empty return.
 if not new_order_id.is_empty() and _transport_owner!=new_order_id:return
 _transport_owner=""
 var facing:float=robot_root.scale.x
 _stop_robot(false)
 robot_root.scale.x=facing

func drive_transport(new_order_id:String,state:String,at_x:float,offer_right:bool,pose:String="carry-empty",velocity:float=0.0) -> void:
 if _transport_owner!=new_order_id or not is_finite(at_x):return
 _robot_x=clampf(at_x,_travel_min_x,_travel_max_x);_robot_target_x=_robot_x
 _robot_velocity=velocity if is_finite(velocity) else 0.0
 robot_state=state;_robot_hold=0.0;_transport_turn=-1.0
 _transport_facing_right=offer_right
 # Empty hands allow travel facing and arm direction to be independent. The
 # old offer pose faced away from its travel direction and popped at each stop.
 robot_root.scale.x=-1.0 if offer_right else 1.0
 _set_pose(pose if pose in ["carry-empty","offer-empty","turn-front"] and _textures.has(pose) else "carry-empty")
 _sync_robot_position()

func drive_transport_turn(new_order_id:String,at_x:float,progress:float) -> void:
 var t:float=clampf(progress,0.0,1.0)
 var pose:String="turn-front" if t>=.30 and t<.70 and _textures.has("turn-front") else "carry-empty"
 drive_transport(new_order_id,"robot_turn",at_x,t>=.5,pose)
 if _transport_owner!=new_order_id:return
 _transport_turn=smoothstep(0.0,1.0,t)
 if pose=="turn-front":robot_root.scale.x=1.0

func transport_hand_point() -> Vector2:
 # Parcel bottom rests on the authored empty hands; no pose alpha blending or
 # independent package flip. The same footprint stays planted during the turn.
 var side:float=1.0 if _transport_facing_right else -1.0
 if _transport_turn>=0:side=lerpf(-1.0,1.0,_transport_turn)
 return robot_root.position+Vector2(TRANSPORT_HAND.x*side,TRANSPORT_HAND.y)

func grip_transport_parcel(new_order_id:String,world_point:Vector2) -> void:
 if _transport_owner!=new_order_id or not world_point.is_finite():return
 var side:float=1.0 if _transport_facing_right else -1.0
 if _transport_turn>=0:side=lerpf(-1.0,1.0,_transport_turn)
 # Counter and parcel remain in world space while the body changes facing.
 # Interpolate the mechanical shoulder, never squash the face/body to turn.
 lift_arm.position=Vector2(TRANSPORT_SHOULDER.x*side/robot_root.scale.x,TRANSPORT_SHOULDER.y)
 var target:Vector2=robot_root.to_local(to_global(world_point))-lift_arm.position
 _lift_reach=target.length();lift_arm.rotation=target.angle()
 lift_arm.scale=Vector2.ONE
 # Only the source tube extends. The generated hand and shoulder keep their
 # pixel dimensions at every reach, including a high expanded-workshop bay.
 _lift_shaft.position=Vector2(5,0)
 _lift_shaft.scale=Vector2(maxf(1.0,_lift_reach-24.0)/28.0,.65)
 _lift_claw.position=Vector2(_lift_reach,0)
 lift_arm.visible=_lift_reach>4.0

func transport_grip_point() -> Vector2:
 return to_local(lift_arm.to_global(Vector2(_lift_reach,0)))

func _arm_piece(filename:String,anchor:Vector2) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new();node.texture=load(ART_ROOT+filename+".png") as Texture2D
 node.centered=false;node.offset=anchor;node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 lift_arm.add_child(node);return node

func release_transport(new_order_id:String="",at_dock:bool=false) -> void:
 if not new_order_id.is_empty() and _transport_owner!=new_order_id:return
 _transport_owner=""
 if not at_dock and not reduced_motion and _scene_visible and is_visible_in_tree():
  # Completion is already committed; this tiny empty-handed turn does not
  # delay loading, launch or input. Keep the source facing until the inbetween.
  lift_arm.hide();_robot_velocity=0.0;_transport_turn=-1.0
  _return_turn_scale=robot_root.scale.x;robot_state="return_turn";_robot_hold=.16
  _set_pose("carry-empty")
 else:_stop_robot(at_dock)

func release_transport_at_workbench(new_order_id:String,at_x:float) -> void:
 # One deterministic final pose for normal, skipped and restored deliveries.
 # No queued automatic return can take over after the completion signal.
 if new_order_id.is_empty() or not is_finite(at_x):return
 if not _transport_owner.is_empty() and _transport_owner!=new_order_id:return
 _transport_owner="";order_id=new_order_id;order_stage="loaded"
 _robot_x=clampf(at_x,_travel_min_x,_travel_max_x)
 _stop_robot(false)
 robot_root.scale.x=-1.0

func reset(clear_order:bool=true) -> void:
 _transport_owner="";_clear_feedback();_stop_robot(true)
 if clear_order:order_id="";order_stage=""

func set_scene_visible(active:bool) -> void:
 if active==_scene_visible and visible==active:return
 _scene_visible=active
 if not active:reset(false)
 visible=active

func _on_visibility_changed() -> void:
 if not is_visible_in_tree():
  _clear_feedback()
  # Ancestor hide is a pause for an owned delivery, including its planted arm.
  if _transport_owner.is_empty() and not robot_state in ["return_turn","return"]:
   var facing:float=robot_root.scale.x
   _stop_robot(false)
   robot_root.scale.x=facing

func set_focus_active(active:bool) -> void:
 _focus_active=active

func _process(delta:float) -> void:
 if not _focus_active:return
 if not _scene_visible or not is_visible_in_tree():return
 if not is_finite(delta) or delta<=0:return
 _step_feedback(delta)
 _step_robot(delta)

func _step_feedback(delta:float) -> void:
 for i in range(_sparks.size()):
  if _spark_ages[i]<0:continue
  _spark_ages[i]+=delta
  if _spark_ages[i]>=.12 or reduced_motion:
   _spark_ages[i]=-1.0;_spark_part_ids[i]=-1;_sparks[i].hide()
  else:
   _sparks[i].modulate.a=.78*(1.0-_spark_ages[i]/.12)
 for id in _actions.keys():
  var action:Dictionary=_actions[id]
  action.age+=delta
  var sprite:Sprite2D=_find_part(int(id))
  if sprite==null:
   _cancel_action(int(id));continue
  var previous=action.sprite.get_ref()
  if sprite!=previous:
   # show_design can replace visual nodes between commits. Rebind once to the
   # current sprite, and capture its scale rather than keeping freed nodes alive.
   _restore_action(action)
   action.sprite=weakref(sprite);action.scale=sprite.scale;action.self_modulate=sprite.self_modulate
  if float(action.age)>=ALIGN_DURATION+LATCH_DURATION:
   _cancel_action(int(id));continue
  if not action.latched and float(action.age)>=ALIGN_DURATION:
   action.latched=true
   if str(action.kind)!="tune" and not reduced_motion:
    _show_spark(assembly_origin+Vector2(action.position)+Vector2(-cell_size*.36,cell_size*.28),int(id))
  _apply_action(action)

func _apply_action(action:Dictionary) -> void:
 var sprite=action.sprite.get_ref()
 if not is_instance_valid(sprite) or sprite.is_queued_for_deletion():return
 var progress:float=clampf(float(action.age)/ALIGN_DURATION,0.0,1.0)
 var remaining:float=(1.0-progress)*(1.0-progress)
 var offset:Vector2=Vector2(0,-10)*remaining
 var angle:float=0.0
 if str(action.kind)=="move":offset=Vector2(-10,-4)*remaining
 elif str(action.kind)=="rotate":offset=Vector2.ZERO;angle=-.10*remaining
 elif str(action.kind)=="tune":offset=Vector2.ZERO
 var latch:float=0.0
 if float(action.age)>=ALIGN_DURATION:
  latch=sin(clampf((float(action.age)-ALIGN_DURATION)/LATCH_DURATION,0.0,1.0)*PI)
 sprite.position=Vector2(action.position)+offset.snapped(Vector2(2,2))
 sprite.rotation=float(action.rotation)+angle
 sprite.scale=Vector2(action.scale)*(1.0-.018*latch)

func _find_part(id:int) -> Sprite2D:
 if _part_root==null:return null
 var parent=_part_root.get_ref()
 if not is_instance_valid(parent) or parent.is_queued_for_deletion():return null
 var node=parent.get_node_or_null("Part"+str(id))
 if not node is Sprite2D or node.is_queued_for_deletion():return null
 return node as Sprite2D

func _restore_action(action:Dictionary) -> void:
 var sprite=action.sprite.get_ref()
 if not is_instance_valid(sprite) or sprite.is_queued_for_deletion():return
 sprite.position=action.position;sprite.rotation=action.rotation;sprite.scale=action.scale;sprite.self_modulate=action.self_modulate

func _cancel_action(id:int) -> void:
 for i in range(_sparks.size()):
  if _spark_part_ids[i]==id:_sparks[i].hide();_spark_ages[i]=-1.0;_spark_part_ids[i]=-1
 if not _actions.has(id):return
 _restore_action(_actions[id]);_actions.erase(id)

func _evict_oldest_action() -> void:
 var oldest:int=-1;var serial:int=9223372036854775807
 for id in _actions:
  if int(_actions[id].serial)<serial:serial=int(_actions[id].serial);oldest=int(id)
 if oldest!=-1:_cancel_action(oldest)

func _show_spark(at:Vector2,part_id:int) -> void:
 if reduced_motion or _sparks.is_empty():return
 var index:int=_spark_serial%MAX_SPARKS;_spark_serial+=1
 _spark_ages[index]=0.0;_spark_part_ids[index]=part_id
 var spark:Sprite2D=_sparks[index];spark.position=at.snapped(Vector2(2,2));spark.rotation=-PI*.5
 spark.modulate=Color(1,1,1,.78);spark.show()

func _clear_feedback() -> void:
 for id in _actions.keys():_cancel_action(int(id))
 for i in range(_sparks.size()):_sparks[i].hide();_spark_ages[i]=-1.0;_spark_part_ids[i]=-1

func _step_robot(delta:float) -> void:
 if not is_instance_valid(robot_root) or not _transport_owner.is_empty():return
 if reduced_motion:
  if _robot_hold>0:
   _robot_hold=maxf(0,_robot_hold-delta)
   if _robot_hold<=0:_stop_robot(false)
  return
 if robot_state=="return_turn":
  _robot_hold=maxf(0.0,_robot_hold-delta)
  var t:float=1.0-_robot_hold/.16
  var target_scale:float=-1.0 if DOCK_X>_robot_x else 1.0
  if t>=.30 and t<.70 and _textures.has("turn-front"):
   robot_root.scale.x=1.0;_set_pose("turn-front")
  else:
   robot_root.scale.x=_return_turn_scale if t<.5 else target_scale;_set_pose("carry-empty")
  if _robot_hold<=0:_start_robot_travel(DOCK_X,"return")
 elif robot_state in ["part_travel","return"]:
  var direction:float=signf(_robot_target_x-_travel_from_x)
  if direction!=0:robot_root.scale.x=-1.0 if direction>0 else 1.0
  _travel_age+=delta
  _robot_x=sample_transport_x(_travel_from_x,_robot_target_x,_travel_age,_travel_duration)
  _robot_velocity=sample_transport_velocity(_travel_from_x,_robot_target_x,_travel_age,_travel_duration)
  _sync_robot_position()
  if _travel_age>=_travel_duration:
   match robot_state:
    "part_travel":
     robot_state="part_offer";_robot_hold=.5;_face_offer(_robot_offer_right);_set_pose("offer-part")
    "return":_stop_robot(false)
 elif _robot_hold>0:
  _robot_hold=maxf(0,_robot_hold-delta)
  if _robot_hold<=0:
   if robot_state=="quiet_ack":_stop_robot(false)
   else:
    _start_robot_travel(DOCK_X,"return");_set_pose("idle")

func _start_robot_travel(target_x:float,state:String) -> void:
 _robot_target_x=clampf(target_x,_travel_min_x,_travel_max_x)
 _travel_from_x=_robot_x;_travel_age=0.0
 _travel_duration=transport_travel_duration(_travel_from_x,_robot_target_x)
 _robot_velocity=0.0;robot_state=state;_robot_hold=0.0

func _face_offer(right:bool) -> void:
 # Authored bodies face left, but the authored right arm offers to the right.
 # Travel flips the entire registered actor; a work gesture faces its actual target.
 if is_instance_valid(robot_root):robot_root.scale.x=1.0 if right else -1.0

func _sync_robot_position() -> void:
 if is_instance_valid(robot_root):robot_root.position=Vector2(_robot_x,_floor_y)

func _stop_robot(at_dock:bool) -> void:
 if is_instance_valid(lift_arm):lift_arm.hide()
 robot_state="idle";_robot_hold=0;_robot_velocity=0;_transport_turn=-1.0
 if at_dock:_robot_x=clampf(DOCK_X,_travel_min_x,_travel_max_x)
 _robot_target_x=_robot_x
 if is_instance_valid(robot_root):robot_root.scale=Vector2.ONE;_sync_robot_position();_set_pose("idle")

func _set_pose(pose:String) -> void:
 robot_pose=pose
 if is_instance_valid(robot) and _textures.has(pose):
  # Keep the original generated idle file for provenance; neutral empty hands
  # avoid a chest/parcel silhouette jump on acquisition and release.
  robot.texture=_textures.get("carry-empty",_textures[pose]) if pose=="idle" else _textures[pose]

func debug_snapshot() -> Dictionary:
 var sparks:int=0
 for sprite in _sparks:
  if sprite.visible:sparks+=1
 return {"actions":_actions.size(),"spark_nodes":_sparks.size(),"visible_sparks":sparks,
  "robot_state":robot_state,"robot_pose":robot_pose,"robot_x":_robot_x,"robot_z":z_index,
  "robot_target_x":_robot_target_x,"robot_velocity":_robot_velocity,"travel_bounds":Vector2(_travel_min_x,_travel_max_x),"floor_y":_floor_y,"order_id":order_id,"order_stage":order_stage,
  "lift_visible":is_instance_valid(lift_arm) and lift_arm.visible,"cached_robot_textures":_textures.size(),"serial":_serial,"transport_owner":_transport_owner}

func _exit_tree() -> void:
 _clear_feedback()
