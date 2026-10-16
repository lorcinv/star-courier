extends SceneTree
const Econ=preload("res://scripts/economy.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Main=preload("res://scripts/main.gd")
class StartupProbe extends Main:
 var trace:Array=[]
 func _build_ui() -> void:
  trace.append("build");world=Node3D.new();add_child(world)
 func _apply_quality() -> void:pass
 func render() -> void:trace.append("render")
 func save_game() -> bool:
  trace.append("save_start");var result:bool=super.save_game();trace.append("saved" if result else "failed");return result
 func notify(message:String) -> void:trace.append("notice:"+message)
 func _process(_delta:float) -> void:pass
 func _restore_story_dialogue() -> void:pass
 func _resume_dispatch() -> void:pass
class UnsafeResumeProbe extends Main:
 func _build_ui() -> void:
  world=Node3D.new();add_child(world)
 func _apply_quality() -> void:pass
 func render() -> void:pass
 func notify(_message:String) -> void:pass
 func _process(_delta:float) -> void:pass
 func _restore_story_dialogue() -> void:pass
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func exact(a:Variant,b:Variant) -> bool:
 return JSON.stringify(JSON.parse_string(JSON.stringify(a,"",true,true)),"",true,true)==JSON.stringify(JSON.parse_string(JSON.stringify(b,"",true,true)),"",true,true)
func recovery_only(app) -> bool:
 return app.economy.review_load_blocked and app.world==null and app.hud==null and app.sim==null and app.courier_input==null and app.get_child_count()==1 and app.get_child(0) is Label and not app.is_processing_input() and not app.is_processing_unhandled_key_input()
func clean() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func write_raw(data:Dictionary,path:String="user://savegame.json") -> void:
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data,"",true,true));file.close()
func disk(path:String="user://savegame.json") -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func fixture(seed_value:int=9142) -> Dictionary:
 clean();var e=Econ.new();e.enable_extreme_mode();e.story_state=Stories.initial_state(seed_value);e.enable_story_mode();e.starter_stock(Extreme.starter_design(),Extreme.starter_launcher());e.enable_seeded_offers(seed_value)
 if not e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}):push_error("fixture save failed")
 return disk()
func run() -> void:
 var base:Dictionary=fixture()
 var legacy:Dictionary=base.duplicate(true);legacy.erase("offer_generation_state");legacy.settings.erase("offer_generation_schema")
 for bad in [null,"broken",[],{},14.75,-1,2147483647,true]:
  clean();var raw:Dictionary=legacy.duplicate(true);raw.story_state.world_seed=bad;write_raw(raw)
  var before:String=FileAccess.get_file_as_string("user://savegame.json");var e=Econ.new()
  check(e.load_state().is_empty() and e.review_load_blocked,"reject original malformed identity seed before normalization: "+str(bad))
  check(not e.save_state([],[],{}) and before==FileAccess.get_file_as_string("user://savegame.json"),"rejected identity bytes cannot be overwritten: "+str(bad))
  var app=StartupProbe.new();root.add_child(app)
  check(app.world==null and not app.is_processing() and not app.trace.has("build") and before==FileAccess.get_file_as_string("user://savegame.json"),"controller cannot expose or replace malformed identity: "+str(bad))
  app.queue_free();await process_frame
 clean();var missing:Dictionary=legacy.duplicate(true);missing.story_state.erase("world_seed");write_raw(missing)
 var missing_seed=Econ.new();check(missing_seed.load_state().is_empty() and missing_seed.review_load_blocked,"nonempty saved identity cannot invent its missing seed")
 for valid_seed in [0.0,9142.0,2147483646.0]:
  clean();var raw:Dictionary=legacy.duplicate(true);raw.story_state.world_seed=valid_seed;write_raw(raw)
  var e=Econ.new();check(not e.load_state().is_empty() and not e.review_load_blocked and e.story_state.world_seed==valid_seed,"exact whole-valued JSON identity seed survives: "+str(valid_seed))
 for absent in ["empty","missing"]:
  clean();var raw:Dictionary=legacy.duplicate(true)
  if absent=="empty":raw.story_state={}
  else:raw.erase("story_state")
  write_raw(raw);var first=Econ.new();var second=Econ.new();first.load_state();second.load_state()
  check(not first.review_load_blocked and exact(first.story_state,second.story_state),"genuine pre-story absence retains deterministic legacy migration: "+absent)
 clean();var corrupt:Dictionary=legacy.duplicate(true);corrupt.story_state.world_seed="broken";write_raw(corrupt);write_raw(legacy,"user://savegame.backup.json")
 var backup_before:String=FileAccess.get_file_as_string("user://savegame.backup.json")
 var recovered=StartupProbe.new();root.add_child(recovered)
 check(not recovered.economy.review_load_blocked and int(recovered.economy.story_state.world_seed)==9142 and int(disk().offer_generation_state.world_seed)==9142,"startup recovers authoritative seed from valid backup")
 check(FileAccess.get_file_as_string("user://savegame.backup.json")==backup_before,"malformed primary never replaces valid backup during startup save")
 check(recovered.trace.find("saved")>=0 and recovered.trace.find("saved")<recovered.trace.find("build"),"recovered startup commits before constructing input or world")
 recovered.queue_free();await process_frame
 # All saved offer content, including future client/parcel/story, is opaque.
 for status in ["available","accepted"]:
  clean();var raw:Dictionary=base.duplicate(true);var saved:Dictionary=raw.contracts[0]
  saved.generation={"version":"seeded-offers-v999","future_payload":{"layout":"opaque"}};saved.client="未来客人";saved.cargo="未来包裹";saved.story="保持这条原始故事";saved.status=status
  if status=="accepted":raw.active_contract_id=saved.contract_id
  var original:Dictionary=saved.duplicate(true);write_raw(raw)
  var e=Econ.new();e.load_state();e.enable_extreme_mode();e.enable_story_mode();e.enable_seeded_offers(12)
  check(exact(e.contracts[0],original),"current story enablement preserves complete future snapshot: "+status)
  check(e.save_state(base.design,base.launcher,base.settings) and exact(disk().contracts[0],original),"future snapshot resave is exact: "+status)
  var app=StartupProbe.new();root.add_child(app)
  check(exact(app.economy.contracts[0],original) and exact(disk().contracts[0],original),"inherited Main startup keeps future snapshot opaque: "+status)
  app.queue_free();await process_frame
 # Block actual temporary writes: no UI may expose an unsaved new morning.
 clean();var empty:Dictionary=base.duplicate(true);empty.contracts=[];write_raw(empty);write_raw(base,"user://savegame.backup.json")
 var primary_before:String=FileAccess.get_file_as_string("user://savegame.json");backup_before=FileAccess.get_file_as_string("user://savegame.backup.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var blocked=StartupProbe.new();root.add_child(blocked)
 check(blocked.economy.review_load_blocked and blocked.world==null and not blocked.is_processing() and not blocked.trace.has("render"),"failed initial save keeps newly authored offers outside all interactive presentation")
 var order_id:String=blocked.economy.contracts[0].contract_id;blocked._action("accept_contract",order_id);blocked._action("next_day",null);blocked._on_focus_entered();blocked._on_focus_exited();blocked.start_flight(false)
 check(blocked.economy.contracts[0].status=="available" and blocked.sim==null,"recovery-only controller cannot accept or launch unsaved offer")
 check(primary_before==FileAccess.get_file_as_string("user://savegame.json") and backup_before==FileAccess.get_file_as_string("user://savegame.backup.json"),"startup failure preserves primary and backup exactly")
 blocked.queue_free();await process_frame;DirAccess.remove_absolute("user://savegame.tmp")
 var retry=StartupProbe.new();root.add_child(retry)
 check(not retry.economy.review_load_blocked and disk().contracts.size()==2 and exact(retry.economy.contracts,disk().contracts),"reopening after storage recovery publishes only persisted generated offers")
 check(retry.trace.find("saved")<retry.trace.find("build") and retry.trace.find("saved")<retry.trace.find("render"),"save completes before the first build and render")
 retry.queue_free();await process_frame
 # Fresh-shop failure has the same gate, without fabricating a saved file.
 clean();DirAccess.make_dir_absolute("user://savegame.tmp");var fresh=StartupProbe.new();root.add_child(fresh)
 check(fresh.economy.review_load_blocked and fresh.world==null and not FileAccess.file_exists("user://savegame.json"),"new shop remains unexposed when its first commit fails")
 fresh.queue_free();await process_frame
 # Startup save cannot advance or reinterpret an existing formal timeline.
 clean();write_raw(base);var flight=Econ.new();flight.load_state();flight.enable_story_mode();var cid:String=flight.contracts[0].contract_id;flight.accept_contract(cid);flight.mark_cargo_loaded(cid);flight.begin_dispatch(base.design,base.launcher)
 flight.in_flight.ticks=120;flight.in_flight.elapsed=1.0;flight.in_flight.input_commands=[{"tick":0,"vertical":0.0,"boost":false,"active":false}]
 var committed:Dictionary=flight.in_flight.duplicate(true);flight.save_state(base.design,base.launcher,base.settings)
 var resume=StartupProbe.new();root.add_child(resume)
 check(exact(resume.economy.in_flight,committed) and exact(disk().in_flight,committed),"deferred in-flight startup preserves formal timeline and frozen route")
 resume.queue_free();await process_frame
 var safe_flight:Dictionary=disk()
 for bad_kind in ["ticks","protocol","missing_route"]:
  clean();var unsafe:Dictionary=safe_flight.duplicate(true)
  match bad_kind:
   "ticks":unsafe.in_flight.ticks=-1
   "protocol":unsafe.in_flight.control_version="pilot-v999"
   "missing_route":unsafe.in_flight.erase("route")
  unsafe.contracts=[] # No unrelated offer authoring during recovery.
  write_raw(unsafe);write_raw(safe_flight,"user://savegame.backup.json")
  primary_before=FileAccess.get_file_as_string("user://savegame.json");backup_before=FileAccess.get_file_as_string("user://savegame.backup.json")
  var unsafe_app=UnsafeResumeProbe.new();root.add_child(unsafe_app);await process_frame
  var expected_block:bool=recovery_only(unsafe_app) if bad_kind in ["protocol","missing_route"] else (unsafe_app.pilot_resume_blocked and unsafe_app.sim==null and is_instance_valid(unsafe_app.world))
  check(expected_block and unsafe_app.economy.contracts.is_empty(),"unsafe replay refuses at its expected boundary before new offers or simulation: "+bad_kind)
  check(not unsafe_app.save_game() and primary_before==FileAccess.get_file_as_string("user://savegame.json") and backup_before==FileAccess.get_file_as_string("user://savegame.backup.json"),"unsafe replay startup preserves primary and good backup: "+bad_kind)
  unsafe_app.queue_free();await process_frame
 # Opaque identities may complete supported frozen physics. Their authentic
 # client receives generic fact-based copy, never a current character's voice.
 for actor in ["human_courier","future_actor",""]:
  clean();var raw:Dictionary=base.duplicate(true);raw.contracts[0].generation={"version":"seeded-offers-v999"};raw.contracts[0].client="未来客户";raw.contracts[0].cargo="未来包裹";raw.contracts[0].story="保持原始说明";raw.contracts[0].appearance_id=actor;write_raw(raw)
  var e=Econ.new();e.load_state();e.enable_story_mode();var id:String=e.contracts[0].contract_id;var prior_story:Dictionary=e.story_state.duplicate(true)
  check(e.accept_contract(id).ok and e.mark_cargo_loaded(id).ok and e.begin_dispatch(base.design,base.launcher).ok,"future identity can commit supported frozen flight: "+actor)
  var result:Dictionary=e.settle_contract_and_save(id,{"integrity":1.0,"energy_used":120.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},20.0,true,base.design,base.launcher,base.settings)
  check(result.ok and e.in_flight.is_empty() and e.settled_ids.has(id),"future identity reaches one saved formal settlement: "+actor)
  check(exact(e.story_state,prior_story) and e.story_conversation(id,"result").is_empty() and e.story_actor(id).is_empty(),"future identity does not advance or impersonate current story: "+actor)
  check(e.contracts[0].appearance_id==actor and e.contracts[0].client=="未来客户" and e.review_state.pending[id].appearance_id=="" and e.review_state.pending[id].client=="未来客户" and e.customer_reviews().is_empty(),"generic pending facts retain real future client without rewriting snapshot: "+actor)
  e.close_day();check(e.next_day_and_save(base.design,base.launcher,base.settings).ok and e.customer_reviews().size()==1 and e.customer_reviews()[0].client=="未来客户" and e.customer_reviews()[0].rating==5,"future identity review publishes once on next day: "+actor)
 clean();print("SEEDED_STARTUP_RECOVERY passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
