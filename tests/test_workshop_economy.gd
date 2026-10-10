extends SceneTree
## Pure tier/accounting regression. Run only with an isolated XDG_DATA_HOME.
const Econ=preload("res://scripts/economy.gd")
const Workshop=preload("res://scripts/workshop_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Stories=preload("res://scripts/courier_stories.gd")
var passed:int=0
var failed:int=0

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("Workshop economy tests require an isolated XDG_DATA_HOME.");quit(2);return
 clear_files()
 test_tier_profiles();test_purchase_guards();test_restart();test_legacy_versions()
 test_frozen_dispatches();test_failed_save_rollback();test_invalid_tier_backup();test_research_independence()
 clear_files()
 print("WORKSHOP_ECONOMY passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)

func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)

func normalized(value:Variant) -> Variant:return JSON.parse_string(JSON.stringify(value,"",true,true))
func same(a:Variant,b:Variant,label:String) -> void:check(normalized(a)==normalized(b),label)

func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)

func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func write_primary(value:Dictionary) -> void:
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(value,"",true,true));file.close()

func craft() -> Array:return Extreme.starter_design()
func pad() -> Array:return Extreme.starter_launcher()

func economy():
 var e=Econ.new();e.enable_extreme_mode();e.starter_stock(craft(),pad())
 e.story_state=Stories.initial_state(1729);e.enable_story_mode()
 e.designs={"workbench":{"design":craft(),"launcher":pad()}}
 return e

func snapshot(e) -> Dictionary:
 return {"credits":e.credits,"workshop_tier":e.workshop_tier,"research":e.research,"reputation":e.reputation,"day":e.day,"phase":e.phase,"jobs_today":e.jobs_today,"deliveries":e.deliveries,"inventory":e.inventory.duplicate(true),"designs":e.designs.duplicate(true),"contracts":e.contracts.duplicate(true),"active_contract_id":e.active_contract_id,"in_flight":e.in_flight.duplicate(true),"flight_mode":e.flight_mode,"settled_ids":e.settled_ids.duplicate(true),"history":e.history.duplicate(true),"last_settlement":e.last_settlement.duplicate(true),"last_trials":e.last_trials.duplicate(true),"story_state":e.story_state.duplicate(true),"story_mode":e.story_mode}

func unrelated(e) -> Dictionary:
 var value:Dictionary=snapshot(e);value.erase("credits");value.erase("workshop_tier");return value

func reject_unchanged(e,target:int,label:String) -> void:
 var before:Dictionary=snapshot(e)
 check(not e.workshop_upgrade(target).get("ok",false),label+" is rejected")
 same(snapshot(e),before,label+" has no partial mutation")

func test_tier_profiles() -> void:
 var sizes:Array[Vector2i]=[Vector2i(9,5),Vector2i(13,7),Vector2i(17,9)]
 var starts:Array[Vector2i]=[Vector2i(-4,-2),Vector2i(-4,-4),Vector2i(-4,-6)]
 var ends:Array[Vector2i]=[Vector2i(5,3),Vector2i(9,3),Vector2i(13,3)]
 for tier in range(3):
  var box:Rect2i=Workshop.bounds(tier)
  check(Workshop.is_valid_tier(tier) and box.position==starts[tier] and box.end==ends[tier],"tier %d uses approved asymmetric bounds"%tier)
  check(Workshop.grid_size(tier)==sizes[tier] and box.get_area()==sizes[tier].x*sizes[tier].y,"tier %d grid size and area"%tier)
  for y in range(box.position.y,box.end.y):
   for x in range(box.position.x,box.end.x):
    check(Workshop.contains_cell(tier,Vector2i(x,y)),"tier %d includes cell (%d,%d)"%[tier,x,y])
  for x in range(box.position.x-1,box.end.x+1):
   check(not Workshop.contains_cell(tier,Vector2i(x,box.position.y-1)),"tier %d rejects row immediately above x%d"%[tier,x])
   check(not Workshop.contains_cell(tier,Vector2i(x,box.end.y)),"tier %d excludes bottom endpoint x%d"%[tier,x])
  for y in range(box.position.y,box.end.y):
   check(not Workshop.contains_cell(tier,Vector2i(box.position.x-1,y)),"tier %d rejects left-adjacent cell y%d"%[tier,y])
   check(not Workshop.contains_cell(tier,Vector2i(box.end.x,y)),"tier %d excludes right endpoint y%d"%[tier,y])
  if tier>0:
   var previous:Rect2i=Workshop.bounds(tier-1)
   check(box.encloses(previous),"tier %d preserves every cell from previous tier"%tier)
   check(box.position.x==previous.position.x and box.end.y==previous.end.y,"tier %d grows right and up only"%tier)
 check(Workshop.purchase_cost(0)==0 and Workshop.purchase_cost(1)==180 and Workshop.purchase_cost(2)==420,"approved per-tier costs")
 check(Workshop.next_tier(0)==1 and Workshop.next_tier(1)==2 and Workshop.next_tier(2)==-1,"next tier caps at two")
 for invalid in [-99,-1,3,99]:
  check(not Workshop.is_valid_tier(invalid) and Workshop.bounds(invalid).get_area()==0,"invalid tier cannot expose cells: %d"%invalid)
  check(not Workshop.contains_cell(invalid,Vector2i.ZERO) and Workshop.purchase_cost(invalid)==-1 and Workshop.next_tier(invalid)==-1,"invalid tier cannot become a free purchase: %d"%invalid)
 check(Workshop.assembly_origin(0)==Vector2(728,288),"base assembly registration remains unchanged")
 check(Workshop.assembly_origin(1)==Vector2(2196,198) and Workshop.bay_top_left(1)==Vector2(1040,-560),"tier one registration matches upward-growth art study")
 check(Workshop.assembly_origin(2)==Vector2(2352,186) and Workshop.bay_top_left(2)==Vector2(1040,-802),"tier two registration matches upward-growth art study")
 check(Workshop.CELL==72.0 and Workshop.FLOOR_Y==486.0,"cell scale and actor floor remain unchanged")

func test_purchase_guards() -> void:
 var e=economy();e.credits=5000
 check(e.workshop_tier==0 and e.workshop_upgrade_cost()==180,"new shop starts with free tier zero")
 reject_unchanged(e,1,"morning purchase")
 e.phase="day";reject_unchanged(e,1,"daytime purchase")
 e.phase="night";reject_unchanged(e,2,"skipping tier one")
 for target in [-1,0,3,999]:reject_unchanged(e,target,"invalid/current initial tier %d"%target)
 e.credits=179;reject_unchanged(e,1,"unaffordable first expansion")
 e.credits=180;var before:Dictionary=unrelated(e);var first:Dictionary=e.workshop_upgrade(1)
 check(first.ok and first.changed and first.cost==180 and e.credits==0 and e.workshop_tier==1,"exact first-tier funds purchase atomically")
 check(first.previous_tier==0 and first.previous_credits==180 and first.tier==1,"first-tier response exposes precise rollback state")
 same(unrelated(e),before,"expansion neither grants inventory nor changes blueprint IDs coordinates story or ledger")
 e.credits=5000
 for attempt in range(10):reject_unchanged(e,1,"duplicate tier-one click %d"%attempt)
 check(e.workshop_upgrade_cost()==420,"second expansion has independent 420-credit price")
 e.credits=419;reject_unchanged(e,2,"unaffordable second expansion")
 e.credits=420;before=unrelated(e);var second:Dictionary=e.workshop_upgrade(2)
 check(second.ok and second.cost==420 and e.credits==0 and e.workshop_tier==2,"exact second-tier funds purchase atomically")
 check(second.previous_tier==1 and second.previous_credits==420,"second-tier response exposes precise rollback state")
 same(unrelated(e),before,"second expansion changes no unrelated state")
 e.credits=5000
 for target in [0,1,2,3,999]:reject_unchanged(e,target,"max-tier stale/current/future target %d"%target)
 check(e.workshop_tier==2 and e.workshop_upgrade_cost()==-1,"maximum tier exposes no further purchase")

func test_restart() -> void:
 for tier in range(3):
  clear_files();var e=economy();e.phase="night";e.credits=1000
  for target in range(1,tier+1):check(e.workshop_upgrade(target).ok,"restart fixture purchases tier %d"%target)
  var custom:Array=craft();var box:Rect2i=Workshop.bounds(tier)
  custom.append(Extreme.part(700,"beam",box.end.x-1,box.position.y,{"input_a":2,"rot":3}))
  e.designs.workbench.design=custom.duplicate(true)
  var before:Dictionary=unrelated(e)
  check(e.save_state(custom,pad(),{"volume":.37}),"tier %d atomic save succeeds"%tier)
  check(int(disk().version)==5 and int(disk().workshop_tier)==tier,"tier %d persists in save schema five"%tier)
  var restored=Econ.new();var loaded:Dictionary=restored.load_state();restored.enable_story_mode()
  check(restored.workshop_tier==tier and restored.credits==e.credits,"tier %d and charged balance survive restart"%tier)
  same(loaded.design,custom,"tier %d outer-boundary design retains coordinates IDs rotation and wiring"%tier)
  same(restored.designs,e.designs,"tier %d named blueprints survive restart without clipping"%tier)
  same(unrelated(restored),before,"tier %d restart retains unrelated model state"%tier)
  reject_unchanged(restored,tier,"restarted stale purchase tier %d"%tier)
  var durable:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  var again=Econ.new();again.load_state()
  check(again.credits==e.credits and again.workshop_tier==tier,"second restart never repeats tier %d payment"%tier)
  check(FileAccess.get_file_as_bytes("user://savegame.json")==durable,"loading tier %d is read-only"%tier)

func test_legacy_versions() -> void:
 for version in [1,2,3,4]:
  clear_files();var e=economy();e.research=2;e.credits=731;e.phase="night"
  var legacy_design:Array=craft();legacy_design.append(Extreme.part(902,"beam",4,-2,{"input_a":2,"rot":1}))
  # Even preexisting out-of-bounds data must be returned intact by migration.
  # The presentation reports it separately; migration must not discard it.
  legacy_design.append(Extreme.part(903,"beam",15,-7,{"input_a":902}))
  e.designs.workbench.design=legacy_design.duplicate(true)
  check(e.save_state(legacy_design,pad(),{"volume":.42}),"legacy v%d fixture serializes"%version)
  var fixture:Dictionary=disk();fixture.version=version;fixture.erase("workshop_tier")
  if version<4:fixture.erase("story_state")
  write_primary(fixture)
  var bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  var migrated=Econ.new();migrated.workshop_tier=2;var loaded:Dictionary=migrated.load_state()
  check(not loaded.is_empty() and migrated.workshop_tier==0,"legacy v%d explicitly resets workshop to base tier"%version)
  check(migrated.credits==731 and migrated.research==2,"legacy v%d keeps credits and research"%version)
  same(loaded.design,legacy_design,"legacy v%d preserves valid and outlying cells instead of deleting IDs"%version)
  same(migrated.inventory,fixture.inventory,"legacy v%d preserves inventory"%version)
  same(migrated.designs,fixture.designs,"legacy v%d preserves saved blueprints"%version)
  check(FileAccess.get_file_as_bytes("user://savegame.json")==bytes,"legacy v%d load never rewrites disk"%version)
  check(migrated.save_state(loaded.design,loaded.launcher,loaded.settings),"legacy v%d can commit current schema"%version)
  check(int(disk().version)==5 and int(disk().workshop_tier)==0,"legacy v%d explicitly upgrades to schema five"%version)
  var again=Econ.new();again.load_state()
  check(again.workshop_tier==0 and again.credits==731,"migrated v%d restarts without a charge"%version)
  same(again.designs,fixture.designs,"migrated v%d blueprints persist exactly"%version)

func test_frozen_dispatches() -> void:
 for version in [2,3,4,5]:
  for protocol in ["autonomous-v5","pilot-v1","pilot-v2","pilot-v3"]:
   clear_files();var e=economy();e.credits=1000;e.research=2
   var cid:String=str(e.contracts[0].contract_id)
   e.accept_contract(cid);e.mark_cargo_loaded(cid);e.begin_dispatch(craft(),pad())
   e.in_flight.control_version=protocol;e.in_flight.route.control_version=protocol
   e.in_flight.route.pilot_energy_tariff=.037123456789;e.in_flight.route.custom_marker="keep-original-route"
   e.in_flight.ticks=37;e.in_flight.elapsed=37.0/60.0
   e.in_flight.input_commands=[{"tick":0,"axis_q":0,"boost":false,"active":false},{"tick":17,"axis_q":127,"boost":true,"active":false}]
   var receipt:Dictionary={"contract_id":"D0-A","profit":73,"success":true,"route":"原航线","energy_tariff":.18}
   e.settled_ids["D0-A"]=receipt.duplicate(true);e.history=[receipt.duplicate(true)];e.last_settlement=receipt.duplicate(true);e.last_trials={cid:{"profit":82,"elapsed":11.0}}
   e.save_state(craft(),pad(),{});var fixture:Dictionary=disk();fixture.version=version
   if version<5:fixture.erase("workshop_tier")
   if version<4:fixture.erase("story_state")
   write_primary(fixture)
   var loaded=Econ.new();loaded.load_state()
   for key in ["in_flight","contracts","active_contract_id","flight_mode","settled_ids","history","last_settlement","last_trials"]:
    same(loaded.get(key),fixture[key],"v%d/%s migration freezes %s"%[version,protocol,key])
   loaded.phase="night"
   reject_unchanged(loaded,1,"v%d/%s even inconsistent night cannot upgrade while in flight"%[version,protocol])
   loaded.in_flight={};var before:Dictionary=unrelated(loaded)
   check(loaded.workshop_upgrade(1).ok,"v%d/%s independent night upgrade succeeds"%[version,protocol])
   same(unrelated(loaded),before,"v%d/%s purchase never changes receipts routes stories or research"%[version,protocol])

func test_failed_save_rollback() -> void:
 clear_files();var e=economy();e.phase="night";e.credits=650
 check(e.save_state(craft(),pad(),{}),"rollback fixture persists original tier and credits")
 var previous:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 var before:Dictionary=snapshot(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var result:Dictionary=e.workshop_upgrade(1)
 check(result.ok and not e.save_state(craft(),pad(),{}),"blocked disk write rejects upgraded persistence")
 # Exercise the explicit response contract used by main's purchase handler.
 e.credits=int(result.previous_credits);e.workshop_tier=int(result.previous_tier)
 same(snapshot(e),before,"caller rollback restores the entire prior model exactly")
 check(not e.save_error.is_empty() and FileAccess.get_file_as_bytes("user://savegame.json")==previous,"failed save leaves previous durable file byte-for-byte intact")
 var restored=Econ.new();restored.load_state()
 check(restored.workshop_tier==0 and restored.credits==650,"restart after failure cannot keep half an upgrade")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.workshop_upgrade(1).ok and e.save_state(craft(),pad(),{}),"explicit retry purchases and persists once")
 var final_load=Econ.new();final_load.load_state()
 check(final_load.workshop_tier==1 and final_load.credits==470,"successful retry persists matching paid amount and tier")
 reject_unchanged(final_load,1,"successful retry duplicate after restart")

func test_invalid_tier_backup() -> void:
 clear_files();var e=economy();e.phase="night";e.credits=1000;e.workshop_upgrade(1)
 check(e.save_state(craft(),pad(),{}),"backup fixture tier one persists")
 e.workshop_upgrade(2);check(e.save_state(craft(),pad(),{}),"second save preserves tier one in valid backup")
 var valid:Dictionary=disk()
 for invalid in [-1,3,999,1.5,"2",true,null]:
  var corrupt:Dictionary=valid.duplicate(true);corrupt.workshop_tier=invalid;write_primary(corrupt)
  var recovered=Econ.new();var value:Dictionary=recovered.load_state()
  check(not value.is_empty() and recovered.workshop_tier==1 and recovered.credits==820,"invalid tier %s recovers matching tier/balance backup"%str(invalid))
  check(not recovered.load_notice.is_empty(),"invalid tier %s reports recovery"%str(invalid))
 var missing:Dictionary=valid.duplicate(true);missing.erase("workshop_tier");write_primary(missing)
 var recovered=Econ.new();recovered.load_state()
 check(recovered.workshop_tier==1 and recovered.credits==820,"v5 missing tier cannot silently shrink a paid workshop")
 clear_files();write_primary(valid);var intact=Econ.new();intact.load_state()
 check(intact.workshop_tier==2 and intact.credits==400,"valid maximum tier still loads when no backup exists")

func test_research_independence() -> void:
 for tier in range(3):
  var e=economy();e.phase="night";e.credits=5000;e.workshop_tier=tier
  for level in range(3):
   var before:int=e.credits;var cost:int=140+level*100
   check(e.research_cost()==cost,"tier %d research %d keeps old price"%[tier,level])
   check(e.research_upgrade().ok and e.research==level+1 and e.credits==before-cost,"tier %d research %d retains purchase behavior"%[tier,level])
   check(e.workshop_tier==tier,"battery calibration never changes workshop tier %d"%tier)
  var before:Dictionary=snapshot(e)
  check(not e.research_upgrade().ok,"tier %d still caps battery research at three"%tier)
  same(snapshot(e),before,"max battery research preserves all state at workshop tier %d"%tier)
 var first=economy();first.phase="night";first.credits=1000
 var second=economy();second.phase="night";second.credits=1000
 first.workshop_upgrade(1);first.research_upgrade();second.research_upgrade();second.workshop_upgrade(1)
 check(first.credits==680 and second.credits==680 and first.research==1 and first.workshop_tier==1,"research and expansion keep independent exact prices in either order")
 same(snapshot(first),snapshot(second),"research/expansion order has no unrelated side effects")
