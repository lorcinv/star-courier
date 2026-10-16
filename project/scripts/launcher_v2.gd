extends RefCounted
## Paid, anchored launch preparation for pilot-free-v2 only.
## Invoke through the new simulation's _prepare_launcher override. Do not call
## from frozen v1 paths. Support limits output rather than destroying property.
const Parts=preload("res://scripts/parts_expanded.gd")
const SCHEMA:String="anchored-launch-v2"
const PAD:Array[String]=["beam","battery","thruster","armor","accelerator","spring"]
const MOTOR:Array[String]=["spring","thruster","accelerator"]
const EPS:float=0.000001
const RELEASE_SECONDS:float=1.0

static func starter_launcher() -> Array:
 var result:Array=[]
 for row in [[1001,"spring",0,0,60.0],[1002,"battery",-1,0,300.0],[1003,"beam",1,0,32.0],[1004,"beam",1,1,32.0]]:
  result.append({"id":row[0],"type":row[1],"x":row[2],"y":row[3],"rot":0,"param":row[4],"input_a":-1,"input_b":-1,"target":-1})
 return result

static func compatible(kind:String) -> bool:return kind in PAD

static func prepare(sim,design:Array) -> void:
 sim.launcher_parts.clear()
 sim.telemetry.launch_policy=SCHEMA
 sim.telemetry.launch_impulse=[0.0,0.0]
 sim.telemetry.launch_speed=0.0
 sim.telemetry.launch_energy_drawn=0.0
 sim.telemetry.launch_heat=0.0
 sim.telemetry.launch_support_limited=false
 sim.telemetry.launch_modules_fired=0
 var lookup:Dictionary={}
 for raw in design:
  var p:Dictionary=sim._new_part(raw)
  sim.launcher_parts.append(p);lookup[int(p.id)]=p
  if not compatible(str(p.type)):sim._log("发射台上的%s不能参与弹射，请在车间调整。"%str(p.type))
 var craft_left:float=INF;var pad_right:float=-INF
 for q in sim.parts.values():
  if q.alive:craft_left=minf(craft_left,sim._part_position(q).x-0.43*q.scale)
 for q in sim.launcher_parts:pad_right=maxf(pad_right,float(q.x)+0.43)
 sim.launcher_origin=Vector2(craft_left-pad_right,0.0) if is_finite(craft_left) and is_finite(pad_right) else Vector2.ZERO
 for q in sim.launcher_parts:q.world_pos=Vector2(q.x,q.y)+sim.launcher_origin
 var body:Dictionary=sim._cargo_body()
 if body.is_empty():return
 var total_impulse:Vector2=Vector2.ZERO
 var visited:Dictionary={}
 for root in sim.launcher_parts:
  if visited.has(root.id):continue
  var component:Array=[root];var queue:Array=[root];visited[root.id]=true
  while not queue.is_empty():
   var current:Dictionary=queue.pop_front()
   for candidate in sim.launcher_parts:
    if not visited.has(candidate.id) and absi(int(current.x)-int(candidate.x))+absi(int(current.y)-int(candidate.y))==1:
     component.append(candidate);queue.append(candidate);visited[candidate.id]=true
  var batteries:Array=[];var support:float=0.0;var has_motor:bool=false
  for p in component:
   if p.type=="battery":batteries.append(p)
   if p.type=="beam":support+=maxf(0.0,float(p.strength))
   # A bolted armor plate is a heavier 90 N anchor; it shares the ship item.
   if p.type=="armor":support+=90.0
   if p.type in MOTOR:has_motor=true
  if not has_motor:continue
  if support<=EPS:
   sim._log("发射台未连接结构梁或装甲底座，没有发射推力。")
   continue
  if batteries.is_empty():
   sim._log("发射台未接通电芯，没有发射推力。")
   continue
  var remaining_impulse:float=support*RELEASE_SECONDS
  for p in component:
   if not p.type in MOTOR:continue
   var available:float=0.0
   for battery in batteries:available+=maxf(0.0,float(battery.energy))
   if available<=EPS or remaining_impulse<=EPS:continue
   var direction:Vector2=Vector2.RIGHT.rotated(p.local_angle)
   var mass:float=maxf(EPS,float(body.mass))
   var projected:float=body.velocity.dot(direction)
   var wanted:float=0.0
   if p.type=="spring":
    # There is no contact/compression simulation at this preparation seam.
    # Never count an opposing craft's kinetic energy as free spring storage:
    # 0 J is off; a paid counter-kick dissipates the opposed motion as heat.
    var stored:float=minf(maxf(0.0,float(p.param)),available)
    if stored<=EPS:continue
    var paid_speed:float=maxf(0.0,projected)
    wanted=mass*(sqrt(paid_speed*paid_speed+2.0*stored/mass)-paid_speed)
   elif p.type=="thruster":
    # A shared nozzle provides one second of its configured Newtons.
    wanted=maxf(0.0,float(p.param))*RELEASE_SECONDS
   else:
    # A rail accelerator raises along-arrow speed to its m/s setting.
    wanted=mass*maxf(0.0,float(p.param)-projected)
   var support_limited:float=minf(wanted,remaining_impulse)
   if support_limited+EPS<wanted:sim.telemetry.launch_support_limited=true
   # Work pays positive kinetic energy plus motor inefficiency. Opposing
   # nozzles cannot use recovered kinetic energy to create free electricity.
   var low:float=0.0;var high:float=support_limited
   for iteration in range(40):
    var midpoint:float=(low+high)*0.5
    if _cost(str(p.type),midpoint,projected,mass)<=available:low=midpoint
    else:high=midpoint
   var magnitude:float=low
   if magnitude<=EPS:continue
   var cost:float=_cost(str(p.type),magnitude,projected,mass)
   var paid:float=sim._pad_draw(batteries,cost)
   if paid+EPS<cost:continue # Defensive only; _pad_draw uses the same cells.
   var impulse:Vector2=direction*magnitude
   var kinetic_change:float=magnitude*projected+0.5*magnitude*magnitude/mass
   var dissipated:float=maxf(0.0,paid-kinetic_change)
   sim.launch(impulse);total_impulse+=impulse;remaining_impulse-=magnitude
   sim.telemetry.launch_heat+=dissipated;sim.telemetry.heat+=dissipated
   p.spent=true;p.stored_energy=0.0;p.active=true
   sim.telemetry.launch_energy_drawn+=paid
   sim.telemetry.launch_modules_fired+=1
   sim._effect("launch",p.world_pos,p.world_pos+direction*2.0,0.75)
 sim.telemetry.launch_impulse=[total_impulse.x,total_impulse.y]
 sim.telemetry.launch_speed=body.velocity.length()
 if int(sim.telemetry.launch_modules_fired)>0:
  sim._log("发射台弹射：起步 %.1f m/s，台上电芯消耗 %.1f J。"%[float(sim.telemetry.launch_speed),float(sim.telemetry.launch_energy_drawn)])
  if sim.telemetry.launch_support_limited:sim._log("底座承载限制了弹射；加装结构梁或装甲可提高推力。")

static func _cost(kind:String,impulse:float,speed:float,mass:float) -> float:
 var impulse_energy:float=0.5*impulse*impulse/mass
 if kind=="spring":return impulse_energy+impulse*maxf(0.0,speed)
 var work:float=maxf(0.0,impulse*speed+impulse_energy)
 return maxf(work,impulse*1.5)
