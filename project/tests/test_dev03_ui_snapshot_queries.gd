extends SceneTree
## Presentation/query regression only. No save files, physics or owner steps.
## Headless timings, if collected separately, are not Windows FPS acceptance.
const World=preload("res://scripts/world_view_2d.gd")
const Main=preload("res://scripts/main.gd")
const HUD=preload("res://scripts/game_hud.gd")
var passed:int=0
var failed:int=0

class SnapshotTrapWorld extends "res://scripts/world_view_2d.gd":
 var diagnostic_queries:int=0
 func loading_snapshot() -> Dictionary:
  diagnostic_queries+=1
  return {"order_id":active_id,"phase":_parcel_phase,"loading":is_loading()}

class OverlayProbe extends Node:
 var last_state:Dictionary={}
 var closes:int=0
 func update_state(value:Dictionary) -> void:last_state=value.duplicate(true)
 func close() -> void:closes+=1

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func _loading_projection() -> void:
 var world=World.new()
 # Deliberately never enter the scene tree or create actors. This query must
 # not depend on expensive renderer/debug state to produce its three scalars.
 for id in ["","order-A"]:
  for state in ["empty","counter","loading","loaded"]:
   for requested in [false,true]:
    world.active_id=id;world.parcel_state=state;world._loading_requested=requested
    world._parcel_phase="robot_carry"
    var before:PackedByteArray=var_to_bytes([world.active_id,world.parcel_state,world._loading_requested,world._parcel_phase])
    var projected:Dictionary=world.loading_ui_state()
    var previous_fields:Dictionary={"order_id":id,"phase":"robot_carry","loading":world.is_loading()}
    check(projected==previous_fields,"loading projection equals previous overlay fields: %s/%s/%s"%[id,state,str(requested)])
    projected.phase="caller-mutated"
    check(var_to_bytes([world.active_id,world.parcel_state,world._loading_requested,world._parcel_phase])==before,"loading query is detached and read only")
 world.free()

func _main_overlay_route() -> void:
 var game=Main.new()
 var world=SnapshotTrapWorld.new()
 var overlay=OverlayProbe.new()
 var hud=CanvasLayer.new()
 game.world=world;game.loading_overlay=overlay;game.hud=hud
 world.active_id="order-A";world._loading_requested=true;world.parcel_state="loading";world._parcel_phase="robot_pickup"
 game._sync_loading_scene_ui()
 check(overlay.last_state==world.loading_ui_state() and not hud.visible,"Main sends current scalar loading state and hides HUD")
 world._parcel_phase="clerk_confirm";game._sync_loading_scene_ui()
 check(overlay.last_state.phase=="clerk_confirm","phase changes reach existing overlay immediately")
 check(world.diagnostic_queries==0,"per-frame Main overlay route never invokes full actor diagnostic snapshot")
 world.parcel_state="loaded";game._sync_loading_scene_ui()
 check(overlay.closes==1 and hud.visible,"completion closes overlay and restores HUD")
 game.world=null;game.loading_overlay=null;game.hud=null
 game.free();world.free();overlay.free();hud.free()

func _telemetry() -> Dictionary:
 return {"elapsed":2.0,"distance":5.0,"total_distance":260.0,"energy_remaining":800.0,"energy_capacity":1000.0,"energy_fraction":.8,
  "integrity":1.0,"paused":false,"charging":false,"events":[],"flight_status":"running","arrival_state":"en_route",
  "destination_navigation":{"status":"running","distance_m":255.0},"detachment_probe":{"values":[1,2,3]}}

func _hud_snapshot() -> void:
 var hud=HUD.new();root.add_child(hud)
 var layout:Dictionary={"mode":"flight","trial":true,"control_version":"pilot-free-v1","activeorder":{"control_version":"pilot-free-v1","destination_name":"收件台","distance":260.0},"settings":{"reduced_motion":true},"flight":_telemetry()}
 hud.render(layout)
 var data:Dictionary=_telemetry()
 var before:PackedByteArray=var_to_bytes(data)
 var generation:int=hud._render_generation
 hud.update_flight(data)
 check(var_to_bytes(data)==before and hud.state.flight==data,"free-flight update keeps exact detached telemetry without mutating caller")
 check(hud._render_generation==generation,"free-flight frame updates do not rebuild the HUD")
 data.detachment_probe.values[0]=99
 check(hud.state.flight.detachment_probe.values[0]==1,"nested caller mutations cannot alter retained free-flight snapshot")
 hud.state.flight.detachment_probe.values[1]=88
 check(data.detachment_probe.values[1]==2,"retained snapshot mutations cannot alter caller telemetry")
 var direct:Dictionary=_telemetry();hud._update_free_flight(direct);direct.detachment_probe.values[2]=77
 check(hud.state.flight.detachment_probe.values[2]==3,"direct free-flight layout path still owns its detached snapshot")
 # Non-free modes still own their one copy in update_flight().
 layout.control_version="pilot-v1";layout.activeorder.control_version="pilot-v1";hud.render(layout)
 var legacy:Dictionary=_telemetry();hud.update_flight(legacy);legacy.detachment_probe.values[0]=44
 check(hud.state.flight.detachment_probe.values[0]==1,"legacy flight snapshot remains detached")
 hud.queue_free()
 await process_frame

func run() -> void:
 _loading_projection();_main_overlay_route();await _hud_snapshot()
 print("DEV03_UI_SNAPSHOT_QUERIES passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)
