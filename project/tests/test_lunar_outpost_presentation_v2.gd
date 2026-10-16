extends SceneTree
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Receipt=preload("res://scripts/lunar_outpost_receipt_v2.gd")
const Presenter=preload("res://scripts/lunar_outpost_presentation_2d.gd")
var passed:int=0
var failed:int=0
class VisualFixture extends RefCounted:
 var position:Vector2=Vector2.ZERO
 var status:String="running"
 var obstacles:Array=[]
 func cargo_position() -> Vector2:return position
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var host:Node2D=Node2D.new();root.add_child(host)
 var world:Node2D=Node2D.new();host.add_child(world)
 var presenter=Presenter.new();host.add_child(presenter)
 var route:Dictionary=Profile.route(Content.fresh_catalog())
 if route.is_empty():
  check(false,"lunar route authoring failed before presentation tests");host.free();quit(1);return
 var frozen:Dictionary=route.duplicate(true)
 check(Receipt.art_error(false).is_empty(),"all recovered and reused files match pinned SHA receipts")
 check(Receipt.art_error().is_empty(),"all pinned lunar resources import with exact dimensions")
 check(presenter.configure_route(route,world,Vector2.ZERO,72.0),"only complete registered new lunar content enables presenter")
 var model:VisualFixture=VisualFixture.new()
 for raw in route.hazards:
  var h:Dictionary=raw.duplicate(true);h.position=Vector2(h.x,h.y)
  h.velocity=Vector2(float(h.velocity[0]),float(h.velocity[1])) if h.has("velocity") else Vector2.ZERO
  model.obstacles.append(h)
 var before:Array=model.obstacles.duplicate(true)
 model.position=Vector2(180.0,-40.0);presenter.update_from_sim(model,.52,model.position)
 check(presenter.debug_snapshot().weight==1.0,"actual progress reveals lunar sky and regolith")
 check(presenter.get_child_count()==2 and world.get_child_count()==1,"exactly two backdrop planes and one bounded field")
 check(presenter.suppresses_hazard(0) and presenter.suppresses_hazard(2) and not presenter.suppresses_hazard(3),"three lunar rocks have sole presentation ownership")
 var receiver:Sprite2D=presenter.receiver_node()
 check(receiver!=null and receiver.get_meta("capture_center")==Content.DESTINATION*72.0,"platform registers exact simulated capture center")
 var art_top:float=receiver.position.y
 check(art_top>(Content.DESTINATION.y+Content.DELIVERY_RADIUS+1.0)*72.0,"whole platform is below capture mouth, leaving two-way approach clear")
 var shader:Shader=load(Receipt.SHADER)
 var sky:Sprite2D=presenter.get_child(0);var terrain:Sprite2D=presenter.get_child(1)
 check(sky.material.shader==shader and sky.material.get_shader_parameter("repeat_x")==false,"Earth texture is clamped and cannot tile duplicate planets")
 check(terrain.material.get_shader_parameter("repeat_x")==true and terrain.material.get_shader_parameter("terrain")==true,"regolith keeps recovered same-direction decorative wrap")
 check(sky.material.get_shader_parameter("source_size_px")==Vector2(1536,864),"native overscan dimensions are not stretched into wrong source coordinates")
 var parameter:Variant=terrain.material.get_shader_parameter("scroll_px")
 presenter.update_from_sim(model,.52,model.position)
 check(terrain.material.get_shader_parameter("scroll_px")==parameter,"unchanged/paused sample has no autonomous terrain motion")
 model.position=Vector2(20.0,-40.0);presenter.update_from_sim(model,.52,model.position)
 check(presenter.debug_snapshot().weight==0.0,"reversing to departure reverses blend without restarting an effect")
 model.position=Vector2(250.0,-40.0);model.status="success";presenter.update_from_sim(model,.35,model.position)
 check(presenter.route_enabled() and presenter.receiver_node()==receiver,"terminal state preserves same registered receiver")
 check(route==frozen and model.obstacles==before,"presentation never mutates route or physical rocks")
 presenter.set_scene_visible(false);check(not world.get_child(0).visible,"leaving flight hides all external field props")
 presenter.leave_flight();check(world.get_child_count()==0 and presenter.get_child_count()==0,"leaving flight frees both external props and backdrop planes")
 check(presenter.configure_route(route,world,Vector2.ZERO,72.0),"second dispatch can recreate bounded lunar scene")
 check(presenter.configure_route(route,world,Vector2.ZERO,72.0) and world.get_child_count()==1 and presenter.get_child_count()==2,"repeat configure replaces prior scene without duplicate props")
 var wrong:Dictionary=route.duplicate(true);wrong.lunar_schema="future-v99"
 check(not presenter.configure_route(wrong,world,Vector2.ZERO,72.0) and world.get_child_count()==0,"invalid lunar snapshot never receives fallback scenery")
 host.free()
 print("LUNAR_OUTPOST_PRESENTATION_V2_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
