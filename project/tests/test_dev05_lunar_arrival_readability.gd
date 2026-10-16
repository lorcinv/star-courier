extends SceneTree
## Synthetic source/geometry gate; real-pixel native judgment remains separate.
const HUD=preload("res://scripts/game_hud.gd")
const Presenter=preload("res://scripts/lunar_outpost_presentation_2d.gd")
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Raster=preload("res://scripts/demo_raster_skin.gd")
var passed:int=0
var failed:int=0
class Fixture extends RefCounted:
 var position:Vector2=Vector2(238,-40)
 var status:String="running"
 var obstacles:Array=[]
 func cargo_position() -> Vector2:return position
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var route:Dictionary=Profile.route(Content.fresh_catalog())
 var route_bytes:PackedByteArray=var_to_bytes(route)
 var flight:Dictionary={"speed":30.0,"cargo_y":-40.0,"destination_distance":20.0,"energy_remaining":80.0,"energy_capacity":100.0,"energy_fraction":.8,"flight_status":"running","arrival_state":"en_route","destination_navigation":{"status":"running","charging":false,"cargo_screen":Vector2(500,360),"receiver_screen":Vector2(850,360),"distance_m":20.0},"events":[]}
 var frozen:PackedByteArray=var_to_bytes(flight)
 var hud=HUD.new();root.add_child(hud);await process_frame
 hud.render({"mode":"flight","control_version":"pilot-free-v2","activeorder":route,"flight":flight,"settings":{"reduced_motion":true}})
 hud.update_flight(flight)
 check(hud.flight_labels.status.text=="按 Ctrl 减速交件","near-field excess speed gets advice before touching the ring")
 check(var_to_bytes(flight)==frozen and var_to_bytes(route)==route_bytes,"HUD advice leaves input telemetry and authored route exact")
 flight.destination_distance=27.0;hud.update_flight(flight)
 check(hud.flight_labels.status.text=="按 Ctrl 减速交件","advice includes exact existing preview boundary")
 flight.destination_distance=27.01;hud.update_flight(flight)
 check(hud.flight_labels.status.text=="朝箭头方向飞","outside preview retains one ordinary goal")
 flight.destination_distance=12.0;flight.speed=24.0;hud.update_flight(flight)
 check(hud.flight_labels.status.text=="进入光圈交件","capture-compatible speed names real airborne target")
 flight.speed=24.01;hud.set_input_device(true);hud.update_flight(flight)
 check(hud.flight_labels.status.text=="按 LT 减速交件","gamepad advice uses actual brake input")
 for side in [-1,1]:
  flight.cargo_x=250.0+side*12.0;flight.speed=30.0;hud.update_flight(flight)
  check(hud.flight_labels.status.text=="按 LT 减速交件","same advice survives overshoot and return side "+str(side))
 for state in ["paused","charging"]:
  flight[state]=true;hud.update_flight(flight)
  check(hud.flight_labels.status.text==("已暂停" if state=="paused" else "准备起飞"),"existing "+state+" state has priority")
  flight[state]=false
 for state in ["success","failed"]:
  flight.flight_status=state;hud.update_flight(flight)
  check(hud.flight_labels.status.text==("货物已签收" if state=="success" else "配送失败"),"terminal "+state+" has priority")
 flight.flight_status="running"
 for key in ["speed","destination_distance"]:
  for malformed in [NAN,INF,-1.0,"12",true,null]:
   var bad:Dictionary=flight.duplicate(true);bad[key]=malformed
   check(hud._lunar_arrival_action(bad).is_empty(),"invalid "+key+" cannot invent arrival advice")
 var older:Dictionary=route.duplicate(true);older.control_version="pilot-free-v1";hud.state.activeorder=older
 check(hud._lunar_arrival_action(flight).is_empty(),"old in-flight controls remain unmodified")
 older.control_version="pilot-free-v2";older.route_profile="free-ground-choice-v1"
 check(hud._lunar_arrival_action(flight).is_empty(),"ordinary ground state is not silently changed")
 hud.state.activeorder=route
 var host=Node2D.new();root.add_child(host);var world=Node2D.new();host.add_child(world)
 var presenter=Presenter.new();host.add_child(presenter)
 check(presenter.configure_route(route,world,Vector2.ZERO,72.0),"exact lunar presenter configures")
 var fixture=Fixture.new()
 for raw in route.hazards:
  var h:Dictionary=raw.duplicate(true);h.position=Vector2(h.x,h.y);h.velocity=Vector2(float(h.velocity[0]),float(h.velocity[1])) if h.has("velocity") else Vector2.ZERO;fixture.obstacles.append(h)
 var model_bytes:PackedByteArray=var_to_bytes(fixture.obstacles)
 for zoom in [.25,.52,.9]:
  presenter.update_from_sim(fixture,zoom,fixture.position)
  var card:PanelContainer=presenter._label_card
  check(card.visible and card.mouse_filter==Control.MOUSE_FILTER_IGNORE,"tag stays visible and never intercepts input at "+str(zoom))
  check(card.get_theme_stylebox("panel") is StyleBoxTexture and card.get_theme_stylebox("panel").texture.atlas==Raster.ATLAS,"tag uses unchanged generated raster pixels")
  check(presenter._label.text=="进入光圈交件","tag labels the circle action instead of the platform")
  var rect:Rect2=Rect2(card.position,card.size*card.scale)
  var r:float=Content.DELIVERY_RADIUS*72.0
  check(Rect2(Content.DESTINATION*72.0-Vector2.ONE*r,Vector2.ONE*r*2).encloses(rect),"tag remains in protected receiver bounds")
  check(card.scale.is_equal_approx(Vector2.ONE/zoom),"text stays screen-sized")
 presenter.update_from_sim(fixture,.1,fixture.position)
 check(not presenter._label_card.visible,"forced ultra-wide fit hides world tag rather than overflowing or tiny type")
 fixture.status="success";presenter.update_from_sim(fixture,.52,fixture.position)
 check(presenter._label.text=="货物已签收","success label requires actual simulation success")
 check(var_to_bytes(route)==route_bytes and var_to_bytes(fixture.obstacles)==model_bytes,"world tag mutates no authored field or obstacle")
 presenter.leave_flight();check(world.get_child_count()==0,"tag cleanup retains bounded scene ownership")
 host.free();hud.free();print("DEV05_LUNAR_ARRIVAL_READABILITY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
