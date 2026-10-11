extends SceneTree
## Presentation-only copy, using the registered real meteor route and HUD.
const HUD=preload("res://scripts/game_hud.gd")
const Meteor=preload("res://scripts/orbital_meteor_catalog.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for unused in 4:await process_frame
func data(distance:float) -> Dictionary:
 return {"distance":distance,"total_distance":740.0,"speed":18.0,"elapsed":30.0,"integrity":1.0,"flight_phase":"approach","next_gate_index":-1,"next_gate_time":-1.0,"altitude":150.0,"target_altitude":150.0,"energy_remaining":3000.0,"battery_capacity":6000.0}
func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 var route:Dictionary=Meteor.author({"id":1,"weight":1.5,"reward":220,"rep":2},42).route.duplicate(true)
 route.destination_name="晨星轨道站";route.name="城市升空与轨道流星 · 晨星轨道站"
 var before:PackedByteArray=var_to_bytes(route)
 var hud=HUD.new();root.add_child(hud)
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  var frame:=Rect2(0,40,1280,720) if extent.x==1280 else Rect2(Vector2.ZERO,Vector2(extent))
  hud.set_art_frame(frame)
  hud.render({"mode":"flight","trial":true,"control_version":"pilot-v3","activeorder":route,"flight":data(543.0),"settings":{"reduced_motion":true}});await settle()
  check(hud._corridor_mode(),"real meteor route selects compact corridor HUD "+str(extent))
  check(hud.flight_labels.destination.text==route.destination_name,"actual destination replaces long contract title "+str(extent))
  check(hud.flight_labels.destination.get_minimum_size().x<=hud.flight_labels.destination.size.x+.1,"destination label fits native width "+str(extent))
  check(hud.flight_labels.status.text.ends_with("轨道巡航") and hud.flight_labels.gate.text.is_empty(),"197 m remaining is orbit cruise, not receipt approach "+str(extent))
  hud.update_flight(data(680.0));check(hud.flight_labels.status.text.ends_with("接近收件台") and hud.flight_labels.gate.text=="接近收件区","near receipt cue begins at actual bounded distance "+str(extent))
  hud.update_flight(data(679.9));check(hud.flight_labels.status.text.ends_with("轨道巡航") and hud.flight_labels.gate.text.is_empty(),"presentation proximity threshold is deterministic "+str(extent))
  var paused:=data(543.0);paused.paused=true;hud.update_flight(paused)
  check(hud.flight_labels.status.text=="已暂停" and hud.flight_labels.gate_detail.text=="已暂停","pause survives quiet orbit cue "+str(extent))
  var charging:=data(543.0);charging.charging=true;charging.phase="发射台蓄能中";hud.update_flight(charging)
  check(hud.flight_labels.status.text=="发射台蓄能中" and not hud._ascent_cue.visible,"launch copy and cue remain phase-owned "+str(extent))
  check(var_to_bytes(route)==before,"HUD never mutates saved route "+str(extent))
 check(not hud._ordinary_receiver_near({}) and not hud._ordinary_receiver_near({"distance":NAN,"total_distance":740.0}),"missing/nonfinite distance cannot claim near receiver")
 check(not hud._ordinary_receiver_near(data(850.0)),"far overshoot is not falsely near receiver")
 hud.queue_free();await settle()
 print("FLIGHT_DESTINATION_COPY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
