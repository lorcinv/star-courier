extends RefCounted
## Bounded, deterministic phase-entry events. Geometry never aims at the craft.
## Only input replay/time/real altitude determines the persisted event chronology.
var events:Array=[]
var states:Dictionary={}
func configure(route:Dictionary)->void:
 events=route.get("ascent_meteor_events",[]).duplicate(true);states.clear()
 for event in events:states[event.id]={"armed":false,"armed_at":-1.0,"spawn_at":-1.0,"spawned":false,"hazard_index":-1,"finished":false}
func advance(sim)->void:
 var altitude:float=float(sim.route.background_ground_y_m)-sim.cargo_position().y
 var bounds:Array=sim.route.ascent_event_world_bounds
 var world:Rect2=Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3]))
 for event in events:
  var state:Dictionary=states[event.id]
  if not state.armed and altitude>=float(event.trigger_altitude_m):
   state.armed=true;state.armed_at=sim.elapsed;state.spawn_at=sim.elapsed+float(event.warning_seconds)
   sim._log("流星预警：%s，%.2f秒后进入轨道。"%[event.id,event.warning_seconds])
  if state.armed and not state.spawned and sim.elapsed+0.00000001>=float(state.spawn_at):
   var position:Vector2=Vector2(event.position[0],event.position[1])
   var hazard:Dictionary={"id":event.id,"type":"rock","position":position,"velocity":Vector2(event.velocity[0],event.velocity[1]),"radius":float(event.radius),"health":float(event.health),"mass":float(event.mass),"cooldown":1.0,"conductive":true,"destructible":true,"ascent_meteor_event_id":event.id}
   state.hazard_index=sim.obstacles.size();sim.obstacles.append(hazard);state.spawned=true;state.spawned_at=sim.elapsed
   sim.telemetry.ascent_meteors_spawned=int(sim.telemetry.get("ascent_meteors_spawned",0))+1
  if state.spawned and not state.finished:
   var hazard:Dictionary=sim.obstacles[int(state.hazard_index)]
   if hazard.health<=0.0:state.finished=true
   elif not world.grow(float(hazard.radius)).has_point(hazard.position):
    # Expire only after the complete physical circle leaves authored world bounds.
    hazard.health=0.0;state.finished=true
func cues(sim)->Array:
 var result:Array=[]
 for event in events:
  var state:Dictionary=states[event.id]
  if not state.armed or state.finished:continue
  var position:Vector2=Vector2(event.position[0],event.position[1]);var velocity:Vector2=Vector2(event.velocity[0],event.velocity[1])
  if state.spawned:
   var h:Dictionary=sim.obstacles[int(state.hazard_index)]
   if h.health<=0.0:continue
   position=h.position;velocity=h.velocity
  result.append({"id":event.id,"seconds_to_spawn":maxf(0.0,float(state.spawn_at)-sim.elapsed),"position":position,"velocity":velocity,"radius":float(event.radius),"active":bool(state.spawned),"warning_started_at":state.armed_at,"spawn_at":state.spawn_at,"hazard_index":state.hazard_index})
 return result
func snapshot()->Dictionary:return states.duplicate(true)
