extends SceneTree
## Isolated scene/transform checks. Does not certify native piloting or rendered
## appearance. Run with the separately reviewed new-contract/bootstrap patch.
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Backdrop=preload("res://scripts/ascent_backdrop_2d.gd")
const World=preload("res://scripts/world_view_2d.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
const EXPECTED_CHECKS:int=72
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for i in 4:await process_frame
func same_edges(image:Image) -> bool:
 for y in image.get_height():
  var a:Color=image.get_pixel(0,y);var b:Color=image.get_pixel(image.get_width()-1,y)
  if a.a!=b.a or Color(a.r*a.a,a.g*a.a,a.b*a.a,a.a)!=Color(b.r*b.a,b.g*b.a,b.b*b.a,b.a):return false
 return true
func sim_for(route:Dictionary,design:Array=Extreme.starter_design()):
 var sim=Sim.new();sim.configure(design,Extreme.starter_launcher(),route,3);return sim
func backdrop_checks() -> void:
 var canvas=CanvasLayer.new();root.add_child(canvas)
 var back=Backdrop.new();canvas.add_child(back)
 check(back.get_child_count()==7 and back.near_city==null,"legacy backdrop retains its original seven-plane pool")
 back.configure_route(Ground.route())
 check(back.get_child_count()==8 and back.near_city.visible and back.debug_snapshot().ground_route,"explicit ground marker adds one cached near-depot raster layer")
 check(back.near_city.texture.resource_path.ends_with("ground/near-city-strip.png") and not back.near_city.flip_h and not back.near_city.flip_v,"ground layer uses the original generated derivative without reflection")
 check(back.near_city.material.get_shader_parameter("repeat_x") and not back.near_city.material.get_shader_parameter("repeat_y") and not back.near_city.material.get_shader_parameter("clamp_y"),"rooftops repeat horizontally only; no repeated or stretched vertical floor")
 check(same_edges(back.near_city.texture.get_image()),"runtime near-city premultiplied RGBA seam is exact, including transparent edges")
 back.update_flight(Vector2(60,-4),Vector2(18,0),.2,Vector2(12,-4))
 var state:Dictionary=back.debug_snapshot()
 check(state.ground_scroll==Vector2(168,-200),"near-depot parallax follows the same actual camera in metres")
 check(state.ground_scroll.x>state.city_scroll.x,"near-depot layer has stronger horizontal depth than the far city")
 check(346-state.ground_scroll.y>=500,"the first opaque roof pixels stay below the ordinary flight band")
 var node_id:int=back.near_city.get_instance_id();var material=back.near_city.material
 var bounded:bool=true;var city_only:bool=true
 for i in 600:
  var x:float=float(i)*7.37
  var y:float=-8.0*float(i)/599.0
  back.update_flight(Vector2(x,y),Vector2(18,-2),float(i)/599.0,Vector2(x,-4+y))
  state=back.debug_snapshot()
  bounded=bounded and state.ground_scroll.is_finite() and state.ground_scroll.x>=0 and state.ground_scroll.x<1280 and state.ground_scroll==state.ground_scroll.round()
  city_only=city_only and state.orbit_weight==0 and not back.starfield.visible and not back.planet.visible and back.near_city.visible
 check(bounded and city_only,"entire ground route remains a bounded city panorama without an orbit crossfade")
 var hostile:Dictionary=Ground.route();hostile.background_route="orbit";back.configure_route(hostile)
 back.update_flight(Vector2(360,-150),Vector2.ZERO,1)
 check(back.debug_snapshot().orbit_weight==0 and not back.planet.visible,"ground content marker also prevents accidental orbit art at high saved altitude")
 back.update_flight(Vector2(110,-5),Vector2(28,-3),.3,Vector2(20,-5))
 check(back.debug_snapshot().ground_blur.length()<=Backdrop.MAX_BLUR_PX*.45+.001,"ground-only texture blur has a bounded footprint")
 back.reduced_motion=true
 check(back.debug_snapshot().ground_blur==Vector2.ZERO,"reduced motion clears near-depot blur without changing positions")
 back.reduced_motion=false;back.motion_blur_enabled=false
 check(back.debug_snapshot().ground_blur==Vector2.ZERO,"separate motion-blur setting also covers the new layer")
 back.motion_blur_enabled=true
 back.update_flight(Vector2(110,-5),Vector2.ZERO,.3,Vector2(20,-5))
 check(back.debug_snapshot().ground_blur==Vector2.ZERO,"pause zero velocity clears ground blur immediately")
 var legacy:Dictionary=Ground.route();legacy.erase("route_profile");legacy.background_route="city_to_orbit"
 back.configure_route(legacy);back.update_flight(Vector2(360,-150),Vector2.ZERO,1)
 check(not back.near_city.visible and back.planet.visible and not back.debug_snapshot().ground_route,"unmarked saved route with ground-like metadata keeps legacy ascent presentation")
 for marker in ["", "ground-city-v2", "pilot-v3"]:
  legacy.route_profile=marker;back.configure_route(legacy)
  check(not back.near_city.visible,"only the exact supported ground marker selects the layer: "+marker)
 for i in 20:back.configure_route(Ground.route());back.configure_route(legacy)
 check(back.get_child_count()==8 and back.near_city.get_instance_id()==node_id and back.near_city.material==material,"repeated ground/ascent changes reuse the cached node and material")
 var periodic:bool=true
 for tile in range(-8,9):
  for offset in [.5,22,640,1279]:
   periodic=periodic and is_equal_approx(Backdrop.ordinary_coordinate(tile*1280+offset,1280),Backdrop.ordinary_coordinate((tile+1)*1280+offset,1280))
 check(periodic and Backdrop.ordinary_coordinate(1281,1280)==1 and Backdrop.ordinary_coordinate(2559,1280)==1279,"ordinary wrap retains forward building orientation on every alternate tile")
 canvas.queue_free();await settle()
func world_checks() -> void:
 var vp=SubViewport.new();vp.size=Vector2i(960,540);root.add_child(vp)
 var world=World.new();vp.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 for design in [Extreme.starter_design(),Extreme.reinforced_design()]:
  var route:Dictionary=Ground.route();var sim=sim_for(route,design)
  world.route_distance=route.distance;world.route_radius=route.delivery_radius
  world.show_design(design);world.focus("workshop",true)
  var before_bg:Dictionary=world.ascent_backdrop.debug_snapshot()
  var before_bodies:Array=sim.bodies.duplicate(true)
  world.start_flight(sim)
  var after_bg:Dictionary=world.ascent_backdrop.debug_snapshot()
  check(before_bg.city_scroll==after_bg.city_scroll and before_bg.sky_scroll==after_bg.sky_scroll and before_bg.cloud_scroll==after_bg.cloud_scroll,"ground dispatch preserves original shop/right-pad parallax registration")
  var cells_exact:bool=true
  for p in design:cells_exact=cells_exact and world.flight_nodes["p"+str(p.id)].position.distance_to(world.assembly_origin+Vector2(p.x,p.y)*World.CELL)<.8
  check(cells_exact and sim.bodies==before_bodies,"ground transfer starts every real module at its workshop cell without touching physics")
  world.launch_transfer_progress=1;world.show_flight(sim)
  var bottom:float=-INF
  for p in sim.parts.values():bottom=maxf(bottom,world.flight_nodes["p"+str(p.id)].position.y+World.CELL*.49)
  check(absf(bottom-World.CRADLE_CONTACT_Y)<.8,"ground craft retains physical right-pad underside registration")
  var kiosk:Sprite2D=world.flight_nodes.destination
  var goal:Vector2=world.flight_origin+Vector2(route.distance,route.destination_y)*World.CELL
  var deck:Vector2=kiosk.position+World.GROUND_RECEIVER_DECK*kiosk.scale
  check(str(kiosk.get_meta("art_id"))=="flight/receiver" and not kiosk.flip_h and not kiosk.flip_v,"explicit ground contract receives a nonmirrored generated depot kiosk")
  check(world.flight_nodes.cues.destination==goal and world.flight_nodes.cues.receiver_radius==route.delivery_radius*World.CELL,"ground capture cue exposes the saved physical goal and radius exactly")
  check(deck.is_equal_approx(goal+Vector2(0,route.delivery_radius*World.CELL+World.GROUND_RECEIVER_CLEARANCE)) and kiosk.get_meta("capture_center")==goal,"generated kiosk deck is centered just below the actual capture aperture")
  check(kiosk.texture.get_width()*kiosk.scale.x>=route.delivery_radius*World.CELL*2,"receiving deck spans the full capture aperture instead of a tiny decorative prop")
  check(world.flight_nodes.receipt_label.text==route.destination_name,"ground world label uses the actual saved destination")
  var hazards_exact:bool=true
  for i in sim.obstacles.size():
   var h:Dictionary=sim.obstacles[i];var sprite:Sprite2D=world.flight_nodes["h"+str(i)]
   hazards_exact=hazards_exact and sprite.visible and sprite.position==(world.flight_origin+h.position*World.CELL).round() and (sprite.texture.get_size()*sprite.scale).is_equal_approx(Vector2.ONE*h.radius*World.CELL*2)
  check(hazards_exact and sim.obstacles.size()==6,"all six real gate circles retain their exact visible positions and diameters")
  check(world.find_children("*","CollisionObject2D",true,false).is_empty(),"scenery integration adds no untested ground-plane colliders")
  var mapped:bool=true;var inverse:bool=true;var immutable:bool=true
  for angle in [-.6,0.0,.6]:
   var body:Dictionary=sim.body_for_part(1);body.angle=angle
   body.position+=Vector2(160,-8)-sim.cargo_position()
   var physical:Array=sim.bodies.duplicate(true)
   world.settle_resumed_flight(sim)
   for p in body.parts:
    var physical_point:Vector2=world.flight_origin+sim.part_world_position(int(p.id))*World.CELL
    var sprite:Sprite2D=world.flight_nodes["p"+str(p.id)]
    mapped=mapped and sprite.position==physical_point.round()
    var canvas:Transform2D=vp.get_canvas_transform()
    inverse=inverse and (canvas.affine_inverse()*(canvas*sprite.position)).distance_to(sprite.position)<.01
   immutable=immutable and sim.bodies==physical
  check(mapped and inverse and immutable,"ground and resumed/rotated full craft retain the same physical-to-canvas mapping and invertible input transform")
  world.leave_flight()
 var custom:Dictionary=Ground.route();custom.distance=401.0;custom.destination_y=-11.0;custom.delivery_radius=9.0;custom.destination_name="西侧收件台"
 var sim=sim_for(custom);world.route_distance=custom.distance;world.route_radius=custom.delivery_radius;world.start_flight(sim,true)
 var goal:Vector2=world.flight_origin+Vector2(401,-11)*World.CELL
 check(world.flight_nodes.cues.destination==goal and world.flight_nodes.cues.receiver_radius==9*World.CELL and world.flight_nodes.destination.get_meta("capture_center")==goal,"saved custom ground geometry is reused rather than re-authored by presentation")
 for route in [Extreme.route(),custom.duplicate(true)]:
  route.erase("route_profile");sim=sim_for(route);world.route_distance=route.distance;world.route_radius=route.delivery_radius;world.start_flight(sim,true)
  var dock:Sprite2D=world.flight_nodes.destination
  check(str(dock.get_meta("art_id"))=="space/orbital-mail-dock" and dock.offset==Vector2(-318,-213) and dock.scale==Vector2.ONE*1.65,"unmarked saved pilot-v3 keeps its original orbital dock geometry")
  check(world.ascent_backdrop.near_city==null or not world.ascent_backdrop.near_city.visible,"unmarked flight never inherits the previous contract's near-city layer")
 world.queue_free();vp.queue_free();await settle()
func telemetry() -> Dictionary:
 return {"speed":18.0,"altitude":4.0,"target_altitude":8.0,"flight_phase":"climb","next_gate_index":1,"next_gate_time":2.5,"next_gate_direction":1,"next_gate_altitude":2.0,"energy_remaining":5200.0,"battery_capacity":6000.0,"thrust_actual":25.0,"overdrive":false,"pilot_active":false,"distance":150.0,"total_distance":360.0,"elapsed":9.0,"integrity":1.0}
func hud_checks() -> void:
 var hud=HUD.new();root.add_child(hud)
 var route:Dictionary=Ground.route();var data:Dictionary={"mode":"flight","control_version":"pilot-v3","activeorder":route,"flight":telemetry(),"settings":{"reduced_motion":true}}
 hud.render(data);await settle()
 check(hud._ground_mode() and hud._extreme_mode() and hud._ascent_mode(),"ground content retains the exact v3 controls and resource layout")
 check(hud.flight_labels.status.text=="速度 18.0 m/s · 低空配送" and hud.flight_labels.altitude.text=="高度 4 / 8 m","ground status avoids ascent copy and retains actual altitude telemetry")
 check(hud.flight_labels.gate.text=="↓ 向下 · 2.5 s 后过门" and hud.flight_labels.gate_detail.text=="第 2 门 · 门高 2 m","ground HUD still reports the real next obstacle and direction")
 check(hud.flight_labels.energy.text=="电量 5.20 kJ / 6.00 kJ" and hud.flight_labels.thrust.text=="巡航 · 推力 25.0 N","ground display preserves paid v3 energy and thrust fields")
 var live:Dictionary=telemetry();live.flight_phase="approach";hud.update_flight(live)
 check(hud.flight_labels.status.text.ends_with("低空配送"),"an early solver approach phase does not hide the remaining ground gates")
 live.next_gate_index=-1;live.next_gate_time=-1;hud.update_flight(live)
 check(hud.flight_labels.status.text.ends_with("低空配送") and hud.flight_labels.gate.text.is_empty(),"210 m to go remains cruise even after the last reported gate")
 live.distance=310.0;hud.update_flight(live) # 50 m from the actual 360 m receiver.
 check(hud.flight_labels.status.text.ends_with("接近收件台") and hud.flight_labels.gate.text=="接近屋顶收件台" and hud.flight_labels.gate_detail.text=="收件限速 24 m/s","clear final approach names the actual roof receiver and speed limit")
 live.paused=true;hud.update_flight(live)
 check(hud.flight_labels.status.text=="已暂停" and hud.flight_labels.gate_detail.text=="已暂停 · 收件限速 24 m/s","paused ground approach retains the real receiving constraint")
 route.destination_name="西侧收件台";route.max_delivery_speed=19.0;data.activeorder=route;data.flight=live;hud.render(data);await settle()
 check(hud.flight_labels.gate.text=="接近西侧收件台" and hud.flight_labels.gate_detail.text=="已暂停 · 收件限速 19 m/s","saved custom goal and limit are never replaced by catalog defaults")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(data);await settle()
  var fits:bool=true
  for key in ["altitude","gate","gate_detail"]:
   var label:Label=hud.flight_labels[key];fits=fits and hud._ascent_cue.get_global_rect().encloses(label.get_global_rect()) and label.get_minimum_size().x<=label.size.x
  check(fits,"ground approach copy fits the existing cue at "+str(extent))
 data.activeorder=Extreme.route();data.flight=telemetry();hud.render(data);await settle()
 check(not hud._ground_mode() and hud.flight_labels.status.text.ends_with("爬升"),"saved ascent route retains exact existing phase copy")
 data.activeorder=route.duplicate(true);data.activeorder.erase("route_profile");hud.render(data);await settle()
 check(not hud._ground_mode() and hud.flight_labels.status.text.ends_with("爬升"),"unmarked route_kind/short distance/low altitude never reinterpret old HUD semantics")
 hud.queue_free();await settle()
func controller_checks() -> void:
 root.size=Vector2i(1280,720)
 var game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 check(game.economy.contracts.size()==2 and game.economy.contracts.all(func(c):return Ground.is_ground_route(c)),"real fresh controller bootstrap authors two new ground contracts with supplied data patch")
 game.economy.accept_contract("D1-A");game.economy.mark_story_seen("D1-A","D1-A/accept");game.start_flight(true)
 check(Ground.is_ground_route(game.sim.route) and game.sim.get_script()==Sim and game.hud._ground_mode(),"new default trial selects the existing v3 solver and ground presentation")
 var original:Dictionary=game.sim.route.duplicate(true)
 var hud_order:Dictionary=game.hud.state.activeorder.duplicate(true);hud_order.erase("accepted")
 var physical_fields_equal:bool=true
 for field in ["route_profile","distance","destination_y","delivery_radius","destination_name","max_delivery_speed","pilot_gates","control_version"]:physical_fields_equal=physical_fields_equal and hud_order[field]==original[field] and game.flight_order[field]==original[field]
 check(physical_fields_equal,"controller passes the persisted route marker, geometry, destination and limits straight through to HUD")
 var legacy:Dictionary=Ground.route();legacy.erase("route_profile");legacy.name="Saved ascent";legacy.background_route="city_to_orbit"
 var commands:Array=[{"tick":0,"axis_q":-1,"boost":false,"active":false}]
 for route in [legacy,Ground.route()]:
  game.economy.in_flight={"route":route.duplicate(true),"design":Extreme.starter_design(),"launcher":Extreme.starter_launcher(),"seed":3,"ticks":12,"elapsed":.2,"control_version":"pilot-v3","simulation_version":"pilot-v3","input_commands":commands.duplicate(true)}
  var encoded:String=JSON.stringify(game.economy.in_flight,"",true,true)
  game.economy.in_flight=JSON.parse_string(encoded)
  game._resume_dispatch()
  var control=sim_for(route)
  for i in 12:control.set_pilot_input(-1,false,false);control.step(1.0/60.0)
  check(not game.pilot_resume_blocked and game.paused and game.pilot_completed_ticks==12,"JSON resume restores all saved command ticks and pauses safely")
  check(game.sim.cargo_position()==control.cargo_position() and game.sim.total_energy()==control.total_energy(),"presentation selection leaves the exact saved v3 cargo replay position and energy unchanged")
  check(game.hud._ground_mode()==Ground.is_ground_route(route) and (str(game.world.flight_nodes.destination.get_meta("art_id"))=="flight/receiver")==Ground.is_ground_route(route),"actual resume selects kiosk/HUD only from the saved explicit marker")
  check(game.world.launch_transfer_progress==1 and game.world.launch_age==1.35,"resume never replays launch transfer or changes the old presentation offset")
 game.queue_free();await settle()
func run() -> void:
 await backdrop_checks()
 await world_checks()
 await hud_checks()
 await controller_checks()
 if passed+failed!=EXPECTED_CHECKS:check(false,"all expected ground presentation checks ran")
 print("GROUND_PRESENTATION passed=",passed," failed=",failed)
 quit(1 if failed else 0)
