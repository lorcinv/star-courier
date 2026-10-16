extends SceneTree
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Free=preload("res://scripts/pilot_free_simulation_v2.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Expanded=preload("res://scripts/parts_expanded.gd")
const LegacyMoon=preload("res://scripts/pilot_moon_profile.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:
 if _route().is_empty():
  check(false,"lunar route authoring failed before physical tests");quit(1);return
 _snapshot_rules()
 _light_delivery(false)
 _light_delivery(true)
 _drill_delivery()
 _shield_contact_delivery()
 print("LUNAR_OUTPOST_V2_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
func _route() -> Dictionary:return Profile.route(Content.fresh_catalog())
func _design(kind:String="light") -> Array:
 var design:Array=Profile.starter_design()
 if kind=="drill":design.append(Extreme.part(9,"drill",2,0,{"input_a":-1}))
 if kind=="shield":design.append(Extreme.part(9,"shield",-2,0,{"input_a":-1}))
 return design
func _sim(kind:String="light"):
 var sim=Free.new();sim.configure(_design(kind),[],_route(),42);return sim
func _command(sim,target:Vector2,max_speed:float=9.0) -> Dictionary:
 # Test pilot only. No state/health/energy/hazard mutation and no hidden runtime
 # autopilot: this emits the same quantized commands a player can record.
 var body:Dictionary=sim.body_for_part(1)
 if body.is_empty():return Timeline.neutral()
 var delta:Vector2=target-sim.cargo_position()
 var wanted:Vector2=delta.normalized()*minf(max_speed,sqrt(delta.length()*3.0))
 var accel:Vector2=(wanted-body.velocity)/.65-Vector2(0.0,float(sim.route.gravity))
 var force:float=0.0
 for p in body.parts:
  if p.type=="thruster" and p.alive:force+=float(p.param)*float(p.output_factor)
 var input:Vector2=(accel*float(body.mass)/maxf(.001,force*float(sim.route.free_drive_throttle))).limit_length(1.0)
 var state:Dictionary=Timeline.neutral();state.axis_x_q=roundi(input.x*1000.0);state.axis_q=roundi(input.y*1000.0)
 return state
func _step(sim,state:Dictionary) -> void:
 sim.set_free_flight_input(state.axis_x_q,state.axis_q,state.boost,state.active,state.device_id,state.brake)
 sim.step(1.0/60.0)
func _measure(label:String,sim) -> void:
 print("LUNAR_MEASURE ",label," ",JSON.stringify({"status":sim.status,"elapsed":sim.elapsed,"position":[sim.cargo_position().x,sim.cargo_position().y],"energy_used":sim.telemetry.get("energy_used",0.0),"energy_remaining":sim.telemetry.get("energy_remaining",0.0),"integrity":sim.telemetry.get("integrity",0.0),"contacts":sim.telemetry.get("swept_contacts",0),"drill_contacts":sim.telemetry.get("drill_contacts",0),"drill_damage":sim.telemetry.get("drill_damage",0),"impact_absorbed":sim.telemetry.get("impact_absorbed",0),"impact_shield_energy":sim.telemetry.get("impact_shield_energy",0)}))
func _snapshot_rules() -> void:
 var source:Dictionary=Content.fresh_catalog();var frozen:Dictionary=source.duplicate(true)
 var route:Dictionary=Profile.route(source)
 check(source==frozen and not route.is_empty(),"new lunar source authors without mutation")
 if route.is_empty():return
 check(Profile.validation_error(route).is_empty() and Content.validation_error(route).is_empty(),"registered lunar v2 satisfies controller and content validators")
 check(route.control_version=="pilot-free-v2" and route.id==6 and route.route_kind=="lunar","new lunar has explicit separate controller and catalog identity")
 check(route.hazards.size()==3 and route.pilot_gates.is_empty() and float(route.gravity)==.20,"three actual rocks and nonzero low gravity, no mandatory gates")
 check(Content.validation_error(JSON.parse_string(JSON.stringify(route))).is_empty(),"full new lunar snapshot survives JSON exactly")
 check(Profile.route(route).is_empty() and Content.author(route).is_empty(),"saved content cannot be reauthored")
 var runtime:Dictionary=route.duplicate(true)
 runtime.contract_id="D2-B";runtime.status="available";runtime.accepted_day=2
 check(Content.validation_error(runtime).is_empty() and Profile.validation_error(runtime).is_empty(),"valid runtime StringName commercial keys preserve exact physical rules")
 var changed:Dictionary=route.duplicate(true);changed[123]=true
 check(not Content.validation_error(changed).is_empty() and not Profile.validation_error(changed).is_empty(),"numeric dictionary keys remain invalid")
 changed=route.duplicate(true);changed[Vector2.ZERO]=true
 check(not Content.validation_error(changed).is_empty(),"object/vector dictionary keys remain invalid")
 changed=route.duplicate(true);changed["unexpected_value"]=StringName("not-a-JSON-string")
 check(not Content.validation_error(changed).is_empty(),"StringName values are not admitted by key compatibility")
 changed=route.duplicate(true);changed.gravity=NAN
 check(not Profile.validation_error(changed).is_empty(),"nonfinite environment value remains invalid")
 changed=route.duplicate(true);changed.hazards[0].health=INF
 check(not Profile.validation_error(changed).is_empty(),"nonfinite nested hazard value remains invalid")
 changed=route.duplicate(true);changed.pirate_sidejob_schema=1
 check(not Content.validation_error(changed).is_empty() and not Profile.validation_error(changed).is_empty(),"pirate side-job markers cannot mix into new lunar content")
 changed=route.duplicate(true);changed.id=5
 check(not Content.validation_error(changed).is_empty() and not Profile.validation_error(changed).is_empty(),"reserved pirate catalog ID5 remains protected")
 changed=route.duplicate(true);changed.hazards[0].health=41.0
 check(not Profile.validation_error(changed).is_empty(),"altered ore geometry/health fails closed")
 changed=route.duplicate(true);changed.hazards[0].position=[0.0,0.0]
 check(not Profile.validation_error(changed).is_empty(),"position alias cannot override saved rock placement")
 changed=route.duplicate(true);changed.erase("lunar_schema")
 check(Content.has_markers(changed) and not Profile.validation_error(changed).is_empty(),"partial lunar markers cannot fall through generic route")
 changed=route.duplicate(true)
 for key in changed.keys():
  if str(key).begins_with("lunar_"):changed.erase(key)
 changed.route_profile="generic";changed.route_kind="ordinary";changed.destination_id="ordinary"
 check(Content.has_markers(changed) and not Profile.validation_error(changed).is_empty(),"nested lunar hazard marker cannot bypass its complete route receipt")
 changed=route.duplicate(true);changed.moon_schema=1
 check(not Profile.validation_error(changed).is_empty(),"legacy Moon marker mixed into v2 fails closed")
 changed=route.duplicate(true);changed.lunar_receiver.entry="left"
 check(not Profile.validation_error(changed).is_empty(),"one-way receiving rule cannot replace any-direction snapshot")
 var old:Dictionary=LegacyMoon.route({"id":4,"weight":2.8});var old_copy:Dictionary=old.duplicate(true)
 check(Profile.route(old).is_empty() and old==old_copy,"historical Moon source is untouched and cannot be relabeled")
 check(not Caps.group_available("moon") and not Caps.group_available("wormhole") and not Caps.group_available("protected-bird"),"historical incomplete scene caps remain closed")
 var spec:Dictionary=route.lunar_receiver
 var platform_top:float=Content.DELIVERY_RADIUS+float(spec.deck_clearance_m)-149.0*float(spec.art_width_m)/279.0
 check(platform_top>Content.DELIVERY_RADIUS+1.0,"entire reused platform stays below true capture circle")
func _light_delivery(from_right:bool) -> void:
 var sim=_sim();var timeline=Timeline.new();var ticks:int=0
 var targets:Array=[Vector2(65.0,-38.0),Vector2(195.0,-63.0),Content.DESTINATION]
 if from_right:targets=[Vector2(65.0,-38.0),Vector2(195.0,-63.0),Vector2(286.0,-63.0),Vector2(292.0,-40.0),Content.DESTINATION]
 var phase:int=0;var furthest_x:float=0.0;var negative_recorded:bool=false
 for tick in range(7200):
  if sim.status!="running":break
  if phase<targets.size()-1 and sim.cargo_position().distance_to(targets[phase])<2.0:phase+=1
  var command:Dictionary=_command(sim,targets[phase])
  var recorded:bool=timeline.record(tick,command)
  if tick==0:check(recorded,"record full two-axis lunar command")
  negative_recorded=negative_recorded or int(command.axis_x_q)<0
  _step(sim,command);ticks+=1;furthest_x=maxf(furthest_x,sim.cargo_position().x)
 _measure("light_return_right" if from_right else "light_upper_detour",sim)
 check(sim.status=="success" and float(sim.telemetry.get("integrity",0.0))==1.0,"light lunar route delivers intact "+str(from_right))
 check(int(sim.telemetry.get("swept_contacts",-1))==0,"light lunar route clears actual rock bodies "+str(from_right))
 check(float(sim.telemetry.get("energy_used",0.0))>0.0 and float(sim.telemetry.get("energy_remaining",0.0))>0.0,"light lunar route pays finite energy "+str(from_right))
 if from_right:check(furthest_x>Content.DESTINATION.x+30.0 and negative_recorded,"real overshoot and negative-X return uses recorded input")
 var saved:Dictionary=JSON.parse_string(JSON.stringify({"route":sim.route,"commands":timeline.snapshot(),"ticks":ticks}))
 var replay=Free.new();replay.configure(_design(),[],saved.route,42)
 var restore=Timeline.new();check(restore.restore(saved.commands,int(saved.ticks)),"new lunar input recording restores")
 for tick in range(int(saved.ticks)):_step(replay,restore.state_at(tick))
 check(replay.status==sim.status and replay.cargo_position()==sim.cargo_position() and replay.telemetry.get("energy_used")==sim.telemetry.get("energy_used"),"new lunar delivery and energy replay exactly "+str(from_right))
func _drill_delivery() -> void:
 var sim=_sim("drill");var snapshot:Dictionary=sim.route.duplicate(true)
 var target_index:int=0
 for tick in range(9000):
  if sim.status!="running":break
  while target_index<2 and float(sim.obstacles[target_index].health)<=0.0:target_index+=1
  if target_index>=2:_step(sim,_command(sim,Content.DESTINATION));continue
  if not bool(sim.parts[9].alive) or sim.body_for_part(9).is_empty():break
  var h:Dictionary=sim.obstacles[target_index]
  var head:Vector2=sim.part_world_position(9)+Vector2.RIGHT.rotated(float(sim.body_for_part(9).angle)+float(sim.parts[9].local_angle))*Expanded.DRILL_HEAD_OFFSET
  var gap:float=h.position.x-float(h.radius)-Expanded.DRILL_HEAD_RADIUS-head.x
  var speed:float=clampf(sqrt(maxf(0.0,gap)*1.5),.35,8.0)
  _step(sim,_command(sim,h.position,speed))
 _measure("paid_drill",sim)
 check(sim.status=="success" and bool(sim.parts[9].alive),"drill build physically breaches lunar ore and delivers")
 check(float(sim.obstacles[0].health)<=0.0 and float(sim.obstacles[1].health)<=0.0 and float(sim.telemetry.get("drill_damage",0.0))>0.0,"both authored ore rocks receive real cutting damage")
 check(float(sim.telemetry.get("drill_energy_used",0.0))>0.0 and float(sim.telemetry.get("energy_remaining",0.0))>0.0,"lunar cutting costs real finite battery energy")
 check(sim.route==snapshot,"live lunar rock destruction never mutates saved content")
func _shield_contact_delivery() -> void:
 var sim=_sim("shield");var touched:bool=false;var phase:int=0
 var targets:Array=[Vector2(80.0,-39.0),Vector2(195.0,-48.0),Content.DESTINATION]
 for tick in range(9000):
  if sim.status!="running":break
  if not touched:
   _step(sim,_command(sim,Vector2(95.0,-15.0),4.0))
   touched=int(sim.telemetry.get("swept_contacts",0))>0
  else:
   if phase<targets.size()-1 and sim.cargo_position().distance_to(targets[phase])<2.0:phase+=1
   _step(sim,_command(sim,targets[phase],8.0))
 _measure("paid_shield",sim)
 check(touched and float(sim.telemetry.get("impact_absorbed",0.0))>0.0,"shield absorbs part of a real lunar rock impact")
 check(float(sim.telemetry.get("impact_shield_energy",0.0))>0.0,"shield impact protection consumes real electrical energy")
 check(sim.status=="success" and float(sim.telemetry.get("energy_remaining",0.0))>0.0,"shield-equipped delivery survives physical impact and detour")
