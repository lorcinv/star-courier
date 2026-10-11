extends "res://tests/test_corridor_framing.gd"
## Scripted poses establish containment/immutability/interruptions, not flight
## success or fair handling of every build. Generated catalog bytes stay frozen.
const Catalog=preload("res://scripts/seeded_offer_catalog.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const Moon=preload("res://scripts/pilot_moon_profile.gd")
const Wormhole=preload("res://scripts/pilot_wormhole_profile.gd")
func representatives() -> Array:
 var result:Array=[Ground.route(),Extreme.route()];var layouts:Dictionary={}
 for seed_value in range(1,60):
  for kind in ["ground","ascent"]:
   var base:Dictionary={"id":0 if kind=="ground" else 2,"weight":1.0 if kind=="ground" else 2.0,"reward":165 if kind=="ground" else 280,"rep":0 if kind=="ground" else 4,"name":"catalog","cargo":"catalog","client":"catalog"}
   var made:Dictionary=Catalog.create_new_offer(base,{"version":Catalog.VERSION,"world_seed":seed_value},7,1,kind,"human_courier")
   if made.ok and not layouts.has(made.offer.generation.layout_template):layouts[made.offer.generation.layout_template]=true;result.append(made.offer)
  if layouts.size()==6:break
 check(layouts.size()==6,"all six immutable generation-v1 layout templates represented")
 return result
func place(point:Vector2,angle:float) -> void:
 var body:Dictionary=game.sim.body_for_part(1);body.angle=angle;body.position+=point-game.sim.cargo_position();body.velocity=Vector2(18,-7)
func pose(label:String,point:Vector2,angle:float) -> void:
 place(point,angle)
 var before:PackedByteArray=physical()
 game.world.settle_resumed_flight(game.sim)
 var frame:Dictionary=game.world._corridor_frame
 var body:Rect2=screen_box(frame.craft)
 var audit:Dictionary=Frame.measure(game.sim,game.world.flight_origin,72,frame,game.world.camera.position,game.world.smooth_zoom,actual_occluders())
 check(hud_clear(body),"whole rotated connected body in real native HUD-safe art: "+label)
 check(frame.center.is_finite() and is_finite(frame.zoom) and frame.zoom>0,"finite bounded camera: "+label)
 check(physical()==before,"no saved route, physics, input, or clocks mutated: "+label)
 report.poses.append({"case":label,"position":point,"angle":angle,"art":game.view_container.display_rect,"canvas":game.view_container.canvas_size,"pixel_scale":game.view_container.pixel_scale,"craft_native":body,"craft_source_pixels":body.size/float(game.view_container.pixel_scale),"frame_zoom":frame.zoom,"bounded_geometry_fit":frame.bounded_geometry_fit,"below_provisional_40_logical_pixel_review_floor":frame.body_below_provisional_review_floor,"required_faces":audit.faces.filter(func(f):return f.gate==frame.next_gate).map(func(f):return {"gate":f.gate,"side":f.side,"samples":f.inward_visible,"nearest":f.nearest_visible,"horizontal_seconds":f.horizontal_seconds})})
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false);await settle()
 game.settings.reduced_motion=true;game._apply_quality()
 var routes:Array=representatives()
 var tall:Array=[Extreme.part(1,"cargo",0)]
 for y in range(-6,3):
  if y!=0:tall.append(Extreme.part(20+y+6,"beam",0,y))
 var dense:Array=[]
 for x in range(-4,13):
  for y in range(-6,3):dense.append(Extreme.part(1 if x==0 and y==0 else 100+dense.size(),"cargo" if x==0 and y==0 else "beam",x,y))
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  for density in ["auto","balanced","low"]:
   game.settings.pixel_density=density;game._apply_quality();await settle()
   for route in routes:
    game._configure_flight(true,Extreme.starter_design(),Extreme.starter_launcher(),route,true);game.paused=true;await settle()
    for gate in [route.pilot_gates[0],route.pilot_gates[1],route.pilot_gates[-1]]:
     var x:float=float(gate.x)-48.0
     for angle in [-.7,0.0,.7]:pose("%s %s %s gate%d"%[str(extent),density,str(route.get("generation",{}).get("layout_template",route.get("route_profile","authored-ascent"))),int(gate.index)],Vector2(x,Ascent.path_y(x,route)),angle)
   for design in [Extreme.reinforced_design(),tall,dense]:
    game._configure_flight(true,design,Extreme.starter_launcher(),routes[-1],true);game.paused=true;await settle()
    game.hud.content.get_node("FlightEventReceipt").show()
    for gate in [routes[-1].pilot_gates[0],routes[-1].pilot_gates[1],routes[-1].pilot_gates[-1]]:
     var x:float=float(gate.x)-36.0
     for angle in [-.7,0.0,.7]:pose("%s %s %d parts gate%d"%[str(extent),density,design.size(),int(gate.index)],Vector2(x,Ascent.path_y(x,routes[-1])),angle)
   # Pause/focus, repeated render, resize, and restore each supported mapper.
   game._configure_flight(true,Extreme.starter_design(),Extreme.starter_launcher(),routes[-1],true);game.paused=true
   place(Vector2(174,-42),-.55);game.world.settle_resumed_flight(game.sim);game.world._scene_paused=true
   var saved:PackedByteArray=physical();var center:Vector2=game.world.smooth_center;var zoom:float=game.world.smooth_zoom
   for i in 10:game.world.show_flight(game.sim,true);game.world._process(.2)
   check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"unchanged pause freezes position and zoom "+str(extent)+density)
   game.world._scene_paused=false;game.world.set_focus_active(false);game.world._process(10)
   check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"focus loss freezes both camera states")
   game.world.set_focus_active(true);game.world._scene_paused=true
   game.world.start_flight(game.sim,true);game.world.settle_resumed_flight(game.sim)
   check(game.world.launch_age==1.35 and not game.world.flight_nodes.launch_burst.visible,"restart settles from snapshot without re-ignition")
   check(hud_clear(screen_box(game.world._corridor_frame.craft)),"restored actual body still HUD clear")
   check(physical()==saved,"all lifecycle calls leave physical state unchanged")
 # Detached remote debris cannot change either body AABB or candidate frame.
 var original:Rect2=Frame.Shared.craft_bounds(game.sim,Vector2.ZERO,72)
 var original_frame:Dictionary=Frame.compose(game.sim,Vector2.ZERO,72,Vector2(1280,720),null,.25,{})
 game.sim.bodies.append({"parts":[],"position":Vector2(1e6,-1e6),"angle":1.0,"velocity":Vector2(1000,-1000)})
 var after_frame:Dictionary=Frame.compose(game.sim,Vector2.ZERO,72,Vector2(1280,720),null,.25,{})
 check(Frame.Shared.craft_bounds(game.sim,Vector2.ZERO,72)==original and after_frame.center==original_frame.center and after_frame.zoom==original_frame.zoom,"detached debris cannot own framing")
 check(not Frame.applies(Moon.route()) and not Frame.applies(Wormhole.route()),"approved Moon and wormhole policies excluded")
 # A deliberate low/late off-corridor state cannot be silently certified.
 game._configure_flight(true,Extreme.starter_design(),Extreme.starter_launcher(),routes[-1],true);place(Vector2(165,0),.6);game.world.settle_resumed_flight(game.sim)
 check(not game.world._corridor_frame.bounded_geometry_fit,"unachievable single-frame preview is explicitly marked as a feasibility failure")
 report.passed=passed;report.failures=failures
 var output_path:String=OS.get_environment("CORRIDOR_OUTPUT")
 if output_path.is_empty():output_path="user://corridor-framing-matrix.json"
 var out=FileAccess.open(output_path,FileAccess.WRITE);out.store_string(JSON.stringify(encode(report),"  "));out.close()
 game.queue_free();game=null;await settle();print("Corridor matrix: %d passed, %d failed, %d poses"%[passed,failures.size(),report.poses.size()]);quit(1 if not failures.is_empty() else 0)
