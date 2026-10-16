extends SceneTree
## Focused policy + existing solver contract. Synthetic fixtures, not native input.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const OldSim=preload("res://scripts/pilot_free_simulation_v1.gd")
const OldProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 p.merge(extra,true);return p
func design(source:int=-2) -> Array:
 return [part(1,"cargo",0),part(2,"battery",-1),part(3,"drill",1,0,{"input_a":source})]
func make_sim(pieces:Array,old:bool=false):
 var route:Dictionary=OldProfile.route(Extreme.route({"weight":1.0})) if old else Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var sim=OldSim.new() if old else Sim.new();sim.configure(pieces,[],route,42);return sim
func step(sim,ticks:int,held:bool=false,id:int=3) -> void:
 for tick in ticks:
  if sim.status!="running":break
  sim.set_free_flight_input(0,0,false,held,id);sim.step(1.0/60.0)
func _initialize() -> void:
 policy();read_only();runtime()
 print("DRILL_HOLD_CONTROL_DEV05 passed=%d failed=%d native_input=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
func policy() -> void:
 var fresh:Dictionary=Policy.new_part(3,"drill",1,0,design(),false,true)
 check(fresh.input_a==-1 and fresh.size()==9,"new placement keeps original automatic default and nine-field schema")
 check(not "drill" in Policy.EDGE and not "drill" in Policy.WAIT,"drill remains continuous held, never edge-triggered")
 var before:Dictionary=fresh.duplicate(true)
 check(Policy.convenience_source(fresh,true,false,"pilot-free-v2")=={"label":"改为按住启动","source":-2},"only explicit current craft offers automatic to held")
 check(fresh==before,"offering the held edit never applies it")
 fresh.input_a=-2
 check(Policy.convenience_source(fresh,true,false,"pilot-free-v2")=={"label":"改为自动运行","source":-1},"held drill offers existing explicit automatic reset")
 check("按住空格 / A" in Policy.trigger_text(fresh,design(),true,false,"pilot-free-v2"),"current held drill explains held rather than repeat-edge input")
 for version in ["","autonomous-v5","pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-pirate-drill-v1","pilot-pirate-drill-v2","pilot-free-v1","future-v99"]:
  fresh.input_a=-1
  check(Policy.convenience_source(fresh,true,false,version).is_empty(),version+" receives no new held option")
  fresh.input_a=-2
  check(Policy.convenience_source(fresh,true,false,version)=={"label":"改为自动运行","source":-1},version+" preserves existing explicit auto reset")
 fresh.input_a=-1
 check(Policy.convenience_source(fresh,true,false).is_empty(),"omitted version never assumes current protocol")
 check(Policy.convenience_source(fresh,false,false,"pilot-free-v2").is_empty(),"non-pilot context cannot opt in to cockpit hold")
 check(Policy.convenience_source(fresh,true,true,"pilot-free-v2").is_empty(),"saved unsupported launcher drill receives no new held option")
 fresh.input_a=-2
 check(Policy.convenience_source(fresh,true,true,"pilot-free-v2").source==-1,"launcher retains only its pre-existing explicit auto reset")
 for source in [6,999,-3]:
  fresh.input_a=source
  check(Policy.convenience_source(fresh,true,false,"pilot-free-v2")=={"label":"改为自动运行","source":-1},"saved source %d retains existing explicit reset, never new manual rewiring"%source)
  check(fresh.input_a==source,"proposal keeps original saved source %d"%source)
 check(Policy.convenience_source(part(5,"coupler",0),true,false,"pilot-free-v2").label=="改为按键触发","existing edge-device convenience is unchanged")
 check(Policy.convenience_source(part(5,"thruster",0),true,false,"pilot-free-v2").is_empty(),"automatic thruster has no new manual control")
 check("60 J/s" in Policy.detail("drill") and Parts.DRILL_POWER==60.0,"unchanged exact drill cost remains disclosed")
func read_only() -> void:
 for source in [-1,-2,6,999,-3]:
  var saved:Dictionary={"design":design(source),"launcher":[part(10,"drill",0,0,{"input_a":source})],"contract":{"control_version":"pilot-free-v1","contract_id":"retained"},"settings":{"opaque":[3.125,"keep"]}}
  saved.design[2].input_b=77;saved.design[2].target=55;saved.design[2].param=2.125
  var raw:String=JSON.stringify(saved,"",true,true)
  var restored:Dictionary=JSON.parse_string(raw);var bytes:PackedByteArray=var_to_bytes(restored)
  for version in ["pilot-free-v2","pilot-free-v1","autonomous-v5",""]:
   for launcher in [false,true]:
    var pieces:Array=restored.launcher if launcher else restored.design
    var p:Dictionary=pieces[0] if launcher else pieces[2]
    for repetition in 3:
     Policy.convenience_source(p,true,launcher,version);Policy.trigger_text(p,pieces,true,launcher,version)
     Policy.local_controls(p,launcher);Policy.readiness(p,pieces,true,launcher)
  check(var_to_bytes(restored)==bytes and JSON.stringify(saved,"",true,true)==raw,"load/inspection projections preserve all saved fields for source %d"%source)
func runtime() -> void:
 var auto=make_sim(design(-1));step(auto,60)
 check(auto.status=="running" and absf(auto.telemetry.drill_energy_used-60.0)<.001,"unchanged automatic drill still pays 60 J per idle second")
 check(not 3 in auto.selectable_device_ids(),"automatic drill does not steal a selectable device slot")
 var pieces:Array=design();var before:PackedByteArray=var_to_bytes(pieces)
 var manual=make_sim(pieces);manual.body_for_part(1).velocity=Vector2(3,-1)
 var start:Vector2=manual.cargo_position();step(manual,60)
 check(manual.status=="running" and manual.cargo_position().distance_to(start)>3.0 and manual.telemetry.energy_used==0.0,"manual drill coasts idle for one second without spending energy")
 check(3 in manual.selectable_device_ids(),"held drill uses existing selected-device registry")
 step(manual,60,true)
 check(absf(manual.telemetry.drill_energy_used-60.0)<.001 and manual.parts[3].drill_power_ratio>0.0,"holding selected drill continuously pays 60 J per second")
 var energy:float=manual.telemetry.energy_used;step(manual,60)
 check(manual.telemetry.energy_used==energy and manual.parts[3].drill_power_ratio==0.0,"release stops motor and energy cost on the next tick")
 check(var_to_bytes(pieces)==before,"simulation configure and held input leave source blueprint exact")
 var cutter=make_sim(design())
 cutter.obstacles.append({"position":cutter.part_world_position(3)+Vector2(1.255,0),"radius":.8,"health":80.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO})
 step(cutter,60,true)
 check(cutter.obstacles[0].health<=.0001 and cutter.telemetry.drill_damage>79.9 and absf(cutter.telemetry.drill_energy_used-60.0)<.001,"held cutter uses unchanged forward-contact damage and motor cost")
 var devices:Array=design();devices.append(part(4,"teleporter",0,1,{"input_a":-2,"param":8.0}));devices.append(part(5,"drill",1,1,{"input_a":-2}))
 var switching=make_sim(devices);step(switching,1,true,3)
 check(switching.parts[3].drill_power_ratio>0.0 and switching.parts[5].drill_power_ratio==0.0,"only the drill selected on press runs")
 energy=switching.telemetry.energy_used;step(switching,4,true,5)
 check(switching.parts[3].drill_power_ratio==0.0 and switching.parts[5].drill_power_ratio==0.0 and switching.telemetry.energy_used==energy,"switching to another drill while held cannot manufacture activation")
 step(switching,4,true,4)
 check(int(switching.telemetry.get("free_teleport_count",0))==0 and switching.telemetry.energy_used==energy,"switching to edge device while held cannot fire it")
 step(switching,1,false,4);step(switching,1,true,4)
 check(int(switching.telemetry.get("free_teleport_count",0))==1,"release and fresh press still activate the newly selected device")
 step(switching,1,false,5);step(switching,4,true,5)
 check(switching.parts[5].drill_power_ratio>0.0 and switching.parts[3].drill_power_ratio==0.0,"fresh press can run newly selected drill safely")
 switching.set_pilot_input(0,false,false)
 check(not switching._enabled(switching.parts[5]),"existing pause/focus clear stops held drill authority")
 var detached=make_sim(design());detached._cut(1,3);step(detached,1,true,3)
 check(detached.parts[3].drill_power_ratio==0.0 and not 3 in detached.selectable_device_ids(),"detached drill loses cargo control and selection")
 var wired:Array=design(6);wired.append(part(6,"not_gate",0,1))
 var external=make_sim(wired);external.set_free_flight_input(0,0,false,true,3);external.parts[6].signal=false
 check(not external._enabled(external.parts[3]) and not 3 in external.selectable_device_ids(),"Space never overrides an external wired drill")
 external.parts[6].signal=true
 check(external._enabled(external.parts[3]),"original live external source still controls wired drill")
 var old=make_sim(devices,true);old.set_free_flight_input(0,0,false,true)
 check(old._enabled(old.parts[3]) and old._enabled(old.parts[5]),"legacy free-v1 retains original shared held-drill semantics")
