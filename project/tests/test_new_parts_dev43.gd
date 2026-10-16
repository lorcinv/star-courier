extends SceneTree
const R=preload("res://scripts/pilot_delivery_rift_simulation_v8.gd")
const G=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
const P=preload("res://scripts/pilot_delivery_profile_v8.gd")
const W=preload("res://scripts/workshop_parts_v2.gd")
const DB=preload("res://scripts/parts_expanded.gd")
var pass_count=0
var failures=0
func check(ok:bool,label:String):
 if ok:pass_count+=1
 else:failures+=1;push_error(label)
func part(id:int,kind:String,x:int,y:int)->Dictionary:return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":DB.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
func _initialize():
 check(W.sale_kinds().size()==14 and W.is_core("heater") and W.is_core("airbrake"),"14 real shop parts")
 for kind in ["heater","airbrake"]:
  check(ResourceLoader.exists("res://assets/2d_v5/modules/"+kind+"-pixel.png"),"real dedicated art "+kind)
  check(W.compatible(kind,false,"pilot-delivery-v8") and not W.compatible(kind,true,"pilot-delivery-v8"),"ship only")
 check(W.new_part(9,"airbrake",0,1,[],false,true,"pilot-delivery-v8").input_a==-2,"normal placement held input")
 var f:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_RIFT_FIXED")))
 var losses=[]
 for condition in ["on","off","empty","far","cut","warm","half"]:
  var design=[part(1,"cargo",0,0),part(2,"battery",-1,0),part(3,"heater",1,0)]
  if condition=="far":design[2].x=2;design.append(part(4,"beam",1,0))
  if condition=="off":design[2].input_a=999
  var s=R.new();s.configure(design,[],f.route,42)
  var cargo:Dictionary=s.parts[1];var b:Dictionary=s.body_for_part(1)
  # Isolated cold boundary unit fixture, NOT a played portal crossing.
  b.position=Vector2(160,0) if condition!="warm" else Vector2(200,60)
  cargo.rift_portal_id=f.route.required_portal_id
  s._rift_exposure[1]=float(f.route.rift_biology.grace_seconds)+1.0
  if condition=="empty":s.parts[2].energy=0
  if condition=="cut":s._cut(1,3)
  if condition=="half":s.parts[3].output_factor=.5
  var initial:float=cargo.hp;s._enemy_attacks(.1)
  var loss:float=initial-float(cargo.hp);losses.append(loss)
  print("HEATER_UNIT ",condition," loss=",loss," energy=",s.telemetry.get("heater_energy_used",0))
 check(losses[0]>0 and is_equal_approx(losses[0],losses[1]*.2),"paid heater reduces exactly80% not immunity")
 check(is_equal_approx(losses[1],losses[2]) and is_equal_approx(losses[1],losses[3]) and is_equal_approx(losses[1],losses[4]),"off empty remote cut no protection")
 check(is_zero_approx(losses[5]),"warm no cold")
 check(is_equal_approx(losses[6],losses[1]*.6),"split material halves protection")
 var g=G.new();g.configure([part(1,"cargo",0,0),part(2,"battery",-1,0),part(3,"airbrake",0,1)],[],C.fresh_route(1),42)
 var b:Dictionary=g.body_for_part(1);b.velocity=Vector2(12,0);b.force=Vector2.ZERO;b.torque=0
 g._apply_airbrake(g.parts[3],b,1.0/120)
 check(b.force.x<0 and absf(b.torque)>0,"real opposing force and eccentric torque")
 check(is_zero_approx(float(g.telemetry.energy_used)),"no battery draw for air resistance")
 g.route.pilot_drag=0;b.force=Vector2.ZERO;b.torque=0;g._apply_airbrake(g.parts[3],b,1.0/120)
 check(b.force==Vector2.ZERO and b.torque==0,"vacuum zero force")
 # Real old save load, normal purchase/save/reload. No money or inventory injection.
 if not OS.get_environment("SC_NATIVE_D3").is_empty():
  var bytes=FileAccess.get_file_as_bytes(OS.get_environment("SC_NATIVE_D3"));var raw=JSON.parse_string(bytes.get_string_from_utf8())
  var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
  var e=load("res://scripts/economy.gd").new();e.load_state();e.enable_story_mode()
  check(not e.review_load_blocked,"genuine old save loads")
  var money:int=e.credits
  check(e.buy_part("heater",DB.catalog().heater).ok and e.buy_part("airbrake",DB.catalog().airbrake).ok,"normal purchase two parts")
  check(e.credits==money-80 and e.inventory.get("heater",0)==1 and e.inventory.get("airbrake",0)==1,"actual80 cost inventory")
  check(e.save_state(raw.design,raw.launcher,raw.settings),"save purchased inventory")
  var again=load("res://scripts/economy.gd").new();again.load_state()
  check(not again.review_load_blocked and again.credits==money-80 and again.inventory.get("heater",0)==1 and again.inventory.get("airbrake",0)==1,"purchases survive reload")
 print("NEW_PARTS_DEV43 passed=",pass_count," failed=",failures," native=false cold_fixture_position_injected=true")
 quit(1 if failures else 0)
