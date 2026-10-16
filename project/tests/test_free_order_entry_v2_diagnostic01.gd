extends SceneTree
## Source-only fixture. Lead runs in an empty isolated XDG_DATA_HOME.
## Real Economy/Main helpers/HUD/World; synthetic clicks, not native acceptance.
const Econ=preload("res://scripts/economy.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Title=preload("res://scripts/demo_title.gd")
var passed:int=0
var failed:int=0
var host

class Host extends "res://scripts/main.gd":
 var notices:Array[String]=[]
 var recovery_held:bool=false
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func notify(message:String) -> void:notices.append(message)
 func _show_save_recovery() -> void:recovery_held=true

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func frames(count:int=3) -> void:
 for unused in count:await process_frame
func remove_tree(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for file in directory.get_files():DirAccess.remove_absolute(path.path_join(file))
 for child in directory.get_directories():remove_tree(path.path_join(child))
 DirAccess.remove_absolute(path)
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","economy-recovery-v1"]:remove_tree("user://"+name)
func durable() -> Array:
 var result:Array=[]
 for slot in ["savegame.json","savegame.backup.json"]:
  result.append(FileAccess.get_file_as_bytes("user://"+slot) if FileAccess.file_exists("user://"+slot) else null)
 return result
func model(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func make_old(accepted:bool=true,loaded:bool=true):
 clear_files();var economy=Econ.new()
 economy.enable_extreme_mode();economy.starter_stock(Extreme.starter_design(),Extreme.starter_launcher());economy.enable_story_mode()
 if accepted:
  check(economy.accept_contract("D1-A").ok,"fixture accepts an old ordinary order")
  economy.mark_story_seen("D1-A","D1-A/accept")
  if loaded:check(economy.mark_cargo_loaded("D1-A").ok,"fixture retains the original loaded box")
 economy.last_trials={"D1-A":{"latest":{"old_prediction":true}},"unrelated":{"keep":true}}
 check(economy.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"fixture old profile is durable")
 return economy
func plain_host(e):
 var game=Host.new();game.economy=e;game.catalog=Parts.catalog();game.catalog.cargo=Parts.cargo_spec();game._starter()
 return game
func open_shop(e) -> void:
 host=plain_host(e);root.add_child(host);host._build_ui();host.set_process(false)
 host.world.set_process(false);host.world.assembly_feedback.set_process(false)
 host.courier_input.set_process(false);host.courier_input.focused=true
 host.render();await frames()
 check(host._free_upgrade_context_available(),"real loaded shop permits optional upgrade")
func close_shop() -> void:
 if is_instance_valid(host):root.remove_child(host);host.free();host=null
 await frames()
func confirm_button() -> Button:
 for button in host.hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("view_key",""))=="free_upgrade:confirm":return button
 return null
func begin(kind:String="accepted") -> Dictionary:
 host._action("swap_accepted_free" if kind=="accepted" else "upgrade_free_offers",null)
 check(host.hud.free_order_upgrade_open(),"explicit request opens one upgrade confirmation")
 return host._pending_free_order_upgrade.duplicate(true)
func click_confirm() -> void:
 var button:Button=confirm_button();check(button!=null,"confirmation has a concrete button")
 if button!=null:button.pressed.emit()
func cache_state() -> Dictionary:
 return {"report":host.report.duplicate(true),"trial":host.trial,"flight_order":host.flight_order.duplicate(true),"sim":host.sim,"page":host.page,"ticks":host.pilot_completed_ticks}

func test_entry_helpers() -> void:
 clear_files();var fresh=plain_host(Econ.new())
 check(fresh._prepare_free_economy_entry(false),"fresh entry opts into free economics")
 check(fresh.economy.flight_mode=="pilot-free-v1" and fresh.economy.contracts.size()==2,"fresh starter stocks two new orders")
 for order in fresh.economy.contracts:check(order.control_version=="pilot-free-v1" and order.economy_policy==Econ.FREE_ECONOMY_POLICY,"free mode precedes initial offer authoring")
 check(not FileAccess.file_exists("user://savegame.json"),"fresh helper does not bypass normal protected startup save")
 fresh.free()
 var e=make_old();e.credits=-210;check(e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"negative legacy fixture saved")
 var original:Dictionary=model(e);var bytes:Array=durable();var continuing=plain_host(Econ.new());var loaded:Dictionary=continuing.economy.load_state(true)
 continuing.design=loaded.design;continuing.launcher=loaded.launcher
 var durable_original:Dictionary=JSON.parse_string(bytes[0].get_string_from_utf8())
 var loaded_before_recovery:Dictionary=model(continuing.economy)
 check(continuing._prepare_free_economy_entry(true),"real continuation applies recovery before later startup authoring")
 check(continuing.economy.credits==0 and not continuing._free_entry_notice.is_empty(),"one compact subsidy notice follows a committed grant")
 # Diagnostic only: retain the original failing assertion unchanged below.
 _entry_diagnostic_stage("authored_to_durable",original,durable_original)
 _entry_diagnostic_stage("durable_to_loaded",durable_original,loaded_before_recovery)
 _entry_diagnostic_stage("loaded_to_recovered",loaded_before_recovery,model(continuing.economy))
 check(continuing.economy.contracts==original.contracts and continuing.economy.history==original.history and continuing.economy.last_settlement==original.last_settlement,"existing offers and receipts remain exact")
 var source:String=str(continuing.economy.economic_recovery.source_sha256)
 check(FileAccess.get_file_as_bytes("user://economy-recovery-v1/"+source+"/savegame.json")==bytes[0],"recovery archives original source bytes")
 var committed:Array=durable();check(continuing._prepare_free_economy_entry(true) and durable()==committed,"repeated helper cannot grant or save again")
 continuing.free()
 e=make_old();e.credits=-30;e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{})
 var failed_entry=plain_host(e);var old_mode:String=e.flight_mode;bytes=durable();var before:Dictionary=model(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not failed_entry._prepare_free_economy_entry(true) and e.review_load_blocked,"failed recovery blocks dependent startup")
 check(e.credits==-30 and e.flight_mode==old_mode and e.contracts==before.contracts and durable()==bytes,"failed entry has no free-mode half update or durable replacement")
 failed_entry.free();clear_files()

func test_empty_old_entry() -> void:
 var e=make_old(false,false);e.credits=-58;e.contracts=[];e.story_state={};e.last_trials={}
 check(e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"empty old boundary saved")
 var game=plain_host(Econ.new());var original:Array=durable();var loaded:Dictionary=game.economy.load_state(true)
 game.design=loaded.design;game.launcher=loaded.launcher
 check(game.economy.contracts.is_empty() and durable()==original,"actual-entry deferred load authors nothing")
 check(game._prepare_free_economy_entry(true) and game.economy.credits==0 and game.economy.contracts.is_empty(),"Main subsidy/free opt-in precede empty-boundary authoring")
 game.economy.enable_story_mode()
 for order in game.economy.contracts:check(order.control_version=="pilot-free-v1","explicit startup after recovery authors free rules only")
 game.free()

func test_loaded_inflight_deferred() -> void:
 var e=make_old();e.credits=0
 check(e.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher()).ok,"legacy trip starts with nonnegative cash")
 check(e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"legacy in-flight snapshot durable")
 var game=plain_host(e);var flight:Dictionary=e.in_flight.duplicate(true);var bytes:Array=durable()
 check(game._prepare_free_economy_entry(true) and game._legacy_recovery_deferred,"nonnegative loaded old trip defers a post-settlement recovery check")
 check(e.in_flight==flight and durable()==bytes,"deferred continuation does not mutate or save the old flight")
 var settled:Dictionary=e.settle_contract_and_save("D1-A",{"integrity":0.0,"energy_used":1000.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},10.0,false,game.design,game.launcher,{})
 check(settled.ok and e.credits<0,"original failure commits its original debt")
 var receipt:Dictionary=e.last_settlement.duplicate(true);var history:Array=e.history.duplicate(true);var settled_ids:Dictionary=e.settled_ids.duplicate(true)
 check(game._finish_deferred_free_recovery(),"post-settlement recovery commits separately")
 check(e.credits==0 and e.last_settlement==receipt and e.history==history and e.settled_ids==settled_ids,"subsidy leaves exact historical failure receipt and settled IDs intact")
 game.free()

func test_deferred_recovery_write_failure() -> void:
 var e=make_old();e.credits=0;e.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher());e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{})
 var game=plain_host(e);check(game._prepare_free_economy_entry(true),"deferred failure fixture enters old trip")
 var result:Dictionary=e.settle_contract_and_save("D1-A",{"integrity":0.0,"energy_used":1000.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},10.0,false,game.design,game.launcher,{})
 check(result.ok,"original legacy failure is durable before subsidy failure")
 var bytes:Array=durable();var before:Dictionary=model(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not game._finish_deferred_free_recovery() and game.recovery_held and e.review_load_blocked,"post-settlement write failure holds dependent gameplay")
 check(e.credits==before.credits and e.last_settlement==before.last_settlement and e.history==before.history and durable()==bytes,"failed subsidy keeps original committed failure and debt exact")
 game.free();clear_files()

func test_title_preview_no_write() -> void:
 var e=make_old();e.credits=-77;e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{})
 var bytes:Array=durable();var title=Title.new()
 title.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd")
 root.add_child(title);await frames(5)
 check(not is_instance_valid(title.game),"title preview does not construct an actual Main")
 check(durable()==bytes and not DirAccess.dir_exists_absolute("user://economy-recovery-v1"),"negative title preview writes no save or subsidy archive")
 root.remove_child(title);title.free();await frames()

func test_cancel_stale_and_success() -> void:
 var e=make_old();await open_shop(e)
 host.report={"old_preview":true};host.trial=true;host.flight_order=e.active_contract().duplicate(true);host.sim=RefCounted.new();host.pilot_completed_ticks=17
 var before:Dictionary=model(e);var bytes:Array=durable();var cache:Dictionary=cache_state()
 var expected:Dictionary=begin();host.hud.controller_back()
 check(not host.hud.is_blocking_modal() and host._pending_free_order_upgrade.is_empty(),"controller Back clears only temporary consent")
 check(model(e)==before and durable()==bytes and cache_state()==cache,"cancel preserves full model, exact slots and trial/view cache")
 begin();host.hud._dismiss_free_order_upgrade()
 check(model(e)==before and durable()==bytes,"close button path also leaves original exact")
 begin();e.active_contract().reward=int(e.active_contract().reward)+1
 var changed:Dictionary=model(e);click_confirm()
 check(model(e)==changed and durable()==bytes and cache_state()==cache,"live snapshot change rejects stale confirmation without cache reset")
 e.active_contract().reward=int(e.active_contract().reward)-1
 begin();var old_click:Callable=confirm_button().pressed.get_connections()[0].callable
 host.hud._dismiss_free_order_upgrade()
 host.render();begin();old_click.call()
 check(host.hud.free_order_upgrade_open() and durable()==bytes,"queued cancelled button cannot approve a reopened identical order")
 host.hud._dismiss_free_order_upgrade();host.render()
 expected=begin();DirAccess.make_dir_absolute("user://savegame.tmp");click_confirm()
 check(model(e)==before and durable()==bytes and cache_state()==cache,"failed final save retains complete old scene/model/slots")
 DirAccess.remove_absolute("user://savegame.tmp")
 var parcel_generation:int=host.world._parcel_generation;var old_cargo:String=str(e.active_contract().cargo)
 begin();click_confirm()
 check(e.active_contract().control_version=="pilot-free-v1" and e.active_contract_id=="D1-A","successful consent swaps the same accepted identity")
 check(e.is_cargo_loaded() and str(e.active_contract().cargo)==old_cargo and host.world.is_parcel_loaded("D1-A"),"same box remains loaded")
 check(host.world._parcel_generation==parcel_generation and not host.world.is_loading_scene(),"successful swap creates no extra handoff or load generation")
 check(host.sim==null and not host.trial and host.report.is_empty() and host.flight_order.is_empty() and host.pilot_completed_ticks==0,"only successful commit clears stale simulation and preview cache")
 check(host.page=="workshop" and host.hud.state.activeorder.control_version=="pilot-free-v1","Main rereads the new active order into workshop HUD")
 check(e.credits==before.credits and e.reputation==before.reputation and e.history==before.history and e.story_state==before.story_state,"swap generates no payment, penalty, story handoff or historical rewrite")
 var committed:Array=durable();host._action("confirm_free_upgrade",expected)
 check(durable()==committed,"repeated old confirmation cannot mutate durable state")
 await close_shop()

func test_guards_and_available() -> void:
 var e=make_old();await open_shop(e)
 var bytes:Array=durable()
 for field in ["closing","entry_defer_controls","pilot_resume_blocked","_free_restore_active","_finalizing_cargo_for_launch"]:
  host.set(field,true);host._request_free_order_upgrade("accepted")
  check(not host.hud.free_order_upgrade_open(),"host owner blocks upgrade: "+field);host.set(field,false)
 host._review_phone_owner=999;host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"even a closing phone owner blocks upgrade");host._review_phone_owner=0
 host._pending_story={"contract_id":"D1-A","beat":"accept"};host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"pending dialogue blocks upgrade");host._pending_story.clear()
 host.dialogue.begin({"dialogue_id":"upgrade-guard","lines":[{"speaker":"npc","text":"测试。"}]},{},host.settings)
 host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"active dialogue blocks upgrade");host.dialogue.cancel(false)
 for field in ["_review_phone_owner","_investigation_owner","_scene_paused","_clerk_return_requested"]:
  var old:Variant=host.world.get(field);host.world.set(field,123 if field.ends_with("owner") else true)
  host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"world owner blocks upgrade: "+field);host.world.set(field,old)
 var original_parcel:String=host.world.parcel_state
 host.world._loading_requested=true;host.world.parcel_state="loading"
 host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"live cargo loading excludes upgrade ownership")
 host.world._loading_requested=false;host.world.parcel_state=original_parcel
 var old_phase:String=host.world._parcel_phase;host.world._parcel_phase="counter_transfer"
 host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"actual handoff phase blocks upgrade");host.world._parcel_phase=old_phase
 host.hud.settings_open=true;host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"settings and upgrade cannot own two modals");host.hud.settings_open=false
 host.page="flight";host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open(),"a running trial cannot be swapped");host.page="hub"
 e.begin_dispatch(host.design,host.launcher);var flight:Dictionary=e.in_flight.duplicate(true)
 host._request_free_order_upgrade("accepted");check(not host.hud.free_order_upgrade_open() and e.in_flight==flight,"committed flight is never interrupted")
 check(durable()==bytes,"all rejected guard intents are no-write")
 await close_shop()
 e=make_old(false,false);await open_shop(e);host.page="contracts";host.render()
 var original:Dictionary=model(e);bytes=durable();begin("available");host.hud.controller_back()
 check(model(e)==original and durable()==bytes,"unaccepted offer cancellation preserves exact original")
 begin("available");e.contracts[0].reward=int(e.contracts[0].reward)+1
 var changed:Dictionary=model(e);click_confirm()
 check(model(e)==changed and durable()==bytes,"available-offer snapshot change invalidates consent")
 e.contracts[0].reward=int(e.contracts[0].reward)-1;host.render()
 begin("available");DirAccess.make_dir_absolute("user://savegame.tmp");click_confirm()
 check(model(e)==original and durable()==bytes,"failed available-offer write keeps original model and both slots")
 DirAccess.remove_absolute("user://savegame.tmp");host.render()
 begin("available");click_confirm()
 check(not e.free_offer_upgrade.is_empty() and e.active_contract_id.is_empty(),"confirmed available upgrade replaces offers without acceptance")
 for order in e.contracts:check(order.control_version=="pilot-free-v1" and order.status=="available","new available offers use the new rules")
 check(e.credits==original.credits and e.jobs_today==original.jobs_today and e.story_state==original.story_state,"offer upgrade invents no cargo handoff or job completion")
 await close_shop()

func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated empty XDG_DATA_HOME required");quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Fixture refuses an existing profile; use an empty isolated XDG_DATA_HOME");quit(2);return
 test_entry_helpers();test_empty_old_entry();test_loaded_inflight_deferred();test_deferred_recovery_write_failure()
 await test_title_preview_no_write()
 await test_cancel_stale_and_success()
 await test_guards_and_available()
 clear_files();print("FREE_ORDER_ENTRY_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)

# Temporary exact-value diagnostics. No epsilon/rounding and no assertion change.
func _entry_diagnostic_stage(stage:String,left:Dictionary,right:Dictionary) -> void:
 for field in ["contracts","history","last_settlement"]:
  var counts:Dictionary={"numeric_type_only":0,"value_changes":0,"type_changes":0,"shape_changes":0}
  var numeric_examples:Array=[];var changed_examples:Array=[]
  _entry_diagnostic_diff(left.get(field),right.get(field),field,counts,numeric_examples,changed_examples)
  print("ENTRY_DIAGNOSTIC ",JSON.stringify({"stage":stage,"field":field,"variant_equal":left.get(field)==right.get(field),"exact_numeric_equal":Econ.Shape_equal(left.get(field),right.get(field)),"counts":counts,"numeric_examples":numeric_examples,"changed_examples":changed_examples},"",true,true))

func _entry_diagnostic_diff(a:Variant,b:Variant,path:String,counts:Dictionary,numeric:Array,changed:Array) -> void:
 var a_number:bool=a is int or a is float
 var b_number:bool=b is int or b is float
 if a_number and b_number:
  if a==b:
   if typeof(a)!=typeof(b):
    counts.numeric_type_only+=1
    if numeric.size()<6:numeric.append(_entry_diagnostic_value(path,a,b))
  else:
   counts.value_changes+=1
   if changed.size()<16:changed.append(_entry_diagnostic_value(path,a,b))
  return
 if a is Dictionary and b is Dictionary:
  for key in a:
   if b.has(key):_entry_diagnostic_diff(a[key],b[key],path+"."+str(key),counts,numeric,changed)
   else:
    counts.shape_changes+=1
    if changed.size()<16:changed.append({"path":path+"."+str(key),"change":"removed_key"})
  for key in b:
   if not a.has(key):
    counts.shape_changes+=1
    if changed.size()<16:changed.append({"path":path+"."+str(key),"change":"added_key"})
  return
 if a is Array and b is Array:
  if a.size()!=b.size():
   counts.shape_changes+=1
   if changed.size()<16:changed.append({"path":path,"change":"array_size","left":a.size(),"right":b.size()})
  for index in mini(a.size(),b.size()):_entry_diagnostic_diff(a[index],b[index],path+"["+str(index)+"]",counts,numeric,changed)
  return
 if typeof(a)!=typeof(b):
  counts.type_changes+=1
  if changed.size()<16:changed.append(_entry_diagnostic_value(path,a,b))
 elif a!=b:
  counts.value_changes+=1
  if changed.size()<16:changed.append(_entry_diagnostic_value(path,a,b))

func _entry_diagnostic_value(path:String,a:Variant,b:Variant) -> Dictionary:
 var value:Dictionary={"path":path,"left_type":type_string(typeof(a)),"right_type":type_string(typeof(b)),"left":a,"right":b}
 if a is int or a is float:value.left_float64_bits=PackedFloat64Array([float(a)]).to_byte_array().hex_encode()
 if b is int or b is float:value.right_float64_bits=PackedFloat64Array([float(b)]).to_byte_array().hex_encode()
 return value
