extends "res://scripts/clerk_motion_r5_base_pose_2d.gd"
## A2 bounded reach correction. Original root owner and source registration are
## unchanged. The inherited gait proposes targets; the actual declared feet
## follow reachable flight paths and make explicit, uniquely numbered contacts.
const A2_CONTACT_MARGIN_NATIVE:float = 0.25
const A2_FLIGHT_SPEED_NATIVE:float = 480.0
const A2_HIP_RECOVERY_NATIVE:float = 48.0
const A2_LANDING_AHEAD_NATIVE:float = 22.0
const A2_SUPPORT_RESERVE_NATIVE:float = 3.0
const A2_FLIGHT_TO_ROOT_SPEED:float = 3.2
var _r5_facing_change:bool=false
var _r5_turn_outcome:String="not_needed"
var _a2_before:Dictionary = {}
var _a2_before_hip_local:Vector2 = Vector2.ZERO
var _a2_contact_serial:int = 0
var _a2_events:Array = []
var _a2_constraint_correction:float = 0.0
var _a2_flight_step:float = 0.0
var _a2_landing_deferred:bool = false
var _a2_current_step:float = 1.0
var _a2_floor_change:bool = false
var _a2_frame_direction:Vector2 = Vector2.RIGHT
var _a2_transfer_feasible:bool = true

func reset(at:Vector2,right:bool,clock:float=0.0,distance:float=0.0) -> void:
 _a2_before={};_a2_events=[]
 super.reset(at,right,clock,distance)
 _a2_current_step=half_step()
 for side in SIDES:
  _a2_contact_serial+=1;feet[side].landing_id=_a2_contact_serial
  _a2_events.append({"kind":"initial_contact","side":side,"contact_id":_a2_contact_serial,"at":feet[side].position})

func update(next_state:String,distance:float,at:Vector2,right:bool,clock:float,stop_age:float=0.0,enabled:bool=true,reduced_motion:bool=false) -> bool:
 if not enabled:return super.update(next_state,distance,at,right,clock,stop_age,enabled,reduced_motion)
 _r5_facing_change=initialized and right!=facing_right
 _r5_turn_outcome="not_needed"
 _a2_before=feet.duplicate(true) if initialized else {}
 _a2_before_hip_local=hip-origin
 _a2_events=[];_a2_constraint_correction=0.0;_a2_flight_step=0.0;_a2_landing_deferred=false
 _a2_transfer_feasible=true
 _a2_floor_change=initialized and absf(at.y-origin.y)>EPS
 return super.update(next_state,distance,at,right,clock,stop_age,enabled,reduced_motion)

func _a2_socket(side:String) -> Vector2:
 return _v(config.legs[side].hip_offset)*Vector2(_sign(),1.0)*_s()

func _a2_sole_offset(side:String) -> Vector2:
 return _v(config.legs[side].sole_from_ankle)*Vector2(_sign(),1.0)*_s()

func _a2_bounds(side:String) -> Vector2:
 var leg:Dictionary=config.legs[side]
 return Vector2(absf(float(leg.thigh_length)-float(leg.shin_length))+A2_CONTACT_MARGIN_NATIVE,
  float(leg.thigh_length)+float(leg.shin_length)-A2_CONTACT_MARGIN_NATIVE)*_s()

func _a2_flight_speed_limit() -> float:
 # Each shoe must cover roughly twice the root travel during its flight half
 # of a stride. A native-only cap makes the unchanged 155 px/s root outrun
 # small-height fixtures. This bound is tied to observed root speed, not to
 # error size or a test result, with finite recovery speed when stopped.
 return maxf(A2_FLIGHT_SPEED_NATIVE,_candidate_speed/_s()*A2_FLIGHT_TO_ROOT_SPEED)

func _a2_annulus_center(side:String) -> Vector2:
 return feet[side].position-_a2_sole_offset(side)-_a2_socket(side)

func _a2_plan_direction(displacement:Vector2) -> Vector2:
 # The owner can brake through zero and accelerate back within one 120 Hz
 # tick. Net displacement may still point the old way while its authorized
 # facing already points the new way. Only FUTURE support planning uses the
 # new facing; the actual root endpoints and consumed displacement stay exact.
 if absf(displacement.y)<=EPS:return Vector2(_sign(),0.0)
 return displacement.normalized()

func _a2_step_budget(at:Vector2,direction:Vector2) -> float:
 # Plan the next support transfer before the currently planted chain reaches
 # its outer boundary. A reverse first step is often much shorter than a
 # steady stride; retaining the full old stride produced the tick-173 witness.
 var drop:float=lerpf(_motion_rest_drop_native(),_motion_walk_drop_native(),_candidate_walk_weight)
 var body:Vector2=at+_v(config.hip)*_s()+Vector2(0,drop*_s())
 var delta:Vector2=body-_a2_annulus_center(support)
 var radius:float=_a2_bounds(support).y
 var projected:float=delta.dot(direction)
 var discriminant:float=projected*projected+radius*radius-delta.length_squared()
 if discriminant<=0.0:return 1.0*_s()
 var until_exit:float=-projected+sqrt(discriminant)
 return clampf(until_exit-A2_SUPPORT_RESERVE_NATIVE*_s(),1.0*_s(),half_step())

func _a2_target_from(at:Vector2,remaining:float) -> Vector2:
 if _a2_floor_change:
  # A lane connector changes the observed floor under the body. Prepare the
  # closest reachable floor contact, rather than continuing a long X swing.
  return Vector2(feet[swing].position.x,at.y)
 var target:Vector2=at+_step_direction*remaining+Vector2(_sign()*A2_LANDING_AHEAD_NATIVE*_s(),0)
 # Land only on a floor height already observed from the owner route.
 target.y=at.y
 return target

func _begin_step(at:Vector2,direction:Vector2) -> void:
 var planned:Vector2=_a2_plan_direction(direction)
 super._begin_step(at,planned)
 _a2_current_step=_a2_step_budget(at,planned)
 _swing_target=_a2_target_from(at,_a2_current_step)
 _a2_events.append({"kind":"begin_support_segment","support":support,"contact_id":feet[support].landing_id,
  "length_native":_a2_current_step/_s(),"at":at})

func _advance_travel(from:Vector2,to:Vector2,actual:float) -> void:
 _upper_distance+=actual
 _a2_frame_direction=_a2_plan_direction(to-from)
 if _a2_floor_change:
  # The route owner supplied one real 120 Hz floor observation. A connector
  # sample must not cycle through nominal support owners before _solve has
  # established a real landing. Keep the actual support and propose only one
  # bounded flight/landing at the latest observed floor; _solve transfers it.
  step_distance+=actual
  step_fraction=clampf(step_distance/maxf(_a2_current_step,EPS),0.0,1.0)
  _step_direction=_a2_frame_direction
  _swing_target=Vector2(feet[swing].position.x,to.y)
  _sample_swing()
  return
 var shortened:float=step_distance+_a2_step_budget(from,_a2_frame_direction)
 if shortened<_a2_current_step:
  _a2_events.append({"kind":"shorten_support_segment","support":support,"contact_id":feet[support].landing_id,
   "old_length_native":_a2_current_step/_s(),"new_length_native":shortened/_s(),"direction":_a2_frame_direction})
  _a2_current_step=shortened
 var consumed:float=0.0
 for boundary in 6:
  var take:float=minf(actual-consumed,maxf(EPS,_a2_current_step-step_distance))
  step_distance+=take;consumed+=take
  step_fraction=clampf(step_distance/_a2_current_step,0.0,1.0)
  var here:Vector2=from.lerp(to,consumed/actual)
  _swing_target=_a2_target_from(here,maxf(0.0,_a2_current_step-step_distance))
  _sample_swing()
  if step_fraction<1.0-EPS:break
  if not _swing_landed:
   feet[swing].position=_swing_target;feet[swing].planted=true
   feet[swing].landing_id=int(feet[swing].landing_id)+1
  var old_support:String=support;support=swing;swing=old_support
  _step_start=here;step_distance=0.0;step_fraction=0.0
  _step_direction=_a2_frame_direction
  _swing_from=feet[swing].position;_swing_landed=false
  _a2_current_step=_a2_step_budget(here,_step_direction)
  _swing_target=_a2_target_from(here,_a2_current_step)
  if consumed>=actual-EPS:break

func _sample_swing() -> void:
 if _a2_floor_change:
  if feet[swing].planted:
   if _swing_landed:return
   # Preserve the old anchor for this actual lift sample.
   feet[swing].planted=false
   return
  # This is only a proposed landing. _solve must reach its floor point through
  # the bounded flight path before assigning a contact ID or releasing support.
  feet[swing].position=_swing_target;feet[swing].planted=true
  feet[swing].landing_id=int(feet[swing].landing_id)+1
  _swing_landed=true
  return
 super._sample_swing()

func _a2_inside(point:Vector2,sides:Array[String]) -> bool:
 for side in sides:
  var radius:Vector2=_a2_bounds(side)
  var distance:float=point.distance_to(_a2_annulus_center(side))
  if distance<radius.x-0.0001 or distance>radius.y+0.0001:return false
 return true

func _a2_nearest_hip(target:Vector2,sides:Array[String]) -> Vector2:
 if sides.is_empty() or _a2_inside(target,sides):return target
 # Exact boundary candidates for the intersection of one or two annuli.
 # This includes the inner radius; zeroing an imaginary outer-circle span is
 # not a feasible solution and caused the inherited tick-173 pelvis collapse.
 var centers:Array[Vector2]=[];var radii:Array[float]=[]
 for side in sides:
  var center:Vector2=_a2_annulus_center(side)
  var bounds:Vector2=_a2_bounds(side)
  centers.append(center);radii.append(bounds.x)
  centers.append(center);radii.append(bounds.y)
 var choices:Array[Vector2]=[]
 for i in centers.size():
  var ray:Vector2=target-centers[i]
  var direction:Vector2=ray.normalized() if ray.length_squared()>EPS else Vector2.UP
  var projected:Vector2=centers[i]+direction*radii[i]
  if _a2_inside(projected,sides):choices.append(projected)
  for j in range(i+1,centers.size()):
   var between:Vector2=centers[j]-centers[i];var distance:float=between.length()
   if distance<=EPS or distance>radii[i]+radii[j] or distance<absf(radii[i]-radii[j]):continue
   var along:float=(radii[i]*radii[i]-radii[j]*radii[j]+distance*distance)/(2.0*distance)
   var high:float=sqrt(maxf(0.0,radii[i]*radii[i]-along*along))
   var tangent:Vector2=between/distance
   var middle:Vector2=centers[i]+tangent*along
   var normal:Vector2=Vector2(-tangent.y,tangent.x)*high
   for option in [middle+normal,middle-normal]:
    if _a2_inside(option,sides):choices.append(option)
 if choices.is_empty():return Vector2(INF,INF)
 var best:Vector2=choices[0]
 for option in choices:
  if option.distance_squared_to(target)<best.distance_squared_to(target):best=option
 return best

func _a2_in_rings(point:Vector2,rings:Array[Dictionary]) -> bool:
 for ring in rings:
  var distance:float=point.distance_to(ring.center)
  if distance<float(ring.bounds.x)-0.0001 or distance>float(ring.bounds.y)+0.0001:return false
 return true

func _a2_nearest_in_rings(target:Vector2,rings:Array[Dictionary]) -> Vector2:
 # Exact nearest-point candidates for circular annuli plus a continuity ball.
 # Inner boundaries are kept. If no feasible point exists, report it instead
 # of clamping a joint, stretching a bone or inventing a planted endpoint.
 if _a2_in_rings(target,rings):return target
 var centers:Array[Vector2]=[];var radii:Array[float]=[]
 for ring in rings:
  for radius in [ring.bounds.x,ring.bounds.y]:
   if radius>EPS:centers.append(ring.center);radii.append(radius)
 var choices:Array[Vector2]=[]
 for i in centers.size():
  var ray:Vector2=target-centers[i]
  var direction:Vector2=ray.normalized() if ray.length_squared()>EPS else Vector2.UP
  var point:Vector2=centers[i]+direction*radii[i]
  if _a2_in_rings(point,rings):choices.append(point)
  for j in range(i+1,centers.size()):
   var between:Vector2=centers[j]-centers[i];var distance:float=between.length()
   if distance<=EPS or distance>radii[i]+radii[j] or distance<absf(radii[i]-radii[j]):continue
   var along:float=(radii[i]*radii[i]-radii[j]*radii[j]+distance*distance)/(2.0*distance)
   var high:float=sqrt(maxf(0.0,radii[i]*radii[i]-along*along))
   var tangent:Vector2=between/distance;var middle:Vector2=centers[i]+tangent*along
   var normal:Vector2=Vector2(-tangent.y,tangent.x)*high
   for option in [middle+normal,middle-normal]:
    if _a2_in_rings(option,rings):choices.append(option)
 if choices.is_empty():return Vector2(INF,INF)
 var best:Vector2=choices[0]
 for option in choices:
  if option.distance_squared_to(target)<best.distance_squared_to(target):best=option
 return best

func _a2_project_flight(side:String,wanted:Vector2) -> Vector2:
 var center:Vector2=hip+_a2_socket(side)
 var ray:Vector2=wanted-_a2_sole_offset(side)-center
 var distance:float=ray.length();var radius:Vector2=_a2_bounds(side)
 var direction:Vector2=ray.normalized() if distance>EPS else Vector2.DOWN
 return center+direction*clampf(distance,radius.x,radius.y)+_a2_sole_offset(side)

func _a2_ground_target(side:String,wanted:Vector2) -> Vector2:
 var anchor:Vector2=hip+_a2_socket(side)
 var offset:Vector2=_a2_sole_offset(side)
 var radius:Vector2=_a2_bounds(side)
 var dy:float=wanted.y-offset.y-anchor.y
 if absf(dy)>radius.y:return Vector2(INF,INF)
 var outer_x:float=sqrt(maxf(0.0,radius.y*radius.y-dy*dy))
 var x:float=clampf(wanted.x-offset.x-anchor.x,-outer_x,outer_x)
 if absf(dy)<radius.x:
  var inner_x:float=sqrt(maxf(0.0,radius.x*radius.x-dy*dy))
  if absf(x)<inner_x:x=inner_x*(1.0 if x>=0.0 else -1.0)
 return Vector2(anchor.x+x+offset.x,wanted.y)

func _solve() -> void:
 if feet.is_empty():return
 if _r5_facing_change and _r5_try_contact_turn():
  _r5_solve_declared_joints();return
 var proposed:Dictionary=feet.duplicate(true)
 var pinned:Array[String]=[]
 for side in SIDES:
  var previous:Dictionary=_a2_before.get(side,feet[side])
  if feet[side].planted and previous.planted and feet[side].landing_id==previous.landing_id:pinned.append(side)
 # A proposed release cannot remove the last actual contact before the other
 # foot has genuinely landed. Restore that exact anchor, not a translated one.
 if pinned.is_empty():
  for side in SIDES:
   var previous:Dictionary=_a2_before.get(side,feet[side])
   if previous.planted:
    feet[side]=previous.duplicate(true);pinned.append(side)
    _a2_events.append({"kind":"release_deferred","side":side,"contact_id":previous.landing_id,"at":previous.position})
    break
 var speed_weight:float=clampf(_candidate_speed/155.0,0.0,1.0) if travelling else 0.0
 _candidate_walk_weight=move_toward(_candidate_walk_weight,speed_weight,_candidate_dt*HIP_BLEND_SPEED)
 var target:Vector2=origin+_v(config.hip)*_s()+Vector2(0.0,lerpf(_motion_rest_drop_native(),_motion_walk_drop_native(),_candidate_walk_weight)*_s())
 if not _a2_before.is_empty():
  target=origin+_a2_before_hip_local.move_toward(target-origin,A2_HIP_RECOVERY_NATIVE*_s()*_candidate_dt)
 hip=_a2_nearest_hip(target,pinned)
 if not hip.is_finite() and pinned.size()==2:
  # The stance itself is infeasible. Keep the feasible contact requiring the
  # smaller body displacement and explicitly lift the other anatomical foot.
  var far_only:Array[String]=["far"];var near_only:Array[String]=["near"]
  var far_hip:Vector2=_a2_nearest_hip(target,far_only)
  var near_hip:Vector2=_a2_nearest_hip(target,near_only)
  var keep:String="far" if far_hip.distance_squared_to(target)<=near_hip.distance_squared_to(target) else "near"
  var release:String=_other(keep)
  feet[release].planted=false;proposed[release].planted=false
  pinned.assign([keep]);support=keep;swing=release
  _swing_from=feet[release].position;_swing_landed=false
  _a2_events.append({"kind":"lift_infeasible_pair","side":release,"contact_id":feet[release].landing_id,"at":feet[release].position})
  hip=far_hip if keep=="far" else near_hip
 _candidate_reach_feasible=hip.is_finite()
 if not hip.is_finite():hip=target
 for side in SIDES:
  if side in pinned:continue
  var previous:Dictionary=_a2_before.get(side,proposed[side])
  var wanted:Vector2=proposed[side].position
  var requested_landing:bool=bool(proposed[side].planted)
  if requested_landing:
   wanted=_a2_ground_target(side,wanted)
   if not wanted.is_finite():
    requested_landing=false;wanted=_a2_project_flight(side,previous.position)
  var bounded:Vector2=previous.position.move_toward(wanted,_a2_flight_speed_limit()*_s()*_candidate_dt) if not _a2_before.is_empty() else wanted
  var actual:Vector2=_a2_project_flight(side,bounded)
  _a2_constraint_correction=maxf(_a2_constraint_correction,actual.distance_to(bounded)/_s())
  _a2_flight_step=maxf(_a2_flight_step,actual.distance_to(previous.position)/_s())
  feet[side].position=actual;feet[side].planted=false;feet[side].landing_id=previous.landing_id
  if requested_landing and actual.distance_to(wanted)<=0.001:
   feet[side].position=wanted;feet[side].planted=true
   _a2_contact_serial+=1;feet[side].landing_id=_a2_contact_serial
   _a2_events.append({"kind":"land","side":side,"contact_id":_a2_contact_serial,"at":wanted,"clock":pose_time,"observed_floor_y":origin.y})
   if side==swing:_swing_landed=true
  elif proposed[side].planted:
   _a2_landing_deferred=true;_swing_landed=false
   if not pinned.is_empty():support=pinned[0];swing=side
   # Hold the final segment until this reachable path actually reaches floor.
   # Do not relabel an airborne target as support at a nominal phase boundary.
   if travelling and step_fraction<0.1:step_fraction=1.0;step_distance=_a2_current_step-EPS
  if previous.planted and not feet[side].planted:
   _a2_events.append({"kind":"lift","side":side,"contact_id":previous.landing_id,"at":previous.position})
 if _a2_floor_change:
  for event in _a2_events.duplicate():
   if event.kind=="land" and event.side!=support:
    var old:String=support
    support=str(event.side);swing=old
    feet[old].planted=false
    _a2_events.append({"kind":"lift","side":old,"contact_id":feet[old].landing_id,"at":feet[old].position,"reason":"observed_floor_transfer"})
    # Ownership has now genuinely transferred. Select the final hip from the
    # new actual contact, the old foot's bounded reachable-flight region and
    # the root-relative continuity ball. Do not retain the outgoing contact
    # as an obsolete pelvis constraint for one extra frame.
    var flight_bound:float=_a2_flight_speed_limit()*_s()*_candidate_dt
    var old_bounds:Vector2=_a2_bounds(old)
    var rings:Array[Dictionary]=[
     {"center":_a2_annulus_center(support),"bounds":_a2_bounds(support)},
     {"center":_a2_annulus_center(old),"bounds":Vector2(maxf(0.0,old_bounds.x-flight_bound),old_bounds.y+flight_bound)},
     {"center":origin+_a2_before_hip_local,"bounds":Vector2(0.0,2.0*_s())}]
    var transfer_hip:Vector2=_a2_nearest_in_rings(target,rings)
    _a2_transfer_feasible=transfer_hip.is_finite()
    if _a2_transfer_feasible:
     hip=transfer_hip
     var old_anchor:Vector2=feet[old].position
     feet[old].position=_a2_project_flight(old,old_anchor)
     var released_step:float=feet[old].position.distance_to(old_anchor)/_s()
     _a2_flight_step=maxf(_a2_flight_step,released_step)
     _a2_constraint_correction=maxf(_a2_constraint_correction,released_step)
    else:
     _a2_events.append({"kind":"transfer_infeasible","at":origin,"clock":pose_time,"rings":rings})
    _swing_from=feet[old].position;_swing_landed=false
    _step_start=origin;step_distance=0.0;step_fraction=0.0
    _step_direction=_a2_frame_direction
    _a2_current_step=_a2_step_budget(origin,_step_direction)
    _swing_target=_a2_target_from(origin,_a2_current_step)
    break
 if not feet[support].planted:
  support="near" if feet.near.planted else "far";swing=_other(support)
 if _a2_landing_deferred and not travelling:settled=false;settling=true
 _r5_solve_declared_joints()

func _r5_solve_declared_joints() -> void:
 max_reach_error=0.0
 for side in SIDES:
  var leg:Dictionary=config.legs[side]
  var at:Vector2=hip+_a2_socket(side)
  var ankle:Vector2=feet[side].position-_a2_sole_offset(side)
  var l1:float=float(leg.thigh_length)*_s();var l2:float=float(leg.shin_length)*_s()
  var distance:float=at.distance_to(ankle)
  var valid:float=clampf(distance,absf(l1-l2)+0.00001,l1+l2-0.00001)
  var toward:Vector2=(ankle-at).normalized()
  var along:float=(l1*l1-l2*l2+valid*valid)/(2.0*valid)
  var height:float=sqrt(maxf(0.0,l1*l1-along*along))
  var knee:Vector2=at+toward*along+Vector2(toward.y,-toward.x)*height*_sign()
  max_reach_error=maxf(max_reach_error,absf(distance-valid))
  joints[side]={"hip":at,"knee":knee,"ankle":ankle,"sole":feet[side].position}
 _candidate_reach_feasible=_candidate_reach_feasible and max_reach_error<=0.001
 _extension_weight=1.0-_candidate_walk_weight

func snapshot() -> Dictionary:
 var result:Dictionary=super.snapshot()
 result.candidate="R5-explicit-two-foot-rest"
 result.turn_preparation=_r5_turn_outcome
 result.rest_plan={"stage":_r5_stage,"order":_r5_order.duplicate(),"targets":_r5_targets.duplicate(true),"first_clock":_settle_start,"stage_clock":_r5_stage_clock,"target_knee_flexion_degrees":12.0}
 result.foot_scheduler="source proposal; explicit reachable flight and real contact latch"
 result.contact_events=_a2_events.duplicate(true)
 result.flight_constraint_correction_native=_a2_constraint_correction
 result.flight_step_native=_a2_flight_step
 result.landing_deferred=_a2_landing_deferred
 result.contact_serial=_a2_contact_serial
 result.support_segment_length_native=_a2_current_step/_s()
 result.landing_ahead_native=A2_LANDING_AHEAD_NATIVE
 result.flight_speed_limit_native=_a2_flight_speed_limit()
 result.transfer_continuity_feasible=_a2_transfer_feasible
 result.floor_change_observed=_a2_floor_change
 result.planned_step_direction=_step_direction
 return result


# R5 rest correction. R4 travel/annulus/contact solver above is unchanged.
# Initial stance is declared once at reset. Subsequent feet move only through
# one real support transfer at a time and R4's unique actual landing latch.
const R5_REST_STEP_SECONDS:float=0.20
const R5_REST_TARGET_TOLERANCE_NATIVE:float=0.25
var _r5_order:Array[String]=[]
var _r5_targets:Dictionary={}
var _r5_stage:int=0
var _r5_stage_clock:float=0.0
var _r5_stage_from:Vector2=Vector2.ZERO
var _r5_landing_requested:bool=false

func configure(data:Dictionary,height:float=210.0) -> bool:
 if not super.configure(data,height):return false
 for side in SIDES:
  var local:Vector2=_r5_rest_sole_native(side)
  config.legs[side].neutral_sole=[local.x,local.y]
 return true

func _r5_rest_sole_native(side:String) -> Vector2:
 var leg:Dictionary=config.legs[side]
 var socket:Vector2=_v(leg.hip_offset)
 var sole:Vector2=_v(leg.sole_from_ankle)
 var l1:float=float(leg.thigh_length);var l2:float=float(leg.shin_length)
 var comfort:float=sqrt(l1*l1+l2*l2+2.0*l1*l2*cos(deg_to_rad(12.0)))
 var dy:float=-sole.y-(float(config.hip[1])+_motion_rest_drop_native()+socket.y)
 var reach_x:float=sqrt(maxf(0.0,comfort*comfort-dy*dy))
 return Vector2(socket.x+sole.x+reach_x*(-1.0 if side=="far" else 1.0),0.0)

func _begin_settle(_stop_age:float) -> void:
 support=_choose_support();swing=_other(support)
 travelling=false;settling=true;settled=false
 _settle_start=pose_time
 _settle_arm=arm_angle;_settle_shoulder=shoulder_offset;_settle_extension=_extension_weight
 _r5_order.assign([swing,support]);_r5_targets={};_r5_stage=0
 for side in SIDES:
  _r5_targets[side]=origin+_r5_rest_sole_native(side)*Vector2(_sign(),1.0)*_s()
 _r5_enter_rest_stage()

func _r5_enter_rest_stage() -> void:
 while _r5_stage<_r5_order.size():
  var side:String=_r5_order[_r5_stage]
  if feet[side].planted and feet[side].position.distance_to(_r5_targets[side])<=R5_REST_TARGET_TOLERANCE_NATIVE*_s():
   _r5_stage+=1;continue
  swing=side;support=_other(side)
  _r5_stage_clock=pose_time;_r5_stage_from=feet[side].position
  _r5_landing_requested=false
  _a2_events.append({"kind":"rest_step_begin","side":side,"contact_id":feet[side].landing_id,
   "from":feet[side].position,"target":_r5_targets[side],"clock":pose_time})
  return
 settling=false;settled=true

func _advance_settle() -> void:
 if not settling:return
 # Ownership advances only after the previous call produced a real landing.
 if _r5_landing_requested and feet[swing].planted and feet[swing].position.distance_to(_r5_targets[swing])<=R5_REST_TARGET_TOLERANCE_NATIVE*_s():
  _r5_stage+=1;_r5_enter_rest_stage()
  if not settling:return
 var u:float=clampf((pose_time-_r5_stage_clock)/R5_REST_STEP_SECONDS,0.0,1.0)
 var smooth:float=u*u*(3.0-2.0*u)
 feet[swing].position=_r5_stage_from.lerp(_r5_targets[swing],smooth)
 feet[swing].position.y-=sin(PI*u)*4.0*_s()
 feet[swing].planted=u>=1.0
 if u>=1.0:
  # This is a request only. R4 constrains flight and assigns the real unique ID.
  feet[swing].position=_r5_targets[swing]
  _r5_landing_requested=true


func _r5_try_contact_turn() -> bool:
 # Only an actually airborne replacement foot may make a new turn landing.
 # A facing request is not permission to slide/relabel an existing contact.
 var planted:Array[String]=[];var airborne:Array[String]=[]
 for side in SIDES:
  if not _a2_before.has(side):return false
  if bool(_a2_before[side].planted):planted.append(side)
  else:airborne.append(side)
 if planted.size()!=1 or airborne.size()!=1:return false
 var old_support:String=planted[0];var new_support:String=airborne[0]
 var continuity_center:Vector2=origin+_a2_before_hip_local
 var old_point:Vector2=_a2_before[old_support].position
 var old_center:Vector2=old_point-_a2_sole_offset(old_support)-_a2_socket(old_support)
 var old_bounds:Vector2=_a2_bounds(old_support)
 var old_radius:float=continuity_center.distance_to(old_center)
 var continuity_radius:float=2.0*_s()
 if old_radius<=old_bounds.y+continuity_radius and old_radius>=old_bounds.x-continuity_radius:return false
 _r5_turn_outcome="no_feasible_actual_transfer"
 var new_from:Vector2=_a2_before[new_support].position
 var new_ground:Vector2=Vector2(new_from.x,origin.y)
 var flight_bound:float=_a2_flight_speed_limit()*_s()*_candidate_dt
 if new_ground.distance_to(new_from)>flight_bound:return false
 var new_center:Vector2=new_ground-_a2_sole_offset(new_support)-_a2_socket(new_support)
 var conservative_flight:float=maxf(0.0,flight_bound-0.0001*_s())
 var rings:Array[Dictionary]=[
  {"center":new_center,"bounds":_a2_bounds(new_support)},
  {"center":old_center,"bounds":Vector2(maxf(0.0,old_bounds.x-conservative_flight),old_bounds.y+conservative_flight)},
  {"center":continuity_center,"bounds":Vector2(0.0,continuity_radius)}]
 var new_weight:float=move_toward(_candidate_walk_weight,clampf(_candidate_speed/155.0,0.0,1.0),_candidate_dt*HIP_BLEND_SPEED)
 var target:Vector2=origin+_v(config.hip)*_s()+Vector2(0.0,lerpf(_motion_rest_drop_native(),_motion_walk_drop_native(),new_weight)*_s())
 target=continuity_center.move_toward(target,A2_HIP_RECOVERY_NATIVE*_s()*_candidate_dt)
 var new_hip:Vector2=_a2_nearest_in_rings(target,rings)
 if not new_hip.is_finite():return false
 var previous_hip:Vector2=hip;hip=new_hip
 var released:Vector2=_a2_project_flight(old_support,old_point)
 if released.distance_to(old_point)>flight_bound+0.00001:
  hip=previous_hip;return false
 _candidate_walk_weight=new_weight
 feet[new_support]=_a2_before[new_support].duplicate(true)
 feet[new_support].position=new_ground;feet[new_support].planted=true
 _a2_contact_serial+=1;feet[new_support].landing_id=_a2_contact_serial
 _a2_events.append({"kind":"land","side":new_support,"contact_id":_a2_contact_serial,"at":new_ground,
  "clock":pose_time,"observed_floor_y":origin.y,"reason":"bounded_turn_preparation"})
 feet[old_support]=_a2_before[old_support].duplicate(true)
 feet[old_support].position=released;feet[old_support].planted=false
 _a2_events.append({"kind":"lift","side":old_support,"contact_id":feet[old_support].landing_id,
  "at":old_point,"clock":pose_time,"reason":"after_real_turn_landing"})
 support=new_support;swing=old_support
 _a2_flight_step=maxf(new_ground.distance_to(new_from),released.distance_to(old_point))/_s()
 _a2_constraint_correction=released.distance_to(old_point)/_s()
 _swing_from=released;_swing_landed=false;_step_start=origin;step_distance=0.0;step_fraction=0.0
 _step_direction=Vector2(_sign(),0.0);_a2_frame_direction=_step_direction
 _a2_current_step=_a2_step_budget(origin,_step_direction)
 _swing_target=_a2_target_from(origin,_a2_current_step)
 _a2_events.append({"kind":"begin_support_segment","support":support,"contact_id":feet[support].landing_id,
  "length_native":_a2_current_step/_s(),"at":origin,"reason":"actual_turn_transfer"})
 _candidate_reach_feasible=true;_a2_transfer_feasible=true
 _r5_turn_outcome="land_then_release"
 return true
