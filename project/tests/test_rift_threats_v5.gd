extends SceneTree
const Threats=preload("res://scripts/delivery_rift_threats_v1.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
class Harness:
 extends "res://scripts/pilot_delivery_simulation_v3.gd"
 var threats=preload("res://scripts/delivery_rift_threats_v1.gd").new()
 var field_added:bool=false
 func _tick(dt:float)->void:
  field_added=false;threats.before_tick(self,dt);super._tick(dt)
 func _act(p:Dictionary,b:Dictionary,dt:float,rising:bool)->void:
  if not field_added:field_added=true;threats.add_forces(self,dt)
  super._act(p,b,dt,rising)
 func _enemy_attacks(dt:float)->void:
  super._enemy_attacks(dt);threats.after_tick(self,dt)
 func _refresh_telemetry()->void:
  super._refresh_telemetry();telemetry.merge(threats.telemetry(self),true)
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int,param:float=0.0)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1}
func make(ship:Array=[],pirate:Dictionary={},field:Dictionary={}):
 var p:Dictionary=Threats.DEFAULT_PIRATE.duplicate(true);p.position=[20.0,0.0];p.merge(pirate,true)
 var f:Dictionary=Threats.DEFAULT_TURBULENCE.duplicate(true);f.bounds=[100.0,100.0,10.0,10.0];f.merge(field,true)
 var s=Harness.new()
 s.configure([part(1,"cargo",0,0,100),part(2,"battery",0,1,300)] if ship.is_empty() else ship,[],Profile.route({"distance":500.0,"destination_y":0.0,"time_limit":60.0,"boundary_y":100.0}),42)
 s.threats.configure({"rift_pirate":p,"rift_turbulence":f})
 s.body_for_part(1).position-=s.cargo_position()
 s.release_launcher(0,0);return s
func advance(s,ticks:int)->void:
 for i in range(ticks):s.step(1.0/120.0)
func fire_direct(s)->void:
 s.threats.activate(s);s.threats.before_tick(s,1.0/120.0);s.threats.after_tick(s,1.0/120.0)
 s.elapsed=float(s.threats.warning.due_at);s.threats.after_tick(s,1.0/120.0)
func _initialize()->void:
 activation_and_warning();obstruction_and_shields();physical_collider();turbulence();replay()
 print("RIFT_THREATS_V5 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func activation_and_warning()->void:
 var s=make();advance(s,400)
 check(s.obstacles.is_empty() and s.threats.shots_fired==0 and s.ship_integrity()==1.0,"time or proximity alone cannot spawn pre-portal pirate")
 s.threats.activate(s);s.threats.activate(s);advance(s,330)
 check(s.obstacles.size()==1 and not s.threats.warning.is_empty() and s.threats.shots_fired==0,"verified activation is idempotent and every shot has full2.75second warning")
 advance(s,1)
 check(s.threats.shots_fired==1 and s.threats.ray_records[0].hit_kind=="part" and s.parts[1].hp==88.0,"warning matures into one real cargo ray hit")
 advance(s,1300)
 check(s.threats.shots_fired==2 and s.threats.ray_records.size()==2 and s.parts[1].hp==76.0,"single pirate exhausts exactlytwo shots with no infinite attacks")
 check(float(s.telemetry.energy_used)==0.0,"enemy ammunition never enters courier energy bill")
 var dodged=make();dodged.threats.activate(dodged);advance(dodged,1)
 var locked:Vector2=dodged.threats.warning.target
 dodged.body_for_part(1).position.y+=4.0;advance(dodged,330)
 check(dodged.threats.ray_records[0].hit_kind=="miss" and dodged.ship_integrity()==1.0 and locked==Vector2.ZERO,"warning aim stays frozen and physically dodging avoids damage")
 var disabled=make();disabled.threats.activate(disabled);advance(disabled,1)
 disabled.obstacles[0].health=0.0;advance(disabled,400)
 check(disabled.threats.shots_fired==0 and disabled.threats.warning.is_empty(),"destroyed physical pirate cancels pending warning before emission")
func obstruction_and_shields()->void:
 check(is_inf(Threats._forward_ray_circle(Vector2.ZERO,Vector2.RIGHT,Vector2(-0.8,0.8),1.0)),"behind-origin off-axis circle with negative farroot cannot clamp to false zero hit")
 var rear_rock=make();rear_rock.obstacles.append({"type":"rock","position":Vector2(19.3,0.8),"velocity":Vector2.ZERO,"radius":1.0,"health":100.0,"mass":20.0,"conductive":true,"destructible":true})
 fire_direct(rear_rock)
 check(rear_rock.threats.ray_records[0].part_id==1 and rear_rock.obstacles[0].health==100.0 and rear_rock.parts[1].hp==88.0,"off-axis solid behind muzzle cannot intercept forward cargo ray")
 var rear_part=make([part(1,"cargo",0,0,100),part(2,"battery",0,1,300),part(3,"armor",0,4)])
 rear_part.body_for_part(3).position+=Vector2(18.844,0.344)-rear_part._part_position(rear_part.parts[3])
 fire_direct(rear_part)
 check(rear_part.threats.ray_records[0].part_id==1 and rear_part.parts[3].hp==150.0 and rear_part.parts[1].hp==88.0,"off-axis module behind muzzle cannot intercept forward cargo ray")
 var rock=make();rock.obstacles.append({"type":"rock","position":Vector2(10,0),"velocity":Vector2.ZERO,"radius":1.0,"health":100.0,"mass":20.0,"conductive":true,"destructible":true})
 fire_direct(rock)
 check(rock.threats.ray_records[0].hit_kind=="obstacle" and rock.obstacles[0].health==88.0 and rock.ship_integrity()==1.0,"nearest actual solid intercepts and receives laser damage")
 var armored=make([part(1,"cargo",0,0,100),part(2,"battery",0,1,300),part(3,"armor",1,0)])
 fire_direct(armored)
 check(armored.threats.ray_records[0].part_id==3 and armored.parts[3].hp==138.0 and armored.ship_integrity()==1.0,"armor protects only by being first actual ray intersection")
 var shielded=make([part(1,"cargo",0,0,100),part(2,"battery",0,1,300),part(3,"shield",0,2,20)])
 var before:float=shielded.total_energy();fire_direct(shielded)
 check(shielded.ship_integrity()==1.0 and absf(before-shielded.total_energy()-18.0)<0.0001 and shielded.threats.ray_records[0].shield_energy_j==18.0,"connected enabled shield pays actual18J to absorb12HP laser")
 var empty=make([part(1,"cargo",0,0,100),part(2,"battery",0,1,300),part(3,"shield",0,2,20)])
 empty.parts[2].energy=0.0;fire_direct(empty)
 check(empty.parts[1].hp==88.0 and empty.threats.ray_records[0].shield_energy_j==0.0,"unpowered shield does not provide free protection")
 var isolated=make([part(1,"cargo",0,0,100),part(2,"battery",0,1,300),part(3,"shield",0,4,20)])
 fire_direct(isolated)
 check(isolated.parts[1].hp==88.0,"detached shield cannot protect a different body")
func physical_collider()->void:
 var s=make([],{"position":[10.0,0.0]});s.threats.activate(s);s.body_for_part(1).velocity=Vector2(6,0)
 advance(s,180)
 check(int(s.telemetry.get("swept_contacts",0))>0 and s.cargo_position().x<10.0,"stationary pirate is inherited swept physical collision geometry")
 check(float(s.obstacles[0].health)<40.0 and float(s.telemetry.cargo_contact_impulse)>0.0,"ram impact affects pirate health and actual cargo impulse")
func turbulence()->void:
 var s=make([],{"position":[90.0,90.0]},{"bounds":[-10.0,-10.0,20.0,20.0]})
 s.threats.activate(s);advance(s,120)
 var b:Dictionary=s.body_for_part(1)
 check(b.velocity.length()>0.05 and absf(float(b.angular_velocity))>0.01,"bounded field changes real translation and spin through force integration")
 check(s.ship_integrity()==1.0,"turbulence never directly or randomly subtracts cargoHP")
 var mass:float=float(b.mass);var total_source:Vector2=Vector2.ZERO;var source_torque:float=0.0
 for p in b.parts:
  var source:Vector2=s._source_forces.get(p.id,Vector2.ZERO);total_source+=source;source_torque+=p.local_pos.rotated(float(b.angle)-float(b.angular_velocity)/120.0).cross(source)
 check(total_source.distance_to(b.force)<0.0001 and absf(source_torque-float(b.torque))<0.0001 and mass>0,"socket bookkeeping represents the same applied net force and torque")
 var bounded:bool=true
 for tick in range(840):
  s.elapsed=float(tick)/120.0;var f:Dictionary=s.threats.field_for_body(s,{"position":Vector2.ZERO})
  bounded=bounded and Vector2(f.force).length()<=18.00001 and absf(float(f.torque))<=10.00001
 check(bounded,"periodic force and torque never exceed authored18N10Nm bounds")
 s.elapsed=4.0
 check(not s.threats.field_for_body(s,{"position":Vector2.ZERO}).active and s.threats.field_for_body(s,{"position":Vector2.ZERO}).force==Vector2.ZERO,"quiet phase permits waiting without physical forcing")
 s.elapsed=1.0
 check(not s.threats.field_for_body(s,{"position":Vector2(12,0)}).active,"moving around bounded region avoids turbulence")
func replay()->void:
 var a=make([],{"position":[20.0,0.0]},{"bounds":[-3.0,-3.0,6.0,6.0]})
 var b=make([],{"position":[20.0,0.0]},{"bounds":[-3.0,-3.0,6.0,6.0]})
 a.threats.activate(a);b.threats.activate(b);advance(a,720);advance(b,720)
 check(a.threats.snapshot()==b.threats.snapshot() and a.parts==b.parts and a.bodies==b.bodies and a.obstacles==b.obstacles,"same fixed input replay reproduces warnings rays bodyforces and all physical state")
