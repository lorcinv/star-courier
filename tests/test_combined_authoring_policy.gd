extends SceneTree
## Composition/transaction tests. Synthetic ordinary telemetry is ledger-only
## test input, never evidence of human flight fairness or natural native play.
const Econ=preload("res://scripts/economy.gd")
const FrozenEcon=preload("res://tests/fixtures/economy_pre_combined.gd")
const Combined=preload("res://scripts/combined_offer_authoring_policy.gd")
const Previous=preload("res://scripts/protected_bird_authoring_policy.gd")
const Ordinary=preload("res://scripts/readable_commercial_authoring_policy.gd")
const Catalog=preload("res://scripts/readable_offer_catalog.gd")
const Readable=preload("res://scripts/readable_offer_guard.gd")
const Bird=preload("res://scripts/protected_bird_offer_v1.gd")
const Seeded=preload("res://scripts/seeded_offer_catalog.gd")
const Meteor=preload("res://scripts/orbital_meteor_offers.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Reviews=preload("res://scripts/customer_reviews_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Camera=preload("res://scripts/readable_corridor_framing_2d.gd")
var assertions:int=0
var failures:Array=[]
var progression:Array=[]

class PoisonedPostBird:
 extends Econ
 var poison:bool=false
 func ensure_contracts() -> void:
  super.ensure_contracts()
  if poison and day>=5 and contracts.size()==2:contracts[0].weight=true
class PoisonedSecond:
 extends Econ
 var poison:bool=false
 func ensure_contracts() -> void:
  super.ensure_contracts()
  if poison and day>=5 and contracts.size()==2:contracts[1].control_version=true
class ForeignGenerated:
 extends Econ
 var poison:bool=false
 func _new_seeded_offer(catalog:Dictionary,slot:int) -> Dictionary:
  if poison and day>1 and slot==1:
   var root:Dictionary=offer_generation_state.duplicate(true);root.world_seed+=1
   return AuthoringPolicy.author(catalog,_autonomous_routes()[int(catalog.id)],root,day,slot,"ground" if int(catalog.id)==0 else "ascent",Stories.IDS[posmod((day-1)*2+slot,Stories.IDS.size())])
  return super._new_seeded_offer(catalog,slot)
class FailedSecond:
 extends Econ
 var poison:bool=false
 func _new_seeded_offer(catalog:Dictionary,slot:int) -> Dictionary:
  if poison and slot==1:return {"ok":false,"offer":{},"error":"Private injected authoring diagnostic."}
  return super._new_seeded_offer(catalog,slot)

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 assertions+=1
 if not ok:failures.append(label);push_error("FAIL "+label)
func bytes(value:Variant) -> String:return JSON.stringify(value,"",true,true)
func same(a:Variant,b:Variant) -> bool:return Readable.same(a,b)
func actor(day_value:int,slot:int=0) -> String:return Stories.IDS[posmod((day_value-1)*2+slot,Stories.IDS.size())]
func root(seed_value:Variant=42,introduced:Variant=0) -> Dictionary:return {"version":Combined.CURRENT_VERSION,"world_seed":seed_value,"ordinary_policy":Ordinary.CURRENT_VERSION,"introduced_day":introduced}
func bird_root(seed_value:int=42,introduced:int=0) -> Dictionary:return {"version":Previous.VERSION,"world_seed":seed_value,"introduced_day":introduced}
func base(id:int) -> Dictionary:
 var value:Dictionary=Econ.new()._autonomous_routes()[id]
 return Ground.route(value) if id==0 else Extreme.route(value)
func snapshot(e) -> Dictionary:
 var result:Dictionary={}
 for key in ["credits","reputation","day","phase","jobs_today","deliveries","research","workshop_tier","contracts","active_contract_id","last_trials","story_state","review_state","offer_generation_state","load_notice","story_mode","in_flight","settled_ids","history","last_settlement","inventory","designs"]:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result
func clean() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func write_save(path:String,value:Dictionary) -> void:
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(bytes(value));file.close()
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func setup(e=Econ.new(),day_value:int=4,rep:int=7,root_value:Dictionary={}):
 e.day=day_value;e.reputation=rep;e.flight_mode=Extreme.CONTROL_VERSION;e.story_state=Stories.initial_state(42);e.story_mode=true
 e.review_state=Reviews.initial_state(day_value)
 e.offer_generation_state={"version":Combined.Legacy.VERSION,"world_seed":42} if root_value.is_empty() else root_value.duplicate(true)
 e.ensure_contracts()
 return e
func ledger_success(e,slot:int=0) -> bool:
 var id:String=e.contracts[slot].contract_id
 if not e.accept_contract(id).ok:return false
 if not e.mark_cargo_loaded(id).ok:return false
 if not e.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher()).ok:return false
 return e.settle_contract_and_save(id,{"integrity":1.0,"energy_used":120.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},10.0,true,[],[],{}).ok
func night_with_pending(e=Econ.new()):
 e=setup(e)
 check(ledger_success(e),"old day-four normal ledger fixture settled")
 check(e.close_day().ok and e.save_state([],[],{}),"old day-four night and pending review saved")
 return e

func run() -> void:
 _root_schemas()
 _authoring_sources()
 _recognition()
 _future_batches()
 _transactions()
 _fresh_boundary()
 _saved_and_recovery()
 _normal_economy_progression()
 var report:Dictionary={"assertions":assertions,"failures":failures,"progression":progression,"engine":Engine.get_version_info().string,"scope":"Combined CPU source-policy, exact saved compatibility and transactional ledger tests. Ordinary progression uses explicit synthetic telemetry; no native/gameplay/human fairness claim."}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):
   var file=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
   if file!=null:file.store_string(JSON.stringify(report,"  ",true,true));file.close()
 clean();print("COMBINED_AUTHORING assertions=%d failures=%d"%[assertions,failures.size()]);quit(0 if failures.is_empty() else 1)

func _root_schemas() -> void:
 var states:Array=[{"version":Seeded.VERSION,"world_seed":42},{"version":Combined.Legacy.VERSION,"world_seed":42},{"version":Ordinary.CURRENT_VERSION,"world_seed":42},bird_root(),bird_root(42,5),root(),root(42,5)]
 for state in states:
  check(Combined.supported_root(state),"exact prior/current root recognized")
  var old_bytes:String=bytes(state)
  var transition:Dictionary=Combined.next_day_root(state,8)
  check(transition.ok and transition.state.version==Combined.CURRENT_VERSION and transition.state.ordinary_policy==Ordinary.CURRENT_VERSION,"explicit composition persists its selected ordinary policy")
  check(bytes(state)==old_bytes and transition.state.world_seed==42 and transition.state.introduced_day==state.get("introduced_day",0),"migration preserves source bytes, shop seed and introduction ledger")
  var changed:Dictionary=state.duplicate(true);changed.unrecognized_field=true
  check(not Combined.supported_root(changed),"every registered root is a closed schema")
 for bad in [null,true,"42",-1,0.5,2147483647,NAN,INF]:check(not Combined.supported_root(root(bad)),"invalid root seed rejected before cast")
 for bad in [null,true,"5",-1,1,4,5.5,1000001,NAN,INF]:check(not Combined.supported_root(root(42,bad)),"invalid introduction ledger rejected before cast")
 for field in Combined.CURRENT_KEYS:
  var changed:Dictionary=root();changed.erase(field)
  check(not Combined.supported_root(changed),"missing combined field rejected "+field)
 var changed:Dictionary=root();changed.ordinary_policy=Combined.Legacy.VERSION
 check(not Combined.supported_root(changed) and Combined.future_root(changed),"current composition cannot silently select an unstated old ordinary policy")
 changed=root();changed.version=Combined.COMBINED_PREFIX+"v999"
 check(not Combined.next_day_root(changed,8).ok and Combined.future_root(changed),"future composition remains opaque")
 check(not Combined.next_day_root(root(42,8),7).ok,"next-day cannot travel before prior introduction")
 check(not Combined.next_day_root(root(),0).ok,"missing/default boundary day cannot activate composition")
 var raw:Dictionary={"offer_generation_state":root(42,5),"contracts":[],"settings":{"protected_bird_schema":1,"offer_authoring_policy":Combined.CURRENT_VERSION}}
 var raw_bytes:String=bytes(raw)
 check(not Reviews.opaque_error(raw).is_empty() and Reviews.opaque_error(Combined.review_inspection(raw)).is_empty(),"only explicit known strict root is projected for frozen review protocol inspection")
 check(bytes(raw)==raw_bytes and Combined.review_inspection(raw).settings.offer_authoring_policy==Combined.CURRENT_VERSION,"review inspection cannot mutate actual stored root or settings")
 raw.offer_generation_state.extra=true
 check(bytes(Combined.review_inspection(raw))==bytes(raw) and not Reviews.opaque_error(Combined.review_inspection(raw)).is_empty(),"malformed composition cannot acquire the legacy review protocol projection")
 check(bytes(Previous.next_day_root({"version":Combined.Legacy.VERSION,"world_seed":42},4).state)==bytes({"version":Combined.Legacy.VERSION,"world_seed":42}),"frozen previous bird wrapper still has original next-day bytes")

func _authoring_sources() -> void:
 var fresh:Array=Econ.new()._autonomous_routes()
 var meteor_count:int=0
 for seed_value in [0,1,42,807,2147483646]:
  for day_value in [1,2,5,8]:
   for id in [0,1,2]:
    for slot in [0,1]:
     var kind:String="ground" if id==0 else "ascent"
     for state in [{"version":Seeded.VERSION,"world_seed":seed_value},{"version":Combined.Legacy.VERSION,"world_seed":seed_value},bird_root(seed_value),bird_root(seed_value,5)]:
      var old_bytes:String=bytes(state)
      check(bytes(Combined.author(base(id),fresh[id],state,day_value,slot,kind,actor(day_value,slot)))==bytes(Previous.author(base(id),fresh[id],state,day_value,slot,kind,actor(day_value,slot))),"old direct-root complete output bytes unchanged")
      check(bytes(state)==old_bytes,"old source root never mutated")
     var state:Dictionary=root(seed_value);var old_bytes:String=bytes(state)
     var offer:Dictionary=Combined.author(base(id),fresh[id],state,day_value,slot,kind,actor(day_value,slot))
     check(offer.ok and bytes(offer)==bytes(Ordinary.author(base(id),fresh[id],{"version":Ordinary.CURRENT_VERSION,"world_seed":seed_value},day_value,slot,kind,actor(day_value,slot))),"explicit ordinary selector returns exact reviewed readable/meteor output")
     var legacy:Dictionary={"version":Combined.Legacy.VERSION,"world_seed":seed_value}
     if Combined.Legacy.selects_meteor(legacy,day_value,slot,id):
      meteor_count+=1
      check(bytes(offer)==bytes(Combined.Legacy.author(base(id),fresh[id],legacy,day_value,slot,kind,actor(day_value,slot))),"ordinary meteor selection and snapshot bytes retain exact old domain")
     elif offer.ok:check(Readable.recognized(offer.offer),"remaining ordinary generated routes fully validate")
     check(bytes(state)==old_bytes,"composed ordinary authoring never mutates independent bird root")
 check(meteor_count>0,"meteor parity sampled selected cases")
 for day_value in [5,6,9]:
  var composed:Dictionary=root(42,0);var projected:Dictionary=Combined.bird_root(composed)
  check(bytes(Bird.create_new_offer(projected,day_value,actor(day_value)))==bytes(Bird.create_new_offer(bird_root(),day_value,actor(day_value))),"independent bird complete snapshot and derived seed unchanged")
  check(Combined.selects_bird(composed,day_value,7,{"id":0}) and not Combined.selects_bird(root(42,5),day_value,7,{"id":0}),"bird selection is exactly once")
  check(not Combined.selects_bird(composed,day_value,7,{"id":4}) and not Combined.selects_bird(composed,day_value,6,{"id":0}),"Moon and reputation guards retained")
 check(not Combined.selects_bird(root(),4,10,{"id":0}),"no first-four-days bird")

func _recognition() -> void:
 var ordinary:Dictionary=Catalog.create_new_offer(base(2),{"version":Ordinary.CURRENT_VERSION,"world_seed":42},8,1,"ascent",actor(8,1)).offer
 check(Combined.known_route(ordinary) and not Combined.known_offer(ordinary.generation.version),"dedicated full commercial route, never broad version membership")
 for field in ["readable_offer_schema","generation"]:
  var bad:Dictionary=ordinary.duplicate(true);bad.erase(field)
  check(not Combined.known_route(bad) and not Econ.route_validation_error(bad).is_empty(),"incomplete commercial marker set rejected")
 for field in ["world_seed","version","readable_commercial_adapter","authoring_policy"]:
  var bad:Dictionary=ordinary.duplicate(true);bad.generation[field]="forged"
  check(not Combined.known_route(bad) and Econ.route_validation_error(bad)=="这份航线记录不完整，暂时无法出发。","forged marked snapshot rejected with Chinese copy")
 var borrowed:Dictionary=ordinary.duplicate(true);borrowed.generation.version=Seeded.VERSION
 check(not Combined.known_route(borrowed),"forged commercial marker cannot borrow old known version")
 var special:Dictionary=Bird.create_new_offer(bird_root(),5,actor(5)).offer
 check(Combined.known_route(special) and not Camera.applies(special),"exact bird protocol recognized without forward-edge camera")
 special.generation.version=Seeded.VERSION
 check(not Combined.known_route(special) and not Econ.route_validation_error(special).is_empty(),"forged bird protocol cannot borrow old known version")
 var opaque:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/readable_opaque_qa.json"))["ascent-heavy"]
 check(not Combined.known_route(opaque) and bytes(Econ._review_order(opaque))==bytes(FrozenEcon._review_order(opaque)),"prior unregistered readable QA keeps old opaque review projection bytes")
 opaque.generation.commercial_adapter="future-experiment"
 check(not Combined.known_route(opaque),"unrelated future adapter key cannot register commercial identity")
 var pursuit:Dictionary=ordinary.duplicate(true);pursuit.route_kind="pursuit"
 check(not Camera.applies(pursuit),"forward-only framing refuses pursuit route kind")

func _future_batches() -> void:
 clean()
 var e=setup();e.close_day();var old_root:String=bytes(e.offer_generation_state)
 check(e.next_day_and_save([],[],{}).ok,"real old-night-to-composed-morning transaction")
 check(e.day==5 and e.offer_generation_state.version==Combined.CURRENT_VERSION and e.offer_generation_state.introduced_day==5,"day-five claim and underlying ordinary policy commit together")
 check(Bird.has_markers(e.contracts[0]) and Bird.validation_error(e.contracts[0]).is_empty() and e._authored_batch_error().is_empty(),"full final batch validation includes post-replacement bird")
 var old=setup(FrozenEcon.new());old.close_day();check(old.next_day().ok,"frozen bird day-five expected batch")
 check(bytes(old.contracts)==bytes(e.contracts) and bytes(old.story_state)==bytes(e.story_state),"day-five bird and special second-slot snapshots retain exact old story/binding bytes")
 check(bytes(old.offer_generation_state)!=bytes(e.offer_generation_state) and old_root!=bytes(e.offer_generation_state),"only explicit root composition differs at transition")
 for later in [6,7,8]:
  var before:Dictionary=snapshot(e)
  var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode();loaded.enable_seeded_offers(999)
  check(same(loaded.contracts,e.contracts) and same(loaded.offer_generation_state,e.offer_generation_state),"saved/restarted composed morning cannot reroll offers/claim")
  e=loaded;check(e.close_day().ok and e.next_day_and_save([],[],{}).ok and e.day==later,"future day advances through ordinary economy save wrapper")
  check(e.offer_generation_state.introduced_day==5 and not Bird.has_markers(e.contracts[0]) and not Bird.has_markers(e.contracts[1]),"later morning never introduces bird again")
  for order in e.contracts:
   if int(order.id)<=2:check(Readable.recognized(order) or Meteor.has_markers(order),"future ordinary cards use explicit readable/meteor source")
  check(e._authored_batch_error().is_empty(),"every future full batch validates before publication")
 clean()
 var moon=setup(Econ.new(),4,10);moon.close_day();check(moon.next_day_and_save([],[],{}).ok,"Moon eligible composed boundary saves")
 check(moon.contracts[0].id==4 and moon.contracts[1].id==4 and moon.offer_generation_state.introduced_day==0,"day-five Moon snapshot defers bird without consuming introduction")
 check(moon.close_day().ok and moon.next_day_and_save([],[],{}).ok and Bird.has_markers(moon.contracts[0]) and moon.contracts[1].id==4 and moon.offer_generation_state.introduced_day==6,"next eligible morning introduces once and preserves independent Moon slot")
 clean()

func _transactions() -> void:
 clean();var e=night_with_pending();var before:Dictionary=snapshot(e);var disk_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var outcome:Dictionary=e.next_day_and_save([],[],{})
 check(not outcome.ok and same(before,snapshot(e)),"failed write rolls back introduction/root/date/offers/story/reviews/finances")
 check(outcome.message=="无法创建临时存档，原存档未改变。" and FileAccess.get_file_as_string("user://savegame.json")==disk_bytes,"failed write uses Chinese message and preserves exact disk bytes")
 check(e.review_state.pending.size()==1 and e.customer_reviews().is_empty() and not e.offer_generation_state.has("introduced_day"),"failed write cannot publish morning review or consume bird claim")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.next_day_and_save([],[],{}).ok and e.offer_generation_state.introduced_day==5 and e.customer_reviews().size()==1,"successful retry commits bird and single next-morning review")
 var feed:String=bytes(e.customer_reviews());var restart=Econ.new();restart.load_state()
 check(bytes(restart.customer_reviews())==feed and restart.offer_generation_state.introduced_day==5,"introduction and published review survive restart together")
 for model in [PoisonedPostBird.new(),PoisonedSecond.new()]:
  clean();model=night_with_pending(model);before=snapshot(model);disk_bytes=FileAccess.get_file_as_string("user://savegame.json");model.poison=true
  outcome=model.next_day_and_save([],[],{})
  check(not outcome.ok and same(before,snapshot(model)) and FileAccess.get_file_as_string("user://savegame.json")==disk_bytes,"invalid completed post-bird pair rolls back every morning field and disk")
  check(model.review_state.pending.size()==1 and model.customer_reviews().is_empty(),"post-bird validation precedes pending-review publication")
 clean();var foreign=setup(ForeignGenerated.new(),1,4);foreign.close_day();before=snapshot(foreign);foreign.poison=true
 check(not foreign.next_day().ok and same(before,snapshot(foreign)),"otherwise valid generated second offer from another root fails full batch provenance validation")
 var failed=setup(FailedSecond.new(),1,4);failed.close_day();before=snapshot(failed);failed.poison=true
 outcome=failed.next_day()
 check(not outcome.ok and same(before,snapshot(failed)) and outcome.message=="今日航线暂时无法整理，原进度已保留。请使用对应版本继续。","second author failure preserves all state with public Chinese message")
 clean()

func _fresh_boundary() -> void:
 for day_value in [1,5,7]:
  clean();var e=Econ.new();e.day=day_value;e.reputation=7;e.enable_extreme_mode();var before:Dictionary=snapshot(e)
  DirAccess.make_dir_absolute("user://savegame.tmp")
  check(not e.author_readable_batch_and_save(42,[],[],{}).ok and same(before,snapshot(e)),"failed optional empty-batch API restores seed/introduced-day/story/reviews/finances")
  DirAccess.remove_absolute("user://savegame.tmp")
  check(e.author_readable_batch_and_save(42,[],[],{}).ok and e.offer_generation_state.version==Combined.CURRENT_VERSION,"explicit empty batch atomically saves strict composed root")
  check(Bird.has_markers(e.contracts[0])==(day_value>=5) and e.offer_generation_state.introduced_day==(day_value if day_value>=5 else 0),"standalone readable API cannot bypass a due bird introduction")
  before=snapshot(e);check(not e.author_readable_batch_and_save(999,[],[],{}).ok and same(before,snapshot(e)),"optional API refuses existing saved/accepted batches without reroll")
  var raw:Dictionary=disk();check(raw.settings.offer_authoring_policy==Combined.CURRENT_VERSION and raw.settings.protected_bird_schema==1 and same(raw.offer_generation_state,e.offer_generation_state),"actual composed policy and bird schema persisted explicitly")
 clean();var existing=setup(Econ.new(),5,7,root());existing.contracts=[]
 var existing_before:Dictionary=snapshot(existing)
 check(not existing.author_readable_batch_and_save(999,[],[],{}).ok and same(existing_before,snapshot(existing)),"clearing a current bird batch cannot bypass saved introduction or identity ledger")
 existing=setup(Econ.new(),2,4,root());existing.contracts=[];existing_before=snapshot(existing)
 check(not existing.author_readable_batch_and_save(999,[],[],{}).ok and same(existing_before,snapshot(existing)),"clearing saved ordinary cards cannot bypass existing daily story bindings")
 clean();var old=Econ.new();old.day=7;old.reputation=7;old.enable_extreme_mode();old.offer_generation_state=bird_root(42,5)
 check(old.author_readable_batch_and_save(999,[],[],{}).ok and old.offer_generation_state.world_seed==42 and old.offer_generation_state.introduced_day==5 and not Bird.has_markers(old.contracts[0]),"empty existing bird root migrates without resetting seed or introduction")
 var invalid=Econ.new();invalid.enable_extreme_mode();var before:Dictionary=snapshot(invalid)
 var result:Dictionary=invalid.author_readable_batch_and_save(true,[],[],{})
 check(not result.ok and result.message=="航线记录不完整，原进度已保留。" and same(before,snapshot(invalid)),"invalid explicit seed never leaks private guard text or mutates state")
 clean()

func _saved_and_recovery() -> void:
 clean();var old=setup(FrozenEcon.new(),5,7,bird_root());var current=setup(Econ.new(),5,7,bird_root())
 check(bytes(snapshot(old))==bytes(snapshot(current)),"old bird-root authoring and identity bytes equal frozen loader/runtime")
 for e in [old,current]:check(e.accept_contract("D5-A").ok and e.mark_cargo_loaded("D5-A").ok,"old bird route accepted and loaded unchanged")
 check(bytes(current.contracts)==bytes(old.contracts) and bytes(current.trial_route())==bytes(old.trial_route()) and bytes(current.story_conversation("D5-A","accept"))==bytes(old.story_conversation("D5-A","accept")),"old accepted bird route/trial/story opening bytes unchanged")
 check(current.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher()).ok and old.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher()).ok,"old bird formal launch remains supported")
 check(bytes(current.in_flight)==bytes(old.in_flight) and current.save_state([],[],{}),"old bird in-flight exact protocol/seed/geometry persisted")
 var saved_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
 var a=Econ.new();var b=FrozenEcon.new();a.load_state();b.load_state()
 check(bytes(a.contracts)==bytes(b.contracts) and bytes(a.in_flight)==bytes(b.in_flight) and bytes(a.story_state)==bytes(b.story_state) and bytes(a.review_state)==bytes(b.review_state),"old bird exact serialized loader/story/review bytes unchanged")
 a.enable_story_mode();a.enable_seeded_offers(999);check(FileAccess.get_file_as_string("user://savegame.json")==saved_bytes and same(a.offer_generation_state,current.offer_generation_state) and same(a.in_flight,current.in_flight),"load/enable cannot reroll accepted or in-flight bird snapshot/root")
 clean();var e=Econ.new();e.enable_extreme_mode();check(e.author_readable_batch_and_save(42,[],[],{}).ok,"current composite recovery fixture")
 var good:Dictionary=disk()
 for state in [{"version":Seeded.VERSION,"world_seed":42},{"version":Combined.Legacy.VERSION,"world_seed":42},{"version":Ordinary.CURRENT_VERSION,"world_seed":42},bird_root(),root(),{"version":"future-root-v999","world_seed":42}]:
  var binding:Dictionary=good.duplicate(true);binding.offer_generation_state=state.duplicate(true);binding.settings.erase("offer_authoring_policy");binding.settings.erase("protected_bird_schema")
  check(e._valid_save(binding),"valid saved readable root-seed binding fixture for historical/current/opaque root")
  binding.offer_generation_state.world_seed=43
  check(not e._valid_save(binding),"known route rejects root-seed mismatch independently of root markers")
 for mode in ["future-version","future-underlying"]:
  var future:Dictionary=good.duplicate(true)
  if mode=="future-version":future.offer_generation_state.version=Combined.COMBINED_PREFIX+"v999";future.settings.offer_authoring_policy=future.offer_generation_state.version
  else:future.offer_generation_state.ordinary_policy="future-ordinary-policy-v999"
  write_save("user://savegame.json",future);write_save("user://savegame.backup.json",good)
  var original_bytes:String=FileAccess.get_file_as_string("user://savegame.json");var recovered=Econ.new();var raw:Dictionary=recovered.load_state()
  check(recovered.review_load_blocked and same(raw.offer_generation_state,future.offer_generation_state),"future composition recovery outranks playable old backup "+mode)
  check(not recovered.save_state([],[],{}) and FileAccess.get_file_as_string("user://savegame.json")==original_bytes and recovered.load_notice=="此存档含暂不支持的委托编排规则。原始记录已保留，请勿覆盖。","future composition preserves source and exposes Chinese read-only recovery")
 for malformed in ["extra-field","missing-field","bad-introduction"]:
  clean();var damaged:Dictionary=good.duplicate(true)
  if malformed=="extra-field":damaged.offer_generation_state.extra=true
  elif malformed=="missing-field":damaged.offer_generation_state.erase("ordinary_policy")
  else:damaged.offer_generation_state.introduced_day=5
  check(not e._valid_save(damaged),"strict current root rejected "+malformed)
  write_save("user://savegame.json",damaged);var original_bytes:String=FileAccess.get_file_as_string("user://savegame.json");var recovered=Econ.new();recovered.load_state()
  check(recovered.review_load_blocked and not recovered.save_state([],[],{}) and FileAccess.get_file_as_string("user://savegame.json")==original_bytes,"damaged current root preserved without creating replacement shop")
 clean();write_save("user://savegame.json",good)
 var forged:Dictionary=good.duplicate(true);forged.contracts[0].generation.readable_commercial_adapter="forged"
 write_save("user://savegame.json",forged);var original_bytes:String=FileAccess.get_file_as_string("user://savegame.json");var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode()
 check(same(loaded.contracts,forged.contracts) and FileAccess.get_file_as_string("user://savegame.json")==original_bytes,"damaged marked route retained without loader regeneration or rebinding")
 var rejected:Dictionary=loaded.accept_contract(str(forged.contracts[0].contract_id))
 check(not rejected.ok and rejected.message=="这份航线记录不完整，暂时无法出发。","forged saved commercial route blocked before accept")
 clean()

func _normal_economy_progression() -> void:
 # Four consecutive economy days, natural root adoption and reputation gains.
 # Physics success is intentionally synthetic here; native plan is separate.
 clean();var e=Econ.new();e.enable_extreme_mode();e.story_state=Stories.initial_state(42);e.enable_story_mode();e.enable_seeded_offers(42)
 var total:int=0
 for expected_day in [1,2,3,4]:
  check(e.day==expected_day and e.contracts.size()==2,"consecutive normal economy morning")
  for slot in [0,1]:
   var order:Dictionary=e.contracts[slot]
   check(not Bird.has_markers(order),"no early bird injection during ordinary progression")
   var cash:int=e.credits;var id:String=order.contract_id
   check(ledger_success(e,slot),"ordinary accept/load/dispatch/settle/save sequence")
   total+=1
   check(e.credits>cash and e.review_state.pending.has(id) and e.story_state.committed_contract_ids.has(id),"normal income, pending review and exact recurring story advance together")
   var settled_cash:int=e.credits
   check(not e.settle_contract(id,{},0,true).ok and e.credits==settled_cash,"duplicate receipt never pays twice in progression")
  progression.append({"day":e.day,"credits":e.credits,"reputation":e.reputation,"root":e.offer_generation_state.duplicate(true),"published":e.customer_reviews().size(),"pending":e.review_state.pending.size(),"orders":e.contracts.duplicate(true)})
  check(e.close_day().ok and e.next_day_and_save([],[],{}).ok,"normal close/next-morning authoring/publication atomic transition")
  var saved:Dictionary=snapshot(e);var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode();loaded.enable_seeded_offers(999)
  check(same(saved,snapshot(loaded)),"normal economy restart preserves all typed progression values")
  e=loaded;check(e.customer_reviews().size()==total,"each receipt publishes exactly once next morning")
 check(e.day==5 and e.offer_generation_state.version==Combined.CURRENT_VERSION and e.offer_generation_state.introduced_day==0 and e.contracts[0].id==4,"natural rep unlock preserves day-five Moon before bird")
 check(e.close_day().ok and e.next_day_and_save([],[],{}).ok and e.day==6 and e.offer_generation_state.introduced_day==6 and Bird.has_markers(e.contracts[0]),"first eligible normal morning schedules independent bird exactly once")
 clean()
