extends SceneTree
## Focused interruption and actual native-HUD resize tests, no GPU claim.
const Profile=preload("res://scripts/pilot_moon_profile.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Frame=preload("res://scripts/moon_framing_2d.gd")
var game
var passed=0
var failures:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failures.append(label);push_error(label)
func settle() -> void:
 for i in 4:await process_frame
func box() -> Rect2:
 var b:Rect2=Frame.craft_bounds(game.sim,game.world.flight_origin,72)
 var t:Transform2D=game.view.get_canvas_transform()
 var a:Vector2=game.view_container.pixel_to_screen(t*b.position)
 var z:Vector2=game.view_container.pixel_to_screen(t*b.end)
 return Rect2(a,z-a)
func hud_clear() -> bool:
 var b:Rect2=box()
 if not game.view_container.display_rect.grow(.1).encloses(b):return false
 for panel in game.hud.content.get_children():
  if panel is PanelContainer and panel.visible and panel.get_global_rect().intersects(b):return false
 return true
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false);await settle()
 game._configure_flight(true,Profile.starter_design(),Profile.starter_launcher(),Profile.route(),true)
 var body:Dictionary=game.sim.body_for_part(1);body.position+=Vector2(740,-145)-game.sim.cargo_position();body.velocity=Vector2(18,2)
 game.world.settle_resumed_flight(game.sim);game.paused=true;game.world._scene_paused=true
 var sim_before:PackedByteArray=var_to_bytes([game.sim.parts,game.sim.bodies,game.sim.route,game.sim.obstacles,game.sim.elapsed])
 for extent in [Vector2i(1920,1080),Vector2i(1280,800),Vector2i(3840,2160),Vector2i(1920,1080)]:
  for density in ["auto","low","balanced"]:
   root.size=extent;game.settings.pixel_density=density;game._apply_quality();await settle()
   # No fresh show_flight: pause/resize must refresh actual mapper budgets.
   game.world._update_camera()
   var frame:Dictionary=game.world.moon_presentation.debug_snapshot().frame
   check(frame.art_extent==game.view_container.display_rect.size,"paused resize observes native art frame: "+str(extent)+density)
   check(frame.viewport_extent==game.world.get_viewport_rect().size,"paused resize observes integer canvas")
   check(hud_clear(),"paused resized body remains clear of actual HUD")
   var center:Vector2=game.world.smooth_center;var zoom:float=game.world.smooth_zoom
   for i in 30:game.world._process(1.0/30.0)
   check(game.world.smooth_center==center and game.world.smooth_zoom==zoom,"pause prevents camera drift on unchanged window")
   for reduced in [true,false]:
    game.world.reduced_motion=reduced;game.world.motion_blur_enabled=not reduced;game.world._update_camera()
    check(game.world.moon_presentation.debug_snapshot().blur==0,"paused reduced/normal blur stays zero")
 check(var_to_bytes([game.sim.parts,game.sim.bodies,game.sim.route,game.sim.obstacles,game.sim.elapsed])==sim_before,"resize/pause/quality never edit authoritative flight")
 var view=game.world.moon_presentation
 var before_nodes:int=view.get_child_count()
 for i in 12:
  game.world.start_flight(game.sim,true);game.world.settle_resumed_flight(game.sim)
  check(game.world.launch_age==1.35 and not game.world.flight_nodes.launch_burst.visible,"repeated restore has no ignition")
  check(view._props.get_child_count()==2 and view.get_child_count()==before_nodes,"restore keeps fixed independent props/planes")
 # Actual saved failure boundary: on-screen dashed line and off-screen arrow
 # are both bounded; a transparent decorative surface never substitutes.
 body.position+=Vector2(700,-225)-game.sim.cargo_position();game.world.settle_resumed_flight(game.sim)
 check(view._cue.frame_cues.any(func(c):return c.kind=="boundary"),"failure limit has a boundary cue even when actual limit is on screen")
 var frame:Dictionary=view.debug_snapshot().frame
 body.velocity=Vector2(60,0)
 var fast:Dictionary=view.camera_target(game.sim,game.world.get_viewport_rect().size,game.world.screen_mapper)
 check(fast.forward_m==210.0,"high-speed warning horizon uses actual 3.5 seconds")
 check(fast.zoom>=.24-.0001 and fast.zoom<=.30+.0001,"high speed cannot shrink standard player beyond bounded zoom reserve")
 game.sim.status="failed";game.world.show_flight(game.sim,true)
 check(game.world.smooth_center.is_finite() and game.world.smooth_zoom>0,"failure framing finite")
 game.world.leave_flight();check(not view.route_enabled() and view._sim==null and view._last_frame.is_empty(),"leave clears retained route, sim and frame")
 game._configure_flight(true,Ground.starter_design(),Ground.starter_launcher(),Ground.route(),true)
 check(not game.world.moon_presentation.route_enabled(),"ground route does not inherit Moon framing or cues")
 game.queue_free();game=null;await settle()
 print("Readable Moon lifecycle: %d passed, %d failed"%[passed,failures.size()]);quit(1 if not failures.is_empty() else 0)
