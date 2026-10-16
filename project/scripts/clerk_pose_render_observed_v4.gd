extends "res://scripts/clerk_pose_render_handoff_v3.gd"
## DEFAULT OFF. Real observed segments provide provider time and end velocity.
const AbortProvider=preload("res://scripts/clerk_arm_owner_abort_v3.gd")
var _observed_coupled_input:Dictionary={}
var _observed_coupled_provenance:Dictionary={}
var _observed_coupled_analytic_token:PackedByteArray=PackedByteArray()
var _observed_coupled_dropped_root:Dictionary={}
var _observed_coupled_dropped_root_frame:float=-INF
var _observed_coupled_dropped_analytic_frame:float=-INF
var _observed_coupled_analytic_frame:float=-INF
var _observed_coupled_analytic_seen:Array=[]
var _observed_coupled_dropped_analytic:PackedByteArray=PackedByteArray()
var _observed_coupled_owner_frame:float=-INF
var _observed_coupled_root_frame:float=-INF
var _observed_coupled_release_frame:float=-INF
var _observed_coupled_release_dropped_frame:float=-INF
var _observed_coupled_release_token:PackedByteArray=PackedByteArray()
var _observed_coupled_release_consumed:float=0.0

func bind_coupled_renderer(profile:Dictionary,tablet_parts:Dictionary,head_views:Array,textures:Dictionary) -> bool:
 if not super.bind_coupled_renderer(profile,tablet_parts,head_views,textures):return false
 # Explicitly before initialization or any accepted arm sample.
 var candidate=AbortProvider.new()
 if not candidate.configure(_height):return false
 _coupled_arms=candidate
 return true

func _ingest_active(enabled:bool) -> bool:
 return enabled and _owner_enabled and _pose_focus_active and is_instance_valid(_node()) and _node().is_visible_in_tree()

func _valid_root_row(row:Variant) -> bool:
 if not row is Dictionary or not row.has_all(["position","velocity","distance","facing_right","state","stop_age"]):return false
 if not row.position is Vector2 or not row.position.is_finite() or not row.facing_right is bool:return false
 if str(row.state) not in PLAYER_STATES:return false
 return is_finite(float(row.velocity)) and is_finite(float(row.distance)) and float(row.distance)>=0.0 and is_finite(float(row.stop_age)) and float(row.stop_age)>=0.0

func _valid_observed_batch(segments:Array,frame_clock:float) -> bool:
 if not is_finite(frame_clock) or segments.size()>32 or not _rig_ready or _model==null or not _model.initialized:return false
 if _node().position!=_model.origin and segments.is_empty():return false
 var previous:Dictionary={}
 for segment in segments:
  if not segment is Dictionary or not segment.has_all(["dt","before","after"]):return false
  var dt:float=float(segment.dt)
  if not is_finite(dt) or dt<=0.0 or dt>COUPLED_MAX_STEP+0.000000000001:return false
  if not _valid_root_row(segment.before) or not _valid_root_row(segment.after):return false
  if previous.is_empty():
   if segment.before.position.distance_to(_model.origin)>0.0001:return false
  elif segment.before.position.distance_to(previous.position)>0.0001 or absf(float(segment.before.distance)-float(previous.distance))>0.0001:return false
  previous=segment.after
 if not previous.is_empty() and previous.position.distance_to(_node().position)>0.0001:return false
 return true

func _observed_model_ready(first:Dictionary,frame_clock:float,source:String) -> bool:
 if not arm_coupling_enabled:return super._observed_model_ready(first,frame_clock,source)
 if _observed_coupled_input.is_empty():return false
 if _coupled_seeded:return _coupled_body_stamp==_body_stamp()
 return _publish_observed_arm(first,0.0,frame_clock,source,true)

func _publish_observed_arm(row:Dictionary,dt:float,frame_clock:float,source:String,seed:bool=false) -> bool:
 var cursor:float=float(_coupled_arms.status().accepted_time)
 var accepted_at:float=cursor if seed else cursor+dt
 if not _coupled_arms.advance(_model.snapshot(),float(row.velocity),accepted_at):return false
 _coupled_seeded=true;_coupled_body_stamp=_body_stamp()
 _coupled_status="accepted_actual_observed_segment"
 _coupled_velocity_source=source+".after.velocity" if not seed else source+".initial.velocity"
 _observed_coupled_provenance={"source":source,"source_frame_clock":frame_clock,"model_pose_clock":_model.pose_time,
  "model_observed_clock":_observed_clock,"segment_dt":dt,"root_snapshot":row.duplicate(true),
  "accepted_presentation_cursor_before":cursor,"accepted_presentation_cursor_after":accepted_at,"initial_seed":seed}
 return true

func _observed_model_segment_accepted(segment:Dictionary,model_clock:float,frame_clock:float,source:String) -> bool:
 if not arm_coupling_enabled:return super._observed_model_segment_accepted(segment,model_clock,frame_clock,source)
 if _observed_coupled_input.is_empty():return false
 if not _publish_observed_arm(segment.after,float(segment.dt),frame_clock,source):return false
 _observed_coupled_provenance.segment_before=segment.before.duplicate(true)
 _observed_coupled_provenance.source_model_clock=model_clock
 return true

func _consume_observed_batch(segments:Array,frame_clock:float,source:String) -> bool:
 if not _observed_coupled_input.is_empty() or not _valid_observed_batch(segments,frame_clock):return false
 if frame_clock<maxf(_observed_last_render_clock,_observed_coupled_owner_frame):return false
 if not segments.is_empty() and frame_clock in [_observed_coupled_owner_frame,_observed_coupled_release_frame]:return false
 if segments.is_empty():
  if not _coupled_seeded:return false
  _render_rig();return true
 var saved:Dictionary=_coupled_checkpoint()
 var had_facing_meta:bool=_node().has_meta("motion_facing_right")
 var facing_meta:Variant=_node().get_meta("motion_facing_right") if had_facing_meta else null
 _observed_coupled_input={"source":source,"frame_clock":frame_clock}
 var ok:bool=super._apply_observed_segments(segments,frame_clock,true,source)
 if not ok:
  _coupled_restore(saved)
  # The inherited tablet wrapper publishes this metadata even on failure.
  if had_facing_meta:_node().set_meta("motion_facing_right",facing_meta)
  else:_node().remove_meta("motion_facing_right")
  return false
 _observed_coupled_input={}
 _observed_coupled_root_frame=frame_clock
 return true

func apply_observed_root(batch:Dictionary,frame_clock:float,enabled:bool=true) -> bool:
 if not arm_coupling_enabled:return super.apply_observed_root(batch,frame_clock,enabled)
 if not _coupled_target_alive():return false
 if not batch.has_all(["owner","reset_epoch","sequence","segments"]) or not batch.segments is Array:return false
 if not batch.owner is int or not batch.reset_epoch is int or not batch.sequence is int:return false
 var token:Dictionary={"owner":int(batch.owner),"reset_epoch":int(batch.reset_epoch),"sequence":int(batch.sequence)}
 # RefCounted ObjectIDs use the signed64 high bit. Negative actual IDs are valid.
 if token.owner in [0,-1] or token.reset_epoch<0 or token.sequence<0 or not is_finite(frame_clock):return false
 if not _ingest_active(enabled):
  _observed_coupled_dropped_root=token
  _observed_coupled_dropped_root_frame=maxf(_observed_coupled_dropped_root_frame,frame_clock)
  return true
 if frame_clock<=_observed_coupled_dropped_root_frame:return _node().position==_model.origin
 if token==_observed_coupled_dropped_root:return _node().position==_model.origin
 if token.owner==_observed_owner and token.reset_epoch<_observed_reset_epoch:return false
 if token.owner==_observed_owner and token.reset_epoch==_observed_reset_epoch:
  if token.sequence==_observed_sequence:return _node().position==_model.origin
  if token.sequence<_observed_sequence:return false
 if _blocks_unlowered_external_motion(enabled):return false
 if not _consume_observed_batch(batch.segments,frame_clock,"shop-root"):return false
 _observed_owner=token.owner;_observed_reset_epoch=token.reset_epoch;_observed_sequence=token.sequence
 return true

func apply_observed_cooperative(segments:Array,frame_clock:float,enabled:bool=true) -> bool:
 if not arm_coupling_enabled:return super.apply_observed_cooperative(segments,frame_clock,enabled)
 if not _coupled_target_alive():return false
 if not is_finite(frame_clock):return false
 var token:PackedByteArray=var_to_bytes([frame_clock,segments])
 if not _ingest_active(enabled):
  _observed_coupled_dropped_analytic=token
  _observed_coupled_dropped_analytic_frame=maxf(_observed_coupled_dropped_analytic_frame,frame_clock)
  return true
 if frame_clock<=_observed_coupled_dropped_analytic_frame:return _node().position==_model.origin
 if token==_observed_coupled_dropped_analytic:return _node().position==_model.origin
 if frame_clock==_observed_coupled_analytic_frame and token in _observed_coupled_analytic_seen:return _node().position==_model.origin
 if frame_clock==_observed_coupled_analytic_frame and _observed_coupled_analytic_seen.size()>=32:return false
 if _blocks_unlowered_external_motion(enabled):return false
 if not _consume_observed_batch(segments,frame_clock,"cooperative-analytic-horizontal"):return false
 if frame_clock!=_observed_coupled_analytic_frame:_observed_coupled_analytic_seen=[]
 _observed_coupled_analytic_frame=frame_clock;_observed_coupled_analytic_seen.append(token)
 _observed_coupled_analytic_token=token
 return true

func apply_player_pose(state:String,distance_px:float,right:bool,enabled:bool=true,clock:float=NAN,stop_age:float=0.0) -> bool:
 if not arm_coupling_enabled:return super.apply_player_pose(state,distance_px,right,enabled,clock,stop_age)
 if not _coupled_target_alive():return false
 # Compatibility idle observations are not an authority for more elapsed time.
 if not _ingest_active(enabled):return true
 if _blocks_unlowered_external_motion(enabled) or not _coupled_seeded:return false
 if state not in ["idle","stop"] or _node().position!=_model.origin or distance_px!=_rig_distance:return false
 if _coupled_body_stamp!=_body_stamp():return false
 if not _rig_active:
  # Dialogue temporarily displays its registered raster. Restore the SAME
  # accepted rig without the inherited idle/model-update reactivation path.
  # No root, contact, model, provider, body stamp or accepted cursor changes.
  var sprite:Sprite2D=_node()
  _rig_active=true;_active=true;_pose=state;_player_state=state
  _facing_right=_model.facing_right;_frame_index=-1;_walk_phase=-1
  _walk_phase_fraction=_model.step_fraction;_stance_shift=0.0;_frame=_neutral
  sprite.texture=null;sprite.material=_original.get("material")
  sprite.scale=Vector2.ONE;sprite.rotation=0.0;sprite.skew=0.0
  sprite.offset=Vector2.ZERO;sprite.flip_h=false;sprite.flip_v=false
  _rig.visible=true
  sprite.set_meta("pose",_pose);sprite.set_meta("motion_frame",-1);sprite.set_meta("motion_active",true)
  sprite.set_meta("motion_facing_right",_facing_right);sprite.set_meta("motion_support_shift",0.0)
  sprite.set_meta("art_id",RIG_MANIFEST);sprite.set_meta("motion_diagnostics",_issues.duplicate())
 _render_rig();return true

func advance_visual(clock:float,enabled:bool=true,reduced:bool=false) -> bool:
 if not arm_coupling_enabled:return super.advance_visual(clock,enabled,reduced)
 if not _coupled_target_alive():return false
 if not is_finite(clock):return false
 set_visual_context(clock,enabled,reduced)
 if not _coupled_seeded:return false
 if _pose_focus_active and _node().is_visible_in_tree():_render_rig()
 return true

func _commit_slice(token:Dictionary,elapsed:float,draw_elapsed:float) -> void:
 super._commit_slice(token,elapsed,draw_elapsed)
 if arm_coupling_enabled and not _coupled_commit_failed:_observed_coupled_owner_frame=float(token.clock)

func initialize_coupled_root(root_snapshot:Dictionary,frame_clock:float) -> bool:
 if arm_coupling_enabled and not _coupled_target_alive():return false
 # One explicit initial snapshot, before any contacts exist. No elapsed sample.
 if not arm_coupling_enabled or _coupled_seeded or _model==null or _model.initialized:return false
 if not _ingest_active(true) or not is_finite(frame_clock) or not _valid_root_row(root_snapshot):return false
 if _node().position!=root_snapshot.position:return false
 if _node().has_meta("motion_facing_right"):
  var actor_facing:Variant=_node().get_meta("motion_facing_right")
  if not actor_facing is bool or actor_facing!=root_snapshot.facing_right:return false
 var saved:Dictionary=_coupled_checkpoint()
 _model.reset(root_snapshot.position,bool(root_snapshot.facing_right),_observed_clock,float(root_snapshot.distance))
 _rig_active=true;_active=true;_rig_distance=float(root_snapshot.distance);_rig_stop_age=float(root_snapshot.stop_age)
 _player_state=str(root_snapshot.state);_facing_right=bool(root_snapshot.facing_right);_pose="idle"
 if not _publish_observed_arm(root_snapshot,0.0,frame_clock,"root-owner-initial",true):
  _coupled_restore(saved);return false
 _observed_last_render_clock=frame_clock
 var sprite:Sprite2D=_node()
 sprite.texture=null;sprite.material=_original.get("material")
 sprite.scale=Vector2.ONE;sprite.rotation=0.0;sprite.skew=0.0;sprite.offset=Vector2.ZERO;sprite.flip_h=false;sprite.flip_v=false
 _rig.visible=true;_render_rig()
 return true

func abort_coupled_owner(kind:String,owner:int) -> bool:
 if arm_coupling_enabled and not _coupled_target_alive():return false
 # Explicit teardown/reset only. This endpoint intentionally clears a live
 # presentation without granting lowering time. Ordinary release cannot use it.
 if not arm_coupling_enabled or not _coupled_seeded or not _coupled_owner_input.is_empty():return false
 if kind=="phone":
  if owner==0 or owner!=_phone_owner:return false
 elif kind=="cooperative":
  if owner!=_cooperative_owner or _cooperative_gesture.is_empty():return false
 else:return false
 if not _coupled_arms.has_method("abort_owner"):return false
 if not _coupled_arms.abort_owner(kind,float(_coupled_arms.status().accepted_time)):return false
 # Clear matched authority directly: ordinary end/cancel intentionally refuses
 # or diagnoses unlowered release and therefore is not this explicit endpoint.
 _model.cancel_presentation_turn("explicit_zero_time_teardown")
 if kind=="phone":
  _phone_owner=0;_phone_phase="none";_phone_last_frame=-1.0
 else:
  _cooperative_owner=-1;_cooperative_gesture="";_cooperative_phase="none"
  _cooperative_last_frame=-1.0;_cooperative_cancel_reason="explicit_zero_time_teardown"
 _new_pose_owner("reach")
 _accepted_pose.draw_progress=0.0;_accepted_pose.draw_target=0.0;_accepted_pose.ready_blend=0.0
 _accepted_pose._ready_from=0.0;_accepted_pose._ready_target=0.0;_accepted_pose._ready_age=0.0
 _accepted_pose.tap_state="complete";_accepted_pose.tap_blend=0.0;_accepted_pose.tap_age=0.0
 _accepted_pose._tap_withdraw_from=0.0;_accepted_pose._tap_withdraw_age=0.0;_accepted_pose._tap_fresh_after_withdraw=false
 _bridge_explicit_completion=false;_tablet_weight=0.0;_tablet_target=0.0
 _pose="idle";_player_state="idle";_coupled_status="explicit_zero_time_teardown"
 _render_rig()
 return true

func coupled_renderer_snapshot() -> Dictionary:
 var result:Dictionary=super.coupled_renderer_snapshot()
 result.accepted_cursor_policy="sum of admitted owner durations and actual observed segment dt; distinct from frozen model pose_time"
 result.observed_provenance=_observed_coupled_provenance.duplicate(true)
 result.stationary_release={"last_frame":_observed_coupled_release_frame,"consumed_duration":_observed_coupled_release_consumed}
 result.world_contract=2
 return result

func reset_cooperative_completion(right:bool,owner:int) -> void:
 if arm_coupling_enabled and not _coupled_target_alive():return
 super.reset_cooperative_completion(right,owner)
 if not arm_coupling_enabled or not _coupled_seeded:return
 # The inherited explicit reset already recreated its provider. Preserve every
 # field and the same nested walk model while promoting that authorized seed.
 var promoted=AbortProvider.new()
 for key in _copy_script_state(_coupled_arms):promoted.set(key,_coupled_arms.get(key))
 _coupled_arms=promoted

func advance_coupled_owner(kind:String,owner:int,elapsed:float,frame_clock:float,accepted_time:float,root_ending_velocity:float=0.0,slice_id:int=0) -> bool:
 if arm_coupling_enabled and not _coupled_target_alive():return false
 if arm_coupling_enabled and frame_clock==_observed_coupled_release_frame:return false
 return super.advance_coupled_owner(kind,owner,elapsed,frame_clock,accepted_time,root_ending_velocity,slice_id)

func advance_coupled_stationary_release(root_snapshot:Dictionary,elapsed:float,frame_clock:float) -> bool:
 if arm_coupling_enabled and not _coupled_target_alive():return false
 # Finite explicit return authority when a real inactive RootOwner emits no
 # segments. Its authoritative snapshot is read only; input is never enabled.
 if not arm_coupling_enabled or not _coupled_seeded or not _valid_root_row(root_snapshot):return false
 if not is_finite(elapsed) or elapsed<=0.0 or elapsed>0.25 or not is_finite(frame_clock):return false
 if not _pose_available():_observed_coupled_release_dropped_frame=maxf(_observed_coupled_release_dropped_frame,frame_clock);return false
 if _bridge_has_owner() or _accepted_pose.draw_progress!=0.0:return false
 if float(root_snapshot.velocity)!=0.0 or root_snapshot.position!=_model.origin or root_snapshot.position!=_node().position:return false
 if float(root_snapshot.distance)!=_rig_distance or bool(root_snapshot.facing_right)!=_model.facing_right:return false
 var token:PackedByteArray=var_to_bytes([root_snapshot,elapsed,frame_clock])
 if token==_observed_coupled_release_token:return true
 if frame_clock<=maxf(_observed_coupled_release_dropped_frame,maxf(_observed_coupled_owner_frame,maxf(_observed_coupled_root_frame,_observed_coupled_release_frame))):return false
 var status:Dictionary=_coupled_arms.status()
 if status.mode=="walk":return true # Terminal no-op, not a perpetual idle clock.
 if status.mode!="release" or not _observed_coupled_input.is_empty() or not _coupled_owner_input.is_empty():return false
 if _coupled_body_stamp!=_body_stamp():return false
 var saved:Dictionary=_coupled_checkpoint()
 var original_cursor:float=float(status.accepted_time)
 var target:float=minf(original_cursor+elapsed,float(status.started)+float(status.duration))
 var cursor:float=original_cursor
 while cursor<target:
  var next:float=minf(cursor+COUPLED_MAX_STEP,target)
  if next<=cursor or not _coupled_arms.advance(_model.snapshot(),float(root_snapshot.velocity),next):
   _coupled_restore(saved);return false
  cursor=next
 _observed_coupled_release_token=token;_observed_coupled_release_frame=frame_clock
 _observed_coupled_release_consumed=cursor-original_cursor
 _coupled_body_stamp=_body_stamp();_coupled_status="accepted_finite_stationary_release"
 _coupled_velocity_source="explicit_stationary_release_root_snapshot.velocity"
 _observed_coupled_provenance={"source":"explicit-stationary-release-root-snapshot","source_frame_clock":frame_clock,
  "root_snapshot":root_snapshot.duplicate(true),"accepted_presentation_cursor_before":original_cursor,
  "accepted_presentation_cursor_after":cursor,"consumed_duration":cursor-original_cursor,
  "model_pose_clock":_model.pose_time,"model_observed_clock":_observed_clock}
 _render_rig()
 return true

func coupled_finish_readiness(kind:String,owner:int) -> Dictionary:
 # Pure query. A lowered prop does not imply that a mid-stride body has landed.
 var result:Dictionary={"valid":false,"ready":false,"reason":"invalid_owner","draw_progress":_accepted_pose.draw_progress,
  "body_settled":false,"needs_body_settle":false}
 if not arm_coupling_enabled or not _coupled_seeded or _model==null or not _model.initialized:return result
 if kind=="phone":
  if owner==0 or owner!=_phone_owner:return result
  if _phone_phase=="failed":result.reason="invalid_failed_phone";return result
 elif kind=="cooperative":
  if owner!=_cooperative_owner or _cooperative_gesture.is_empty():return result
  if _cooperative_phase=="failed":result.reason="invalid_failed_cooperative";return result
 else:return result
 if not is_instance_valid(_node()) or _node().position!=_model.origin:
  result.reason="invalid_unobserved_root";return result
 if kind=="cooperative" and _node().position!=_cooperative_root:
  result.reason="invalid_cooperative_root";return result
 var status:Dictionary=_coupled_arms.status()
 if status.owner!=kind or status.mode not in ["acquire","neutral"]:
  result.reason="invalid_provider_authority";return result
 var landed:bool=_model.settled and not _model.settling and not _model.travelling and _model.feet.near.planted and _model.feet.far.planted
 result.valid=true;result.body_settled=landed;result.needs_body_settle=not landed
 if not _pose_available() or (kind=="cooperative" and not _owner_enabled):
  result.reason="pending_active_presentation";return result
 if not landed:result.reason="pending_body_settle";return result
 if _accepted_pose.draw_progress!=0.0:result.reason="pending_tablet_lower";return result
 result.ready=true;result.reason="ready"
 return result

func finish_coupled_owner(kind:String,owner:int) -> bool:
 if not arm_coupling_enabled:return super.finish_coupled_owner(kind,owner)
 var readiness:Dictionary=coupled_finish_readiness(kind,owner)
 if not readiness.valid or not readiness.ready:return false
 return super.finish_coupled_owner(kind,owner)

func world_consumer_contract_version() -> int:
 # Source03 passed all six isolated gates. This advertises bounded integration
 # capability only; the default-OFF World/native/visual release is not granted.
 return 2

func _coupled_target_alive() -> bool:
 # A surviving RefCounted motion can outlive its weak actor and child rig.
 return is_instance_valid(_node()) and is_instance_valid(_rig)

func set_visual_context(clock:float,enabled:bool=true,reduced:bool=false) -> void:
 if arm_coupling_enabled and not _coupled_target_alive():return
 super.set_visual_context(clock,enabled,reduced)

func end_review_phone(owner:int) -> void:
 if arm_coupling_enabled and not _coupled_target_alive():return
 super.end_review_phone(owner)

func begin_review_phone(owner:int) -> bool:
 if arm_coupling_enabled and not _coupled_target_alive():return false
 return super.begin_review_phone(owner)

func apply_cooperative_gesture(pose_id:String,right:bool,owner:int) -> bool:
 if arm_coupling_enabled and not _coupled_target_alive():return false
 return super.apply_cooperative_gesture(pose_id,right,owner)

func debug_snapshot() -> Dictionary:
 if not arm_coupling_enabled:return super.debug_snapshot()
 # The canonical anatomy profile deliberately has no legacy head_reference.
 # Report actual model/owner/node properties without that incompatible chain.
 var alive:bool=_coupled_target_alive()
 var initialized:bool=_model!=null and _model.initialized
 var body:Dictionary=_model.snapshot() if initialized else {}
 var result:Dictionary={"appearance_id":appearance_id,"available":alive and _rig_ready,
  "active":alive and _active and _rig_active,"pose":_pose,"player_state":_player_state,
  "rigid_active":alive and _rig_active,"rig_ready":_rig_ready,"model_initialized":initialized,
  "facing_right":_model.facing_right if initialized else _facing_right,
  "facing_source":"actual_queued_model" if initialized else "configured_actor_before_initialization",
  "requested_root_facing_right":_facing_right,"diagnostics":_issues.duplicate(),
  "rig":body,"body_model":"UpperResponseV2","visual_turn_queue":body.get("turn_queue",{}),
  "recovery_profile":RECOVERY_PROFILE,"exact_canonical_recovery":false,
  "world_consumer_contract":world_consumer_contract_version(),"visual_acceptance":"candidate; actual World/native acceptance pending",
  "support_points_world":_support_points.duplicate(),"head_live":false,
  "observed_bridge":{"pose_clock":_observed_clock,"render_clock":_observed_last_render_clock,
   "batches":_observed_batches,"samples":_observed_samples,"duplicate_skips":_observed_duplicates,
   "unsupported_paths":_observed_unsupported,"sequence":_observed_sequence,"owner":_observed_owner,"reset_epoch":_observed_reset_epoch},
  "cooperative_gesture":{"owner":_cooperative_owner,"gesture":_cooperative_gesture,"phase":_cooperative_phase,
   "elapsed":_cooperative_elapsed,"completed_seconds":_cooperative_completed,"last_render_clock":_cooperative_last_frame,
   "root":_cooperative_root,"explicit_completion_resets":_cooperative_resets,"last_cancel_reason":_cooperative_cancel_reason},
  "phone":{"owner":_phone_owner,"phase":_phone_phase,"elapsed":_phone_elapsed,"last_frame":_phone_last_frame},
  "tablet_rig":{"ready":_tablet_ready,"weight":_accepted_pose.draw_progress,"target":_accepted_pose.draw_target,
   "gesture":_accepted_pose.gesture,"joints":_pose_result.get("joints",{}).duplicate(true),"body_texture_switch":false},
  "blink_ready":false,"blink_status":"canonical head views; blink not wired"}
 if initialized:
  result.walk_phase_fraction=_model.step_fraction;result.walk_cycle_distance=_model.half_step()*2.0
  result.distance_rebases=_model.distance_rebases;result.hip_point=_model.hip
 if alive:
  var actor:Sprite2D=_node()
  result.foot_point=actor.position;result.rig_node_count=_rig.get_child_count()
  if _parts.has("head") and is_instance_valid(_parts.head):
   var head:Sprite2D=_parts.head
   result.head_live=true;result.head_draw_transform=head.transform
   result.head_texture=head.texture.resource_path if head.texture!=null else ""
   result.head_texture_size=head.texture.get_size() if head.texture!=null else Vector2.ZERO
   result.head_view=str(_pose_result.get("placements",{}).get("head",{}).get("texture_key",""))
   # A fixture ImageTexture has no resource path; expose its actual bank key,
   # explicitly labeled instead of inventing a legacy registration filename.
   result.head_reference=result.head_texture if not result.head_texture.is_empty() else result.head_view
   result.head_reference_kind="texture_resource_path" if not result.head_texture.is_empty() else "bridge_texture_key"
 return result
