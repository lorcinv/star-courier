extends SceneTree
## Actual HUD/canvas interrupted framing. Test fixtures do not alter native saves.
const Profile=preload("res://scripts/pilot_moon_profile.gd")
const Frame=preload("res://scripts/moon_framing_2d.gd")
var game
var passed:int=0
var failures:Array=[]
var rows:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failures.append(label);push_error(label)
func settle() -> void:
 for i in 4:await process_frame
func body_box() -> Rect2:
 var b:Rect2=Frame.craft_bounds(game.sim,game.world.flight_origin,72)
 var t:Transform2D=game.view.get_canvas_transform()
 var a:Vector2=game.view_container.pixel_to_screen(t*b.position)
 var z:Vector2=game.view_container.pixel_to_screen(t*b.end)
 return Rect2(a,z-a)
func hud_clear() -> bool:
 var b:Rect2=body_box()
 if not game.view_container.display_rect.grow(.1).encloses(b):return false
 for panel in game.hud.content.get_children():
  if panel is PanelContainer and panel.visible and panel.get_global_rect().intersects(b):return false
 return true
func place(point:Vector2) -> void:
 var b:Dictionary=game.sim.body_for_part(1)
 b.position+=point-game.sim.cargo_position();b.velocity=Vector2(18,-8)
func state() -> PackedByteArray:return var_to_bytes([game.sim.parts,game.sim.bodies,game.sim.route,game.sim.obstacles,game.sim.elapsed])
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false);await settle()
 for pose in [{"point":Vector2(180,-61),"phase":"ascent"},{"point":Vector2(515,-150),"phase":"return_to_lunar"},{"point":Vector2(650,-150),"phase":"lunar"}]:
  game._configure_flight(true,Profile.starter_design(),Profile.starter_launcher(),Profile.route(),true)
  place(pose.point);game.world.settle_resumed_flight(game.sim);game.paused=true;game.world._scene_paused=true
  var before:PackedByteArray=state()
  for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
   for density in ["auto","balanced","low"]:
    root.size=extent;game.settings.pixel_density=density;game._apply_quality();await settle();game.world._update_camera()
    var f:Dictionary=game.world.moon_presentation.debug_snapshot().frame
    check(f.phase==pose.phase,"phase derives from real cargo / trailing gate geometry")
    check(f.art_extent==game.view_container.display_rect.size and f.viewport_extent==game.world.get_viewport_rect().size,"paused resize refreshes actual mapper budgets")
    check(hud_clear(),"whole cargo-connected body clear after paused resize")
    var center:Vector2=game.world.smooth_center;var zoom:float=game.world.smooth_zoom
    for i in 12:game.world._process(.5)
    check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"pause freezes both framing and zoom recovery")
    game.world.set_focus_active(false);game.world._scene_paused=false;game.world._process(5)
    check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"focus loss freezes framing")
    game.world.set_focus_active(true);game.world._scene_paused=true
    for reduced in [true,false]:
     game.world.reduced_motion=reduced;game.world.motion_blur_enabled=not reduced;game.world._update_camera()
     check(game.world.moon_presentation.debug_snapshot().blur==0,"paused reduced or normal blur is zero")
    game.world.start_flight(game.sim,true);game.world.settle_resumed_flight(game.sim);game.world._scene_paused=true
    var restored:Dictionary=game.world.moon_presentation.debug_snapshot().frame
    check(restored.phase==pose.phase and hud_clear(),"restored phase and whole body derive from checkpoint")
    check(game.world.launch_age==1.35 and not game.world.flight_nodes.launch_burst.visible,"restore never repeats ignition")
    check(game.world.moon_presentation.get_child_count()==2 and game.world.moon_presentation._props.get_child_count()==2,"resize/restart retains fixed nodes")
    rows.append({"phase":pose.phase,"extent":[extent.x,extent.y],"density":density,"target_zoom":restored.zoom,"craft_height_px":body_box().size.y})
  check(state()==before,"all presentation interruptions preserve fixture physics bytes")
 # Zoom recovery is continuous and monotone along the clear post-ascent span.
 game._configure_flight(true,Profile.starter_design(),Profile.starter_launcher(),Profile.route(),true)
 place(Vector2(200,-55));game.world.settle_resumed_flight(game.sim)
 var previous:float=0.0;var maximum_step:float=0.0
 for step in 1001:
  place(Vector2(480.0+float(step)*.1,-150));game.sim.elapsed+=1.0/60.0
  var frame:Dictionary=game.world.moon_presentation.camera_target(game.sim,game.world.get_viewport_rect().size,game.world.screen_mapper)
  if step>0:
   check(frame.zoom>=previous-.000001,"post-gate zoom recovery does not hunt")
   maximum_step=maxf(maximum_step,absf(frame.zoom-previous))
  previous=frame.zoom
 check(previous>=.24 and previous<=.30,"readable lunar zoom restored before cruise")
 check(maximum_step<.001,"distance-based recovery has no gate-change zoom jump")
 var output:String=OS.get_environment("MOON_ASCENT_LIFECYCLE_OUTPUT")
 if not output.is_empty():
  var out=FileAccess.open(output,FileAccess.WRITE);out.store_string(JSON.stringify({"passed":passed,"failures":failures,"rows":rows,"maximum_recovery_zoom_step_per_0_1m":maximum_step},"  "));out.close()
 game.queue_free();game=null;await settle()
 print("Readable Moon ascent lifecycle: %d passed, %d failed"%[passed,failures.size()]);quit(1 if not failures.is_empty() else 0)
