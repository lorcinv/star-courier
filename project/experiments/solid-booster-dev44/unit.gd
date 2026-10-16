extends SceneTree
const S=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
const P=preload("res://scripts/pilot_delivery_profile_v8.gd")
var failed=0
func ck(label:String,ok:bool,detail:Variant=null):
 print("CHECK ",label," ",ok," ",detail)
 if not ok:failed+=1
func make():
 var s=S.new();s.configure([{"id":1,"type":"cargo","x":0,"y":0},{"id":2,"type":"solid_booster","x":-1,"y":0,"rotation":0,"input_a":-2}],P.starter_launcher(),C.fresh_route(1),42);return s
func _initialize():
 var s=make();var p=s.parts[2];var b=s.body_for_part(2)
 ck("wet mass",is_equal_approx(p.mass,1.8),p.mass)
 ck("manual unlit inactive",not s._enabled(p))
 var poses={};var velocities={}
 b.angular_velocity=.3;b.velocity=Vector2(2,3);b.angle=.4
 for q in b.parts:poses[q.id]=s._part_position(q);velocities[q.id]=s._part_velocity(q)
 s._apply_solid_booster(p,b,1.0/60);s._update_solid_mass()
 ck("ignition latches after release",s._enabled(p))
 var kept=true
 for q in b.parts:kept=kept and poses[q.id].distance_to(s._part_position(q))<.00001 and velocities[q.id].distance_to(s._part_velocity(q))<.00001
 ck("mass shift preserves point pose velocity",kept)
 for i in range(719):s._apply_solid_booster(p,b,1.0/60);s._update_solid_mass()
 ck("burnout 12 seconds",is_zero_approx(p.solid_fuel_fraction) and not s._enabled(p),p.solid_fuel_fraction)
 ck("finite 336 Ns",absf(s.telemetry.solid_impulse-336)<.001,s.telemetry.solid_impulse)
 ck("dry mass .8",is_equal_approx(p.mass,.8),p.mass)
 ck("fuel fee 20",absf(s.telemetry.ammo_cost-20)<.00001,s.telemetry.ammo_cost)
 ck("full receipt fuel exactly 20",C.quote(s.route,s.telemetry,false).ammo==20,C.quote(s.route,s.telemetry,false).ammo)
 var z=make();ck("unlit receipt zero",C.quote(z.route,z.telemetry,false).ammo==0)
 z._apply_solid_booster(z.parts[2],z.body_for_part(2),3.0);ck("quarter fuel receipt five",C.quote(z.route,z.telemetry,false).ammo==5)
 ck("no electric fuel source",is_zero_approx(s.telemetry.energy_used),s.telemetry.energy_used)
 var impulse=s.telemetry.solid_impulse
 s._apply_solid_booster(p,b,1);ck("no reignition",s.telemetry.solid_impulse==impulse)
 var t=make();var tp=t.parts[2];var tb=t.body_for_part(2)
 t._apply_solid_booster(tp,tb,11.995);t._update_solid_mass();t._apply_solid_booster(tp,tb,1.0/60);t._update_solid_mass()
 ck("partial final tick bounded",absf(t.telemetry.solid_impulse-336)<.001 and is_equal_approx(tp.mass,.8))
 # Normal fixed-step controls; one ignition tick then release. Replay same inputs.
 var a=make();var c=make();a.release_launcher(15,.1);c.release_launcher(15,.1)
 for i in range(120):
  for sim in [a,c]:
   sim.set_free_flight_input(0,0,false,i==0,2,false);sim.step(1.0/60)
 ck("normal step burns after key release",float(a.parts[2].solid_fuel_fraction)<.85,a.parts[2].solid_fuel_fraction)
 ck("input replay fuel pose deterministic",a.parts[2].solid_fuel_fraction==c.parts[2].solid_fuel_fraction and a.cargo_position()==c.cargo_position())
 # Powered adjacent splitter divides remaining material instead of duplicating it.
 var split=S.new();split.configure([{"id":1,"type":"cargo","x":0,"y":0},{"id":2,"type":"solid_booster","x":1,"y":0,"input_a":-2},{"id":3,"type":"splitter","x":1,"y":1,"target":2},{"id":4,"type":"battery","x":0,"y":1}],P.starter_launcher(),C.fresh_route(1),42)
 split._apply_solid_booster(split.parts[2],split.body_for_part(2),3);split._update_solid_mass()
 split._split_module(split.parts[3],split.parts[2],split.body_for_part(3),1.0/60)
 var fuel=0.0;var mass=0.0;var count=0;var latched=true
 for q in split.parts.values():
  if q.type=="solid_booster":fuel+=q.solid_fuel_fraction*q.output_factor;mass+=q.mass;count+=1;latched=latched and q.solid_lit
 ck("split preserves .75 fuel and 1.55 material",count==2 and absf(fuel-.75)<.00001 and absf(mass-1.55)<.00001,[count,fuel,mass])
 ck("split keeps ignition state",latched)
 for q in split.parts.values():
  if q.type=="solid_booster":split._apply_solid_booster(q,split.body_for_part(q.id),9)
 split._update_solid_mass()
 ck("split total impulse remains 336",absf(split.telemetry.solid_impulse-336)<.001,split.telemetry.solid_impulse)
 ck("split total fuel fee remains 20",absf(split.telemetry.ammo_cost-20)<.001,split.telemetry.ammo_cost)
 var quarter=make()
 for i in range(360):quarter._apply_solid_booster(quarter.parts[2],quarter.body_for_part(2),1.0/120)
 ck("quarter receipt at real 120Hz exactly five",C.quote(quarter.route,quarter.telemetry,false).ammo==5,quarter.telemetry.ammo_cost)
 var cut=S.new();cut.configure([{"id":1,"type":"cargo","x":0,"y":0},{"id":2,"type":"solid_booster","x":0,"y":2,"rot":3,"input_a":-2},{"id":4,"type":"coupler","x":0,"y":1,"target":2,"input_a":-2}],P.starter_launcher(),C.fresh_route(1),42)
 cut._apply_solid_booster(cut.parts[2],cut.body_for_part(2),12);cut._update_solid_mass()
 var before=cut.body_for_part(1).mass;var dry=cut.parts[2].mass
 cut._cut(4,2);cut._rebuild_bodies()
 ck("coupler drops real .8kg dry shell",absf(before-cut.body_for_part(1).mass-.8)<.00001 and cut.parts[1].body_id!=cut.parts[2].body_id,dry)
 ck("detached shell cannot restart",not cut._enabled(cut.parts[2]) and is_zero_approx(cut.parts[2].solid_fuel_fraction))
 print("FAILED ",failed);quit(failed)
