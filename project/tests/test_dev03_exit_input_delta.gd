extends SceneTree
const Router=preload("res://scripts/courier_input.gd")
class Controller extends "res://scripts/main.gd":
 var saves:int=0
 var checkpoints:int=0
 var exits:int=0
 var notices:Array=[]
 var allow_save:bool=true
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func save_game() -> bool:
  saves+=1;_last_save_error="测试写入失败"
  if allow_save:return economy.save_state([],[],settings)
  return false
 func _checkpoint_flight() -> void:checkpoints+=1
 func _finish_quit(_code:int) -> void:exits+=1
 func notify(message:String) -> void:notices.append(message)
class RouterProbe extends "res://scripts/courier_input.gd":
 func synchronize() -> void:pass
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func joy(dialog:Window,button:int) -> void:
 var event:=InputEventJoypadButton.new();event.button_index=button;event.pressed=true
 dialog.push_input(event,true)
 event=InputEventJoypadButton.new();event.button_index=button;event.pressed=false
 dialog.push_input(event,true)
func settle() -> void:
 await process_frame;await process_frame
func bytes() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func app_new():
 var app=Controller.new();root.add_child(app);app.economy.ensure_contracts();return app
func run() -> void:
 root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
 var app=app_new();app._request_save_and_quit();await settle()
 app._quit_prompt.get_cancel_button().pressed.emit();await settle()
 check(not app.closing and not app._quit_prompt.visible and app.saves==0,"real Cancel button pressed path hides native prompt without saving")
 app._request_save_and_quit();await settle();app._quit_prompt.get_ok_button().pressed.emit();await settle()
 check(app.saves==1 and app.exits==1 and not app._quit_prompt.visible,"real OK button pressed path invokes native confirmed exactly once")
 app._quit_prompt.get_ok_button().pressed.emit();app._quit_prompt.get_cancel_button().pressed.emit();await settle()
 check(app.saves==1 and app.exits==1 and app.closing,"stale duplicate native OK/Cancel events cannot repeat save or undo exit")
 app.free()
 app=app_new();app._request_save_and_quit();await settle();check(app._quit_prompt.gui_get_focus_owner()==app._quit_prompt.get_cancel_button(),"native prompt defaults to safe Cancel focus");joy(app._quit_prompt,JOY_BUTTON_A);await settle()
 check(not app.closing and app.saves==0 and not app._quit_prompt.visible,"Window-pushed gamepad A activates focused Cancel through native button")
 app._request_save_and_quit();await settle();app._quit_prompt.get_ok_button().grab_focus();joy(app._quit_prompt,JOY_BUTTON_A);await settle()
 check(app.saves==1 and app.exits==1,"Window-pushed gamepad A activates focused OK exactly once")
 app.free()
 app=app_new();app._request_save_and_quit();await settle();joy(app._quit_prompt,JOY_BUTTON_B);await settle()
 check(not app.closing and app.saves==0,"Window-pushed B uses cancel without a save")
 app.page="flight";app.paused=true;app._paused_before_modal=false;app._flight_modal_was_open=true
 app._request_save_and_quit();await settle();app._quit_prompt.get_cancel_button().pressed.emit();await settle()
 check(app.paused and not app._paused_before_modal and app.saves==0,"initial cancel preserves paused and independent modal resume target")
 app._set_paused(app._paused_before_modal);check(not app.paused,"closing settings after cancelled exit resumes originally running flight")
 app.free()
 app=app_new();check(app.economy.save_state([],[],app.settings),"seed primary");app.economy.credits+=1;check(app.economy.save_state([],[],app.settings),"seed distinct backup")
 var original:Array=bytes();app.page="flight"
 var router=RouterProbe.new();router.host=app;router.active_device=7;router._buttons={"b:7:0":true};router._axes={"a:7:0":1.0};app.courier_input=router;root.add_child(router)
 app._request_save_and_quit();await settle();router._joy_connection_changed(7,false)
 check(router.active_device==-1 and router._buttons.is_empty() and router._axes.is_empty(),"actual disconnect callback clears device and held input during close hold")
 check(app.saves==0 and app.checkpoints==0 and bytes()==original,"disconnect during exit prompt cannot checkpoint/save/rotate either durable slot")
 app._quit_prompt.get_cancel_button().pressed.emit();await settle()
 check(app.saves==0 and app.checkpoints==0 and bytes()==original and app.paused,"cancel after disconnect remains paused and keeps both exact files")
 router.free();app.courier_input=null;app.free()
 app=app_new();app.allow_save=false;app._request_save_and_quit();await settle();app._quit_prompt.get_ok_button().pressed.emit();await settle()
 check(app.saves==1 and app.exits==0 and app._quit_dialog.visible,"native OK failure enters retry dialog without exit")
 app.allow_save=true;app._quit_dialog.get_ok_button().grab_focus();joy(app._quit_dialog,JOY_BUTTON_A);await settle()
 check(app.saves==2 and app.exits==1 and not app._quit_dialog.visible,"native gamepad retry commits once and exits")
 app._quit_dialog.get_ok_button().pressed.emit();app._quit_dialog.get_cancel_button().pressed.emit();await settle()
 check(app.saves==2 and app.exits==1 and app.closing,"stale retry/cancel after success cannot resave or resume gameplay")
 app.free()
 print("DEV03_EXIT_INPUT_DELTA passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
