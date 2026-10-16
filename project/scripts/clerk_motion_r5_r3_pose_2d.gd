extends "res://scripts/clerk_motion_r5_r2_pose_2d.gd"
## Bounded presentation-facing queue. Owner position, distance and requested
## facing are observed unchanged. A visual mirror waits for real support.
const TURN_LAG_LIMIT:float=0.05
var _turn_requested_right:bool=true
var _turn_pending:bool=false
var _turn_age:float=0.0
var _turn_max_lag:float=0.0
var _turn_last_lag:float=0.0
var _turn_status:String="none"
var _turn_solution:Dictionary={}
var _turn_preparing:bool=false
var _turn_preparation_feasible:bool=true

func reset(at:Vector2,right:bool,clock:float=0.0,distance:float=0.0) -> void:
 _turn_requested_right=right;_turn_pending=false;_turn_age=0.0
 _turn_max_lag=0.0;_turn_last_lag=0.0;_turn_status="reset"
 _turn_solution={};_turn_preparing=false;_turn_preparation_feasible=true
 super.reset(at,right,clock,distance)

func cancel_presentation_turn(reason:String) -> void:
 _turn_requested_right=facing_right;_turn_pending=false;_turn_age=0.0
 _turn_solution={};_turn_preparing=false;_turn_status=reason

func update(next_state:String,distance:float,at:Vector2,right:bool,clock:float,stop_age:float=0.0,enabled:bool=true,reduced_motion:bool=false) -> bool:
 if not enabled:return super.update(next_state,distance,at,right,clock,stop_age,enabled,reduced_motion)
 var active_slice:float=clampf(clock-_last_clock,0.0,0.1) if initialized else 0.0
 var dt:float=active_slice if not _freeze_clock else 0.0
 _turn_requested_right=right;_turn_solution={};_turn_preparing=false;_turn_preparation_feasible=true
 if initialized and right!=facing_right:
  if _turn_pending:_turn_age+=active_slice
  else:_turn_pending=true;_turn_age=0.0;_turn_status="preparing"
  _turn_solution=_plan_mirrored_contacts(at,right,dt)
  if _turn_solution.is_empty():_turn_preparing=true
  else:
   _turn_last_lag=_turn_age;_turn_max_lag=maxf(_turn_max_lag,_turn_age)
   _turn_status="consumed";_turn_pending=false
  if _turn_age>TURN_LAG_LIMIT:_turn_status="lag_limit_failed"
 elif _turn_pending:cancel_presentation_turn("cancelled_by_second_direction")
 return super.update(next_state,distance,at,facing_right if _turn_preparing else right,clock,stop_age,enabled,reduced_motion)

func _turn_offset(side:String,right:bool) -> Vector2:
 return (_v(config.legs[side].hip_offset)+_v(config.legs[side].sole_from_ankle))*Vector2(1.0 if right else -1.0,1.0)*_s()

func _plan_mirrored_contacts(at:Vector2,right:bool,dt:float) -> Dictionary:
 if dt<=0.0:return {}
 var center:Vector2=hip+at-origin
 var speed:float=at.distance_to(origin)/dt
 var flight:float=maxf(A2_FLIGHT_SPEED_NATIVE,speed/_s()*A2_FLIGHT_TO_ROOT_SPEED)*_s()*dt
 var margin:float=0.0001*_s();var safe:float=maxf(0.0,flight-margin)
 var ball:Dictionary={"center":center,"bounds":Vector2(0.0,2.0*_s()-margin)}
 var weight:float=move_toward(_candidate_walk_weight,clampf(speed/155.0,0.0,1.0),dt*HIP_BLEND_SPEED)
 var wanted:Vector2=at+_v(config.hip)*_s()+Vector2(0,lerpf(_motion_rest_drop_native(),_motion_walk_drop_native(),weight)*_s())
 wanted=center.move_toward(wanted,A2_HIP_RECOVERY_NATIVE*_s()*dt)
 var fixed:Dictionary={};var expanded:Dictionary={};var planted:Array[String]=[]
 for side in SIDES:
  var b:Vector2=_a2_bounds(side);var c:Vector2=feet[side].position-_turn_offset(side,right)
  fixed[side]={"center":c,"bounds":b}
  expanded[side]={"center":c,"bounds":Vector2(maxf(0.0,b.x-safe),b.y+safe)}
  if feet[side].planted:planted.append(side)
 var choices:Array[Dictionary]=[]
 if planted.size()==2:
  var rings:Array[Dictionary]=[fixed.far,fixed.near,ball]
  var point:Vector2=_a2_nearest_in_rings(wanted,rings)
  if point.is_finite():choices.append({"hip":point,"keep":"both","weight":weight,"score":point.distance_squared_to(wanted),"feet":feet.duplicate(true)})
 for keep in planted:
  var moving:String=_other(keep);var rings:Array[Dictionary]=[fixed[keep],expanded[moving],ball]
  var point:Vector2=_a2_nearest_in_rings(wanted,rings)
  if not point.is_finite():continue
  var foot_rings:Array[Dictionary]=[
   {"center":point+_turn_offset(moving,right),"bounds":_a2_bounds(moving)},
   {"center":feet[moving].position,"bounds":Vector2(0.0,safe)}]
  var foot:Vector2=_a2_nearest_in_rings(feet[moving].position,foot_rings)
  if not foot.is_finite():continue
  var declared:Dictionary=feet.duplicate(true);declared[moving].position=foot;declared[moving].planted=false
  choices.append({"hip":point,"keep":keep,"weight":weight,"score":point.distance_squared_to(wanted)+0.000001,"feet":declared})
 if planted.size()==1:
  var old:String=planted[0];var incoming:String=_other(old);var from:Vector2=feet[incoming].position
  var dy:float=at.y-from.y
  if absf(dy)<=safe:
   var span:float=sqrt(maxf(0.0,safe*safe-dy*dy))
   for x in [from.x,from.x-span,from.x+span]:
    var ground:Vector2=Vector2(x,at.y)
    var new_ring:Dictionary={"center":ground-_turn_offset(incoming,right),"bounds":_a2_bounds(incoming)}
    var rings:Array[Dictionary]=[new_ring,expanded[old],ball]
    var point:Vector2=_a2_nearest_in_rings(wanted,rings)
    if not point.is_finite():continue
    var foot_rings:Array[Dictionary]=[
     {"center":point+_turn_offset(old,right),"bounds":_a2_bounds(old)},
     {"center":feet[old].position,"bounds":Vector2(0.0,safe)}]
    var released:Vector2=_a2_nearest_in_rings(feet[old].position,foot_rings)
    if not released.is_finite():continue
    var declared:Dictionary=feet.duplicate(true)
    declared[incoming].position=ground;declared[incoming].planted=true
    declared[old].position=released;declared[old].planted=false
    choices.append({"hip":point,"keep":incoming,"weight":weight,"score":point.distance_squared_to(wanted)+0.000002,"feet":declared})
 if choices.is_empty():return {}
 var best:Dictionary=choices[0]
 for option in choices:
  if float(option.score)<float(best.score):best=option
 return best

func _r5_try_contact_turn() -> bool:
 if _turn_solution.is_empty():return false
 hip=_turn_solution.hip;_candidate_walk_weight=_turn_solution.weight
 var incoming:Dictionary=_turn_solution.feet
 # A new landing precedes releasing the old contact. Existing double support
 # requires only a lift; it never receives an invented replacement ID.
 for side in SIDES:
  feet[side]=incoming[side].duplicate(true)
  if feet[side].planted and not _a2_before[side].planted:
   _a2_contact_serial+=1;feet[side].landing_id=_a2_contact_serial
   _a2_events.append({"kind":"land","side":side,"contact_id":_a2_contact_serial,"at":feet[side].position,"clock":pose_time,"observed_floor_y":origin.y,"reason":"queued_visual_turn_real_landing"})
 for side in SIDES:
  if _a2_before[side].planted and not feet[side].planted:
   _a2_events.append({"kind":"lift","side":side,"contact_id":feet[side].landing_id,"at":_a2_before[side].position,"clock":pose_time,"reason":"queued_visual_turn_retained_support"})
  _a2_flight_step=maxf(_a2_flight_step,feet[side].position.distance_to(_a2_before[side].position)/_s())
 support=_choose_support();swing=_other(support)
 _swing_from=feet[swing].position;_swing_landed=false;_step_start=origin;step_distance=0.0;step_fraction=0.0
 _step_direction=Vector2(_sign(),0.0);_a2_frame_direction=_step_direction
 _a2_current_step=_a2_step_budget(origin,_step_direction);_swing_target=_a2_target_from(origin,_a2_current_step)
 _candidate_reach_feasible=true;_a2_transfer_feasible=true;_r5_turn_outcome="strict_mirrored_contacts"
 if not travelling and state not in TRAVEL:_begin_settle(0.0)
 return true

func _solve() -> void:
 if _turn_preparing and not _a2_before.is_empty():
  if _prepare_actual_contact():_r5_solve_declared_joints();return
  _turn_preparation_feasible=false;_turn_status="preparation_intersection_empty"
 super._solve()

func _prepare_actual_contact() -> bool:
 if _candidate_dt<=0.0:
  # First resumed sample clears inherited freeze bookkeeping. No foot can
  # spend a zero flight budget; retain the actual previous world pose.
  feet=_a2_before.duplicate(true)
  _candidate_reach_feasible=true;_a2_transfer_feasible=true
  return true
 var planted:Array[String]=[]
 for side in SIDES:
  if _a2_before[side].planted:planted.append(side)
 if planted.is_empty():return false
 var keep:String=planted[0]
 if planted.size()==2:
  # Prefer the actual support requiring less mirrored reach correction.
  var smallest:float=INF
  for side in planted:
   var center:Vector2=_a2_before[side].position-_turn_offset(side,_turn_requested_right)
   var gap:float=maxf(0.0,(origin+_a2_before_hip_local).distance_to(center)-_a2_bounds(side).y)
   if gap<smallest:smallest=gap;keep=side
 var moving:String=_other(keep)
 var flight:float=_a2_flight_speed_limit()*_s()*_candidate_dt
 var safe:float=maxf(0.0,flight-0.0001*_s())
 var fixed:Dictionary={"center":_a2_before[keep].position-_turn_offset(keep,facing_right),"bounds":_a2_bounds(keep)}
 var bounds:Vector2=_a2_bounds(moving)
 var airborne:Dictionary={"center":_a2_before[moving].position-_turn_offset(moving,facing_right),"bounds":Vector2(maxf(0.0,bounds.x-safe),bounds.y+safe)}
 var ball:Dictionary={"center":origin+_a2_before_hip_local,"bounds":Vector2(0.0,2.0*_s()-0.0001*_s())}
 var rings:Array[Dictionary]=[fixed,airborne,ball]
 var target:Vector2=_turn_preparation_hip_target(keep)
 var point:Vector2=_a2_nearest_in_rings(target,rings)
 if not point.is_finite():return false
 hip=point
 var wanted:Vector2=_turn_preparation_wanted(moving)
 if not wanted.is_finite():return false
 var foot_rings:Array[Dictionary]=[
  {"center":hip+_turn_offset(moving,facing_right),"bounds":bounds},
  {"center":_a2_before[moving].position,"bounds":Vector2(0.0,safe)}]
 var actual:Vector2=_a2_nearest_in_rings(wanted,foot_rings)
 if not actual.is_finite() or actual.y>origin.y+0.001:return false
 for side in SIDES:feet[side]=_a2_before[side].duplicate(true)
 feet[moving].position=actual;feet[moving].planted=false
 if not _a2_before[moving].planted and actual.distance_to(wanted)<=0.001 and absf(actual.y-origin.y)<=0.001:
  feet[moving].planted=true;_a2_contact_serial+=1;feet[moving].landing_id=_a2_contact_serial
  _a2_events.append({"kind":"land","side":moving,"contact_id":_a2_contact_serial,"at":actual,"clock":pose_time,"observed_floor_y":origin.y,"reason":"visual_turn_preparation"})
 elif _a2_before[moving].planted:
  _a2_events.append({"kind":"lift","side":moving,"contact_id":feet[moving].landing_id,"at":_a2_before[moving].position,"clock":pose_time,"reason":"visual_turn_preparation_retains_support","retained_contact_id":feet[keep].landing_id})
 support=keep;swing=moving;_swing_from=actual;_swing_landed=feet[moving].planted
 _a2_flight_step=actual.distance_to(_a2_before[moving].position)/_s()
 _candidate_reach_feasible=true;_a2_transfer_feasible=true;settled=false
 return true

func _advance_settle() -> void:
 if not settling:return
 if _r5_stage>=_r5_order.size():return
 var intended:String=_r5_order[_r5_stage]
 if _r5_landing_requested and feet[intended].planted and feet[intended].position.distance_to(_r5_targets[intended])<=R5_REST_TARGET_TOLERANCE_NATIVE*_s():
  _r5_stage+=1;_r5_enter_rest_stage()
  if not settling:return
  intended=_r5_order[_r5_stage]
 var other:String=_other(intended)
 if not feet[other].planted:
  # A shared travel recovery can change swing ownership. Finish its actual
  # other-foot landing before lifting the explicitly scheduled rest foot.
  support=intended;swing=other
  feet[other].position=Vector2(feet[other].position.x,origin.y);feet[other].planted=true
  return
 support=other;swing=intended
 if feet[intended].planted and feet[intended].position.distance_to(_r5_targets[intended])>R5_REST_TARGET_TOLERANCE_NATIVE*_s():
  feet[intended].planted=false;_r5_landing_requested=false
  return
 var u:float=clampf((pose_time-_r5_stage_clock)/R5_REST_STEP_SECONDS,0.0,1.0)
 feet[intended].position=_r5_stage_from.lerp(_r5_targets[intended],u*u*(3.0-2.0*u))
 feet[intended].position.y-=sin(PI*u)*4.0*_s()
 feet[intended].planted=u>=1.0
 if u>=1.0:feet[intended].position=_r5_targets[intended];_r5_landing_requested=true

func snapshot() -> Dictionary:
 var result:Dictionary=super.snapshot()
 result.turn_queue={"requested_facing_right":_turn_requested_right,"visual_facing_right":facing_right,"pending":_turn_pending,"active_elapsed_seconds":_turn_age,"last_lag_seconds":_turn_last_lag,"max_lag_seconds":_turn_max_lag,"lag_limit_seconds":TURN_LAG_LIMIT,"status":_turn_status,"preparation_feasible":_turn_preparation_feasible}
 return result

# Calibration-specific preparation goal hook; historical default preserved.
func _turn_preparation_wanted(moving:String) -> Vector2:
 var wanted:Vector2=Vector2(_a2_before[moving].position.x,origin.y)
 if _a2_before[moving].planted:return _a2_before[moving].position+Vector2(0,-2.0*_s())
 return _a2_ground_target(moving,wanted)

func _turn_preparation_hip_target(_keep:String) -> Vector2:
 return origin+_a2_before_hip_local
