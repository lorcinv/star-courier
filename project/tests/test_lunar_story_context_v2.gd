extends SceneTree
const Stories=preload("res://scripts/courier_stories.gd")
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
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
 if fresh.is_empty():
  check(false,"lunar route authoring failed before story tests");quit(1);return
 for actor in Stories.IDS:
  var route:Dictionary=fresh.duplicate(true)
  route.contract_id="D2-LUNAR-"+actor;route.status="available";route.accepted_day=2;route.appearance_id=actor
  var bound:Dictionary=Stories.bind_contract(Stories.initial_state(123),route,2,1)
  var accepted:Dictionary=Stories.conversation_for(bound.state,bound.contract,"accept")
  check(text_of(accepted).contains("月面前哨收件台") and not text_of(accepted).contains("星港"),"lunar accept names true destination for "+actor)
  bound.contract.status="settled"
  var report:Dictionary={"contract_id":route.contract_id,"success":true}
  var settled:Dictionary=Stories.commit_settlement(bound.state,bound.contract,report)
  check(settled.advanced and text_of(settled.conversation).contains("月面回执"),"formal lunar receipt preserves lunar story for "+actor)
  var stored:Dictionary=JSON.parse_string(JSON.stringify(settled.state))
  var normalized:Dictionary=Stories.normalize_state(stored)
  var returns:Array=Stories.pending_return_conversations(normalized)
  check(returns.size()==1 and text_of(returns[0]).contains("月面前哨收件台") and not text_of(returns[0]).contains("星港"),"JSON restore retains actual lunar address for "+actor)
  var context:Dictionary=normalized.committed_contract_ids[route.contract_id].route_context
  check(context.route_profile==Content.ROUTE_PROFILE and context.route_kind=="lunar" and context.destination_id==Content.DESTINATION_ID,"story stores exact new content identity for "+actor)
 var wrong:Dictionary={"route_profile":Content.ROUTE_PROFILE,"route_kind":"moon","destination_id":"moon-regolith-airlock","route_name":"wrong","destination_name":"wrong"}
 check(Stories._normalize_route_context(wrong).is_empty(),"new story identity cannot reuse old airlock identity")
 var old:Dictionary={"route_profile":Stories.MOON_ROUTE_PROFILE,"route_kind":"moon","destination_id":"moon-regolith-airlock","route_name":"old","destination_name":"月面收件舱"}
 check(Stories._normalize_route_context(old)==old,"historical Moon story context remains unchanged")
 print("LUNAR_STORY_CONTEXT_V2_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
