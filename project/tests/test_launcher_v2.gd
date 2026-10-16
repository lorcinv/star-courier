extends SceneTree
## Headless deterministic tests. NOT RUN in authoring lane; no real save writes.
const Launcher=preload("res://scripts/launcher_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Frozen=preload("res://scripts/pilot_free_simulation_v1.gd")
class Harness:
 extends "res://scripts/pilot_free_simulation_v1.gd"
 func _prepare_launcher(design:Array) -> void:
  preload("res://scripts/launcher_v2.gd").prepare(self,design)
var failures:int=0
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func near(a:float,b:float,tolerance:float=0.00001) -> bool:return absf(a-b)<tolerance
func part(id:int,kind:String,x:int,y:int=0,param:float=-1.0,rot:int=0) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":rot,"param":Parts.defaults(kind) if param<0.0 else param,"input_a":-1,"input_b":-1,"target":-1}
func route() -> Dictionary:
 var r:Dictionary=Profile.route(Extreme.route({"weight":1.0}));r.distance=10000.0;r.destination_y=-1000.0;r.hazards=[];r.pilot_gates=[];r.pilot_drag=0.0;r.gravity=0.0;r.wind=[0.0,0.0];return r
func create(pad:Array):
 var sim=Harness.new();sim.configure([part(1,"cargo",0),part(2,"battery",-1)],pad,route(),42);return sim
func pad(motor:String="spring",power:float=60.0,support:String="beam") -> Array:
 return [part(100,"battery",-1),part(101,motor,0,0,power),part(102,support,1)]
func _initialize() -> void:
 var empty=create([]);var standard=create(pad("spring",20.0));var strong=create(Launcher.starter_launcher())
 check(near(empty.body_for_part(1).velocity.length(),0.0),"no launcher means zero initial launch speed")
 check(standard.body_for_part(1).velocity.x>2.8,"20 J starter gives measurable actual initial speed")
 check(strong.body_for_part(1).velocity.x>standard.body_for_part(1).velocity.x+1.5,"60 J reinforced starter meaningfully beats old20J")
 check(near(strong.telemetry.launch_energy_drawn,60.0) and near(strong.telemetry.launch_energy,60.0),"spring paid draw equals exact kinetic work")
 check(near(strong.parts[2].energy,strong.parts[2].capacity),"launcher uses no ship battery charge")
 var at:Vector2=strong.cargo_position();var speed:float=strong.body_for_part(1).velocity.x
 for index in range(120):strong.set_free_flight_input(0,0,false,false);strong.step(1.0/120.0)
 check(near(strong.cargo_position().x-at.x,speed,0.001),"no-engine ballistic probe travels its real launch speed for1s")
 print("LAUNCH_TRAJECTORY helper_harness no_pad=",empty.body_for_part(1).velocity," old20J=",standard.body_for_part(1).velocity," new60J=",speed," displacement_1s=",strong.cargo_position()-at)
 var rotated:Array=pad();rotated[1].rot=1
 var down=create(rotated);check(down.body_for_part(1).velocity.y>0.0 and absf(down.body_for_part(1).velocity.x)<0.00001,"pad rotation changes impulse direction")
 var weak=create(pad("accelerator",20.0));var armor=create(pad("accelerator",20.0,"armor"))
 check(bool(weak.telemetry.launch_support_limited) and weak.body_for_part(1).velocity.x<armor.body_for_part(1).velocity.x,"armor90N anchor produces more launch speed than beam32N")
 check(weak.launcher_parts.all(func(p):return p.alive),"support limiting does not destroy paid parts")
 var nozzle=create(pad("thruster",12.0));check(near(nozzle.body_for_part(1).velocity.x,12.0/5.0),"shared thruster provides one-second12Ns kick")
 check(float(nozzle.telemetry.launch_energy_drawn)>0.0,"shared thruster consumes real pad energy")
 var no_cell:Array=pad();no_cell.remove_at(0);var dry=create(no_cell)
 check(near(dry.telemetry.launch_speed,0.0) and near(dry.telemetry.energy_used,0.0),"no battery means no free launch")
 var no_anchor:Array=pad();no_anchor.remove_at(2);var unsupported=create(no_anchor)
 check(near(unsupported.telemetry.launch_speed,0.0) and near(unsupported.telemetry.energy_used,0.0),"no anchor means no charge or free launch")
 var isolated:Array=pad();isolated[0].x=-4;var disconnected=create(isolated)
 check(near(disconnected.telemetry.launch_speed,0.0),"separate pad components cannot borrow batteries")
 var ample:Array=Launcher.starter_launcher();ample.append(part(1005,"thruster",0,1,40.0));ample.append(part(1006,"armor",-1,1))
 var combination=create(ample)
 check(combination.telemetry.launch_modules_fired==2 and combination.body_for_part(1).velocity.x>speed,"reinforced spring+shared nozzle compound launch")
 var energy:float=combination.telemetry.energy_used;combination.status="failed";combination.finalize_settlement()
 var receipt:Dictionary=combination.telemetry.duplicate(true);combination.finalize_settlement()
 check(receipt==combination.telemetry and near(combination.telemetry.energy_used,energy),"recovery is idempotent and does not bill launch twice")
 var old=Frozen.new();old.configure([part(1,"cargo",0),part(2,"battery",-1)],pad("spring",20.0),route(),42)
 check(not old.telemetry.has("launch_policy"),"frozen v1 replay still owns frozen launcher path")
 print("LAUNCHER_V2 failures=",failures," engine_status=executed native_gui=NOT_RUN")
 quit(1 if failures else 0)
