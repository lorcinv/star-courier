extends SceneTree
## Actual world -> camera -> PixelStage projection; no altered camera target.
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for unused in 3:await process_frame
func run() -> void:
 var game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  game._configure_flight(true,Profile.starter_design(),Profile.starter_launcher(),Profile.route(),true)
  game.paused=true;await settle()
  for displacement in [Vector2(100,-80),Vector2(620,-240),Vector2(800,70)]:
   var body:Dictionary=game.sim.body_for_part(1);body.position+=displacement-game.sim.cargo_position()
   game.world.show_flight(game.sim,true);await settle()
   var route_before:PackedByteArray=var_to_bytes(game.sim.route)
   var center:Vector2=game.world.target_center;var zoom:float=game.world.target_zoom
   var snapshot:Dictionary=game.world.delivery_navigation_snapshot(game.sim)
   var receiver:Vector2=Vector2(float(game.sim.route.distance),float(game.sim.route.destination_y))
   var point:Vector2=game.world.flight_root.to_global(game.world.flight_origin+receiver*game.world.CELL)
   var pixel:Vector2=game.view.get_canvas_transform()*point
   var expected:Vector2=game.view_container.pixel_to_screen(pixel)
   check(snapshot.receiver_screen.distance_to(expected)<.001,"receiver uses actual camera and stage projection "+str(extent))
   check(absf(snapshot.distance_m-game.sim.cargo_position().distance_to(receiver))<.00001,"distance is actual Euclidean metres, not route progress")
   check(game.world.target_center==center and game.world.target_zoom==zoom and var_to_bytes(game.sim.route)==route_before,"navigation read never changes camera or saved route")
 game.queue_free();await settle();print("DELIVERY_NAVIGATION_PROJECTION passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
