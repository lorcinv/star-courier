extends SceneTree
## Focused versioned-copy tests. No world, art, simulator or live profile.
const Stories=preload("res://scripts/courier_stories.gd")
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const ACCEPT:Array[String]=["小勺送去苔光温室。朋友在给幼苗换盆，铲子比花盆还大。","拿饭勺不就行了？","饭勺得留着吃饭，这把专门给花盆。"]
const RETURN:String="收到了。他说，一片叶子都没碰掉。"
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func texts(conversation:Dictionary) -> Array:
 var result:Array=[]
 for line in conversation.get("lines",[]):result.append(line.text)
 return result
func fixture(actor:String="human_courier",node:int=0) -> Dictionary:
 var route:Dictionary=Profile.route(Content.fresh_catalog())
 route.contract_id="D5-A";route.status="available";route.appearance_id=actor
 var state:Dictionary=Stories.initial_state(321)
 state.roster[actor].story_node=node
 return Stories.bind_contract(state,route,5,0)
func _initialize() -> void:
 for node in [0,1,3]:
  var f:Dictionary=fixture("human_courier",node)
  var original:Dictionary=f.contract.duplicate(true)
  check(not f.contract.has("parcel_presentation_id"),"ordinary bind does not retrofit a parcel: node "+str(node))
  f.contract=Stories.author_new_parcel_presentation(f.contract)
  check(Stories.parcel_presentation_id(f.contract)==Stories.MOSSLIGHT_SPOON_PARCEL,"new exact identity receives versioned marker: node "+str(node))
  check(texts(Stories.conversation_for(f.state,f.contract,"accept"))==ACCEPT,"exact three-line acceptance overrides generic recurring opener: node "+str(node))
  f.contract.erase("parcel_presentation_id")
  check(f.contract==original,"parcel authoring changes no route, cargo, fee or identity field: node "+str(node))
 for actor in Stories.IDS:
  var f:Dictionary=fixture(actor)
  var order:Dictionary=Stories.author_new_parcel_presentation(f.contract)
  check(order.has("parcel_presentation_id")== (actor=="human_courier"),"existing customer pool keeps its own parcel: "+actor)
 var f:Dictionary=fixture("human_courier",2)
 var old_conversation:Dictionary=Stories.conversation_for(f.state,f.contract,"accept")
 var old_state:Dictionary=f.state.duplicate(true)
 var old_contract:Dictionary=f.contract.duplicate(true)
 f.contract=Stories.author_new_parcel_presentation(f.contract)
 var contract:Dictionary=f.contract.duplicate(true)
 for key in ["parcel_presentation_id","appearance_id","species","story_id","route_profile","route_kind","destination_id","control_version","id"]:
  var malformed:Dictionary=contract.duplicate(true)
  malformed[key]="unknown" if key!="id" else 6
  check(Stories.parcel_presentation_id(malformed).is_empty(),"single selector rejects wrong "+key)
  check(texts(Stories.conversation_for(f.state,malformed,"accept"))!=ACCEPT,"wrong "+key+" cannot receive new story")
 # Regression: Variant String id versus numeric7 previously emitted a script
 # error despite the visual test's assertions reporting a neutral fallback.
 for pair in [["id","7"],["id",{}],["id",null],["id",NAN],["control_version",7],["parcel_presentation_id",1],["route_profile",{}],["route_kind",2],["destination_id",[]],["appearance_id",true],["species",1],["story_id",[]],["name",false],["destination_name",{}]]:
  var malformed:Dictionary=contract.duplicate(true);malformed[pair[0]]=pair[1]
  check(Stories.parcel_presentation_id(malformed).is_empty(),"malformed Variant selector safely rejects "+str(pair[0])+" / "+str(pair[1]))
 var rebound:Dictionary=Stories.bind_contract(Stories.normalize_state(JSON.parse_string(JSON.stringify(old_state))),old_contract,5,0)
 check(rebound.contract==old_contract and Stories.conversation_for(rebound.state,rebound.contract,"accept")==old_conversation,"old saved D5-A stays unmarked and keeps old acceptance on rebind")
 contract.status="settled"
 var intact:Dictionary={"contract_id":"D5-A","success":true,"integrity":100.0}
 var trial:Dictionary=Stories.commit_settlement(f.state,contract,intact,true)
 check(not trial.advanced and trial.state==f.state and trial.conversation.is_empty(),"trial cannot advance, create return or grant a reward")
 for quality in [100.0,99.999,99.0,85.0,40.0,0.0,null,"100",-1.0,101.0]:
  var report:Dictionary={"contract_id":"D5-A","success":true}
  if quality!=null:report.integrity=quality
  var settled:Dictionary=Stories.commit_settlement(f.state,contract,report)
  var saved:Dictionary=Stories.normalize_state(JSON.parse_string(JSON.stringify(settled.state)))
  var receipt:Dictionary=saved.committed_contract_ids["D5-A"]
  check(settled.advanced and receipt.get("parcel_presentation_id")==Stories.MOSSLIGHT_SPOON_PARCEL,"successful versioned receipt freezes identity: "+str(quality))
  var cue:Dictionary=Stories.conversation_for(saved,{"contract_id":"D5-A"},"return")
  check((texts(cue)==[RETURN])==(quality is float and quality==100.0),"only proven fully undamaged success claims no leaf loss: "+str(quality))
  check(texts(Stories.conversation_for(saved,{"contract_id":"D5-A"},"result"))!=[RETURN],"result does not duplicate return-only cue: "+str(quality))
  var before:Dictionary=saved.duplicate(true)
  for unused in 4:Stories.conversation_for(saved,{"contract_id":"D5-A"},"return")
  var duplicate:Dictionary=Stories.commit_settlement(saved,contract,intact)
  check(saved==before and duplicate.state==before and not duplicate.advanced,"reads and duplicate settlement never advance again: "+str(quality))
 var settled:Dictionary=Stories.commit_settlement(f.state,contract,intact)
 var seen:Dictionary=Stories.mark_seen(settled.state,"D5-A","D5-A/return")
 check(Stories.pending_return_conversations(seen).is_empty() and Stories.mark_seen(seen,"D5-A","D5-A/return")==seen,"return consumption is one-time and idempotent")
 var failure:Dictionary=Stories.commit_settlement(f.state,contract,{"contract_id":"D5-A","success":false,"integrity":100.0})
 check(not failure.state.committed_contract_ids["D5-A"].has("parcel_presentation_id") and texts(Stories.conversation_for(failure.state,{"contract_id":"D5-A"},"return"))!=[RETURN],"failure keeps ordinary receipt even when cargo was intact")
 var old_settled:Dictionary=old_contract.duplicate(true);old_settled.status="settled"
 var old:Dictionary=Stories.commit_settlement(old_state,old_settled,intact)
 check(not old.state.committed_contract_ids["D5-A"].has("parcel_presentation_id"),"legacy success never inherits new parcel marker")
 var old_receipt:Dictionary=old.state.committed_contract_ids["D5-A"].duplicate(true)
 var old_return:Dictionary=Stories.conversation_for(old.state,old_settled,"return")
 check(Stories.conversation_for(old.state,contract,"return")==old_return and old.state.committed_contract_ids["D5-A"]==old_receipt,"today's tagged contract cannot retrofit a historical receipt")
 var normalized:Dictionary=Stories.normalize_state(JSON.parse_string(JSON.stringify(old.state)))
 check(normalized==old.state,"old saved receipts and history normalize without new fields")
 var wrong_receipt:Dictionary=settled.state.duplicate(true)
 wrong_receipt.committed_contract_ids["D5-A"].route_context.route_kind="wormhole"
 check(texts(Stories.conversation_for(wrong_receipt,{"contract_id":"D5-A"},"return"))!=[RETURN],"malformed frozen route cannot claim the specialized return")
 for key in ["route_kind","destination_id"]:
  var malformed_receipt:Dictionary=settled.state.duplicate(true)
  malformed_receipt.committed_contract_ids["D5-A"].route_context[key]=7
  var normalized_receipt:Dictionary=Stories.normalize_state(malformed_receipt)
  var fallback:Dictionary=Stories.conversation_for(normalized_receipt,{"contract_id":"D5-A"},"return")
  check(not normalized_receipt.committed_contract_ids["D5-A"].has("route_context") and not normalized_receipt.committed_contract_ids["D5-A"].has("parcel_presentation_id") and not fallback.is_empty() and texts(fallback)!=[RETURN],"numeric receipt "+key+" drops malformed context and safely uses ordinary return")
 print("MOSSLIGHT_PARCEL_STORY_DEV18 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
