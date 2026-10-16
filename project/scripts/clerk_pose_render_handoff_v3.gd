extends "res://scripts/clerk_pose_render_bridge_v1.gd"
## DEFAULT-OFF handoff successor. World contract remains 0 pending ingestion/abort gates.
const CoupledBody=preload("res://scripts/clerk_shop_run_pose_v1.gd")
const ArmProvider=preload("res://scripts/clerk_arm_owner_transfer_v2.gd")
const COUPLED_MAX_STEP:float=1.0/120.0
var arm_coupling_enabled:bool=false
var _coupled_arms=ArmProvider.new()
var _coupled_seeded:bool=false
var _coupled_body_stamp:PackedByteArray=PackedByteArray()
var _coupled_owner_input:Dictionary={}
var _coupled_commit_failed:bool=false
var _coupled_status:String="disabled"
var _coupled_velocity_source:String="none"

func enable_pose_experiment(profile:Dictionary,tablet_parts:Dictionary) -> bool:
 # Called virtually by inherited bind, still before any model initialization.
 if accepted_pose_experiment_enabled or not _rig_ready or _model==null or _model.initialized:return false
 if not profile.get("presentation") is Dictionary:return false
 var candidate=CoupledBody.new();var helper=TabletPresentation.new()
 if not candidate.configure(profile,_height) or not helper.configure(tablet_parts,profile.parts):return false
 _rig_data=profile.duplicate(true);_model=candidate;_pose_helper=helper
 accepted_pose_experiment_enabled=true
 return true

func bind_coupled_renderer(profile:Dictionary,tablet_parts:Dictionary,head_views:Array,textures:Dictionary) -> bool:
 if arm_coupling_enabled:return false
 var provider=ArmProvider.new()
 if not provider.configure(_height):return false
 if not bind_pose_renderer(profile,tablet_parts,head_views,textures):return false
 _coupled_arms=provider;arm_coupling_enabled=true
 _coupled_status="bound_before_initialization; accepted arm seed required"
 return true

func _body_stamp() -> PackedByteArray:
 # Deliberately excludes owner/requested facing and all render clocks.
 return var_to_bytes({"origin":_model.origin,"hip":_model.hip,"joints":_model.joints,
  "upper_body":_model.upper_body,"facing_right":_model.facing_right})

func accept_root_owner_segment(root_owner_snapshot:Dictionary,accepted_time:float) -> bool:
 # Pass the real RootOwner snapshot. Displacement/dt and model._candidate_speed
 # are deliberately not substitutes for this authoritative ending velocity.
 if not _owner_enabled or not _pose_focus_active:return false
 if not root_owner_snapshot.has_all(["position","velocity"]):return false
 if _model==null or not _model.initialized:return false
 var position:Vector2=_bridge_point(root_owner_snapshot.position)
 if not position.is_finite() or position.distance_to(_model.origin)>0.0001:return false
 return _accept_arm_segment(float(root_owner_snapshot.velocity),accepted_time,"root_owner_snapshot.velocity")

func _accept_arm_segment(root_ending_velocity:float,accepted_time:float,source:String) -> bool:
 # Caller invokes once AFTER an actual accepted model segment, BEFORE display.
 # Initial call explicitly seeds the already-initialized body; no model reset.
 if not arm_coupling_enabled or not _rig_active or _model==null or not _model.initialized:return false
 if not _pose_available() or not is_finite(root_ending_velocity) or not is_finite(accepted_time):return false
 if _bridge_has_owner() and _coupled_owner_input.is_empty():return false
 if not _coupled_arms.advance(_model.snapshot(),root_ending_velocity,accepted_time):return false
 _coupled_seeded=true;_coupled_body_stamp=_body_stamp()
 _coupled_status="accepted_segment";_coupled_velocity_source=source
 return true

func _coupled_checkpoint() -> Dictionary:
 return {"base":_owner_checkpoint(),"arms":_copy_script_state(_coupled_arms),
  "walk":_copy_script_state(_coupled_arms._walk)}

func _slice_rollback_owned_by_caller() -> bool:
 # advance_coupled_owner creates this context only AFTER its full coupled
 # checkpoint. Every failed slice/commit returns through _coupled_restore.
 # There is no yield or callback handoff before that outer transaction ends.
 return arm_coupling_enabled and not _coupled_owner_input.is_empty()

func _coupled_restore(saved:Dictionary) -> void:
 _restore_checkpoint(saved.base)
 for key in saved.arms:_coupled_arms.set(key,saved.arms[key])
 for key in saved.walk:_coupled_arms._walk.set(key,saved.walk[key])

func _capture_arm_owner(kind:String) -> bool:
 if not _coupled_seeded:return false
 var status:Dictionary=_coupled_arms.status()
 # A new session while the same visual neutral owner remains needs no rewind.
 if status.mode in ["acquire","neutral"]:return str(status.owner)==kind
 return _coupled_arms.acquire(kind,float(status.accepted_time))

func apply_cooperative_gesture(pose_id:String,right:bool,owner:int) -> bool:
 if not arm_coupling_enabled:return super.apply_cooperative_gesture(pose_id,right,owner)
 if not _coupled_seeded or _coupled_body_stamp!=_body_stamp():return false
 var saved:Dictionary=_coupled_checkpoint()
 if not super.apply_cooperative_gesture(pose_id,right,owner):return false
 if not _capture_arm_owner("cooperative"):_coupled_restore(saved);return false
 return true

func begin_review_phone(owner:int) -> bool:
 if not arm_coupling_enabled:return super.begin_review_phone(owner)
 if not _coupled_seeded or _coupled_body_stamp!=_body_stamp():return false
 # A held prop can change authority only through the explicit guarded transfer.
 if owner!=_phone_owner and (_accepted_pose.draw_progress>0.0 or _bridge_has_owner()):return false
 var saved:Dictionary=_coupled_checkpoint()
 if not super.begin_review_phone(owner):return false
 if not _capture_arm_owner("phone"):_coupled_restore(saved);return false
 return true

func advance_cooperative_pose_slice(owner:int,elapsed:float,frame_clock:float,slice_id:int) -> bool:
 if arm_coupling_enabled and _coupled_owner_input.is_empty():return false
 return super.advance_cooperative_pose_slice(owner,elapsed,frame_clock,slice_id)

func advance_review_phone(owner:int,elapsed:float,frame_clock:float) -> bool:
 if arm_coupling_enabled and _coupled_owner_input.is_empty():return false
 return super.advance_review_phone(owner,elapsed,frame_clock)

func advance_coupled_owner(kind:String,owner:int,elapsed:float,frame_clock:float,accepted_time:float,root_ending_velocity:float=0.0,slice_id:int=0) -> bool:
 # No hidden provider samples inside an aggregated owner interval. The caller
 # retains physical settle, then arm return, then tablet lower/raise ownership.
 if not arm_coupling_enabled or not _coupled_seeded or not _coupled_owner_input.is_empty():return false
 if kind not in ["cooperative","phone"] or not is_finite(elapsed) or elapsed<=0.0 or elapsed>COUPLED_MAX_STEP+0.000000000001:return false
 if not is_finite(root_ending_velocity) or root_ending_velocity!=0.0:return false
 var previous:float=float(_coupled_arms.status().accepted_time)
 if not is_finite(accepted_time) or absf((accepted_time-previous)-elapsed)>0.000000000001:return false
 var saved:Dictionary=_coupled_checkpoint()
 _coupled_owner_input={"kind":kind,"time":accepted_time,"velocity":root_ending_velocity,"previous":previous}
 _coupled_commit_failed=false
 var ok:bool=advance_review_phone_slice(owner,elapsed,frame_clock,slice_id) if kind=="phone" else advance_cooperative_pose_slice(owner,elapsed,frame_clock,slice_id)
 if not ok or _coupled_commit_failed:
  _coupled_restore(saved);_coupled_owner_input={}
  _coupled_status="rejected_coupled_owner_segment"
  _render_rig()
  return false
 _coupled_owner_input={}
 return true

func world_consumer_contract_version() -> int:
 # Root batch ingestion and explicit teardown have not yet passed their gate.
 return 0

func advance_review_phone_slice(owner:int,elapsed:float,frame_clock:float,slice_id:int) -> bool:
 if arm_coupling_enabled and _coupled_owner_input.is_empty():return false
 return super.advance_review_phone_slice(owner,elapsed,frame_clock,slice_id)

func _commit_slice(token:Dictionary,elapsed:float,draw_elapsed:float) -> void:
 if not arm_coupling_enabled:super._commit_slice(token,elapsed,draw_elapsed);return
 if _coupled_owner_input.is_empty():_coupled_commit_failed=true;return
 var before:Dictionary=_coupled_arms.status()
 var end:float=float(_coupled_owner_input.time)
 if not _accept_arm_segment(float(_coupled_owner_input.velocity),end,"explicit_stationary_owner_ending_velocity"):_coupled_commit_failed=true;return
 var arm_ready_suffix:float=elapsed if bool(before.pickup_ready) else 0.0
 if str(before.mode)=="acquire":
  var ready_at:float=float(before.started)+float(before.duration)
  arm_ready_suffix=clampf(end-ready_at,0.0,elapsed)
 # Both are suffixes of this exact accepted segment: intersect their budgets.
 super._commit_slice(token,elapsed,minf(draw_elapsed,arm_ready_suffix))

func finish_coupled_owner(kind:String,owner:int) -> bool:
 if not arm_coupling_enabled or not _coupled_seeded or _accepted_pose.draw_progress>0.000001:return false
 if _coupled_arms.status().mode not in ["acquire","neutral"]:return false
 if kind=="phone":
  if owner==0 or owner!=_phone_owner:return false
  super.end_review_phone(owner)
 elif kind=="cooperative":
  if owner!=_cooperative_owner or _cooperative_gesture.is_empty():return false
  super._cancel_cooperative("explicit_lowered_coupled_release")
 else:return false
 if not _coupled_arms.cancel(float(_coupled_arms.status().accepted_time)):return false
 _coupled_status="released_at_lowered_endpoint"
 return true


func end_review_phone(owner:int) -> void:
 if not arm_coupling_enabled:super.end_review_phone(owner);return
 if owner==0 or owner!=_phone_owner:return
 if _accepted_pose.draw_progress<=0.000001:
  finish_coupled_owner("phone",owner)
 else:
  super.end_review_phone(owner)
  _coupled_status="unsupported_unlowered_release"

func _cancel_cooperative(reason:String,lower:bool=true) -> void:
 var was_owner:bool=not _cooperative_gesture.is_empty()
 super._cancel_cooperative(reason,lower)
 if not arm_coupling_enabled or not was_owner or not _coupled_seeded:return
 if _accepted_pose.draw_progress<=0.000001:
  _coupled_arms.cancel(float(_coupled_arms.status().accepted_time))
 else:_coupled_status="unsupported_unlowered_release"

func reset_cooperative_completion(right:bool,owner:int) -> void:
 # The only permitted provider reseed after model initialization is the same
 # explicit historical relocation endpoint already authorized by the owner.
 super.reset_cooperative_completion(right,owner)
 if not arm_coupling_enabled or not _model.initialized:return
 var accepted_time:float=float(_coupled_arms.status().accepted_time)
 var replacement=ArmProvider.new()
 if not replacement.configure(_height) or not replacement.advance(_model.snapshot(),0.0,accepted_time):
  _coupled_status="invalid_explicit_endpoint_provider_seed";return
 _coupled_arms=replacement;_coupled_seeded=true;_coupled_body_stamp=_body_stamp()
 _coupled_velocity_source="explicit_completion_endpoint_zero_velocity"
 _render_rig()

func _walking_result() -> Dictionary:
 var context:Dictionary=accepted_pose_context()
 context.weight=0.0;context.draw_progress=0.0;context.ready_blend=0.0
 context.tap_blend=0.0;context.gaze_progress=0.0
 var result:Dictionary=_pose_helper.evaluate(context)
 if not result.get("valid",false):return result
 var provider:Dictionary=_coupled_arms.snapshot()
 for side in ["near","far"]:
  for item in [["upper",side+"_upper"],["fore",side+"_fore"],["hand",side+"_hand_relaxed"]]:
   var slot:String=side+"_"+str(item[0]);var source:String=str(item[1])
   var placement:Dictionary=provider.placements[source]
   result.placements[slot].texture_key=source
   result.placements[slot].root=_bridge_point(_pose_helper.tablet_parts[source].root)
   result.placements[slot].at=placement.at;result.placements[slot].angle=placement.angle
   result.placements[slot].mirror=1.0
 # Canonical level source at the actual V2 head angle and neck; blink deferred.
 result.placements.head.texture_key="head_level"
 result.placements.head.root=_bridge_point(_pose_head_views[0].root)
 result.status="V4/provider placement overlay; blink not wired"
 return result

func _render_tablet_pose() -> void:
 if not arm_coupling_enabled:super._render_tablet_pose();return
 if not _rig_active or _model==null or not _model.initialized:return
 if not _coupled_seeded or _coupled_body_stamp!=_body_stamp():
  _coupled_status="missing_or_stale_accepted_arm_segment"
  if not _bridge_last_draw.is_empty():_bridge_apply_result(_bridge_last_draw,_bridge_last_facing)
  return
 if _accepted_pose.draw_progress>0.000001 or _bridge_explicit_completion:
  # Accepted tablet placements retain ownership until a genuinely lowered exit.
  super._render_tablet_pose()
  return
 var result:Dictionary=_walking_result()
 if not _bridge_apply_result(result,_model.facing_right):
  _coupled_status="invalid_provider_draw";return
 _pose_result=result;_bridge_last_draw=result.duplicate(true)
 _bridge_last_facing=_model.facing_right;_bridge_status="drawn_coupled_provider"

func coupled_renderer_snapshot() -> Dictionary:
 return {"enabled":arm_coupling_enabled,"status":_coupled_status,
  "provider":_coupled_arms.status(),"body":"UpperResponseV2",
  "velocity_policy":"authoritative root ending velocity, explicit accepted segments",
  "last_velocity_source":_coupled_velocity_source,
  "blink":"not wired; canonical level source only", "acceptance":"WIP; no native or performance claim"}

func transfer_coupled_ready_to_phone(cooperative_owner:int,phone_owner:int) -> bool:
 # An event-time authority switch. No draw call, sample, reset, or elapsed time.
 if not arm_coupling_enabled or not _coupled_seeded or not _owner_enabled or not _pose_available():return false
 if not _coupled_owner_input.is_empty() or phone_owner==0 or _phone_owner!=0:return false
 if _cooperative_owner!=cooperative_owner or _cooperative_gesture!="ready" or _cooperative_phase!="raise":return false
 if _pose_lower_requested or _accepted_pose.draw_progress!=1.0 or _accepted_pose.draw_target!=1.0 or _accepted_pose.ready_blend!=1.0:return false
 if _accepted_pose.gesture!="ready" or _accepted_pose.tap_blend!=0.0:return false
 if not _model.initialized or not _model.settled or _model.settling or _model.travelling:return false
 if not _model.feet.near.planted or not _model.feet.far.planted:return false
 if _node().position!=_model.origin or _node().position!=_cooperative_root:return false
 if _coupled_body_stamp!=_body_stamp() or _bridge_last_draw.is_empty():return false
 var status:Dictionary=_coupled_arms.status()
 if status.mode!="neutral" or status.owner!="cooperative":return false
 if _coupled_velocity_source!="explicit_stationary_owner_ending_velocity":return false
 var saved:Dictionary=_coupled_checkpoint()
 if not _coupled_arms.transfer_neutral_owner("cooperative","phone",float(status.accepted_time)):return false
 # Bypass our ordinary cancellation guard only after the above exact boundary.
 # This is not a release; the single displayed prop remains wholly owned.
 super._cancel_cooperative("explicit_same_prop_phone_transfer",false)
 if not super.begin_review_phone(phone_owner):
  _coupled_restore(saved);return false
 _tablet_gesture="reach"
 _coupled_status="held_cooperative_to_phone_transferred"
 return true

func _blocks_unlowered_external_motion(enabled:bool) -> bool:
 # Reject before the inherited owner/sequence/model bookkeeping can mutate.
 return arm_coupling_enabled and enabled and _owner_enabled and _pose_available() and (_bridge_has_owner() or _accepted_pose.draw_progress>0.0)

func apply_player_pose(state:String,distance_px:float,right:bool,enabled:bool=true,clock:float=NAN,stop_age:float=0.0) -> bool:
 if _blocks_unlowered_external_motion(enabled):return false
 return super.apply_player_pose(state,distance_px,right,enabled,clock,stop_age)

func apply_observed_root(batch:Dictionary,frame_clock:float,enabled:bool=true) -> bool:
 if _blocks_unlowered_external_motion(enabled):return false
 return super.apply_observed_root(batch,frame_clock,enabled)

func apply_observed_cooperative(segments:Array,frame_clock:float,enabled:bool=true) -> bool:
 if _blocks_unlowered_external_motion(enabled):return false
 return super.apply_observed_cooperative(segments,frame_clock,enabled)
