extends "res://scripts/world_view_2d.gd"
## Opt-in adapter over frozen World04. No new actor, model, route or save schema.
signal title_shop_entry_finished(success:bool,reason:String)
const TITLE_ENTRY_START:Vector2=Vector2(600.0,496.0)
const TITLE_ENTRY_TARGET:String="focus_counter"
const TITLE_ENTRY_MAX_SECONDS:float=6.0
const TITLE_SKIP_MAX_SECONDS:float=1.0
var _title_entry_configured:bool=false
var _title_entry_active:bool=false
var _title_entry_phase:String="disabled"
var _title_entry_reason:String=""
var _title_entry_elapsed:float=0.0
var _title_skip_elapsed:float=0.0
var _title_entry_resume_route:bool=false
var _title_entry_signaled:bool=false

func configure_title_shop_entry(initial_position:Vector2=TITLE_ENTRY_START,target_action:String=TITLE_ENTRY_TARGET) -> bool:
 # Host must first validate/load/commit an ordinary empty daytime shop state.
 # Never call for flight, result, active order, dialogue or pending story return.
 if is_inside_tree() or _clerk_motion!=null or _title_entry_configured or _clerk_pose_bootstrap==null:return false
 if initial_position!=TITLE_ENTRY_START or target_action!=TITLE_ENTRY_TARGET:return false
 _title_entry_configured=true;_title_entry_phase="prepared"
 return true

func _initialize_clerk_pose_candidate() -> bool:
 if _title_entry_configured:
  if not _title_shop_context_safe():
   _clerk_pose_setup_error="unsafe_title_initial_context";return false
  # Sole initial placement BEFORE the inherited constructor, model or contacts.
  clerk.position=TITLE_ENTRY_START;clerk.z_index=11
 return super._initialize_clerk_pose_candidate()

func _ready() -> void:
 super._ready()
 if not _title_entry_configured:return
 if not _clerk_pose_setup_error.is_empty() or not _clerk_pose_consumer_enabled:
  _title_entry_phase="blocked";_title_entry_reason="title_initialization_not_ready";return
 _clerk_state="free"
 super.set_shop_input(0.0,false)

func _title_shop_context_safe() -> bool:
 return mode=="hub" and not night and active_id.is_empty() and parcel_state=="empty" and _parcel_phase=="empty" and not _loading_requested and not _dialogue_active and _review_phone_owner==0 and _investigation_owner==0 and _clerk_lower_owner<0 and not _clerk_return_requested

func _title_active_context() -> bool:
 return _focus_active and not _scene_paused and is_visible_in_tree() and is_instance_valid(clerk) and clerk.is_visible_in_tree()

func _title_actual_body_settled() -> bool:
 if _clerk_motion==null:return false
 var rig:Dictionary=_clerk_motion.debug_snapshot().get("rig",{})
 var feet:Dictionary=rig.get("feet",{})
 return bool(rig.get("settled",false)) and not bool(rig.get("settling",true)) and not bool(rig.get("travelling",true)) and bool(feet.get("near",{}).get("planted",false)) and bool(feet.get("far",{}).get("planted",false)) and float(_shop_motion.snapshot().velocity)==0.0

func _request_title_counter_walk() -> bool:
 # Opening presentation owns an empty-handed return to the clerk's workplace,
 # not permission to speak to a customer who has not yet arrived. Retain the
 # same real route and RootOwner without exposing a gameplay counter bypass.
 if not _title_entry_active or not _title_shop_context_safe() or not _title_active_context():return false
 if is_at_shop_counter():return true
 if not _shop_owns_clerk:_adopt_shop_clerk()
 _shop_motion.navigate_to(CLERK_HOME_X-ShopLocomotion2D.COUNTER_MIN_X)
 _shop_navigation=""
 return false

func start_title_shop_entry() -> bool:
 if _title_entry_active:return true
 if not _title_entry_configured or _title_entry_phase!="prepared" or not _clerk_pose_consumer_enabled or not _clerk_pose_setup_error.is_empty():return false
 if not _title_shop_context_safe() or not _title_active_context():return false
 _title_entry_active=true;_title_entry_phase="walking";_title_entry_elapsed=0.0
 _title_entry_resume_route=false
 super.set_shop_input(0.0,true)
 # Route request owns the same existing RootOwner. Its false result normally
 # means navigation is in progress, not failure; no endpoint relocation occurs.
 var at_target:bool=_request_title_counter_walk()
 _shop_navigation="" # Dedicated entry completion, never a contracts-drawer action.
 if at_target:_title_entry_phase="settling"
 elif not _shop_motion.is_navigating():
  _finish_title_entry(false,"entry_route_rejected");return false
 return true

func skip_title_shop_entry() -> bool:
 if not _title_entry_configured or _title_entry_phase in ["complete","blocked","disabled"]:return false
 if _title_entry_phase=="braking":return true
 if not _title_shop_context_safe():return false
 _title_entry_active=true;_title_entry_phase="braking";_title_skip_elapsed=0.0
 _title_entry_resume_route=false
 # Do not clear velocity or snap to the counter. Existing RootOwner step brakes
 # from its actual current velocity and then settles the same physical body.
 _shop_navigation="";_shop_motion.cancel_navigation()
 if _title_active_context():super.set_shop_input(0.0,true)
 if _title_actual_body_settled():_finish_title_entry(true,"skipped_at_settled_root")
 return true

func _finish_title_entry(success:bool,reason:String) -> void:
 if _title_entry_signaled:return
 _title_entry_signaled=true;_title_entry_active=false
 _title_entry_phase="complete" if success else "blocked";_title_entry_reason=reason
 _shop_navigation="";_shop_motion.cancel_navigation()
 if success:
  # This endpoint is reached only after actual zero velocity/double support.
  # Restore the normal fresh-input barrier without moving or rebuilding actor.
  _shop_motion.clear_input();_shop_input_enabled=false
  if clerk.position.distance_to(Vector2(CLERK_HOME_X,SHOP_FLOOR_Y))<=.1:
   _shop_owns_clerk=false;_clerk_state="counter";clerk.z_index=0
  else:_clerk_state="free"
 else:
  # Keep Main quarantined; host must not treat a blocked route as completion.
  super.set_shop_input(0.0,false)
 title_shop_entry_finished.emit(success,reason)

func set_shop_input(axis:float,enabled:bool=true,running:bool=false) -> void:
 if _title_entry_active:
  # Neutral automatic input belongs to this explicit bounded entry authority.
  # No player axis is accepted during title, even if a held key reaches World.
  if _title_active_context():super.set_shop_input(0.0,true)
  else:
   if _title_entry_phase=="walking":_title_entry_resume_route=true
   super.set_shop_input(0.0,false)
  return
 if _title_entry_configured and _title_entry_phase!="complete":
  super.set_shop_input(0.0,false);return
 super.set_shop_input(axis,enabled,running)

func _step_shop_locomotion(delta:float) -> void:
 if not _title_entry_active:super._step_shop_locomotion(delta);return
 # Avoid the gameplay arrival branch that restores a historical full-body pose
 # before its live body has settled. Keep this same rig observed through stop.
 _shop_navigation=""
 super._step_shop_locomotion(delta)
 if _title_entry_phase=="walking" and _shop_motion.arrived():_title_entry_phase="settling"

func _process(delta:float) -> void:
 if not _title_entry_configured:super._process(delta);return
 if _title_entry_phase=="blocked":return
 if not _title_entry_active:super._process(delta);return
 if not _title_shop_context_safe():
  _finish_title_entry(false,"entry_context_changed");return
 if not _title_active_context() or not is_finite(delta) or delta<=0.0:return
 if _title_entry_resume_route and _title_entry_phase=="walking":
  _title_entry_resume_route=false
  super.set_shop_input(0.0,true)
  if is_at_shop_counter():
   _title_entry_phase="settling"
  else:
   _request_title_counter_walk();_shop_navigation=""
   if not _shop_motion.is_navigating() and not _shop_motion.arrived():
    _finish_title_entry(false,"entry_resume_route_rejected");return
 super.set_shop_input(0.0,true)
 # RootOwner itself caps actual admitted frame time to MAX_FRAME_SECONDS.
 var admitted:float=minf(delta,ShopLocomotion2D.MAX_FRAME_SECONDS)
 _title_entry_elapsed+=admitted
 if _title_entry_phase=="braking":_title_skip_elapsed+=admitted
 super._process(delta)
 if _title_entry_phase=="braking" and _title_actual_body_settled():
  _finish_title_entry(true,"skipped_at_settled_root")
 elif _title_entry_phase=="settling" and is_at_shop_counter() and _title_actual_body_settled():
  _finish_title_entry(true,"arrived_and_settled")
 elif _title_entry_phase=="braking" and _title_skip_elapsed>TITLE_SKIP_MAX_SECONDS:
  _finish_title_entry(false,"skip_settle_budget_exceeded")
 elif _title_entry_elapsed>TITLE_ENTRY_MAX_SECONDS:
  _finish_title_entry(false,"entry_route_budget_exceeded")

func title_shop_entry_status() -> Dictionary:
 return {"configured":_title_entry_configured,"active":_title_entry_active,"phase":_title_entry_phase,
  "complete":_title_entry_phase=="complete","blocked":_title_entry_phase=="blocked",
  "reason":_title_entry_reason,"elapsed":_title_entry_elapsed,"skip_elapsed":_title_skip_elapsed,
  "at_counter":is_at_shop_counter() if is_instance_valid(clerk) else false,
  "body_settled":_title_actual_body_settled() if _clerk_pose_consumer_enabled else false,
  "root":clerk.position if is_instance_valid(clerk) else Vector2.ZERO,
  "root_owner_id":_shop_motion.get_instance_id(),"player_input_quarantined":_title_entry_configured and _title_entry_phase!="complete"}
