extends SceneTree
## Calls the real Main comparison without entering the scene tree or _ready.
## Reads the original native A/B evidence; never loads it into Economy or saves.
## Headless regression only: native input, raster, and flight physics are not run.
const Main=preload("res://scripts/main.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const A_SHA256:String="16ff3d35dc66bab44aca6c7d4b185932c4226fff9d82f2637179995f399136c3"
const B_SHA256:String="ca24ab596711db280c7be554a7fb7ecba9640ecbddac229494af4005faaea546"
var passed:int=0
var failed:int=0
var game

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func read_fixture(path:String,expected_hash:String,label:String) -> Dictionary:
 if path.is_empty() or not FileAccess.file_exists(path):
  check(false,label+" fixture path is required");return {}
 check(FileAccess.get_sha256(path)==expected_hash,label+" is the original native save")
 if FileAccess.get_sha256(path)!=expected_hash:return {}
 var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(parsed is Dictionary,label+" is a readable save dictionary")
 return parsed if parsed is Dictionary else {}
func snapshots(value:Dictionary) -> Dictionary:
 return {"design_snapshot":value.get("design_snapshot",[]).duplicate(true),"launcher_snapshot":value.get("launcher_snapshot",[]).duplicate(true)}
func part(value:Dictionary,id:int) -> Dictionary:
 for item in value.design_snapshot+value.launcher_snapshot:
  if int(item.id)==id:return item
 return {}
func side_effect_state() -> PackedByteArray:
 return var_to_bytes([game.design,game.launcher,game.catalog,game.report,game.undo_history,game.economy.credits,game.economy.inventory,game.economy.history,game.economy.settled_ids,game.economy.last_trials,game.economy.last_settlement])
func expect(current:Dictionary,previous:Dictionary,expected:String,label:String) -> void:
 game.design=current.get("design_snapshot",[]);game.launcher=current.get("launcher_snapshot",[])
 var inputs_before:PackedByteArray=var_to_bytes([current,previous])
 var state_before:PackedByteArray=side_effect_state()
 var result:String=game._design_changes(previous)
 check(result==expected,label+" exact comparison: "+result)
 check(var_to_bytes([current,previous])==inputs_before and side_effect_state()==state_before,label+" changes no inputs, report, undo, inventory, credits, or paid ledger")

func run() -> void:
 if OS.get_environment("SC_TRIAL_LAYOUT_TEST_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Use SC_TRIAL_LAYOUT_TEST_ISOLATED=1, a new empty XDG_DATA_HOME, and SC_TRIAL_LAYOUT_A_SAVE / SC_TRIAL_LAYOUT_B_SAVE paths; no existing profile is used.");quit(2);return
 var a_path:String=OS.get_environment("SC_TRIAL_LAYOUT_A_SAVE")
 var b_path:String=OS.get_environment("SC_TRIAL_LAYOUT_B_SAVE")
 var a_save:Dictionary=read_fixture(a_path,A_SHA256,"A")
 var b_save:Dictionary=read_fixture(b_path,B_SHA256,"B")
 if a_save.is_empty() or b_save.is_empty():quit(2);return
 var durable_before:PackedByteArray=var_to_bytes([a_save,b_save])
 var a:Dictionary=a_save.last_trials["D6-A"].latest
 var b:Dictionary=b_save.last_trials["D6-A"].latest
 check(b_save.last_trials["D6-A"].previous==a,"native B retains exact A as its previous trial")
 check(a.design_snapshot==a_save.design and b.design_snapshot==b_save.design and a.launcher_snapshot==b.launcher_snapshot,"native trial snapshots match the saved craft and unchanged launcher")
 var moved:Dictionary=snapshots(a)
 part(moved,1007).x=1.0;part(moved,1007).y=2.0
 check(moved==snapshots(b),"native A/B differ only by beam #1007 moving from (2,1) to (1,2)")
 check(b.comparison["本次改动"]=="装置未改动。","native B retains the historical misleading comparison for evidence")
 game=Main.new() # Never add Main to root: no startup, save, simulation, or UI.
 game.catalog=Parts.catalog();game.catalog.cargo=Parts.cargo_spec()
 game.report=b;game.economy.last_trials=b_save.last_trials
 game.economy.credits=int(b_save.credits);game.economy.inventory=b_save.inventory
 game.economy.history=b_save.history;game.economy.settled_ids=b_save.settled_ids;game.economy.last_settlement=b_save.last_settlement
 expect(b,a,"结构梁换了位置","actual native A to B")
 expect(a,b,"结构梁换了位置","move back / undo-equivalent comparison")
 expect(a,a,"装置未改动。","identical native A")
 expect(b,b,"装置未改动。","identical native B")
 expect({}, {},"装置未改动。","empty design and launcher")
 var reordered:Dictionary=snapshots(a)
 reordered.design_snapshot.reverse();reordered.launcher_snapshot.reverse()
 expect(reordered,a,"装置未改动。","reordered current craft and launcher")
 expect(a,reordered,"装置未改动。","reordered previous craft and launcher")
 expect(reordered,reordered,"装置未改动。","both lists reordered")
 var numeric:Dictionary=snapshots(a)
 for item in numeric.design_snapshot+numeric.launcher_snapshot:item.x=int(item.x);item.y=int(item.y)
 expect(numeric,a,"装置未改动。","integer and JSON-number grid coordinates compare equally")
 for axis in ["x","y"]:
  var craft_move:Dictionary=snapshots(a);part(craft_move,1007)[axis]+=1
  expect(craft_move,a,"结构梁换了位置","craft "+axis+"-only move")
  var launcher_move:Dictionary=snapshots(a);part(launcher_move,1001)[axis]+=1
  expect(launcher_move,a,"蓄能弹簧换了位置","launcher "+axis+"-only move")
 var added:Dictionary=snapshots(a)
 var new_part:Dictionary=part(a,1007).duplicate(true);new_part.id=2001;new_part.x=4;new_part.y=3
 added.design_snapshot.append(new_part)
 expect(added,a,"新增 #2001 结构梁","new part keeps existing added copy without a move notice")
 var removed:Dictionary=snapshots(a);removed.design_snapshot.erase(part(removed,1007))
 expect(removed,a,"拆下 #"+str(part(a,1007).id),"removed part keeps existing JSON-number ID copy")
 var rotated:Dictionary=snapshots(a);part(rotated,1007).rot=1
 expect(rotated,a,"#1007 朝向 右 → 下","rotation-only copy unchanged")
 var tuned:Dictionary=snapshots(a);part(tuned,4).param=30.0
 var tune_text:String="#4 %s → %s N"%[str(part(a,4).param),str(part(tuned,4).param)]
 expect(tuned,a,tune_text,"parameter-only value and unit unchanged")
 var epsilon:Dictionary=snapshots(a);part(epsilon,4).param+=0.000001
 expect(epsilon,a,"装置未改动。","existing approximate parameter equality unchanged")
 for key in ["input_a","input_b","target"]:
  var rewired:Dictionary=snapshots(a);part(rewired,8)[key]=3
  expect(rewired,a,"#8 调整"+{"input_a":"信号 A","input_b":"信号 B","target":"作用目标"}[key],key+"-only copy unchanged")
 var combined:Dictionary=snapshots(a)
 part(combined,4).x=3;part(combined,4).y=3;part(combined,4).rot=1;part(combined,4).param=30.0
 part(combined,4).input_a=3;part(combined,4).input_b=7;part(combined,4).target=2
 expect(combined,a,"推进喷口换了位置；#4 朝向 右 → 下；"+tune_text+"；#4 调整信号 A；#4 调整信号 B；#4 调整作用目标","combined change preserves all existing categories and order")
 for repeat in 5:expect(b,a,"结构梁换了位置","repeat "+str(repeat))
 check(var_to_bytes([a_save,b_save])==durable_before and b.comparison["本次改动"]=="装置未改动。","both complete save objects and old report text remain byte-exact in memory")
 check(FileAccess.get_sha256(a_path)==A_SHA256 and FileAccess.get_sha256(b_path)==B_SHA256,"original A/B files remain byte-exact on disk")
 check(not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"comparison never creates either save slot")
 game.free()
 print("TRIAL_LAYOUT_FEEDBACK_DEV07 passed=%d failed=%d native_input=NOT_RUN flight_physics=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
