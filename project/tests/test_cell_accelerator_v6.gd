extends SceneTree
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Helper=preload("res://scripts/cell_combinations_v6.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-2 if kind=="accelerator" else -1,"input_b":-1,"target":-1};p.merge(extra,true);return p
func bare()->Array:return [part(1,"cargo",1,0,100),part(2,"accelerator",0,0,8,{"target":1}),part(3,"battery",-1,0,300)]
func grouped()->Array:return bare()+[part(4,"battery",2,0,300),part(5,"beam",2,1,32)]
func make(ship:Array,data:Dictionary={}):
 var s=Sim.new();s.configure(ship,[],Profile.route({"distance":20.0,"delivery_radius":2.0,"max_delivery_speed":8.0}) if data.is_empty() else data,42);s.release_launcher(0,0);return s
func fire(s)->void:s.set_free_flight_input(0,0,false,true,2,false);s.step(1.0/120.0)
func kinetic(s)->float:
 var result:float=0.0
 for b in s.bodies:result+=0.5*float(b.mass)*b.velocity.length_squared()+0.5*float(b.inertia)*pow(float(b.angular_velocity),2)
 return result
func momentum(s)->Vector2:
 var result:Vector2=Vector2.ZERO
 for b in s.bodies:result+=Vector2(b.velocity)*float(b.mass)
 return result
func angular(s)->float:
 var result:float=0.0
 for b in s.bodies:result+=float(b.mass)*Vector2(b.position).cross(Vector2(b.velocity))+float(b.inertia)*float(b.angular_velocity)
 return result
func _initialize()->void:
 bare_delivery();group_physics();failure_atomicity();damage();reversal()
 print("CELL_ACCELERATOR_V6 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func bare_delivery()->void:
 var s=make(bare());var before:Vector2=s.cargo_position();var preview:Dictionary=s.preview_accelerator(2)
 check(preview.can_fire and preview.payload_ids==[1] and is_equal_approx(preview.payload_mass,3.0),"bare cargo is legal previewed payload")
 fire(s)
 check(s.status=="running" and s.telemetry.unpowered_coasting and s.parts[2].spent,"actual manual bare cargo shot survives first unpowered tick")
 check(s.cargo_position().distance_to(before+s.body_for_part(1).velocity/120.0)<0.0001,"no unconditional muzzle position jump")
 s.set_free_flight_input(0,0)
 for tick in range(120*10):
  if s.status!="running":break
  s.step(1.0/120.0)
 check(s.status=="success" and s.ship_integrity()==1.0,"bare cargo physically coasts into actual legal receiver")
 s.finalize_settlement()
 check(s.telemetry.lost_cost==100 and s.telemetry.ammo_cost==0,"successful bare shot bills abandoned accelerator55 plus cell45 without ammo double charge")
 print("CELL_BARE_SAMPLE ",JSON.stringify({"time":s.elapsed,"energy":s.telemetry.energy_used,"lost":s.telemetry.lost_cost,"ammo":s.telemetry.ammo_cost,"integrity":s.ship_integrity()}))
func group_physics()->void:
 var s=make(grouped());var preview:Dictionary=s.preview_accelerator(2)
 check(preview.can_fire and preview.payload_ids==[1,4,5] and preview.carrier_ids==[2,3],"single interface cut preserves whole cargo cell and beam group")
 var energy:float=kinetic(s);var linear:Vector2=momentum(s);var spin:float=angular(s)
 fire(s)
 check(s.body_for_part(1).id==s.body_for_part(4).id and s.body_for_part(4).id==s.body_for_part(5).id and s.body_for_part(2).id!=s.body_for_part(1).id,"successful split cuts only selected bridge")
 check(momentum(s).distance_to(linear)<0.00001 and absf(angular(s)-spin)<0.0001,"offcenter group shot conserves linear and angular momentum")
 check(absf(kinetic(s)-energy-float(s.telemetry.energy_used))<0.0001,"electrical payment equals actual added translational and rotational kinetic energy")
 check(absf(s.parts[3].energy-s.parts[4].energy)<0.00001,"parallel cells pay equally before separating into independent groups")
 check(s.telemetry.ammo_cost==0,"group carrying cargo is not prepaid disposable ammo")
 var spinning=make(grouped());spinning.body_for_part(1).velocity=Vector2(3,-2);spinning.body_for_part(1).angular_velocity=0.35
 var initial_k:float=kinetic(spinning);var initial_p:Vector2=momentum(spinning);var initial_l:float=angular(spinning)
 var spin_preview:Dictionary=spinning.preview_accelerator(2)
 spinning._accelerate(spinning.parts[2],spinning.parts[1],spinning.body_for_part(2),1.0/120.0)
 check(spin_preview.can_fire and momentum(spinning).distance_to(initial_p)<0.00001 and absf(angular(spinning)-initial_l)<0.0001 and absf(kinetic(spinning)-initial_k-float(spinning.telemetry.energy_used))<0.0001,"initial spin plus eccentric group conserves all momentum and pays actual mechanical energy gain")

 var ammo:Array=[part(1,"cargo",-1,0,100),part(2,"accelerator",0,0,8,{"target":4}),part(3,"battery",-2,0,300),part(4,"beam",1,0,32),part(5,"beam",2,0,32)]
 var a=make(ammo);fire(a)
 check(a.parts[2].spent and a.telemetry.ammo_cost==20 and a.parts[4].replacement_kind=="ammo" and a.parts[5].replacement_kind=="ammo","noncargo payload bills every actual expelled module once")
func failure_atomicity()->void:
 var bypass:Array=bare()+[part(4,"beam",0,1,32),part(5,"beam",1,1,32)]
 var cases:Array=[]
 var a=make(bypass);cases.append([a,"bypass_connection"])
 var b=make(bare());b.parts[3].energy=0;cases.append([b,"insufficient_energy"])
 var inward:Array=bare();inward[1].rot=2;var wrong_way=make(inward);cases.append([wrong_way,"exit_blocked"])
 var c=make(bare());c.obstacles.append({"type":"rock","position":c.cargo_position()+Vector2(1.0,0),"velocity":Vector2.ZERO,"radius":0.7,"health":100.0,"mass":50.0});cases.append([c,"exit_blocked"])
 for row in cases:
  var s=row[0];var links:Array=s.links.duplicate(true);var parts:Dictionary=s.parts.duplicate(true);var bodies:Array=s.bodies.duplicate(true);var used:float=s.telemetry.energy_used
  var preview:Dictionary=s.preview_accelerator(2)
  s._accelerate(s.parts[2],s.parts[1],s.body_for_part(2),1.0/120.0)
  check(not preview.can_fire and preview.reason==row[1] and s.parts==parts and s.links==links and s.bodies==bodies and s.telemetry.energy_used==used,"rejected "+row[1]+" preserves charge topology position and spent state")
func damage()->void:
 var r:Dictionary=Profile.route({"distance":80.0,"cargo_safe_acceleration":4.0})
 var ship:Array=bare();ship[1].param=20
 var s=make(ship,r);fire(s)
 check(s.parts[1].hp<100 and s.telemetry.cargo_peak_acceleration>4.0,"finite stroke actual projectile delta-v reaches fragile cargo HP")
 var carrier_ship:Array=[part(1,"cargo",-1,0,100),part(2,"accelerator",0,0,20,{"target":4}),part(3,"battery",-2,0,300),part(4,"beam",1,0,32),part(5,"beam",2,0,32)]
 var carrier=make(carrier_ship,r);fire(carrier)
 check(carrier.parts[1].hp<100,"recoil-side cargo receives its own actual delta-v load")
 var protected_ship:Array=ship.duplicate(true);protected_ship.append(part(5,"damper",1,1,8,{"target":1}))
 var buffered=make(protected_ship,r);fire(buffered)
 check(buffered.parts[2].spent and buffered.parts[1].hp>s.parts[1].hp,"real direct cargo damper spreads accelerator pulse without named-part immunity")
func reversal()->void:
 var ship:Array=grouped();var reverse:Array=ship.duplicate(true);reverse.reverse()
 var a=make(ship);var b=make(reverse)
 fire(a);fire(b)
 check(a.parts==b.parts and a.bodies==b.bodies and a.telemetry.accelerator_events==b.telemetry.accelerator_events,"reversing blueprint array preserves per-id cell charge and grouped ejection result")
 var preview:Dictionary=Helper.preview_blueprint(grouped(),Profile.route(),2)
 check(preview.can_fire and preview.payload_ids==[1,4,5],"workshop shared preview uses actual configured cargo mass and graph")
