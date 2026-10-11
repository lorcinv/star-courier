extends SceneTree
const Stories=preload("res://scripts/courier_stories.gd")
const FrozenStories=preload("res://tests/fixtures/protected_bird_controller/frozen_courier_stories.gd")
const Receipt=preload("res://scripts/flight_receipt.gd")
const FrozenReceipt=preload("res://tests/fixtures/protected_bird_controller/frozen_flight_receipt.gd")
const Profile=preload("res://scripts/pilot_protected_bird_profile.gd")
const Offer=preload("res://scripts/protected_bird_offer_v1.gd")
const Policy=preload("res://scripts/protected_bird_authoring_policy.gd")
var passed:int=0
var failed:int=0
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func same(a:Variant,b:Variant,label:String) -> void:check(JSON.stringify(a,"",true,true)==JSON.stringify(b,"",true,true),label)
func _initialize() -> void:
 for profile in ["",Stories.GROUND_ROUTE_PROFILE,Stories.OTHERWORLD_ROUTE_PROFILE,Stories.MOON_ROUTE_PROFILE]:
  for actor in Stories.IDS:
   var contract:Dictionary={"contract_id":"COPY-TEST","status":"available","appearance_id":actor,"name":"城市货站 → 测试目的地","destination_name":"测试目的地","route_profile":profile}
   if profile==Stories.MOON_ROUTE_PROFILE:contract.route_kind="moon";contract.destination_id="moon-regolith-airlock"
   var actual:Dictionary=Stories.bind_contract(Stories.initial_state(420),contract,1,0)
   var frozen:Dictionary=FrozenStories.bind_contract(FrozenStories.initial_state(420),contract,1,0)
   same(actual,frozen,"old profile/actor binding byte equality: "+profile+"/"+actor)
   same(Stories.conversation_for(actual.state,actual.contract,"accept"),FrozenStories.conversation_for(frozen.state,frozen.contract,"accept"),"old acceptance output byte equality")
   for success in [false,true]:
    var settled:Dictionary=actual.contract.duplicate(true);settled.status="settled"
    var report:Dictionary={"contract_id":"COPY-TEST","success":success}
    var current:Dictionary=Stories.commit_settlement(actual.state,settled,report)
    var old:Dictionary=FrozenStories.commit_settlement(frozen.state,settled,report)
    same(current,old,"old story commit and result byte equality")
    same(Stories.pending_return_conversations(current.state),FrozenStories.pending_return_conversations(old.state),"old return output byte equality")
 for actor in Stories.IDS:
  var authored:Dictionary=Offer.create_new_offer({"version":Policy.VERSION,"world_seed":420,"introduced_day":0},5,actor)
  check(authored.ok,"valid commercial bird story fixture")
  var bound:Dictionary=Stories.bind_contract(Stories.initial_state(420),authored.offer,5,0)
  var context:Dictionary=Stories._contract_route_context(bound.contract)
  check(context.route_profile==Profile.ROUTE_PROFILE,"bird context retains actual v5 route identity")
  var accept:Dictionary=Stories.conversation_for(bound.state,bound.contract,"accept")
  check(accept.route_hint==authored.offer.name,"bird story uses actual route name")
  for success in [false,true]:
   var settled:Dictionary=bound.contract.duplicate(true);settled.status="settled"
   var result:Dictionary=Stories.commit_settlement(bound.state,settled,{"contract_id":"D5-A","success":success})
   check(result.advanced and result.conversation.title=="异界回执","v5 story selects otherworld result without v4 relabel")
   var saved:Dictionary=result.state.committed_contract_ids["D5-A"].route_context
   check(saved.route_profile==Profile.ROUTE_PROFILE and saved.destination_name=="苔光驿站","v5 committed copy context remains exact")
   var restored:Dictionary=Stories.normalize_state(JSON.parse_string(JSON.stringify(result.state)))
   same(restored,result.state,"v5 context survives saved story normalization")
   var text:String=JSON.stringify(Stories.pending_return_conversations(restored))
   check(text.contains("苔光驿站") and not text.contains("mosslight-protected") and not text.contains("pilot-v5"),"return dialogue uses user-facing destination without helper codes")
 var current=Receipt.new();var old=FrozenReceipt.new()
 for version in ["","pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole"]:
  current.reset();old.reset()
  for elapsed in [0.0,2.0,10.0,30.0]:
   var data:Dictionary={"control_version":version,"elapsed":elapsed,"wormhole_phase":"space","wormhole_last_denial":"exit_blocked","events":["1.00s  出口被挡住了，本次无法通行。","2.00s  电池耗尽。"]}
   same(current.update(data),old.update(data),"old receipt output byte equality "+version+" @ "+str(elapsed))
 current.reset()
 var pinned:Dictionary={"control_version":Profile.CONTROL_VERSION,"elapsed":30.0,"wormhole_phase":"space","wormhole_last_denial":"exit_blocked","events":["1.00s  出口被挡住了，本次无法通行。"]}
 check(current.update(pinned).size()==1,"v5 retains actionable unresolved wormhole denial")
 pinned.wormhole_phase="otherworld";check(current.update(pinned).is_empty(),"v5 clears stale denial after actual transit")
 pinned.control_version="pilot-v99";pinned.wormhole_phase="space";check(current.update(pinned).is_empty(),"future protocol never inherits v5 presentation")
 for reason in ["node_budget","earlier_uncertain_root","invalid_harm_source: origin_missing"]:
  var raw:String="12.50s  "+Receipt.BIRD_FAILURE_PREFIX+reason
  var projected:String=Receipt.player_event(raw,Profile.CONTROL_VERSION)
  check(projected=="12.50s  "+Receipt.BIRD_FAILURE_COPY,"v5 exact diagnostic projection preserves timestamp and concise failure")
  current.reset()
  var cue:Array=current.update({"control_version":Profile.CONTROL_VERSION,"elapsed":13.0,"events":[raw]})
  check(cue.size()==1 and cue[0].text==Receipt.BIRD_FAILURE_COPY and cue[0].source==projected,"HUD label and source tooltip both hide internal reason")
  for version in ["","pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v99"]:
   check(Receipt.player_event(raw,version)==raw,"diagnostic projection never changes other protocol output: "+version)
 check(Receipt.player_event("12.50s  电池耗尽。",Profile.CONTROL_VERSION)=="12.50s  电池耗尽。","ordinary gameplay failure remains unchanged")
 print("PROTECTED_BIRD_COPY_CONTEXT passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
