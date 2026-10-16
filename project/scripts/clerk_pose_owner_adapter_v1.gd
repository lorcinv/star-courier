extends "res://scripts/clerk_recovery_motion_2d.gd"
## DEFAULT OFF. No World selector changes. Source/ownership experiment only.
const AnatomyPose=preload("res://scripts/clerk_anatomy_motion_pose_v1.gd")
const AcceptedPose=preload("res://scripts/clerk_accepted_pose_state.gd")
const TabletPresentation=preload("res://scripts/clerk_tablet_continuity_v2.gd")
var accepted_pose_experiment_enabled:bool=false
var _accepted_pose=AcceptedPose.new()
var _pose_helper=TabletPresentation.new()
var _pose_last_token:Dictionary={}
var _pose_result:Dictionary={}
var _pose_head_views:Array=[]
var _pose_focus_active:bool=true
var _pose_generation:int=0
var _pose_lower_requested:bool=false

func enable_pose_experiment(profile:Dictionary,tablet_parts:Dictionary) -> bool:
 # Initialization only: replacing a live model would destroy actual contacts.
 if accepted_pose_experiment_enabled or not _rig_ready or _model==null or _model.initialized:return false
 var candidate=AnatomyPose.new()
 var helper=TabletPresentation.new()
 if not candidate.configure(profile,_height) or not helper.configure(tablet_parts,profile.parts):return false
 _rig_data=profile.duplicate(true);_model=candidate;_pose_helper=helper
 accepted_pose_experiment_enabled=true
 return true

func _uses_accepted_pose_clock() -> bool:
 return accepted_pose_experiment_enabled

func set_pose_focus_active(active:bool) -> void:
 # Explicit host focus gate; no elapsed time is banked for a later resume.
 _pose_focus_active=active

func set_pose_head_views(views:Array) -> bool:
 # Optional registration only. No synthetic head image or implied acceptance.
 if not views.is_empty() and views.size()!=3:return false
 for view in views:
  if not view is Dictionary or not view.has_all(["texture_key","root"]):return false
 _pose_head_views=views.duplicate(true)
 return true

func _pose_available() -> bool:
 return _pose_focus_active and is_instance_valid(_node()) and _node().is_visible_in_tree() and _rig_active and _model!=null

func _new_pose_owner(gesture:String="reach") -> void:
 _pose_generation+=1;_pose_last_token={};_pose_lower_requested=false
 _accepted_pose.begin_owner(gesture)

func apply_cooperative_gesture(pose_id:String,right:bool,owner:int) -> bool:
 if not accepted_pose_experiment_enabled:return super.apply_cooperative_gesture(pose_id,right,owner)
 if not _pose_focus_active:return false
 var was_owner:bool=not _cooperative_gesture.is_empty() and _cooperative_owner==owner
 var ok:bool=super.apply_cooperative_gesture(pose_id,right,owner)
 if not ok:return false
 if not was_owner:_new_pose_owner(pose_id)
 _accepted_pose.intent(pose_id)
 _accepted_pose.draw_target=0.0 if _pose_lower_requested else 1.0
 return true

func begin_review_phone(owner:int) -> bool:
 if not accepted_pose_experiment_enabled:return super.begin_review_phone(owner)
 if owner==0 or not _pose_available():return false
 if owner==_phone_owner:return true
 var ok:bool=super.begin_review_phone(owner)
 if ok:
  _new_pose_owner();_accepted_pose.intent("reach");_accepted_pose.draw_target=1.0
 return ok

func set_phone_pose_intent(owner:int,gesture:String) -> bool:
 if not accepted_pose_experiment_enabled or owner==0 or owner!=_phone_owner or not _pose_available():return false
 if not _accepted_pose.intent(gesture):return false
 _tablet_gesture=gesture
 return true

func request_pose_lower(owner:int,kind:String) -> bool:
 if not accepted_pose_experiment_enabled or not _pose_available():return false
 if kind=="phone":
  if owner==0 or owner!=_phone_owner:return false
 elif kind=="cooperative":
  if _cooperative_gesture.is_empty() or owner!=_cooperative_owner or not _owner_enabled:return false
 else:return false
 _pose_lower_requested=true;_accepted_pose.request_lower()
 return true

func end_review_phone(owner:int) -> void:
 if not accepted_pose_experiment_enabled:super.end_review_phone(owner);return
 if owner!=_phone_owner:return
 super.end_review_phone(owner)
 _accepted_pose.request_lower()
 # Release grants no further elapsed slices. Finish animated lower beforehand.

func _copy_script_state(object:Object) -> Dictionary:
 var saved:Dictionary={}
 for property in object.get_property_list():
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
   var value:Variant=object.get(property.name)
   saved[property.name]=value.duplicate(true) if value is Dictionary or value is Array else value
 return saved

func _slice_rollback_owned_by_caller() -> bool:
 # Standalone adapters retain their own complete rollback checkpoint.
 return false

func _owner_checkpoint() -> Dictionary:
 return {"owner":_copy_script_state(self),"model":_copy_script_state(_model),
  "presentation":_copy_script_state(_accepted_pose),"helper":_copy_script_state(_pose_helper)}

func _restore_checkpoint(saved:Dictionary) -> void:
 for key in saved.owner:set(key,saved.owner[key])
 for key in saved.model:_model.set(key,saved.model[key])
 for key in saved.presentation:_accepted_pose.set(key,saved.presentation[key])
 for key in saved.helper:_pose_helper.set(key,saved.helper[key])

func _valid_slice(elapsed:float,frame_clock:float) -> bool:
 return is_finite(elapsed) and elapsed>0.0 and elapsed<=0.25 and is_finite(frame_clock)

func _slice_token(kind:String,owner:int,frame_clock:float,slice_id:int) -> Dictionary:
 return {"kind":kind,"owner":owner,"clock":frame_clock,"slice":slice_id,"generation":_pose_generation}

func _commit_slice(token:Dictionary,elapsed:float,draw_elapsed:float) -> void:
 _accepted_pose.consume(elapsed,draw_elapsed)
 _pose_last_token=token;_tablet_weight=_accepted_pose.draw_progress
 _render_rig()

func advance_review_phone(owner:int,elapsed:float,frame_clock:float) -> bool:
 if not accepted_pose_experiment_enabled:return super.advance_review_phone(owner,elapsed,frame_clock)
 return advance_review_phone_slice(owner,elapsed,frame_clock,0)

func _review_phone_clock_duplicate(frame_clock:float) -> bool:
 # Enabled calls have already passed the explicit unique-token gate below.
 return super._review_phone_clock_duplicate(frame_clock) if not accepted_pose_experiment_enabled else false

func advance_review_phone_slice(owner:int,elapsed:float,frame_clock:float,slice_id:int) -> bool:
 if not accepted_pose_experiment_enabled or not _valid_slice(elapsed,frame_clock) or slice_id<0:return false
 if owner==0 or owner!=_phone_owner or not _pose_available():return false
 if _node().position!=_model.origin:return false
 var token:Dictionary=_slice_token("phone",owner,frame_clock,slice_id)
 if token==_pose_last_token:return true
 if frame_clock<_phone_last_frame:return false
 if not _pose_last_token.is_empty() and frame_clock<float(_pose_last_token.clock):return false
 if not _pose_last_token.is_empty() and _pose_last_token.kind=="phone" and frame_clock==_pose_last_token.clock and slice_id<=int(_pose_last_token.slice):return false
 var before:float=_phone_elapsed
 var phase_before:String=_phone_phase
 var owns_rollback:bool=not _slice_rollback_owned_by_caller()
 var checkpoint:Dictionary=_owner_checkpoint() if owns_rollback else {}
 var ok:bool=super.advance_review_phone(owner,elapsed,frame_clock)
 if not ok:
  if owns_rollback:_restore_checkpoint(checkpoint)
  return false
 var settle_used:float=_phone_elapsed-before if phase_before=="settle" else 0.0
 var draw_elapsed:float=maxf(0.0,elapsed-settle_used) if _phone_phase=="raise" else 0.0
 _commit_slice(token,elapsed,draw_elapsed)
 return true

func advance_cooperative_gesture(owner:int,elapsed:float,frame_clock:float) -> bool:
 if not accepted_pose_experiment_enabled:return super.advance_cooperative_gesture(owner,elapsed,frame_clock)
 return advance_cooperative_pose_slice(owner,elapsed,frame_clock,0)

func advance_cooperative_pose_slice(owner:int,elapsed:float,frame_clock:float,slice_id:int) -> bool:
 # A caller with multiple real slices in a render frame supplies unique IDs.
 # The compatibility entry point accepts at most one slice per frame clock.
 if not accepted_pose_experiment_enabled or not _valid_slice(elapsed,frame_clock) or slice_id<0:return false
 if owner!=_cooperative_owner or _cooperative_gesture.is_empty() or not _owner_enabled or not _pose_available():return false
 if _node().position!=_cooperative_root or _node().position!=_model.origin:return false
 var token:Dictionary=_slice_token("cooperative",owner,frame_clock,slice_id)
 if token==_pose_last_token:return true
 if not _pose_last_token.is_empty() and frame_clock<float(_pose_last_token.clock):return false
 if not _pose_last_token.is_empty() and _pose_last_token.kind=="cooperative" and frame_clock==_pose_last_token.clock and slice_id<=int(_pose_last_token.slice):return false
 var before:float=_cooperative_elapsed
 var phase_before:String=_cooperative_phase
 var owns_rollback:bool=not _slice_rollback_owned_by_caller()
 var checkpoint:Dictionary=_owner_checkpoint() if owns_rollback else {}
 var ok:bool=super.advance_cooperative_gesture(owner,elapsed,frame_clock)
 if not ok:
  if owns_rollback:_restore_checkpoint(checkpoint)
  return false
 var draw_elapsed:float=0.0
 if _cooperative_phase=="raise":
  # Already-settled presentation owns this entire accepted slice, including a
  # positive terminal tail below the inherited body's micro-step threshold.
  # Do not recover its duration by subtracting rounded cumulative clocks.
  draw_elapsed=elapsed if phase_before=="raise" else clampf(_cooperative_elapsed-maxf(before,_cooperative_completed),0.0,elapsed)
 _commit_slice(token,elapsed,draw_elapsed)
 return true

func advance_visual(clock:float,enabled:bool=true,reduced:bool=false) -> bool:
 if not accepted_pose_experiment_enabled:return super.advance_visual(clock,enabled,reduced)
 # Render/context input cannot manufacture accepted owner slices.
 set_visual_context(clock,enabled,reduced)
 if not _cooperative_gesture.is_empty() or _phone_owner!=0:return true
 return super.advance_visual(clock,enabled,reduced)

func reset_cooperative_completion(right:bool,owner:int) -> void:
 super.reset_cooperative_completion(right,owner)
 if accepted_pose_experiment_enabled:
  _new_pose_owner("ready");_accepted_pose.complete_ready_endpoint()
  _tablet_weight=1.0;_tablet_target=1.0
  _render_rig()

func accepted_pose_context() -> Dictionary:
 if not accepted_pose_experiment_enabled or _model==null or not _model.initialized:return {}
 var upper:Dictionary=_model.upper_body.duplicate(true)
 var origin:Vector2=_model.origin
 upper.torso_pivot_world-=origin;upper.neck_world-=origin
 for side in ["near","far"]:upper.shoulder_world[side]-=origin
 var context:Dictionary={"hip":_model.hip-origin,"upper_body":upper,"height":_height,
  "facing_right":_model.facing_right,"weight":_accepted_pose.draw_progress,
  "draw_progress":_accepted_pose.draw_progress,"gesture":_accepted_pose.gesture,
  "gesture_age":_accepted_pose.gesture_age,"ready_blend":_accepted_pose.ready_blend,
  "tap_blend":_accepted_pose.tap_blend,
  "coordinate_space":"actor_root_relative_pixels"}
 if not _pose_head_views.is_empty():context.head_views=_pose_head_views.duplicate(true)
 return context

func _render_tablet_pose() -> void:
 if not accepted_pose_experiment_enabled:super._render_tablet_pose();return
 var context:Dictionary=accepted_pose_context()
 if context.is_empty():return
 _pose_result=_pose_helper.evaluate(context)
 # Deliberately evaluation-only until a separate art/draw gate. No fake heads.
 # Root/contact/model state is never written by this hook.
 if _parts.has("pelvis"):_parts.pelvis.visible=false

func accepted_pose_snapshot() -> Dictionary:
 return {"enabled":accepted_pose_experiment_enabled,"controls":_accepted_pose.snapshot(),
  "last_token":_pose_last_token.duplicate(true),"result":_pose_result.duplicate(true),
  "head_views_configured":not _pose_head_views.is_empty(),"draw_status":"PENDING: evaluation only; art HOLD"}
