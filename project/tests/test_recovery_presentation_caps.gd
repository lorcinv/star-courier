extends SceneTree
## Recovery capability receipt and save/ownership boundaries. Run only with
## an isolated XDG_DATA_HOME; the harness restores all preexisting save bytes.
const Econ=preload("res://scripts/economy.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
const Moon=preload("res://scripts/pilot_moon_profile.gd")
const Wormhole=preload("res://scripts/pilot_wormhole_profile.gd")
const Bird=preload("res://scripts/protected_bird_offer_v1.gd")
const Meteor=preload("res://scripts/orbital_meteor_offers.gd")
const SAVE_NAMES:Array=["savegame.json","savegame.backup.json","savegame.tmp"]
const STATE_KEYS:Array=["credits","reputation","day","phase","jobs_today","deliveries","research","workshop_tier","history","designs","inventory","contracts","active_contract_id","settled_ids","in_flight","last_settlement","last_trials","story_mode","story_state","review_state","offer_generation_state","load_notice"]
var passed:int=0
var failed:int=0
var preserved:Dictionary={}
var observed_candidates:Array=[]
var observed_reviews:Array=[]
var watched

func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)

func _initialize() -> void:
 for name in SAVE_NAMES:
  if FileAccess.file_exists("user://"+name):preserved[name]=FileAccess.get_file_as_bytes("user://"+name)
 clear_files()
 check(not Caps.group_available("moon") and not Caps.group_available("otherworld") and not Caps.group_available("protected-bird"),"missing special groups remain explicitly closed")
 check(not Caps.group_available("unknown"),"unknown group never becomes available")
 test_markers()
 test_meteor_receipt()
 var good:Dictionary=ordinary_save()
 test_save_priority(good)
 test_mutation_boundaries()
 test_main_runtime_denials()
 test_next_day_rollback()
 test_main_ordering()
 clear_files()
 for name in preserved:write_bytes("user://"+name,preserved[name])
 print("RECOVERY_PRESENTATION_CAPS passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)

func clear_files() -> void:
 for name in SAVE_NAMES:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)

func write_bytes(path:String,bytes:PackedByteArray) -> void:
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file!=null:file.store_buffer(bytes);file.close()

func write_save(path:String,value:Dictionary) -> void:
 write_bytes(path,(" \n"+JSON.stringify(value,"\t",true,true)+"\n").to_utf8_buffer())

func bytes_snapshot() -> Dictionary:
 var result:Dictionary={}
 for name in SAVE_NAMES:
  if FileAccess.file_exists("user://"+name):result[name]=FileAccess.get_file_as_bytes("user://"+name)
 return result

func state(e) -> Dictionary:
 var result:Dictionary={}
 for key in STATE_KEYS:
  var value:Variant=e.get(key)
  result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result

func test_markers() -> void:
 var ordinary:Dictionary={"control_version":"pilot-v3","route_profile":"ordinary","name":"Moon wormhole bird meteor are just words"}
 check(Caps.route_error(ordinary).is_empty(),"ordinary v3 and display words do not imply special art")
 var cases:Array=[
  {"moon_schema":null},{"moon":false},{"route_profile":"moon-surface-v1"},{"route_kind":"moon"},{"destination_id":"moon-regolith-airlock"},
  {"hazards":[{"moon_hardware":false}]},{"pilot_gates":[{"moon_gate":null}]},
  {"control_version":"pilot-v4-wormhole"},{"pilot_profile":"pilot-v4-wormhole"},{"wormhole_schema":null},{"wormhole_portal":[]},
  {"otherworld_background":null},{"route_kind":"wormhole"},{"route_profile":"wormhole-otherworld-v1"},{"hazards":[{"wormhole_hardware":false}]},{"pilot_gates":[{"otherworld":false}]},
  {"control_version":"pilot-v5-protected-bird"},{"ecology":null},{"ecology_schema":false},{"ecology_generator":[]},{"route_profile":"mosslight-protected-bird-v1"},{"generation":{"version":"protected-bird-offers-v1"}}
 ]
 for marker in cases:
  var route:Dictionary=ordinary.duplicate(true);route.merge(marker,true)
  var before:String=JSON.stringify(route)
  check(not Caps.route_error(route).is_empty(),"partial marker closes route: "+JSON.stringify(marker))
  check(JSON.stringify(route)==before,"marker inspection does not rewrite route")
 for marker in [{"orbital_event":null},{"hazards":[{"meteor_event_id":"only-marker"}]},{"generation":{"version":"orbital-meteor-offers-v1"}}]:
  check(not Caps.route_error(marker).is_empty(),"partial meteor marker cannot become ordinary art")

func test_meteor_receipt() -> void:
 # Positive fixture deliberately requires the approved copied runtime receipt.
 check(Caps.group_available("meteor"),"approved meteor manifest and all three imported sprites are ready")
 var root_path:String="user://recovery-meteor-receipt-test/"
 DirAccess.make_dir_recursive_absolute(root_path)
 for name in ["manifest.json","meteor.png","fragment-a.png","fragment-b.png"]:
  if FileAccess.file_exists(Caps.METEOR_ROOT+name):write_bytes(root_path+name,FileAccess.get_file_as_bytes(Caps.METEOR_ROOT+name))
 check(Caps._meteor_receipt_ready(root_path,false),"pinned measured receipt validates exact raw copies")
 for name in ["manifest.json","meteor.png","fragment-a.png","fragment-b.png"]:
  var path:String=root_path+name;var original:PackedByteArray=FileAccess.get_file_as_bytes(path)
  DirAccess.remove_absolute(path)
  check(not Caps._meteor_receipt_ready(root_path,false),"missing meteor member rejects complete group: "+name)
  write_bytes(path,"corrupt".to_utf8_buffer())
  check(not Caps._meteor_receipt_ready(root_path,false),"hash-corrupt meteor member rejects complete group: "+name)
  write_bytes(path,original)
 for name in ["manifest.json","meteor.png","fragment-a.png","fragment-b.png"]:DirAccess.remove_absolute(root_path+name)
 DirAccess.remove_absolute(root_path)
 var e=Econ.new()
 var outcome:Dictionary=Meteor.create_new_offer(e._autonomous_routes()[1],{"version":Meteor.POLICY,"world_seed":73},2,0,Econ.Stories.IDS[0])
 check(outcome.ok and Caps.route_error(outcome.offer).is_empty(),"actual registered meteor offer is available independently of missing special groups")

func ordinary_save() -> Dictionary:
 clear_files()
 var e=Econ.new();e.enable_extreme_mode();e.story_state=Econ.Stories.initial_state(73);e.enable_story_mode();e.enable_seeded_offers(73)
 check(e.save_state([],[],{}),"ordinary seed fixture saves")
 return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))

func special_order(group:String) -> Dictionary:
 var e=Econ.new();var order:Dictionary={}
 if group=="moon":order=Moon.route(e._autonomous_routes()[4])
 elif group=="otherworld":order=Wormhole.route(e._autonomous_routes()[3])
 else:
  return Bird.create_new_offer({"version":Bird.POLICY,"world_seed":73,"introduced_day":5},5,Econ.Stories.IDS[0]).offer
 order.contract_id="D1-A";order.status="available";order.accepted_day=1;order.variant="标准件"
 return order

func test_save_priority(good:Dictionary) -> void:
 for group in ["moon","otherworld","protected-bird"]:
  for status in ["available","accepted","in_flight"]:
   var raw:Dictionary=good.duplicate(true);var order:Dictionary=special_order(group);order.status=status;raw.contracts=[order]
   if status!="available":raw.active_contract_id=order.contract_id
   if status=="in_flight":raw.in_flight={"route":order.duplicate(true),"design":[],"launcher":[],"control_version":order.control_version,"seed":1,"ticks":0,"input_commands":[]}
   if group=="protected-bird":
    raw.day=5;raw.review_state=Econ.Reviews.initial_state(5)
    raw.offer_generation_state={"version":Bird.POLICY,"world_seed":73,"introduced_day":5}
    raw.settings.offer_authoring_policy=Bird.POLICY;raw.settings.protected_bird_schema=1
   check(Econ.new()._valid_save(raw),"valid unsupported route fixture: "+group+" "+status)
   check_blocked_raw(raw,good,group+" "+status+" valid")
   # Adjacent corruption must not authorize replacing an unsupported route
   # with the playable backup, even before structural migrations can run.
   raw.review_state={"invalid":"adjacent-review"}
   check_blocked_raw(raw,good,group+" "+status)
 for marker in [{"moon_schema":null},{"wormhole_portal":null},{"ecology":null}]:
  var raw:Dictionary=good.duplicate(true);raw.contracts[0].merge(marker,true)
  check_blocked_raw(raw,good,"partial saved marker "+JSON.stringify(marker))
 # Even missing top-level arrays must stay raw in unavailable recovery mode.
 var malformed:Dictionary={"contracts":[{"moon_schema":null}],"in_flight":false,"design":false}
 check_blocked_raw(malformed,good,"malformed neighboring snapshot")
 clear_files();write_bytes("user://savegame.json","{broken JSON".to_utf8_buffer());write_save("user://savegame.backup.json",good)
 var before:Dictionary=bytes_snapshot();var restored=Econ.new();restored.route_guard=Caps.route_error;var loaded:Dictionary=restored.load_state()
 check(not restored.review_load_blocked and restored.load_notice.contains("备份") and loaded==good,"unparseable primary still uses valid ordinary backup")
 check(bytes_snapshot()==before,"corrupt-primary fallback itself remains read-only")
 clear_files();write_bytes("user://savegame.json","{broken JSON".to_utf8_buffer());before=bytes_snapshot();restored=Econ.new();restored.route_guard=Caps.route_error;restored.load_state()
 check(restored.review_load_blocked and not restored.save_state([],[],{}) and bytes_snapshot()==before,"unparseable primary without backup is never replaced by new shop")
 var invalid:Dictionary=good.duplicate(true);invalid.workshop_tier=-1
 clear_files();write_save("user://savegame.json",invalid);write_save("user://savegame.backup.json",good);before=bytes_snapshot();restored=Econ.new();restored.route_guard=Caps.route_error;restored.load_state()
 check(not restored.review_load_blocked and restored.load_notice.contains("备份") and bytes_snapshot()==before,"ordinary integrity failure retains established validated-backup priority")

func check_blocked_raw(raw:Dictionary,good:Dictionary,label:String) -> void:
 clear_files();write_save("user://savegame.json",raw);write_save("user://savegame.backup.json",good);write_bytes("user://savegame.tmp","untouched existing tmp".to_utf8_buffer())
 var before:Dictionary=bytes_snapshot();var e=Econ.new();e.route_guard=Caps.route_error;var loaded:Dictionary=e.load_state()
 var parsed_primary:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(e.review_load_blocked and loaded==parsed_primary and not e.load_notice.contains("备份"),"unsupported primary outranks playable backup: "+label)
 var original:Dictionary=state(e);e.enable_extreme_mode();e.enable_story_mode();e.ensure_contracts()
 check(state(e)==original,"blocked startup cannot author or bind: "+label)
 check(not e.accept_contract("D1-A").ok and not e.begin_dispatch([],[]).ok and not e.next_day_and_save([],[],{}).ok and not e.save_state([],[],{}),"blocked session rejects ownership and saves: "+label)
 check(bytes_snapshot()==before,"primary backup and tmp remain byte-identical: "+label)

func test_mutation_boundaries() -> void:
 for group in ["moon","otherworld","protected-bird"]:
  var e=Econ.new();e.route_guard=Caps.route_error;e.contracts=[special_order(group)];e.reputation=100
  var before:Dictionary=state(e)
  check(not e.accept_contract(e.contracts[0].contract_id).ok and state(e)==before,"accept preflights before ownership: "+group)
  e.contracts[0].status="accepted";e.active_contract_id=e.contracts[0].contract_id;before=state(e)
  check(not e.mark_cargo_loaded(e.active_contract_id).ok and state(e)==before,"cargo preflights before loaded flag: "+group)
  check(not e.begin_dispatch([],[]).ok and e.trial_route().is_empty() and state(e)==before,"trial/formal dispatch preflight before ledger mutation: "+group)
 var legacy=Econ.new();legacy.contracts=[special_order("moon")];legacy.reputation=100
 check(not legacy.route_guard.is_valid() and legacy.accept_contract("D1-A").ok,"unbound model retains historical Moon acceptance")

func test_main_runtime_denials() -> void:
 # Do not enter the tree or build World. Any accidental ownership access here
 # would touch a null world; the denial must happen before that point.
 var main_script=load("res://scripts/main.gd")
 for group in ["moon","otherworld","protected-bird"]:
  var game=main_script.new();game.economy.route_guard=Caps.route_error
  game.economy.contracts=[special_order(group)];game.economy.reputation=100
  var before:Dictionary=state(game.economy)
  game._action("accept_contract",game.economy.contracts[0].contract_id)
  check(state(game.economy)==before and game.page=="hub" and game.world==null,"Main acceptance blocks before navigation/owner: "+group)
  var order:Dictionary=game.economy.contracts[0];order.status="accepted";game.economy.active_contract_id=order.contract_id
  before=state(game.economy)
  for trial in [true,false]:
   game.start_flight(trial)
   check(state(game.economy)==before and game.sim==null and game.page=="hub","Main dispatch blocks before cargo/simulation/save: "+group)
  game._configure_flight(false,[],[],order,true)
  check(game.pilot_resume_blocked and game.sim==null and game.flight_order.is_empty() and game.page=="hub" and state(game.economy)==before,"configure denies before flight owner: "+group)
  game.pilot_resume_blocked=false
  game.economy.in_flight={"route":order.duplicate(true),"design":[],"launcher":[],"control_version":order.control_version,"seed":1,"ticks":0,"input_commands":[]}
  before=state(game.economy);var files:Dictionary=bytes_snapshot()
  game._resume_dispatch()
  check(game.pilot_resume_blocked and game.sim==null and game.page=="hub" and state(game.economy)==before and bytes_snapshot()==files,"resume denies without replay/ownership/save: "+group)
  game.free()

func observe_guard(route:Dictionary) -> String:
 observed_candidates.append(route.duplicate(true));observed_reviews.append(watched.review_state.duplicate(true))
 return Caps.route_error(route)

func test_next_day_rollback() -> void:
 clear_files()
 var e=Econ.new();e.day=2;e.enable_extreme_mode();e.story_state=Econ.Stories.initial_state(73);e.enable_story_mode();e.enable_seeded_offers(73)
 var id:String=str(e.contracts[0].contract_id)
 check(e.accept_contract(id).ok and e.mark_cargo_loaded(id).ok and e.begin_dispatch([],[]).ok,"real receipt fixture dispatches")
 check(e.settle_contract(id,{"integrity":1.0},10.0,true).ok,"real receipt fixture creates pending reviews")
 e.reputation=7;check(e.close_day().ok and e.save_state([],[],{}),"night fixture persists before unsupported next-day boundary")
 var original:Dictionary=state(e);var original_files:Dictionary=bytes_snapshot();var pending:Dictionary=e.review_state.duplicate(true)
 watched=e;e.route_guard=observe_guard
 var seen_signature:String=""
 for attempt in 3:
  observed_candidates=[];observed_reviews=[]
  var result:Dictionary=e.next_day_and_save([],[],{})
  check(not result.ok and result.message.contains("恢复"),"normal exact candidate is unavailable attempt %d"%attempt)
  check(state(e)==original and bytes_snapshot()==original_files,"night seed story reviews ledger and bytes roll back attempt %d"%attempt)
  check(not observed_candidates.is_empty(),"candidate checked without filtering")
  for reviews in observed_reviews:check(reviews==pending,"no next-morning review publication before art guard")
  var signature:String=JSON.stringify(observed_candidates,"",true,true)
  if attempt==0:seen_signature=signature
  else:check(signature==seen_signature,"retry evaluates identical candidate without reroll")
 # Removing only presentation restriction must reveal the same normal batch.
 e.route_guard=Callable();var allowed:Dictionary=e.next_day()
 check(allowed.ok and not e.customer_reviews().is_empty(),"normal progression publishes once after allowed candidate")
 for route in observed_candidates:
  var matching:Array=e.contracts.filter(func(order):return order.contract_id==route.contract_id)
  check(matching.size()==1 and matching[0]==route,"unrestricted exact candidate agrees with prior refused candidate")

func test_main_ordering() -> void:
 var source:String=FileAccess.get_file_as_string("res://scripts/main.gd")
 check(source.find("economy.route_guard=RecoveryPresentationCaps.route_error")<source.find("var loaded=economy.load_state()"),"main binds recovery guard before load")
 for method in ["func start_flight(","func _configure_flight(","func _resume_dispatch("]:
  var body:String=source.substr(source.find(method)).get_slice("\nfunc ",0)
  check(body.contains("route_preflight_error("),"main entry preflights "+method)
 var configure:String=source.substr(source.find("func _configure_flight(")).get_slice("\nfunc ",0)
 check(configure.find("route_preflight_error(")<configure.find("trial=is_trial"),"configure denies before simulation and world ownership")
 var action:String=source.substr(source.find("func _action(")).get_slice("\nfunc ",0)
 check(action.find("route_preflight_error(")<action.find("workshop_input.cancel()"),"accept action denies before UI ownership change")
 check(source.contains("恢复预览 WIP"),"preview is visibly WIP labelled")
 check(ProjectSettings.get_setting("application/config/use_custom_user_dir",false) and ProjectSettings.get_setting("application/config/custom_user_dir","")=="star-courier-recovery-preview","preview uses a dedicated application save directory")
