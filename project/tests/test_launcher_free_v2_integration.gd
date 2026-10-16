extends SceneTree
## Must run AFTER merging the force worker's v2 files. NOT RUN by author.
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const OpenProfile=preload("res://scripts/pilot_extreme_profile.gd")
const OldProfile=preload("res://scripts/pilot_profile.gd")
const Launcher=preload("res://scripts/launcher_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var failures:int=0
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,amount:float) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":amount,"input_a":-1,"input_b":-1,"target":-1}
func setup(pad:Array):
 var route:Dictionary=Profile.route(OpenProfile.route({"weight":1.0}));route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0;route.gravity=0.0;route.wind=[0.0,0.0]
 var result=Sim.new();result.configure(OpenProfile.starter_design(),pad,route,42);return result
func run_probe(label:String,pad:Array) -> Dictionary:
 var sim=setup(pad);check(sim.status=="running",label+" configures exact v2")
 if sim.status!="running":return {}
 var initial:Vector2=sim.cargo_position();var velocity:Vector2=sim.body_for_part(1).velocity;var energy:float=sim.total_energy();var snapshots:Array=[]
 for index in range(240):
  sim.set_free_flight_input(0,0,false,false,-1,false);sim.step(1.0/120.0)
  if index in [0,119,239]:snapshots.append({"time":sim.elapsed,"position":[sim.cargo_position().x,sim.cargo_position().y],"velocity":[sim.body_for_part(1).velocity.x,sim.body_for_part(1).velocity.y]})
 check(sim.body_for_part(1).velocity.distance_to(velocity)<0.00001,label+" neutral input preserves launch momentum")
 check(absf(sim.total_energy()-energy)<0.00001,label+" coast consumes no ship propulsion energy")
 print("LAUNCH_V2_ACTUAL ",label," initial_velocity=",velocity," points=",JSON.stringify(snapshots))
 return {"speed":velocity.length(),"displacement":sim.cargo_position().distance_to(initial)}
func _initialize() -> void:
 var reinforced:Array=Launcher.starter_launcher();reinforced.append(part(1010,"thruster",0,1,40.0));reinforced.append(part(1011,"armor",-1,1,150.0))
 var absent:Dictionary=run_probe("no_pad",[])
 var old:Dictionary=run_probe("old_starter20J",OldProfile.starter_launcher())
 var standard:Dictionary=run_probe("new_starter60J",Launcher.starter_launcher())
 var upgraded:Dictionary=run_probe("spring_nozzle_armor",reinforced)
 if absent.is_empty() or old.is_empty() or standard.is_empty() or upgraded.is_empty():quit(1);return
 check(absf(float(absent.speed))<0.00001 and float(old.speed)>0.0,"empty pad versus existing starter has real velocity difference")
 check(float(standard.speed)>float(old.speed) and float(upgraded.speed)>float(standard.speed),"more spring energy and a supported shared nozzle each increase actual departure speed")
 check(float(standard.displacement)>float(old.displacement) and float(upgraded.displacement)>float(standard.displacement),"launcher changes actual2s position rather than only telemetry")
 print("LAUNCHER_FREE_V2_INTEGRATION failures=",failures," gui=NOT_RUN");quit(1 if failures else 0)
