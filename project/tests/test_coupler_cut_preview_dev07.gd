extends SceneTree
## Presentation contract plus actual current/legacy fixed-step cuts; no direct
## _cut/_act or velocity/body edits substitute for the A/B runtime witness.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const View=preload("res://scripts/selected_device_presentation_v2.gd")
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const OldSim=preload("res://scripts/pilot_free_simulation_v1.gd")
const OldProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
class MissingBodyProbe extends RefCounted:
 var route:Dictionary={"control_version":"pilot-free-v2"}
 var pilot_device_id:int=5
 var parts:Dictionary={5:{"id":5,"type":"coupler"}}
 func selectable_device_ids() -> Array:return [5]
 func body_for_part(_id:int) -> Dictionary:return {}

var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 p.merge(extra,true);return p
func design(bridge:bool=false) -> Array:
 return [part(1,"cargo",0),part(2,"battery",-1),part(3,"thruster",0,-1,{"param":28.0}),part(4,"thruster",0,1,{"param":28.0}),part(5,"coupler",1,0,{"input_a":-2,"target":6}),part(6,"beam",2),part(7,"beam",1,1),part(8,"beam",1 if bridge else 2,2 if bridge else 1)]
func make_sim(parts:Array,legacy:bool=false):
 var route:Dictionary=(OldProfile if legacy else Profile).route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var sim=OldSim.new() if legacy else Sim.new();sim.configure(parts,[],route,42);return sim
func object_state(value) -> PackedByteArray:
 # Cover every inherited script variable, including solver caches, accumulators,
 # body maps, effects, incidents, controls, telemetry and replay cursor state.
 var result:Dictionary={}
 for info in value.get_property_list():
  if int(info.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
   var item=value.get(info.name)
   result[info.name]={"seed":item.seed,"state":item.state} if item is RandomNumberGenerator else item
 return var_to_bytes(result)
func select(sim,id:int=5,active:bool=false,x:int=0,legacy:bool=false) -> void:
 if legacy:sim.set_free_flight_input(x,0,false,active)
 else:sim.set_free_flight_input(x,0,false,active,id)
func expect_workshop(parts:Array,id:int,ready:bool,fragment:String,label:String,pilot:bool=true,launcher:bool=false) -> Dictionary:
 var chosen:Dictionary={}
 for p in parts:
  if int(p.id)==id:chosen=p
 var before:PackedByteArray=var_to_bytes(parts)
 var actual:Dictionary=Policy.readiness(chosen,parts,pilot,launcher,"pilot-free-v2")
 check(actual.ready==ready and fragment in str(actual.text),label)
 check(var_to_bytes(parts)==before,label+" is byte-read-only")
 return actual
func expect_live(sim,expected:String,label:String) -> void:
 var before:PackedByteArray=object_state(sim)
 for repeat in 5:check(View.state(sim).status==expected,label+" query "+str(repeat))
 check(object_state(sim)==before,label+" leaves all solver state and RNG exact")
func _initialize() -> void:
 _workshop();_live_topology();_routing();_actual_ab_and_replay()
 print("COUPLER_CUT_PREVIEW_DEV07 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
func _workshop() -> void:
 expect_workshop(Profile.starter_design(),8,true,"断开后仍相连","starter keeps legal battery socket with bypass")
 for bridge in [false,true]:
  var d:Array=design(bridge);var expected:String="断开后会分离" if bridge else "断开后仍相连"
  var ready:Dictionary=expect_workshop(d,5,true,expected,"A/B workshop "+str(bridge))
  check(ready.target_id==6 and 6 in ready.valid_targets and not ready.warning,"preview preserves valid target and readiness")
  d.append(part(10,"beam",20));d.append(part(11,"beam",21))
  expect_workshop(d,5,true,expected,"preexisting separate island is not counted as cut outcome")
 var d:Array=design();d[4].input_a=-1
 expect_workshop(d,5,false,"尚未设置触发","unset source wins over topology")
 d[4].input_a=999;expect_workshop(d,5,false,"控制零件已断开","missing source wins over topology")
 d[4].input_a=-2;d[0].x=-20
 expect_workshop(d,5,false,"未连接货物","cockpit disconnection wins over topology")
 d=design();expect_workshop(d,5,false,"尚未设置触发","cockpit sentinel unavailable on autonomous route",false)
 d[4].target=2;expect_workshop(d,5,false,"先选择一个相邻零件","remote explicit target never substituted")
 for saved in [999,5,-1]:
  d=design();d[4].target=saved
  var ready:Dictionary=expect_workshop(d,5,true,"断开后仍相连","design fallback uses resolved socket "+str(saved))
  check(ready.target_id==1 and ready.warning==(saved>=0) and ("原目标不可用" in str(ready.text))==(saved>=0),"missing/self warning remains alongside outcome")
 d=design();d[4].x=50
 expect_workshop(d,5,false,"先选择一个相邻零件","missing adjacent socket is blocked")
 expect_workshop(design(),5,false,"发射台无法使用","launcher compatibility text untouched",true,true)
func _live_topology() -> void:
 var sim=make_sim(Profile.starter_design());select(sim,8)
 expect_live(sim,"断开后仍相连","starter actual current graph")
 for bridge in [false,true]:
  sim=make_sim(design(bridge));select(sim)
  expect_live(sim,"断开后会分离" if bridge else "断开后仍相连","A/B actual graph")
  sim.parts[2].energy=0.0
  expect_live(sim,"断开后会分离" if bridge else "断开后仍相连","mechanical cut needs zero energy")
 # Another real selected coupler opens the bypass before the main one is used.
 var d:Array=design();d[7]=part(8,"coupler",2,1,{"input_a":-2,"target":6})
 sim=make_sim(d);select(sim,8,true);sim.step(sim.FIXED_DT);select(sim,5,false)
 check(not sim._linked(8,6) and sim._linked(5,6) and sim.bodies.size()==1,"earlier real cut removes only the alternate socket")
 expect_live(sim,"断开后会分离","live graph never rebuilds broken bypass from original grid")
 check("断开后仍相连" in Policy.readiness(d[4],d,true,false).text,"unchanged blueprint intentionally retains original cycle")
 for flag in ["alive","delivered","body_id"]:
  sim=make_sim(design());select(sim)
  sim.parts[8][flag]=false if flag=="alive" else true if flag=="delivered" else -77
  expect_live(sim,"断开后会分离","bypass excludes invalid member "+flag)
 sim=make_sim(design());select(sim);sim.parts[5].target=2
 expect_live(sim,"未连接目标","remote explicit live target retains blocker")
 for saved in [999,5,-1]:
  sim=make_sim(design());select(sim);sim.parts[5].target=saved
  expect_live(sim,"断开后仍相连","existing live fallback "+str(saved))
 for flag in ["alive","delivered"]:
  sim=make_sim(design());select(sim);sim.parts[6][flag]=false if flag=="alive" else true
  check(sim._target(sim.parts[5],sim.body_for_part(5)).id==1,"dead/delivered explicit target retains solver fallback")
  expect_live(sim,"断开后仍相连","dead/delivered target fallback "+flag)
 sim=make_sim(design());select(sim);sim.links=[]
 expect_live(sim,"未连接目标","no actual socket remains invalid")
 sim=make_sim(design());select(sim);sim.parts[6].body_id=-77
 expect_live(sim,"未连接目标","cross-body target remains invalid")
 for flag in ["alive","delivered"]:
  sim=make_sim(design());select(sim);sim.parts[5][flag]=false if flag=="alive" else true
  expect_live(sim,"已失联","invalid selected device "+flag)
 var detached:Array=design();detached[0].x=-20
 sim=make_sim(detached);select(sim);expect_live(sim,"已失联","live device on a real cargo-free body")
 check(View.state(MissingBodyProbe.new()).status=="已失联","existing empty-body guard still blocks before topology")
 sim=make_sim(design());select(sim,999)
 expect_live(sim,"已失联","missing selection never substitutes device")
 # Duplicate/reversed socket occurrences are removed together by frozen _cut.
 sim=make_sim(design(true));select(sim);sim.links.append({"a":6,"b":5,"strength":32.0})
 expect_live(sim,"断开后会分离","duplicate reverse target links are both ignored")
 var islands:Array=design();islands.append(part(10,"beam",20));islands.append(part(11,"beam",21))
 sim=make_sim(islands);select(sim);expect_live(sim,"断开后仍相连","other current bodies do not change result")
func _routing() -> void:
 for legacy in [false,true]:
  var d:Array=design(true);d[4].input_a=9;d.append(part(9,"not_gate",1,-1))
  var ready:Dictionary=expect_workshop(d,5,true,"等待原控制信号；断开后会分离","wired original source wording")
  check(not "按键" in ready.text and not "空格" in ready.text,"wired prediction never claims manual control")
  var sim=make_sim(d,legacy);select(sim,5,false,0,legacy)
  if legacy:check(View.state(sim).is_empty(),"legacy selected-device projection remains absent")
  else:expect_live(sim,"已失联","externally wired device is never manually selectable")
  sim.step(sim.FIXED_DT)
  check(not sim._linked(5,6) and sim.parts[5].body_id!=sim.parts[6].body_id,"original not-gate signal drives real current/legacy cut "+str(legacy))
  d=design(true);sim=make_sim(d,legacy);select(sim,5,true,0,legacy);sim.step(sim.FIXED_DT)
  check(not sim._linked(5,6),"manual current/legacy route still cuts "+str(legacy))
 var sim=make_sim(design());sim.route.control_version="pilot-free-v1"
 check(View.state(sim).is_empty(),"route identity continues gating selected UI")
func _actual_ab_and_replay() -> void:
 for bridge in [false,true]:
  var d:Array=design(bridge);var saved:PackedByteArray=var_to_bytes(d)
  var sim=make_sim(d);var control=make_sim(d);var replay=make_sim(d);var timeline=Timeline.new()
  var edges:int=sim.links.size();var energy:float=sim.total_energy();var before_distance:float=sim._part_position(sim.parts[6]).distance_to(sim.cargo_position())
  for tick in range(122):
   var command:Dictionary={"axis_x_q":-1000 if tick>=2 else 0,"axis_q":0,"boost":false,"active":tick==0,"device_id":5,"brake":false}
   timeline.record(tick,command)
   select(sim,5,command.active,command.axis_x_q);select(control,5,command.active,command.axis_x_q)
   var before:PackedByteArray=object_state(sim);var record_before:PackedByteArray=object_state(timeline)
   for query in 3:View.state(sim);Policy.readiness(d[4],d,true,false)
   if tick in [0,1,121]:check(object_state(sim)==before and object_state(timeline)==record_before,"preview is full solver/replay read-only at tick "+str(tick))
   sim.step(sim.FIXED_DT);control.step(control.FIXED_DT)
   if tick==0:
    check(sim.links.size()==edges-1 and not sim._linked(5,6),"A/B tick cuts exactly the chosen edge "+str(bridge))
    check(sim.bodies.size()==(2 if bridge else 1) and (sim.parts[5].body_id==sim.parts[6].body_id)==not bridge,"A/B predicted body separation is real "+str(bridge))
    check(sim.total_energy()==energy and sim.telemetry.energy_used==0.0,"cut has exact zero energy cost")
    check(sim._part_velocity(sim.parts[6])==Vector2.ZERO,"cut adds no hidden ejection impulse")
    expect_live(sim,"未连接目标","postcut graph reports consumed direct socket")
    if bridge:check(sim.body_for_part(6).mass==0.5 and sim.body_for_part(6).parts.size()==1,"B separates only a 0.5kg beam")
  check(object_state(sim)==object_state(control),"all-state equality with never-previewed control A/B "+str(bridge))
  var stored:Array=timeline.snapshot();var restored=Timeline.new();check(restored.restore(JSON.parse_string(JSON.stringify(stored)),122),"recorded command stream restores")
  for tick in range(122):
   var command:Dictionary=restored.state_at(tick);select(replay,5,command.active,command.axis_x_q);replay.step(replay.FIXED_DT)
  check(object_state(sim)==object_state(replay),"bit-exact replay with previews versus no previews A/B "+str(bridge))
  var body_id:int=int(sim.parts[1].body_id)
  check(sim.status=="running" and sim.parts[2].body_id==body_id and sim.parts[3].body_id==body_id and sim.parts[4].body_id==body_id and sim._available_energy(sim.body_for_part(1),1)>0.0,"A/B cargo retains battery and both thrusters after drive")
  check(sim.parts[3].pilot_force.length()>0.0 and sim.parts[4].pilot_force.length()>0.0,"both retained thrusters deliver actual paid force")
  check(sim.links.size()==edges-1,"no unrequested socket lost during A/B drive")
  if bridge:check(sim._part_position(sim.parts[6]).distance_to(sim.cargo_position())>before_distance,"B relative motion comes from subsequent left thrust")
  else:check(sim.parts[6].body_id==body_id,"A target beam still follows same rigid body")
  check(var_to_bytes(d)==saved,"actual cut/replay leaves design exact")
  print("AB_MEASURE bridge=%s links=%d bodies=%d cargo_energy=%.9f target_mass=%.9f distance=%.9f"%[bridge,sim.links.size(),sim.bodies.size(),sim._available_energy(sim.body_for_part(1),1),sim.body_for_part(6).mass,sim._part_position(sim.parts[6]).distance_to(sim.cargo_position())])
