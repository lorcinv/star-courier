extends SceneTree
## Bounded ledger lifecycle with explicit synthetic prior-day/telemetry fixtures.
## This is not GUI or successful-flight evidence. Requires a fresh test profile.
const Econ=preload("res://scripts/economy.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const RETURN:String="收到了。他说，一片叶子都没碰掉。"
var passed:int=0
var failed:int=0
var design:Array=Profile.starter_design()
var pad:Array=Profile.starter_launcher()
var settings:Dictionary={"volume":0.0,"reduced_motion":true}
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
 return ok
func same(a:Variant,b:Variant) -> bool:return Content._same(a,b)
func texts(conversation:Dictionary) -> Array:
 var result:Array=[]
 for line in conversation.get("lines",[]):result.append(line.text)
 return result
func fresh():
 var e=Econ.new();e.enable_force_mode();e.day=5;e.reputation=4;e.deliveries=2;e.credits=600
 e.story_state=Stories.initial_state(321);e.story_state.roster.human_courier.story_node=1
 e.enable_story_mode();e.starter_stock(design,pad);return e
func restored():
 var e=Econ.new();e.load_state(true);e.enable_story_mode();return e
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func ledger(e) -> Dictionary:
 return {"credits":e.credits,"reputation":e.reputation,"jobs_today":e.jobs_today,"deliveries":e.deliveries,"history":e.history.duplicate(true),"settled_ids":e.settled_ids.duplicate(true),"story_state":e.story_state.duplicate(true)}
func run_case(quality:float,success:bool,legacy:bool=false) -> void:
 var label:String="legacy" if legacy else str(quality)+"/"+str(success)
 var e=fresh()
 if not check(e.contracts.size()==2 and e.contracts[0].id==7 and e.contracts[1].id==1,"unchanged normal D5 route pair: "+label):return
 var order:Dictionary=e.contracts[0]
 var cid:String=order.contract_id
 check(cid=="D5-A" and order.client=="小禾" and order.cargo=="包好的一把小勺" and order.story_node==1,"existing recurring customer and spoon cargo identity: "+label)
 check(order.reward==350 and order.weight==1.25 and order.required==85.0 and order.deadline==85.0,"commercial terms unchanged: "+label)
 check(order.get("parcel_presentation_id")==Stories.MOSSLIGHT_SPOON_PARCEL and not e.contracts[1].has("parcel_presentation_id"),"only matching new ordinary order is tagged: "+label)
 if legacy:
  # Reconstruct the saved unmarked dev17 shape before exercising real reloads.
  order.erase("parcel_presentation_id")
  order.story=Stories.conversation_for(e.story_state,order,"accept").lines[0].text
 var frozen:Dictionary=order.duplicate(true)
 if not check(e.save_state(design,pad,settings),"available state durably saves: "+label):return
 var before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 e=restored();e.ensure_contracts()
 check(not e.review_load_blocked and same(e.contract_by_id(cid),frozen),"available contract reload keeps exact saved marker or absence: "+label)
 check(FileAccess.get_file_as_bytes("user://savegame.json")==before,"read and bind do not rewrite durable bytes: "+label)
 if not check(e.accept_contract_and_save(cid,design,pad,settings).ok,"accepted state durably commits: "+label):return
 frozen=disk().contracts[0].duplicate(true);e=restored()
 check(same(e.active_contract(),frozen),"accepted reload preserves existing contract exactly: "+label)
 var accept:Array=texts(e.story_conversation(cid,"accept"))
 check((accept==["小勺送去苔光温室。朋友在给幼苗换盆，铲子比花盆还大。","拿饭勺不就行了？","饭勺得留着吃饭，这把专门给花盆。"])==not legacy,"acceptance honors frozen opt-in at repeated story node: "+label)
 var unchanged:Dictionary=ledger(e)
 for unused in 4:
  e.story_conversation(cid,"accept");e.trial_route();e.estimate_delivery(e.active_contract(),{"integrity":quality,"energy_used":10.0},12.0,success)
 check(ledger(e)==unchanged and e.pending_story_returns().is_empty(),"trial/quote/dialogue reads do not advance or pay: "+label)
 if not check(e.mark_cargo_loaded(cid).ok and e.begin_dispatch(design,pad).ok and e.save_state(design,pad,settings),"formal dispatch snapshot durably commits: "+label):return
 var flight:Dictionary=disk().in_flight.duplicate(true);e=restored()
 check(not e.review_load_blocked and same(e.in_flight,flight),"in-flight reload preserves marker without replay changes: "+label)
 check(e.in_flight.route.has("parcel_presentation_id")==not legacy,"flight snapshot carries only original marker: "+label)
 var telemetry:Dictionary={"integrity":quality,"energy_used":10.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0}
 var quote:Dictionary=e.estimate_delivery(e.active_contract(),telemetry,12.0,success)
 var credits:int=e.credits
 if not check(e.settle_contract_and_save(cid,telemetry,12.0,success,design,pad,settings).ok,"formal settlement durably commits once: "+label):return
 var raw:Dictionary=disk();var receipt:Dictionary=raw.last_settlement.duplicate(true)
 check(receipt.has("parcel_presentation_id")==(success and not legacy),"successful financial receipt freezes marker only from original order: "+label)
 check(raw.story_state.committed_contract_ids[cid].has("parcel_presentation_id")==(success and not legacy),"story receipt freezes same version: "+label)
 check(e.credits==credits+int(quote.profit) and e.history.size()==1 and e.jobs_today==1 and e.story_state.roster.human_courier.story_node==2,"one unchanged payment and one story advance: "+label)
 e=restored()
 check(not e.review_load_blocked and same(e.last_settlement,receipt),"settled financial receipt reloads exactly: "+label)
 var expected:bool=success and quality==1.0 and not legacy
 check((texts(e.story_conversation(cid,"return"))==[RETURN])==expected,"durable return only claims full undamaged success: "+label)
 unchanged=ledger(e)
 check(not e.settle_contract(cid,telemetry,12.0,success).ok and ledger(e)==unchanged,"duplicate settlement changes no money, receipt or progression: "+label)
 if not check(e.close_day().ok and e.next_day_and_save(design,pad,settings).ok,"next day clears contracts through existing authoring: "+label):return
 e=restored()
 check(e.contract_by_id(cid).is_empty() and same(e.settled_ids[cid],receipt),"old receipt persists after contracts leave the day: "+label)
 check((texts(e.story_conversation(cid,"return"))==[RETURN])==expected,"return reads frozen receipt rather than current contracts: "+label)
 check(e.mark_story_seen(cid,cid+"/return") and not e.mark_story_seen(cid,cid+"/return") and e.story_conversation(cid,"return").is_empty(),"return consumes once without extra story progression: "+label)
 check(e.save_state(design,pad,settings),"consumed return saves: "+label)
 e=restored()
 check(e.story_conversation(cid,"return").is_empty() and e.story_state.roster.human_courier.story_node==2,"consumed cue stays consumed after reload: "+label)
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json"):
  printerr("Use a fresh isolated HOME/XDG_DATA_HOME. Existing profiles are not removed.");quit(2);return
 run_case(1.0,true);run_case(0.99,true);run_case(1.0,false);run_case(1.0,true,true)
 # Existing contracts generated while stories were off also remain untagged.
 var e=Econ.new();e.enable_force_mode();e.day=5;e.reputation=4;e.deliveries=2;e.credits=600;e.ensure_contracts()
 e.enable_story_mode()
 check(not e.contracts[0].has("parcel_presentation_id"),"late story opt-in never retrofits an already generated contract")
 print("MOSSLIGHT_PARCEL_ECONOMY_DEV18 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
