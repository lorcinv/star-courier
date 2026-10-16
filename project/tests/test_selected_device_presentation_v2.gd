extends SceneTree
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const View=preload("res://scripts/selected_device_presentation_v2.gd")
var passed:int=0
var failed:int=0
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func make_sim():
 var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var design:Array=Profile.starter_design()
 design.append(Extreme.part(9,"teleporter",2,0,{"input_a":-2,"param":8.0}))
 design.append(Extreme.part(10,"accelerator",3,0,{"input_a":-2,"target":9,"param":10.0}))
 var sim=Sim.new();sim.configure(design,[],route,42);return sim
func snapshot(sim) -> PackedByteArray:
 return var_to_bytes({"parts":sim.parts,"bodies":sim.bodies,"links":sim.links,"energy":sim.telemetry,"elapsed":sim.elapsed,"aim":[sim.pilot_aim_x_q,sim.pilot_aim_y_q],"id":sim.pilot_device_id,"edge":sim._active_edge_device_id})
func _initialize() -> void:
 check(View.state(null).is_empty(),"no flight has no device panel")
 var sim=make_sim()
 check(View.state(sim).is_empty(),"no selected device has no misleading ready state")
 sim.set_free_flight_input(0,0,false,false,8)
 var before:PackedByteArray=snapshot(sim)
 var actual:Dictionary=View.state(sim)
 check(actual.name=="分离扣" and actual.status=="可用","selected real starter socket shows its concrete available action")
 check(snapshot(sim)==before,"read-only view changes no typed physical or command state")
 sim.set_free_flight_input(-1000,-1000,false,false,9);actual=View.state(sim)
 check(actual.direction=="↖" and actual.status=="可用","teleporter display follows actual diagonal flight aim")
 sim.set_free_flight_input(0,0,false,false,9)
 check(View.state(sim).direction=="↖","released keys retain recorded last aim")
 sim.set_free_flight_input(-1000,0,false,false,9)
 sim.obstacles.append({"position":sim.cargo_position()+Vector2(-8,0),"velocity":Vector2.ZERO,"mass":1000.0,"radius":1.0,"health":1000.0,"type":"rock","cooldown":0.0})
 check(View.state(sim).status=="落点受阻","blocked actual exit is visible before firing")
 sim.obstacles.clear();sim.parts[3].energy=0.0
 check(View.state(sim).status=="电量不足","empty connected cell reports energy rather than ready")
 sim.parts[3].energy=sim.parts[3].capacity
 sim.set_free_flight_input(0,0,false,false,10);sim.parts[10].spent=true
 check(View.state(sim).status=="已发射","one-shot spent module reports spent")
 sim.parts[10].spent=false;sim.parts[10].target=1
 check(View.state(sim).status=="未连接目标","invalid selected target never gets silent fallback readiness")
 sim.set_free_flight_input(0,0,false,false,99999)
 check(View.state(sim).status=="已失联","invalid selection does not display another ready module")
 sim.route.control_version="pilot-free-v1"
 check(View.state(sim).is_empty(),"new selection UI never implies v2 control for legacy route")
 print("SELECTED_DEVICE_PRESENTATION_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
