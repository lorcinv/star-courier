extends SceneTree
## Native Button.pressed signal injection, not physical/native OS reproduction.
class Controller extends "res://scripts/main.gd":
 var saves:int=0
 var exits:int=0
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func save_game() -> bool:
  saves+=1;_last_save_error="测试保存失败";return false
 func _finish_quit(_code:int) -> void:exits+=1
 func notify(_message:String) -> void:pass
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 await process_frame;await process_frame
func run() -> void:
 root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
 var app=Controller.new();root.add_child(app);app._request_save_and_quit();await settle()
 app._quit_prompt.get_ok_button().pressed.emit();await settle()
 check(app.closing and not app._quit_prompt_pending and app._quit_failure_pending and app._quit_dialog.visible and app.saves==1 and app.exits==0,"failed confirmed save hands ownership from initial prompt to failure dialog")
 app._quit_prompt.get_cancel_button().pressed.emit();await settle()
 check(app.closing and app._quit_failure_pending and app._quit_dialog.visible and app.saves==1 and app.exits==0,"late hidden initial-prompt Cancel cannot dismiss active save-failure dialog")
 app._quit_dialog.get_cancel_button().pressed.emit();await settle()
 check(not app.closing and not app._quit_failure_pending and not app._quit_dialog.visible and app.saves==1 and app.exits==0,"current failure-dialog Cancel returns to game without another save or exit")
 app.free()
 print("DEV03_EXIT_STALE_CANCEL_R2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
