extends SceneTree
## Lead-run focused fixture only. Requires an isolated XDG_DATA_HOME.
const Econ=preload("res://scripts/economy.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Free=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Isolated XDG_DATA_HOME required.");quit(2);return
 test_readonly_capability();test_real_purchase_and_repeat();test_stock_and_low_funds()
 test_bad_payloads();test_flight_and_legacy_guards();test_save_rollback();test_night_unchanged()
 clear_files();print("DAY_BASIC_PURCHASE passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func craft() -> Array:return Extreme.starter_design()
func pad() -> Array:return Extreme.starter_launcher()
func state(e) -> Dictionary:
 var out:Dictionary={}
 for key in Econ.SHOP_TRANSACTION_FIELDS:
  var value:Variant=e.get(key);out[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return out
func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func fixture():
 clear_files();var e=Econ.new();e.enable_free_mode();e.starter_stock(craft(),pad());e.enable_story_mode()
 check(e.accept_contract("D1-A").ok,"first free delivery is accepted")
 check(e.save_state(craft(),pad(),{}),"accepted free shop is durable")
 return e
func buy(e,kind:String) -> Dictionary:return e.buy_part_and_save(kind,Parts.catalog()[kind],craft(),pad(),{})

func test_readonly_capability() -> void:
 var e=Econ.new();var before:Dictionary=state(e)
 check(not e.can_buy_basic_during_day(),"legacy morning has no daytime shelf")
 var kinds:Array=e.day_basic_part_kinds()
 check(kinds==["beam","battery","thruster","armor","shield","drill"],"HUD receives precisely six basic kinds")
 kinds.append("bomb")
 check(not "bomb" in e.day_basic_part_kinds(),"HUD cannot mutate trusted kind list")
 same(state(e),before,"capability and list are read-only and create no orders")
 e.enable_free_mode();check(not e.can_buy_basic_during_day(),"free morning still waits for accepted first job")
 e.phase="day";check(e.can_buy_basic_during_day(),"free shop day permits basic purchase without touching contracts")
 check(e.contracts.is_empty(),"capability query does not author the empty boundary")
 e.phase="night";check(not e.can_buy_basic_during_day(),"night uses separate unchanged supply rules")

func test_real_purchase_and_repeat() -> void:
 var e=fixture();var before:Dictionary=state(e);var initial:int=int(e.inventory.get("drill",0))
 check(e.can_buy_basic_during_day() and e.active_contract().status=="accepted","accepted first free job can buy a drill before launch")
 check(buy(e,"drill").ok and e.credits==195 and int(e.inventory.drill)==initial+1,"first drill costs real65 and adds exactly one owned part")
 check(buy(e,"drill").ok and e.credits==130 and int(e.inventory.drill)==initial+2,"second explicit click buys a second real part for another65")
 for key in ["contracts","active_contract_id","jobs_today","deliveries","settled_ids","history","review_state","story_state"]:same(e.get(key),before[key],"purchase does not fake or rewrite "+key)
 var restored=Econ.new();restored.load_state(true)
 check(not restored.review_load_blocked and restored.credits==130 and int(restored.inventory.drill)==initial+2,"both paid parts and exact balance survive restart")
 var mounted:Array=craft();mounted.append(Extreme.part(900,"drill",2,0))
 check(e.missing_parts(mounted,pad()).is_empty(),"purchased drill is real stock usable by the assembly check")

func test_stock_and_low_funds() -> void:
 for kind in ["beam","battery","thruster","armor","shield","drill"]:
  var e=fixture();var price:int=int(Parts.catalog()[kind].price);var owned:int=int(e.inventory.get(kind,0));var money:int=e.credits
  check(buy(e,kind).ok and e.credits==money-price and int(e.inventory[kind])==owned+1,"actual catalogue price and one stock for "+kind)
 var empty=fixture();empty.credits=0;check(empty.save_state(craft(),pad(),{}),"zero-money shop saved")
 var before:Dictionary=state(empty)
 check(not buy(empty,"drill").ok,"zero funds cannot create a free drill or overdraft")
 same(state(empty),before,"unaffordable daytime purchase changes nothing")
 check(empty.missing_parts(craft(),pad()).is_empty(),"zero-cash player still owns default launchable hardware")
 check(empty.mark_cargo_loaded("D1-A").ok and empty.begin_dispatch(craft(),pad()).ok,"default owned craft can continue without new money")
 var exact=fixture();exact.credits=65;check(exact.save_state(craft(),pad(),{}),"exact funds persisted")
 check(buy(exact,"drill").ok and exact.credits==0,"exact65 is a valid one-time purchase to zero")
 check(not buy(exact,"drill").ok and exact.credits==0 and int(exact.inventory.drill)==1,"next click at zero cannot create another item")

func test_bad_payloads() -> void:
 var e=fixture();var before:Dictionary=state(e)
 for price in [0,-1,1,64,64.5,66,"65",true,null,INF,NAN]:
  check(not e.buy_part_and_save("drill",{"price":price},craft(),pad(),{}).ok,"reject forged/nonintegral price "+str(price))
  same(state(e),before,"bad price leaves full account exact "+str(price))
 check(not e.buy_part_and_save("drill",{},craft(),pad(),{}).ok,"missing price is not a free default")
 for kind in ["unknown","cargo","bomb","teleporter","lance"]:
  var spec:Dictionary=Parts.catalog().get(kind,{"price":1})
  check(not e.buy_part_and_save(kind,spec,craft(),pad(),{}).ok,"daytime shelf rejects unknown/advanced "+kind)
  same(state(e),before,"rejected kind cannot mutate inventory "+kind)
 check(e.buy_part_and_save("drill",{"price":65.0},craft(),pad(),{}).ok,"exact JSON numeric65.0 matches trusted catalogue price")

func test_flight_and_legacy_guards() -> void:
 var e=fixture();e.mark_cargo_loaded("D1-A");e.begin_dispatch(craft(),pad());var paid:Dictionary=state(e)
 check(not e.can_buy_basic_during_day() and not buy(e,"drill").ok,"formal paid flight cannot buy a basic item")
 same(state(e),paid,"in-flight refusal preserves exact paid replay and balance")
 for protocol in ["autonomous-v5","pilot-v1","pilot-v2","pilot-v3","pilot-v4"]:
  var old=Econ.new();old.flight_mode=protocol;old.phase="day";old.credits=260
  var before:Dictionary=state(old)
  check(not old.can_buy_basic_during_day() and not old.buy_part("drill",Parts.catalog().drill).ok,"old protocol retains daytime refusal "+protocol)
  same(state(old),before,"legacy daytime refusal is unchanged "+protocol)
 var blocked=fixture();blocked.review_load_blocked=true;var untouched:Dictionary=state(blocked)
 check(not blocked.can_buy_basic_during_day() and not buy(blocked,"drill").ok,"recovery-only account cannot purchase")
 same(state(blocked),untouched,"recovery refusal preserves records")

func test_save_rollback() -> void:
 var e=fixture();var before:Dictionary=state(e);var primary:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not buy(e,"drill").ok,"failed final save rejects daytime purchase")
 same(state(e),before,"save failure rolls back real money and stock together")
 check(FileAccess.get_file_as_bytes("user://savegame.json")==primary,"failed purchase preserves durable primary byte-for-byte")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(buy(e,"drill").ok and e.credits==195 and e.inventory.drill==1,"retry after failed save purchases exactly one item once")

func test_night_unchanged() -> void:
 for protocol in ["autonomous-v5","pilot-v3",Free.CONTROL_VERSION]:
  var e=Econ.new();e.flight_mode=protocol;e.phase="night";e.credits=260
  check(e.buy_part("teleporter",Parts.catalog().teleporter).ok and e.credits==180 and e.inventory.teleporter==1,"night advanced purchase retains original price and availability "+protocol)
  check(e.buy_part("drill",Parts.catalog().drill).ok and e.credits==115 and e.inventory.drill==1,"night existing drill purchase remains unchanged "+protocol)
