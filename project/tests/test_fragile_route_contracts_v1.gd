extends SceneTree
## Bounded content/contract checks. Native source saves are read-only inputs;
## the synthetic fragile fixture is explicitly not native gameplay evidence.
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
 # JSON saves sort dictionary keys. Canonicalize order only, preserving exact
 # numeric types/values and vectors for the physical-state byte comparison.
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
 clear_files()
 var path:String=OS.get_environment(variable)
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path);sources[path]=bytes
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 return JSON.parse_string(bytes.get_string_from_utf8())
func telemetry(version:String,integrity:float=1.0)->Dictionary:
 return {"control_version":version,"integrity":integrity,"delivery_integrity":integrity,"energy_used":0.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0}
func settings(raw:Dictionary)->Dictionary:return raw.get("settings",{}).get("launch_settings",{"angle_degrees":15.0,"power_fraction":0.12})
func write_primary(data:Dictionary)->void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(data,"",true,true));file.close()

func test_layout()->void:
 var route:Dictionary=Chapter.fresh_route(3)
 var original:Dictionary=route.duplicate(true)
 check(route.control_version==Ground.VERSION and Chapter.route_error(route).is_empty(),"new fragile geometry retains v8 physics and validates")
 check(route.distance==95.0 and route.min_delivery_integrity==0.9 and route.required==90.0 and route.max_delivery_speed==6.0,"95m, 90%, and existing receipt speed remain unchanged")
 var view:Dictionary=Layout.preview(route)
 check(view.circles.size()==2 and is_equal_approx(view.clearance_m,2.4) and view.passage_center==Vector2(48,-10),"shared preview derives gap and centre from actual frozen circles")
 check(Layout.summary(route).contains("2.4 m"),"human-readable clearance is geometry-derived")
 var misleading:Dictionary=route.duplicate(true);misleading.risk="净空100米";misleading.clearance_m=100.0
 check(Layout.summary(misleading)==Layout.summary(route),"untrusted prose or unrelated clearance field cannot lie to preview")
 var changed_receiver:Dictionary=route.duplicate(true);changed_receiver.distance=96.0
 check(Layout.preview(changed_receiver).receiver.x==96.0,"preview reads this order snapshot rather than reauthoring current catalogue")
 view.circles[0].position=Vector2.ZERO
 same(route,original,"returned preview cannot mutate route geometry")
 for bad in [null,[],{},"fragile-dual-rock-v1",{"schema":Layout.SCHEMA,"id":"future"},{"schema":"future","id":Layout.FRAGILE_ID},{"schema":Layout.SCHEMA,"id":Layout.FRAGILE_ID,"clearance_m":100.0}]:
  var data:Dictionary=route.duplicate(true);data.route_layout=bad
  check(not Chapter.route_error(data).is_empty() and Layout.preview(data).is_empty(),"malformed or unknown layout identity is blocked")
 for value in [null,true,"7",NAN,INF,-1.0,7.1]:
  var data:Dictionary=route.duplicate(true);data.hazards[0].radius=value
  check(not Chapter.route_error(data).is_empty() and Layout.preview(data).is_empty(),"invalid/nonfinite/unfrozen radius is blocked")
 for key in ["x","y","health","mass"]:
  var data:Dictionary=route.duplicate(true);data.hazards[0][key]=INF
  check(not Chapter.route_error(data).is_empty(),"nonfinite frozen hazard field is blocked "+key)
 for key in ["position","velocity"]:
  var data:Dictionary=route.duplicate(true);data.hazards[0][key]=[0.0,0.0]
  check(not Chapter.route_error(data).is_empty(),"solver geometry override cannot disagree with preview "+key)
 for key in ["distance","destination_y","delivery_radius","variation"]:
  var data:Dictionary=route.duplicate(true);data[key]=NAN
  check(not Chapter.route_error(data).is_empty(),"nonfinite preview environment is blocked "+key)
 var drift:Dictionary=route.duplicate(true);drift.variation=1.0
 check(not Chapter.route_error(drift).is_empty(),"random obstacle displacement cannot invalidate quoted gap")
 var unknown:Dictionary=route.duplicate(true);unknown.route_layout_clearance=100.0
 check(not Chapter.route_error(unknown).is_empty(),"unknown route-layout extension cannot introduce fake clearance")
 var wrong:Dictionary=route.duplicate(true);wrong.control_version="pilot-delivery-v7"
 check(not Chapter.route_error(wrong).is_empty(),"layout identity cannot silently relabel old solver")
 var offered:Dictionary=Chapter.offer(3,3,0)
 check(Layout.author_fragile(offered).is_empty(),"layout author refuses displayed or accepted quote")
 for level in [1,2,4,5]:check(not Chapter.fresh_route(level).has("route_layout"),"unrelated level stays unmarked %d"%level)
 var json_route:Dictionary=JSON.parse_string(JSON.stringify(route))
 check(Chapter.route_error(json_route).is_empty(),"layout values retain identity through JSON")
 var sim=Sim.new();sim.configure(Ground.starter_design(),Ground.starter_launcher(),json_route,309)
 check(sim.free_route_error.is_empty() and sim.obstacles.size()==2,"unchanged v8 directly constructs new circular obstacles")
 for index in 2:
  check(sim.obstacles[index].position==Layout.preview(json_route).circles[index].position and sim.obstacles[index].radius==Layout.preview(json_route).circles[index].radius,"preview circle equals actual solver circle %d"%index)
 same(route,original,"validation and preview leave quote byte-equivalent values unchanged")

func test_native_old_accepted()->void:
 var raw:Dictionary=copy_native("COURIER_OLD_ACCEPTED")
 var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked and e.active_contract_id==raw.active_contract_id,"actual old accepted native shop loads without migration")
 same(e.contracts,raw.contracts,"native displayed and accepted contracts remain exact")
 same(e.settled_ids,raw.settled_ids,"native historical receipts remain exact")
 var id:String=str(e.active_contract_id)
 if not e.is_cargo_loaded(id):check(e.mark_cargo_loaded(id).ok,"old accepted cargo loads normally")
 check(e.begin_dispatch(raw.design,raw.launcher,settings(raw)).ok,"native old accepted order still dispatches under own protocol")
 var frozen:Dictionary=e.in_flight.duplicate(true)
 check(e.save_state(raw.design,raw.launcher,raw.settings),"native old dispatch saves")
 var resumed=Econ.new();resumed.load_state()
 same(resumed.in_flight,frozen,"native old route and unpaid preparation survive restart unchanged")
 check(Econ.replay_protocol_error(resumed.in_flight).is_empty() and not resumed.in_flight.route.has("route_layout"),"old route gains no new layout or input identity")

func test_completed_native_entry()->void:
 var raw:Dictionary=copy_native("COURIER_OLD_THIRD_COMPLETE")
 var e=Econ.new();e.load_state();e.enable_story_mode()
 check(not e.review_load_blocked and e.day==3 and int(e.delivery_chapter_state.unlocked_level)==4,"actual three-completed native day3 source loads")
 same(e.contracts,raw.contracts,"already displayed native day3 B remains unchanged")
 same(e.settled_ids,raw.settled_ids,"actual old three chapter receipts retain all fields")
 check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"normal native close and next day reach new authoring boundary")
 var first:Dictionary=e.contracts[0];var second:Dictionary=e.contracts[1]
 check(e.day==4 and first.chapter_level==4 and second.chapter_level==3 and not second.chapter_progression and not second.recovery_offer,"day4 moon A plus optional nonprogression fragile B are reachable")
 check(str(second.name).contains("自选复送") and second.route_layout.id==Layout.FRAGILE_ID,"optional order states its repeat purpose and freezes new layout")
 var offered:Dictionary=second.duplicate(true);e.ensure_contracts();same(e.contracts[1],offered,"repeated display never rewrites new quoted layout")
 var ledger:Dictionary=e.settled_ids.duplicate(true);var chapter:Dictionary=e.delivery_chapter_state.duplicate(true)
 check(e.accept_contract_and_save("D4-B",raw.design,raw.launcher,raw.settings).ok,"new optional fragile B accepts normally")
 check(e.mark_cargo_loaded("D4-B").ok,"optional fragile cargo loads")
 var trial:Dictionary=e.trial_route()
 check(trial.route_layout==offered.route_layout and trial.hazards==offered.hazards,"free trial uses the same frozen offered geometry")
 var credits:int=e.credits
 e.estimate_delivery(e.active_contract(),telemetry(Ground.VERSION,0.74),20.0,false)
 check(e.credits==credits and e.settled_ids==ledger,"failed free trial quote cannot bill or advance progression")
 check(e.begin_dispatch(raw.design,raw.launcher,settings(raw)).ok,"optional new contract begins paid dispatch")
 check(e.save_state(raw.design,raw.launcher,raw.settings),"new layout dispatch saves")
 var frozen:Dictionary=e.in_flight.duplicate(true);var resumed=Econ.new();resumed.load_state();resumed.enable_story_mode()
 same(resumed.in_flight,frozen,"new exact layout and geometry survive restart")
 check(Econ.replay_protocol_error(resumed.in_flight).is_empty(),"new layout replay snapshot validates without v9 adapter")
 var corrupt:Dictionary=resumed.in_flight.route.duplicate(true);resumed.in_flight.route.hazards[0].y=-18.0
 check(not resumed.settle_contract("D4-B",telemetry(Ground.VERSION),0.0,false).ok and resumed.credits==credits,"changed frozen geometry cannot settle")
 resumed.in_flight.route=corrupt
 resumed.in_flight.launch_released=true;resumed.in_flight.erase("launch_preparation")
 check(resumed.settle_contract_and_save("D4-B",telemetry(Ground.VERSION),20.0,true,raw.design,raw.launcher,raw.settings).ok,"bounded model outcome settles optional fragile delivery")
 same(resumed.delivery_chapter_state,chapter,"optional success cannot advance or repeat chapter unlock")
 check(not resumed.last_settlement.level_completed and not resumed.last_settlement.chapter_progression and resumed.last_settlement.income==380,"optional bill earns only normal shipping pay")
 for id in ledger:same(resumed.settled_ids[id],ledger[id],"earlier native receipt survives optional new settlement "+str(id))
 check(resumed.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and resumed.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"normal next day reaches odd rotation")
 check(resumed.day==5 and resumed.contracts[1].chapter_level==1 and not resumed.contracts[1].has("route_layout"),"odd-day B remains basic light")
 var displayed:Array=resumed.contracts.duplicate(true);resumed.credits=-1;resumed.ensure_contracts()
 same(resumed.contracts,displayed,"balance changes do not rewrite already displayed quotes")
 check(resumed.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and resumed.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"debt still enters normal next-day authoring")
 check(resumed.day==6 and resumed.contracts[0].chapter_level==1 and resumed.contracts[1].chapter_level==1 and resumed.contracts[1].recovery_offer,"even-day debt recovery keeps both offers light")

func test_synthetic_old_fragile()->void:
 # This is a synthetic preservation fixture with the exact pre-dev29 circles,
 # not a claim that a player reached or flew this accepted state natively.
 clear_files()
 var old:Dictionary=Chapter.offer(3,1,0,false)
 old.erase("route_layout")
 old.hazards=[{"id":"chapter-fragile-upper","x":39.0,"y":-20.0,"radius":4.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true},{"id":"chapter-fragile-lower","x":64.0,"y":1.0,"radius":4.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true}]
 old.risk="避免猛推、急停和硬碰撞；缓慢加速与缓冲装配都可尝试。"
 check(Chapter.route_error(old).is_empty() and Layout.preview(old).is_empty(),"synthetic old v8 fragile geometry validates without inferred layout")
 var e=Econ.new();e.enable_delivery_mode();e.starter_stock(Ground.starter_design(),Ground.starter_launcher());e.contracts=[old,Chapter.offer(1,1,1,false)]
 var offered:Array=e.contracts.duplicate(true);e.ensure_contracts();same(e.contracts,offered,"synthetic old displayed fragile is never reauthored")
 check(e.accept_contract("D1-A").ok and e.begin_dispatch(Ground.starter_design(),Ground.starter_launcher(),{"angle_degrees":15.0,"power_fraction":0.12}).ok,"synthetic old fragile remains dispatchable")
 check(e.save_state(Ground.starter_design(),Ground.starter_launcher(),{}),"synthetic old fragile in-flight snapshot saves")
 var frozen:Dictionary=e.in_flight.duplicate(true);var loaded=Econ.new();loaded.load_state()
 same(loaded.in_flight,frozen,"synthetic old fragile geometry survives disk and reload")
 var a=Sim.new();var b=Sim.new()
 a.configure(frozen.design,frozen.launcher,frozen.route,int(frozen.seed));b.configure(loaded.in_flight.design,loaded.in_flight.launcher,loaded.in_flight.route,int(loaded.in_flight.seed))
 a.release_launcher(15.0,0.12);b.release_launcher(15.0,0.12)
 for tick in 60:a.step(1.0/60.0);b.step(1.0/60.0)
 check(var_to_bytes(canonical([a.parts,a.bodies,a.obstacles,a.telemetry]))==var_to_bytes(canonical([b.parts,b.bodies,b.obstacles,b.telemetry])),"synthetic old frozen-route one-second replay is exact after key ordering")
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 var broken:Dictionary=saved.duplicate(true);broken.contracts[0].route_layout={"schema":Layout.SCHEMA,"id":"future"}
 write_primary(broken);var blocked=Econ.new();blocked.load_state()
 check(blocked.review_load_blocked,"unknown future layout is preserved as blocked instead of silently falling back")

func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Use isolated XDG_DATA_HOME");quit(2);return
 for key in ["COURIER_OLD_ACCEPTED","COURIER_OLD_THIRD_COMPLETE"]:
  if OS.get_environment(key).is_empty():printerr("Missing read-only source "+key);quit(2);return
 test_layout();test_native_old_accepted();test_completed_native_entry();test_synthetic_old_fragile()
 for path in sources:check(FileAccess.get_file_as_bytes(path)==sources[path],"native source file remains unchanged "+str(path))
 clear_files();print("FRAGILE_ROUTE_CONTRACTS_V1 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
