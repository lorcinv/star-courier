extends Node
## Narrow new-ascent presentation gate. Geometry/telemetry only, no user saves.
const Profile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const Presenter=preload("res://scripts/moon_ascent_presenter_v4.gd")
const Backdrop=preload("res://scripts/ascent_backdrop_2d.gd")
const HUD=preload("res://scripts/game_hud.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
class FlightView extends RefCounted:
 var at:Vector2=Vector2.ZERO
 var telemetry:Dictionary={}
 func cargo_position() -> Vector2:return at
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for tick in 4:await get_tree().process_frame
func warn(seconds:float=3.25,active:bool=false) -> Dictionary:
 return {"id":"ascent-shower-1","seconds_to_spawn":seconds,"position":Vector2(4,-330),"velocity":Vector2(16,2.5),"radius":.9,"active":active}
func run() -> void:
 if OS.get_environment("SC_ASCENT_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 var route:Dictionary=Profile.route()
 check(not route.is_empty() and Profile.validation_error(route).is_empty(),"new authoritative ascent route is valid")
 check(Presenter.route_error(route).is_empty(),"new ascent gate accepts exact existing lunar resources")
 var malformed:Dictionary=route.duplicate(true);malformed.control_version="pilot-delivery-v3"
 check(not Presenter.route_error(malformed).is_empty(),"mixed old-version ascent markers fail closed")
 check(not Caps.group_available("moon"),"legacy unavailable moon component stays closed")
 var backdrop=Backdrop.new();add_child(backdrop);backdrop.configure_route(route)
 backdrop.update_flight(Vector2(0,-100),Vector2(0,-4),1.0)
 check(backdrop.debug_snapshot().orbit_weight==0.0,"100m stays atmosphere instead of old 85/135m orbit")
 backdrop.update_flight(Vector2(0,-220),Vector2(0,-4),0.0)
 check(backdrop.debug_snapshot().orbit_weight>0.0 and backdrop.debug_snapshot().orbit_weight<1.0,"current 180 to 260m interval blends continuously")
 backdrop.update_flight(Vector2(10000,0),Vector2.RIGHT,1.0)
 check(backdrop.debug_snapshot().orbit_weight==0.0,"horizontal travel and route progress cannot fake orbit")
 backdrop.update_flight(Vector2(0,-280),Vector2(0,-4),0.0)
 check(backdrop.debug_snapshot().orbit_weight==1.0,"actual 280m altitude reaches space")
 backdrop.update_flight(Vector2(0,-80),Vector2(0,4),1.0)
 check(backdrop.debug_snapshot().orbit_weight==0.0 and backdrop.debug_snapshot().cloud_weight>0.0,"descending restores atmosphere rather than highest-altitude latch")
 var world=World.new();world.flight_root=Node2D.new();world.add_child(world.flight_root)
 var origin:Vector2=Vector2(660,345);var goal:Vector2=origin+Vector2(route.distance,route.destination_y)*72.0
 var receiver:Sprite2D=world._ground_receiver(goal,float(route.delivery_radius)*72.0)
 check(receiver.get_meta("capture_center")==goal and receiver.get_meta("deck_center").y>goal.y,"moon receiver art uses exact physical capture coordinate and deck below it")
 var presentation=Presenter.new();add_child(presentation)
 var before:PackedByteArray=var_to_bytes(route)
 check(presentation.configure_route(route,world.flight_root,origin,72.0),"new moon presenter configures without optional legacy airlock")
 presentation.bind_receiver(receiver)
 var view:=FlightView.new()
 var safe:Rect2=Rect2(-10000,-100000,20000,100000)
 presentation.update_from_sim(view,origin,1.0,Vector2(1280,720),safe)
 check(presentation.debug_snapshot().weight==0.0,"ground departure has no fake lunar backdrop")
 view.at=Vector2(10000,0);presentation.update_from_sim(view,origin,1.0,Vector2(1280,720),safe)
 check(presentation.debug_snapshot().weight==0.0,"X does not trigger lunar arrival scenery")
 view.at=Vector2(0,-530);presentation.update_from_sim(view,origin+view.at*72.0,.52,Vector2(1280,720),safe)
 check(is_equal_approx(presentation.debug_snapshot().weight,.5),"real 530m height blends halfway between frozen 500 and 560m thresholds")
 view.at=Vector2(40,-560);view.telemetry={"ascent_warnings":[warn()]}
 presentation.update_from_sim(view,origin+view.at*72.0,.52,Vector2(1280,720),safe)
 check(presentation.debug_snapshot().weight==1.0 and presentation.debug_snapshot().warning_count==1,"moon arrival and warning consume current simulation snapshot")
 var frozen:Dictionary=presentation.debug_snapshot();await settle()
 check(presentation.debug_snapshot()==frozen,"presentation has no autonomous phase or warning clock")
 view.at=Vector2(0,-80);view.telemetry.ascent_warnings=[];presentation.update_from_sim(view,origin+view.at*72.0,.52,Vector2(1280,720),safe)
 check(presentation.debug_snapshot().weight==0 and presentation.debug_snapshot().warning_count==0,"descent and authoritative warning cancellation reset visible state")
 check(var_to_bytes(route)==before and receiver.get_meta("capture_center")==goal,"background and cue updates never mutate route or move receiver")
 check(Presenter.warnings_from({"ascent_warnings":[warn(),{"position":[1,2]},warn(-1),warn(INF)]}).size()==1,"only finite complete authoritative warning records are displayed")
 var hud=HUD.new();add_child(hud)
 var flight:Dictionary={"cargo_y":-220.0,"altitude_m":220.0,"ascent_phase":"upper_air","ascent_warnings":[],"delivery_integrity":.99,"flight_status":"running","speed":12.0,"energy_remaining":5500.0,"energy_capacity":6000.0,"energy_fraction":5500.0/6000.0}
 var fixture:Dictionary={"mode":"flight","control_version":Profile.VERSION,"activeorder":route,"settings":{"reduced_motion":true},"flight":flight}
 hud.render(fixture);await settle()
 check(hud._free_flight_mode() and hud._force_flight_mode() and hud._delivery_mode(),"v4 reuses approved inertial controls and delivery HUD")
 check(hud.flight_labels.integrity.text=="99%" and hud.flight_labels.integrity_minimum.text=="最低 80%","cargo integrity and order threshold stay visible")
 check("220.0" in hud.flight_labels.height.text and "电量" in hud.flight_labels.energy.text,"real current height and energy stay visible")
 check(hud.flight_labels.status.text=="穿过高空，留意电量","phase copy consumes real physics phase")
 flight.ascent_warnings=[warn()];hud.update_flight(flight);await settle()
 check("3.2" in hud.flight_labels.status.text and "流星雨" in hud.flight_labels.status.text,"pre-spawn countdown comes directly from authority")
 var waiting:String=hud.flight_labels.status.text;await settle()
 check(hud.flight_labels.status.text==waiting,"HUD never counts down while physics is unchanged or paused")
 flight.ascent_warnings=[warn(0,true)];hud.update_flight(flight)
 check(hud.flight_labels.status.text=="流星来袭，避开箭头标记","spawned real entity switches warning copy")
 flight.ascent_phase="lunar_approach";flight.ascent_warnings=[];flight.cargo_y=-550;hud.update_flight(flight);await settle()
 check(hud.flight_labels.status.text=="接近月面，减速进入收件光圈","cleared warnings resume actual lunar-approach guidance")
 var label:Label=hud.flight_labels.status
 check(label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x<=label.size.x,"longest ascent guidance fits existing destination card")
 flight.flight_status="failed";flight.ascent_warnings=[warn(0,true)];hud.update_flight(flight)
 check(hud.flight_labels.status.text=="配送失败","terminal result has priority over hazard cue")
 # One narrow real-solver threshold test; this is not a ground-to-moon playthrough.
 var Simulation=load("res://scripts/pilot_delivery_ascent_simulation_v4.gd")
 var actual=Simulation.new();actual.configure(Profile.starter_design(),[],route,42)
 actual.body_for_part(1).position=Vector2(80,-281);actual.release_launcher(0,0);actual.step(1.0/120.0)
 var live:Array[Dictionary]=Presenter.warnings_from(actual.telemetry)
 check(live.size()==3 and not live[0].active and float(live[0].seconds_to_spawn)>3.0,"real altitude trigger produces three finite pre-spawn cues")
 var actual_flight:Dictionary=fixture.duplicate(true);actual_flight.flight=actual.telemetry.duplicate(true)
 hud.render(actual_flight);await settle()
 check(hud.flight_labels.status.text==Presenter.status_text(actual.telemetry) and "3.2" in hud.flight_labels.status.text,"HUD countdown matches real solver warning exactly")
 var live_before:PackedByteArray=var_to_bytes(actual.telemetry)
 presentation.update_from_sim(actual,origin+actual.cargo_position()*72.0,.52,Vector2(1280,720),safe)
 check(presentation.debug_snapshot().warning_count==3 and var_to_bytes(actual.telemetry)==live_before,"world warning projection consumes real cues without advancing or mutating simulation")
 for tick in 400:actual.step(1.0/120.0)
 hud.update_flight(actual.telemetry)
 check(Presenter.warnings_from(actual.telemetry).any(func(item):return item.active) and hud.flight_labels.status.text=="流星来袭，避开箭头标记","actual spawned moving meteor drives active warning")
 var legacy:Dictionary=fixture.duplicate(true);legacy.control_version="pilot-delivery-v3";legacy.activeorder.control_version="pilot-delivery-v3";legacy.flight=flight.duplicate(true);legacy.flight.flight_status="running"
 hud.render(legacy);await settle()
 check(hud.flight_labels.status.text=="朝箭头方向飞","chapter-one presentation does not adopt ascent warning fields")
 presentation.leave_flight();check(not presentation.route_enabled() and not presentation.visible,"leaving flight releases all new presenter state")
 hud.queue_free();presentation.queue_free();backdrop.queue_free();world.free();await settle()
 print("DELIVERY_UI_V4 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
