extends SceneTree
## Production Main, CourierInput, PixelStage, HUD and WorkshopInput. Every mouse,
## keyboard and controller event enters Window.push_input, including GUI release.
## Synthetic viewport events only: no physical gamepad, native mouse or FPS claim.
const Main=preload("res://scenes/main.tscn")
class CountedMain extends "res://scripts/main.gd":
 var qa_saves:int=0
 func save_game() -> bool:
  qa_saves+=1
  return super.save_game()
var game
var owner
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=3) -> void:
 for unused in n:await process_frame
func dispatch(event:InputEvent) -> void:
 root.push_input(event);await settle()
func mouse(at:Vector2,down:bool,which:int=MOUSE_BUTTON_LEFT,mask:int=-1) -> void:
 var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=which;event.pressed=down
 event.button_mask=(1<<(which-1) if down else 0) if mask<0 else mask
 await dispatch(event)
func motion(at:Vector2,mask:int=0) -> void:
 var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.button_mask=mask
 await dispatch(event)
func joy(which:int,down:bool,device:int=0) -> void:
 var event:=InputEventJoypadButton.new();event.button_index=which;event.pressed=down;event.device=device
 await dispatch(event)
func tap(which:int) -> void:await joy(which,true);await joy(which,false)
func key(which:int,down:bool) -> void:
 var event:=InputEventKey.new();event.keycode=which;event.physical_keycode=which;event.pressed=down
 await dispatch(event)
func axis(which:int,value:float,device:int=0) -> void:
 var event:=InputEventJoypadMotion.new();event.axis=which;event.axis_value=value;event.device=device
 await dispatch(event)
func point(cell:Vector2i) -> Vector2:return game.world._screen_point(game.world.assembly_origin+Vector2(cell)*72.0)
func cell(part:Dictionary) -> Vector2i:return Vector2i(int(part.x),int(part.y))
func piece(id:int) -> Dictionary:
 for part in game.design:
  if int(part.id)==id:return part
 return {}
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json")]
func same_json_numbers(actual:Variant,expected:Variant,path:String,differences:Array) -> bool:
 if actual is Dictionary and expected is Dictionary:
  if actual.size()!=expected.size():return false
  for name in expected:
   if not actual.has(name) or not same_json_numbers(actual[name],expected[name],path+"."+str(name),differences):return false
  return true
 if actual is Array and expected is Array:
  if actual.size()!=expected.size():return false
  for index in expected.size():
   if not same_json_numbers(actual[index],expected[index],path+"[%d]"%index,differences):return false
  return true
 if typeof(actual)!=typeof(expected):
  if not (actual is int or actual is float) or not (expected is int or expected is float):return false
  differences.append({"path":path,"disk_type":type_string(typeof(actual)),"memory_type":type_string(typeof(expected)),"exact_equal":actual==expected})
 return actual==expected
func model() -> Dictionary:
 return {"design":game.design.duplicate(true),"launcher":game.launcher.duplicate(true),"inventory":game.economy.inventory.duplicate(true),"credits":game.economy.credits,"next_id":game.next_id}
func target() -> Vector2i:
 var bounds:Rect2i=game.workshop_input.camera.grid_bounds
 for y in range(bounds.position.y,bounds.end.y):
  for x in range(bounds.position.x,bounds.end.x):
   var at:=Vector2i(x,y)
   if not game.workshop_input.Controls.occupied(game.design,at) and game.workshop_input._allowed_screen(point(at)):return at
 check(false,"fixture has a visible empty drop cell");return Vector2i.ZERO
func control(id:String) -> Control:
 for node in game.hud.content.find_children("*","Control",true,false):
  if str(node.get_meta("view_key",""))==id:return node
 return null
func click(at:Vector2) -> void:await motion(at);await mouse(at,true);await mouse(at,false)
func fresh() -> bool:
 if is_instance_valid(game):game.queue_free();await settle(5)
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
 game=Main.instantiate();game.set_script(CountedMain);root.add_child(game)
 game.set_process(false);game.world.set_process(false);await settle(6);game._on_focus_entered()
 owner=game.courier_input
 # Advance the canonical shop scene before using its actual workbench button.
 # Do not teleport the clerk, force page/context, or bypass input ownership.
 for unused in 360:game.world._process(1.0/60.0)
 owner.tick(0);await settle()
 var workbench:Control=control("action:focus_workbench:null")
 check(workbench!=null,"fixture exposes the real workbench action")
 if workbench==null:return false
 await click(workbench.get_global_rect().get_center())
 for unused in 120:game.world._process(1.0/60.0)
 game.workshop_input.fit();owner.tick(0);await settle(5)
 check(game.page=="workshop" and owner.context=="ui" and game.workshop_input.enabled(),"real GUI workbench entry settles into usable UI context")
 if not game.workshop_input.enabled():return false
 await click(point(cell(game.design[0])))
 check(game.selected_id==int(game.design[0].id),"fixture selects a module through real mouse GUI dispatch")
 return true
func grid(pickup:bool=false) -> void:
 await tap(JOY_BUTTON_X)
 check(owner.context=="grid" and owner._grid,"fresh X enters production controller grid")
 if pickup:
  await tap(JOY_BUTTON_Y)
  check(game.workshop_input.controller_moving(),"fresh Y creates a pending controller pickup")
func drag_case(different:bool,pickup:bool) -> void:
 if not await fresh():return
 var label:String="different=%s pickup=%s"%[different,pickup]
 var part:Dictionary=game.design[1 if different else 0].duplicate(true)
 await grid(pickup)
 var before:Dictionary=model();var bytes:Array=disk();var saves:int=game.qa_saves;var undo:int=game.undo_history.size()
 var destination:Vector2i=target();var from:Vector2=point(cell(part));var to:Vector2=point(destination)
 await motion(from);await mouse(from,true)
 check(owner.context=="ui" and not owner._grid and not owner.controller_navigation,"mouse press owns UI immediately "+label)
 check(not owner._blocked.has("m:1") and owner._mouse.has("m:1"),"initiating left press remains live across handoff "+label)
 check(not game.workshop_input.controller_moving() and game.workshop_input.camera.gesture=="move","mouse press cancels old controller pickup and arms mouse move "+label)
 await motion(to,MOUSE_BUTTON_MASK_LEFT)
 check(model()==before and disk()==bytes and game.qa_saves==saves and game.undo_history.size()==undo,"held drag makes no model/save/undo writes "+label)
 var preview:Dictionary=game.world.workshop_drag_snapshot()
 check(preview.visible and preview.valid,"held first drag exposes valid ghost "+label)
 print("WITNESS before_release ",JSON.stringify({"case":label,"context":owner.context,"blocked":owner._blocked,"mouse":owner._mouse,"gesture":game.workshop_input.camera.gesture,"source":cell(piece(part.id)),"target":destination,"save_delta":game.qa_saves-saves,"undo_delta":game.undo_history.size()-undo}))
 await mouse(to,false)
 var moved:Dictionary=piece(part.id).duplicate(true);var relocated:bool=cell(moved)==destination;moved.x=part.x;moved.y=part.y
 check(relocated and moved==part,"first valid release moves exactly the source module "+label)
 check(game.qa_saves==saves+1 and game.undo_history.size()==undo+1,"first valid release creates exactly one save and undo "+label)
 var persisted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 var number_types:Array=[];var saved_matches:bool=same_json_numbers(persisted.design,game.design,"design",number_types)
 print("WITNESS persisted ",JSON.stringify({"case":label,"design_matches":saved_matches,"backup_matches":disk()[1]==bytes[0],"save_error":game._last_save_error,"numeric_type_differences":number_types}))
 check(saved_matches and disk()[1]==bytes[0] and game._last_save_error.is_empty(),"drop persists the exact design and promotes the old primary once "+label)
 check(game.undo_history.size()==undo+1 and game.undo_history.back().design==before.design and game.undo_history.back().launcher==before.launcher,"drop retains the exact pre-edit undo snapshot "+label)
 check(game.workshop_input.camera.gesture.is_empty() and not game.world.workshop_drag_snapshot().visible,"release clears gesture and ghost "+label)
 check(not owner._mouse.has("m:1") and not owner._blocked.has("m:1"),"release leaves no orphaned mouse token "+label)
 check(game.economy.inventory==before.inventory and game.economy.credits==before.credits and game.launcher==before.launcher and game.next_id==before.next_id,"handoff preserves stock credits launcher and ID allocator "+label)
 var after:Dictionary=model();var after_bytes:Array=disk();var after_saves:int=game.qa_saves;var after_undo:int=game.undo_history.size()
 await mouse(to,false);await motion(to)
 check(model()==after and disk()==after_bytes and game.qa_saves==after_saves and game.undo_history.size()==after_undo,"duplicate release cannot replay a commit "+label)
func middle_case() -> void:
 if not await fresh():return
 await grid(true)
 var before:Dictionary=model();var bytes:Array=disk();var saves:int=game.qa_saves;var undo:int=game.undo_history.size()
 var from:Vector2=point(cell(game.design[0]));var center:Vector2=game.workshop_input.camera.center
 await motion(from);await mouse(from,true,MOUSE_BUTTON_MIDDLE)
 check(owner.context=="ui" and not owner._blocked.has("m:3") and game.workshop_input.camera.gesture=="pan" and not game.workshop_input.controller_moving(),"initiating middle press switches ownership and cancels controller pickup")
 await motion(from+Vector2(24,12),MOUSE_BUTTON_MASK_MIDDLE)
 check(game.workshop_input.camera.center!=center,"middle motion applies existing camera pan")
 await mouse(from+Vector2(24,12),false,MOUSE_BUTTON_MIDDLE)
 check(game.workshop_input.camera.gesture.is_empty() and not owner._mouse.has("m:3") and not owner._blocked.has("m:3"),"first middle release ends pan and releases its token")
 check(model()==before and disk()==bytes and game.qa_saves==saves and game.undo_history.size()==undo,"middle handoff remains presentation-only")
func boundary_case(reason:String) -> void:
 if not await fresh():return
 await grid()
 var before:Dictionary=model();var bytes:Array=disk();var saves:int=game.qa_saves;var undo:int=game.undo_history.size()
 var from:Vector2=point(cell(game.design[0]));var to:Vector2=point(target())
 await mouse(from,true);await motion(to,MOUSE_BUTTON_MASK_LEFT)
 if reason=="focus":game._on_focus_exited();game._on_focus_entered()
 elif reason=="modal":
  await tap(JOY_BUTTON_START);check(owner.context=="modal","settings creates a genuine context boundary")
  game.workshop_input.tick();await tap(JOY_BUTTON_B)
 elif reason=="device":
  await joy(JOY_BUTTON_RIGHT_SHOULDER,true,1);await joy(JOY_BUTTON_RIGHT_SHOULDER,false,1)
 check(owner._blocked.has("m:1"),"old held left remains quarantined at "+reason+" boundary")
 await mouse(to,true)
 check(owner._blocked.has("m:1") and model()==before,"duplicate held press cannot clear "+reason+" barrier")
 await mouse(to,false);await motion(to)
 check(not owner._blocked.has("m:1") and not owner._mouse.has("m:1"),"old release clears only its quarantine token after "+reason)
 check(model()==before and disk()==bytes and game.qa_saves==saves and game.undo_history.size()==undo and game.workshop_input.camera.gesture.is_empty() and not game.world.workshop_drag_snapshot().visible,"interrupted release cannot commit across "+reason)
 # A genuinely fresh subsequent drag must still work after the required release.
 await mouse(from,true);await motion(to,MOUSE_BUTTON_MASK_LEFT);await mouse(to,false)
 check(game.qa_saves==saves+1 and game.undo_history.size()==undo+1,"fresh post-release drag commits once after "+reason)
func preserve_other_tokens() -> void:
 if not await fresh():return
 var from:Vector2=point(cell(game.design[0]))
 await mouse(from,true)
 await tap(JOY_BUTTON_START);game.workshop_input.tick();await tap(JOY_BUTTON_B)
 await grid()
 await key(KEY_F8,true);await joy(JOY_BUTTON_Y,true);await axis(JOY_AXIS_LEFT_X,.6)
 check(owner._blocked.has("m:1") and game.workshop_input.controller_moving(),"fixture retains an old held mouse and controller pickup")
 await mouse(from,true,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_MIDDLE)
 check(not owner._blocked.has("m:3") and owner._blocked.has("m:1"),"handoff exempts only the initiating middle token")
 check(owner._blocked.has("k:%d"%KEY_F8) and owner._blocked.has("b:0:%d"%JOY_BUTTON_Y) and owner._blocked.has("a:0:%d"%JOY_AXIS_LEFT_X),"handoff still quarantines held key controller button and stick")
 await mouse(from,false,MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MASK_MIDDLE)
 await mouse(from,false,MOUSE_BUTTON_MIDDLE)
 await key(KEY_F8,false);await joy(JOY_BUTTON_Y,false);await axis(JOY_AXIS_LEFT_X,0)
 check(owner._mouse.is_empty() and owner._blocked.is_empty() and game.workshop_input.camera.gesture.is_empty(),"each retained held input clears only through its release or neutral")
func held_button_matrix(reason:String) -> void:
 if not await fresh():return
 # Old buttons start in the letterbox, so even right-button coverage is read-only.
 var inert:=Vector2(4,4)
 for which in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:
  var label:String="%s m:%d"%[reason,which];var token:String="m:%d"%which
  var before:Dictionary=model();var bytes:Array=disk();var saves:int=game.qa_saves;var undo:int=game.undo_history.size()
  await mouse(inert,true,which)
  if reason=="focus":game._on_focus_exited();game._on_focus_entered()
  else:await tap(JOY_BUTTON_START);await tap(JOY_BUTTON_B)
  check(owner._blocked.has(token),"old held button is quarantined "+label)
  await grid();await mouse(inert,true,which)
  check(owner.context=="grid" and owner._blocked.has(token),"blocked duplicate cannot trigger grid handoff "+label)
  var initiating:int=MOUSE_BUTTON_MIDDLE if which==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_LEFT
  var new_token:String="m:%d"%initiating;var from:Vector2=point(cell(game.design[0]))
  await mouse(from,true,initiating,(1<<(which-1))|(1<<(initiating-1)))
  check(owner.context=="ui" and owner._blocked.has(token) and not owner._blocked.has(new_token),"fresh handoff preserves the other held button "+label)
  await mouse(inert,false,which,1<<(initiating-1))
  check(not owner._blocked.has(token) and not owner._mouse.has(token),"old button releases its own quarantine "+label)
  await mouse(from,false,initiating)
  await mouse(inert,true,which)
  check(not owner._blocked.has(token) and owner._mouse.has(token),"a fresh press becomes eligible only after old release "+label)
  await mouse(inert,false,which)
  check(model()==before and disk()==bytes and game.qa_saves==saves and game.undo_history.size()==undo and game.workshop_input.camera.gesture.is_empty(),"held-button boundary cannot mutate the assembly "+label)
func run() -> void:
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/courier-dev06-") or FileAccess.file_exists("user://savegame.json"):
  printerr("Fresh isolated /tmp/courier-dev06-* XDG_DATA_HOME required");quit(2);return
 root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
 for different in [false,true]:
  for pickup in [false,true]:await drag_case(different,pickup)
 await middle_case()
 for reason in ["focus","modal","device"]:await boundary_case(reason)
 await preserve_other_tokens()
 for reason in ["focus","modal"]:await held_button_matrix(reason)
 if is_instance_valid(game):game.queue_free();await settle(5)
 check(passed+failed==191,"all viewport handoff assertions completed")
 print("WORKSHOP_MOUSE_HANDOFF_DEV06 passed=%d failed=%d input=synthetic_Window.push_input physical_gamepad=false native_mouse=false"%[passed,failed])
 quit(1 if failed else 0)
