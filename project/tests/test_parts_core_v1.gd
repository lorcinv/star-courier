extends SceneTree
## New presentation/editor policy + actual frozen free-flight behavior.
## No player save path or native-input claim. Frozen legacy suites run separately.
const Policy=preload("res://scripts/workshop_parts_v1.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Free=preload("res://scripts/pilot_free_simulation_v1.gd")
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Old=preload("res://scripts/simulation.gd")
const V2=preload("res://scripts/pilot_ascent_simulation.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v1.gd")
var passed:int=0
var failed:int=0
func check(value:bool,message:String) -> void:
 if value:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func near(a:float,b:float,tolerance:float=.00001) -> bool:return absf(a-b)<tolerance
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func route() -> Dictionary:
 var value:Dictionary=Profile.route(Extreme.route({"weight":1.0}));value.distance=10000.0;value.destination_y=-1000.0;value.hazards=[];value.pilot_gates=[];value.pilot_drag=0.0;return value
func sim(design:Array,energy:float=6000.0):
 var s=Free.new();s.configure(design,[],route(),42)
 for p in s.parts.values():
  if p.type=="battery":p.energy=energy
 return s
func base(kind:String,extra:Dictionary={}) -> Array:
 return [part(1,"cargo",0),part(2,"battery",-1),part(3,kind,1,0,extra),part(4,"beam",2)]
func tick(s,active:bool=false,count:int=1) -> void:
 for index in count:s.set_free_flight_input(0,0,false,active);s.step(1.0/120.0)
func _initialize() -> void:
 catalog_and_policy();each_type_properties_and_trigger();splitter_behavior();teleporter_behavior();shared_button();protection_and_drill();legacy_combinations();launcher_and_replay()
 print("PARTS_CORE_V1 passed=%d failed=%d native_input=not_tested"%[passed,failed]);quit(1 if failed else 0)

func catalog_and_policy() -> void:
 check(Parts.catalog().size()==26 and Policy.CORE.size()==9,"26 retained registry IDs and exactly nine core sale IDs")
 check("splitter" in Policy.CORE and not "damper" in Policy.CORE and not "spring" in Policy.SHIP,"splitter core, spring launcher-specific, damper retained legacy")
 var entries:Array=[]
 for kind in Parts.catalog():
  var entry:Dictionary=Parts.catalog()[kind].duplicate(true);entry.type=kind;entry.launcher_compatible=kind in Parts.launcher_types();entries.append(entry)
 var old:Dictionary=part(30,"not_gate",0);var old_copy:Dictionary=old.duplicate(true)
 var owned:Dictionary={"not_gate":2,"coupler":1}
 var display:Array=Policy.visible_entries(entries,[old],owned,"旧版保留",false)
 check(display.map(func(row):return row.type)==["coupler","not_gate"],"only owned or installed legacy items shown, no hidden full advanced catalogue")
 check(Policy.visible_entries(entries,[],{},"旧版保留",false).is_empty(),"new empty inventory never exposes 17 legacy kinds")
 check(Policy.visible_entries(entries,[],{},"发射台",false).is_empty(),"new ship catalogue does not offer launcher spring")
 for kind in Parts.catalog():
  var item:Dictionary=part(3,kind,1,0,{"param":Parts.defaults(kind),"input_a":9,"target":999})
  var before:Dictionary=item.duplicate(true)
  Policy.local_controls(item,false);Policy.trigger_text(item,[old],true,false);Policy.readiness(item,[item,old],true,false)
  check(item==before,kind+" presentation preserves saved param/input/target")
 check(old==old_copy,"legacy source dictionary unchanged")
 var design:Array=[part(1,"cargo",0),part(2,"battery",2)]
 var new_split:Dictionary=Policy.new_part(3,"splitter",1,0,design,false,true)
 check(new_split.input_a==-2 and new_split.target==2 and new_split.size()==9,"explicit new splitter chooses visible valid battery, never adjacent cargo")
 var pending:Dictionary=Policy.new_part(3,"splitter",1,0,[design[0]],false,true)
 check(pending.target==-1 and not Policy.readiness(pending,[design[0],pending],true,false).ready,"only cargo adjacent stays visibly invalid instead of pretending readiness")
 check("货物" in str(Policy.readiness(pending,[design[0],pending],true,false).text),"cargo rejection is a visible specific reason")
 var saved:Dictionary=part(3,"splitter",1,0,{"target":1})
 var view:Dictionary=Policy.readiness(saved,[design[0],saved,design[1]],true,false)
 check(view.target_id==1 and not view.ready and saved.target==1,"saved forbidden cargo target is not silently changed to battery")
 check(Policy.new_part(3,"teleporter",1,0,design,false,true).input_a==-2,"new teleporter has visible cockpit binding")
 check(Policy.new_part(3,"teleporter",1,0,design,false,false).input_a==-1,"autonomous context never receives unsupported cockpit default")
 check("同时" in Policy.trigger_text(new_split,design,true,false),"shared Space/A semantics clearly stated")
 var valve:Dictionary=part(8,"valve",1,1,{"param":120.0,"target":3})
 check("功率阀" in str(Policy.readiness(new_split,design+[new_split,valve],true,false).text),"assembly detects instantaneous valve conflict")
 var off:Dictionary=part(3,"splitter",1,0,{"target":4})
 check(Policy.convenience_source(off,true,false).source==-2 and off.input_a==-1,"manual convenience is explicit proposed edit, never migration")

func each_type_properties_and_trigger() -> void:
 for kind in Parts.catalog():
  var s=sim(base(kind,{"target":4}))
  var p:Dictionary=s.parts[3];var spec:Dictionary=Parts.catalog()[kind]
  check(p.type==kind and near(p.mass,float(spec.mass)) and near(p.price,float(spec.price)),kind+" actual free instance preserves type, mass and price")
  var expected_hp:float=150.0 if kind=="armor" else 60.0 if kind=="drill" else 45.0
  check(near(p.hp,expected_hp),kind+" actual HP")
  check(s._enabled(p)==(kind not in Policy.WAIT),kind+" actual unconnected trigger default")
  var controls:Dictionary=Parts.controls(kind)
  if int(controls.inputs)>0:
   p.input_a=-2;s.set_free_flight_input(0,0,false,false);check(not s._enabled(p),kind+" cockpit release is off")
   s.set_free_flight_input(0,0,false,true);check(s._enabled(p),kind+" cockpit held is on when connected")
   s._cut(1,3);check(not s._enabled(p),kind+" cockpit cannot cross cut socket")
  var schema:Dictionary=Parts.parameter_schema(kind)
  check(near(p.param,float(schema.default)),kind+" actual parameter is schema default")
  check(is_finite(Parts.sanitize_parameter(kind,NAN)) and is_finite(Parts.sanitize_parameter(kind,INF)),kind+" nonfinite values sanitized")
 var battery=sim(base("battery"));check(near(battery.parts[3].capacity,6000.0),"free battery uses actual 20x route capacity, not 300J UI myth")

func splitter_behavior() -> void:
 var design:Array=base("splitter",{"input_a":-2,"target":4})
 var s=sim(design);var mass:float=s.total_mass();var energy:float=s.total_energy();var hp:float=s.parts[4].hp;var price:float=s.parts[4].price
 tick(s,false);check(s.parts.size()==4,"splitter waits before button")
 tick(s,true);check(s.parts.size()==5 and near(energy-s.total_energy(),10.0),"press actually creates one detached half for exactly 10J")
 check(near(s.total_mass(),mass) and near(s.parts[4].mass+s.parts[5].mass,.5),"split preserves total and target mass")
 check(near(s.parts[4].hp+s.parts[5].hp,hp) and near(s.parts[4].price+s.parts[5].price,price),"split preserves durability and replenishment price")
 check(near(s.parts[4].strength+s.parts[5].strength,32.0) and near(s.parts[4].output_factor+s.parts[5].output_factor,1.0),"split preserves strength and output budget")
 check(s.parts[4].body_id!=s.parts[5].body_id and near(s.parts[4].scale,sqrt(.5)),"split produces visibly smaller detached clone, not extra resources")
 tick(s,true,4);check(s.parts.size()==5,"held input does not split each step")
 tick(s,false);tick(s,true);check(s.parts.size()==6 and near(energy-s.total_energy(),20.0),"release/repress re-arms with no hidden timer cooldown")
 var dry=sim(design,9.0);tick(dry,true);check(dry.parts.size()==4 and near(dry.total_energy(),9.0),"less than10J refuses split with no charge")
 var forbidden=sim(base("splitter",{"input_a":-2,"target":1}));tick(forbidden,true)
 check(forbidden.parts.size()==4 and near(forbidden.telemetry.energy_used,0.0) and "货物" in str(forbidden.events),"cargo cannot be split, no charge, explicit runtime event")
 var remote=sim(base("splitter",{"input_a":-2,"target":2}));tick(remote,true);check(remote.parts.size()==4,"same-body but nonadjacent target cannot split")
 var valve=sim(design+[part(8,"valve",1,1,{"target":3,"param":120.0})]);tick(valve,true)
 check(valve.parts.size()==5 and near(valve.telemetry.energy_used,0.0),"maximum old valve cannot fund 10J in one physical step")
 var tiny=sim(design);tiny.parts[4].mass=.049;tick(tiny,true);check(tiny.parts.size()==4,"minimum target mass rejects repeated microscopic copies")
 # Battery split pays first, then divides the remaining stored energy/capacity.
 var cell=sim([part(1,"cargo",0),part(2,"splitter",1,0,{"input_a":-2,"target":3}),part(3,"battery",2)])
 tick(cell,true)
 check(cell.parts.size()==4 and near(cell.total_energy(),5990.0) and near(cell.parts[3].capacity+cell.parts[4].capacity,6000.0),"split battery conserves paid remaining energy and capacity")

func teleporter_behavior() -> void:
 var design:Array=base("teleporter",{"input_a":-2,"param":8.0})
 var s=sim(design);var at:Vector2=s.cargo_position();var energy:float=s.total_energy()
 tick(s,true);check(s.cargo_position().distance_to(at+Vector2(8,0))<.00001 and near(energy-s.total_energy(),25.0),"teleporter button moves full connected craft8m for25J")
 tick(s,true,3);check(s.cargo_position().distance_to(at+Vector2(8,0))<.00001,"holding does not repeat teleport")
 tick(s,false);tick(s,true);check(s.cargo_position().distance_to(at+Vector2(16,0))<.00001 and near(energy-s.total_energy(),50.0),"repress performs next paid teleport with no timer cooldown")
 var dry=sim(design,24.0);var dry_at:Vector2=dry.cargo_position();tick(dry,true)
 check(dry.cargo_position()==dry_at and near(dry.total_energy(),24.0),"insufficient teleport charge preserves position and energy")
 var blocked=sim(design);var blocked_at:Vector2=blocked.cargo_position()
 blocked.obstacles.append({"position":blocked_at+Vector2(8,0),"velocity":Vector2.ZERO,"mass":1000000.0,"radius":1.0,"health":1000000.0,"type":"rock","cooldown":1.0,"conductive":false})
 tick(blocked,true);check(blocked.cargo_position()==blocked_at and near(blocked.telemetry.energy_used,0.0),"blocked whole-craft landing refuses free of charge")
 var moving=sim(design);moving.body_for_part(1).velocity=Vector2(2,1);moving.body_for_part(1).angular_velocity=.2
 var speed:Vector2=moving.body_for_part(1).velocity
 moving.set_free_flight_input(0,0,false,true);moving._act(moving.parts[3],moving.body_for_part(3),1.0/120.0,true)
 check(moving.body_for_part(1).velocity==speed and near(moving.body_for_part(1).angular_velocity,.2),"teleport preserves linear and angular velocity")

func shared_button() -> void:
 var design:Array=[part(1,"cargo",0),part(2,"battery",-1),part(3,"splitter",1,0,{"target":4,"input_a":-2}),part(4,"beam",2),part(6,"teleporter",0,-1,{"input_a":-2,"param":8.0})]
 var s=sim(design);var start:Vector2=s.cargo_position();tick(s,true)
 check(s.parts.size()==6 and near(s.telemetry.energy_used,35.0) and s.cargo_position().x>start.x+7.0,"one shared press executes splitter then teleporter and pays10+25J")
 tick(s,true,3);check(s.parts.size()==6 and near(s.telemetry.energy_used,35.0),"two held devices still act only once")
 var poor=sim(design,30.0);var at:Vector2=poor.cargo_position();tick(poor,true)
 check(poor.parts.size()==6 and near(poor.telemetry.energy_used,10.0) and poor.cargo_position().distance_to(at)<.5,"insufficient shared budget uses frozen order: split succeeds, teleport waits")
 var reversed:Array=design.duplicate(true);var first:Dictionary=reversed.pop_back();reversed.insert(2,first)
 var other=sim(reversed,30.0);tick(other,true)
 check(other.parts.size()==5 and near(other.telemetry.energy_used,25.0),"frozen assembly order is deterministic: first teleport leaves insufficient split charge")

func protection_and_drill() -> void:
 var armor=sim(base("armor"));armor._damage_part(armor.parts[3],20.0,"collision")
 check(near(armor.parts[3].hp,130.0) and near(armor.parts[1].hp,100.0) and near(armor.telemetry.energy_used,0.0),"armor absorbs local contact in own150HP without power")
 armor._damage_part(armor.parts[1],20.0,"collision");check(near(armor.parts[1].hp,80.0),"armor elsewhere cannot remotely protect cargo")
 var shield=sim(base("shield"));shield._damage_part(shield.parts[1],20.0,"collision")
 check(near(shield.parts[1].hp,93.0) and near(shield.telemetry.energy_used,19.5),"free shield absorbs65% impact for1.5J/HP across connected hull")
 var dry=sim(base("shield"),0);dry._damage_part(dry.parts[1],20.0,"collision");check(near(dry.parts[1].hp,80.0),"empty shield grants no protection")
 var old=V2.new();old.configure(base("shield"),[],Ascent.route(),42);old._damage_part(old.parts[1],20.0,"collision")
 check(near(old.parts[1].hp,80.0),"oldv2 shield remains attack-only")
 var drill=sim(base("drill"));tick(drill,false,120)
 check(near(drill.telemetry.drill_energy_used,60.0,.001) and near(drill.telemetry.drill_damage,0.0),"drill burns60J/s while idling, so detour saves tool power")
 var stopped=sim(base("drill",{"input_a":-2}));tick(stopped,false,10);check(near(stopped.telemetry.drill_energy_used,0.0),"old manual drill stays off until held")
 tick(stopped,true,12);check(near(stopped.telemetry.drill_energy_used,6.0,.001),"manual held drill is continuous, not rising-edge only")
 var dry_drill=sim(base("drill"),0);dry_drill._act(dry_drill.parts[3],dry_drill.body_for_part(3),1.0/120.0,true)
 check(near(dry_drill.parts[3].drill_power_ratio,0.0),"empty drill has zero paid cutter output")
 var cutter=sim([part(1,"cargo",0),part(2,"battery",-1),part(3,"drill",1)])
 cutter.obstacles.append({"position":cutter.part_world_position(3)+Vector2(1.255,0),"radius":.8,"health":80.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO})
 tick(cutter,false,120)
 check(cutter.obstacles[0].health<.0001 and cutter.telemetry.drill_damage>79.9 and near(cutter.telemetry.energy_used,60.0,.001),"actual contact drill cuts80HP stone for60J in one second")
 var tower=sim([part(1,"cargo",0),part(2,"battery",-1),part(3,"drill",1)])
 tower.obstacles.append({"position":tower.part_world_position(3)+Vector2(1.255,0),"radius":.8,"health":1000000.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO,"pilot_gate":true})
 tick(tower,false,120)
 check(near(tower.obstacles[0].health,1000000.0) and near(tower.telemetry.drill_damage,0.0),"actual contact with indestructible gate does not drill through")
 var rear=sim([part(1,"cargo",0),part(2,"battery",-1),part(3,"drill",1,0,{"rot":2})])
 rear.obstacles.append({"position":rear.part_world_position(3)+Vector2(1.255,0),"radius":.8,"health":80.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO})
 tick(rear,false,30);check(near(rear.obstacles[0].health,80.0),"backward drill cannot cut forward stone")
 var legacy=Old.new();legacy.configure(base("drill"),[],{"distance":1000.0},42)
 check(legacy.parts[3].type=="beam" and "结构梁" in Policy.purpose("drill",false,"autonomous-v5"),"unsupported old drill fallback is honestly displayed")

func legacy_combinations() -> void:
 var d=sim(base("damper"));d.body_for_part(1).angular_velocity=2.0;tick(d)
 check(d.body_for_part(1).angular_velocity<2.0 and near(d.telemetry.energy_used,0),"retained damper dissipates rotation without electricity")
 var shrink=sim(base("shrink",{"target":4}));tick(shrink);check(near(shrink.parts[4].scale,.55) and near(shrink.parts[4].mass,.5),"shrink changes collision size, never mass")
 var large=sim(base("enlarge",{"target":4}));tick(large);check(near(large.parts[4].scale,1.6) and near(large.parts[4].mass,.5),"enlarge changes size without extra resources")
 var turn=sim(base("rotator",{"target":4}));tick(turn,false,12);check(turn.parts[4].local_angle>0 and near(turn.telemetry.energy_used,.4,.0001),"rotator rotates adjacent target with paid4J/s default")
 var decoy=sim(base("decoy"));tick(decoy,false,12);check(decoy.parts[3].active and near(decoy.telemetry.energy_used,.2,.0001),"decoy emits powered tracker lure for2J/s")
 var gate=sim(base("not_gate"));tick(gate);check(gate.parts[3].signal,"unconnected NOT remains true")
 for kind in ["and_gate","or_gate","delay"]:
  var logic=sim(base(kind));tick(logic);check(not logic.parts[3].signal,kind+" unconnected false stays preserved")
 var probe=sim(base("probe"));tick(probe);check(not probe.parts[3].signal,"probe ignores its own adjacent structure")
 var contact=sim(base("collision"));contact.parts[3].next_contact=true;tick(contact);check(contact.parts[3].signal,"collision outputs actual contact marker")
 tick(contact);check(not contact.parts[3].signal,"contact pulse clears without new collision")
 for kind in ["lance","arc"]:
  var ray=sim(base(kind));var power:float=28.0 if kind=="lance" else 24.0;tick(ray,false,12)
  check(near(ray.telemetry.energy_used,power*.1,.001),kind+" old automatic ray pays exact continuous power")
 var coupler=sim(base("coupler",{"input_a":-2,"target":4}));tick(coupler,true);check(coupler.body_for_part(3).id!=coupler.body_for_part(4).id,"coupler cuts its selected edge on button")
 var bomb=sim(base("bomb",{"input_a":-2}));tick(bomb,true);check(not bomb.parts[3].alive and bomb.parts[3].spent,"bomb consumes itself and causes real friendly blast")
 var accel=sim(base("accelerator",{"target":4}));tick(accel);check(accel.parts[3].spent and accel.body_for_part(4).id!=accel.body_for_part(3).id,"accelerator still fires once automatically without hidden edge setup")
 var spring=sim(base("spring",{"input_a":-2,"target":4}));tick(spring,false,60);check(spring.parts[3].stored_energy>0 and not spring.parts[3].spent,"old onboard spring automatically charges while trigger is off")
 tick(spring,true);check(spring.parts[3].spent and spring.body_for_part(3).id!=spring.body_for_part(4).id,"old onboard spring releases conserved opposite impulses on press")

func launcher_and_replay() -> void:
 var pad:Array=[part(1001,"spring",0,0,{"param":20.0}),part(1002,"battery",-1),part(1003,"beam",1)]
 var s=Free.new();s.configure([part(1,"cargo",0),part(2,"battery",-1)],pad,route(),42)
 check(s.telemetry.launch_energy>0 and s.cargo_position().is_finite(),"launcher spring releases automatically with battery plus structural support")
 var unsupported=Free.new();unsupported.configure([part(1,"cargo",0),part(2,"battery",-1)],pad.slice(0,2),route(),42)
 check(near(unsupported.telemetry.launch_energy,0),"spring without support does not invent launch force")
 var design:Array=base("splitter",{"input_a":-2,"target":4});var original:Array=design.duplicate(true)
 var first=sim(design);var second=sim(JSON.parse_string(JSON.stringify(design)))
 var timeline=Timeline.new();timeline.record(0,{"axis_x_q":0,"axis_q":0,"boost":false,"active":true});timeline.record(2,Timeline.neutral());timeline.record(3,{"axis_x_q":0,"axis_q":0,"boost":false,"active":true})
 var saved:Array=timeline.snapshot();var replay=Timeline.new();check(replay.restore(JSON.parse_string(JSON.stringify(saved)),8),"unchanged free input schema restores tool button timeline")
 for index in 8:
  var input:Dictionary=timeline.state_at(index);var restored:Dictionary=replay.state_at(index)
  first.set_free_flight_input(input.axis_x_q,input.axis_q,input.boost,input.active);first.step(1.0/60.0)
  second.set_free_flight_input(restored.axis_x_q,restored.axis_q,restored.boost,restored.active);second.step(1.0/60.0)
 check(first.parts.size()==second.parts.size() and near(first.total_energy(),second.total_energy()) and first.cargo_position().is_equal_approx(second.cargo_position()),"old two-axis replay yields same actual tool results")
 check(design==original,"configuring and replaying never modifies blueprint bytes")
