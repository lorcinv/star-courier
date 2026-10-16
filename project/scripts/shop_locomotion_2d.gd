extends RefCounted
## Distance-only locomotion on a bounded, connected shop-floor route. No Input,
## Node, wall clock, Tween, physics dependency, inventory or order ownership.
const MOVE_SPEED:float=155.0
# Walk remains the legacy route pace; running is explicit player intent.
const RUN_SPEED:float=260.0
const WALK_SPEED:float=MOVE_SPEED
const ACCELERATION:float=700.0
const BRAKING:float=750.0
const REVERSAL_BRAKING:float=1000.0
const STOP_SETTLE_SECONDS:float=.12
const INPUT_EPSILON:float=.001
const STEP_SECONDS:float=1.0/120.0
const MAX_FRAME_SECONDS:float=.1
const COUNTER_MIN_X:float=196.0
const COUNTER_EDGE_X:float=452.0
const COUNTER_FLOOR_Y:float=486.0
const AISLE_FLOOR_Y:float=496.0
const FRONT_RADIUS:float=22.0
var position:Vector2=Vector2(276,COUNTER_FLOOR_Y)
var velocity:float=0.0
var distance:float=0.0
var stop_age:float=0.0
var facing_right:bool=true
var state:String="idle"
var coordinate:float=80.0
var right_bound:float=864.0
var _axis:float=0.0
var _running:bool=false
var _enabled:bool=false
var _active:bool=true
var _navigation_paused:bool=false
var _needs_neutral:bool=true
var _join_from:Vector2=Vector2.ZERO
var _join_to:Vector2=Vector2.ZERO
var _join_distance:float=0.0
var _join_progress:float=0.0
var _goal:float=NAN
var _arrived:bool=false
var _blocked:bool=false
var _blockers:Array[Vector2]=[]
var _clearance:float=58.0
const FOOT_DEPTH_CLEARANCE:float=8.0
# Bounded read-only presentation history. Never included in snapshot().
const PRESENTATION_MAX_SEGMENTS:int=16
var _presentation_segments:Array[Dictionary]=[]
var _presentation_sequence:int=0
var _presentation_reset_epoch:int=0
func presentation_segments() -> Dictionary:
 return {"owner":get_instance_id(),"reset_epoch":_presentation_reset_epoch,"sequence":_presentation_sequence,"segments":_presentation_segments.duplicate(true)}
func clear_presentation_segments() -> void:
 _presentation_segments.clear()


func configure(right_edge:float) -> void:
 if not is_finite(right_edge):return
 right_bound=maxf(COUNTER_EDGE_X+140.0,right_edge)
 # A tier grows to the right. Reconfiguration never relocates an actor; a rare
 # externally narrowed route is resolved by an ordinary connector on adoption.
 if is_finite(_goal):_goal=clampf(_goal,0.0,route_length())

func route_corner() -> float:return COUNTER_EDGE_X-COUNTER_MIN_X
func front_start() -> float:return route_corner()+AISLE_FLOOR_Y-COUNTER_FLOOR_Y
func route_length() -> float:return front_start()+right_bound-COUNTER_EDGE_X
func point_at(value:float) -> Vector2:
 var s:float=clampf(value,0.0,route_length())
 if s<=route_corner():return Vector2(COUNTER_MIN_X+s,COUNTER_FLOOR_Y)
 if s<=front_start():return Vector2(COUNTER_EDGE_X,COUNTER_FLOOR_Y+s-route_corner())
 return Vector2(COUNTER_EDGE_X+s-front_start(),AISLE_FLOOR_Y)

func coordinate_for_front_x(at_x:float) -> float:
 return front_start()+clampf(at_x,COUNTER_EDGE_X,right_bound)-COUNTER_EDGE_X

func adopt_position(at:Vector2) -> void:
 if not at.is_finite():return
 clear_input();cancel_navigation();position=at
 if at.x<=COUNTER_EDGE_X and absf(at.y-COUNTER_FLOOR_Y)<.1:
  coordinate=clampf(at.x-COUNTER_MIN_X,0.0,route_corner())
 elif absf(at.x-COUNTER_EDGE_X)<.1 and at.y<=AISLE_FLOOR_Y:
  coordinate=route_corner()+clampf(at.y-COUNTER_FLOOR_Y,0.0,AISLE_FLOOR_Y-COUNTER_FLOOR_Y)
 else:coordinate=coordinate_for_front_x(at.x)
 _join_from=at;_join_to=point_at(coordinate);_join_distance=at.distance_to(_join_to);_join_progress=0.0

func set_blockers(points:Array,clearance:float=58.0) -> void:
 _blockers.clear()
 _clearance=clampf(clearance,1.0,160.0) if is_finite(clearance) else 58.0
 for at in points:
  if at is Vector2 and at.is_finite() and _blockers.size()<8:_blockers.append(at)

func set_input(axis:float,enabled:bool=true,allow_navigation:bool=false,running:bool=false) -> void:
 # Losing player context freezes all motion by default, including a queued
 # click route. Only an explicitly permitted story return can keep moving.
 if not enabled:
  _enabled=false;_running=false
  _active=allow_navigation and is_navigating()
  if _active:
   _axis=0.0;_needs_neutral=true;_navigation_paused=false
  else:clear_input()
  return
 _enabled=true;_active=true
 var requested:float=clampf(axis,-1.0,1.0) if is_finite(axis) else 0.0
 if absf(requested)<INPUT_EPSILON:requested=0.0
 if _needs_neutral:
  _axis=0.0;_running=false
  if requested==0.0:_needs_neutral=false;_navigation_paused=false
  return
 _axis=requested;_running=running and requested!=0.0
 if _axis!=0.0 and is_finite(_goal):cancel_navigation()

func clear_input() -> void:
 _presentation_reset_epoch+=1;clear_presentation_segments()
 _axis=0.0;_running=false;velocity=0.0;stop_age=0.0
 _needs_neutral=true;_navigation_paused=true;state="idle";_blocked=false

func navigate_to(value:float) -> void:
 if not is_finite(value):return
 _axis=0.0;_running=false;stop_age=0.0;_needs_neutral=true;_goal=clampf(value,0.0,route_length());_arrived=false;_navigation_paused=not _active

func cancel_navigation() -> void:
 _goal=NAN;_arrived=false

func is_navigating() -> bool:return is_finite(_goal)
func arrived() -> bool:return _arrived
func joining_route() -> bool:return _join_progress<_join_distance-.00001
func rear_lane() -> bool:return coordinate<=route_corner() and not joining_route()
func distance_to(value:float) -> float:
 return absf(coordinate-clampf(value,0.0,route_length()))+maxf(0.0,_join_distance-_join_progress)

func step(delta:float) -> void:
 _presentation_sequence+=1;clear_presentation_segments()
 if not _active or not is_finite(delta) or delta<=0:return
 var remaining:float=minf(delta,MAX_FRAME_SECONDS)
 while remaining>.000001:
  var dt:float=minf(STEP_SECONDS,remaining);remaining-=dt
  var before:Dictionary=snapshot()
  _step_slice(dt)
  if _presentation_segments.size()<PRESENTATION_MAX_SEGMENTS:
   _presentation_segments.append({"dt":dt,"before":before,"after":snapshot()})

func _step_slice(dt:float) -> void:
 var automatic:bool=is_finite(_goal) and not _navigation_paused
 var axis:float=_axis if _enabled and not _needs_neutral else 0.0
 var target_speed:float=0.0
 if automatic:
  var left:float=distance_to(_goal)
  if left<=.000001:
   # The previous slice already travelled to the goal; do not snap a final
   # uncounted gap or advance the animation phase while standing.
   velocity=0.0;_goal=NAN;_arrived=true
   _update_state(0.0,0.0,false,dt)
   return
  var direction:float=signf(_goal-coordinate)
  if direction==0.0:direction=1.0 if facing_right else -1.0
  target_speed=direction*minf(MOVE_SPEED,sqrt(2.0*BRAKING*left))
 else:
  # The router owns deadzone/run intent. Physics still ramps real velocity;
  # releasing Shift brakes down to walking instead of switching root speed.
  target_speed=axis*(RUN_SPEED if _running else WALK_SPEED)
 var reversing:bool=velocity*target_speed<0.0
 var acceleration:float=ACCELERATION
 if reversing:acceleration=REVERSAL_BRAKING
 elif target_speed==0.0 or absf(target_speed)<absf(velocity):acceleration=BRAKING
 # A reversal has two real legs: brake to zero, then accelerate in the new
 # direction. Splitting at zero counts both distances and preserves facing.
 var segment_target:float=0.0 if reversing else target_speed
 var ramp_time:float=minf(dt,absf(segment_target-velocity)/acceleration)
 var used:float=ramp_time if reversing and ramp_time<dt else dt
 var previous_velocity:float=velocity
 velocity=move_toward(velocity,segment_target,acceleration*ramp_time)
 if absf(velocity)<.000001:velocity=0.0
 # Exact piecewise integral: once a target is reached, spend the remainder
 # at that speed rather than stretching the ramp across the whole slice.
 var travel:float=(previous_velocity+velocity)*.5*ramp_time+velocity*(used-ramp_time)
 var before:Vector2=position
 var previous_coordinate:float=coordinate;var previous_join:float=_join_progress;var previous_distance:float=distance
 _blocked=false
 if absf(travel)>.00000001:
  if joining_route():
   var consumed:float=minf(absf(travel),_join_distance-_join_progress)
   _join_progress+=consumed;position=_join_from.lerp(_join_to,_join_progress/_join_distance)
   distance+=consumed;travel=signf(travel)*(absf(travel)-consumed)
  if not joining_route() and absf(travel)>.00000001:
   var next:float=clampf(coordinate+travel,0.0,route_length())
   if automatic and (next-_goal)*(coordinate-_goal)<=0.0:next=_goal
   var travelled:float=absf(next-coordinate);coordinate=next;position=point_at(coordinate);distance+=travelled
   if travelled<absf(travel)-.00001 and not automatic:
    velocity=0.0;_blocked=true
 for obstacle in _blockers:
  # Moving away from an already overlapping externally moved object remains
  # possible. A normal route can never enter its reserved floor footprint.
  if _foot_gap(position,obstacle)<1.0 and _foot_gap(position,obstacle)<_foot_gap(before,obstacle)-.000001:
   position=before;coordinate=previous_coordinate;_join_progress=previous_join;distance=previous_distance
   velocity=0.0;_blocked=true;break
 var moved:bool=distance>previous_distance+.00000001
 if moved:
  # During a connector the route direction still identifies the facing. On
  # an ordinary route the signed, actual distance decides it, even on the
  # final braking slice whose ending velocity is exactly zero.
  facing_right=previous_velocity>0.0 if velocity==0.0 else velocity>0.0
 if automatic and not _blocked and distance_to(_goal)<=.000001:
  velocity=0.0;_goal=NAN;_arrived=true
 _update_state(target_speed,previous_velocity,moved,used)
 if state=="stop" and absf(previous_velocity)>.000001 and not _blocked and not automatic and target_speed==0.0:
  stop_age=minf(STOP_SETTLE_SECONDS,stop_age+used-ramp_time)
  if stop_age>=STOP_SETTLE_SECONDS:state="idle"
 if used<dt-.00000001:_step_slice(dt-used)

func _update_state(target_speed:float,previous_velocity:float,moved:bool,dt:float) -> void:
 if absf(velocity)>.000001:
  stop_age=0.0
  if target_speed==0.0 or velocity*target_speed<0.0 or absf(velocity)>absf(target_speed)+.1:
   state="inertial_stop"
  elif absf(velocity)<absf(target_speed)-.1:state="start"
  else:state="move"
 elif moved or absf(previous_velocity)>.000001 or state in ["start","move","inertial_stop"]:
  state="stop";stop_age=0.0
 elif state=="stop":
  stop_age=minf(STOP_SETTLE_SECONDS,stop_age+dt)
  if stop_age>=STOP_SETTLE_SECONDS:state="idle"
 else:state="idle"

func _foot_gap(at:Vector2,obstacle:Vector2) -> float:
 # The authored deck is only ~34 screen pixels deep. Its near/far standing
 # lanes use projected floor footprints, not character-height screen circles.
 return Vector2((at.x-obstacle.x)/_clearance,(at.y-obstacle.y)/FOOT_DEPTH_CLEARANCE).length()

func snapshot() -> Dictionary:
 return {"position":position,"velocity":velocity,"distance":distance,"stop_age":stop_age,
  "state":state,"facing_right":facing_right,"coordinate":coordinate,"route_length":route_length(),
  "right_bound":right_bound,"rear_lane":rear_lane(),"joining":joining_route(),
  "running_requested":_running,"gait":"run" if absf(velocity)>WALK_SPEED+.1 else "walk" if velocity!=0.0 else "idle",
  "enabled":_enabled,"active":_active,"needs_neutral":_needs_neutral,"axis":_axis,"navigating":is_navigating(),
  "navigation_paused":_navigation_paused,"goal":_goal if is_finite(_goal) else -1.0,"arrived":_arrived,"blocked":_blocked}
