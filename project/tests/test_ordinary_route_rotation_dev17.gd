extends SceneTree
## dev17 explicit five-candidate successor to the immutable dev06 baseline.
## Expected changes are mapped in qa/mosslight-rotation-test-migration.md.
## Fresh isolated HOME/XDG only. Old four-candidate assertions remain in dev06.
## Uses actual Main's capability guard and production Economy/save/Title entry.
## Progression and receipt inputs below are explicitly synthetic ledger fixtures,
## not played deliveries. Legacy snapshots are captured from unchanged Economy.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Main=preload("res://scripts/main.gd")
const TitleScene=preload("res://scenes/demo_title.tscn")
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
const SAVE_NAMES=["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]
const SNAPSHOT_KEYS=["contracts","in_flight","last_settlement","settled_ids","history","offer_generation_state","story_state","review_state","force_offer_upgrade","free_offer_upgrade","accepted_free_swaps"]
var passed:int=0
var failed:int=0
var guard_host
var title
var settings:Dictionary={"volume":0.0,"reduced_motion":true}
var design:Array=Profile.starter_design()
var pad:Array=Profile.starter_launcher()

class Catalog extends "res://scripts/economy.gd":
 var catalog:Array=[]
 func routes() -> Array:return catalog.duplicate(true)

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func ids(offers:Array) -> Array:
 var result:Array=[]
 for order in offers:result.append(int(order.id))
 return result
func gate(route:Dictionary) -> String:return guard_host._recovery_route_error(route)
func restricted(route:Dictionary,allowed:Array) -> String:
 var error:String=gate(route)
 return error if not error.is_empty() else ("test-only capability denial" if not int(route.id) in allowed else "")
func model(d:int=3,rep:int=4,allowed:Variant=null):
 var e=Econ.new();e.enable_force_mode();e.day=d;e.reputation=rep;e.deliveries=2;e.credits=600
 e.story_state=Econ.Stories.initial_state(73)
 e.route_guard=gate if allowed==null else restricted.bind(allowed)
 return e
func candidates(e) -> Array:
 var result:Array=[]
 # Observe actual pre-admission capability probes from ensure_contracts.
 # A new ID7 probe can pass its art guard, then be excluded because the final
 # pool is mixed. Pair assertions below separately prove that exclusion.
 var original:Callable=e.route_guard
 e.route_guard=func(route:Dictionary) -> String:
  var error:String=original.call(route) if original.is_valid() else ""
  if error.is_empty() and not route.has("contract_id"):result.append(int(route.id))
  return error
 e.ensure_contracts();e.route_guard=original
 return result
func state(e) -> Dictionary:
 var result:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result
func bytes() -> Array:
 var result:Array=[]
 for name in SAVE_NAMES:result.append(FileAccess.get_file_as_bytes("user://"+name) if FileAccess.file_exists("user://"+name) else null)
 return result
func clear_slots() -> void:
 for name in SAVE_NAMES:
  var path:String="user://"+name
  if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
  elif DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func write_bytes(path:String,value:PackedByteArray) -> void:
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file!=null:file.store_buffer(value);file.close()
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func frames(count:int=3) -> void:
 for unused in count:await process_frame
func close_title() -> void:
 var refs:Array=[]
 if is_instance_valid(title):
  for player in title.find_children("*","AudioStreamPlayer",true,false):AudioClock.watch_player(player,refs)
  root.remove_child(title);title.free();title=null
 await frames()
 if not refs.is_empty():
  var released:Dictionary=await AudioClock.wait_released(self,refs)
  check(bool(released.ok),"Title/Main audio owners finish releasing at test teardown")
func finish() -> void:
 await close_title()
 if is_instance_valid(guard_host):guard_host.free()
 print("ORDINARY_ROUTE_ROTATION_DEV17 passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)

func test_cycles() -> void:
 var cases:Array=[
  {"pool":[0],"pairs":[[0,0]]},
  {"pool":[0,1],"pairs":[[0,1],[1,0]]},
  {"pool":[0,1,6],"pairs":[[0,1],[1,6],[6,0]]},
  {"pool":[0,1,2,6],"pairs":[[0,2],[1,6],[2,0],[6,1]]},
  {"pool":[0,1,2,6,7],"pairs":[[0,2],[1,6],[2,7],[6,0],[7,1]]},
  {"pool":[0,1,2],"pairs":[[0,1],[1,2],[2,0]]}
 ]
 for row in cases:
  var a_counts:Dictionary={};var b_counts:Dictionary={}
  for index in row.pool.size():
   var d:int=index+1;var e=model(d,4,row.pool)
   check(candidates(e)==row.pool,"actual catalog/guard retains fixed eligible order N%d day%d"%[row.pool.size(),d])
   check(ids(e.contracts)==row.pairs[index],"fixed-pool half-offset pair N%d day%d"%[row.pool.size(),d])
   if e.contracts.size()!=2:continue
   var a:int=int(e.contracts[0].id);var b:int=int(e.contracts[1].id)
   a_counts[a]=int(a_counts.get(a,0))+1;b_counts[b]=int(b_counts.get(b,0))+1
   check(a==row.pool[index],"A slot stays exactly day-indexed N%d day%d"%[row.pool.size(),d])
   check(not e.contracts[1].has("recovery_offer") and e.contracts[1].variant=="重货件","non-recovery singleton/filtered B remains a heavy job")
  for id in row.pool:check(a_counts.get(id)==1 and b_counts.get(id)==1,"each fixed-pool ID occupies both slots once: "+str(row.pool)+" / "+str(id))
 var none=model(3,4,[]);var root_before:Dictionary=none.offer_generation_state.duplicate(true)
 none.ensure_contracts()
 check(none.contracts.is_empty() and not none.load_notice.is_empty() and none.offer_generation_state==root_before,"N0 keeps no-route notice and root without modulo")
 for row in [{"rep":0,"day":3,"pool":[0]},{"rep":2,"day":2,"pool":[0,1,6]},{"rep":4,"day":2,"pool":[0,1,2,6,7]},{"rep":12,"day":4,"pool":[0,1,2,6,7]},{"rep":10,"day":2,"pool":[0,1,2,4,6,7]}]:
  var e=model(row.day,row.rep)
  check(candidates(e)==row.pool,"real Main pre-admission capability probes rep%d day%d"%[row.rep,row.day])
  if row.day==2 and row.rep in [2,4,10]:check(ids(e.contracts)==[1,6] and e.contracts[1].deadline==83.0 and e.contracts[1].time_limit==110.0,"day2 rep%d retains exact heavy lunar introduction, including mixed-pool exclusion"%row.rep)
 # The five-item ordinary force-v2 pool works without a bound guard at rep4.
 var unbound=model(3,4);unbound.route_guard=Callable();unbound.ensure_contracts()
 check(ids(unbound.contracts)==[2,7],"guard presence itself is not a rotation opt-in")
 var in_flight_only=model(3,4);in_flight_only.in_flight={"contract_id":"D3-B","route":{"id":6}}
 var flight_before:Dictionary=in_flight_only.in_flight.duplicate(true);in_flight_only.ensure_contracts()
 check(in_flight_only.contracts.is_empty() and in_flight_only.in_flight==flight_before,"an existing in-flight snapshot alone still blocks new authoring")

func test_horizon_and_terms() -> void:
 var expected:Array=[[1,6],[2,7],[6,0],[7,1],[0,2],[1,6],[2,7]]
 var expected_rewards:Array=[660,735,605,680,605,660,735]
 var total:int=0;var catalog:Dictionary={}
 for route in model().routes():catalog[int(route.id)]=route
 for d in range(2,9):
  var e=model(d,(d-1)*4);e.ensure_contracts()
  check(ids(e.contracts)==expected[d-2],"day%d modeled two-intact-deliveries progression pair"%d)
  if e.contracts.size()!=2:continue
  var reward:int=int(e.contracts[0].reward)+int(e.contracts[1].reward);total+=reward
  check(reward==expected_rewards[d-2],"day%d unchanged per-route/slot reward composition"%d)
  for slot in 2:
   var order:Dictionary=e.contracts[slot];var base:Dictionary=catalog[int(order.id)]
   check(order.weight==float(base.weight)*(1.55 if slot==1 else 1.0) and order.reward==int(base.reward)+(55 if slot==1 else 0) and order.deadline==float(base.deadline)+(3.0 if slot==1 else 0.0),"day%d slot%d exact existing unrounded commercial decoration"%[d,slot])
   for key in ["required","time_limit","gravity","distance","destination_y","delivery_radius","max_delivery_speed","pilot_battery_multiplier","pilot_energy_tariff"]:check(order[key]==base[key],"unchanged route term "+key+" day%d slot%d"%[d,slot])
   check(Profile.validation_error(order).is_empty() and gate(order).is_empty(),"selected day%d slot%d remains protocol/capability-valid"%[d,slot])
  var before:Dictionary=state(e);e.ensure_contracts();e.available_contracts();e.contract_by_id("D%d-B"%d)
  check(state(e)==before,"repeated queries never reselect day%d"%d)
  var twin=model(d,(d-1)*4);twin.ensure_contracts()
  check(e.contracts==twin.contracts,"identical fresh inputs yield identical realized snapshots day%d"%d)
 check(total==4680,"days2-8 new-directory gross face reward is4680; the dev06 baseline4455 remains preserved in its original test")
 check(catalog[1].distance==catalog[2].distance and catalog[1].destination_y==catalog[2].destination_y and catalog[1].hazards==catalog[2].hazards,"orbital IDs1/2 share geometry; rotation adds no route content")

func test_recovery() -> void:
 var rows:Array=[
  {"deliveries":1,"credits":220,"last":{},"recovery":true},
  {"deliveries":2,"credits":219,"last":{},"recovery":true},
  {"deliveries":2,"credits":220,"last":{"success":false},"recovery":true},
  {"deliveries":2,"credits":220,"last":{},"recovery":false},
  {"deliveries":2,"credits":221,"last":{"success":true},"recovery":false},
  {"deliveries":3,"credits":220,"last":{"success":true},"recovery":false}
 ]
 for index in rows.size():
  var row:Dictionary=rows[index];var e=model();e.deliveries=row.deliveries;e.credits=row.credits;e.last_settlement=row.last
  # An earlier failure cannot replace the existing latest-settlement predicate.
  e.history=[{"success":false}];e.ensure_contracts()
  check(e.needs_recovery_orders()==row.recovery,"independent recovery predicate boundary %d"%index)
  check(ids(e.contracts)==([0,0] if row.recovery else [2,7]),"recovery precedence or ordinary pair boundary %d"%index)
  if row.recovery:
   check(e.contracts[0].weight==1.0 and e.contracts[1].weight==1.0 and e.contracts[0].reward==220 and e.contracts[1].reward==220 and e.contracts[1].deadline==35.0 and e.contracts[1].variant=="轻件续单" and e.contracts[0].recovery_offer and e.contracts[1].recovery_offer,"recovery retains light terms and existing B deadline/label")
 var absent=model(2,4,[1,2]);absent.credits=219;absent.ensure_contracts()
 check(ids(absent.contracts)==[2,2] and absent.contracts[1].weight==absent.contracts[0].weight,"synthetic ground-unavailable recovery keeps original default pair/decoration")
 var low=model(3,1);low.ensure_contracts();check(ids(low.contracts)==[0,0] and low.contracts[1].weight==1.55,"low-reputation non-recovery singleton is still ordinary heavy B")

func test_exclusions() -> void:
 for mode in ["autonomous-v5","pilot-v1","pilot-v2","pilot-v3","pilot-free-v1"]:
  var e=model(3,4);e.flight_mode=mode;e.ensure_contracts()
  check(ids(e.contracts)==[2,2],"legacy/free-v1 selection remains A index and catalog back: "+mode)
 var early=model(1,10);var early_probes:Array=candidates(early)
 check(early_probes==[0,1,2,4,6,7],"mixed pool probes new art before its separate ordinary-only admission decision")
 check(ids(early.contracts)==[0,6],"mixed early legacy ID4 pool excludes fresh ID7 and retains old pair wholesale")
 var unbound=model(4,12);unbound.route_guard=Callable();unbound.ensure_contracts()
 check(ids(unbound.contracts)==[3,6],"unbound wormhole/Moon mixed catalog keeps historical pair")
 var original:Array=model().routes().filter(func(route):return int(route.id) in [0,1,2,6])
 for key in ["unknown_id","missing_policy","wrong_policy","wrong_version","invalid_force","generation"]:
  var e=Catalog.new();e.enable_force_mode();e.day=3;e.reputation=4;e.deliveries=2;e.credits=600;e.catalog=original.duplicate(true)
  match key:
   "unknown_id":e.catalog[1].id=99
   "missing_policy":e.catalog[1].erase("economy_policy")
   "wrong_policy":e.catalog[1].economy_policy="future"
   "wrong_version":e.catalog[1].control_version="pilot-v3"
   "invalid_force":e.catalog[1].free_drive_throttle=0.123
   "generation":e.catalog[1].generation={"version":"future"}
  e.ensure_contracts()
  check(ids(e.contracts)==[2,6],"one nonregistered/invalid candidate excludes the whole pool: "+key)
 # Direct helper-only inputs cannot safely pass the preexisting catalog loop.
 if Econ.new().has_method("_ordinary_force_pool"):
  var e=Econ.new()
  check(not e.call("_ordinary_force_pool",[null]) and not e.call("_ordinary_force_pool",[]) and not e.call("_ordinary_force_pool",original+[original[0]]),"eligibility rejects nondictionaries, N0, and duplicated N5")

func ready_save(e) -> void:
 e.starter_stock(design,pad);e.enable_story_mode()
 e.offer_generation_state={"version":Econ.AuthoringPolicy.PIRATE_VERSION,"world_seed":73,"ordinary_policy":Econ.AuthoringPolicy.Ordinary.CURRENT_VERSION,"introduced_day":0,"pirate_introduced_day":0}
func capture_legacy() -> void:
 clear_slots();var e=model(3,8);ready_save(e)
 check(ids(e.contracts)==[2,6],"legacy capture genuinely uses unchanged day3 A2/B6 selection")
 for status in ["available","accepted","in_flight","settled"]:
  if status=="accepted":
   check(e.accept_contract("D3-B").ok,"legacy fixture accepts B through production API");e.mark_story_seen("D3-B","D3-B/accept");check(e.mark_cargo_loaded("D3-B").ok,"legacy fixture loads accepted B")
  elif status=="in_flight":check(e.begin_dispatch(design,pad).ok,"legacy fixture snapshots formal B dispatch")
  elif status=="settled":check(e.settle_contract("D3-B",{"integrity":100.0},10.0,true).ok,"synthetic legacy ledger receipt uses production settlement, not played flight")
  check(e.save_state(design,pad,settings),"legacy "+status+" snapshot saves")
  write_bytes("user://legacy-"+status+".json",FileAccess.get_file_as_bytes("user://savegame.json"))
  print("LEGACY_FIXTURE ",status," ",ProjectSettings.globalize_path("user://legacy-"+status+".json"))

func test_legacy_snapshots(directory:String) -> void:
 for status in ["available","accepted","in_flight","settled"]:
  clear_slots();var source:String=directory.path_join("legacy-"+status+".json")
  if not check(FileAccess.file_exists(source),"unchanged-economy captured fixture present: "+status):continue
  var original:PackedByteArray=FileAccess.get_file_as_bytes(source);write_bytes("user://savegame.json",original)
  var raw:Dictionary=JSON.parse_string(original.get_string_from_utf8());var e=Econ.new();e.route_guard=gate;e.load_state(true)
  check(not e.review_load_blocked and ids(e.contracts)==[2,6],"old day3 "+status+" pair loads despite new B7 formula")
  var before:Dictionary=state(e);e.enable_force_mode();e.ensure_contracts();e.available_contracts();e.contract_by_id("D3-B")
  check(state(e)==before and FileAccess.get_file_as_bytes("user://savegame.json")==original,"old "+status+" reads/enable preserve model and exact durable bytes")
  for key in SNAPSHOT_KEYS:
   if raw.has(key):
    # Existing load normalizers reconstruct story/review counters as ints.
    # Route, flight and receipt snapshots themselves remain strict Variants.
    if key in ["story_state","review_state"]:
     print("LEGACY_NORMALIZATION ",JSON.stringify({"status":status,"field":key,"variant_equal":e.get(key)==raw[key],"exact_values":Econ.Shape_equal(e.get(key),raw[key])}))
     check(Econ.Shape_equal(e.get(key),raw[key]),"old "+status+" exact saved values, existing normalizer: "+key)
    else:check(e.get(key)==raw[key],"old "+status+" exact saved snapshot field "+key)
  check(e.save_state(design,pad,settings),"old "+status+" can be resaved without migration or new marker")
  var saved:Dictionary=disk()
  for key in SNAPSHOT_KEYS:
   if raw.has(key):check(Econ.Shape_equal(saved.get(key),raw[key]),"resave retains old "+status+" field "+key)
  check(saved.keys()==raw.keys() and saved.settings.keys()==raw.settings.keys() and saved.offer_generation_state==raw.offer_generation_state,"old "+status+" retains root/settings key sets and exact authoring root")
  if status=="available":await test_title_continuation([2,6],"old-saved-B")

func test_next_day_rollback() -> void:
 clear_slots();var e=model(2,4);ready_save(e)
 check(e.close_day().ok and e.save_state(design,pad,settings),"synthetic day2 night fixture saved")
 var before:Dictionary=state(e);var slots:Array=bytes();var root_before:Dictionary=e.offer_generation_state.duplicate(true)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var blocked:Dictionary=e.next_day_and_save(design,pad,settings)
 check(not blocked.ok and state(e)==before and bytes()==slots,"blocked save rolls back night/morning offers/root/reviews/ledger and all durable slots")
 DirAccess.remove_absolute("user://savegame.tmp")
 var next:Dictionary=e.next_day_and_save(design,pad,settings)
 check(next.ok and e.day==3 and ids(e.contracts)==[2,7],"retry authors and saves exactly one new day3 B mosslight")
 print("ROOT_REPRESENTATION ",JSON.stringify({"model_variant_equal":e.offer_generation_state==root_before,"disk_variant_equal":disk().offer_generation_state==root_before,"disk_exact_values":Econ.Shape_equal(disk().offer_generation_state,root_before)}))
 check(e.offer_generation_state==root_before and Econ.Shape_equal(disk().offer_generation_state,root_before),"rotation adds no schema/version/introduction marker to exact-key root")
 var current:Dictionary=state(e);slots=bytes()
 check(not e.next_day_and_save(design,pad,settings).ok and state(e)==current and bytes()==slots,"repeated next-day request cannot duplicate or reselect current morning")

func capture_slots(label:String) -> void:
 for name in ["savegame.json","savegame.backup.json"]:
  if not FileAccess.file_exists("user://"+name):continue
  var destination:String="user://"+label+"-"+name
  write_bytes(destination,FileAccess.get_file_as_bytes("user://"+name))
  print("TITLE_RAW_CAPTURE ",label," ",destination," sha256=",FileAccess.get_sha256(destination))

func test_title_continuation(expected:Array=[2,7],label:String="new-rotation") -> void:
 # Continue saved snapshots through real entry, retaining raw pre/post files.
 capture_slots(label+"-before")
 var saved:Dictionary=disk();var offers:Array=saved.contracts.duplicate(true);var root_before:Dictionary=saved.offer_generation_state.duplicate(true)
 title=TitleScene.instantiate();root.add_child(title);await frames()
 if DisplayServer.get_name()=="headless":title._focus_entered()
 title._continue_game()
 var deadline:int=Time.get_ticks_msec()+20000
 while title.screen!="game" and not title._opening_failed and Time.get_ticks_msec()<deadline:await process_frame
 if not check(title.screen=="game" and is_instance_valid(title.game),label+" actual Title Continue opens saved morning in Main"):return
 var game=title.game;game.set_process(false);game.world.set_process(false)
 check(not game.economy.review_load_blocked and ids(game.economy.contracts)==expected,label+" real Main exposes the expected saved day3 pair")
 for unused in 3:game.economy.available_contracts();game.render()
 print("TITLE_SNAPSHOT_REPRESENTATION ",JSON.stringify({"label":label,"model_variant_equal":game.economy.contracts==offers,"model_exact_values":Econ.Shape_equal(game.economy.contracts,offers),"disk_variant_equal":disk().contracts==offers,"disk_exact_values":Econ.Shape_equal(disk().contracts,offers)}))
 check(Econ.Shape_equal(game.economy.contracts,offers) and Econ.Shape_equal(game.economy.offer_generation_state,root_before),label+" Main rendering/query/entry preserves exact values, no epsilon or ignored keys")
 check(Econ.Shape_equal(disk().contracts,offers) and Econ.Shape_equal(disk().offer_generation_state,root_before),label+" Main protected entry preserves durable route/commercial snapshots")
 capture_slots(label+"-after")
 await close_title()

func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json"):
  printerr("Use a fresh isolated XDG_DATA_HOME. Existing saves are never deleted by this test.");quit(2);return
 guard_host=Main.new()
 if "--capture-legacy-only" in OS.get_cmdline_user_args():
  check(false,"Capture legacy fixtures with the unchanged dev06 test on its immutable source, never dev17.");await finish();return
 test_cycles();test_horizon_and_terms();test_recovery();test_exclusions()
 var legacy_dir:String=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--legacy-fixtures="):legacy_dir=arg.trim_prefix("--legacy-fixtures=")
 if not legacy_dir.is_empty():await test_legacy_snapshots(legacy_dir)
 else:check(false,"--legacy-fixtures must point to snapshots captured from unchanged Economy")
 test_next_day_rollback();await test_title_continuation();await finish()
