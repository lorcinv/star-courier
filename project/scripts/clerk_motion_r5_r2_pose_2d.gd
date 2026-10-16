extends "res://scripts/clerk_motion_r5_pose_2d.gd"
## R5-r2 source candidate: on an observed turn, a genuinely existing second
## ground contact may retain ownership while the incompatible foot lifts.
## The original R5-r1 implementation and exact failed runs remain unchanged.
func _r5_try_contact_turn() -> bool:
 if _a2_before.size()!=2 or not _a2_before.far.planted or not _a2_before.near.planted:return super._r5_try_contact_turn()
 var center:Vector2=origin+_a2_before_hip_local
 var ball:Dictionary={"center":center,"bounds":Vector2(0.0,2.0*_s())}
 var rings_by_side:Dictionary={}
 for side in SIDES:
  rings_by_side[side]={"center":_a2_before[side].position-_a2_sole_offset(side)-_a2_socket(side),"bounds":_a2_bounds(side)}
 var both:Array[Dictionary]=[rings_by_side.far,rings_by_side.near,ball]
 if _a2_nearest_in_rings(center,both).is_finite():return false
 _r5_turn_outcome="no_feasible_dual_contact_lift"
 var flight:float=_a2_flight_speed_limit()*_s()*_candidate_dt
 var conservative:float=maxf(0.0,flight-0.0001*_s())
 var weight:float=move_toward(_candidate_walk_weight,clampf(_candidate_speed/155.0,0.0,1.0),_candidate_dt*HIP_BLEND_SPEED)
 var wanted:Vector2=origin+_v(config.hip)*_s()+Vector2(0,lerpf(_motion_rest_drop_native(),_motion_walk_drop_native(),weight)*_s())
 wanted=center.move_toward(wanted,A2_HIP_RECOVERY_NATIVE*_s()*_candidate_dt)
 var best:Dictionary={}
 for keep in SIDES:
  var release:String=_other(keep);var released:Dictionary=rings_by_side[release]
  var expanded:Dictionary={"center":released.center,"bounds":Vector2(maxf(0.0,released.bounds.x-conservative),released.bounds.y+conservative)}
  var rings:Array[Dictionary]=[rings_by_side[keep],expanded,ball]
  var candidate:Vector2=_a2_nearest_in_rings(wanted,rings)
  if not candidate.is_finite():continue
  var old_hip:Vector2=hip;hip=candidate
  var foot:Vector2=_a2_project_flight(release,_a2_before[release].position);hip=old_hip
  if foot.distance_to(_a2_before[release].position)>flight+0.00001:continue
  var score:float=candidate.distance_squared_to(wanted)
  if best.is_empty() or score<float(best.score):best={"keep":keep,"release":release,"hip":candidate,"foot":foot,"score":score}
 if best.is_empty():return false
 hip=best.hip;_candidate_walk_weight=weight
 var keep:String=best.keep;var release:String=best.release
 for side in SIDES:feet[side]=_a2_before[side].duplicate(true)
 feet[release].position=best.foot;feet[release].planted=false
 _a2_events.append({"kind":"lift","side":release,"contact_id":feet[release].landing_id,"at":_a2_before[release].position,
  "clock":pose_time,"reason":"turn_keep_existing_ground_contact","retained_side":keep,"retained_contact_id":feet[keep].landing_id})
 support=keep;swing=release
 _a2_flight_step=feet[release].position.distance_to(_a2_before[release].position)/_s()
 _a2_constraint_correction=_a2_flight_step
 _swing_from=feet[release].position;_swing_landed=false;_step_start=origin;step_distance=0.0;step_fraction=0.0
 _step_direction=Vector2(_sign(),0.0);_a2_frame_direction=_step_direction
 _a2_current_step=_a2_step_budget(origin,_step_direction)
 _swing_target=_a2_target_from(origin,_a2_current_step)
 _a2_events.append({"kind":"begin_support_segment","support":keep,"contact_id":feet[keep].landing_id,
  "length_native":_a2_current_step/_s(),"at":origin,"reason":"existing_ground_contact_turn"})
 _candidate_reach_feasible=true;_a2_transfer_feasible=true
 _r5_turn_outcome="retain_existing_contact_then_lift"
 return true
