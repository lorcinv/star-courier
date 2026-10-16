extends SceneTree
## Synthetic HUD rendering/metric checks; no native visual acceptance claim.
const HUD=preload("res://scripts/game_hud.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error(label)
func run() -> void:
 var hud=HUD.new();root.add_child(hud);await process_frame
 var route:Dictionary={"control_version":"pilot-free-v1","destination_name":"屋顶收件台","background_ground_y_m":0.0}
 var flight:Dictionary={"control_version":"pilot-free-v1","free_flight":true,"speed":12.345,"cargo_y":-8.0,"energy_remaining":80.0,"energy_capacity":100.0,"energy_fraction":.8,"flight_status":"running","destination_navigation":{"status":"running","charging":false,"cargo_screen":Vector2(600,360),"receiver_screen":Vector2(1400,360),"distance_m":100.0},"events":[]}
 for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)))
  hud.render({"mode":"flight","control_version":"pilot-free-v1","activeorder":route,"flight":flight,"settings":{"reduced_motion":true}})
  for i in 4:await process_frame
  hud.update_flight(flight)
  check(hud.flight_labels.speed.text=="速度 12.3 m/s","real speed displayed in m/s")
  check(hud.flight_labels.height.text=="高度 +8.0 m · 地面基准","height explicitly labels scene ground datum")
  check(hud.flight_labels.energy.text=="电量 80%","energy stays visible")
  check(hud._destination_cue.visible,"target arrow stays visible")
  var telemetry:Control=hud.content.get_node("FlightTelemetry")
  var goal:Control=hud.content.get_node("FreeFlightGoal")
  var resources:Control=hud.content.get_node("FlightResources")
  check(not telemetry.get_global_rect().intersects(goal.get_global_rect()) and not telemetry.get_global_rect().intersects(resources.get_global_rect()),"native telemetry panel does not overlap target/energy")
  for label in [hud.flight_labels.speed,hud.flight_labels.height]:
   check(telemetry.get_global_rect().grow(1).encloses(label.get_global_rect()),"native telemetry text fits its panel")
 var height:Dictionary=hud._free_flight_height({"cargo_y":-20.0},{"background_ground_y_m":5.0})
 check(height.value==25.0 and height.label=="地面基准","offset ground plane is respected")
 height=hud._free_flight_height({"cargo_y":-20.0},{})
 check(height.value==20.0 and height.label=="起飞基准","missing terrain gets honest launch datum")
 height=hud._free_flight_height({"cargo_y":3.0},{"background_ground_y_m":0.0})
 check(height.value==-3.0,"below datum remains negative, never silently clamped")
 height=hud._free_flight_height({"altitude":9.0},{})
 check(height.value==9.0,"legacy altitude fallback uses same launch coordinate")
 height=hud._free_flight_height({},{})
 check(not is_finite(height.value),"missing height stays unknown")
 flight.speed=NAN;flight.cargo_y=NAN;hud.update_flight(flight)
 check(hud.flight_labels.speed.text=="速度 — m/s" and hud.flight_labels.height.text.begins_with("高度 — m"),"invalid readings are not fabricated zeros")
 flight.speed=4.0;flight.cargo_y=-10.0;flight.paused=true;hud.update_flight(flight)
 check(hud.flight_labels.status.text=="已暂停" and hud.flight_labels.speed.text=="速度 4.0 m/s","pause retains last actual telemetry")
 hud.free()
 print("DEV03_FLIGHT_TELEMETRY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
