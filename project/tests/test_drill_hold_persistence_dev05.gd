extends SceneTree
## Real Main set_input/undo/save_game and Economy disk save/load, stub presentation.
## Requires an EMPTY isolated profile. Never erases fixtures; preserve failures.
const Econ=preload("res://scripts/economy.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Policy=preload("res://scripts/workshop_parts_v2.gd")
var passed:int=0
var failed:int=0
class SavingEconomy extends "res://scripts/economy.gd":
 var fail_save:bool=false
 var save_attempts:int=0
 func save_state(craft:Array,pad:Array,preferences:Dictionary) -> bool:
  save_attempts+=1
  if fail_save:save_error="Injected drill fixture save failure; previous disk remains.";return false
  return super.save_state(craft,pad,preferences)
class WorldStub extends RefCounted:
 var edits:Array=[]
 func show_design(_design:Array,_selected:int) -> void:pass
 func committed_edit(kind:String,p:Dictionary) -> void:edits.append([kind,p.duplicate(true)])
class InputStub extends RefCounted:
 func cancel() -> void:pass
class Host extends "res://scripts/main.gd":
 var notices:Array=[]
 func _ready() -> void:pass
 func render() -> void:pass
 func notify(message:String) -> void:notices.append(message)
 func _sound(_key:String) -> void:pass
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func part(id:int,kind:String,x:int,y:int=0,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1}
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json") if FileAccess.file_exists("user://savegame.backup.json") else PackedByteArray()]
func saved() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func source(data:Dictionary) -> int:return int(data.design[2].input_a)
func _initialize() -> void:
 if OS.get_environment("SC_DRILL_TEST_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Use SC_DRILL_TEST_ISOLATED=1 and a new empty isolated XDG_DATA_HOME; existing fixtures are never erased.");quit(2);return
 var game=Host.new();game.economy=SavingEconomy.new();game.economy.enable_force_mode()
 game.design=[part(1,"cargo",0),part(2,"battery",-1),part(3,"drill",1),part(4,"drill",0,1),part(6,"not_gate",1,1)]
 game.launcher=[part(10,"battery",0),part(11,"beam",1)]
 game.economy.starter_stock(game.design,game.launcher)
 game.world=WorldStub.new();game.workshop_input=InputStub.new();game.page="workshop";game.assembly_mode="craft";game.selected_id=3
 if not check(game.save_game(),"baseline automatic drill saves through real Main/Economy"):
  game.free();quit(1);return
 var before:Array=game.design.duplicate(true);var pad:Array=game.launcher.duplicate(true)
 var inventory:Dictionary=game.economy.inventory.duplicate(true);var credits:int=game.economy.credits
 var attempts:int=game.economy.save_attempts
 var choice:Dictionary=Policy.convenience_source(game.selected_part(),true,false,"pilot-free-v2")
 check(game.design==before and game.undo_history.is_empty() and game.economy.save_attempts==attempts,"inspecting proposal creates no undo/save or design mutation")
 game._action("set_input",{"id":3,"key":"input_a","source":choice.source})
 var expected:Array=before.duplicate(true);expected[2].input_a=-2
 check(game.design==expected and game.launcher==pad and game.economy.inventory==inventory and game.economy.credits==credits,"actual Main action changes only selected drill source")
 check(game.undo_history.size()==1 and game.undo_history[0].design==before and game.economy.save_attempts==attempts+1 and source(saved())==-2,"explicit held edit has one exact undo and one durable save")
 game.undo_assembly()
 check(game.design==before and game.undo_history.is_empty() and source(saved())==-1,"existing Main undo durably restores original automatic design")
 attempts=game.economy.save_attempts
 game._action("set_input",{"id":999,"key":"input_a","source":-2})
 check(game.design==before and game.economy.save_attempts==attempts and game.undo_history.is_empty(),"stale inspector ID cannot edit another selected part or write")
 # Real serializer/loader round-trips defaults, opt-in hold, and external wires.
 for wire in [-1,-2,6,999]:
  game.design[2].input_a=wire;game.design[2].input_b=71;game.design[2].target=13;game.design[2].param=2.125
  if not check(game.save_game(),"save fixture source %d"%wire):continue
  var raw:Array=disk();var snapshot:Dictionary=saved();var loader=Econ.new();var restored:Dictionary=loader.load_state(true)
  check(not loader.review_load_blocked and restored.design==snapshot.design and restored.launcher==snapshot.launcher,"actual load preserves all saved drill fields for source %d"%wire)
  for repetition in 3:Policy.convenience_source(restored.design[2],true,false,"pilot-free-v2");Policy.trigger_text(restored.design[2],restored.design,true,false,"pilot-free-v2")
  check(disk()==raw and restored.design==snapshot.design,"load plus repeated inspect never rewrites durable slots for source %d"%wire)
 # Restore a fresh current automatic reference before testing existing failure semantics.
 game.design=before.duplicate(true);game.undo_history.clear();game.notices.clear()
 if not check(game.save_game(),"automatic failure baseline saved"):
  game.free();quit(1);return
 var durable:Array=disk();attempts=game.economy.save_attempts
 game.economy.fail_save=true
 game._action("set_input",{"id":3,"key":"input_a","source":-2})
 check(game.design[2].input_a==-2 and game.undo_history.size()==1 and game.economy.save_attempts==attempts+1,"failed save retains undoable live edit under existing Main contract")
 check(disk()==durable and not game._last_save_error.is_empty() and game.notices.has(game._last_save_error),"failed edit reports save error and preserves both durable slots")
 game.notices.clear();game.undo_assembly()
 check(game.design==before and game.undo_history.is_empty() and disk()==durable,"undo during save failure restores live blueprint without changing disk")
 var warned:bool=false
 for message in game.notices:
  if "已撤销，但进度未保存" in str(message):warned=true
 check(warned and not game.notices.has("已撤销上一步装配修改。"),"failed undo save warns instead of claiming durable success")
 game.economy.fail_save=false
 game._action("set_input",{"id":3,"key":"input_a","source":-2})
 check(source(saved())==-2 and game.undo_history.size()==1,"retry with restored saving persists explicit held choice")
 game.undo_assembly()
 check(source(saved())==-1 and game.design==before,"successful undo after failure is durable and exact")
 print("DRILL_HOLD_PERSISTENCE_DEV05 passed=%d failed=%d native_input=NOT_RUN retained_user_dir=%s"%[passed,failed,OS.get_user_data_dir()])
 game.free();quit(1 if failed else 0)
