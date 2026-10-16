extends "res://scripts/clerk_motion_a2_blink_2d.gd"
## Presentation-only bridge. Root positions are observed, never written here.
const OBSERVED_STEP:float=1.0/120.0
var _observed_sequence:int=-1
var _observed_owner:int=-1
var _observed_reset_epoch:int=-1
var _observed_last_render_clock:float=-1.0
var _observed_clock:float=0.0
var _observed_batches:int=0
var _observed_samples:int=0
var _observed_duplicates:int=0
var _observed_unsupported:int=0
var _observed_last_input:Dictionary={}

func set_visual_context(clock:float,enabled:bool=true,reduced:bool=false) -> void:
 if not is_finite(clock):return
 _owner_clock=clock;_owner_enabled=enabled;_owner_reduced=reduced
 if not enabled and _model!=null:
  _model.freeze(_observed_clock,_rig_distance);_observed_last_render_clock=clock

func _observed_input(state:String,distance:float,right:bool,at:Vector2) -> Dictionary:
 return {"state":state,"distance":distance,"right":right,"position":at}

func apply_player_pose(state:String,distance_px:float,right:bool,enabled:bool=true,clock:float=NAN,stop_age:float=0.0) -> bool:
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or not _rig_ready:return false
 var frame_clock:float=_owner_clock if not is_finite(clock) else clock
 var input:Dictionary=_observed_input(state,distance_px,right,sprite.position)
 if _rig_active and frame_clock==_observed_last_render_clock and input==_observed_last_input:
  _observed_duplicates+=1;return true
 var elapsed:float=maxf(0.0,frame_clock-_observed_last_render_clock) if _observed_last_render_clock>=0.0 else 0.0
 _observed_last_render_clock=frame_clock;_observed_last_input=input
 if not enabled or not _owner_enabled or not sprite.is_visible_in_tree():
  _model.freeze(_observed_clock,distance_px);return true
 if _rig_active and _model.initialized and sprite.position.distance_to(_model.origin)>0.0001:
  # Unknown moving callers are rejected rather than given a fabricated path.
  # An inactive full-body/tablet boundary still uses the inherited explicit
  # neutral reset at its actual new root when the rig is restored.
  _observed_unsupported+=1;_issue("unobserved_clerk_root_path")
  return false
 if elapsed<=0.0:
  return super.apply_player_pose(state,distance_px,right,enabled,_observed_clock,stop_age)
 var remaining:float=minf(elapsed,0.1)
 var ok:bool=true
 while remaining>0.000001:
  var dt:float=minf(OBSERVED_STEP,remaining);remaining-=dt;_observed_clock+=dt
  ok=super.apply_player_pose(state,distance_px,right,enabled,_observed_clock,stop_age) and ok
 return ok

func apply_observed_root(batch:Dictionary,frame_clock:float,enabled:bool=true) -> bool:
 var sequence:int=int(batch.get("sequence",-1))
 var owner:int=int(batch.get("owner",-1));var reset_epoch:int=int(batch.get("reset_epoch",-1))
 if sequence==_observed_sequence and owner==_observed_owner and reset_epoch==_observed_reset_epoch:
  _observed_duplicates+=1;return true
 _observed_sequence=sequence;_observed_owner=owner;_observed_reset_epoch=reset_epoch
 return _apply_observed_segments(batch.get("segments",[]),frame_clock,enabled,"shop-root")

func apply_observed_cooperative(segments:Array,frame_clock:float,enabled:bool=true) -> bool:
 return _apply_observed_segments(segments,frame_clock,enabled,"cooperative-analytic-horizontal")

func _apply_observed_segments(segments:Array,frame_clock:float,enabled:bool,source:String) -> bool:
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or not _rig_ready:return false
 if not enabled or not _owner_enabled or not sprite.is_visible_in_tree():
  _model.freeze(_observed_clock,_rig_distance);_observed_last_render_clock=frame_clock;return true
 if segments.is_empty():return apply_player_pose(_player_state,_rig_distance,_facing_right,enabled,frame_clock,_rig_stop_age)
 if segments.size()>32:_observed_unsupported+=1;return false
 var first:Dictionary=segments[0].before
 if not _model.initialized or (not _rig_active and _model.origin.distance_to(first.position)>0.01):
  _model.reset(first.position,bool(first.facing_right),_observed_clock,float(first.distance))
 if not _observed_model_ready(first,frame_clock,source):return false
 var final:Dictionary={}
 for segment in segments:
  var dt:float=float(segment.dt)
  if dt<=0.0 or dt>OBSERVED_STEP+0.000001:_observed_unsupported+=1;return false
  var after:Dictionary=segment.after
  _observed_clock+=dt
  if not _model.update(str(after.state),float(after.distance),after.position,bool(after.facing_right),_observed_clock,float(after.stop_age),true,_owner_reduced):return false
  if not _observed_model_segment_accepted(segment,_observed_clock,frame_clock,source):return false
  _observed_samples+=1;final=after
 if final.position.distance_to(sprite.position)>0.0001:_observed_unsupported+=1;return false
 _observed_batches+=1;_observed_last_render_clock=frame_clock
 _observed_last_input=_observed_input(str(final.state),float(final.distance),bool(final.facing_right),final.position)
 _rig_active=true;_rig_distance=float(final.distance);_rig_stop_age=float(final.stop_age)
 _player_state=str(final.state);_facing_right=bool(final.facing_right);_active=true
 _pose="walk" if _player_state in MOVING_STATES else _player_state
 _frame_index=-1;_walk_phase=-1;_walk_phase_fraction=_model.step_fraction
 _stance_shift=0.0;_frame=_neutral
 sprite.texture=null;sprite.material=_original.get("material")
 sprite.scale=Vector2.ONE;sprite.rotation=0.0;sprite.skew=0.0;sprite.offset=Vector2.ZERO;sprite.flip_h=false;sprite.flip_v=false
 _rig.visible=true;_render_rig()
 sprite.set_meta("pose",_pose);sprite.set_meta("motion_frame",-1);sprite.set_meta("motion_active",true)
 sprite.set_meta("motion_facing_right",_facing_right);sprite.set_meta("motion_support_shift",0.0)
 sprite.set_meta("art_id",RIG_MANIFEST);sprite.set_meta("motion_diagnostics",_issues.duplicate())
 return true

func advance_visual(clock:float,enabled:bool=true,reduced:bool=false) -> bool:
 set_visual_context(clock,enabled,reduced)
 if not _rig_active:return false
 if clock==_observed_last_render_clock:_observed_duplicates+=1;return true
 return apply_player_pose(_player_state,_rig_distance,_facing_right,enabled,clock,_rig_stop_age)

func debug_snapshot() -> Dictionary:
 var result:Dictionary=super.debug_snapshot()
 result.observed_bridge={"pose_clock":_observed_clock,"render_clock":_observed_last_render_clock,"batches":_observed_batches,"samples":_observed_samples,"duplicate_skips":_observed_duplicates,"unsupported_paths":_observed_unsupported,"sequence":_observed_sequence,"owner":_observed_owner,"reset_epoch":_observed_reset_epoch}
 return result

func _observed_model_ready(_first:Dictionary,_frame_clock:float,_source:String) -> bool:
 # Default no-op: existing non-experimental semantics are unchanged.
 return true

func _observed_model_segment_accepted(_segment:Dictionary,_model_clock:float,_frame_clock:float,_source:String) -> bool:
 # Invoked only after the existing model.update accepted this actual segment.
 return true
