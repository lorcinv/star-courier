extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var hud=HUD.new();root.add_child(hud);await process_frame
 var success:String="001.9s  模块分裂：质量、储能、强度与耐久均分，未复制货物。"
 var tiny:String="001.9500s  首次受损：分裂核 #1005 · 碰撞 · 0.00 HP。"
 var flight:Dictionary={"elapsed":2.0,"control_version":"pilot-free-v2","free_flight":true,"speed":5.5,"cargo_y":-3.6,"energy_remaining":5880.0,"energy_capacity":6000.0,"energy_fraction":.98,"flight_status":"running","events":[success,tiny],"selected_tool":{"name":"分裂核","status":"可用","direction":"→","hold_to_use":false},"destination_navigation":{"status":"running","charging":false,"cargo_screen":Vector2(600,360),"receiver_screen":Vector2(1400,360),"distance_m":248.0}}
 var before:Dictionary=flight.duplicate(true)
 for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)))
  hud.render({"mode":"flight","control_version":"pilot-free-v2","activeorder":{"control_version":"pilot-free-v2","background_ground_y_m":0.0},"flight":flight,"settings":{"reduced_motion":true}})
  for i in 3:await process_frame
  hud.update_flight(flight)
  check(hud.flight_labels.events.text=="模块已分裂 · 发生碰撞，零件受损。","brief success and actual contact both visible "+str(extent))
  check(hud.content.get_node("FlightEventReceipt").visible,"same existing receipt panel used "+str(extent))
  check(hud.flight_labels.events.get_theme_font("font").get_string_size(hud.flight_labels.events.text,HORIZONTAL_ALIGNMENT_LEFT,-1,hud.flight_labels.events.get_theme_font_size("font_size")).x<=hud.flight_labels.events.size.x,"short combined text fits existing line "+str(extent))
  check(hud.flight_labels.tool_state.text=="可用" and hud.flight_labels.energy.text=="电量 98%","readiness and battery state unchanged "+str(extent))
 check(flight==before,"HUD does not mutate input snapshot")
 flight.paused=true;hud.update_flight(flight)
 check(hud.flight_labels.events.text.begins_with("模块已分裂"),"pause retains receipt at fixed simulation elapsed")
 for warning in ["002.0s  首次受损：货物 #1 · 碰撞 · 3.50 HP。","002.0s  部分货物损毁，委托失败。","002.0s  未知结构警报。"]:
  flight.events=[success,warning];hud.update_flight(flight)
  check(not hud.flight_labels.events.text.contains("模块已分裂"),"new important or unknown event not diluted "+warning)
 flight.events=[success,tiny];flight.elapsed=9.0;hud.update_flight(flight)
 check(hud.flight_labels.events.text.is_empty() and not hud.content.get_node("FlightEventReceipt").visible,"receipt naturally expires without permanent text")
 hud.free();print("SPLITTER_FEEDBACK_UI_DEV13 passed=",passed," failed=",failed," native_gui=NOT_RUN");quit(1 if failed else 0)
