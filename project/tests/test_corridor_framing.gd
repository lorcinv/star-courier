extends SceneTree
## Real scene/HUD coordinates and exact immutable native timeline; no human
## fairness, fresh native input, or GPU-rendering claim from this headless test.
const Frame=preload("res://scripts/corridor_framing_2d.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
var game
var passed:int=0
var failures:Array=[]
var report:Dictionary={"method":"Exact original native input through unchanged physical solver; actual scene and native HUD coordinates", "replays":[],"poses":[]}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failures.append(label);push_error(label)
func settle() -> void:
 for i in 3:await process_frame
func encode(value:Variant) -> Variant:
 if value is Vector2 or value is Vector2i:return [value.x,value.y]
 if value is Rect2:return [value.position.x,value.position.y,value.size.x,value.size.y]
 if value is Dictionary:
  var out:Dictionary={}
  for key in value:out[str(key)]=encode(value[key])
  return out
 if value is Array:
  var out:Array=[]
  for item in value:out.append(encode(item))
  return out
 if value is float and not is_finite(value):return null
 return value
func physical() -> PackedByteArray:
 return var_to_bytes([game.sim.route,game.sim.parts,game.sim.bodies,game.sim.obstacles,game.sim.telemetry,game.sim.elapsed,game.sim.status,game.sim.events])
func screen_box(box:Rect2) -> Rect2:
 var t:Transform2D=game.view.get_canvas_transform()
 var a:Vector2=game.view_container.pixel_to_screen(t*box.position)
 var b:Vector2=game.view_container.pixel_to_screen(t*box.end)
 return Rect2(a,b-a)
func hud_clear(box:Rect2) -> bool:
 if not game.view_container.display_rect.grow(.1).encloses(box):return false
 for panel in game.hud.content.get_children():
  if panel is PanelContainer and panel.visible and panel.get_global_rect().intersects(box):return false
 return true
func actual_occluders() -> Array:
 var result:Array=[]
 var art:Rect2=game.view_container.display_rect
 var ratio:float=1280.0/art.size.x
 for panel in game.hud.content.get_children():
  if panel is PanelContainer and panel.visible:
   var rect:Rect2=panel.get_global_rect().grow(4.0*game.hud._ui_scale)
   result.append(Rect2((rect.position-art.position)*ratio,rect.size*ratio))
 return result
func snapshot() -> Dictionary:
 var source_path:String=OS.get_environment("CORRIDOR_INPUT")
 if source_path.is_empty():source_path="res://tests/fixtures/corridor_native_trial_v1.json"
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path))
 return source.get("snapshot",source.get("flight_snapshot",{}))
func pose_probe(s:Dictionary) -> void:
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  game._configure_flight(true,s.design,s.launcher,s.route,true);game.paused=true
  var b:Dictionary=game.sim.body_for_part(1);b.position+=Vector2(57.6736,-8.4372)-game.sim.cargo_position();b.velocity=Vector2(13,-5)
  game.world.settle_resumed_flight(game.sim);await settle()
  var f:Dictionary=game.world._corridor_frame
  var box:Rect2=screen_box(Frame.Shared.craft_bounds(game.sim,game.world.flight_origin,72))
  check(hud_clear(box),"actual native HUD clear at exact baseline first-gate pose "+str(extent))
  var data:Dictionary=Frame.measure(game.sim,game.world.flight_origin,72,f,game.world.camera.position,game.world.smooth_zoom,actual_occluders())
  for face in data.faces:
   if face.gate==0:check(face.inward_visible==9,"first generated physical inward face visible "+face.side+str(extent))
  var panels:Array=[]
  for panel in game.hud.content.get_children():
   if panel is PanelContainer:panels.append({"name":panel.name,"rect":panel.get_global_rect(),"visible":panel.visible})
  report.poses.append({"extent":extent,"art":game.view_container.display_rect,"craft_native":box,"zoom":game.world.smooth_zoom,"panels":panels,"audit":data})
func replay(extent:Vector2i,s:Dictionary) -> void:
 root.size=extent;game.settings.pixel_density="auto";game._apply_quality();await settle()
 game._configure_flight(true,s.design,s.launcher,s.route,true)
 game.sim.configure(s.design,s.launcher,s.route,int(s.seed))
 game.paused=true;game.world._scene_paused=false;game.world.set_process(false)
 game.world.launch_age=2;game.world.launch_transfer_progress=1;game.world.settle_resumed_flight(game.sim)
 var line=Timeline.new();check(line.restore(s.input_commands,int(s.ticks)),"exact native timeline restored")
 var seen:Dictionary={};var rows:Array=[];var min_height:float=INF;var min_width:float=INF;var clear:bool=true;var state_same:bool=true;var min_zoom:float=INF;var max_delta:float=0;var old_pos:Vector2=Vector2.ZERO;var rejected:int=0
 for tick in int(s.ticks):
  var command:Dictionary=line.state_at(tick)
  game.sim.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active));game.sim.step(1.0/60.0)
  var before:PackedByteArray=physical() if tick%60==0 else PackedByteArray()
  game.world.show_flight(game.sim);game.world._process(1.0/60.0)
  if tick%60==0:state_same=state_same and before==physical()
  var f:Dictionary=game.world._corridor_frame
  var body:Rect2=screen_box(f.craft)
  var audit:Dictionary=Frame.measure(game.sim,game.world.flight_origin,72,f,game.world.camera.position,game.world.smooth_zoom,actual_occluders())
  if tick>120 and game.sim.status=="running":
   min_height=minf(min_height,body.size.y);min_width=minf(min_width,body.size.x);min_zoom=minf(min_zoom,game.world.smooth_zoom)
   clear=clear and hud_clear(body)
   if not f.bounded_geometry_fit:rejected+=1
   if old_pos!=Vector2.ZERO:max_delta=maxf(max_delta,body.get_center().distance_to(old_pos))
   old_pos=body.get_center()
  for face in audit.faces:
   var id:String=str(face.gate)+"-"+str(face.side)
   if not seen.has(id):seen[id]={"arc_since":-1.0,"nearest_since":-1.0,"overlap_time":-1.0,"minimum_samples_before_overlap":9}
   var record:Dictionary=seen[id]
   if record.overlap_time<0:
    if face.inward_visible==9:
     if record.arc_since<0:record.arc_since=game.sim.elapsed
    else:record.arc_since=-1.0
    if face.nearest_visible:
     if record.nearest_since<0:record.nearest_since=game.sim.elapsed
    else:record.nearest_since=-1.0
    if face.first_horizontal_overlap:
     record.overlap_time=game.sim.elapsed
     record.arc_preview=game.sim.elapsed-float(record.arc_since) if record.arc_since>=0 else 0.0
     record.nearest_preview=game.sim.elapsed-float(record.nearest_since) if record.nearest_since>=0 else 0.0
     record.position=game.sim.cargo_position();record.body_native=body;record.zoom=game.world.smooth_zoom
  if tick%12==0 or game.sim.status!="running":rows.append({"tick":tick+1,"position":game.sim.cargo_position(),"zoom":game.world.smooth_zoom,"target_zoom":f.zoom,"required_zoom":f.required_zoom,"center":game.world.camera.position,"target_center":f.center,"safe":f.safe,"audit":audit if absf(game.sim.cargo_position().x-174.0)<2 else {},"craft_native":body,"faces":audit.faces.map(func(a):return {"gate":a.gate,"side":a.side,"samples":a.inward_visible,"nearest":a.nearest_visible,"horizontal_seconds":a.horizontal_seconds,"euclidean_seconds":a.euclidean_seconds})})
 check(clear,"entire real connected craft clears actual HUD for full native replay "+str(extent))
 check(state_same,"presentation does not mutate any sampled physical bytes "+str(extent))
 check(game.sim.status=="success" and game.sim.ship_integrity()==1.0,"same immutable native input delivers intact "+str(extent))
 check(absf(game.sim.elapsed-float(s.elapsed))<.0001,"exact terminal time unchanged "+str(extent))
 for id in seen:
  check(float(seen[id].get("arc_preview",0))>=2.5-.000001,"all nine actual inward samples continuously visible >=2.5 s before first conservative horizontal overlap: "+id+str(extent))
 report.replays.append({"extent":extent,"minimum_craft_height_px":min_height,"minimum_craft_width_px":min_width,"minimum_zoom":min_zoom,"maximum_craft_center_step_px":max_delta,"bounded_fit_rejected_ticks":rejected,"gates":seen,"rows":rows})
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false);await settle()
 var s:Dictionary=snapshot();await pose_probe(s)
 if OS.get_environment("CORRIDOR_POSES_ONLY")!="1":
  for extent in ([Vector2i(1280,800)] if OS.get_environment("CORRIDOR_ONE_SIZE")=="1" else [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]):await replay(extent,s)
 report.passed=passed;report.failures=failures
 var output_path:String=OS.get_environment("CORRIDOR_OUTPUT")
 if output_path.is_empty():output_path="user://corridor-framing-report.json"
 var out=FileAccess.open(output_path,FileAccess.WRITE);out.store_string(JSON.stringify(encode(report),"  "));out.close()
 game.queue_free();game=null;await settle()
 print("Corridor framing: %d passed, %d failed"%[passed,failures.size()]);quit(1 if not failures.is_empty() else 0)
