extends SceneTree
const Econ=preload("res://scripts/economy.gd")
const Reviews=preload("res://scripts/customer_reviews_v2.gd")
const Legacy=preload("res://scripts/customer_reviews.gd")
const Bird=preload("res://scripts/protected_bird_settlement_v1.gd")
const Offer=preload("res://scripts/protected_bird_offer_v1.gd")
const Policy=preload("res://scripts/protected_bird_authoring_policy.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const Sim=preload("res://scripts/pilot_protected_bird_simulation.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const Timeline=preload("res://scripts/pilot_timeline.gd")
const Replay=preload("res://scripts/protected_bird_replay_v1.gd")
var passed:int=0
var failed:int=0
var harm_fixture:Dictionary={}
var safe_fixture:Dictionary={}
var abort_fixture:Dictionary={}

class FailingEconomy:
 extends "res://scripts/economy.gd"
 var fail_save:bool=false
 var observed:Dictionary={}
 func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
  if fail_save:
   observed={"day":day,"review_state":review_state.duplicate(true),"settled_ids":settled_ids.duplicate(true)}
   save_error="injected final commit failure";return false
  return super.save_state(design,launcher,settings)

func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:check(Profile.same_value(a,b),label)
func bytes(value:Variant) -> String:return JSON.stringify(value,"",true,true)
func clear_files() -> void:
 for name in ["savegame.json","savegame.tmp","savegame.backup.json"]:DirAccess.remove_absolute("user://"+name)
func write_save(path:String,value:Dictionary) -> void:
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(bytes(value));f.close()
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 test_offer_policy()
 safe_fixture=live_fixture(false);harm_fixture=live_fixture(true);abort_fixture=live_fixture(true,true)
 if safe_fixture.is_empty() or harm_fixture.is_empty() or abort_fixture.is_empty():print("BIRD_REVIEWS fixture failure");quit(1);return
 test_lifecycle();test_safe_and_failure();test_rollback();test_introduction_rollback();test_migration();test_tampering();test_future_recovery();test_trial_and_duplicates()
 clear_files()
 print("PROTECTED_BIRD_REVIEWS passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)

func new_shop(e:Variant=null) -> Variant:
 if e==null:e=Econ.new()
 e.day=5;e.reputation=7;e.flight_mode=Extreme.CONTROL_VERSION
 e.offer_generation_state={"version":Policy.VERSION,"world_seed":420,"introduced_day":0}
 e.ensure_contracts()
 return e

func guidance(sim:Variant,harm:bool) -> int:
 var pos:Vector2=sim.cargo_position();var offset:float=0.0
 for gate in sim.route.pilot_gates:
  if pos.x<float(gate.x)+6.5:offset=float(gate.lane_offset);break
 if pos.x>980.0 and pos.x<1120.0:offset=0.0 if harm else 7.0
 var normal:Vector2=Ascent.path_tangent(pos.x,sim.route).orthogonal()*-1.0
 var body:Dictionary=sim._cargo_body();var velocity:Vector2=body.get("velocity",Vector2.ZERO)
 var lateral:float=velocity.dot(normal)
 var acceleration:float=float(sim.route.pilot_net_force_limit)/maxf(1.0,float(body.get("mass",10.2)))
 var preview:float=lateral*(0.45+absf(lateral)/(2.0*acceleration*0.9))
 var error:float=Ascent.path_y(pos.x,sim.route)+offset-pos.y-preview
 return int(signf(error))*1000 if absf(error)>0.9 else 0

func live_fixture(harm:bool,abort_after_harm:bool=false) -> Dictionary:
 var e=new_shop();var id:String="D5-A"
 check(Offer.has_markers(e.contract_by_id(id)),"day-5 actual introduction exists")
 var design:Array=Extreme.starter_design();var launcher:Array=Extreme.starter_launcher()
 check(e.accept_contract(id).ok and e.begin_dispatch(design,launcher).ok,"actual bird offer accepted/dispatched")
 var snapshot:Dictionary=e.in_flight
 var sim=Sim.new();sim.configure(design,launcher,Offer.canonical_route(snapshot.route),int(snapshot.seed))
 var timeline=Timeline.new();var axis:int=0
 for tick in range(6000):
  if tick%12==0:axis=guidance(sim,harm)
  timeline.record(tick,{"axis_q":axis,"boost":false,"active":false})
  sim.set_pilot_input(axis,false,false);sim.step(1.0/60.0)
  snapshot.ticks=tick+1
  if abort_after_harm and not sim.first_harm.is_empty() and sim.status=="running":sim.status="failed"
  if sim.status!="running":break
 snapshot.input_commands=timeline.commands.duplicate(true)
 sim.finalize_settlement()
 var evidence:Dictionary=Bird.from_simulator(sim,snapshot)
 check(sim.status==("failed" if abort_after_harm else "success"),"actual commercial route terminal outcome: "+str(harm)+"/abort="+str(abort_after_harm))
 check(not evidence.is_empty(),"live terminal sim exports bounded completion: "+str(harm))
 if evidence.is_empty():return {}
 check(evidence.result.harms.size()==(1 if harm else 0),"same route has factual harm/safe witness: "+str(harm))
 var replay:Dictionary=Replay.restore(Replay.snapshot(evidence.route,design,launcher,int(snapshot.seed),int(snapshot.ticks),snapshot.input_commands))
 check(replay.ok,"independent exact replay validates witness: "+str(harm))
 if replay.ok:same(replay.simulator.wildlife_result(),evidence.result,"replay reconstructs same cause without duplicate")
 return {"order":e.contract_by_id(id).duplicate(true),"snapshot":snapshot.duplicate(true),"telemetry":sim.telemetry.duplicate(true),"evidence":evidence,"design":design,"launcher":launcher,"elapsed":sim.elapsed,"success":sim.status=="success"}

func fixture_shop(f:Dictionary,e:Variant=null) -> Variant:
 e=new_shop(e);e.contracts[0]=f.order.duplicate(true);e.in_flight=f.snapshot.duplicate(true);e.active_contract_id=f.order.contract_id;e.phase="day"
 return e
func settle(e:Variant,f:Dictionary) -> Dictionary:return e.settle_contract_and_save(f.order.contract_id,f.telemetry,f.elapsed,f.success,f.design,f.launcher,{},f.evidence)
func state(e:Variant) -> Dictionary:
 var result:Dictionary={}
 for key in ["credits","reputation","workshop_tier","jobs_today","deliveries","day","phase","contracts","settled_ids","history","last_settlement","story_state","review_state","in_flight","active_contract_id","offer_generation_state"]:
  var value:Variant=e.get(key);result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 return result

func test_offer_policy() -> void:
 for day in [1,2,3,4]:
  var e=Econ.new();e.day=day;e.reputation=10;e.flight_mode=Extreme.CONTROL_VERSION;e.offer_generation_state={"version":Policy.VERSION,"world_seed":420,"introduced_day":0};e.ensure_contracts()
  check(not Offer.has_markers(e.contracts[0]) and not Offer.has_markers(e.contracts[1]),"first four days untouched "+str(day))
 var e=new_shop();var exact:String=bytes(e.contracts);e.ensure_contracts();same(bytes(e.contracts),exact,"repeated offer read never reauthors")
 check(e.offer_generation_state.introduced_day==5,"one-time introduction durably claimed")
 var route:Dictionary=e.contracts[0];check(Offer.validation_error(route).is_empty(),"commercial metadata accepted explicitly")
 same(Offer.create_new_offer(e.offer_generation_state,5,"human_courier").offer,route,"same seed/day/actor produces identical offer")
 check(Offer.derived_seed(420,5)!=Offer.derived_seed(421,5) and Offer.derived_seed(420,5)!=Offer.derived_seed(420,6),"independent world/day seed domain")
 e.day=6;e.contracts=[];e.ensure_contracts();check(not Offer.has_markers(e.contracts[0]),"no repeated bird offer after first introduction")
 var moon=Econ.new();moon.day=5;moon.reputation=10;moon.flight_mode=Extreme.CONTROL_VERSION;moon.offer_generation_state={"version":Policy.VERSION,"world_seed":420,"introduced_day":0};moon.ensure_contracts()
 check(moon.contracts[0].id==4 and moon.contracts[1].id==4 and moon.offer_generation_state.introduced_day==0,"Moon slot A/B survives day-5 selection")
 moon.day=6;moon.contracts=[];moon.ensure_contracts();check(Offer.has_markers(moon.contracts[0]) and moon.contracts[1].id==4,"later first eligible boundary preserves Moon slot B")
 for key in ["client","cargo","appearance_id","contract_id","seed","ecology_schema","deadline","time_limit","pilot_net_force_limit","name","destination_name","risk"]:
  var bad:Dictionary=route.duplicate(true);bad[key]="tampered";check(not Offer.validation_error(bad).is_empty(),"offer rejects changed "+key)
 var old:Dictionary={"version":Policy.Legacy.VERSION,"world_seed":420}
 same(Policy.next_day_root(old,4).state,old,"no policy migration before future boundary")
 check(Policy.next_day_root(old,5).state.version==Policy.VERSION,"explicit next-day migration at day 5")

func test_lifecycle() -> void:
 clear_files();var f:Dictionary=harm_fixture;var e=fixture_shop(f)
 var quote:Dictionary=e.estimate_delivery(f.order,f.telemetry,f.elapsed,f.success);var credits:int=e.credits;var rep:int=e.reputation
 check(settle(e,f).ok,"formal bird harm commits once")
 check(e.credits==credits+int(quote.profit) and e.reputation==rep+2,"bird adds no credit or reputation debit")
 check(not e.last_settlement.has("review") and not e.last_settlement.has("rating"),"formal bird receipt contains facts, no instant customer review")
 check(e.review_state.version==2 and e.review_state.pending.size()==1 and e.customer_reviews().is_empty(),"v2 pending evidence has no current-day disclosure")
 var pending:Dictionary=e.review_state.pending[f.order.contract_id]
 check(not pending.has("body") and not pending.has("rating") and not e.review_state.dispatch[f.order.contract_id].has("body"),"pending records/tags contain no review body or rating")
 var saved:Dictionary=disk();var restarted=Econ.new();restarted.load_state()
 check(not restarted.review_load_blocked and restarted.customer_reviews().is_empty(),"restart preserves pending without publication")
 var bound_identity:Dictionary=restarted.review_state.dispatch[f.order.contract_id].evidence.dispatch_identity.duplicate(true)
 restarted.contracts[0].client="unrelated later customer";restarted.contracts[0].appearance_id="robot_machinist"
 check(restarted.customer_reviews().is_empty(),"mutating live customer list cannot reveal a current-day review")
 same(restarted.review_state.dispatch[f.order.contract_id].evidence.dispatch_identity,bound_identity,"pending review retains actual completion identity after contract mutation")
 restarted.contracts=[]
 check(restarted.customer_reviews().is_empty(),"clearing live contracts cannot reveal a current-day review")
 check(restarted.close_day().ok and restarted.next_day_and_save(f.design,f.launcher,{}).ok,"successful next day publishes")
 var feed:Array=restarted.customer_reviews();check(feed.size()==1 and feed[0].rating==2 and feed[0].published_day==6,"exactly one two-star review on next day")
 check(feed[0].body.contains("伤到了保护鸟") and not feed[0].body.contains("准时又完好") and feed[0].client==f.order.client and feed[0].appearance_id==f.order.appearance_id,"factual harm copy keeps real customer identity")
 same(Reviews.publish_next_day(restarted.review_state,5,6).state,restarted.review_state,"repeated publication callback is idempotent")
 check(not restarted.next_day_and_save(f.design,f.launcher,{}).ok,"second next-day request cannot skip day")
 var again=Econ.new();again.load_state();same(again.customer_reviews(),feed,"published bytes survive restart")
 for later in range(3):
  again.close_day();var outcome:Dictionary=again.next_day_and_save(f.design,f.launcher,{})
  check(outcome.ok and outcome.published_reviews==0,"later next-day requests publish no duplicate: "+str(later))
  same(again.customer_reviews(),feed,"later days preserve original publication bytes: "+str(later))
 check(saved.review_state.published.is_empty() and saved.settings.customer_reviews_schema==2 and saved.settings.protected_bird_schema==1,"durable schema markers saved with pending")

func test_safe_and_failure() -> void:
 for outcome in [[true,50.0,100.0],[true,80.0,100.0],[true,50.0,95.0],[true,50.0,70.0],[false,50.0,100.0]]:
  var facts:Dictionary={"settlement_id":"D5-A","delivery_day":5,"client":harm_fixture.order.client,"appearance_id":harm_fixture.order.appearance_id,"route_name":harm_fixture.order.name,"destination_name":harm_fixture.order.destination_name,"success":outcome[0],"elapsed":outcome[1],"deadline":72.0,"integrity":outcome[2],"required":90.0}
  var base:Dictionary=Legacy._publish(facts);var record:Dictionary=Reviews._publish(facts,Reviews._dispatch(harm_fixture.evidence))
  check(record.rating==mini(int(base.rating),2) and record.category==base.category,"pure factual template caps ordinary rating once for "+str(base.category))
 clear_files();var e=fixture_shop(safe_fixture);check(settle(e,safe_fixture).ok,"safe known empty evidence commits")
 e.close_day();check(e.next_day_and_save(safe_fixture.design,safe_fixture.launcher,{}).ok,"safe next-day saved")
 var review:Dictionary=e.customer_reviews()[0];check(review.rating==5 and not review.body.contains("鸟"),"safe route uses exact ordinary review template")
 # Real abort after the already-recorded harm retains that fact; no new harm is injected.
 var f:Dictionary=abort_fixture
 e=fixture_shop(f);clear_files();check(settle(e,f).ok,"formal failure retains actual pre-failure cause")
 e.close_day();e.next_day_and_save(f.design,f.launcher,{})
 review=e.customer_reviews()[0];check(review.rating==1 and review.body.begins_with("这次没送到") and review.body.contains("伤到了保护鸟"),"failed base remains one star with truthful no-arrival copy")

func test_rollback() -> void:
 for mode in ["temporary_write","final_commit"]:
  clear_files();var f:Dictionary=harm_fixture;var e=fixture_shop(f,FailingEconomy.new());e.workshop_tier=2
  check(e.save_state(f.design,f.launcher,{}),"dispatch baseline saved: "+mode)
  var before:Dictionary=state(e);var prior_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
  if mode=="temporary_write":DirAccess.make_dir_absolute("user://savegame.tmp")
  else:e.fail_save=true
  check(not settle(e,f).ok,"settlement save failure rejected: "+mode)
  same(state(e),before,"settlement rollback restores all mutable state: "+mode)
  check(FileAccess.get_file_as_string("user://savegame.json")==prior_bytes and e.customer_reviews().is_empty(),"failed settlement preserves disk and hides review: "+mode)
  if mode=="temporary_write":DirAccess.remove_absolute("user://savegame.tmp")
  else:e.fail_save=false
  check(settle(e,f).ok,"settlement retry succeeds once: "+mode)
  e.close_day();check(e.save_state(f.design,f.launcher,{}),"night baseline saved")
  before=state(e);prior_bytes=FileAccess.get_file_as_string("user://savegame.json")
  e.fail_save=true
  check(not e.next_day_and_save(f.design,f.launcher,{}).ok,"next-day final save failure rejected")
  check(e.observed.review_state.published.size()==1,"failure occurred after candidate publication")
  same(state(e),before,"next-day rollback restores pending, publication, offers and root")
  check(e.customer_reviews().is_empty() and FileAccess.get_file_as_string("user://savegame.json")==prior_bytes,"failed morning never reveals next-day review")
  e.fail_save=false;check(e.next_day_and_save(f.design,f.launcher,{}).ok and e.customer_reviews().size()==1,"morning retry publishes once")

func test_introduction_rollback() -> void:
 clear_files();var e=FailingEconomy.new();e.day=4;e.reputation=7;e.workshop_tier=2;e.flight_mode=Extreme.CONTROL_VERSION
 e.offer_generation_state={"version":Policy.Legacy.VERSION,"world_seed":420};e.ensure_contracts()
 check(e.accept_contract("D4-A").ok and e.begin_dispatch([],[]).ok,"pre-introduction ordinary contract dispatched")
 check(e.settle_contract_and_save("D4-A",{"integrity":1.0},10.0,true,[],[],{}).ok,"pre-introduction v1 pending review saved")
 e.close_day();e.save_state([],[],{});var previous:Dictionary=state(e)
 e.fail_save=true;check(not e.next_day_and_save([],[],{}).ok,"failed day-5 authoring/publication commit rejected")
 same(state(e),previous,"failed introduction restores old policy claim, v1 pending, day and paid tier")
 check(e.offer_generation_state.version==Policy.Legacy.VERSION and not e.offer_generation_state.has("introduced_day") and e.workshop_tier==2,"failed introduction consumes no feature claim or paid workshop tier")
 e.fail_save=false;check(e.next_day_and_save([],[],{}).ok,"retry commits first introduction")
 check(e.offer_generation_state.introduced_day==5 and Offer.has_markers(e.contracts[0]) and e.workshop_tier==2,"successful introduction claims once and preserves paid tier")
 var reloaded=Econ.new();reloaded.load_state();check(reloaded.workshop_tier==2 and reloaded.offer_generation_state.introduced_day==5,"restart preserves tier and unique feature claim")

func test_migration() -> void:
 var f:Dictionary={"settlement_id":"D3-A","delivery_day":3,"client":"小禾","appearance_id":"human_courier","route_name":"旧航线","destination_name":"旧驿站","success":true,"elapsed":1,"deadline":10,"integrity":100,"required":85}
 var old:Dictionary=Legacy.initial_state(3);old.pending[f.settlement_id]=f
 old=Legacy.publish_next_day(old,3,4).state;old=Legacy.publish_next_day(old,4,5).state
 var original:String=bytes(old.published[0]);var migrated:Dictionary=Reviews.migrate_v1(old,5)
 check(migrated.ok and bytes(migrated.state.published[0])==original,"migration preserves exact legacy published record bytes")
 var more:Dictionary=f.duplicate(true);more.settlement_id="D5-B";more.delivery_day=5;old.pending[more.settlement_id]=more
 migrated=Reviews.migrate_v1(old,5);check(migrated.ok and bytes(migrated.state.pending[more.settlement_id])==bytes(more),"migration preserves legacy pending values")
 var published:Dictionary=Reviews.publish_next_day(migrated.state,5,6)
 check(published.ok and bytes(published.state.published[1])==original,"next day never reauthors old v1 published bodies")
 same(published.state.published[0],Legacy._publish(more),"migrated pending publishes through frozen v1 template")
 check(Legacy.normalize_state(Reviews.normalize_state(null,5).state,5).ok,"ordinary new shop retains v1 envelope")

func test_tampering() -> void:
 clear_files();var e=fixture_shop(harm_fixture);check(settle(e,harm_fixture).ok,"tamper baseline settled")
 var good:Dictionary=disk();var id:String="D5-A"
 for key in ["schema","seed","command_ticks","status","elapsed","route","launch_design","registry","result","dispatch_identity"]:
  for invalid in [null,{},[],true,"future",INF]:
   var bad:Dictionary=good.duplicate(true);bad.settled_ids[id].wildlife_evidence[key]=invalid
   check(not e._valid_save(bad),"malformed completion rejected: "+key+"/"+str(invalid))
 for key in ["event_id","entity_id","hp_delta","physics_tick","source"]:
  var bad:Dictionary=good.duplicate(true);bad.review_state.dispatch[id].evidence.result.harms[0][key]="changed"
  check(not e._valid_save(bad),"pending cause tamper rejected: "+key)
 var missing:Dictionary=good.duplicate(true);missing.settled_ids[id].erase("wildlife_evidence");check(not e._valid_save(missing),"mandatory v5 wildlife evidence cannot disappear")
 var altered:Dictionary=good.duplicate(true);altered.review_state.pending[id].body="premature";check(not e._valid_save(altered),"v2 pending cannot contain future body")
 altered=good.duplicate(true);altered.review_state.dispatch[id].template_id=Reviews.DELIVERY_TEMPLATE;check(not e._valid_save(altered),"harm template cannot be downgraded")
 altered=good.duplicate(true);altered.review_state.dispatch.erase(id);check(not e._valid_save(altered),"dispatch identity cannot disappear")
 e.close_day();e.next_day_and_save(harm_fixture.design,harm_fixture.launcher,{});good=disk()
 for key in ["rating","body","published_day","settlement_id"]:
  altered=good.duplicate(true);altered.review_state.published[0][key]="changed";check(not e._valid_save(altered),"published tamper rejected: "+key)

func test_future_recovery() -> void:
 clear_files();var e=fixture_shop(harm_fixture);settle(e,harm_fixture);var good:Dictionary=disk()
 for future in ["envelope","template","fact","evidence","route"]:
  var bad:Dictionary=good.duplicate(true)
  match future:
   "envelope":bad.review_state.version=3
   "template":bad.review_state.dispatch["D5-A"].template_id="protected-bird-review-v9"
   "fact":bad.settled_ids["D5-A"].wildlife_evidence.result.schema="protected-bird-harm-v9"
   "evidence":bad.settled_ids["D5-A"].wildlife_evidence.schema="protected-bird-settlement-v9"
   "route":bad.contracts[0].ecology_schema="protected-bird-route-v9"
  clear_files();write_save("user://savegame.json",bad);write_save("user://savegame.backup.json",good)
  var original:String=FileAccess.get_file_as_string("user://savegame.json");var restored=Econ.new();var loaded:Dictionary=restored.load_state()
  check(restored.review_load_blocked and Profile.same_value(loaded,bad),"future "+future+" outranks playable backup")
  check(not restored.save_state([],[],{}) and restored.customer_reviews().is_empty() and FileAccess.get_file_as_string("user://savegame.json")==original,"future "+future+" stays opaque and nonwritable")

func test_trial_and_duplicates() -> void:
 clear_files();var e=new_shop();var before:Dictionary=state(e)
 var preview:Dictionary=e.estimate_delivery(harm_fixture.order,harm_fixture.telemetry,harm_fixture.elapsed,true)
 check(not preview.is_empty(),"trial quote can inspect real telemetry")
 same(state(e),before,"free trial/quote never changes ledger or reviews")
 check(not e.settle_contract("D5-A",harm_fixture.telemetry,harm_fixture.elapsed,true,harm_fixture.evidence).ok,"unlaunched offer cannot settle harm")
 e=fixture_shop(harm_fixture);var fake:Dictionary=harm_fixture.telemetry.duplicate(true);fake.wildlife_result.harms[0].source.owner_kind="enemy"
 check(not e.settle_contract("D5-A",fake,harm_fixture.elapsed,true,harm_fixture.evidence).ok,"background/enemy ownership cannot fabricate customer blame")
 check(not e.settle_contract("D5-A",harm_fixture.telemetry,harm_fixture.elapsed,true).ok,"telemetry alone cannot substitute for live completion package")
 check(settle(e,harm_fixture).ok,"real completion accepted after negative controls")
 before=state(e);check(not settle(e,harm_fixture).ok,"repeated formal settlement rejected by unique ID");same(state(e),before,"duplicate settlement leaves money, facts and IDs unchanged")
