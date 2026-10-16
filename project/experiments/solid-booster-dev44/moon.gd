extends SceneTree
const S=preload("res://scripts/pilot_delivery_ascent_simulation_v8.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
func _initialize():
 for mode in ["electric","solid_keep","solid_drop"]:fly(mode)
 quit()
func fly(mode:String):
 var f=JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/moon-fixed.json"))
 var ship:Array=f.ship
 if mode!="electric":
  ship=[{"id":1,"type":"cargo","x":0,"y":0},{"id":2,"type":"battery","x":0,"y":-1},{"id":3,"type":"thruster","x":0,"y":1,"param":28},{"id":4,"type":"coupler","x":0,"y":2,"target":5,"input_a":-2},{"id":5,"type":"solid_booster","x":0,"y":3,"rot":3,"input_a":-2}]
 var s=S.new();s.configure(ship,f.launcher,f.route,42);var launch=s.release_launcher(90,1)
 var price=0
 for p in ship:
  if p.type!="cargo":price+=int(Parts.catalog()[p.type].price)
 for tick in range(60*100):
  if s.status!="running":break
  var b=s.body_for_part(1);var at=s.cargo_position();var delta=Vector2(40,-560)-at
  var speed=minf(20,sqrt(4*maxf(0,delta.length()-2)))
  var desired=(delta.normalized()*speed-b.velocity).limit_length(2)
  var env=s.environment_at(at)
  desired-=Vector2(0,env.gravity)+Vector2(env.wind)
  var output=0.0
  for p in b.parts:
   if p.type=="thruster":output+=p.param*p.output_factor*.72
   if p.type=="solid_booster" and float(p.solid_fuel_fraction)>0 and (tick==0 or p.solid_lit):desired-=Vector2.RIGHT.rotated(b.angle+p.local_angle)*28.0*p.output_factor/b.mass
  var input=desired*b.mass/maxf(.01,output)
  var active=mode!="electric" and (tick==0 or (mode=="solid_drop" and tick==721))
  s.set_free_flight_input(roundi(input.x*1000),roundi(input.y*1000),false,active,4 if tick==721 else 5,false)
  s.step(1.0/60)
 print("MOON ",JSON.stringify({"mode":mode,"hardware":price,"status":s.status,"seconds":s.elapsed,"integrity":s.ship_integrity(),"energy":s.telemetry.energy_used,"fuel":s.telemetry.get("solid_fuel_used",0),"impulse":s.telemetry.get("solid_impulse",0),"ammo":s.telemetry.ammo_cost,"position":[s.cargo_position().x,s.cargo_position().y],"quote":C.quote(f.route,s.telemetry,s.status=="success")}))
