extends "res://scripts/pilot_delivery_simulation_v3.gd"
## New v4 only. External altitude fields are applied before the inherited force
## integration; committed route dictionaries and all older solvers stay unchanged.
const VerticalProfile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const VerticalMeteors=preload("res://scripts/delivery_ascent_meteors_v1.gd")
var ascent_route_error:String=""
var ascent_meteors=VerticalMeteors.new()
var _ascent_wind_delta:Dictionary={}

func configure(design:Array,launcher:Array,route_data:Dictionary,random_seed:int=1)->void:
 ascent_route_error=VerticalProfile.validation_error(route_data)
 ascent_meteors.configure(route_data);_ascent_wind_delta.clear()
 if not ascent_route_error.is_empty():
  # Let the inherited invalid-route branch clear every old runtime collection.
  super.configure([],[],{},random_seed)
  route=route_data.duplicate(true);free_route_error=ascent_route_error;delivery_route_error=ascent_route_error
  events=[ascent_route_error];telemetry={"control_version":VerticalProfile.VERSION,"route_error":ascent_route_error,"launch_released":false,"delivery_qualified":false,"delivery_failure":"invalid_route"}
  return
 super.configure(design,launcher,VerticalProfile.compatibility_route(route_data),random_seed)
 route=route_data.duplicate(true)
 _refresh_telemetry()

func environment_at(position:Vector2)->Dictionary:return VerticalProfile.environment_at(route,position)

func _tick(dt:float)->void:
 if _graph_dirty:_rebuild_bodies()
 ascent_meteors.advance(self)
 _ascent_wind_delta.clear()
 for body in bodies:
  var field:Dictionary=environment_at(body.position)
  var wind_delta:Vector2=Vector2(field.wind)*dt
  body.velocity+=(Vector2(0.0,float(field.gravity))*dt+wind_delta)
  var before_drag:float=0.5*float(body.mass)*body.velocity.length_squared()
  body.velocity*=exp(-float(field.drag)*dt/maxf(EPS,float(body.mass)))
  telemetry.heat=float(telemetry.heat)+maxf(0.0,before_drag-0.5*float(body.mass)*body.velocity.length_squared())
  for p in body.parts:
   if p.type=="cargo":_ascent_wind_delta[p.id]=wind_delta
 # route.gravity/wind/pilot_drag are explicitly zero in this protocol, so the
 # inherited integrator never adds a second gravity/wind/drag acceleration.
 super._tick(dt)

func _collisions()->void:
 # Freefall is not a compressive load. Only the actual non-gravity wind impulse
 # reaches the cargo damage model here; thruster/contact loads remain inherited.
 for id in _ascent_wind_delta:
  if parts.has(id):_pulse_damage(parts[id],_ascent_wind_delta[id],_tick_dt,"ascent_wind_load")
 super._collisions()

func preview_launcher(angle_degrees:float=0.0,power_fraction:float=1.0)->Dictionary:
 var preview:Dictionary=super.preview_launcher(angle_degrees,power_fraction)
 if not preview.get("can_release",false):return preview
 var b:Dictionary=_cargo_body()
 if b.is_empty():return preview
 var position:Vector2=b.position;var offset:Vector2=cargo_position()-position
 var velocity:Vector2=preview.velocity;var mass:float=maxf(EPS,float(b.mass))
 var trajectory:Array=[position+offset]
 # Same fixed-step field sample and semi-implicit position order as a coasting
 # launch, not a differently scaled art parabola. No thrust/hazard prediction.
 for tick in range(360):
  var field:Dictionary=environment_at(position)
  velocity+=(Vector2(0.0,float(field.gravity))+Vector2(field.wind))*FIXED_DT
  velocity*=exp(-float(field.drag)*FIXED_DT/mass)
  position+=velocity*FIXED_DT
  if (tick+1)%15==0:trajectory.append(position+offset)
 preview.trajectory=trajectory;preview.environment=environment_at(b.position)
 preview.thrust_to_weight=_thrust_to_weight(b,float(preview.environment.gravity))
 if float(preview.thrust_to_weight)<1.0:
  preview.warning="当前普通推力不足以持续克服近地重力；弹射只能提供短暂起步，请减重或增加有效推进。"
 return preview

func release_launcher(angle_degrees:float=0.0,power_fraction:float=1.0)->Dictionary:
 var predicted:Dictionary=preview_launcher(angle_degrees,power_fraction)
 var released:Dictionary=super.release_launcher(angle_degrees,power_fraction)
 if released.get("released",false) and predicted.has("trajectory"):released.trajectory=predicted.trajectory
 return released

func _thrust_to_weight(body:Dictionary,gravity:float)->float:
 if body.is_empty():return 0.0
 var force:float=0.0
 for p in body.parts:
  if p.type=="thruster" and p.alive and _enabled(p) and _available_energy(body,p.id)>EPS:force+=float(p.param)*float(p.output_factor)*float(route.get("free_drive_throttle",0.72))
 return force/maxf(EPS,float(body.mass)*maxf(0.001,gravity))

func _check_status()->void:
 var altitude:float=float(route.background_ground_y_m)-cargo_position().y
 if altitude < -float(route.ascent_return_below_ground_m):
  status="failed";telemetry.delivery_failure="returned_to_ground";telemetry.free_failure="returned_to_ground";telemetry.delivery_qualified=false
  _log("飞船已落回起飞区下方，本次登月结束；存活部件救回，实际费用照常结算。")
  return
 super._check_status()

func _refresh_telemetry()->void:
 super._refresh_telemetry()
 telemetry.control_version=VerticalProfile.VERSION;telemetry.input_schema=VerticalProfile.INPUT_SCHEMA
 var field:Dictionary=environment_at(cargo_position())
 telemetry.altitude_m=field.altitude_m;telemetry.ascent_phase=field.phase;telemetry.environment=field.duplicate(true)
 telemetry.thrust_to_weight=_thrust_to_weight(_cargo_body(),float(field.gravity))
 telemetry.ascent_warnings=ascent_meteors.cues(self)
 telemetry.ascent_event_state=ascent_meteors.snapshot()
 if not telemetry.has("ascent_meteors_spawned"):telemetry.ascent_meteors_spawned=0
 telemetry.ascent_return_warning=float(field.altitude_m)<0.0
