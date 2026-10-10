extends SceneTree
## Real Godot Control/camera transforms, synthetic composition states. This does
## not substitute for native real-time piloting or human fairness evaluation.
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var game
var passed:int=0
var failed:int=0
var worst_clearance:float=INF
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error(label)
func settle() -> void:
 await process_frame;await process_frame;await process_frame
func projected_craft() -> Rect2:
 var low:Vector2=Vector2(INF,INF);var high:Vector2=Vector2(-INF,-INF)
 var body:Dictionary=game.sim.body_for_part(1)
 for p in body.parts:
  var sprite:Sprite2D=game.world.flight_nodes["p"+str(p.id)]
  var box:Rect2=sprite.get_rect()
  for q in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
   var pixel:Vector2=game.view.get_canvas_transform()*(sprite.global_transform*q)
   var screen:Vector2=game.view_container.pixel_to_screen(pixel)
   low=low.min(screen);high=high.max(screen)
 return Rect2(low,high-low)
func run() -> void:
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 var tall:Array=[Profile.part(1,"cargo",0)]
 for y in range(-6,3):
  if y!=0:tall.append(Profile.part(20+y+6,"beam",0,y))
 for x in [-1,1]:
  for y in [-2,0,2]:tall.append(Profile.part(40+tall.size(),"beam",x,y))
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  for density in ["auto","balanced","low"]:
   game.settings.pixel_density=density;game._apply_quality();await settle()
   for design in [Profile.starter_design(),Profile.reinforced_design(),tall]:
    game._configure_flight(true,design,Profile.starter_launcher(),Profile.route())
    game._process(game.launch_transfer_remaining+.4);await settle()
    var on_pad:Rect2=projected_craft()
    check(game.view_container.display_rect.encloses(on_pad),"the entire grounded craft fits the art frame at charge")
    check(not game.hud._launch_layer.get_global_rect().intersects(on_pad),"the actual launch ribbon does not cover the grounded craft")
    game._configure_flight(true,design,Profile.starter_launcher(),Profile.route(),true)
    game.paused=true;await settle()
    for angle in [-.7,0.0,.7]:
     for lane_offset in [-1000.0,0.0,1000.0]:
      var body:Dictionary=game.sim.body_for_part(1);body.angle=angle
      body.position+=Vector2(100,lane_offset)-game.sim.cargo_position()
      game.sim.telemetry.lane_y=0.0;game.sim.telemetry.route_heading=angle;game.sim.telemetry.forward_speed=13.0
      game.world._ascent_view_zoom=.35;game.world.settle_resumed_flight(game.sim)
      var craft:Rect2=projected_craft()
      var label:String="%s %s %d modules angle%.1f offset%.0f"%[str(extent),density,design.size(),angle,lane_offset]
      check(game.view_container.display_rect.encloses(craft),"connected craft stays entirely on the native art canvas: "+label)
      var clear:bool=true
      for panel in game.hud.content.get_children():
       if panel is PanelContainer and panel.visible:
        clear=clear and not panel.get_global_rect().intersects(craft)
        if panel.name=="FlightResources":worst_clearance=minf(worst_clearance,craft.position.y-panel.get_global_rect().end.y)
      check(clear,"actual native HUD panels do not cover the connected craft: "+label)
      check(game.world._ascent_view_zoom<=.35,"craft-fit pullback never reduces the established hazard visibility: "+label)
 game.queue_free();await settle()
 print("FLIGHT_VISIBILITY passed=",passed," failed=",failed," worst_top_resource_clearance_native_px=",worst_clearance)
 quit(1 if failed else 0)
