extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
class FlightStub extends RefCounted:
 var status:String="running"
 var telemetry:Dictionary={"pilot_axis_q":0,"pilot_boost":false,"pilot_active":false}
 func set_pilot_input(_axis:int,_boost:bool,_active:bool) -> void:pass
class Controller extends "res://scripts/main.gd":
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 await process_frame;await process_frame
func key(code:int,pressed:bool) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
 Input.parse_input_event(event);await settle()
func tap(code:int) -> void:
 await key(code,true);await key(code,false)
func data(app,protocol:String) -> Dictionary:
 return {"mode":"flight","control_version":protocol,"activeorder":{"control_version":protocol,"distance":100.0},"save_exit_available":app._flight_save_exit_available(),"settings":{"reduced_motion":true},"flight":{"paused":app.paused,"save_exit_available":app._flight_save_exit_available(),"speed":3.0,"cargo_y":-8.0,"integrity":1.0,"energy_fraction":.8,"energy_remaining":80.0,"energy_capacity":100.0}}
func run() -> void:
 root.gui_embed_subwindows=true
 for protocol in ["pilot-free-v1","pilot-v1"]:
  var app=Controller.new();root.add_child(app);app.page="flight";app.flight_order={"control_version":protocol};app.sim=FlightStub.new()
  app.hud=HUD.new();app.add_child(app.hud);app.hud.action_requested.connect(app._action)
  for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
   root.size=extent;app.hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));app.paused=false;app.hud.render(data(app,protocol));await settle()
   await tap(KEY_P)
   var pause_button:Button=app.hud._pause_button.get_ref()
   check(app.paused and pause_button.has_focus(),protocol+" physical P pauses with Continue focus "+str(extent))
   await tap(KEY_P)
   check(not app.paused and root.gui_get_focus_owner()==null,protocol+" physical P resumes with no flight HUD focus "+str(extent))
   await key(KEY_SPACE,true)
   check(not app.paused and app.pilot_keys.has(KEY_SPACE),protocol+" Space reaches pilot active input rather than focused Pause "+str(extent))
   await key(KEY_SPACE,false)
   check(not app.paused and not app.pilot_keys.has(KEY_SPACE),protocol+" Space release remains a flight input "+str(extent))
   app._set_paused(true);app.hud.settings_open=true;app.hud.render(data(app,protocol));await settle()
   var modal_owner:Control=root.gui_get_focus_owner()
   var exit_button:Button=app.hud.content.get_node("FlightSaveAndExit")
   for tick in 3:app.hud.update_flight(data(app,protocol).flight)
   check(is_instance_valid(modal_owner) and root.gui_get_focus_owner()==modal_owner,protocol+" telemetry keeps settings focus "+str(extent))
   check(exit_button.disabled and exit_button.focus_mode==Control.FOCUS_NONE,protocol+" telemetry cannot reactivate modal background footer "+str(extent))
   app.hud.settings_open=false;app.hud.render(data(app,protocol));await settle();app._set_paused(false);await settle()
  app.free();await settle()
 print("DEV03_FLIGHT_FOCUS_R2 passed=%d failed=%d synthetic_key_events=true physical_keyboard=false"%[passed,failed]);quit(1 if failed else 0)
