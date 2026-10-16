extends SceneTree
## Permanent CPU integration tests, separate from frozen v1/meteor source tests.
const Econ=preload("res://scripts/economy.gd")
const OldEcon=preload("res://tests/fixtures/economy_pre_readable.gd")
const Policy=preload("res://scripts/readable_commercial_authoring_policy.gd")
const Combined=preload("res://scripts/combined_offer_authoring_policy.gd")
const OldPolicy=preload("res://tests/fixtures/offer_policy_pre_readable.gd")
const Catalog=preload("res://scripts/readable_offer_catalog.gd")
const Guard=preload("res://scripts/readable_offer_guard.gd")
const T=preload("res://scripts/readable_offer_templates.gd")
const Seeded=preload("res://scripts/seeded_offer_catalog.gd")
const Meteor=preload("res://scripts/orbital_meteor_offers.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ground=preload("res://scripts/pilot_ground_profile.gd")
const Moon=preload("res://scripts/pilot_moon_profile.gd")
const Wormhole=preload("res://scripts/pilot_wormhole_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
var assertions:int=0
var failures:Array=[]
var offer_count:int=0
var fallback_count:int=0
class FailedSecond:
 extends Econ
 func _new_seeded_offer(catalog:Dictionary,slot:int) -> Dictionary:
  if day>1 and slot==1:return {"ok":false,"offer":{},"error":"Explicit second-offer failure."}
  return super._new_seeded_offer(catalog,slot)
class PoisonedBatch:
 extends Econ
 func ensure_contracts() -> void:
  super.ensure_contracts()
  if day>1 and not contracts.is_empty():contracts[0].weight=true
func _initialize():run.call_deferred()
func check(value:bool,label:String) -> void:
 assertions+=1
 if not value:failures.append(label);push_error("FAIL "+label)
func bytes(value:Variant) -> String:return JSON.stringify(value,"",true,true)
func exact(a:Variant,b:Variant) -> bool:return Guard.same(a,b)
func root_state(seed_value:Variant=42) -> Dictionary:return {"version":T.ROOT_POLICY,"world_seed":seed_value}
func actor(day_value:int,slot:int) -> String:return Stories.IDS[posmod((day_value-1)*2+slot,Stories.IDS.size())]
func base(id:int) -> Dictionary:
 var fresh:Dictionary=Econ.new()._autonomous_routes()[id]
 return Ground.route(fresh) if id==0 else Extreme.route(fresh)
func offer(seed_value:int=42,day_value:int=8,slot:int=1,id:int=2) -> Dictionary:
 return Catalog.create_new_offer(base(id),root_state(seed_value),day_value,slot,"ground" if id==0 else "ascent",actor(day_value,slot))
func snapshot(e) -> Dictionary:
 var result:Dictionary={}
 for key in ["credits","reputation","day","phase","jobs_today","contracts","active_contract_id","last_trials","story_state","review_state","offer_generation_state","load_notice","story_mode","in_flight","settled_ids","history","last_settlement"]:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result
func clean() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func setup(e=Econ.new(),seed_value:int=42):
 e.enable_extreme_mode();e.story_state=Stories.initial_state(seed_value);e.enable_story_mode();e.enable_seeded_offers(seed_value)
 return e
func run() -> void:
 _old_source_bytes()
 _typed_new_catalog()
 _geometry()
 _opaque_and_saved()
 _legacy_lifecycle()
 _transactions()
 _public_recovery_copy()
 var report:Dictionary={"assertions":assertions,"failures":failures,"offers":offer_count,"fallbacks":fallback_count,"engine":Engine.get_version_info().string,"scope":"CPU content/transaction tests; no new native, human fairness, arbitrary-build or hardware claims."}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):
   var file=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
   if file!=null:file.store_string(JSON.stringify(report,"  ",true,true));file.close()
 clean();print("READABLE_ADAPTER assertions=%d failures=%d offers=%d fallbacks=%d"%[assertions,failures.size(),offer_count,fallback_count]);quit(0 if failures.is_empty() else 1)

func _old_source_bytes() -> void:
 var fresh:Array=Econ.new()._autonomous_routes()
 var selected:int=0
 for seed_value in range(32):
  for day_value in [1,2,5,8]:
   for id in [0,1,2]:
    for slot in [0,1]:
     var kind:String="ground" if id==0 else "ascent"
     for version in [Seeded.VERSION,OldPolicy.VERSION]:
      var state:Dictionary={"version":version,"world_seed":seed_value}
      var before:String=bytes(state)
      var expected:Dictionary=OldPolicy.author(base(id),fresh[id],state,day_value,slot,kind,actor(day_value,slot))
      check(bytes(expected)==bytes(Policy.author(base(id),fresh[id],state,day_value,slot,kind,actor(day_value,slot))),"old root output bytes unchanged")
      check(bytes(state)==before,"old/private roots never mutated by authoring")
     var current:Dictionary=root_state(seed_value)
     var previous:String=bytes(current)
     var value:Dictionary=Policy.author(base(id),fresh[id],current,day_value,slot,kind,actor(day_value,slot))
     check(value.ok,"new root authors ordinary catalog")
     if not value.ok:continue
     var meteor_root:Dictionary={"version":OldPolicy.VERSION,"world_seed":seed_value}
     if OldPolicy.selects_meteor(meteor_root,day_value,slot,id):
      selected+=1
      check(bytes(value)==bytes(OldPolicy.author(base(id),fresh[id],meteor_root,day_value,slot,kind,actor(day_value,slot))),"meteor distribution and complete output bytes unchanged")
     else:check(Guard.recognized(value.offer),"only remaining ordinary slots choose readable")
     check(bytes(current)==previous,"meteor projection does not mutate readable root")
 check(selected>0,"meteor distribution exercised")
 var mismatch:Dictionary=fresh[1].duplicate(true);mismatch.weight=99.0
 check(not Policy.author(base(1),mismatch,root_state(),8,0,"ascent",actor(8,0)).ok,"new source rejects mismatched fresh commercial catalog")
 var bad_catalog:Dictionary=base(1);bad_catalog.weight=true
 check(not Policy.author(bad_catalog,fresh[1],root_state(),8,0,"ascent",actor(8,0)).ok,"meteor selection cannot bypass new request validation")
 check(not Policy.known_offer(T.VERSION),"geometry version alone is deliberately still unknown")
 var unknown:Dictionary={"version":"future-root-v999","world_seed":42}
 var unchanged:String=bytes(unknown)
 check(not Policy.next_day_root(unknown).ok and bytes(unknown)==unchanged,"unknown root not downgraded or reauthored")
 for bad in [null,true,"42",-1,0.5,2147483647,NAN,INF]:
  check(not Policy.next_day_root(root_state(bad)).ok,"bad root rejected before numeric casts")

func _typed_new_catalog() -> void:
 var layouts:Dictionary={}
 for seed_value in [0,1,42,807,2147483646]:
  for day_value in [1,2,8,33]:
   for id in [0,1,2]:
    for slot in [0,1]:
     var result:Dictionary=offer(seed_value,day_value,slot,id)
     check(result.ok,"new readable catalog smoke")
     if not result.ok:continue
     offer_count+=1
     check(not result.fallback,"valid deterministic candidates need no fallback")
     var route:Dictionary=result.offer
     check(bytes(route)==bytes(offer(seed_value,day_value,slot,id).offer),"deterministic complete snapshot")
     check(Guard.validation_error(JSON.parse_string(bytes(route))).is_empty(),"typed numeric JSON roundtrip")
     check(Policy.known_route(route) and Econ.route_validation_error(route).is_empty(),"valid registered route fully known")
     layouts[bytes(route.pilot_gates)]=true
 check(layouts.size()>8,"private streams vary actual bounded geometry")
 seed(7265);var expected_global:int=randi();seed(7265);offer();check(randi()==expected_global,"does not consume global simulation random stream")
 check(not Guard.same(true,1) and not Guard.same("1",1) and Guard.same(1,1.0),"JSON numeric equivalence preserves booleans and strings exactly")
 var fixture:Dictionary=offer().offer
 for field in ["weight","reward","required","deadline","distance","delivery_radius","pilot_altitude","pilot_climb_start","pilot_climb_end","pilot_net_force_limit"]:
  for bad in [true,"1",null,NAN,INF]:
   var mutated:Dictionary=fixture.duplicate(true);mutated[field]=bad
   check(not Guard.validation_error(mutated).is_empty() and not Policy.known_route(mutated),"typed route mutation rejected "+field)
 for field in ["world_seed","day","slot","seed","layout_seed","task_seed","dialogue_seed","base_id","base_weight","base_reward","weight_delta"]:
  for bad in [true,"1",null,0.5,NAN,INF]:
   var mutated:Dictionary=fixture.duplicate(true);mutated.generation[field]=bad
   check(not Guard.validation_error(mutated).is_empty(),"typed metadata mutation rejected "+field)
 for field in ["x","y","half_gap","index","heading","lane_offset"]:
  for bad in [true,"0",null,0.25,NAN,INF]:
   var mutated:Dictionary=fixture.duplicate(true);mutated.pilot_gates[0][field]=bad
   check(not Guard.validation_error(mutated).is_empty(),"typed real gate mutation rejected "+field)
 for field in ["x","y","radius","health","mass","gate_index","pilot_gate"]:
  var mutated:Dictionary=fixture.duplicate(true);mutated.hazards[0][field]="bad"
  check(not Guard.validation_error(mutated).is_empty(),"typed collider mutation rejected "+field)
 for pair in [["position",[0,0]],["tracking",false],["velocity",[0,0]],["damage",0],["future_mechanic",true]]:
  var mutated:Dictionary=fixture.duplicate(true);mutated.hazards[0][pair[0]]=pair[1]
  check(not Guard.validation_error(mutated).is_empty(),"hidden collider override rejected")
 for pair in [["weight",999.0],["reward",999],["client","other"],["cargo","other"],["appearance_id","human_courier"],["story_id","other"],["story","other"],["rep",0],["route_profile","moon-surface-v1"],["readable_offer_schema",true]]:
  var mutated:Dictionary=fixture.duplicate(true);mutated[pair[0]]=pair[1]
  check(not Guard.validation_error(mutated).is_empty(),"commercial/appearance/mixed identity mutation rejected "+str(pair[0]))
 for field in ["version","policy","readable_commercial_adapter","authoring_policy"]:
  var mutated:Dictionary=fixture.duplicate(true);mutated.generation[field]="future-v999"
  check(not Guard.validation_error(mutated).is_empty() and not Policy.known_route(mutated),"mixed partial markers blocked")
 var mutated:Dictionary=fixture.duplicate(true);mutated.erase("readable_offer_schema")
 check(not Econ.route_validation_error(mutated).is_empty(),"partial registration cannot bypass guard")
 mutated=fixture.duplicate(true);mutated.generation.erase("readable_commercial_adapter")
 check(not Econ.route_validation_error(mutated).is_empty(),"partial metadata cannot bypass guard")
 mutated=fixture.duplicate(true);mutated.hazards[0].y+=0.5
 var fallback:Dictionary=Catalog.accept_candidate_or_fallback(mutated,base(2),root_state(),8,1,"ascent",actor(8,1))
 check(fallback.ok and fallback.fallback,"rejected new geometry gets one readable fallback")
 if fallback.ok:
  fallback_count+=1
  check(Guard.validation_error(fallback.offer).is_empty(),"fallback validates exact registered geometry")
  check(exact([fallback.offer.weight,fallback.offer.reward,fallback.offer.generation.world_seed,fallback.offer.generation.task_seed],[fixture.weight,fixture.reward,fixture.generation.world_seed,fixture.generation.task_seed]),"fallback retains requested mass/commerce/private seeds")
  check(fallback.offer.pilot_gates[0].x==105.0 and fallback.offer.pilot_gates[1].x==565.0 and fallback.offer.generation.fallback_reason=="candidate_rejected","fallback is fixed level-pair no-jitter v2")
  check(exact(Catalog.restore_offer(fallback.offer).offer,fallback.offer),"restore preserves fallback without authoring")
 var wrong:Dictionary=offer(43).offer
 var rebound:Dictionary=Catalog.accept_candidate_or_fallback(wrong,base(2),root_state(),8,1,"ascent",actor(8,1))
 check(rebound.ok and rebound.fallback and rebound.offer.generation.world_seed==42,"valid wrong-request candidate falls back to original request")
 for bad in [true,"42",null,NAN,INF,-1,0.5]:check(not Catalog.create_new_offer(base(2),root_state(bad),8,1,"ascent",actor(8,1)).ok,"invalid requests do not get fallbacks")
 check(not Catalog.create_new_offer(fixture,root_state(),8,1,"ascent",actor(8,1)).ok,"accepted materialized snapshots cannot be input catalogs")
 for special in [Moon.route(Econ.new()._autonomous_routes()[4]),Wormhole.route(Econ.new()._autonomous_routes()[3])]:
  check(not Catalog.create_new_offer(special,root_state(),8,1,"ascent",actor(8,1)).ok,"Moon/wormhole not replaced by readable catalog")

func _geometry() -> void:
 check(Guard.reference_preview_error().is_empty(),"true starter quads and reference gate screen budgets")
 for extent in [Vector2(1280,720),Vector2(1920,1080),Vector2(3840,2160)]:
  for sample in [[3.2,19.7],[7.5,18.0]]:
   var budget:Dictionary=Guard.preview_budget(extent,sample[0],sample[1])
   check(budget.fits and budget.physical_module_px>=19.7567,"1280/1080p/4K physical inward faces fit declared level reference")
 check(not Guard.preview_budget(Vector2(1280,720),7.5,33.0).fits,"fast player build honestly outside preview certificate")
 var expanded:Array=Extreme.starter_design();expanded.append(Extreme.part(99,"beam",20,10))
 var prior:String=bytes(expanded)
 check(not Guard.design_bounds(expanded).reference_envelope and bytes(expanded)==prior,"arbitrary large legal design gets a warning, no ban/mutation")
 var sim=Sim.new();sim.configure(Extreme.starter_design(),Extreme.starter_launcher(),offer().offer,807)
 var prior_route:String=bytes(sim.route)
 Guard.connected_preview(sim,Vector2(1280,720))
 check(bytes(sim.route)==prior_route,"true connected module preview is read-only and preserves physics")

func _opaque_and_saved() -> void:
 var prototypes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/readable_opaque_qa.json"))
 var opaque:Dictionary=prototypes["ascent-heavy"].duplicate(true)
 opaque.contract_id="D8-B";opaque.accepted_day=8;opaque.client="Saved QA client";opaque.cargo="Saved QA parcel";opaque.appearance_id="robot_machinist";opaque.story="Saved opaque opening"
 for state_name in ["available","accepted","in_flight","settled"]:
  var saved:Dictionary=opaque.duplicate(true);saved.status=state_name
  var previous:String=bytes(saved)
  check(not Policy.known_route(saved) and Econ.route_validation_error(saved).is_empty(),"unregistered readable snapshot stays opaque")
  var a=Econ.new();var b=OldEcon.new()
  for shop in [a,b]:
   shop.day=8;shop.contracts=[saved.duplicate(true)];shop.story_state=Stories.initial_state(42);shop.offer_generation_state={"version":Seeded.VERSION,"world_seed":42};shop.enable_story_mode();shop.enable_seeded_offers(99)
  check(bytes(a.contracts[0])==previous and bytes(a.contracts)==bytes(b.contracts),"old opaque accepted lifecycle bytes preserved "+state_name)
  check(exact(a._review_order(saved),b._review_order(saved)) and a.story_actor("D8-B").is_empty(),"old opaque story/review projection unchanged "+state_name)
  check(bytes(Catalog.restore_offer(saved).offer)==previous,"opaque restore never stamps registration")
 var unknown:Dictionary=opaque.duplicate(true);unknown.generation.version="future-v999";unknown.generation.policy="future-camera-v999";unknown.generation.commercial_adapter="unknown-adapter"
 check(not Policy.known_route(unknown) and Econ.route_validation_error(unknown).is_empty(),"arbitrary future metadata remains opaque")
 var fixtures:Array=[]
 var fresh:Array=Econ.new()._autonomous_routes()
 fixtures.append(Seeded.create_new_offer(base(0),{"version":Seeded.VERSION,"world_seed":42},8,0,"ground",actor(8,0)).offer)
 fixtures.append(Meteor.create_new_offer(fresh[1],{"version":Meteor.POLICY,"world_seed":42},8,0,actor(8,0)).offer)
 fixtures.append(Moon.route(fresh[4]));fixtures.append(Wormhole.route(fresh[3]))
 for saved in fixtures:
  if not saved.has("contract_id"):saved.contract_id="D8-A";saved.accepted_day=8;saved.variant="标准件"
  for state_name in ["available","accepted","in_flight","settled"]:
   saved.status=state_name
   var a=Econ.new();var b=OldEcon.new()
   for shop in [a,b]:shop.day=8;shop.contracts=[saved.duplicate(true)];shop.story_state=Stories.initial_state(42);shop.enable_story_mode();shop.enable_seeded_offers(42)
   check(bytes(a.contracts)==bytes(b.contracts) and bytes(a.story_state)==bytes(b.story_state),"legacy v1/meteor/Moon/wormhole story output bytes unchanged")
 var damaged:Dictionary=offer().offer;damaged.hazards[0].radius=true
 var before:String=bytes(damaged)
 check(not Catalog.restore_offer(damaged).ok and bytes(Catalog.restore_offer(damaged).offer)==before,"corrupt registered restore preserves exact bytes and blocks")

func _transactions() -> void:
 clean()
 var fresh=Econ.new();fresh.enable_extreme_mode();var before:Dictionary=snapshot(fresh)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not fresh.author_readable_batch_and_save(42,[],[],{}).ok and exact(before,snapshot(fresh)),"fresh failed save rolls back seed/policy/story/finances/both offers")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(fresh.author_readable_batch_and_save(42,[],[],{}).ok and fresh.offer_generation_state.version==Combined.CURRENT_VERSION,"genuine fresh empty batch atomically commits root and complete offers")
 check(fresh.contracts.size()==2 and Guard.recognized(fresh.contracts[0]) and Guard.recognized(fresh.contracts[1]),"fresh committed cards use real registered client/parcel/catalog")
 var committed:Dictionary=snapshot(fresh)
 check(not fresh.author_readable_batch_and_save(99,[],[],{}).ok and exact(committed,snapshot(fresh)),"existing cards cannot reroll at explicit fresh boundary")
 var restarted=Econ.new();restarted.load_state();restarted.enable_story_mode();restarted.enable_seeded_offers(99)
 check(exact(committed,snapshot(restarted)),"fresh save/restart/enable preserves new seed and snapshot")
 clean();var e=setup();var previous:Dictionary=snapshot(e);e.enable_seeded_offers(999)
 check(exact(previous,snapshot(e)) and e.offer_generation_state.version==Seeded.VERSION,"enable on current batch changes no root/route")
 e.reputation=4;e.phase="night";check(e.save_state([],[],{}),"old night save")
 var disk:String=FileAccess.get_file_as_string("user://savegame.json");previous=snapshot(e)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.next_day_and_save([],[],{}).ok and exact(previous,snapshot(e)),"next-day failed save rolls back root/date/offers/story/reviews/finances")
 check(FileAccess.get_file_as_string("user://savegame.json")==disk,"next-day failed save retains disk bytes")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.next_day_and_save([],[],{}).ok and e.offer_generation_state.version==Combined.CURRENT_VERSION,"real next-day adopts readable root once")
 committed=snapshot(e);restarted=Econ.new();restarted.load_state();restarted.enable_story_mode();restarted.enable_seeded_offers(999)
 check(exact(committed,snapshot(restarted)),"saved/restarted next-day no regeneration")
 var order:Dictionary=e.contracts[1];var id:String=order.contract_id;var saved_geometry:String=bytes([order.pilot_gates,order.hazards,order.generation])
 check(e.accept_contract(id).ok,"new heavy readable accept")
 var conversation:Dictionary=e.story_conversation(id,"accept")
 check(not conversation.is_empty() and conversation.lines[0].text==order.generation.dialogue.accept_lines[0].text,"actual saved readable opening and recurring story identity")
 check(e.story_actor(id).appearance_id==order.generation.dialogue.appearance_id,"actual actor matches commercial dialogue")
 var trial:Dictionary=e.trial_route();e.mark_cargo_loaded(id)
 var dispatch:Dictionary=e.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher())
 check(dispatch.ok and exact(trial.generation,dispatch.snapshot.route.generation) and exact(trial.pilot_gates,dispatch.snapshot.route.pilot_gates) and exact(trial.hazards,dispatch.snapshot.route.hazards),"trial/formal exact saved route geometry/provenance")
 check(trial.seed==e.day*100+int(order.id)*3+1 and dispatch.snapshot.seed==trial.seed,"normal trial/formal seed derives from actual accepted day/id/slot")
 check(Guard.validation_error(dispatch.snapshot.route).is_empty(),"dispatch research multiplier validates without rewriting accepted geometry")
 check(bytes([e.contracts[1].pilot_gates,e.contracts[1].hazards,e.contracts[1].generation])==saved_geometry,"accept/loading/formal preserves authored snapshot")
 check(e.save_state([],[],{}),"new in-flight atomic save")
 var again=Econ.new();again.load_state();check(exact(e.in_flight,again.in_flight),"in-flight restart exact snapshot")
 var cash:int=e.credits
 check(not e.begin_dispatch([],[]).ok and e.credits==cash,"duplicate launch cannot change finances")
 check(e.settle_contract_and_save(id,{"integrity":1.0,"energy_used":120.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},44.0,true,[],[],{}).ok,"formal readable settlement uses real ledger")
 check(Guard.recognized(e.contracts[1]) and e.story_state.committed_contract_ids.has(id),"settled lifecycle success flag keeps registered story binding")
 check(e.review_state.pending[id].client==order.client and e.review_state.pending[id].appearance_id==order.appearance_id,"review snapshot binds exact real commercial customer")
 cash=e.credits
 check(not e.settle_contract(id,{},0,true).ok and e.credits==cash,"duplicate settlement pays once")
 check(e.close_day().ok and e.next_day_and_save([],[],{}).ok and e.customer_reviews().size()==1,"next-day publishes bound review once")
 clean();var failed=setup(FailedSecond.new());failed.phase="night";previous=snapshot(failed)
 check(not failed.next_day().ok and exact(previous,snapshot(failed)),"second-offer author failure rolls back direct new-day root")
 check(not failed.next_day_and_save([],[],{}).ok and exact(previous,snapshot(failed)),"second-offer author failure rolls back saved new-day")
 var poisoned=setup(PoisonedBatch.new());poisoned.phase="night";previous=snapshot(poisoned)
 check(not poisoned.next_day_and_save([],[],{}).ok and exact(previous,snapshot(poisoned)),"new batch validation failure aborts publication and restores state")
 clean()

func _legacy_lifecycle() -> void:
 var fresh:Array=Econ.new()._autonomous_routes()
 var fixtures:Array=[Seeded.create_new_offer(base(0),{"version":Seeded.VERSION,"world_seed":42},8,0,"ground",actor(8,0)).offer,
  Meteor.create_new_offer(fresh[1],{"version":Meteor.POLICY,"world_seed":42},8,0,actor(8,0)).offer,
  Moon.route(fresh[4]),Wormhole.route(fresh[3])]
 var opaque:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/readable_opaque_qa.json"))["ascent-heavy"]
 opaque.contract_id="D8-B";opaque.story="Saved opaque opening";fixtures.append(opaque)
 for value in fixtures:
  clean()
  var saved:Dictionary=value.duplicate(true)
  if not saved.has("contract_id"):saved.contract_id="D8-A";saved.accepted_day=8;saved.variant="标准件"
  saved.status="available"
  var a=Econ.new();var b=OldEcon.new()
  for shop in [a,b]:
   shop.day=8;shop.reputation=20;shop.contracts=[saved.duplicate(true)];shop.story_state=Stories.initial_state(42);shop.offer_generation_state={"version":Seeded.VERSION,"world_seed":42};shop.enable_story_mode()
  var id:String=saved.contract_id
  check(a.accept_contract(id).ok and b.accept_contract(id).ok,"old snapshot acceptance remains usable")
  check(bytes(a.contracts)==bytes(b.contracts) and bytes(a.trial_route())==bytes(b.trial_route()),"legacy accepted/trial bytes unchanged")
  a.mark_cargo_loaded(id);b.mark_cargo_loaded(id)
  var da:Dictionary=a.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher())
  var db:Dictionary=b.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher())
  check(da.ok and db.ok and bytes(da)==bytes(db),"legacy formal dispatch/protocol/seed bytes unchanged")
  check(a.save_state([],[],{}),"old committed dispatch save remains valid")
  var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode();loaded.enable_seeded_offers(999)
  var old_loaded=OldEcon.new();old_loaded.load_state();old_loaded.enable_story_mode();old_loaded.enable_seeded_offers(999)
  print("RESTART_DIAGNOSTIC ",saved.get("name")," numeric_exact=",exact(loaded.in_flight,a.in_flight)," old_loaded_bytes_equal=",bytes(loaded.in_flight)==bytes(old_loaded.in_flight)," contract_numeric_exact=",exact(loaded.contracts,a.contracts)," old_contract_bytes_equal=",bytes(loaded.contracts)==bytes(old_loaded.contracts))
  check(exact(loaded.in_flight,a.in_flight) and exact(loaded.contracts,a.contracts) and bytes(loaded.in_flight)==bytes(old_loaded.in_flight) and bytes(loaded.contracts)==bytes(old_loaded.contracts),"old in-flight restart preserves typed values and exact old-loader bytes")
  var telemetry:Dictionary={"integrity":1.0,"energy_used":120.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0}
  var ra:Dictionary=a.settle_contract(id,telemetry,44.0,true)
  var rb:Dictionary=b.settle_contract(id,telemetry,44.0,true)
  check(bytes(ra)==bytes(rb) and bytes(a.history)==bytes(b.history) and bytes(a.review_state)==bytes(b.review_state),"legacy settled receipt/story/review output bytes unchanged")
  check(a.save_state([],[],{}),"old settled save valid")
  loaded=Econ.new();loaded.load_state();loaded.enable_story_mode()
  old_loaded=OldEcon.new();old_loaded.load_state();old_loaded.enable_story_mode()
  print("SETTLED_DIAGNOSTIC ",saved.get("name")," numeric_exact=",exact(loaded.contracts,a.contracts)," old_loaded_bytes_equal=",bytes(loaded.contracts)==bytes(old_loaded.contracts)," history_numeric_exact=",exact(loaded.history,a.history)," old_history_bytes_equal=",bytes(loaded.history)==bytes(old_loaded.history))
  check(exact(loaded.contracts,a.contracts) and exact(loaded.history,a.history) and bytes(loaded.contracts)==bytes(old_loaded.contracts) and bytes(loaded.history)==bytes(old_loaded.history),"old settled restart preserves typed values and exact old-loader bytes")
 clean()

func _public_recovery_copy() -> void:
 var damaged:Dictionary=offer().offer;damaged.hazards[0].radius=true
 check(Econ.route_validation_error(damaged)=="这份航线记录不完整，暂时无法出发。","invalid readable route entry point exposes only concise Chinese recovery copy")
 var invalid=Econ.new();invalid.enable_extreme_mode()
 var result:Dictionary=invalid.author_readable_batch_and_save(true,[],[],{})
 check(not result.ok and result.get("message")=="航线记录不完整，原进度已保留。","fresh invalid seed never leaks internal helper diagnostics")
 var failed=setup(FailedSecond.new());failed.phase="night"
 result=failed.next_day()
 check(not result.ok and result.get("message")=="今日航线暂时无法整理，原进度已保留。请使用对应版本继续。","second-offer internal error maps to established Chinese recovery copy")
 clean();var saved=Econ.new();saved.enable_extreme_mode()
 check(saved.author_readable_batch_and_save(42,[],[],{}).ok,"recovery fixture has committed readable offers")
 var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 raw.contracts[0].hazards[0].radius=true
 var corrupt_bytes:String=bytes(raw)
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(corrupt_bytes);file.close()
 var loaded=Econ.new();loaded.load_state();loaded.enable_story_mode()
 check(exact(loaded.contracts,raw.contracts) and FileAccess.get_file_as_string("user://savegame.json")==corrupt_bytes,"damaged known saved snapshot preserved exactly without restore fallback or regeneration")
 result=loaded.accept_contract(str(raw.contracts[0].contract_id))
 check(not result.ok and result.get("message")=="这份航线记录不完整，暂时无法出发。","damaged saved-route acceptance blocked with player-facing Chinese copy")
 clean()
