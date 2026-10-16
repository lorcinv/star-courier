extends SceneTree
## Bounded authoring/save/settlement checks. Model telemetry below is a contract
## fixture, not evidence of native flight. Native source saves are read-only.
const Econ=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Layout=preload("res://scripts/delivery_route_layout_v1.gd")
const Ground=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
var passed:int=0
var failed:int=0
var sources:Dictionary={}

func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String)->void:
 check(JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true)),label)
func canonical(value:Variant)->Variant:
 if value is Dictionary:
  var result:Dictionary={};var keys:Array=value.keys();keys.sort_custom(func(a,b):return str(a)<str(b))
  for key in keys:result[key]=canonical(value[key])
  return result
 if value is Array:
  var result:Array=[]
  for item in value:result.append(canonical(item))
  return result
 return value
func clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
func copy_native(variable:String)->Dictionary:
 clear_files();var path:String=OS.get_environment(variable)
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path);sources[path]=bytes
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 return JSON.parse_string(bytes.get_string_from_utf8())
func telemetry(version:String=Ground.VERSION,integrity:float=1.0)->Dictionary:
 return {"control_version":version,"integrity":integrity,"delivery_integrity":integrity,"energy_used":0.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0}
func launch_settings(raw:Dictionary={})->Dictionary:
 return raw.get("settings",{}).get("launch_settings",{"angle_degrees":70.0,"power_fraction":1.0})
func advance_day(e,ship:Array,pad:Array,settings:Dictionary={})->void:
 check(e.close_day_and_save(ship,pad,settings).ok and e.next_day_and_save(ship,pad,settings).ok,"ordinary close/open authors next batch")
func begin(e,id:String,ship:Array,pad:Array,settings:Dictionary)->void:
 check(e.accept_contract(id).ok and e.mark_cargo_loaded(id).ok,"normal acceptance and cargo loading "+id)
 check(e.begin_dispatch(ship,pad,settings).ok,"paid dispatch freezes route "+id)
func release_fixture(e)->void:
 # Represents Main's physical release checkpoint; never claimed as gameplay.
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")

func test_layout()->void:
 var route:Dictionary=Chapter.fresh_route(2);var original:Dictionary=route.duplicate(true)
 check(route.control_version==Ground.VERSION and Chapter.route_error(route).is_empty(),"new heavy layout retains v8 and validates")
 check(route.route_layout.id==Layout.HEAVY_ID and route.distance==110.0 and route.destination_y==-72.0 and route.delivery_radius==8.0,"new content freezes 110m/72m receiver")
 check(route.weight==4.0 and route.min_delivery_integrity==0.75 and route.required==75.0 and route.max_delivery_speed==10.0,"12kg weight factor and old integrity/speed limits stay")
 check(route.gravity==0.35 and route.wind==[-0.1,0.15] and route.pilot_drag==0.025 and route.pilot_energy_tariff==0.025,"gravity wind drag and fee rate stay")
 check(route.reward==340 and route.cargo_value==320 and route.economy_policy==Chapter.ECONOMY_POLICY,"rewards liability and cargo value stay")
 var view:Dictionary=Layout.preview(route)
 check(view.layout_id==Layout.HEAVY_ID and view.circles.size()==1 and view.circles[0].position==Vector2(62,-64) and view.circles[0].radius==9.0,"shared view reads single exact rock")
 check(view.receiver==Vector2(110,-72) and view.altitude_m==72.0 and view.cargo_mass_kg==12.0 and view.min_delivery_integrity==0.75 and view.max_delivery_speed==10.0,"shared view uses actual height mass and receipt requirements")
 check(not view.has("clearance_m") and not view.has("passage_center"),"single rock never claims a narrow passage")
 check(Layout.summary(route).contains("72 m") and Layout.summary(route).contains("12 kg") and Layout.summary(route).contains("75%"),"summary states correct height actual cargo mass and requirement")
 var misleading:Dictionary=route.duplicate(true);misleading.risk="高1米重4公斤";misleading.altitude_m=1.0;misleading.cargo_mass_kg=4.0
 check(Layout.summary(misleading)==Layout.summary(route),"untrusted descriptive fields cannot replace actual physics data")
 view.circles[0].position=Vector2.ZERO
 same(route,original,"preview cannot mutate saved rock geometry")
 for bad in [null,[],{},"heavy-uplift-rock-v1",{"schema":Layout.SCHEMA,"id":"future"},{"schema":"future","id":Layout.HEAVY_ID},{"schema":Layout.SCHEMA,"id":Layout.HEAVY_ID,"extra":1}]:
  var data:Dictionary=route.duplicate(true);data.route_layout=bad
  check(not Chapter.route_error(data).is_empty() and Layout.preview(data).is_empty(),"unknown malformed or extended layout is rejected")
 for value in [null,true,"9",NAN,INF,-1.0,8.9]:
  var data:Dictionary=route.duplicate(true);data.hazards[0].radius=value
  check(not Chapter.route_error(data).is_empty() and Layout.preview(data).is_empty(),"nonfinite or unfrozen rock radius is rejected")
 for key in ["x","y","radius","health","mass"]:
  var data:Dictionary=route.duplicate(true);data.hazards[0][key]=float(data.hazards[0][key])+0.1
  check(not Chapter.route_error(data).is_empty(),"frozen rock numeric field cannot drift "+key)
 for pair in [["id","another"],["type","asteroid"],["destructible",false],["conductive",false]]:
  var data:Dictionary=route.duplicate(true);data.hazards[0][pair[0]]=pair[1]
  check(not Chapter.route_error(data).is_empty(),"frozen rock identity and flags cannot drift "+str(pair[0]))
 for key in ["position","velocity"]:
  var data:Dictionary=route.duplicate(true);data.hazards[0][key]=[0.0,0.0]
  check(not Chapter.route_error(data).is_empty(),"hidden solver geometry override is rejected "+key)
 for hazards in [[],[route.hazards[0],route.hazards[0]],{},null]:
  var data:Dictionary=route.duplicate(true);data.hazards=hazards
  check(not Chapter.route_error(data).is_empty(),"rock count or collection type cannot drift")
 for key in ["distance","destination_y","delivery_radius","variation","weight","min_delivery_integrity","required","max_delivery_speed","gravity","pilot_drag"]:
  var data:Dictionary=route.duplicate(true);data[key]=NAN
  check(not Chapter.route_error(data).is_empty() and Layout.preview(data).is_empty(),"nonfinite heavy requirement is rejected "+key)
  data=route.duplicate(true);data[key]=float(data[key])+0.1
  check(not Chapter.route_error(data).is_empty(),"new layout frozen environment cannot drift "+key)
 for wind in [[-0.1,0.16],[-0.1,NAN],[-0.1],Vector2(-0.1,0.15),"wind"]:
  var data:Dictionary=route.duplicate(true);data.wind=wind
  check(not Chapter.route_error(data).is_empty(),"wind must retain the exact existing vector")
 for pair in [["control_version","pilot-delivery-v7"],["chapter_level",3],["chapter_id",2],["cargo_kind","fragile"],["route_kind","orbit"],["route_layout_height",72.0]]:
  var data:Dictionary=route.duplicate(true);data[pair[0]]=pair[1]
  check(not Chapter.route_error(data).is_empty(),"new layout cannot relabel another protocol or chapter "+str(pair[0]))
 check(Layout.author_heavy(Chapter.offer(2,2,0)).is_empty() and Layout.author_fragile(Chapter.offer(3,3,0)).is_empty(),"both authors refuse a displayed committed quote")
 var base:Dictionary={"chapter_level":2,"cargo_kind":"heavy"};var authored:Dictionary=Layout.author_heavy(base)
 check(not authored.is_empty() and not base.has("route_layout"),"uncommitted author duplicates its input")
 for level in [1,4,5]:check(not Chapter.fresh_route(level).has("route_layout"),"unrelated layout remains untouched %d"%level)
 var fragile:Dictionary=Chapter.fresh_route(3);var fragile_view:Dictionary=Layout.preview(fragile)
 check(Chapter.route_error(fragile).is_empty() and fragile.route_layout.id==Layout.FRAGILE_ID and fragile.hazards==Layout.HAZARDS,"existing fragile layout keeps exact entity records")
 check(is_equal_approx(fragile_view.clearance_m,2.4) and fragile_view.passage_center==Vector2(48,-10) and fragile_view.receiver==Vector2(95,-10),"fragile API retains original gap centre and receiver")
 check(Layout.summary(fragile)=="窄道净空 2.4 m；可从浮石上方或下方绕行。","existing fragile summary is unchanged")
 var minimal_fragile:Dictionary=fragile.duplicate(true)
 for key in ["weight","min_delivery_integrity","max_delivery_speed"]:minimal_fragile.erase(key)
 check(Layout.validation_error(minimal_fragile).is_empty() and not Layout.preview(minimal_fragile).is_empty(),"old fragile layout API is not tightened by new optional preview terms")
 check(not Layout.preview(minimal_fragile).has("cargo_mass_kg") and not Layout.preview(minimal_fragile).has("min_delivery_integrity") and not Layout.preview(minimal_fragile).has("max_delivery_speed"),"missing legacy optional terms are omitted instead of fabricated")
 fragile.distance=96.0
 check(Layout.preview(fragile).receiver.x==96.0,"legacy fragile preview still reads its own frozen receiver")
 var roundtrip:Dictionary=JSON.parse_string(JSON.stringify(route));var sim=Sim.new()
 sim.configure(Ground.starter_design(),Ground.starter_launcher(),roundtrip,42)
 check(Chapter.route_error(roundtrip).is_empty() and sim.free_route_error.is_empty() and sim.obstacles.size()==1,"JSON frozen heavy is consumed by unchanged v8 solver")
 check(sim.obstacles[0].position==Vector2(62,-64) and sim.obstacles[0].radius==9.0,"physical collider and shared preview agree")
 var cargo_mass:float=0.0
 for p in sim.parts.values():
  if p.type=="cargo":cargo_mass+=float(p.mass)
 check(cargo_mass==Layout.preview(roundtrip).cargo_mass_kg,"preview mass equals actual solver cargo mass rather than weight factor")
 same(route,original,"all validation is read-only")

func test_rotation_policy()->void:
 for unlocked in range(1,5):
  var state:Dictionary=Chapter.initial_state();state.unlocked_level=unlocked
  for level in range(1,unlocked):state.completed_levels[str(level)]="fixture-%d"%level
  var expected:Array=[1] if unlocked<=2 else ([1,2] if unlocked==3 else [1,2,3])
  for day in range(1,10):
   check(Chapter.repeat_level(state,day)==expected[day%expected.size()],"day modulo eligible rotation level%d day%d"%[unlocked,day])
   check(Chapter.repeat_level(state,day,true)==1,"debt repeat always light level%d day%d"%[unlocked,day])

func test_new_shop_progression()->void:
 clear_files();var ship:Array=Ground.starter_design();var pad:Array=Ground.starter_launcher()
 var e=Econ.new();e.enable_delivery_mode();e.starter_stock(ship,pad);e.enable_story_mode()
 check(e.contracts[0].chapter_level==1 and e.contracts[1].chapter_level==1,"normal new shop starts with two light offers")
 for level in [1,2,3]:
  var id:String="D%d-A"%level;var before_b:Dictionary=e.contracts[1].duplicate(true)
  check(e.contracts[0].chapter_level==level,"ordinary new days reach existing chapter %d"%level)
  if level==2:check(e.contracts[0].route_layout.id==Layout.HEAVY_ID,"first normal heavy chapter authors the new layout")
  if level==3:check(e.contracts[1].chapter_level==2 and not e.contracts[1].chapter_progression,"completed heavy naturally becomes day3 optional B")
  begin(e,id,ship,pad,launch_settings());release_fixture(e)
  check(e.settle_contract_and_save(id,telemetry(),20.0,true,ship,pad,{}).ok and e.delivery_chapter_state.unlocked_level==level+1,"qualified model receipt advances one existing chapter")
  e.ensure_contracts();same(e.contracts[1],before_b,"completion does not rewrite already displayed B")
  advance_day(e,ship,pad)
 check(e.day==4 and e.contracts[0].chapter_level==4 and e.contracts[1].chapter_level==2,"normal progression reaches moon A and new heavy B")

func test_old_native_accepted()->void:
 var raw:Dictionary=copy_native("COURIER_OLD_ACCEPTED");var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked and e.active_contract_id==raw.active_contract_id,"actual old accepted native shop loads")
 same(e.contracts,raw.contracts,"old displayed and accepted contracts preserve every field")
 same(e.settled_ids,raw.settled_ids,"old historical receipts stay exact")
 var id:String=str(e.active_contract_id)
 check(e.active_contract().chapter_level==2 and e.active_contract().destination_y==-18.0 and not e.active_contract().has("route_layout"),"old heavy keeps original eighteen-metre destination")
 if not e.is_cargo_loaded(id):check(e.mark_cargo_loaded(id).ok,"old cargo loads normally")
 check(e.begin_dispatch(raw.design,raw.launcher,launch_settings(raw)).ok,"old heavy dispatches under its original version")
 var frozen:Dictionary=e.in_flight.duplicate(true)
 check(e.save_state(raw.design,raw.launcher,raw.settings),"old heavy dispatch saves")
 var resumed=Econ.new();resumed.load_state()
 same(resumed.in_flight,frozen,"old heavy snapshot survives restart without new geometry")
 check(Econ.replay_protocol_error(resumed.in_flight).is_empty(),"old heavy replay identity remains supported")

func test_completed_native_repeat()->void:
 var raw:Dictionary=copy_native("COURIER_OLD_THIRD_COMPLETE");var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked and e.day==3 and e.delivery_chapter_state.unlocked_level==4,"real old three-completed day3 loads")
 same(e.contracts,raw.contracts,"actual already displayed day3 quote remains frozen")
 advance_day(e,raw.design,raw.launcher,raw.settings)
 check(e.day==4 and e.contracts[0].chapter_level==4 and e.contracts[1].chapter_level==2,"old player reaches heavy B at normal next-day boundary")
 var offered:Dictionary=e.contracts[1].duplicate(true)
 check(offered.route_layout.id==Layout.HEAVY_ID and not offered.chapter_progression and not offered.recovery_offer and str(offered.name).contains("自选复送"),"optional heavy purpose and frozen layout are explicit")
 var chapter:Dictionary=e.delivery_chapter_state.duplicate(true);var ledger:Dictionary=e.settled_ids.duplicate(true);var credits:int=e.credits;var inventory:Dictionary=e.inventory.duplicate(true)
 e.ensure_contracts();same(e.contracts[1],offered,"repeat display never rerolls heavy")
 begin(e,"D4-B",raw.design,raw.launcher,launch_settings(raw))
 var trial:Dictionary=e.trial_route()
 check(trial.route_layout==offered.route_layout and trial.hazards==offered.hazards,"free trial uses frozen heavy quote")
 e.estimate_delivery(e.active_contract(),telemetry(Ground.VERSION,0.5),20.0,false)
 check(e.credits==credits and e.settled_ids==ledger,"free trial estimate cannot charge or advance")
 check(e.save_state(raw.design,raw.launcher,raw.settings),"new heavy snapshot saves")
 var frozen:Dictionary=e.in_flight.duplicate(true);var resumed=Econ.new();resumed.load_state();resumed.enable_story_mode()
 same(resumed.in_flight,frozen,"new heavy in-flight layout survives save/Continue")
 var saved_route:Dictionary=resumed.in_flight.route.duplicate(true);resumed.in_flight.route.hazards[0].y=-63.0
 check(not resumed.settle_contract("D4-B",telemetry(),0.0,false).ok and resumed.credits==credits,"corrupt frozen geometry cannot settle")
 resumed.in_flight.route=saved_route;release_fixture(resumed)
 check(resumed.settle_contract_and_save("D4-B",telemetry(),20.0,true,raw.design,raw.launcher,raw.settings).ok,"model heavy result settles through normal receipt path")
 same(resumed.delivery_chapter_state,chapter,"repeat delivery cannot unlock or repeat chapter reward")
 same(resumed.inventory,inventory,"repeat creates no free inventory")
 check(resumed.credits==credits+340 and not resumed.last_settlement.level_completed and not resumed.last_settlement.chapter_progression and resumed.last_settlement.income==340,"repeat pays only original normal heavy fare")
 for id in ledger:same(resumed.settled_ids[id],ledger[id],"earlier real receipt remains exact "+str(id))
 var after=Econ.new();after.load_state();after.enable_story_mode()
 check(not after.review_load_blocked and after.credits==credits+340 and not after.settle_contract("D4-B",telemetry(),20.0,true).ok,"saved repeat cannot pay a second time")
 advance_day(after,raw.design,raw.launcher,raw.settings)
 check(after.day==5 and after.contracts[1].chapter_level==3 and after.contracts[1].route_layout.id==Layout.FRAGILE_ID,"three-way policy retains natural fragile day5")
 advance_day(after,raw.design,raw.launcher,raw.settings)
 check(after.day==6 and after.contracts[1].chapter_level==1,"three-way policy retains natural basic light day6")
 advance_day(after,raw.design,raw.launcher,raw.settings)
 check(after.day==7 and after.contracts[1].chapter_level==2,"three-way policy repeats heavy day7")
 var displayed:Array=after.contracts.duplicate(true);after.credits=-1;after.ensure_contracts()
 same(after.contracts,displayed,"becoming indebted never rewrites already displayed heavy")
 advance_day(after,raw.design,raw.launcher,raw.settings)
 check(after.day==8 and after.contracts[0].chapter_level==1 and after.contracts[1].chapter_level==1 and after.contracts[1].recovery_offer and not after.contracts[1].chapter_progression,"debt overrides normally-fragile day8 with two light recovery offers")

func test_old_v8_heavy_and_fragile()->void:
 clear_files()
 # Exact pre-dev30 v8 heavy geometry, deliberately a synthetic compatibility
 # fixture; native accepted v7 heavy is independently exercised above.
 var old:Dictionary=Chapter.offer(2,1,0,false);old.erase("route_layout");old.destination_y=-18.0
 old.hazards=[{"id":"chapter-heavy-low","x":43.0,"y":4.0,"radius":5.0,"type":"rock","health":120.0,"mass":80.0,"destructible":true,"conductive":true},{"id":"chapter-heavy-high","x":76.0,"y":-28.0,"radius":4.5,"type":"rock","health":120.0,"mass":80.0,"destructible":true,"conductive":true}]
 old.risk="重货影响发射、爬升和制动；侧风与重力需要持续供能。"
 check(Chapter.route_error(old).is_empty() and Layout.preview(old).is_empty(),"unmarked old v8 heavy stays valid without inferred new layout")
 var e=Econ.new();e.enable_delivery_mode();e.starter_stock(Ground.starter_design(),Ground.starter_launcher());e.contracts=[old,Chapter.offer(1,1,1,false)]
 var quoted:Array=e.contracts.duplicate(true);e.ensure_contracts();same(e.contracts,quoted,"old v8 displayed quote cannot be reauthored")
 begin(e,"D1-A",Ground.starter_design(),Ground.starter_launcher(),launch_settings())
 check(e.save_state(Ground.starter_design(),Ground.starter_launcher(),{}),"old v8 heavy dispatch saves")
 var frozen:Dictionary=e.in_flight.duplicate(true);var loaded=Econ.new();loaded.load_state()
 same(loaded.in_flight,frozen,"old v8 heavy remains exact through JSON save")
 var a=Sim.new();var b=Sim.new()
 a.configure(frozen.design,frozen.launcher,frozen.route,int(frozen.seed));b.configure(loaded.in_flight.design,loaded.in_flight.launcher,loaded.in_flight.route,int(loaded.in_flight.seed))
 a.release_launcher(70.0,1.0);b.release_launcher(70.0,1.0)
 for tick in 60:a.step(1.0/60.0);b.step(1.0/60.0)
 check(var_to_bytes(canonical([a.parts,a.bodies,a.obstacles,a.telemetry]))==var_to_bytes(canonical([b.parts,b.bodies,b.obstacles,b.telemetry])),"old v8 heavy short replay remains byte-exact after JSON key order")
 if not OS.get_environment("COURIER_OLD_FRAGILE_ACCEPTED").is_empty():
  var raw:Dictionary=copy_native("COURIER_OLD_FRAGILE_ACCEPTED");var fragile=Econ.new();fragile.load_state();fragile.enable_story_mode()
  check(not fragile.review_load_blocked and fragile.day==4 and fragile.active_contract_id=="D4-B" and fragile.active_contract().chapter_level==3,"real old day4 fragile repeat stays accepted despite new heavy rotation")
  same(fragile.contracts,raw.contracts,"real old fragile batch geometry and story remain exact")
  fragile.ensure_contracts();same(fragile.contracts,raw.contracts,"reopening old day4 display never rerolls fragile as heavy")
  same(fragile.settled_ids,raw.settled_ids,"real old fragile shop historical receipts stay exact")

func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Use isolated XDG_DATA_HOME");quit(2);return
 for key in ["COURIER_OLD_ACCEPTED","COURIER_OLD_THIRD_COMPLETE"]:
  if OS.get_environment(key).is_empty():printerr("Missing read-only source "+key);quit(2);return
 test_layout();test_rotation_policy();test_new_shop_progression();test_old_native_accepted();test_completed_native_repeat();test_old_v8_heavy_and_fragile()
 for path in sources:check(FileAccess.get_file_as_bytes(path)==sources[path],"native source remains byte-identical "+str(path))
 clear_files();print("HEAVY_ROUTE_CONTRACTS_V1 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
