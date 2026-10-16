extends SceneTree
## Real helper regression from independent review; NOT RUN by author.
## Frozen free-v1 harness replaces only launcher preparation, not its physics.
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
class Harness:
 extends "res://scripts/pilot_free_simulation_v1.gd"
 func _prepare_launcher(design:Array) -> void:
  preload("res://scripts/launcher_v2.gd").prepare(self,design)
var failures:int=0
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func near(a:float,b:float,tolerance:float=0.00001) -> bool:return absf(a-b)<tolerance
func build(fixture:Dictionary,pad:Array):
 var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}));route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.gravity=0.0;route.wind=[0.0,0.0];route.pilot_drag=0.0
 var sim=Harness.new();sim.configure(fixture.design,pad,route,42);return sim
func _initialize() -> void:
 var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dev04-review/zero-joule-opposed-spring.json"))
 if not raw is Dictionary:check(false,"independent review fixture loads");quit(1);return
 var fixture:Dictionary=raw
 var no_spring:Array=fixture.launcher.filter(func(p):return p.type!="spring")
 var reference=build(fixture,no_spring)
 check(near(reference.body_for_part(1).mass,5.0) and near(reference.body_for_part(1).velocity.x,2.4),"unchanged review fixture has5kg craft and real12Ns nozzle baseline")
 check(near(reference.telemetry.launch_energy_drawn,18.0),"nozzle baseline consumes18J")
 var zero=build(fixture,fixture.launcher)
 var spring:Dictionary={}
 for p in zero.launcher_parts:
  if p.type=="spring":spring=p
 check(zero.body_for_part(1).velocity.distance_to(reference.body_for_part(1).velocity)<0.00001,"zero-joule opposed spring cannot reverse or change nozzle velocity")
 check(near(zero.telemetry.launch_energy_drawn,reference.telemetry.launch_energy_drawn) and zero.telemetry.launch_modules_fired==1,"zero spring pays nothing and does not count as fired")
 check(not spring.spent and not spring.active and near(spring.stored_energy,0.0),"zero setting leaves spring unspent and inactive")
 for joules in [0.0001,1.0,14.4,60.0]:
  var pad:Array=fixture.launcher.duplicate(true)
  for p in pad:
   if p.type=="spring":p.param=joules
  var actual=build(fixture,pad)
  var expected:float=2.4-sqrt(2.0*joules/5.0)
  var velocity:Vector2=actual.body_for_part(1).velocity
  check(near(velocity.x,expected),"opposed %.4fJ follows continuous paid impulse, no free reflection branch"%joules)
  check(near(float(actual.telemetry.launch_energy_drawn)-18.0,joules),"opposed %.4fJ consumes real spring energy rather than net-work0"%joules)
  check(actual.telemetry.launch_modules_fired==2,"positive %.4fJ spring fires once"%joules)
  var kinetic:float=0.5*5.0*velocity.length_squared()
  check(near(kinetic+float(actual.telemetry.launch_heat),float(actual.telemetry.launch_energy_drawn)),"opposed %.4fJ conserves paid energy as final motion plus heat"%joules)
  check(near(actual.telemetry.heat,actual.telemetry.launch_heat),"opposed %.4fJ absorbed motion is recorded as heat"%joules)
  check(near(actual.parts[2].energy,actual.parts[2].capacity),"opposed %.4fJ never consumes ship battery"%joules)
  print("OPPOSED_SPRING_ACTUAL J=",joules," velocity=",velocity," pad_J=",actual.telemetry.launch_energy_drawn," heat=",actual.telemetry.launch_heat)
 print("LAUNCHER_OPPOSED_SPRING_V2 failures=",failures," gui=NOT_RUN");quit(1 if failures else 0)
