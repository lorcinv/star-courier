extends SceneTree
## Resource/bounds regressions, plus timings recorded without hardware-dependent gates.
const Sim = preload("res://scripts/simulation.gd")
const Parts = preload("res://scripts/parts.gd")
var passed = 0
var failed = 0
var metrics: Dictionary = {}

func check(condition: bool, message: String) -> void:
 if condition: passed += 1; print("PASS ",message)
 else: failed += 1;push_error("FAIL "+message)

func p(id: int, type: String, x: int, y: int = 0) -> Dictionary:
 return {"id":id,"type":type,"x":x,"y":y,"rot":0,"param":Parts.defaults(type),"input_a":-1,"input_b":-1,"target":-1}

func route(limit: float = 90.0) -> Dictionary:
 return {"distance":10000.0,"delivery_radius":5.0,"max_delivery_speed":45.0,"time_limit":limit,"boundary_y":80.0,"weight":1.0,"hazards":[],"gravity":0.0,"wind":Vector2.ZERO,"seed":100,"variation":0.0}

func split_design() -> Array:
 var craft: Array=[];var id=1
 for y in range(-2,3):
  for x in [-4,-2,0,2]:
   var splitter=p(id,"splitter",x,y);id+=1
   var battery=p(id,"battery",x+1,y);id+=1
   splitter.target=battery.id;splitter.input_a=41
   craft.append(splitter);craft.append(battery)
 var oscillator=p(41,"not_gate",4,-2);oscillator.input_a=41;craft.append(oscillator)
 craft.append(p(42,"cargo",4,0));craft.append(p(43,"beam",4,-1));craft.append(p(44,"beam",4,1));craft.append(p(45,"beam",4,2))
 return craft

func _initialize() -> void:
 var craft=split_design();var cells:Dictionary={};var legal=true
 for part in craft:
  var cell=Vector2i(part.x,part.y)
  legal=legal and abs(part.x)<=4 and abs(part.y)<=2 and not cells.has(cell)
  cells[cell]=true
 check(craft.size()==45 and legal,"split stress uses exactly45 unique legal editor cells")
 var sim=Sim.new();sim.configure(craft,[],route(),100)
 var steps:Array=[];var start=Time.get_ticks_usec()
 var initial_mass=sim.total_mass()
 for i in range(180):
  var before=Time.get_ticks_usec();sim.step(1.0/60.0);steps.append(float(Time.get_ticks_usec()-before)/1000.0)
 steps.sort()
 metrics.split_wall_ms=float(Time.get_ticks_usec()-start)/1000.0
 metrics.split_step_1_60_ms_p50=steps[89];metrics.split_step_1_60_ms_p95=steps[170]
 metrics.split_parts=sim.parts.size();metrics.split_bodies=sim.bodies.size();metrics.split_elapsed=sim.elapsed;metrics.split_status=sim.status
 check(sim.parts.size()==134 and sim.bodies.size()==90,"optimized stress preserves baseline134parts and90bodies at3seconds")
 check(sim.parts.size()<=Sim.MAX_SIM_PARTS and sim.bodies.size()<=sim.parts.size(),"legal repeated splitting stays within hard budget")
 check(is_equal_approx(sim.total_mass(),initial_mass),"repeated splitting conserves total mass")
 check(sim.parts.values().filter(func(item):return item.type=="cargo").size()==1,"repeated splitting never clones cargo")
 check(sim.incidents.is_empty() and sim.status=="running","stationary stress stays undamaged and running")
 var correct_lookup=true;var finite_state=true
 for body in sim.bodies:
  correct_lookup=correct_lookup and sim._body_by_id(body.id)==body
  for part in body.parts:
   correct_lookup=correct_lookup and sim.body_for_part(part.id)==body
   var pos:Vector2=sim.part_world_position(part.id)
   finite_state=finite_state and is_finite(pos.x) and is_finite(pos.y) and is_finite(float(part.mass))
 check(correct_lookup,"all body and module lookups agree after89split rebuilds")
 check(sim._body_by_id(-12345).is_empty(),"unknown body lookup safely returns empty")
 check(finite_state,"all many-body positions and masses remain finite")
 var count_before=sim.parts.size()
 for i in range(30):sim.step(1.0/60.0)
 check(sim.parts.size()==count_before,"finite battery energy prevents continued split growth")

 # Artificial cap-boundary construction intentionally exceeds editor45-cell input.
 # It verifies the defensive simulation guard, not a claimed player-legal design.
 var raw=[p(1,"cargo",0),p(2,"battery",-1),p(3,"splitter",-2)]
 raw[2].target=2
 for i in range(189):raw.append(p(4+i,"beam",100+i*2))
 var capped=Sim.new();capped.configure(raw,[],route(),100)
 var energy_before=capped.total_energy();var mass_before=capped.total_mass();var price_before=capped.parts[2].price
 for i in range(5):capped._split_module(capped.parts[3],capped.parts[2],capped.body_for_part(3),1.0/120.0)
 check(capped.parts.size()==Sim.MAX_SIM_PARTS,"split at192part boundary creates no extra module")
 check(is_equal_approx(capped.total_energy(),energy_before),"refused split consumes no energy")
 check(is_equal_approx(capped.total_mass(),mass_before) and capped.parts[2].price==price_before,"refused split changes neither mass nor value")
 check(capped.events.filter(func(event):return str(event).contains("安全上限")).size()==1,"repeated cap refusal emits only one safety notice")

 var visual=Sim.new();visual.configure([p(1,"cargo",0),p(2,"battery",-1)],[],route(),100)
 var telemetry_before=visual.telemetry.duplicate(true);var momentum_before=visual.total_momentum();energy_before=visual.total_energy()
 for i in range(1024):visual._effect("lance",Vector2(i,0),Vector2(i+1,0),.02)
 check(visual.effects.size()==Sim.MAX_EFFECTS,"visual effect list never exceeds192 entries")
 check(int(visual.effects.front().from.x)==1024-Sim.MAX_EFFECTS,"effect overflow evicts oldest visual only")
 check(visual.telemetry==telemetry_before and visual.total_momentum()==momentum_before and visual.total_energy()==energy_before,"effect eviction changes no telemetry, energy or momentum")
 visual.step(.05)
 check(visual.effects.is_empty(),"effects expire naturally on subsequent physics ticks")

 var oscillator=p(2,"not_gate",-1);oscillator.input_a=2
 var delay=p(3,"delay",-2);delay.input_a=2;delay.param=5.0
 var logic=Sim.new();logic.configure([p(1,"cargo",0),oscillator,delay],[],route(6.0),100)
 var peak_queue=0
 for i in range(13):
  logic.step(.5);peak_queue=maxi(peak_queue,logic.parts[3].delay_queue.size())
 metrics.delay_peak_queue=peak_queue;metrics.logic_elapsed=logic.elapsed
 check(peak_queue<=601 and peak_queue>=590,"5second oscillating delay queue stays within120Hz horizon")
 check(logic.status=="failed" and logic.elapsed>=6.0 and logic.elapsed<6.02,"flight time limit terminates unchanged stationary logic circuit")
 check(logic.events.size()<=100,"event history stays within100entry bound")
 check(logic.parts[3].delay_queue.is_empty() or logic.parts[3].delay_queue.size()<=601,"terminal delay state remains bounded")
 var collision_start=Time.get_ticks_usec()
 for i in range(20):sim._collisions()
 metrics.split_collision_pass_ms=float(Time.get_ticks_usec()-collision_start)/20000.0
 var signals_start=Time.get_ticks_usec()
 for i in range(20):sim._update_signals(1.0/120.0)
 metrics.split_signal_pass_ms=float(Time.get_ticks_usec()-signals_start)/20000.0
 metrics.passed=passed;metrics.failed=failed
 var file=FileAccess.open("res://docs/qa/performance-simulation-regressions.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(metrics,"  "))
 print("PERFORMANCE_REGRESSIONS ",JSON.stringify(metrics))
 quit(1 if failed else 0)
