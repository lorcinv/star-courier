extends SceneTree
## Headless actual-scene coordinates + exact native-input replay. No human,
## fresh native-input, GPU image, FPS, or full-circle acceptance claims.
const Frame=preload("res://scripts/moon_framing_2d.gd")
const Profile=preload("res://scripts/pilot_moon_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
const Baseline=preload("res://tests/fixtures/moon_presentation_pre_framing.gd")
var game
var passed:int=0
var failures:Array=[]
var report:Dictionary={"method":"Headless scene/HUD coordinate tests and exact prior native-input replay, not new native footage","matrix":[],"replay":[]}
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1
 else:failures.append(label);push_error(label)
func settle() -> void:
 for i in 3:await process_frame
func json_value(value:Variant) -> Variant:
 if value is Vector2 or value is Vector2i:return [value.x,value.y]
 if value is Rect2:return [value.position.x,value.position.y,value.size.x,value.size.y]
 if value is Dictionary:
  var out:Dictionary={}
  for key in value:out[str(key)]=json_value(value[key])
  return out
 if value is Array:
  var out:Array=[]
  for x in value:out.append(json_value(x))
  return out
 if value is float and not is_finite(value):return null
 return value
func physical_state(sim) -> PackedByteArray:
 return var_to_bytes([sim.route,sim.parts,sim.bodies,sim.obstacles,sim.telemetry,sim.elapsed,sim.status,sim.events])
func screen_box(box:Rect2) -> Rect2:
 var t:Transform2D=game.view.get_canvas_transform()
 var a:Vector2=game.view_container.pixel_to_screen(t*box.position)
 var b:Vector2=game.view_container.pixel_to_screen(t*box.end)
 return Rect2(a,b-a)
func clear_of_hud(box:Rect2) -> bool:
 if not game.view_container.display_rect.grow(.1).encloses(box):return false
 for panel in game.hud.content.get_children():
  if panel is PanelContainer and panel.visible and panel.get_global_rect().intersects(box):return false
 return true
func set_cargo(point:Vector2,angle:float=0.0) -> void:
 var body:Dictionary=game.sim.body_for_part(1);body.angle=angle
 body.position+=point-game.sim.cargo_position()
func verify_pose(label:String) -> void:
 var before:PackedByteArray=physical_state(game.sim)
 game.world.settle_resumed_flight(game.sim)
 var frame:Dictionary=game.world.moon_presentation.debug_snapshot().frame
 var box:Rect2=screen_box(Frame.craft_bounds(game.sim,game.world.flight_origin,72))
 check(clear_of_hud(box),"entire actual craft clears native panels: "+label)
 check(frame.zoom<=.30+.0001 and frame.zoom>0 and frame.center.is_finite(),"bounded finite camera: "+label)
 var visibility:Dictionary=game.world.moon_presentation.debug_snapshot().framing_visibility
 check(visibility.cues.size()<=6,"bounded cue count: "+label)
 for cue in visibility.cues:
  check(frame.safe.has_point(cue.screen),"cue inside unobscured frame: "+label)
  if cue.kind=="hazard":
   var h:Dictionary=game.sim.obstacles[int(cue.index)]
   check(absf(cue.point_m.distance_to(h.position)-float(h.radius))<.001,"cue points to actual physical circumference: "+label)
 check(physical_state(game.sim)==before,"presentation leaves all simulation/route bytes unchanged: "+label)
 check(game.world.moon_presentation.get_child_count()==2 and game.world.moon_presentation._props.get_child_count()==2,"fixed nodes/planes under repeated compose: "+label)
 report.matrix.append({"case":label,"craft_native":box,"zoom":frame.zoom,"cues":visibility.cues.size()})
func matrix() -> void:
 var tall:Array=[Extreme.part(1,"cargo",0)]
 for y in range(-6,3):
  if y!=0:tall.append(Extreme.part(20+y+6,"beam",0,y))
 var dense:Array=[]
 for x in range(-8,9):
  for y in range(-4,5):dense.append(Extreme.part(1 if x==0 and y==0 else 100+dense.size(),"cargo" if x==0 and y==0 else "beam",x,y))
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  for density in ["auto","balanced","low"]:
   game.settings.pixel_density=density;game._apply_quality();await settle()
   for design in [Extreme.starter_design(),Extreme.reinforced_design(),tall,dense]:
    game._configure_flight(true,design,Extreme.starter_launcher(),Profile.route(),true)
    game.paused=true;await settle();game.hud.content.get_node("FlightEventReceipt").show()
    for angle in [-.7,0.0,.7]:
     for point in [Vector2(105,-23),Vector2(650,-150),Vector2(845,-128),Vector2(898,-126)]:
      set_cargo(point,angle)
      verify_pose("%s %s %d parts %.1f %s"%[str(extent),density,design.size(),angle,str(point)])
    if design.size()==8:
     var center:Vector2=game.world.smooth_center
     var zoom:float=game.world.smooth_zoom
     game.world._scene_paused=true;game.world._process(10)
     check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"pause freezes camera")
     game.world._scene_paused=false;game.world.set_focus_active(false);game.world._process(10)
     check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"focus loss freezes camera")
     game.world.set_focus_active(true)
     for reduced in [false,true]:
      game.world.reduced_motion=reduced;game.world.motion_blur_enabled=false
      game.world._update_camera()
      check(game.world.moon_presentation.debug_snapshot().blur==0,"blur-off or reduced leaves player/cues crisp")
 # Far detached body must not alter player bounds or camera target.
 game._configure_flight(true,Extreme.starter_design(),Extreme.starter_launcher(),Profile.route(),true)
 var original:Rect2=Frame.craft_bounds(game.sim,Vector2.ZERO,72)
 game.sim.bodies.append({"parts":[],"position":Vector2(1e6,1e6),"angle":1.0,"velocity":Vector2.ZERO})
 check(Frame.craft_bounds(game.sim,Vector2.ZERO,72)==original,"detached remote body excluded from player framing")
 # Real saved route boundary warning, not the decorative regolith silhouette.
 set_cargo(Vector2(700,-225));game.world.settle_resumed_flight(game.sim)
 var cues:Array=game.world.moon_presentation.debug_snapshot().framing_visibility.cues
 check(cues.any(func(c):return c.kind=="boundary" and c.id=="upper-boundary"),"actual upper failure boundary receives distinct warning")
func replay(extent:Vector2i,snapshot:Dictionary) -> void:
 root.size=extent;game.settings.pixel_density="auto";game._apply_quality();await settle()
 game._configure_flight(true,snapshot.design,snapshot.launcher,snapshot.route,true)
 game.sim.configure(snapshot.design,snapshot.launcher,snapshot.route,int(snapshot.seed))
 game.paused=true;game.world._scene_paused=false;game.world.set_process(false)
 game.world.launch_age=2;game.world.launch_transfer_progress=1
 game.world.settle_resumed_flight(game.sim)
 var line=Timeline.new();check(line.restore(snapshot.input_commands,int(snapshot.ticks)),"exact native timeline accepted")
 var baseline=Baseline.new();game.view.add_child(baseline)
 var baseline_props=Node2D.new();game.view.add_child(baseline_props)
 baseline.configure_route(snapshot.route,baseline_props,game.world.flight_origin,72,game.sim.obstacles)
 var baseline_center:Vector2=game.world.smooth_center;var baseline_zoom:float=.30
 var min_pixels:float=INF;var max_pixels:float=0;var baseline_min:float=INF;var baseline_max:float=0
 var phase_min:Dictionary={};var phase_max:Dictionary={}
 var maximum_jump:float=0;var last_screen:Vector2=Vector2.ZERO;var maximum_cues:int=0
 var craft_clear:bool=true;var states_same:bool=true;var all_finite:bool=true
 var seen:Dictionary={};var rows:Array=[]
 for tick in int(snapshot.ticks):
  var command:Dictionary=line.state_at(tick)
  game.sim.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active));game.sim.step(1.0/60.0)
  var before:PackedByteArray=physical_state(game.sim) if tick%30==0 else PackedByteArray()
  game.world.show_flight(game.sim);game.world._process(1.0/60.0)
  if tick%30==0:states_same=states_same and physical_state(game.sim)==before
  var craft:Rect2=Frame.craft_bounds(game.sim,game.world.flight_origin,72)
  var box:Rect2=screen_box(craft)
  var snap:Dictionary=game.world.moon_presentation.debug_snapshot()
  var visibility:Dictionary=snap.framing_visibility
  maximum_cues=maxi(maximum_cues,visibility.cues.size())
  var velocity:Vector2=snap.frame.velocity
  var old:Dictionary=baseline.camera_target(game.sim.cargo_position(),velocity,game.sim.obstacles,game.sim.status)
  baseline_center=baseline_center.lerp(old.center,1-exp(-8.0/60.0));baseline_zoom=lerpf(baseline_zoom,old.zoom,1-exp(-8.0/60.0))
  if tick>120 and game.sim.status=="running":
   min_pixels=minf(min_pixels,box.size.y);max_pixels=maxf(max_pixels,box.size.y)
   var phase:String=snap.frame.phase
   phase_min[phase]=minf(float(phase_min.get(phase,INF)),box.size.y);phase_max[phase]=maxf(float(phase_max.get(phase,0)),box.size.y)
   var previous_px:float=craft.size.y*baseline_zoom*game.view_container.display_rect.size.x/1280.0
   baseline_min=minf(baseline_min,previous_px);baseline_max=maxf(baseline_max,previous_px)
   craft_clear=craft_clear and clear_of_hud(box)
   all_finite=all_finite and game.world.smooth_center.is_finite() and is_finite(game.world.smooth_zoom)
   if last_screen!=Vector2.ZERO:maximum_jump=maxf(maximum_jump,box.get_center().distance_to(last_screen))
   last_screen=box.get_center()
  # Required gates are audited over the whole flight, independent of the
  # 3.5 s cue eligibility window. Far cues from this read-only audit are ignored.
  var all_gate_frame:Dictionary=snap.frame.duplicate();all_gate_frame.forward_m=1.0e9
  var all_geometry:Dictionary=Frame.visibility(game.sim,game.world.flight_origin,72,all_gate_frame,game.world.smooth_center,game.world.smooth_zoom)
  var hazards:Array=visibility.hazards.filter(func(h):return not str(h.id).begins_with("gate-"))
  hazards.append_array(all_geometry.hazards.filter(func(h):return str(h.id).begins_with("gate-")))
  for h in hazards:
   var id:String=h.id
   if not seen.has(id):seen[id]={"first_relevant":game.sim.elapsed,"first_any_arc_visible":-1.0,"first_quarter_arc_visible":-1.0,"first_nearest_visible":-1.0,"first_edge_cue":-1.0,"cross_center":-1.0,"cross_front":-1.0,"nearest_since":-1.0,"arc_since":-1.0,"quarter_since":-1.0,"warning_since":-1.0,"inward_since":-1.0,"front_inward_arc_continuous_seconds":0.0,"front_nearest_continuous_seconds":0.0,"front_arc_continuous_seconds":0.0,"front_quarter_arc_continuous_seconds":0.0,"front_warning_continuous_seconds":0.0,"full_circle_sample_count":0,"visible_nearest_sample_count":0}
   if int(h.visible_arc_samples)>0 and seen[id].first_any_arc_visible<0:seen[id].first_any_arc_visible=game.sim.elapsed
   if int(h.visible_arc_samples)>=8 and seen[id].first_quarter_arc_visible<0:seen[id].first_quarter_arc_visible=game.sim.elapsed
   if h.nearest_visible:
    if seen[id].first_nearest_visible<0:seen[id].first_nearest_visible=game.sim.elapsed
    seen[id].visible_nearest_sample_count+=1
   if h.complete_circle_visible:seen[id].full_circle_sample_count+=1
   if visibility.cues.any(func(c):return c.id==id) and seen[id].first_edge_cue<0:seen[id].first_edge_cue=game.sim.elapsed
   if game.sim.cargo_position().x>=game.sim.obstacles[int(h.index)].position.x and seen[id].cross_center<0:seen[id].cross_center=game.sim.elapsed
   var has_cue:bool=visibility.cues.any(func(c):return c.id==id)
   for pair in [["nearest_since",bool(h.nearest_visible)],["arc_since",int(h.visible_arc_samples)>0],["quarter_since",int(h.visible_arc_samples)>=8],["warning_since",bool(h.nearest_visible) or has_cue],["inward_since",int(h.inward_arc_visible_samples)==9]]:
    if bool(pair[1]):
     if float(seen[id][pair[0]])<0:seen[id][pair[0]]=game.sim.elapsed
    else:seen[id][pair[0]]=-1.0
   var physical:Dictionary=game.sim.obstacles[int(h.index)]
   if craft.end.x>=game.world.flight_origin.x+(float(physical.position.x)-float(physical.radius))*72 and seen[id].cross_front<0:
    seen[id].cross_front=game.sim.elapsed
    for pair in [["nearest_since","front_nearest_continuous_seconds"],["arc_since","front_arc_continuous_seconds"],["quarter_since","front_quarter_arc_continuous_seconds"],["warning_since","front_warning_continuous_seconds"],["inward_since","front_inward_arc_continuous_seconds"]]:
     seen[id][pair[1]]=game.sim.elapsed-float(seen[id][pair[0]]) if float(seen[id][pair[0]])>=0 else 0.0
  if tick%12==0 or game.sim.status!="running":rows.append({"tick":tick+1,"position":game.sim.cargo_position(),"zoom":game.world.smooth_zoom,"phase":snap.frame.phase,"target_zoom":snap.frame.zoom,"craft_native":box,"baseline_zoom":baseline_zoom,"cue_count":visibility.cues.size(),"visible_nearest":visibility.hazards.filter(func(h):return h.nearest_visible).map(func(h):return h.id),"cues":visibility.cues.map(func(h):return h.id)})
 check(craft_clear,"all exact replay craft AABBs clear current native HUD at "+str(extent))
 check(states_same,"all sampled replay render calls leave physics bytes unchanged")
 check(all_finite and maximum_cues<=6,"entire replay finite with <=6 cues")
 check(game.sim.status=="success" and game.sim.ship_integrity()==1.0,"same actual recorded inputs still deliver intact")
 check(absf(game.sim.elapsed-float(snapshot.elapsed))<.0001,"recorded flight terminal time unchanged")
 for id in seen:
  if str(id).begins_with("gate-"):
   check(float(seen[id].front_inward_arc_continuous_seconds)>=2.5,"required gate has >=2.5 s continuous inward-facing quarter arc before first horizontal overlap: "+id+" "+str(extent))
 report.replay.append({"extent":extent,"input_ticks":snapshot.ticks,"status":game.sim.status,"elapsed":game.sim.elapsed,"remaining_energy":game.sim.total_energy(),"phase_minimum_height_px":phase_min,"phase_maximum_height_px":phase_max,"minimum_craft_height_px":min_pixels,"maximum_craft_height_px":max_pixels,"baseline_minimum_height_px":baseline_min,"baseline_maximum_height_px":baseline_max,"max_craft_center_step_px_at_60hz":maximum_jump,"max_cues":maximum_cues,"required_gate_geometry_window":"whole flight, independent of cue horizon", "hazard_coverage":seen,"rows":rows})
 baseline.leave_flight();baseline.queue_free();baseline_props.queue_free();await settle()
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 await settle()
 if OS.get_environment("MOON_FRAME_REPLAY_ONLY")!="1":await matrix()
 var input_path:String=OS.get_environment("MOON_RECORDED_REPLAY")
 if input_path.is_empty():input_path="res://tests/fixtures/moon_native_input_v1.json"
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input_path))
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:await replay(extent,source.snapshot)
 report.passed=passed;report.failures=failures
 var output_path:String=OS.get_environment("MOON_FRAME_OUTPUT")
 if output_path.is_empty():output_path="user://moon-framing-report.json"
 var out=FileAccess.open(output_path,FileAccess.WRITE);out.store_string(JSON.stringify(json_value(report),"  "));out.close()
 game.queue_free();game=null;await settle()
 print("Readable Moon framing: %d passed, %d failed"%[passed,failures.size()])
 quit(1 if not failures.is_empty() else 0)
