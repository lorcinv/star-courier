extends SceneTree
## Defensive dispatch only. Scripted camera poses compare unchanged exact
## frame/release outputs; they do not establish physical flight or fairness.
const Current=preload("res://scripts/readable_corridor_framing_2d.gd")
const Frozen=preload("res://tests/fixtures/readable_camera_pre_defense.gd")
const Econ=preload("res://scripts/economy.gd")
const Catalog=preload("res://scripts/readable_offer_catalog.gd")
const Guard=preload("res://scripts/readable_offer_guard.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const Moon=preload("res://scripts/pilot_moon_profile.gd")
const Wormhole=preload("res://scripts/pilot_wormhole_profile.gd")
const Bird=preload("res://scripts/protected_bird_offer_v1.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
var assertions:int=0
var failures:Array=[]
var poses:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 assertions+=1
 if not ok:failures.append(label);push_error("FAIL "+label)
func bytes(value:Variant) -> String:return JSON.stringify(value,"",true,true)
func run() -> void:
 var old_source:String=FileAccess.get_file_as_string("res://tests/fixtures/readable_camera_pre_defense.gd")
 var new_source:String=FileAccess.get_file_as_string("res://scripts/readable_corridor_framing_2d.gd")
 check(old_source.substr(old_source.find("static func compose"))==new_source.substr(new_source.find("static func compose")),"compose and reviewed release math remain byte-identical")
 var routes:Array=[]
 var opaque:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/readable_opaque_qa.json"))
 for name in opaque:
  check(Current.applies(opaque[name]) and Frozen.applies(opaque[name]),"reviewed opaque "+str(name)+" still uses identical camera")
  routes.append(opaque[name])
 for seed_value in [0,42,807]:
  for id in [0,1,2]:
   for slot in [0,1]:
    var base:Dictionary=Econ.new()._autonomous_routes()[id]
    base=Ground.route(base) if id==0 else Extreme.route(base)
    var made:Dictionary=Catalog.create_new_offer(base,{"version":Catalog.POLICY,"world_seed":seed_value},8,slot,"ground" if id==0 else "ascent",["alien_botanist","robot_machinist"][slot])
    check(made.ok and Guard.recognized(made.offer) and Current.applies(made.offer)==Frozen.applies(made.offer),"fully guarded new ordinary source keeps camera eligibility")
    routes.append(made.offer)
 var anchor:Vector2=Vector2(300,550)
 for route in routes:
  for design in [Extreme.starter_design(),Extreme.reinforced_design()]:
   var sim=Sim.new();sim.configure(design,Extreme.starter_launcher(),route,807)
   var before_route:String=bytes(sim.route)
   for extent in [Vector2(1280,720),Vector2(1920,1080),Vector2(3840,2160)]:
    var previous_a:Dictionary={};var previous_b:Dictionary={}
    for x in [0.0,float(route.pilot_gates[0].x)-48.0,float(route.pilot_gates[1].x)-30.0,float(route.distance)-12.0]:
     for angle in [-0.35,0.0,0.35]:
      var body:Dictionary=sim._cargo_body();body.angle=angle;body.position+=Vector2(x,Ascent.path_y(x,route))-sim.cargo_position();body.velocity=Vector2(18,-1);sim.elapsed+=.1
      var a:Dictionary=Current.compose(sim,anchor,72.0,extent,null,previous_a)
      var b:Dictionary=Frozen.compose(sim,anchor,72.0,extent,null,previous_b)
      check(bytes(a)==bytes(b),"valid starter/heavy/ground full camera output byte parity")
      for amount in [-.1,0.0,.125,.5,1.0,1.1]:
       var release_a:Dictionary=Current.release_frame(a.craft,a.craft.get_center(),.82,a.center,a.zoom,a.scene_size,a.craft_safe,amount)
       var release_b:Dictionary=Frozen.release_frame(b.craft,b.craft.get_center(),.82,b.center,b.zoom,b.scene_size,b.craft_safe,amount)
       check(bytes(release_a)==bytes(release_b),"reviewed launch-release full output unchanged")
      previous_a=a;previous_b=b;poses+=1
   check(bytes(sim.route)==before_route,"camera output comparison never mutates saved physics route")
 var ordinary:Dictionary=opaque["ascent-heavy"].duplicate(true)
 for kind in ["pursuit","moon","wormhole","protected-area","",null,true,3]:
  var bad:Dictionary=ordinary.duplicate(true);bad.generation.kind=kind
  check(not Current.applies(bad),"nonordinary/malformed generation family refuses forward-edge framing")
 for kind in ["pursuit","moon","wormhole","ground","ascent",null,true,3]:
  var bad:Dictionary=ordinary.duplicate(true);bad.route_kind=kind
  check(not Current.applies(bad),"special/pursuit/foreign explicit ascent route kind rejected outside Economy")
 ordinary.route_kind="";check(Current.applies(ordinary),"reviewed ascent explicit empty route kind remains supported")
 ordinary=opaque["ground-heavy"].duplicate(true)
 for kind in ["pursuit","moon","wormhole","ascent","",null,true,3]:
  var bad:Dictionary=ordinary.duplicate(true);bad.route_kind=kind
  check(not Current.applies(bad),"ground marker must remain exact even outside Economy")
 ordinary.erase("route_kind");check(not Current.applies(ordinary),"missing explicit ground identity cannot claim ordinary framing")
 var bird:Dictionary=Bird.create_new_offer({"version":Bird.POLICY,"world_seed":42,"introduced_day":0},5,"human_courier").offer
 for route in [Extreme.route(),Ground.route(),Moon.route(),Wormhole.route(),bird]:check(not Current.applies(route) and not Frozen.applies(route),"old/special camera routing unaffected")
 var report:Dictionary={"assertions":assertions,"failures":failures,"scripted_poses":poses,"scope":"Exact function/output parity and defensive applicability only; no new native/human fairness or performance conclusion."}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):
   var file=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
   if file!=null:file.store_string(JSON.stringify(report,"  ",true,true));file.close()
 print("READABLE_CAMERA_APPLICABILITY assertions=%d failures=%d poses=%d"%[assertions,failures.size(),poses]);quit(0 if failures.is_empty() else 1)
