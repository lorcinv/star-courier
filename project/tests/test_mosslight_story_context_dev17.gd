extends SceneTree
## Address-only extension of the existing story system. No new story arc.
const Stories=preload("res://scripts/courier_stories.gd")
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func text_of(conversation:Dictionary) -> String:
 var result:String=str(conversation.get("title",""))+" "+str(conversation.get("route_hint",""))
 for line in conversation.get("lines",[]):result+=" "+str(line.text)
 return result
func _initialize() -> void:
 var fresh:Dictionary=Content.author(Content.fresh_catalog())
 if fresh.is_empty():check(false,"route authors before story test");quit(1);return
 for actor in Stories.IDS:
  for success in [false,true]:
   var route:Dictionary=fresh.duplicate(true)
   route.contract_id="D3-MOSSLIGHT-"+actor+str(success);route.status="available";route.accepted_day=3;route.appearance_id=actor
   var bound:Dictionary=Stories.bind_contract(Stories.initial_state(123),route,3,1)
   var accepted:Dictionary=Stories.conversation_for(bound.state,bound.contract,"accept")
   check(text_of(accepted).contains(Content.FIELDS.destination_name) and not text_of(accepted).contains("星港") and not text_of(accepted).contains("异界"),"new ordinary accept names actual destination: "+actor+str(success))
   bound.contract.status="settled"
   var report:Dictionary={"contract_id":route.contract_id,"success":success}
   var settled:Dictionary=Stories.commit_settlement(bound.state,bound.contract,report)
   check(settled.advanced and text_of(settled.conversation).contains(Content.FIELDS.destination_name),"formal receipt keeps actual address: "+actor+str(success))
   var normalized:Dictionary=Stories.normalize_state(JSON.parse_string(JSON.stringify(settled.state)))
   var returns:Array=Stories.pending_return_conversations(normalized)
   check(returns.size()==1 and text_of(returns[0]).contains(Content.FIELDS.destination_name) and not text_of(returns[0]).contains("星港") and not text_of(returns[0]).contains("异界"),"saved return conversation retains true address: "+actor+str(success))
   var context:Dictionary=normalized.committed_contract_ids[route.contract_id].route_context
   check(context.route_profile==Content.ROUTE_PROFILE and context.route_kind=="mosslight" and context.destination_id==Content.DESTINATION_ID,"saved new content identity is exact: "+actor+str(success))
 var wrong:Dictionary={"route_profile":Content.ROUTE_PROFILE,"route_kind":"wormhole","destination_id":"mosslight-delivery-platform-v2","route_name":"wrong","destination_name":"wrong"}
 check(Stories._normalize_route_context(wrong).is_empty(),"new story context cannot become historical wormhole")
 wrong.route_kind="mosslight";wrong.destination_id="unknown"
 check(Stories._normalize_route_context(wrong).is_empty(),"new story context cannot borrow an unrecognized receiver")
 for profile in [Stories.GROUND_ROUTE_PROFILE,Stories.FREE_GROUND_ROUTE_PROFILE,Stories.OTHERWORLD_ROUTE_PROFILE,Stories.PROTECTED_BIRD_ROUTE_PROFILE,Stories.MOON_ROUTE_PROFILE,Stories.LUNAR_ROUTE_PROFILE,""]:
  var old:Dictionary={"route_profile":profile,"route_name":"old route","destination_name":"old destination"}
  if profile==Stories.MOON_ROUTE_PROFILE:old.route_kind="moon";old.destination_id="moon-regolith-airlock"
  if profile==Stories.LUNAR_ROUTE_PROFILE:old.route_kind="lunar";old.destination_id="lunar-delivery-platform-v2"
  check(Stories._normalize_route_context(old)==old,"historical context remains exact: "+profile)
 print("MOSSLIGHT_STORY_CONTEXT_DEV17 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
