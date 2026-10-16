extends SceneTree
## Player-equivalent test inputs only: no position, velocity, health, force,
## obstacle, inventory or battery mutation. Each run is bounded to 9000 ticks.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Free=preload("res://scripts/pilot_free_simulation_v2.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:
 if route().is_empty():check(false,"new route must author before physical tests");quit(1);return
 check(Profile.starter_design().size()==8,"unchanged starter has exactly eight parts")
 _coast()
 for heavy in [false,true]:
  for upper in [true,false]:_detour(upper,heavy)
 _overspeed_return()
 print("MOSSLIGHT_FLIGHT_DEV17 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func route(heavy:bool=false) -> Dictionary:
 var result:Dictionary=Profile.route(Content.fresh_catalog())
 if heavy and not result.is_empty():
  result.variant="重货件";result.weight=float(result.weight)*1.55;result.reward=int(result.reward)+55;result.deadline=88.0
 return result
func sim(heavy:bool=false):
 var value=Free.new();value.configure(Profile.starter_design(),[],route(heavy),42);return value
func _velocity_command(value,wanted:Vector2,boost:bool=false) -> Dictionary:
 var body:Dictionary=value.body_for_part(1)
 if body.is_empty():return Timeline.neutral()
 var wind:Vector2=Vector2(float(value.route.wind[0]),float(value.route.wind[1]))
 var accel:Vector2=(wanted-body.velocity)/.65-wind-Vector2(0.0,float(value.route.gravity))
 var force:float=0.0
 for p in body.parts:
  if p.type=="thruster" and p.alive:force+=float(p.param)*float(p.output_factor)
 var throttle:float=float(value.route.free_boost_throttle) if boost else float(value.route.free_drive_throttle)
 var input:Vector2=(accel*float(body.mass)/maxf(.001,force*throttle)).limit_length(1.0)
 var command:Dictionary=Timeline.neutral();command.axis_x_q=roundi(input.x*1000.0);command.axis_q=roundi(input.y*1000.0);command.boost=boost
 return command
func _command(value,target:Vector2,max_speed:float=9.0) -> Dictionary:
 var delta:Vector2=target-value.cargo_position()
 return _velocity_command(value,delta.normalized()*minf(max_speed,sqrt(delta.length()*3.0)))
func _step(value,command:Dictionary) -> void:
 value.set_free_flight_input(command.axis_x_q,command.axis_q,command.boost,command.active,command.device_id,command.brake);value.step(1.0/60.0)
func _record_step(value,timeline,tick:int,command:Dictionary) -> void:
 timeline.record(tick,command);_step(value,command)
func _measure(label:String,value,extras:Dictionary={}) -> void:
 var report:Dictionary={"status":value.status,"elapsed":value.elapsed,"position":[value.cargo_position().x,value.cargo_position().y],"energy_used":value.telemetry.get("energy_used",0.0),"energy_remaining":value.telemetry.get("energy_remaining",0.0),"integrity":value.telemetry.get("integrity",0.0),"contacts":value.telemetry.get("swept_contacts",0)}
 report.merge(extras);print("MOSSLIGHT_MEASURE ",label," ",JSON.stringify(report))
func _coast() -> void:
 var value=sim();var before:Vector2=value.cargo_position()
 for tick in range(60):_step(value,Timeline.neutral())
 var velocity:Vector2=value.body_for_part(1).velocity
 check(value.status=="running" and velocity.x>0.30 and velocity.y>0.15 and value.cargo_position().x>before.x and value.cargo_position().y>before.y,"unpowered coast exhibits real constant rightward wind and weak downward acceleration")
 check(float(value.telemetry.energy_used)==0.0,"environmental acceleration does not grant energy or fire idle nozzles")
func _replay(value,timeline,ticks:int,heavy:bool,label:String) -> void:
 var saved:Dictionary=JSON.parse_string(JSON.stringify({"route":value.route,"commands":timeline.snapshot(),"ticks":ticks}))
 var replay=Free.new();replay.configure(Profile.starter_design(),[],saved.route,42)
 var restored=Timeline.new()
 if not check_restore(restored,saved.commands,int(saved.ticks),label):return
 for tick in range(int(saved.ticks)):_step(replay,restored.state_at(tick))
 check(replay.status==value.status and replay.cargo_position()==value.cargo_position() and replay.telemetry.get("energy_used")==value.telemetry.get("energy_used") and replay.telemetry.get("energy_remaining")==value.telemetry.get("energy_remaining"),"exact saved-input trajectory/energy replay "+label)
 check(Content.validation_error(saved.route).is_empty() and float(saved.route.weight)==float(route(heavy).weight),"JSON replay retains exact authored content/commercial weight "+label)
func check_restore(timeline,commands:Array,ticks:int,label:String) -> bool:
 var ok:bool=timeline.restore(commands,ticks);check(ok,"saved six-field command timeline restores "+label);return ok
func _detour(upper:bool,heavy:bool) -> void:
 var value=sim(heavy);var timeline=Timeline.new();var frozen:Dictionary=value.route.duplicate(true)
 var y:float=-45.0 if upper else 10.0
 var targets:Array=[Vector2(58.0,y),Vector2(228.0,y),Content.DESTINATION]
 var phase:int=0;var ticks:int=0
 for tick in range(9000):
  if value.status!="running":break
  if phase<targets.size()-1 and value.cargo_position().distance_to(targets[phase])<2.0:phase+=1
  _record_step(value,timeline,tick,_command(value,targets[phase]));ticks+=1
 var label:String=("upper" if upper else "lower")+("_heavy" if heavy else "_standard")
 _measure(label,value,{"ticks":ticks,"parts":Profile.starter_design().size()})
 check(value.status=="success" and float(value.telemetry.get("integrity",0.0))==1.0,"eight-part starter delivers intact "+label)
 check(int(value.telemetry.get("swept_contacts",-1))==0,"wide detour clears actual rock bodies "+label)
 check(float(value.telemetry.get("energy_used",0.0))>0.0 and float(value.telemetry.get("energy_remaining",0.0))>=600.0,"delivery pays finite energy and retains at least10percent reserve "+label)
 check(value.route==frozen,"physics never mutates content snapshot "+label)
 _replay(value,timeline,ticks,heavy,label)
func _overspeed_return() -> void:
 var value=sim();var timeline=Timeline.new();var targets:Array=[Vector2(58.0,-45.0),Vector2(160.0,-45.0),Vector2(185.0,-25.0)]
 var phase:int=0;var ticks:int=0;var runup:bool=false;var returning:bool=false;var braking:bool=true
 var crossed_fast:bool=false;var fast_speed:float=0.0;var furthest_x:float=0.0;var reverse_recorded:bool=false
 for tick in range(9000):
  if value.status!="running":break
  var at:Vector2=value.cargo_position();var command:Dictionary
  if not runup:
   if phase<targets.size()-1 and at.distance_to(targets[phase])<2.0:phase+=1
   if phase==targets.size()-1 and at.distance_to(targets[phase])<2.0:runup=true
   command=_command(value,targets[phase])
  elif not returning:
   # Drive through the real capture circle faster than its limit, rather than
   # merely taking a scenic route past its x-coordinate. This is paid thrust.
   command=_velocity_command(value,Vector2(25.2,clampf((Content.DESTINATION.y-at.y)*1.5,-3.0,3.0)),true)
   if at.x>Content.DESTINATION.x+8.0:returning=true
  else:
   if braking and value.body_for_part(1).velocity.length()>.5:
    command=Timeline.neutral();command.brake=true
   else:
    braking=false;command=_command(value,Content.DESTINATION,6.0)
    reverse_recorded=reverse_recorded or int(command.axis_x_q)<0
  _record_step(value,timeline,tick,command);ticks+=1
  at=value.cargo_position();furthest_x=maxf(furthest_x,at.x)
  if value.status=="running" and at.distance_to(Content.DESTINATION)<=Content.DELIVERY_RADIUS:
   var speed:float=value.body_for_part(1).velocity.length()
   if speed>Content.MAX_DELIVERY_SPEED:crossed_fast=true;fast_speed=maxf(fast_speed,speed)
 _measure("overspeed_against_wind_return",value,{"ticks":ticks,"crossed_fast":crossed_fast,"capture_speed":fast_speed,"furthest_x":furthest_x,"negative_x_recorded":reverse_recorded})
 check(crossed_fast and fast_speed>Content.MAX_DELIVERY_SPEED,"real capture-circle overspeed is missed capture rather than terminal failure")
 check(furthest_x>Content.DESTINATION.x+38.0 and reverse_recorded and value.route.wind[0]>0.0,"paid recorded reverse thrust returns from downwind overshoot")
 check(value.status=="success" and float(value.telemetry.get("integrity",0.0))==1.0 and int(value.telemetry.get("swept_contacts",-1))==0,"eight-part starter returns intact after genuine overspeed")
 check(float(value.telemetry.get("energy_remaining",0.0))>=600.0,"overspeed correction retains at least10percent battery reserve")
 _replay(value,timeline,ticks,false,"overspeed_against_wind_return")
