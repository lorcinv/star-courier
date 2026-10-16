extends SceneTree
const Reviews=preload("res://scripts/customer_reviews.gd")
const Econ=preload("res://scripts/economy.gd")
const LegacyEcon=preload("res://tests/fixtures/economy_pre_reviews_v5.gd")
var passed:int=0
var failed:int=0

func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 test_timing();test_outcomes();test_malformed();test_untrusted_receipts();test_bounds();test_economy();test_failed_save();test_migration();test_settlement_save_failure();test_unreadable_saves();test_downgrade_detection();test_capture_failure_transaction()
 clear_files()
 print("CUSTOMER_REVIEWS passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)

func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func same(a:Variant,b:Variant,label:String) -> void:
 check(JSON.stringify(JSON.parse_string(JSON.stringify(a,"",true,true)),"",true,true)==JSON.stringify(JSON.parse_string(JSON.stringify(b,"",true,true)),"",true,true),label)

func fixture(day:int=1,slot:String="A",actor:String="human_courier",success:bool=true,elapsed:float=8,integrity:float=100) -> Dictionary:
 var id:String="D%d-%s"%[day,slot]
 var client:String=Reviews.ACTORS.get(actor,"林奶奶")
 var order:Dictionary={"contract_id":id,"status":"settled","client":client,"appearance_id":actor,"name":"城市 → 月面","destination_name":"月面收件舱"}
 var receipt:Dictionary={"contract_id":id,"day":day,"client":client,"route":order.name,"success":success,"elapsed":elapsed,"deadline":10.0,"integrity":integrity,"required":85.0,"route_context":{"destination_name":"月面收件舱"}}
 return {"order":order,"ledger":{id:receipt},"id":id}

func capture(state:Variant,f:Dictionary,day:int=1) -> Dictionary:
 return Reviews.capture_settlement(state,f.order,f.ledger,day)

func test_timing() -> void:
 var f:Dictionary=fixture();var original:Dictionary=Reviews.initial_state(1)
 var state:Dictionary=capture(original,f).state
 check(state.pending.size()==1 and state.published.is_empty(),"formal settlement creates pending facts only")
 check(not state.pending[f.id].has("body") and not state.pending[f.id].has("rating"),"pending has no future review body or rating")
 same(original,Reviews.initial_state(1),"capture never mutates caller state")
 check(Reviews.visible_reviews(state,1).is_empty(),"same-day phone cannot show pending result")
 var frozen:Dictionary=state.duplicate(true)
 for i in 20:Reviews.visible_reviews(state,1)
 same(state,frozen,"render/feed reads do not publish or consume reviews")
 var roundtrip:Variant=JSON.parse_string(JSON.stringify(state,"",true,true))
 same(capture(roundtrip,f).state,state,"duplicate settlement after restart is idempotent")
 check(not Reviews.publish_next_day(state,1,1).ok and not Reviews.publish_next_day(state,1,3).ok,"same-day and skipped-day publication are rejected")
 seed(7319);var expected:int=randi();seed(7319)
 var published:Dictionary=Reviews.publish_next_day(roundtrip,1,2)
 check(randi()==expected,"review publication consumes no global simulation RNG")
 check(published.ok and published.published_count==1 and published.state.pending.is_empty(),"one successful next-day publishes yesterday once")
 var review:Dictionary=published.state.published[0]
 check(review.delivery_day==1 and review.published_day==2 and review.settlement_id==f.id,"delivery and publication dates persist with unique settlement ID")
 check(review.body.contains("月面收件舱") and not review.body.contains("晨星"),"review keeps actual destination rather than today's route")
 same(Reviews.publish_next_day(published.state,1,2).state,published.state,"repeat next-day callback cannot duplicate publication")
 same(Reviews.normalize_state(JSON.parse_string(JSON.stringify(published.state)),2).state,published.state,"published content survives JSON restart unchanged")
 check(Reviews.visible_reviews(published.state,1).is_empty(),"a future-day state fails closed on an earlier-day read")
 var feed:Array=Reviews.visible_reviews(published.state,2);feed[0].body="changed"
 check(published.state.published[0].body!="changed","phone receives detached read-only projection")
 check(not capture(published.state,f,2).ok,"replaying yesterday's receipt cannot enqueue it again")

func test_outcomes() -> void:
 for actor in Reviews.ACTORS:
  for result in [[true,8.0,100.0,"complete",5],[true,10.0,100.0,"complete",5],[true,8.0,90.0,"worn",4],[true,11.0,90.0,"late",3],[true,11.0,100.0,"late",3],[true,8.0,70.0,"damaged",2],[true,11.0,70.0,"late_damaged",2],[false,8.0,100.0,"failed",1]]:
   var f:Dictionary=fixture(1,"A",actor,result[0],result[1],result[2])
   var record:Dictionary=Reviews.publish_next_day(capture(null,f).state,1,2).state.published[0]
   check(record.category==result[3] and record.rating==result[4] and record.client==Reviews.ACTORS[actor],"coherent actual outcome for %s/%s"%[actor,result[3]])
   check(not record.body.contains("鸟") and not record.body.contains("奖励"),"no invented wildlife harm or reward for %s/%s"%[actor,result[3]])
 var f:Dictionary=fixture();f.order.bird_hits=90;f.ledger[f.id].bird_hits=90;f.ledger[f.id].collisions=90
 var record:Dictionary=Reviews.publish_next_day(capture(null,f).state,1,2).state.published[0]
 check(record.rating==5 and not record.body.contains("鸟"),"arbitrary collision/bird counters cannot fabricate an unimplemented harm mechanism")
 for status in ["available","accepted","cancelled","declined","in_flight"]:
  f=fixture();f.order.status=status
  check(not capture(null,f).ok,"no delivery review for status "+status)
 f=fixture();f.ledger={};check(not capture(null,f).ok,"no fake review without authoritative formal ledger receipt")

func test_malformed() -> void:
 var base:Dictionary=Reviews.initial_state(1)
 for bad in [{},[],"broken",{"version":999}, {"version":1,"template_version":1,"start_day":1,"published_through_day":0,"pending":[],"published":[]}]:
  check(not Reviews.normalize_state(bad,1).ok,"malformed root fails closed: "+str(bad))
 var f:Dictionary=fixture();var pending:Dictionary=capture(base,f).state
 for key in ["success","integrity","elapsed","deadline","required","client","appearance_id","settlement_id","delivery_day"]:
  var bad:Dictionary=pending.duplicate(true);bad.pending[f.id][key]={"invalid":true}
  check(not Reviews.normalize_state(bad,1).ok,"malformed fact fails closed: "+key)
 for value in [NAN,INF,-INF,-1.0,101.0]:
  var bad:Dictionary=pending.duplicate(true);bad.pending[f.id].integrity=value
  check(not Reviews.normalize_state(bad,1).ok,"invalid integrity fails closed: "+str(value))
 var bad:Dictionary=pending.duplicate(true);bad.pending[f.id].client="伪造客户"
 check(not Reviews.normalize_state(bad,1).ok,"known actor cannot be rebound to another name")
 bad=pending.duplicate(true);bad.pending[f.id].delivery_day=2
 check(not Reviews.normalize_state(bad,1).ok,"future pending facts rejected")
 var published:Dictionary=Reviews.publish_next_day(pending,1,2).state
 for key in ["body","category","rating","published_day"]:
  bad=published.duplicate(true);bad.published[0][key]="invented"
  check(not Reviews.normalize_state(bad,2).ok,"tampered published field rejected: "+key)
 bad=published.duplicate(true);bad.published.append(bad.published[0].duplicate(true))
 check(not Reviews.normalize_state(bad,2).ok,"duplicate published ID rejected")
 f=fixture();f.ledger[f.id].elapsed=9.0
 check(not capture(pending,f).ok,"same settlement ID with conflicting facts rejected")
 bad=pending.duplicate(true);bad.pending[f.id].body="提前泄漏";bad.pending[f.id].bird_harm=true;bad.pending[f.id].credits=999
 var normalized:Dictionary=Reviews.normalize_state(bad,1)
 check(normalized.ok and not normalized.state.pending[f.id].has("body") and not normalized.state.pending[f.id].has("bird_harm") and not normalized.state.pending[f.id].has("credits"),"normalization whitelists facts and strips future copy, harm, finance fields")
 check(not Reviews.normalize_state(base,0).ok and not Reviews.normalize_state(base,Reviews.MAX_DAY+1).ok,"unbounded or invalid calendar rejected")

func test_bounds() -> void:
 var state:Dictionary=Reviews.initial_state(1)
 for day in range(1,31):
  for slot in ["A","B"]:state=capture(state,fixture(day,slot),day).state
  check(not capture(state,fixture(day,"C"),day).ok,"daily pending bound on day "+str(day))
  state=Reviews.publish_next_day(state,day,day+1).state
 check(state.published.size()==Reviews.MAX_PUBLISHED and state.pending.is_empty(),"30-entry feed remains bounded after 60 settlements")
 check(not capture(state,fixture(1),31).ok,"watermark prevents replay of a trimmed historical settlement")
 var count:int=state.published.size();state=Reviews.publish_next_day(state,31,32).state
 check(state.published.size()==count and state.published_through_day==31,"empty business day produces no invented reviews")

func clear_files() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)

func ready_order(e,slot:int=0) -> String:
 e.ensure_contracts();var id:String=e.contracts[slot].contract_id
 e.accept_contract(id);e.begin_dispatch([],[])
 return id

func telemetry() -> Dictionary:
 return {"integrity":1.0,"energy_used":12.0,"ammo_cost":2.0,"repair_cost":3.0,"lost_cost":4.0}

func finances(e) -> Dictionary:
 return {"credits":e.credits,"reputation":e.reputation,"deliveries":e.deliveries,"settled_ids":e.settled_ids.duplicate(true),"history":e.history.duplicate(true),"inventory":e.inventory.duplicate(true)}

func test_economy() -> void:
 clear_files();var e=Econ.new();var id:String=ready_order(e)
 var quote:Dictionary=e.estimate_delivery(e.active_contract(),telemetry(),8.0,true);var balance:int=e.credits
 var result:Dictionary=e.settle_contract(id,telemetry(),8.0,true)
 check(result.ok and e.credits==balance+int(quote.profit),"real economy settlement retains original single payment")
 check(e.review_state.pending.size()==1 and e.customer_reviews().is_empty(),"real settlement is pending and phone stays empty today")
 var money:Dictionary=finances(e)
 check(not e.settle_contract(id,telemetry(),8.0,true).ok,"actual duplicate settlement remains rejected")
 same(finances(e),money,"repeat settlement grants no additional rewards or fees")
 check(e.save_state([],[],{}),"pending facts and ledger share ordinary atomic save")
 var restored=Econ.new();restored.load_state()
 check(restored.customer_reviews().is_empty() and restored.review_state.pending.size()==1,"restart before next-day retains only pending facts")
 check(not restored.next_day().ok and restored.customer_reviews().is_empty(),"daytime transition cannot publish reviews")
 check(restored.close_day().ok,"actual shop closes normally")
 check(restored.next_day_and_save([],[],{}).ok,"successful saved next-day publishes reviews")
 check(restored.day==2 and restored.customer_reviews().size()==1,"real next-day feed contains one yesterday review")
 same(finances(restored),money,"publication changes no balance, reputation, inventory, settlement, or receipt")
 var again=Econ.new();again.load_state()
 same(again.review_state,restored.review_state,"post-publication restart keeps review and dates exactly")
 check(not again.next_day_and_save([],[],{}).ok and again.customer_reviews().size()==1,"repeated main transition cannot republish")
 var failed_id:String=ready_order(again)
 check(again.settle_contract(failed_id,telemetry(),8.0,false).ok,"formal failed delivery still settles")
 check(again.review_state.pending[failed_id].success==false,"formal failure queues a factual review")
 check(again.customer_reviews().size()==1,"new current-day failure does not leak alongside yesterday feed")
 var cancelled_id:String=again.contracts[1].contract_id;again.accept_contract(cancelled_id);again.cancel_accepted()
 check(not again.review_state.pending.has(cancelled_id),"canceled-before-dispatch creates no delivery review")
 again.close_day();again.next_day_and_save([],[],{})
 check(again.customer_reviews()[0].category=="failed","formal failure publishes next morning")

func test_failed_save() -> void:
 clear_files();var e=Econ.new();e.enable_story_mode();var id:String=e.contracts[0].contract_id
 e.accept_contract(id);e.mark_cargo_loaded(id);e.begin_dispatch([],[]);e.settle_contract(id,telemetry(),8.0,true);e.close_day()
 check(e.save_state([],[],{}),"night-before review transaction saved")
 var previous:Dictionary={}
 for key in ["day","jobs_today","phase","contracts","active_contract_id","last_trials","story_state","review_state"]:previous[key]=e.get(key).duplicate(true) if e.get(key) is Dictionary or e.get(key) is Array else e.get(key)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.next_day_and_save([],[],{}).ok,"write failure rejects next-day transaction")
 for key in previous:same(e.get(key),previous[key],"failed save restores "+key)
 check(e.customer_reviews().is_empty(),"failed next-day save exposes no new review")
 var restored=Econ.new();restored.load_state()
 check(restored.day==1 and restored.phase=="night" and restored.customer_reviews().is_empty(),"restart after failed transition restores un-published night")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.next_day_and_save([],[],{}).ok and e.customer_reviews().size()==1,"explicit retry publishes once after save recovers")

func test_migration() -> void:
 clear_files();var e=Econ.new();var id:String=ready_order(e);e.settle_contract(id,telemetry(),8.0,true);e.save_state([],[],{})
 var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"));old.erase("review_state");old.settings.erase("customer_reviews_schema")
 clear_files();var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
 var migrated=Econ.new();migrated.load_state()
 check(migrated.review_state.pending.is_empty() and migrated.customer_reviews().is_empty(),"legacy historical receipt is not retroactively queued")
 migrated.close_day();migrated.next_day_and_save([],[],{})
 check(migrated.customer_reviews().is_empty(),"first migrated next-day does not invent historical review")
 var id2:String=ready_order(migrated);migrated.settle_contract(id2,telemetry(),8.0,true);migrated.close_day();migrated.next_day_and_save([],[],{})
 check(migrated.customer_reviews().size()==1 and migrated.customer_reviews()[0].settlement_id==id2,"only new post-migration settlement participates")
 var good:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"));var bad:Dictionary=good.duplicate(true);bad.review_state.published[0].published_day=999
 check(not migrated._valid_save(bad),"present malformed review state invalidates save rather than resetting feed")
 file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(bad));file.close()
 var recovered=Econ.new();var parsed:Dictionary=recovered.load_state()
 check(not parsed.is_empty() and recovered.load_notice.contains("备份"),"corrupt primary uses existing validated backup recovery")
 # No valid backup: keep the genuine ledger and both source files, never reset.
 clear_files();file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(bad));file.close()
 var original_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
 var locked=Econ.new();var locked_save:Dictionary=locked.load_state()
 check(not locked_save.is_empty() and locked.review_load_blocked,"unrecoverable review corruption locks the actual loaded ledger")
 check(locked.credits==int(bad.credits) and locked.settled_ids.size()==bad.settled_ids.size(),"unrecoverable review corruption never fabricates a new shop balance")
 check(locked.customer_reviews().is_empty() and not locked.save_state([],[],{}),"unrecoverable review corruption fails closed for feed and writes")
 check(FileAccess.get_file_as_string("user://savegame.json")==original_bytes,"failed recovery preserves original source bytes")
 check(not locked.next_day_and_save([],[],{}).ok,"unrecoverable review corruption blocks next-day")
 for malformed_state in [null,[],"broken",12]:
  bad=good.duplicate(true);bad.review_state=malformed_state;clear_files()
  file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(bad));file.close()
  locked=Econ.new();locked.load_state()
  check(locked.review_load_blocked and not locked.save_state([],[],{}),"malformed review root remains blocked: "+str(malformed_state))

func test_untrusted_receipts() -> void:
 for key in ["contract_id","status","name","client","appearance_id","destination_name"]:
  for value in [null,{},[],12,true]:
   var f:Dictionary=fixture();f.order[key]=value
   # A stored receipt's destination takes precedence over mutable order copy.
   if key=="destination_name":f.ledger[f.id].erase("route_context")
   check(not capture(null,f).ok,"bad contract type rejected for %s/%s"%[key,str(value)])
 for key in ["contract_id","day","client","route","success","elapsed","deadline","integrity","required","route_context"]:
  for value in [{},[],"broken",true]:
   var f:Dictionary=fixture();f.ledger[f.id][key]=value
   if key=="success" and value is bool:continue
   check(not capture(null,f).ok,"bad receipt type rejected for %s/%s"%[key,str(value)])

func test_settlement_save_failure() -> void:
 clear_files();var e=Econ.new();var id:String=ready_order(e)
 check(e.save_state([],[],{}),"pre-settlement formal dispatch saved")
 var previous:Dictionary={}
 for key in ["credits","reputation","jobs_today","deliveries","contracts","settled_ids","history","last_settlement","story_state","review_state","in_flight","active_contract_id","load_notice"]:
  var value:Variant=e.get(key);previous[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 var original_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 check(not e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{}).ok,"failed formal-settlement save rejects pending-fact transaction")
 for key in previous:same(e.get(key),previous[key],"failed settlement save restores "+key)
 check(e.customer_reviews().is_empty() and e.review_state.pending.is_empty(),"failed settlement save leaves neither pending nor published review")
 check(FileAccess.get_file_as_string("user://savegame.json")==original_bytes,"failed settlement save preserves saved in-flight bytes")
 var restored=Econ.new();restored.load_state()
 check(restored.in_flight.contract_id==id and restored.settled_ids.is_empty() and restored.review_state.pending.is_empty(),"restart after failed settlement restores original dispatched order")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{}).ok,"recovered formal-settlement save commits once")
 var money:Dictionary=finances(e)
 check(not e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{}).ok,"retrying saved settlement is duplicate-rejected")
 same(finances(e),money,"repeated saved settlement adds no money or charge")
 e.close_day();e.next_day_and_save([],[],{})
 check(e.customer_reviews().size()==1,"recovered settlement produces exactly one review next morning")

func test_unreadable_saves() -> void:
 for filenames in [["savegame.json","savegame.backup.json"],["savegame.backup.json"]]:
  clear_files()
  for filename in filenames:
   var file=FileAccess.open("user://"+filename,FileAccess.WRITE);file.store_string("{malformed");file.close()
  var locked=Econ.new();var parsed:Dictionary=locked.load_state()
  check(parsed.is_empty() and locked.review_load_blocked,"existing malformed save(s) block new shop: "+str(filenames))
  check(not locked.save_state([],[],{}),"existing malformed save(s) block writes: "+str(filenames))
  for filename in filenames:check(FileAccess.get_file_as_string("user://"+filename)=="{malformed","preserve corrupt file bytes: "+filename)
  var money:Dictionary=finances(locked)
  locked.phase="night";locked.credits=10000;money=finances(locked)
  check(not locked.buy_part("beam",{"price":5}).ok and not locked.research_upgrade().ok and not locked.workshop_upgrade(1).ok and not locked.cancel_accepted().ok,"corrupt save guard blocks all financial mutation APIs")
  same(finances(locked),money,"blocked financial APIs preserve balance and ledger")
 clear_files();var e=Econ.new();e.save_state([],[],{});e.save_state([],[],{})
 var backup:String=FileAccess.get_file_as_string("user://savegame.backup.json")
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string("{malformed");file.close()
 var valid=Econ.new();var restored:Dictionary=valid.load_state()
 check(not restored.is_empty() and not valid.review_load_blocked and valid.load_notice.contains("备份"),"valid backup remains available for malformed JSON primary")
 check(FileAccess.get_file_as_string("user://savegame.backup.json")==backup,"backup recovery does not delete/archive/purge sources")
 clear_files();var fresh=Econ.new()
 check(fresh.load_state().is_empty() and not fresh.review_load_blocked,"truly absent saves still allow an intentional new shop")

func test_downgrade_detection() -> void:
 clear_files();var e=Econ.new();var id:String=ready_order(e);e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{});e.close_day();e.next_day_and_save([],[],{})
 var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(int(baseline.version)==5 and int(baseline.settings.customer_reviews_schema)==1,"new review save keeps paid-tier v5 protocol with a durable schema marker")
 var old=LegacyEcon.new();var old_loaded:Dictionary=old.load_state()
 var old_settings:Dictionary={};old_settings.merge(old_loaded.settings,true)
 check(old.save_state([],[],old_settings),"captured older v5 economy can re-save known settings")
 var dropped:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(not dropped.has("review_state") and dropped.settings.customer_reviews_schema==1,"known old executable drops reviews but preserves the detectable marker")
 var recovered=Econ.new();recovered.load_state()
 check(not recovered.review_load_blocked and recovered.customer_reviews().size()==1 and recovered.load_notice.contains("备份"),"returning newer loader recovers reviews from valid pre-downgrade backup")
 # A second old save replaces even that backup. Detect and lock both losses.
 old.save_state([],[],old_settings)
 var source:String=FileAccess.get_file_as_string("user://savegame.json")
 var locked=Econ.new();var parsed:Dictionary=locked.load_state()
 check(not parsed.is_empty() and locked.review_load_blocked,"two old saves cannot silently masquerade as legacy migration")
 check(not locked.save_state([],[],{}) and FileAccess.get_file_as_string("user://savegame.json")==source,"unrecoverable downgrade loss preserves source and requires explicit recovery")
 check(locked.credits==int(dropped.credits) and locked.customer_reviews().is_empty(),"downgrade-loss lock keeps actual ledger without inventing reviews")

func test_capture_failure_transaction() -> void:
 clear_files();var e=Econ.new();e.enable_story_mode()
 for slot in [0,1]:
  var id:String=e.contracts[slot].contract_id;e.accept_contract(id);e.mark_cargo_loaded(id);e.begin_dispatch([],[])
  if slot==0:check(e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{}).ok,"capture-rejection fixture retains one earlier valid pending review")
 var id:String=e.active_contract_id;check(e.save_state([],[],{}),"capture-rejection fixture has a durably saved formal dispatch")
 var original_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
 e.active_contract().appearance_id="injected_unknown_identity"
 check(Reviews.normalize_state(e.review_state,e.day).ok and e.review_state.pending.size()==1,"capture rejection is injected into facts while review_state remains valid")
 var previous:Dictionary={}
 for key in ["credits","reputation","jobs_today","deliveries","contracts","settled_ids","history","last_settlement","story_state","review_state","in_flight","active_contract_id","load_notice"]:
  var value:Variant=e.get(key);previous[key]=value.duplicate(true) if value is Dictionary or value is Array else value
 var rejected:Dictionary=e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{})
 check(not rejected.ok and rejected.message.contains("尚未保存"),"saved transaction rejects capture failure with a concise retry/reload notice")
 for key in previous:same(e.get(key),previous[key],"capture failure transaction restores "+key)
 check(FileAccess.get_file_as_string("user://savegame.json")==original_bytes,"capture rejection never writes an incomplete formal receipt")
 check(e.customer_reviews().is_empty() and e.review_state.pending.size()==1,"capture failure preserves previous pending facts without current-day disclosure")
 e.active_contract().appearance_id="elf_archivist"
 check(e.settle_contract_and_save(id,telemetry(),8.0,true,[],[],{}).ok and e.review_state.pending.size()==2,"corrected identity retries once without losing either review")
 # The unsaved compatibility method advertises its degraded result explicitly.
 var legacy=Econ.new();var legacy_id:String=ready_order(legacy);legacy.active_contract().appearance_id="injected_unknown_identity"
 var direct:Dictionary=legacy.settle_contract(legacy_id,telemetry(),8.0,true)
 check(direct.ok and not direct.review_pending and not direct.review_error.is_empty(),"legacy direct-settlement compatibility exposes explicit capture rejection")
