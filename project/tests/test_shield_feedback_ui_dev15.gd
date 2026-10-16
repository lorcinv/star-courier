extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
const Receipt=preload("res://scripts/flight_receipt.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var hud=HUD.new();root.add_child(hud);await process_frame
 var flight:Dictionary={"elapsed":1.0,"control_version":"pilot-free-v2","free_flight":true,"speed":16.0,"cargo_y":-4.0,"energy_remaining":4000.0,"energy_capacity":6000.0,"energy_fraction":.666,"flight_status":"running","events":[],"impact_absorbed":0.0,"impact_shield_energy":0.0,"destination_navigation":{"status":"running","distance_m":140.0}}
 for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)))
  hud.render({"mode":"hub"})
  flight.elapsed=1.0;flight.impact_absorbed=0.0;flight.impact_shield_energy=0.0;flight.events=[]
  hud.render({"mode":"flight","control_version":"pilot-free-v2","activeorder":{"control_version":"pilot-free-v2","contract_id":"shield-test","background_ground_y_m":0.0},"flight":flight,"settings":{"reduced_motion":true}})
  for i in 3:await process_frame
  check(hud.flight_labels.events.text.is_empty(),"no permanent shield row at rest "+str(extent))
  flight.elapsed=2.0;flight.impact_absorbed=24.0;flight.impact_shield_energy=36.0;flight.events=["002.0000s  首次受损：装甲板 #5 · 碰撞 · 55.70 HP。"]
  var before:Dictionary=flight.duplicate(true);hud.update_flight(flight)
  for i in 3:await process_frame
  hud.update_flight(flight)
  check(hud.flight_labels.events.text=="发生碰撞，零件受损。 · 护盾已抵消 24.0 HP","damage retained first, shield suffix "+str(extent))
  check(hud.content.get_node("FlightEventReceipt").visible,"same existing event panel "+str(extent))
  check(hud.flight_labels.events.get_theme_font("font").get_string_size(hud.flight_labels.events.text,HORIZONTAL_ALIGNMENT_LEFT,-1,hud.flight_labels.events.get_theme_font_size("font_size")).x<=hud.flight_labels.events.size.x,"combined receipt fits "+str(extent))
  check(flight==before,"observation never edits snapshot "+str(extent))
  flight.paused=true;hud.update_flight(flight);check(hud.flight_labels.events.text.contains("护盾已抵消"),"paused sim clock retains paid cue")
  hud.render({"mode":"flight","control_version":"pilot-free-v2","activeorder":{"control_version":"pilot-free-v2","contract_id":"shield-test","background_ground_y_m":0.0},"settings":{"reduced_motion":true}})
  # Rebuilt Labels have no usable width until the real container layout pass.
  for i in 3:await process_frame
  hud.update_flight(flight)
  check(hud.flight_labels.events.text.contains("护盾已抵消"),"same-flight rebuild retains cue without replay")
  flight.paused=false;flight.elapsed=8.01;hud.update_flight(flight)
  check(hud.flight_labels.events.text.is_empty() and not hud.content.get_node("FlightEventReceipt").visible,"expires without persistent panel")
 flight.elapsed=9;flight.impact_absorbed=28.0;flight.impact_shield_energy=42.0;flight.events=["009.0s  部分货物损毁，委托失败。"]
 hud.update_flight(flight);check(hud.flight_labels.events.text.begins_with("货物损毁，配送失败。"),"major damage remains first even before terminal snapshot")
 flight.flight_status="failed";hud.update_flight(flight)
 check(not hud.flight_labels.events.text.contains("护盾") and hud.flight_labels.events.text.contains("损毁"),"terminal failure not diluted by protection success")
 check(Receipt.shield_totals(flight)=={"impact_absorbed":28.0,"impact_shield_energy":42.0},"terminal actual totals still available for stored report")
 hud.free();print("SHIELD_FEEDBACK_UI_DEV15 passed=",passed," failed=",failed," native_gui=NOT_RUN");quit(1 if failed else 0)
