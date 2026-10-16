extends SceneTree
## Read-only boot of a cloned, actually earned paid-delivery save.
## The harness supplies its own HOME/XDG directory. No route/input/credit edits.
const ExactValue=preload("res://scripts/pilot_protected_bird_profile.gd")
var game
var passed:int=0
var failed:int=0
var checks:Dictionary={}

func _initialize() -> void:run.call_deferred()

func check(ok:bool,label:String) -> void:
 checks[label]=ok
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)

func run() -> void:
 var out:String=OS.get_environment("SC_RECOVERY_PROBE_OUT")
 if out.is_empty() or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 var original:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 if not original is Dictionary:quit(3);return
 check(int(original.get("credits",0))==367 and int(original.get("day",0))==1,"earned fixture is Day1 balance367")
 check(original.get("settled_ids",{}).keys()==["D1-A"],"fixture has one actual paid receipt")
 root.size=Vector2i(1280,800)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 for i in 20:await process_frame
 check(not game.economy.review_load_blocked,"earned record opens without recovery lock")
 check(game.page=="hub" and not game._dialogue_is_open(),"completed dialogue does not replay on boot")
 check(game.world.missing_assets.is_empty(),"active presentation has no missing resources")
 check(game.economy.credits==367 and game.economy.jobs_today==1,"boot retains earned balance and job count")
 check(game.economy.settled_ids==original.settled_ids and game.economy.history==original.history,"boot keeps the actual receipt and history values")
 check(game.economy.active_contract_id.is_empty() and game.economy.in_flight.is_empty(),"completed route stays closed")
 check(ExactValue.same_value(game.economy.review_state,original.review_state),"boot preserves exact finite pending review values")
 check(game.economy.review_state.pending.keys()==["D1-A"] and game.economy.review_state.published.is_empty(),"current-day review is still unpublished")
 var f=FileAccess.open(out+"/result.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"passed":passed,"failed":failed,"native_input":false,"fixture":"Copied native-paid-ground03 completed save; no progression supplied by this probe.","review_original":original.review_state,"review_live":game.economy.review_state,"review_native_types":review_types(original.review_state,game.economy.review_state),"exactness":"Finite numeric values compare exactly; v1 integer normalization is reported separately. No epsilon or whole-file numeric-spelling assumption."},"  "));f.close()
 print("RECOVERY_PAID_SAVE_BOOT passed=%d failed=%d"%[passed,failed])
 await game._quit_cleanly(1 if failed else 0)

func review_types(a:Variant,b:Variant,path:String="") -> Array:
 var differences:Array=[]
 if typeof(a)!=typeof(b):differences.append({"path":path,"before_type":typeof(a),"after_type":typeof(b),"before":a,"after":b})
 if a is Dictionary and b is Dictionary:
  for key in a:
   if b.has(key):differences.append_array(review_types(a[key],b[key],path+"/"+str(key)))
 elif a is Array and b is Array:
  for i in mini(a.size(),b.size()):differences.append_array(review_types(a[i],b[i],path+"/"+str(i)))
 return differences
