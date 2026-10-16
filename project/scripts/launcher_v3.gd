extends RefCounted
## PDR first chapter: a single paid launch, no contact solver and no BFS priority.
## 2 m is a tunable effective launch stroke, not a user-prescribed real-world value.
const Parts=preload("res://scripts/parts_expanded.gd")
const SCHEMA:String="delivery-launch-v3"
const STROKE_METRES:float=2.0
const EPS:float=0.000001
const PAD:Array[String]=["beam","battery","thruster","armor","accelerator","spring"]
const MOTOR:Array[String]=["spring","thruster","accelerator"]

static func compatible(kind:String)->bool:return kind in PAD

static func starter_launcher()->Array:
 # Connected 3x3 footprint. Four real 60 J springs, 128 N support, one shared finite cell.
 var result:Array=[]
 for row in [[1001,"battery",0,0,300.0],[1002,"spring",-1,0,60.0],[1003,"spring",1,0,60.0],[1004,"spring",0,-1,60.0],[1005,"spring",0,1,60.0],[1006,"beam",-1,-1,32.0],[1007,"beam",1,-1,32.0],[1008,"beam",-1,1,32.0],[1009,"beam",1,1,32.0]]:
  result.append({"id":row[0],"type":row[1],"x":row[2],"y":row[3],"rot":0,"param":row[4],"input_a":-1,"input_b":-1,"target":-1})
 return result

static func prepare(sim,design:Array)->void:
 sim.launcher_parts.clear()
 sim.telemetry.merge({"launch_policy":SCHEMA,"launch_released":false,"launch_impulse":[0.0,0.0],"launch_speed":0.0,"launch_energy_drawn":0.0,"launch_heat":0.0,"launch_support_limited":false,"launch_modules_fired":0},true)
 for raw in design:
  var p:Dictionary=sim._new_part(raw)
  # A shared cell retains exactly the same capacity as on the ship.
  sim.launcher_parts.append(p)
  if not compatible(str(p.type)):sim._log("发射台上的%s不参与发射。"%str(p.type))
 sim.launcher_parts.sort_custom(func(a,b):return int(a.id)<int(b.id))
 var craft_left:float=INF;var pad_right:float=-INF
 for q in sim.parts.values():
  if q.alive:craft_left=minf(craft_left,sim._part_position(q).x-0.43*q.scale)
 for q in sim.launcher_parts:pad_right=maxf(pad_right,float(q.x)+0.43)
 sim.launcher_origin=Vector2(craft_left-pad_right,0.0) if is_finite(craft_left) and is_finite(pad_right) else Vector2.ZERO
 for q in sim.launcher_parts:q.world_pos=Vector2(q.x,q.y)+sim.launcher_origin

static func _components(sim)->Array:
 var result:Array=[];var seen:Dictionary={}
 for root in sim.launcher_parts:
  if seen.has(root.id) or not root.alive:continue
  var group:Array=[root];var queue:Array=[root];seen[root.id]=true
  while not queue.is_empty():
   var current:Dictionary=queue.pop_front()
   for candidate in sim.launcher_parts:
    if candidate.alive and not seen.has(candidate.id) and absi(int(current.x)-int(candidate.x))+absi(int(current.y)-int(candidate.y))==1:
     group.append(candidate);queue.append(candidate);seen[candidate.id]=true
  group.sort_custom(func(a,b):return int(a.id)<int(b.id))
  result.append(group)
 return result

static func _plan(sim,angle_degrees:float,power_fraction:float)->Dictionary:
 var body:Dictionary=sim._cargo_body()
 var angle:float=clampf(angle_degrees,0.0,90.0) if is_finite(angle_degrees) else 0.0
 var power:float=clampf(power_fraction,0.0,1.0) if is_finite(power_fraction) else 0.0
 var mass:float=maxf(EPS,float(body.get("mass",0.0)))
 var result:Dictionary={"schema":SCHEMA,"angle_degrees":angle,"power_fraction":power,"mass":mass,"available_energy":0.0,"energy_used":0.0,"kinetic_energy":0.0,"speed":0.0,"velocity":Vector2.ZERO,"impulse":Vector2.ZERO,"support_limited":false,"energy_limited":false,"can_release":not body.is_empty() and sim.status=="running" and not sim.launch_released,"released":sim.launch_released,"warning":"","trajectory":[],"stroke_metres":STROKE_METRES,"release_seconds":0.0,"components":[]}
 var valid:bool=is_finite(angle_degrees) and is_finite(power_fraction) and angle_degrees>=0.0 and angle_degrees<=90.0 and power_fraction>=0.0 and power_fraction<=1.0
 if not valid:result.can_release=false;result.warning="发射角须为0°–90°，力度须为0%–100%。"
 if body.is_empty():result.can_release=false;result.warning="没有可发射的货物刚体。";return result
 for group in _components(sim):
  var batteries:Array=[];var motors:Array=[];var support:float=0.0;var available:float=0.0;var capacity:float=0.0
  for p in group:
   if p.type=="battery":batteries.append(p);available+=maxf(0.0,float(p.energy))
   if p.type=="beam" or p.type=="armor":support+=maxf(0.0,float(p.strength))*clampf(float(p.hp)/maxf(EPS,float(p.max_hp)),0.0,1.0)
   if p.type in MOTOR:
    var work:float=0.0
    if p.type=="spring":work=maxf(0.0,float(p.param))
    elif p.type=="thruster":work=maxf(0.0,float(p.param))*STROKE_METRES
    else:work=0.5*float(p.mass)*pow(maxf(0.0,float(p.param)),2.0)
    work*=clampf(float(p.hp)/maxf(EPS,float(p.max_hp)),0.0,1.0)
    motors.append({"part":p,"capacity":work});capacity+=work
  if motors.is_empty():continue
  var desired:float=capacity*power
  var supported:float=support*STROKE_METRES
  var used:float=minf(desired,minf(available,supported))
  result.available_energy+=available
  result.energy_used+=used
  result.support_limited=bool(result.support_limited) or (desired>supported+EPS and available>supported+EPS)
  result.energy_limited=bool(result.energy_limited) or (desired>available+EPS and supported>available+EPS)
  result.components.append({"group_id":int(group[0].id),"batteries":batteries,"motors":motors,"capacity":capacity,"desired":desired,"available":available,"support_work":supported,"used":used})
 var direction:Vector2=Vector2.RIGHT.rotated(-deg_to_rad(angle))
 var old:Vector2=body.velocity
 # Normal release is from rest. This form also pays for an already moving body;
 # opposed motion cannot regenerate free electricity.
 var projected:float=maxf(0.0,old.dot(direction))
 var addition:float=sqrt(projected*projected+2.0*float(result.energy_used)/mass)-projected
 result.velocity=old+direction*addition;result.impulse=direction*addition*mass
 result.speed=result.velocity.length();result.kinetic_energy=maxf(0.0,0.5*mass*(result.velocity.length_squared()-old.length_squared()))
 result.release_seconds=2.0*STROKE_METRES/maxf(EPS,projected*2.0+addition) if addition>EPS else 0.0
 if result.warning.is_empty():
  if result.energy_used<=EPS:result.warning="本次没有有效弹射能量；释放后需要船上推进。"
  elif result.support_limited:result.warning="支撑承载限制了输出；增加相连梁或装甲可提高有效储能。"
  elif result.energy_limited:result.warning="台上电量限制了输出；增加同一连通台的电芯可提高有效储能。"
 var start:Vector2=sim.cargo_position()
 var acceleration:Vector2=sim._vector(sim.route.get("wind",Vector2.ZERO))+Vector2(0.0,float(sim.route.get("gravity",0.0)))
 for i in range(25):
  var seconds:float=float(i)/8.0
  result.trajectory.append(start+result.velocity*seconds+0.5*acceleration*seconds*seconds)
 return result

static func preview(sim,angle_degrees:float=0.0,power_fraction:float=1.0)->Dictionary:
 var result:Dictionary=_plan(sim,angle_degrees,power_fraction)
 # Copy the plan's already-computed bounds, never modules or a second solver.
 # Each group pays independently; capacities must not imply shared cell energy.
 var groups:Array=[]
 for group in result.components:
  var limits:Array[String]=[]
  if absf(float(group.used)-float(group.desired))<=EPS:
   limits.append("power" if float(result.power_fraction)<1.0 and float(group.capacity)>EPS else "capacity")
  if absf(float(group.used)-float(group.support_work))<=EPS:limits.append("support")
  if absf(float(group.used)-float(group.available))<=EPS:limits.append("energy")
  limits.make_read_only()
  var summary:Dictionary={"group_id":group.group_id,"capacity":group.capacity,"desired":group.desired,"supported":group.support_work,"available":group.available,"used":group.used,"limits":limits}
  summary.make_read_only();groups.append(summary)
 groups.make_read_only();result.group_limits=groups
 # Internal mutable module dictionaries never escape into UI state. Release
 # still returns its exact previous contract, without these preview-only keys.
 result.erase("components")
 return result

static func release(sim,angle_degrees:float=0.0,power_fraction:float=1.0)->Dictionary:
 var result:Dictionary=_plan(sim,angle_degrees,power_fraction)
 if not result.can_release:
  result.erase("components");return result
 sim.launch_released=true
 var modules_fired:int=0
 for group in result.components:
  var used:float=group.used
  if used<=EPS:continue
  # Every cell and motor shares the same component's demand proportionally.
  # Input array order cannot decide which module monopolises electricity/support.
  for battery in group.batteries:battery.energy=maxf(0.0,float(battery.energy)-used*float(battery.energy)/maxf(EPS,float(group.available)))
  for motor in group.motors:
   var p:Dictionary=motor.part
   p.launch_work=used*float(motor.capacity)/maxf(EPS,float(group.capacity))
   if p.launch_work>EPS:p.spent=true;p.active=true;p.stored_energy=0.0;modules_fired+=1
 sim.telemetry.energy_used=float(sim.telemetry.energy_used)+float(result.energy_used)
 sim.launch(result.impulse)
 sim.telemetry.merge({"launch_policy":SCHEMA,"launch_released":true,"launch_mass":result.mass,"launch_available_energy":result.available_energy,"launch_energy_drawn":result.energy_used,"launch_speed":result.speed,"launch_angle_degrees":result.angle_degrees,"launch_power_fraction":result.power_fraction,"launch_impulse":[result.impulse.x,result.impulse.y],"launch_support_limited":result.support_limited,"launch_modules_fired":modules_fired,"launch_release_seconds":result.release_seconds},true)
 sim._apply_launch_damage(result.impulse/maxf(EPS,float(result.mass)),float(result.release_seconds))
 sim._effect("launch",sim.launcher_origin,sim.cargo_position(),0.75)
 sim._log("发射：%.0f°，力度 %.0f%%，%.1f J 推动 %.1f kg，初速 %.2f m/s。"%[result.angle_degrees,result.power_fraction*100.0,result.energy_used,result.mass,result.speed])
 if not result.warning.is_empty():sim._log(result.warning)
 result.released=true;result.can_release=false;result.erase("components")
 sim._refresh_telemetry()
 return result
