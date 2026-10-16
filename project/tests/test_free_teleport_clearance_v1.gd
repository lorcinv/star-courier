extends SceneTree
const Free=preload("res://scripts/pilot_free_simulation_v1.gd")
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Open=preload("res://scripts/pilot_extreme_profile.gd")
const Legacy=preload("res://scripts/pilot_extreme_simulation.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func route() -> Dictionary:
 var data:Dictionary=Profile.route(Open.route({"weight":1.0}))
 data.hazards=[];data.pilot_gates=[];data.distance=10000.0;data.destination_y=0.0;return data
func sim_at(at:Vector2):
 var design:Array=Profile.starter_design();design.append({"id":9,"type":"teleporter","x":2,"y":0,"rot":0,"param":8.0,"input_a":-2})
 var sim=Free.new();sim.configure(design,[],route(),42)
 var body:Dictionary=sim.body_for_part(1);body.position+=at-sim.cargo_position();body.velocity=Vector2.ZERO;body.angular_velocity=0.0;return sim
func rock(at:Vector2) -> Dictionary:
 return {"position":at,"velocity":Vector2.ZERO,"mass":1000000.0,"radius":1.0,"health":100.0,"type":"rock","cooldown":0.0,"conductive":false}
func _initialize() -> void:
 var outside:float=float(route().get("boundary_y",80.0))+100.0
 for at in [Vector2(-60,0),Vector2(0,outside),Vector2(0,-outside)]:
  var sim=sim_at(at);var body:Dictionary=sim.body_for_part(1)
  check(sim.destination_clear(body,Vector2(8,0)),"clear exit is legal outside legacy box "+str(at))
  var before:Vector2=sim.cargo_position();var energy:float=sim.total_energy()
  sim.set_free_flight_input(0,0,false,true);sim.step(1.0/60.0)
  check(sim.cargo_position().x>before.x+7.9 and sim.total_energy()<energy-24.9,"actual edge-trigger teleport spends power outside old box "+str(at))
 var blocked=sim_at(Vector2(-60,0));blocked.obstacles.append(rock(Vector2(-52,0)))
 check(not blocked.destination_clear(blocked.body_for_part(1),Vector2(8,0)),"real exit overlap is still rejected")
 var before:Vector2=blocked.cargo_position();blocked.set_free_flight_input(0,0,false,true);blocked.step(1.0/60.0)
 check(blocked.cargo_position().distance_to(before)<0.01,"blocked teleport never moves through obstacle")
 var swept=sim_at(Vector2(-60,0));swept.body_for_part(1).velocity=Vector2(20,0);swept.obstacles.append(rock(Vector2(-45,0)))
 check(not swept.destination_clear(swept.body_for_part(1),Vector2(8,0)),"0.22-second post-exit collision preview is retained")
 var old_route:Dictionary=Open.route({"weight":1.0});old_route.hazards=[];old_route.pilot_gates=[]
 var old=Legacy.new();old.configure(Profile.starter_design(),[],old_route,42);var old_body:Dictionary=old.body_for_part(1)
 old_body.position+=Vector2(-60,0)-old.cargo_position();old_body.velocity=Vector2.ZERO
 check(not old.destination_clear(old_body,Vector2(8,0)),"old saved protocol retains exact original teleporter boundary")
 print("FREE_TELEPORT_CLEARANCE passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
