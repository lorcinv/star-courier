extends "res://scripts/clerk_phone_r5_r3_2d.gd"
## Cooperative presentation intent owns only an observed stationary root. The
## World passes actual phase slices; the physical solver and phone owner stay
## unchanged. Natural stop is distinct from explicit skip/restore relocation.
var _cooperative_owner:int=-1
var _cooperative_gesture:String=""
var _cooperative_phase:String="none"
var _cooperative_elapsed:float=0.0
var _cooperative_last_frame:float=-1.0
var _cooperative_completed:float=-1.0
var _cooperative_root:Vector2=Vector2.ZERO
var _cooperative_resets:int=0
var _cooperative_cancel_reason:String=""

func _cancel_cooperative(reason:String,lower:bool=true) -> void:
 if _cooperative_gesture.is_empty():return
 _cooperative_owner=-1;_cooperative_gesture="";_cooperative_phase="none"
 _cooperative_last_frame=-1.0;_cooperative_cancel_reason=reason
 if lower:_tablet_target=0.0

func apply_cooperative_gesture(pose_id:String,right:bool,owner:int) -> bool:
 if pose_id not in ["reach","align","ready"] or not _tablet_ready or not _owner_enabled:return false
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or not sprite.is_visible_in_tree() or _phone_owner!=0:return false
 if not _rig_active:
  if not super.apply_player_pose("idle",_rig_distance,right,true,_owner_clock,0.0):return false
 if _model.origin.distance_to(sprite.position)>.0001:
  _issue("cooperative_gesture_unobserved_root");return false
 if _cooperative_gesture.is_empty() or _cooperative_owner!=owner:
  _model.cancel_presentation_turn("cooperative_gesture_acquired")
  _cooperative_owner=owner;_cooperative_elapsed=0.0;_cooperative_completed=-1.0
  _cooperative_last_frame=_owner_clock;_cooperative_root=sprite.position
  _cooperative_phase="raise" if _model.settled and _model.feet.far.planted and _model.feet.near.planted else "settle"
 _cooperative_gesture=pose_id;_tablet_gesture=pose_id;_facing_right=right
 _player_state="stop";_pose=pose_id
 _tablet_target=1.0 if _cooperative_phase=="raise" else 0.0
 sprite.set_meta("pose",pose_id)
 return true

func advance_cooperative_gesture(owner:int,elapsed:float,frame_clock:float) -> bool:
 if owner!=_cooperative_owner or _cooperative_gesture.is_empty():return false
 if not is_finite(elapsed) or elapsed<0.0 or elapsed>.25:
  _issue("cooperative_stationary_interval_invalid");return false
 if not _owner_enabled or not is_instance_valid(_node()) or not _node().is_visible_in_tree():return false
 if _node().position.distance_to(_cooperative_root)>.0001:
  _issue("cooperative_stationary_root_changed");return false
 # Multiple real phase slices may share a render clock. Each is consumed once
 # by World; advance_visual only observes the final clock and cannot replay it.
 _cooperative_last_frame=frame_clock
 if not _model.update("stop",_rig_distance,_cooperative_root,_facing_right,_observed_clock,_cooperative_elapsed,true,_owner_reduced):return false
 var remaining:float=elapsed
 while remaining>.000001:
  var dt:float=minf(OBSERVED_STEP,remaining);remaining-=dt
  _observed_clock+=dt;_cooperative_elapsed+=dt
  if not _model.update("stop",_rig_distance,_cooperative_root,_facing_right,_observed_clock,_cooperative_elapsed,true,_owner_reduced):return false
  if _cooperative_phase=="settle":
   if _model.settled and not _model.settling and _model.feet.far.planted and _model.feet.near.planted:
    _cooperative_phase="raise";_cooperative_completed=_cooperative_elapsed;_tablet_target=1.0
   elif _cooperative_elapsed>.5:
    _cooperative_phase="failed";_issue("cooperative_settle_exceeded500ms");return false
 _observed_last_render_clock=frame_clock
 _observed_last_input=_observed_input("stop",_rig_distance,_facing_right,_cooperative_root)
 _player_state="stop";_pose=_cooperative_gesture;_node().set_meta("pose",_pose)
 _render_rig()
 return true

func reset_cooperative_completion(right:bool,owner:int) -> void:
 # World calls this only after its existing explicit skip/restore endpoint
 # relocation. No fictitious walk path or landing event crosses that jump.
 _cancel_cooperative("explicit_completion_relocation")
 _model.reset(_node().position,right,_observed_clock,_rig_distance)
 _cooperative_resets+=1
 _observed_last_render_clock=_owner_clock
 _observed_last_input={}
 _facing_right=right

func set_visual_context(clock:float,enabled:bool=true,reduced:bool=false) -> void:
 if not enabled and not _cooperative_gesture.is_empty():
  _tablet_clock=clock;_cooperative_last_frame=clock
 super.set_visual_context(clock,enabled,reduced)

func advance_visual(clock:float,enabled:bool=true,reduced:bool=false) -> bool:
 if _cooperative_gesture.is_empty():return super.advance_visual(clock,enabled,reduced)
 set_visual_context(clock,enabled,reduced)
 if not enabled:return true
 if clock==_cooperative_last_frame:return true
 var elapsed:float=maxf(0.0,clock-_cooperative_last_frame)
 return advance_cooperative_gesture(_cooperative_owner,minf(elapsed,.1),clock)

func _cooperative_frozen_call(clock:float,distance_px:float) -> bool:
 # Match the inherited bookkeeping-only freeze without cancelling a still
 # valid presentation owner or lowering its tablet. No physical time advances.
 var frame_clock:float=_owner_clock if not is_finite(clock) else clock
 _model.freeze(_observed_clock,distance_px)
 _observed_last_render_clock=frame_clock;_cooperative_last_frame=frame_clock
 return true

func apply_player_pose(state:String,distance_px:float,right:bool,enabled:bool=true,clock:float=NAN,stop_age:float=0.0) -> bool:
 if _cooperative_gesture.is_empty():return super.apply_player_pose(state,distance_px,right,enabled,clock,stop_age)
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or not _rig_ready:return false
 if state not in PLAYER_STATES or not is_finite(distance_px) or distance_px<0.0 or not is_finite(stop_age):return false
 if not enabled or not _owner_enabled or not sprite.is_visible_in_tree():return _cooperative_frozen_call(clock,distance_px)
 if _rig_active and _model.initialized and sprite.position.distance_to(_model.origin)>.0001:return false
 var target:float=_tablet_target
 var ok:bool=super.apply_player_pose(state,distance_px,right,enabled,clock,stop_age)
 if ok:_cancel_cooperative("player_pose")
 else:_tablet_target=target
 return ok

func _cooperative_segments_valid(segments:Array) -> bool:
 if segments.size()>32:return false
 for segment in segments:
  if not segment is Dictionary or not segment.has_all(["dt","before","after"]):return false
  var dt:float=float(segment.dt)
  if not is_finite(dt) or dt<=0.0 or dt>OBSERVED_STEP+.000001:return false
  for row in [segment.before,segment.after]:
   if not row is Dictionary or not row.has_all(["position","distance","facing_right","state","stop_age"]):return false
   if not row.position is Vector2 or not row.position.is_finite():return false
   if str(row.state) not in PLAYER_STATES or not is_finite(float(row.distance)) or float(row.distance)<0.0 or not is_finite(float(row.stop_age)):return false
 if not segments.is_empty() and segments[-1].after.position.distance_to(_node().position)>.0001:return false
 return true

func apply_observed_root(batch:Dictionary,frame_clock:float,enabled:bool=true) -> bool:
 if not _cooperative_gesture.is_empty() and enabled and _owner_enabled:
  if not is_instance_valid(_node()) or not batch.get("segments",[]) is Array:return false
  if not _cooperative_segments_valid(batch.get("segments",[])):return false
 return super.apply_observed_root(batch,frame_clock,enabled)

func _apply_observed_segments(segments:Array,frame_clock:float,enabled:bool,source:String) -> bool:
 if _cooperative_gesture.is_empty():return super._apply_observed_segments(segments,frame_clock,enabled,source)
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or not _rig_ready:return false
 if not enabled or not _owner_enabled or not sprite.is_visible_in_tree():return _cooperative_frozen_call(frame_clock,_rig_distance)
 if not _cooperative_segments_valid(segments):return false
 var target:float=_tablet_target
 var ok:bool=super._apply_observed_segments(segments,frame_clock,enabled,source)
 if ok:_cancel_cooperative("observed_root")
 else:_tablet_target=target
 return ok

func apply_dialogue(handoff:bool=false,facing_right:bool=true) -> bool:
 if not _cooperative_gesture.is_empty():
  var sprite:Sprite2D=_node()
  if not is_instance_valid(sprite) or not sprite.is_visible_in_tree() or not _owner_enabled:return false
 var ok:bool=super.apply_dialogue(handoff,facing_right)
 if ok:_cancel_cooperative("dialogue")
 return ok

func begin_review_phone(owner:int) -> bool:
 # These are precisely the unchanged superclass rejection preconditions.
 # Nonzero raw owner replacement remains its existing behavior; World guards
 # matched ownership. A rejected acquisition cannot cancel cooperative intent.
 if owner==0 or not _rig_active or _model==null:return false
 var ok:bool=super.begin_review_phone(owner)
 if ok:_cancel_cooperative("phone_owner",false)
 return ok

func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 result.cooperative_gesture={"owner":_cooperative_owner,"gesture":_cooperative_gesture,"phase":_cooperative_phase,"elapsed":_cooperative_elapsed,"completed_seconds":_cooperative_completed,"last_render_clock":_cooperative_last_frame,"root":_cooperative_root,"explicit_completion_resets":_cooperative_resets,"last_cancel_reason":_cooperative_cancel_reason}
 return result
