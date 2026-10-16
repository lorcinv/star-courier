extends "res://scripts/actor_motion_2d.gd"
## Explicit recovered whole-raster presentation. Root position and displacement
## remain caller-owned. This does not reconstruct the missing human rigid rig.
const RECOVERY_PROFILE:String = "reconstructed_recovery_v1"
const STATES:Array[String] = ["idle", "start", "move", "inertial_stop", "stop"]
const MOVING:Array[String] = ["start", "move", "inertial_stop"]
var _owner_enabled:bool = true
var _owner_reduced:bool = false
var _owner_clock:float = 0.0
var _motion_state:String = "idle"
var _distance_baseline:float = NAN
var _phase_distance:float = 0.0
var _distance_rebases:int = 0

func _preload_motion_assets() -> void:
 _record = _record.duplicate(true)
 for key in ["run", "run_sequence", "run_phase_weights"]:_record[key] = []
 super._preload_motion_assets()

func set_visual_context(clock:float, enabled:bool = true, reduced:bool = false) -> void:
 if not is_finite(clock):return
 _owner_clock = clock;_owner_enabled = enabled;_owner_reduced = reduced
 if not enabled:_distance_baseline = NAN

func apply_npc_pose(state:String, distance:float, right:bool, clock:float, _stop_age:float = 0.0) -> bool:
 var sprite:Sprite2D = _node()
 if state not in STATES or not is_finite(distance) or distance < 0.0 or not is_finite(clock):return false
 if not is_instance_valid(sprite):return false
 if not sprite.is_visible_in_tree() or not _owner_enabled:
  _distance_baseline = distance
  return false
 _owner_clock = clock
 var cycle:float = walk_cycle_distance()
 if not is_finite(cycle) or cycle <= 0.0:return false
 var change:float = 0.0 if not is_finite(_distance_baseline) else distance-_distance_baseline
 if change < -0.00001 or change > cycle*0.75:
  _distance_rebases += 1;change = 0.0
 _distance_baseline = distance
 _motion_state = state
 if state in MOVING:
  _phase_distance = fposmod(_phase_distance + maxf(change,0.0), cycle)
  return super.apply_walk(_phase_distance,right)
 return _apply_neutral(right,state)

func _apply_neutral(right:bool, state:String = "idle") -> bool:
 var frame:Variant = _record.get("gestures", {}).get("neutral")
 if not frame is Dictionary:_issue("recovery_missing_neutral");return false
 return _apply_frame(frame,state,-1,right)

func apply_idle(facing_right:bool = true) -> bool:
 var sprite:Sprite2D = _node()
 if not is_instance_valid(sprite) or not sprite.is_visible_in_tree() or not _owner_enabled:return false
 _distance_baseline = NAN;_motion_state = "idle"
 return _apply_neutral(facing_right)

func apply_walk(distance_px:float,facing_right:bool = true) -> bool:
 return apply_npc_pose("move",distance_px,facing_right,_owner_clock)

func apply_run(distance_px:float,facing_right:bool = true) -> bool:
 return apply_walk(distance_px,facing_right)

func run_cycle_distance() -> float:return walk_cycle_distance()

func apply_gesture(pose_id:String,facing_right:bool = true) -> bool:
 if not _owner_enabled:return false
 _distance_baseline = NAN
 return super.apply_gesture(pose_id,facing_right)

func restore_original() -> void:
 _distance_baseline = NAN
 super.restore_original()

func dispose() -> void:
 _target = null

func debug_snapshot() -> Dictionary:
 var result:Dictionary = super.debug_snapshot()
 result.recovery_profile = RECOVERY_PROFILE;result.exact_canonical_recovery = false
 result.rigid_active = false;result.rig_ready = false;result.motion_state = _motion_state
 result.distance_rebases = _distance_rebases
 result.visual_acceptance = "pending: head_consistency, sparse_gait, neutral_accessory_occlusion"
 return result
