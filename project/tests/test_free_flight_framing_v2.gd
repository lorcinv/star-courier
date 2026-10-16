extends SceneTree
## Source fixture for a future authorized engine run. No scene/window launcher.
const Frame=preload("res://scripts/free_flight_framing_2d.gd")
const FreeSim=preload("res://scripts/pilot_free_simulation_v1.gd")
const FreeProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
var passed:int=0
var failed:int=0

func check(value:bool,label:String) -> void:
 if value:passed+=1
 else:failed+=1;push_error(label)

func _initialize() -> void:
 _identity();_signed_tracking();_arrival_matrix();_live_bounds()
 print("FREE_FLIGHT_FRAMING_V2 passed=",passed," failed=",failed)
 quit(1 if failed else 0)

func _identity() -> void:
 for version in ["pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-pirate-drill-v2",""]:
  check(not Frame.applies({"control_version":version,"route_profile":"ground-city-v1"}),"old controller remains camera-identical: "+version)
 check(Frame.applies({"control_version":"pilot-free-v1","route_profile":"ground-city-v1"}),"new controller also supports inherited ordinary content identity")
 var route:Dictionary={"control_version":"pilot-free-v1","route_profile":"free-ground-choice-v1","free_ground_schema":"free-ground-choice-v1"}
 check(Frame.is_ground_route(route),"strict fresh ground kiosk identity")
 route.control_version="pilot-v3"
 check(not Frame.is_ground_route(route),"new marker cannot reclassify legacy ground")

func _project_box(box:Rect2,center:Vector2,zoom:float,scene:Vector2) -> Rect2:
 return Rect2(Frame.Shared.project(box.position,center,zoom,scene),box.size*zoom)

func _signed_tracking() -> void:
 var scene:Vector2=Vector2(1280,720);var safe:Rect2=Frame.safe_rect(scene)
 var cargo:Vector2=Vector2(-2000,-10000);var craft:Rect2=Rect2(cargo-Vector2.ONE*108,Vector2.ONE*216)
 var goal:Vector2=Vector2(260,-8)*72;var receiver:Rect2=Rect2(goal-Vector2.ONE*504,Vector2.ONE*1008)
 var previous:Dictionary={}
 for tick in 120:
  previous=Frame.compose_bounds(craft,cargo,goal,receiver,504,Vector2(12,0),72,scene,safe,float(tick)/60.0,"running",previous)
 check(previous.center.x>craft.get_center().x,"right-moving craft has rightward lead")
 var first:Vector2=previous.lookahead
 var reversed:Dictionary=Frame.compose_bounds(craft,cargo,goal,receiver,504,Vector2(-12,0),72,scene,safe,2.0,"running",previous)
 check(first.distance_to(reversed.lookahead)<9.0,"direction reversal slews rather than jumps")
 for tick in range(121,240):
  reversed=Frame.compose_bounds(craft,cargo,goal,receiver,504,Vector2(-12,0),72,scene,safe,float(tick)/60.0,"running",reversed)
 check(reversed.center.x<craft.get_center().x,"return flight has leftward lead")
 var upward:Dictionary=Frame.compose_bounds(craft,cargo,goal,receiver,504,Vector2(0,-12),72,scene,safe,4.0,"running")
 check(upward.center.y<craft.get_center().y and upward.center.y<-9000,"no route lane or ground-Y clamp")
 var frozen:Dictionary=Frame.compose_bounds(craft,cargo,goal,receiver,504,Vector2(12,12),72,scene,safe,4.0,"running",upward)
 check(frozen.lookahead==upward.lookahead,"unchanged simulation time freezes directional slew")

func _arrival_matrix() -> void:
 for extent in [Vector2(640,360),Vector2(1280,720),Vector2(1920,1080)]:
  var scene:Vector2=extent*1280.0/extent.x;var safe:Rect2=Frame.safe_rect(extent)
  var unit:float=Frame.DisplayMetrics.factor(extent)*1280.0/extent.x
  var goal:Vector2=Vector2(260,-8)*72;var radius:float=504.0
  # Actual 279x220 ground sprite registered using World's deck anchor.
  var scale:float=(radius*2.0+120.0)/279.0
  var kiosk:Rect2=Rect2(goal+Vector2(0,radius+32)-Vector2(139.5,149)*scale,Vector2(279,220)*scale)
  var receiver:Rect2=kiosk.merge(Rect2(goal-Vector2.ONE*radius,Vector2.ONE*radius*2.0))
  for direction in 16:
   for meters in [8.99,7.0,3.0,0.0]:
    var cargo:Vector2=goal+Vector2.from_angle(TAU*direction/16.0)*meters*72
    var craft:Rect2=Rect2(cargo-Vector2.ONE*108,Vector2.ONE*216)
    var frame:Dictionary=Frame.compose_bounds(craft,cargo,goal,receiver,radius,Vector2(12,-4),72,scene,safe,5.0,"running",{},unit)
    check(frame.arrival,"arrival recognized from every direction")
    # Use a wildly stale interpolated camera, not only the eventual target.
    var fit:Dictionary=Frame.constrain(cargo+Vector2(1500,-1000),.90,frame,extent)
    check(safe.grow(.001).encloses(_project_box(frame.full,fit.center,fit.zoom,scene)),"every arrival frame contains craft, capture mouth and entire kiosk")
    if extent.x>=1280:
     check(not fit.readability_limited,"ordinary starter remains above readable floor at supported native size")
    var success:Dictionary=Frame.compose_bounds(craft,cargo,goal,receiver,radius,Vector2.ZERO,72,scene,safe,5.0,"success",frame,unit)
    check(success.center.is_equal_approx(frame.center) and is_equal_approx(success.zoom,frame.zoom),"status transition alone cannot create success zoom lurch")
  var cargo:Vector2=goal+Vector2(0,-9.1*72);var craft:Rect2=Rect2(cargo-Vector2.ONE*108,Vector2.ONE*216)
  var preview:Dictionary=Frame.compose_bounds(craft,cargo,goal,receiver,radius,Vector2.ZERO,72,scene,safe,1.0,"running",{},unit)
  check(not preview.arrival and preview.approach_weight>.99,"smooth geometric preview before full arrival constraint")
 # Do not falsely promise a readable floor for geometry that cannot fit.
 var huge:Dictionary=Frame.compose_bounds(Rect2(-2000,-2000,4000,4000),Vector2.ZERO,Vector2.ZERO,Rect2(-500,-500,1000,1000),504,Vector2.ZERO,72,Vector2(1280,720),Frame.safe_rect(Vector2(1280,720)),0,"running")
 check(huge.readability_limited,"oversized geometry explicitly reports unreadable containment conflict")

func _live_bounds() -> void:
 var route:Dictionary=FreeProfile.route(Ground.route({"weight":1.0}))
 var sim=FreeSim.new();sim.configure(FreeProfile.starter_design(),[],route,42)
 var body:Dictionary=sim.body_for_part(1);body.angle=.7;body.position=Vector2(260,-8)
 var origin:Vector2=Vector2(1115,330)
 var receiver=Sprite2D.new()
 receiver.texture=ImageTexture.create_from_image(Image.create_empty(279,220,false,Image.FORMAT_RGBA8))
 receiver.centered=false;receiver.scale=Vector2.ONE*1128.0/279.0
 receiver.position=origin+Vector2(route.distance,route.destination_y)*72+Vector2(0,536)-Vector2(139.5,149)*receiver.scale
 var before:PackedByteArray=var_to_bytes([sim.route,sim.parts,sim.bodies,sim.obstacles,sim.telemetry,sim.elapsed,sim.status])
 var frame:Dictionary=Frame.compose(sim,origin,72,receiver,Vector2(1280,720))
 var actual:Rect2=Frame.Receipt.receiver_bounds(receiver)
 print("BOUNDS_DIAG receiver=",frame.receiver," actual=",actual," start_delta=",frame.receiver.position-actual.position," end_delta=",frame.receiver.end-actual.end)
 check(frame.receiver.encloses(actual),"actual transformed sprite bounds retained")
 for p in body.parts:
  var module:Rect2=Frame._part_bounds(sim,p,origin,72,body.angle+p.local_angle)
  check(frame.craft.encloses(module),"every rotated cargo-connected module contained")
 check(var_to_bytes([sim.route,sim.parts,sim.bodies,sim.obstacles,sim.telemetry,sim.elapsed,sim.status])==before,"all physics/replay/route bytes unchanged")
 var attached:Rect2=Frame.craft_bounds(sim,origin,72)
 for p in body.parts:
  p.world_pos=sim.part_world_position(p.id);p.world_angle=body.angle+p.local_angle;p.delivered=true
 sim.status="success";sim.bodies.clear()
 check(Frame.craft_bounds(sim,origin,72).is_equal_approx(attached),"detached recovered hardware retains the complete success bounds")
 receiver.free()
