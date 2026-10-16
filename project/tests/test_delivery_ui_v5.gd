extends Node
## One narrow actual portal/threat projection plus early receipt-speed layout.
const Profile=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const Simulation=preload("res://scripts/pilot_delivery_rift_simulation_v5.gd")
const Presenter=preload("res://scripts/rift_delivery_presenter_v5.gd")
const DeliveryUI=preload("res://scripts/delivery_ui_v3.gd")
const Moon=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const HUD=preload("res://scripts/game_hud.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
class Snapshot extends RefCounted:
 var telemetry:Dictionary={}
 var elapsed:float=0.0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for i in 3:await get_tree().process_frame
func fits(label:Label)->bool:
 return label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x<=label.size.x
func run()->void:
 if OS.get_environment("SC_RIFT_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 var route:Dictionary=Profile.route()
 check(not route.is_empty() and Presenter.route_error(route).is_empty(),"new v5 gate validates exact existing resources")
 var wrong:Dictionary=route.duplicate(true);wrong.control_version="pilot-delivery-v3"
 check(not Presenter.route_error(wrong).is_empty(),"old version with rift markers fails closed")
 check(not Caps.group_available("otherworld") and not Caps.group_available("moon"),"legacy missing art capabilities remain closed")
 var world=World.new();world.flight_root=Node2D.new();world.add_child(world.flight_root)
 var origin:Vector2=Vector2(660,345);var goal:Vector2=origin+Vector2(route.distance,route.destination_y)*72.0
 var receiver:Sprite2D=world._ground_receiver(goal,float(route.delivery_radius)*72.0)
 var presenter=Presenter.new();add_child(presenter)
 check(presenter.configure_route(route,world.flight_root,origin),"pixel geometry portal field configures without old wormhole art")
 presenter.bind_receiver(receiver)
 var fake=Snapshot.new();fake.telemetry={"region":"departure","portal_crossing_tick":-1,"cargo_x":200.0}
 var safe:Rect2=Rect2(origin+Vector2(80,-35)*72.0,Vector2(140,70)*72.0)
 presenter.update_from_sim(fake,.52,safe)
 check(not presenter.special_active() and not receiver.visible,"X-only arrival cannot change scene or reveal receiver")
 fake.telemetry.region="greenhouse";presenter.update_from_sim(fake,.52,safe)
 check(not presenter.special_active(),"region alone without a crossing tick cannot change scene")
 fake.telemetry.portal_crossing_tick=1;fake.telemetry.region="departure";presenter.update_from_sim(fake,.52,safe)
 check(not presenter.special_active(),"crossing tick alone without correct region cannot change scene")
 check(presenter._field.point(route.rift_portal.entry)==origin+Vector2(28,0)*72.0 and presenter._field.point(route.rift_portal.exit)==origin+Vector2(100,0)*72.0,"both portal planes use authoritative world coordinates")
 var sim=Simulation.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),route,42)
 sim.release_launcher(0,1)
 for i in 1600:
  sim.step(1.0/120.0)
  if bool(sim.telemetry.get("rift_pirate",{}).get("warning",false)):break
 check(Presenter.crossed(sim.telemetry) and not sim.portal_crossings.is_empty(),"real launched craft physically crosses entry before special region")
 check(bool(sim.telemetry.rift_pirate.warning) and float(sim.telemetry.rift_pirate.warning_remaining)>2.5,"real finite-ammo pirate begins authoritative advance warning")
 var before:PackedByteArray=var_to_bytes(sim.telemetry)
 presenter.update_from_sim(sim,.52,safe);await settle()
 check(presenter.special_active() and receiver.visible and receiver.get_meta("capture_center")==goal,"actual crossing reveals special sky and exact receiver")
 check(var_to_bytes(sim.telemetry)==before,"world projection never changes solver telemetry")
 check(presenter._pirate.position==origin+Vector2(sim.telemetry.rift_pirate.position)*72.0,"one pirate sprite stays on its real collider")
 var cold_label:Vector2=presenter._field.zone_label_position(route.rift_biology.cold_bounds)
 var turbulence_label:Vector2=presenter._field.zone_label_position(route.rift_turbulence.bounds,true)
 check(turbulence_label.y-cold_label.y>32.0/.52,"cold upper label and turbulence lower label cannot overlap; actual bounds stay fixed")
 var frozen:Dictionary=presenter.debug_snapshot();await settle()
 check(presenter.debug_snapshot()==frozen,"no autonomous portal warning or cycle timer")
 var hud=HUD.new();add_child(hud)
 var fixture:Dictionary={"mode":"flight","control_version":Profile.VERSION,"activeorder":route,"settings":{"reduced_motion":true},"flight":sim.telemetry.duplicate(true)}
 hud.render(fixture);await settle()
 check(hud._free_flight_mode() and hud._delivery_mode(),"v5 retains known controls and cargo-only health")
 check(hud.flight_labels.status.text==Presenter.status_text(sim.telemetry) and "海盗瞄准" in hud.flight_labels.status.text,"HUD warning uses actual physical countdown")
 check(fits(hud.flight_labels.status),"pirate countdown fits existing status card")
 for i in 500:
  sim.step(1.0/120.0)
  if int(sim.telemetry.rift_pirate.shots_fired)>0:break
 presenter.update_from_sim(sim,.52,safe);await settle()
 check(sim.telemetry.rift_pirate.ammo_remaining==1 and not sim.telemetry.rift_pirate.last_ray.is_empty(),"real fired shot decrements finite ammunition and records exact ray")
 check(presenter._field.frame.rift_pirate.last_ray==sim.telemetry.rift_pirate.last_ray,"display consumes exact physical hit endpoint")
 var flight:Dictionary=sim.telemetry.duplicate(true)
 flight.destination_distance=55.0;flight.speed=12.0;flight.flight_status="running"
 flight.rift_pirate.warning=true;flight.rift_pirate.warning_remaining=1.25
 flight.biological_temperature_c=-12.0;flight.biological_exposure_seconds=2.0
 flight.delivery_integrity=.95
 hud.update_flight(flight);await settle()
 check(hud.flight_labels.receipt_speed.visible and hud.flight_labels.receipt_speed.text=="收件 ≤ 8.0 m/s" and "12.0" in hud.flight_labels.speed.text,"early approach shows actual 8m/s limit beside current speed")
 check("海盗瞄准" in hud.flight_labels.status.text and fits(hud.flight_labels.status),"receipt limit leaves active warning fully readable")
 check(hud.flight_labels.integrity.text=="95%" and hud.flight_labels.integrity_minimum.text=="最低 80%" and hud.flight_labels.integrity_status.text=="完整度达标" and "2.0/2.5 s" in hud.flight_labels.biology.text and hud.flight_labels.biology.is_visible_in_tree(),"cold exposure stays in its persistent context line while the only HP card retains qualification")
 check(fits(hud.flight_labels.receipt_speed) and hud.flight_labels.receipt_speed.get_global_rect().end.y<=hud.content.get_node("FlightTelemetry").get_global_rect().end.y,"speed limit fits within unchanged telemetry card")
 flight.delivery_integrity=.7;hud.update_flight(flight)
 check("不合格" in hud.flight_labels.integrity_status.text,"below-minimum cargo warning wins over biology context")
 flight.rift_pirate.warning=false;flight.rift_turbulence={"enabled":true,"inside":true,"active":true,"seconds_to_change":1.5};hud.update_flight(flight)
 check(hud.flight_labels.status.text=="乱流持续 1.5s","bounded physical field countdown is authoritative")
 flight.flight_status="failed";flight.rift_pirate.warning=true;hud.update_flight(flight)
 check(hud.flight_labels.status.text=="配送失败" and not hud.flight_labels.receipt_speed.visible,"terminal state outranks hazard and approach guidance")
 var moon:Dictionary=Moon.route();var near:Dictionary={"speed":24.0,"destination_distance":140.0,"flight_status":"running"}
 check(not DeliveryUI.receipt_speed(near,moon).is_empty(),"fast lunar approach reveals 8m/s threshold well before mouth")
 near.destination_distance=300.0
 check(DeliveryUI.receipt_speed(near,moon).is_empty(),"far ascent retains concise normal telemetry")
 near.destination_distance=50.0;near.speed=6.0
 check(not DeliveryUI.receipt_speed(near,moon).overspeed,"actual speed under exact contract threshold is not flagged")
 moon.control_version="pilot-delivery-v3"
 check(DeliveryUI.receipt_speed(near,moon).is_empty(),"chapter-one UI has no new arrival threshold row")
 presenter.leave_flight();check(not presenter.route_enabled() and not presenter.visible,"exit cleans new scene and threat projection")
 hud.queue_free();presenter.queue_free();world.free();await settle()
 print("DELIVERY_UI_V5 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
