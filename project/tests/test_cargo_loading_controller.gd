extends SceneTree
## Controller/save integration for the same-parcel robot sequence.
## SceneTree/tween steps are explicit; this is not native-input visual proof.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
var game
var passed:int=0
var failed:int=0

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func frames(count:int=3) -> void:
 for i in count:await process_frame
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func ledger() -> Dictionary:
 return {"credits":game.economy.credits,"inventory":game.economy.inventory.duplicate(true),"jobs":game.economy.jobs_today,"deliveries":game.economy.deliveries,"settled":game.economy.settled_ids.duplicate(true)}
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await frames()
 game=null
func fresh(erase:bool=true) -> void:
 await dispose()
 if erase:
  for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
   if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames()
func accept(cid:String="D1-A") -> void:
 game._action("accept_contract",cid)
func finish_dialogue() -> void:
 if game.dialogue.is_open():game.dialogue.skip_conversation()
func step_loading(seconds:float) -> void:
 for i in ceili(seconds*120.0):
  var tween:Tween=game.world._parcel_tween
  if tween!=null and game.world._focus_active and game.world.is_visible_in_tree():
   tween.pause();tween.custom_step(1.0/120.0)
  game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0)
func cargo_sprite() -> Sprite2D:
 for node in game.world.ship_root.get_children():
  if node is Sprite2D and bool(node.get_meta("is_cargo",false)):return node
 return null

func test_economy_guard() -> void:
 var e=Econ.new();e.enable_ascent_mode();e.enable_story_mode();e.starter_stock(Profile.starter_design(),Profile.starter_launcher());e.accept_contract("D1-A")
 check(not e.is_cargo_loaded() and not e.begin_dispatch(Profile.starter_design(),Profile.starter_launcher()).ok,"story dispatch cannot commit before cargo is loaded")
 check(e.in_flight.is_empty() and e.active_contract().status=="accepted" and e.credits==260,"blocked loading commitment changes no status or money")
 check(not e.mark_cargo_loaded("D1-B").ok and not e.is_cargo_loaded(),"foreign loading completion cannot mark the active parcel")
 var mark:Dictionary=e.mark_cargo_loaded("D1-A")
 check(mark.ok and mark.changed and e.is_cargo_loaded(),"matching accepted cargo can be committed loaded")
 check(not e.mark_cargo_loaded("D1-A").changed,"repeated loading is idempotent")
 check(e.begin_dispatch(Profile.starter_design(),Profile.starter_launcher()).ok and e.in_flight.route.cargo_loaded,"formal snapshot includes its loaded cargo state")
 check(not e.mark_cargo_loaded("D1-A").ok,"late renderer callback cannot modify an in-flight contract")
 var legacy=Econ.new();legacy.starter_stock(Profile.starter_design(),Profile.starter_launcher());legacy.accept_contract("D1-A")
 check(legacy.begin_dispatch(Profile.starter_design(),Profile.starter_launcher()).ok,"standalone legacy economy retains its original no-presentation dispatch contract")

func test_dialogue_and_natural_load() -> void:
 await fresh();accept()
 var money:Dictionary=ledger();var parcel_id:int=game.world.parcel.get_instance_id()
 check(game.dialogue.is_open() and not game.economy.is_cargo_loaded(),"acceptance opens dialogue before loading")
 check(game.world._parcel_phase=="waiting_customer" and not game.world.is_loading(),"customer keeps its parcel until acceptance dialogue ends")
 check(cargo_sprite()!=null and not cargo_sprite().visible,"actual cargo module has no duplicate painted box before installation")
 game.start_flight(true)
 check(game.sim==null and game.page=="hub" and game.economy.in_flight.is_empty(),"launch cannot race the acceptance modal")
 finish_dialogue()
 check(game.world.is_loading() and not game.economy.is_cargo_loaded(),"dialogue completion starts robot chain without claiming loaded")
 step_loading(.18)
 game._on_focus_exited();var stopped:Dictionary=game.world.loading_snapshot();step_loading(.8)
 check(game.world.loading_snapshot()==stopped,"focus loss freezes loading with no catch-up movement")
 game._on_focus_entered();step_loading(9.0)
 check(game.world.is_parcel_loaded("D1-A") and game.economy.is_cargo_loaded(),"natural robot sequence commits the actual cargo bay")
 check(not game.world.parcel.visible and cargo_sprite().visible,"handoff swaps external parcel for installed cargo on completion")
 check(game.world.parcel.get_instance_id()==parcel_id,"counter transfer and robot carry reuse one external parcel node")
 check(ledger()==money,"complete cargo transfer changes no inventory, price, quota or reward")
 check(bool(disk().contracts[0].cargo_loaded),"natural completion persists loaded state in the ordinary atomic save")
 var saved_bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 for i in 12:game._on_cargo_loading_complete("D1-A");game.world.begin_loading("D1-A")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==saved_bytes and ledger()==money,"repeated completion creates no new save effects or financial mutations")
 await fresh(false)
 check(game.economy.is_cargo_loaded() and game.world.is_parcel_loaded("D1-A") and not game.world.is_loading(),"loaded restart restores directly without repeating pickup")
 check(not game.dialogue.is_open() and cargo_sprite().visible and not game.world.parcel.visible,"loaded restart keeps seen dialogue closed and only installed cargo visible")

func test_restart_cancel_fastforward() -> void:
 await fresh();accept();finish_dialogue();step_loading(.2);game.save_game()
 check(not disk().contracts[0].cargo_loaded,"interrupted transport saves accepted-but-unloaded state")
 await fresh(false)
 check(not game.dialogue.is_open() and game.world.is_loading() and not game.economy.is_cargo_loaded(),"seen acceptance restarts one safe unfinished loading chain")
 var old_generation:int=game.world._parcel_generation
 game._action("cancel_contract",null);accept("D1-B")
 check(game.economy.active_contract_id=="D1-B" and game.world._parcel_phase=="waiting_customer","cancel/new order replaces the waiting parcel identity")
 game.world._complete_loading("D1-A",old_generation);game._on_cargo_loading_complete("D1-A")
 check(not game.economy.is_cargo_loaded() and not game.world.is_parcel_loaded("D1-B"),"old order completion cannot install the new customer's cargo")
 finish_dialogue();var before:Dictionary=ledger();game.start_flight(true)
 check(game.page=="flight" and game.trial and game.world.is_parcel_loaded("D1-B"),"explicit trial fast-forwards the same parcel before physics begins")
 check(game.economy.is_cargo_loaded() and disk().contracts[1].cargo_loaded,"fast-forward loading is durable before launch")
 check(ledger()==before and game.economy.in_flight.is_empty(),"fast-forward trial leaves formal accounting untouched")
 game.abort_flight();game.start_flight(false)
 check(game.page=="flight" and not game.trial and game.economy.in_flight.route.cargo_loaded,"formal launch includes loaded cargo without repeating transport")
 var inflight:Dictionary=game.economy.in_flight.duplicate(true)
 game._on_cargo_loading_complete("D1-B")
 check(game.economy.in_flight==inflight,"late loading callback cannot mutate committed flight snapshot")

func test_reduced_motion_and_failed_save() -> void:
 await fresh();game.settings.reduced_motion=true;game.render();accept()
 check(not game.economy.is_cargo_loaded() and game.world._parcel_phase=="waiting_customer","reduced motion still waits for unread acceptance")
 finish_dialogue()
 check(game.economy.is_cargo_loaded() and game.world.is_parcel_loaded() and not game.world.is_loading(),"reduced-motion acceptance reaches exactly the same loaded final state")
 await fresh();accept();finish_dialogue()
 var before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 game.start_flight(false)
 check(game.sim==null and game.page!="flight" and game.economy.in_flight.is_empty(),"failed loading save blocks formal launch before commitment")
 check(not game.economy.is_cargo_loaded() and game.world.is_parcel_loaded(),"failed save keeps durable model uncommitted despite settled visuals")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==before and game.economy.credits==260,"failed loading save preserves prior bytes and funds")
 DirAccess.remove_absolute("user://savegame.tmp")
 game.start_flight(false)
 check(game.page=="flight" and game.economy.in_flight.route.cargo_loaded,"next explicit launch safely retries the loaded save")
 check(disk().in_flight.route.cargo_loaded and game.economy.jobs_today==0,"successful retry persists one commitment, not a settlement")

func run() -> void:
 root.size=Vector2i(1280,800)
 test_economy_guard()
 await test_dialogue_and_natural_load()
 await test_restart_cancel_fastforward()
 await test_reduced_motion_and_failed_save()
 await dispose()
 print("CARGO_LOADING_CONTROLLER passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)
