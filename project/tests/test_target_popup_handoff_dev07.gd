extends SceneTree
## Actual Main/CourierInput/HUD; all gesture events enter root Window.push_input.
## Synthetic embedded-window routing; epoch/closed-stale are explicit lifecycle probes.
## Native mouse and application focus are separate later gates.
const Main=preload("res://scenes/main.tscn")
class CountedMain extends "res://scripts/main.gd":
 var qa_saves:int=0
 var qa_actions:Array=[]
 func save_game() -> bool:
  qa_saves+=1
  return super.save_game()
 func _action(action:String,payload:Variant=null) -> void:
  qa_actions.append([action,payload])
  super._action(action,payload)
var game
var choice:OptionButton
var popup:PopupMenu
var scenario:String
var stage:String="fixture"
var passed:int=0
var failed:int=0
var trial_signals:Dictionary={"down":0,"up":0,"pressed":0}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",scenario," ",label)
 else:failed+=1;push_error("FAIL "+scenario+" "+label)
func settle(n:int=3) -> void:
 for unused in n:await process_frame
func snapshot(label:String,event:InputEvent=null) -> void:
 var row:Dictionary={"case":scenario,"stage":stage,"label":label,"embed":root.gui_embed_subwindows,"root_focus":root.has_focus()}
 if is_instance_valid(game) and is_instance_valid(game.courier_input):
  row.merge({"page":game.page,"focused":game.courier_input.focused,"context":game.courier_input.context,"mouse":game.courier_input._mouse.duplicate(),"blocked":game.courier_input._blocked.duplicate(),"generation":game.hud._render_generation,"saves":game.qa_saves,"undos":game.undo_history.size(),"actions":game.qa_actions.duplicate(true),"target":game.selected_part().get("target",-999)})
 if is_instance_valid(popup):row.merge({"popup_id":popup.get_instance_id(),"popup_visible":popup.visible,"popup_tree":popup.is_inside_tree(),"popup_embedded":popup.is_embedded()})
 if event!=null:
  row["event"]=event.as_text()
  if event is InputEventMouseButton or event is InputEventKey:row["pressed"]=event.pressed
 print("HANDOFF_TRACE ",JSON.stringify(row))
func dispatch(event:InputEvent) -> void:
 snapshot("before push",event);root.push_input(event);snapshot("after push",event);await settle()
func mouse(at:Vector2,down:bool,which:int=MOUSE_BUTTON_LEFT,mask:int=-1) -> void:
 var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=which;event.pressed=down
 event.button_mask=(1<<(which-1) if down else 0) if mask<0 else mask
 await dispatch(event)
func motion(at:Vector2,mask:int=0) -> void:
 var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.button_mask=mask
 await dispatch(event)
func key(code:int,down:bool) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;await dispatch(event)
func joy(button:int,down:bool) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=button;event.pressed=down;await dispatch(event)
func axis(value:float) -> void:
 var event:=InputEventJoypadMotion.new();event.device=0;event.axis=JOY_AXIS_RIGHT_X;event.axis_value=value;await dispatch(event)
func click(at:Vector2) -> void:await motion(at);await mouse(at,true);await mouse(at,false)
func control(id:String) -> Control:
 for node in game.hud.content.find_children("*","Control",true,false):
  if str(node.get_meta("view_key",""))==id:return node
 return null
func bind_popup() -> void:
 choice=game.hud.content.find_child("PartTargetChoice",true,false);popup=choice.get_popup()
 popup.about_to_popup.connect(func():snapshot("popup about_to_popup"))
 popup.popup_hide.connect(func():snapshot("popup popup_hide"))
 popup.focus_entered.connect(func():snapshot("popup focus_entered"))
 popup.focus_exited.connect(func():snapshot("popup focus_exited"))
 popup.tree_exiting.connect(func():snapshot("popup tree_exiting"))
 popup.tree_exited.connect(func():snapshot("popup tree_exited"))
 popup.window_input.connect(func(event):snapshot("popup window_input",event))
 choice.item_selected.connect(func(index):snapshot("choice item_selected "+str(index)))
func item_position(index:int) -> Vector2:
 var panel:StyleBox=popup.get_theme_stylebox("panel")
 var row_height:float=(popup.size.y-panel.get_minimum_size().y)/popup.item_count
 return Vector2(popup.position)+Vector2(popup.size.x/2.0,panel.get_content_margin(SIDE_TOP)+(index+.5)*row_height)
func open_popup(drag:bool=false) -> void:
 bind_popup();stage="open"
 var at:Vector2=choice.get_global_rect().get_center()
 await motion(at);await mouse(at,true)
 check(popup.visible and popup.is_inside_tree() and popup.is_embedded(),"actual embedded target PopupMenu opens from root mouse press")
 check(game.courier_input._blocked.has("m:1"),"opening focus transfer quarantines held opening press")
 if not drag:
  await mouse(at,false)
  check(not game.courier_input._blocked.has("m:1"),"actual opening release observed by popup releases only its token")
func select_item(index:int,drag:bool=false) -> void:
 stage="select"
 var at:Vector2=item_position(index)
 if drag:await motion(at,MOUSE_BUTTON_MASK_LEFT);await mouse(at,false)
 else:await click(at)
 await settle()
func actions_named(name:String) -> int:
 var count:int=0
 for action in game.qa_actions:
  if action[0]==name:count+=1
 return count
func persisted_target() -> int:
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 for part in saved.design:
  if int(part.id)==8:return int(part.target)
 return -999
func trial_once() -> void:
 stage="trial"
 var trial:BaseButton=control("action:trial:null")
 check(trial!=null and not trial.disabled,"real free-trial action is enabled")
 if trial==null:return
 trial.button_down.connect(func():trial_signals.down+=1)
 trial.button_up.connect(func():trial_signals.up+=1)
 trial.pressed.connect(func():trial_signals.pressed+=1)
 var old_count:int=actions_named("trial")
 await click(trial.get_global_rect().get_center())
 check(game.page=="flight" and actions_named("trial")==old_count+1,"one fresh complete trial click launches exactly once")
 check(trial_signals=={"down":1,"up":1,"pressed":1},"trial receives one native button down/up/pressed sequence")
func run() -> void:
 scenario=OS.get_environment("COURIER_POPUP_CASE")
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/courier-popup-") or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Fresh isolated /tmp/courier-popup-* XDG_DATA_HOME required");quit(2);return
 DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
 var f:=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_string(FileAccess.get_file_as_string(OS.get_environment("COURIER_POPUP_FIXTURE")));f.close()
 root.size=Vector2i(1280,812);root.gui_embed_subwindows=true
 root.focus_entered.connect(func():snapshot("root focus_entered"))
 root.focus_exited.connect(func():snapshot("root focus_exited"))
 game=Main.instantiate();game.set_script(CountedMain);game.entry_settings_overrides={"reduced_motion":true,"fullscreen":false};root.add_child(game)
 game.set_process(false);game.world.set_process(false);await settle(8)
 for unused in 360:game.world._process(1.0/60.0)
 game.navigate("workshop");game.selected_id=8;game.render();game.workshop_input.fit();game.courier_input.tick(0);await settle(8)
 var saves:int=game.qa_saves;var undos:int=game.undo_history.size();var original:PackedByteArray=var_to_bytes(game.design)
 var disk:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 check(game.page=="workshop" and game.selected_part().type=="coupler" and int(game.selected_part().target)==2,"original native A fixture loaded through production Main")
 if scenario=="control":await trial_once()
 elif scenario in ["click","drag","same","undo","repeat"]:
  await open_popup(scenario=="drag")
  await select_item(choice.selected if scenario=="same" else choice.item_count-1,scenario=="drag")
  var changed:bool=scenario!="same"
  check(int(game.selected_part().target)==(7 if changed else 2),"real target selection keeps expected target")
  check(actions_named("set_input")==int(changed) and game.qa_saves==saves+int(changed) and game.undo_history.size()==undos+int(changed),"selection owns exactly its one action/save/undo, same target owns zero")
  check(persisted_target()==(7 if changed else 2),"real primary save carries exact target")
  check(not game.courier_input._blocked.has("m:1") and not game.courier_input._mouse.has("m:1"),"selecting release leaves no orphaned left-button state")
  if scenario=="undo":
   stage="undo";var undo:Control=control("action:undo:null");check(undo!=null,"real undo action available")
   if undo!=null:await click(undo.get_global_rect().get_center())
   check(var_to_bytes(game.design)==original and persisted_target()==2 and game.undo_history.size()==undos,"one actual undo exactly restores pre-selection blueprint and disk")
   check(game.qa_saves==saves+2 and actions_named("undo")==1,"undo adds exactly its own save")
  if scenario=="repeat":
   await open_popup();await select_item(1)
   check(int(game.selected_part().target)==2 and actions_named("set_input")==2 and game.qa_saves==saves+2 and game.undo_history.size()==undos+2,"second reopened popup commits once without stale state")
  await trial_once()
 elif scenario in ["escape","outside","drag_escape","rebuild","resize","held_rebuild","held_resize"]:
  var held:bool=scenario in ["drag_escape","held_rebuild","held_resize"]
  await open_popup(held);stage=scenario
  if scenario in ["escape","drag_escape"]:await key(KEY_ESCAPE,true);await key(KEY_ESCAPE,false)
  elif scenario=="outside":await click(Vector2(4,4))
  elif scenario in ["rebuild","held_rebuild"]:game.render();await settle()
  else:root.size=Vector2i(1440,900);await settle(8)
  check(not is_instance_valid(popup) or not popup.visible,"dismissal or rebuild closes the actual popup")
  check(var_to_bytes(game.design)==original and game.qa_saves==saves and game.undo_history.size()==undos and FileAccess.get_file_as_bytes("user://savegame.json")==disk,"dismissal or rebuild is model/save/undo neutral")
  if held:
   check(game.courier_input._blocked.has("m:1"),"dismissal or rebuild cannot clear a still-held opening mouse")
   await mouse(Vector2(4,4),false)
  check(not game.courier_input._blocked.has("m:1"),"only genuine release leaves next click eligible")
  await trial_once()
 elif scenario in ["held","release_matrix"]:
  await key(KEY_F8,true);await joy(JOY_BUTTON_GUIDE,true);await axis(.6)
  for button in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:await mouse(Vector2(4,4),true,button)
  await open_popup(true)
  if scenario=="release_matrix":
   for button in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:
    await mouse(Vector2(popup.position)+Vector2(8,8),false,button,MOUSE_BUTTON_MASK_LEFT)
    check(not game.courier_input._blocked.has("m:%d"%button) and game.courier_input._blocked.has("m:1") and popup.visible,"popup releases only actual button "+str(button)+" and retains held opener")
  await select_item(choice.item_count-1,true)
  for token in (["k:%d"%KEY_F8,"b:0:%d"%JOY_BUTTON_GUIDE,"a:0:%d"%JOY_AXIS_RIGHT_X,"m:2","m:3","m:8","m:9"] if scenario=="held" else ["k:%d"%KEY_F8,"b:0:%d"%JOY_BUTTON_GUIDE,"a:0:%d"%JOY_AXIS_RIGHT_X]):check(game.courier_input._blocked.has(token),"popup left release preserves other held "+token)
  check(not game.courier_input._blocked.has("m:1"),"popup releases only left token")
  await trial_once()
 elif scenario=="app_focus":
  await mouse(Vector2(4,4),true);game._on_focus_exited();game._on_focus_entered();await settle()
  check(game.courier_input._blocked.has("m:1"),"application focus boundary retains held mouse barrier")
  var trial:Control=control("action:trial:null");await mouse(trial.get_global_rect().get_center(),true)
  check(game.page=="workshop" and actions_named("trial")==0 and game.courier_input._blocked.has("m:1"),"duplicate held press after application focus return is blocked")
  await mouse(trial.get_global_rect().get_center(),false);await trial_once()
 elif scenario in ["epoch_reopen","closed_stale"]:
  await open_popup()
  var same_popup:PopupMenu=popup
  var same_generation:int=game.hud._render_generation
  var opening_at:Vector2=choice.get_global_rect().get_center()
  stage="synthetic_lifecycle_hide_without_settle"
  # Escape closure is deferred by the engine and is covered separately above.
  # Hide explicitly; probe stale retirement after engine focus cleanup settles.
  var before_epoch:int=game.hud._target_popup_epoch
  var observed_releases:Array=[]
  game.hud.target_popup_mouse_released.connect(func(button:int):observed_releases.append(button))
  same_popup.hide()
  check(not popup.visible and popup.is_inside_tree() and game.hud._render_generation==same_generation,"explicit lifecycle hide keeps same-generation popup alive")
  if scenario=="epoch_reopen":
   await settle() # Let engine-owned deferred focus cleanup finish.
   stage="synthetic_stale_epoch_after_real_reopen"
   await mouse(opening_at,true)
   check(popup==same_popup and popup.visible and game.hud._target_popup_epoch==before_epoch+1 and game.courier_input._blocked.has("m:1"),"fresh real press reopens exact popup with a new epoch and held token")
   # Explicit stale-callback guard probe, not a claim about native event timing.
   game.hud._retire_target_popup.call_deferred(popup.get_instance_id(),same_generation,before_epoch)
   await settle()
   check(popup.visible and game.hud._target_popup_id==popup.get_instance_id() and game.hud._target_popup_epoch==before_epoch+1 and game.courier_input._blocked.has("m:1"),"late old-epoch retirement cannot retire reopened live popup or release held token")
   await mouse(opening_at,false)
   check(popup==same_popup and popup.visible and observed_releases==[MOUSE_BUTTON_LEFT] and not game.courier_input._blocked.has("m:1") and not game.courier_input._mouse.has("m:1"),"reopened live popup forwards exactly its genuine opening release")
   await key(KEY_ESCAPE,true);await key(KEY_ESCAPE,false)
  else:
   await settle()
   check(game.hud._render_generation==same_generation and game.hud._target_popup_id==0,"closed popup is retired without any render-generation change")
   await mouse(Vector2(4,4),true);game._on_focus_exited();game._on_focus_entered()
   check(game.courier_input._blocked.has("m:1"),"new unrelated held mouse barrier exists after retirement")
   var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
   same_popup.window_input.emit(release)
   check(game.courier_input._blocked.has("m:1") and game.hud._render_generation==same_generation,"closed same-generation popup signal cannot release a newer barrier")
   await mouse(Vector2(4,4),false)
  check(game.page=="workshop" and game.qa_saves==saves and game.undo_history.size()==undos and var_to_bytes(game.design)==original,"lifecycle probes leave workshop, blueprint save and undo unchanged")
  await trial_once()
 elif scenario in ["cancel_pending","stale"]:
  await open_popup(true)
  var old_choice:OptionButton=choice;var old_popup:PopupMenu=popup
  var at:Vector2=item_position(choice.item_count-1)
  await motion(at,MOUSE_BUTTON_MASK_LEFT)
  if scenario=="cancel_pending":
   var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false
   root.push_input(event)
   check(int(game.selected_part().target)==7 and game.qa_saves==saves+1,"selection commits before its deferred-only presentation")
   game.navigate("hub");var gen:int=game.hud._render_generation;await settle()
   check(game.page=="hub" and game.hud.mode=="hub" and game.hud._render_generation==gen,"new navigation cancels stale target presentation rebuild")
  else:
   # Hold removed old nodes until after synthetic stale-signal probes. Normal
   # gestures above still use real routing; these explicitly test guard logic.
   game.render()
   var before:Dictionary=game.courier_input._blocked.duplicate()
   old_choice.item_selected.emit(old_choice.item_count-1)
   var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
   old_popup.window_input.emit(release)
   check(game.courier_input._blocked==before and game.qa_saves==saves and game.undo_history.size()==undos and int(game.selected_part().target)==2,"stale-generation popup cannot release barriers or commit a target")
   await settle();await mouse(Vector2(4,4),false);await trial_once()
 else:check(false,"known scenario")
 snapshot("final");stage="teardown";game.queue_free();finish_case.call_deferred()

func finish_case() -> void:
 # Quit only after the run coroutine and its local popup/Callable refs return.
 await settle(6)
 print("TARGET_POPUP_HANDOFF case=%s passed=%d failed=%d native_mouse=false native_app_focus=false retained_user_dir=%s"%[scenario,passed,failed,OS.get_user_data_dir()]);quit(1 if failed else 0)
