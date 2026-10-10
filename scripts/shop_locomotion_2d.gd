extends RefCounted
## Distance-only locomotion on a bounded, connected shop-floor route. No Input,
## Node, wall clock, Tween, physics dependency, inventory or order ownership.
const WALK_SPEED:float=155.0
const RUN_SPEED:float=300.0
const RUN_HOLD_SECONDS:float=.50
const ACCELERATION:float=900.0
const BRAKING:float=1250.0
const REVERSAL_BRAKING:float=1650.0
const INPUT_EPSILON:float=.001
const RUN_AXIS_THRESHOLD:float=.85
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
var hold_seconds:float=0.0
var facing_right:bool=true
var state:String="idle"
var coordinate:float=80.0
var right_bound:float=864.0
var _axis:float=0.0
var _enabled:bool=false
var _needs_neutral:bool=true
var _hold_direction:float=0.0
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

func set_input(axis:float,enabled:bool=true) -> void:
 if not enabled:
  var navigation_velocity:float=velocity if is_navigating() else 0.0
  _enabled=false;clear_input();velocity=navigation_velocity;return
 _enabled=true
 var requested:float=clampf(axis,-1.0,1.0) if is_finite(axis) else 0.0
 if absf(requested)<INPUT_EPSILON:requested=0.0
 if _needs_neutral:
  _axis=0.0
  if requested==0.0:_needs_neutral=false
  return
 _axis=requested
 if _axis!=0.0 and is_finite(_goal):cancel_navigation()

func clear_input() -> void:
 _axis=0.0;velocity=0.0;hold_seconds=0.0;_hold_direction=0.0
 _needs_neutral=true;state="idle";_blocked=false

func navigate_to(value:float) -> void:
 if not is_finite(value):return
 _axis=0.0;hold_seconds=0.0;_hold_direction=0.0;_needs_neutral=true;_goal=clampf(value,0.0,route_length());_arrived=false

func cancel_navigation() -> void:
 _goal=NAN;_arrived=false

func is_navigating() -> bool:return is_finite(_goal)
func arrived() -> bool:return _arrived
func joining_route() -> bool:return _join_progress<_join_distance-.00001
func rear_lane() -> bool:return coordinate<=route_corner() and not joining_route()
func distance_to(value:float) -> float:
 return absf(coordinate-clampf(value,0.0,route_length()))+maxf(0.0,_join_distance-_join_progress)

func step(delta:float) -> void:
 if not is_finite(delta) or delta<=0:return
 var remaining:float=minf(delta,MAX_FRAME_SECONDS)
 while remaining>.000001:
  var dt:float=minf(STEP_SECONDS,remaining);remaining-=dt;_step_slice(dt)

func _step_slice(dt:float) -> void:
 var automatic:bool=is_finite(_goal)
 var axis:float=_axis if _enabled and not _needs_neutral else 0.0
 var target_speed:float=0.0
 if automatic:
  var left:float=distance_to(_goal)
  if left<=.04:
   coordinate=_goal;position=point_at(coordinate);velocity=0.0;state="idle";_goal=NAN;_arrived=true;return
  var direction:float=signf(_goal-coordinate)
  if direction==0.0:direction=1.0 if facing_right else -1.0
  target_speed=direction*minf(WALK_SPEED,sqrt(2.0*BRAKING*left))
 else:
  var direction:float=signf(axis)
  if direction==0.0 or direction!=_hold_direction or _blocked or absf(axis)<RUN_AXIS_THRESHOLD:hold_seconds=0.0
  if absf(axis)>=RUN_AXIS_THRESHOLD and not _blocked:hold_seconds+=dt
  _hold_direction=direction
  target_speed=axis*(RUN_SPEED if hold_seconds>=RUN_HOLD_SECONDS else WALK_SPEED)
 var acceleration:float=ACCELERATION
 if target_speed==0.0:acceleration=BRAKING
 elif velocity*target_speed<0.0:acceleration=REVERSAL_BRAKING
 elif absf(target_speed)<absf(velocity):acceleration=BRAKING
 var previous_velocity:float=velocity
 velocity=move_toward(velocity,target_speed,acceleration*dt)
 if absf(velocity)<.001:velocity=0.0
 var travel:float=(previous_velocity+velocity)*.5*dt
 var before:Vector2=position
 var previous_coordinate:float=coordinate;var previous_join:float=_join_progress;var previous_distance:float=distance
 _blocked=false
 if absf(travel)>.000001:
  if joining_route():
   var used:float=minf(absf(travel),_join_distance-_join_progress)
   _join_progress+=used;position=_join_from.lerp(_join_to,_join_progress/_join_distance)
   distance+=used;travel=signf(travel)*(absf(travel)-used)
  if not joining_route() and absf(travel)>.000001:
   var next:float=clampf(coordinate+travel,0.0,route_length())
   if automatic and (next-_goal)*(coordinate-_goal)<=0.0:next=_goal
   var moved:float=absf(next-coordinate);coordinate=next;position=point_at(coordinate);distance+=moved
   if moved<absf(travel)-.00001 and not automatic:
    velocity=0.0;hold_seconds=0.0;_blocked=true
 for obstacle in _blockers:
  # Moving away from an already overlapping externally moved object remains
  # possible. A normal route can never enter its reserved floor footprint.
  if _foot_gap(position,obstacle)<1.0 and _foot_gap(position,obstacle)<_foot_gap(before,obstacle)-.000001:
   position=before;coordinate=previous_coordinate;_join_progress=previous_join;distance=previous_distance
   velocity=0.0;hold_seconds=0.0;_blocked=true;break
 if position.distance_to(before)>.000001:
  if absf(velocity)>.01:facing_right=velocity>0.0
  state="run" if absf(velocity)>WALK_SPEED*1.12 else "walk"
 else:
  state="idle"
  if absf(target_speed)>.0 and not joining_route():hold_seconds=0.0

func _foot_gap(at:Vector2,obstacle:Vector2) -> float:
 # The authored deck is only ~34 screen pixels deep. Its near/far standing
 # lanes use projected floor footprints, not character-height screen circles.
 return Vector2((at.x-obstacle.x)/_clearance,(at.y-obstacle.y)/FOOT_DEPTH_CLEARANCE).length()

func snapshot() -> Dictionary:
 return {"position":position,"velocity":velocity,"distance":distance,"hold_seconds":hold_seconds,
  "state":state,"facing_right":facing_right,"coordinate":coordinate,"route_length":route_length(),
  "right_bound":right_bound,"rear_lane":rear_lane(),"joining":joining_route(),
  "enabled":_enabled,"needs_neutral":_needs_neutral,"axis":_axis,"navigating":is_navigating(),
  "goal":_goal if is_finite(_goal) else -1.0,"arrived":_arrived,"blocked":_blocked}
