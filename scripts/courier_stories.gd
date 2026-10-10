class_name CourierStories
extends RefCounted
## Pure JSON-safe story helpers. Never grants money, reputation, parts or rewards.
## Call commit_settlement only AFTER Economy has committed its unique formal report.
const VERSION:int=1
const MAX_PENDING_RETURNS:int=8
const GROUND_ROUTE_PROFILE:String="ground-city-v1"
const IDS:Array[String]=["human_courier","elf_archivist","alien_botanist","robot_machinist"]
const PROFILES:Dictionary={
 "human_courier":{"name":"小禾","species":"human","story_id":"spoon_at_the_station","cargo":"包好的一把小勺","accessories":["none"],"voice_pitch":1.12},
 "elf_archivist":{"name":"叶笺","species":"elf","story_id":"a_bookmark_on_leave","cargo":"压花书签","accessories":["book_pouch","map_case"],"voice_pitch":1.26},
 "alien_botanist":{"name":"绒团","species":"alien","story_id":"sunny_side_of_a_pot","cargo":"一盆会打盹的幼苗","accessories":["seed_pod","field_vial"],"voice_pitch":1.42},
 "robot_machinist":{"name":"铆钉","species":"robot","story_id":"a_kettle_for_two","cargo":"旧水壶的哨片","accessories":["tool_pack","power_cell"],"voice_pitch":0.86}
}

static func stable_seed(text:String) -> int:
 # Explicit arithmetic avoids process-specific or engine-version-dependent hashes.
 var result:int=5381
 for byte in text.to_utf8_buffer():result=(result*33+int(byte))%2147483647
 return result

static func initial_state(world_seed:int=0) -> Dictionary:
 # One saved cosmetic seed per new shop. Simulation RNG is never consulted
 # during a render, conversation or reload; species-compatible choices persist.
 var roster:Dictionary={}
 for id in IDS:roster[id]={"appearance_seed":stable_seed(str(world_seed)+"/"+id)}
 return normalize_state({"world_seed":world_seed,"roster":roster})

static func _saved_int(value:Variant,fallback:int) -> int:
 if value is int:return value
 if value is float and is_finite(value):return int(value)
 return fallback

static func _identity(id:String,old:Dictionary) -> Dictionary:
 var profile:Dictionary=PROFILES[id]
 var seed:int=_saved_int(old.get("appearance_seed"),stable_seed("star-courier-v1/"+id))
 # Bound saves before indexing; avoid overflowing deterministic arithmetic later.
 seed=posmod(seed,2147483647)
 var accessory:String=str(old.get("accessory_id",profile.accessories[posmod(seed,profile.accessories.size())]))
 if not accessory in profile.accessories:accessory=profile.accessories[posmod(seed,profile.accessories.size())]
 return {"appearance_id":id,"appearance_seed":seed,"species":profile.species,"accessory_id":accessory,"story_id":profile.story_id,"story_node":clampi(_saved_int(old.get("story_node"),0),0,3)}

static func normalize_state(raw:Dictionary) -> Dictionary:
 var state:Dictionary={"version":VERSION,"world_seed":_saved_int(raw.get("world_seed"),0),"roster":{},"contract_bindings":{},"seen_dialogue_ids":{},"committed_contract_ids":{},"pending_returns":[]}
 var roster:Dictionary=raw.get("roster",{}) if raw.get("roster") is Dictionary else {}
 for id in IDS:
  state.roster[id]=_identity(id,roster.get(id,{}) if roster.get(id) is Dictionary else {})
 # Nested entries are untrusted save data; rebuild only compatible identities.
 if raw.get("contract_bindings") is Dictionary:
  for cid in raw.contract_bindings:
   var old:Variant=raw.contract_bindings[cid]
   if not cid is String or cid.is_empty() or not old is Dictionary:continue
   var id:Variant=old.get("appearance_id")
   if not id is String or not PROFILES.has(id):continue
   state.contract_bindings[cid]=_identity(id,old)
 if raw.get("seen_dialogue_ids") is Dictionary:
  for cid in raw.seen_dialogue_ids:
   var seen:Variant=raw.seen_dialogue_ids[cid]
   if not cid is String or not state.contract_bindings.has(cid) or not seen is Dictionary:continue
   var valid:Dictionary={}
   for did in seen:
    if did is String and did in [cid+"/accept",cid+"/result",cid+"/return"] and seen[did] is bool and seen[did]:valid[did]=true
   if not valid.is_empty():state.seen_dialogue_ids[cid]=valid
 if raw.get("committed_contract_ids") is Dictionary:
  for cid in raw.committed_contract_ids:
   var report:Variant=raw.committed_contract_ids[cid]
   if not cid is String or not state.contract_bindings.has(cid) or not report is Dictionary:continue
   if report.get("success") is bool:
    var receipt:Dictionary={"success":report.success}
    var context:Dictionary=_normalize_route_context(report.get("route_context"))
    # Optional copy context belongs to this unique receipt. Never infer it for
    # old success-only entries from today's contract, roster or route defaults.
    if not context.is_empty():receipt.route_context=context
    state.committed_contract_ids[cid]=receipt
 if raw.get("pending_returns") is Array:
  for cid in raw.pending_returns:
   if not cid is String or not state.contract_bindings.has(cid) or not state.committed_contract_ids.has(cid):continue
   if state.seen_dialogue_ids.get(cid,{}).has(cid+"/return"):continue
   if not state.pending_returns.has(cid):state.pending_returns.append(cid)
 while state.pending_returns.size()>MAX_PENDING_RETURNS:state.pending_returns.pop_front()
 return state

static func bind_contract(raw:Dictionary,contract:Dictionary,day:int,slot:int=0) -> Dictionary:
 var state:=normalize_state(raw)
 var order:=contract.duplicate(true)
 var cid:String=str(order.get("contract_id",""))
 if cid.is_empty():return {"state":state,"contract":order,"actor":{}}
 if not state.contract_bindings.has(cid):
  # Never retrofit an identity onto a legacy dispatch already in flight/settled.
  if str(order.get("status","")) in ["in_flight","settled"]:return {"state":state,"contract":order,"actor":{}}
  var id:String=str(order.get("appearance_id",IDS[posmod((maxi(day,1)-1)*2+slot,IDS.size())]))
  if not PROFILES.has(id):id=IDS[posmod((maxi(day,1)-1)*2+slot,IDS.size())]
  state.contract_bindings[cid]=state.roster[id].duplicate(true)
 var binding:Dictionary=state.contract_bindings[cid]
 for key in ["appearance_id","appearance_seed","species","accessory_id","story_id","story_node"]:order[key]=binding.get(key)
 var actor:=actor_metadata(binding)
 if not actor.is_empty():order.client=actor.name;order.cargo=PROFILES[str(binding.appearance_id)].cargo
 return {"state":state,"contract":order,"actor":actor}

static func actor_metadata(binding:Dictionary) -> Dictionary:
 var id:String=str(binding.get("appearance_id",""))
 if not PROFILES.has(id):return {}
 var result:=binding.duplicate(true)
 result.name=PROFILES[id].name;result.voice_pitch=PROFILES[id].voice_pitch
 result.body_path="res://assets/2d_v5/actors/customer-idle-pixel.png" if id=="human_courier" else "res://assets/2d_v5/npcs/%s/idle-pixel.png"%id
 result.portraits={}
 for emotion in ["neutral","pleased","concerned"]:
  result.portraits[emotion]="res://assets/2d_v5/dialogue/human_courier-%s.png"%emotion if id=="human_courier" else "res://assets/2d_v5/npcs/%s/portraits/%s.png"%[id,emotion]
 return result

static func mark_seen(raw:Dictionary,contract_id:String,dialogue_id:String) -> Dictionary:
 var state:=normalize_state(raw)
 if not state.contract_bindings.has(contract_id):return state
 # Foreign IDs may not hide another contract's story.
 if not dialogue_id.begins_with(contract_id+"/"):return state
 if not state.seen_dialogue_ids.has(contract_id):state.seen_dialogue_ids[contract_id]={}
 state.seen_dialogue_ids[contract_id][dialogue_id]=true
 if dialogue_id==contract_id+"/return":state.pending_returns.erase(contract_id)
 return state

static func conversation_for(raw:Dictionary,contract:Dictionary,beat:String,success:bool=true) -> Dictionary:
 var state:=normalize_state(raw)
 var cid:String=str(contract.get("contract_id",""))
 if not state.contract_bindings.has(cid) or not beat in ["accept","result","return"]:return {}
 var did:String=cid+"/"+beat
 if state.seen_dialogue_ids.get(cid,{}) is Dictionary and state.seen_dialogue_ids.get(cid,{}).has(did):return {}
 if beat in ["result","return"] and not state.committed_contract_ids.has(cid):return {}
 var binding:Dictionary=state.contract_bindings[cid]
 var actor:=actor_metadata(binding)
 if actor.is_empty():return {}
 var context:Dictionary=_contract_route_context(contract)
 if beat in ["result","return"]:
  success=bool(state.committed_contract_ids[cid].get("success",false))
  context=state.committed_contract_ids[cid].get("route_context",{})
 var ground:bool=str(context.get("route_profile",""))==GROUND_ROUTE_PROFILE
 var title:String="柜台来信" if beat=="accept" else (("货站回执" if ground else "星港回执") if beat=="result" else "又见面了")
 var lines:Array=_ground_lines(str(binding.appearance_id),beat,success,int(binding.get("story_node",0)),str(context.get("destination_name",""))) if ground else _lines(str(binding.appearance_id),beat,success,int(binding.get("story_node",0)))
 return {"id":did,"dialogue_id":did,"contract_id":cid,"beat":beat,"title":title,"route_hint":str(context.get("route_name","晨星社区 → 星港中转站")),"lines":lines,"actor":actor}

static func _normalize_route_context(raw:Variant) -> Dictionary:
 # Copy metadata only. Never a route authoring/migration or physics input path.
 if not raw is Dictionary:return {}
 for key in ["route_profile","route_name","destination_name"]:
  if not raw.get(key) is String:return {}
  if str(raw[key]).length()>160 or str(raw[key]).contains("\n") or str(raw[key]).contains("\r"):return {}
 if not raw.route_profile in ["",GROUND_ROUTE_PROFILE]:return {}
 if str(raw.route_name).strip_edges().is_empty() or str(raw.destination_name).strip_edges().is_empty():return {}
 return {"route_profile":raw.route_profile,"route_name":raw.route_name,"destination_name":raw.destination_name}

static func _contract_route_context(contract:Dictionary) -> Dictionary:
 # Missing route_profile deliberately means the old ascent/starport semantics.
 # No coordinate/altitude heuristic may reclassify an old saved v3 contract.
 return _normalize_route_context({"route_profile":contract.get("route_profile",""),"route_name":contract.get("name",""),"destination_name":contract.get("destination_name","星港中转站")})

static func commit_settlement(raw:Dictionary,contract:Dictionary,report:Dictionary,is_trial:bool=false) -> Dictionary:
 var state:=normalize_state(raw)
 var cid:String=str(contract.get("contract_id",""))
 var unchanged:Dictionary={"state":state,"advanced":false,"conversation":{}}
 if is_trial or cid.is_empty() or str(report.get("contract_id",""))!=cid:return unchanged
 if not state.contract_bindings.has(cid) or state.committed_contract_ids.has(cid):return unchanged
 # Require the actual committed contract status; estimates/previews cannot advance.
 if str(contract.get("status",""))!="settled" or not report.get("success") is bool:return unchanged
 var id:String=str(state.contract_bindings[cid].get("appearance_id",""))
 if not state.roster.has(id):return unchanged
 state.committed_contract_ids[cid]={"success":bool(report.success)}
 var context:Dictionary=_contract_route_context(contract)
 if not context.is_empty():state.committed_contract_ids[cid].route_context=context
 state.roster[id].story_node=mini(int(state.roster[id].story_node)+1,3)
 state.pending_returns.append(cid)
 while state.pending_returns.size()>MAX_PENDING_RETURNS:state.pending_returns.pop_front()
 return {"state":state,"advanced":true,"conversation":conversation_for(state,contract,"result",bool(report.success))}

static func pending_return_conversations(raw:Dictionary) -> Array:
 var state:=normalize_state(raw);var result:Array=[]
 for cid in state.pending_returns:
  var convo:=conversation_for(state,{"contract_id":cid},"return")
  if not convo.is_empty():result.append(convo)
 return result

static func _line(speaker:String,text:String,expression:String="neutral") -> Dictionary:
 return {"speaker":speaker,"text":text,"expression":expression}

static func _ground_lines(id:String,beat:String,success:bool,story_node:int,destination:String) -> Array:
 if beat=="accept" and story_node>0:
  return [_line("npc","又来麻烦你了。这回送去%s，我把地址写大了。"%destination,"pleased"),_line("clerk","看见了。老规矩，先把箱子垫稳。","warm_smile")]
 if beat=="result" and not success:
  return [_line("npc","%s的回执我看到了。这次没送成，先把人和装置照顾好。"%destination,"concerned"),_line("clerk","我会把这次的问题记下来。下一件，重新检查。","concerned")]
 if beat=="return" and not success:
  return [_line("npc","我来看看你。%s那份包裹的事慢慢来，别为了赶路把自己弄得太累。"%destination,"neutral"),_line("clerk","嗯。今天会从最小的一箱开始。","warm_smile")]
 match id+"/"+beat:
  "human_courier/accept":return [_line("npc","帮我把小勺送到%s吧。朋友调去那边值早班，连着三天只带了叉子。"%destination,"concerned"),_line("clerk","一把勺子，也值得单独跑一趟？","curious"),_line("npc","他早饭喝粥。已经用叉子捞了三天米粒了。","pleased")]
  "human_courier/result":return [_line("npc","%s的朋友签收了，还发来一张空碗的照片。"%destination,"pleased"),_line("clerk","看来这把勺子，上班第一天就很忙。","pleased")]
  "human_courier/return":return [_line("npc","%s的朋友让我转告你：今天的粥，终于没凉。"%destination,"pleased"),_line("clerk","那就好。下次出门值班，记得先检查餐具。","warm_smile")]
  "elf_archivist/accept":return [_line("npc","这枚书签送到%s。那里的值班员总把借书条夹进自己的小说。"%destination,"neutral"),_line("clerk","所以大家都找不到借书条了？","curious"),_line("npc","找得到。得先听她讲完那一章。","pleased")]
  "elf_archivist/result":return [_line("npc","%s回话了，书签很合适，借书条也各就各位了。"%destination,"pleased"),_line("clerk","那一章讲完了吗？","curious"),_line("npc","还没。她把下一章寄给我了。","concerned")]
  "elf_archivist/return":return [_line("npc","%s寄来的下一章，我看完了。原来她一直讲错了凶手。"%destination,"pleased"),_line("clerk","嘘，这句可别写在包裹外面。","surprised")]
  "alien_botanist/accept":return [_line("npc","这盆幼苗送到%s的向阳窗边。见到太阳，它就会醒一会儿。"%destination,"neutral"),_line("clerk","箱子上需要写什么？","curious"),_line("npc","写轻拿轻放就好。别写懒，它会不好意思。","concerned")]
  "alien_botanist/result":return [_line("npc","%s说它醒了，还朝窗户挪了半厘米。"%destination,"pleased"),_line("clerk","这么小的脚程，也算顺利到家了。","warm_smile")]
  "alien_botanist/return":return [_line("npc","它现在每天替%s的值班员看日出。今天还多长了一片叶子。"%destination,"pleased"),_line("clerk","原来它也在认真上班。","pleased")]
  "robot_machinist/accept":return [_line("npc","这片旧水壶哨片，送给%s值班的室友。新水壶叫得太准时了。"%destination,"neutral"),_line("clerk","准时也有问题？","curious"),_line("npc","旧的会先哼两声。正好够他慢慢找杯子。","pleased")]
  "robot_machinist/result":return [_line("npc","%s的哨片装好了。刚才他发来消息：杯子找到了。"%destination,"pleased"),_line("clerk","水也开了？","curious"),_line("npc","还没有。还是熟悉的两声。","pleased")]
  "robot_machinist/return":return [_line("npc","他给我留了一个杯子。下次休息，我去%s喝茶。"%destination,"pleased"),_line("clerk","这回自己送一趟点心，正好配茶。","warm_smile")]
 return []

static func _lines(id:String,beat:String,success:bool,story_node:int) -> Array:
 if beat=="accept" and story_node>0:
  return [_line("npc","又来麻烦你了。还是送去星港中转站，这回我把地址写大了。","pleased"),_line("clerk","看见了。老规矩，先把箱子垫稳。","warm_smile")]
 if beat=="result" and not success:
  return [_line("npc","回执我看到了。这次没送成，先把人和装置照顾好。","concerned"),_line("clerk","我会把这次的问题记下来。下一件，重新检查。","concerned")]
 if beat=="return" and not success:
  return [_line("npc","我来看看你。包裹的事慢慢来，别为了赶路把自己弄得太累。","neutral"),_line("clerk","嗯。今天会从最小的一箱开始。","warm_smile")]
 match id+"/"+beat:
  "human_courier/accept":return [_line("npc","帮我送把小勺去星港吧。朋友搬过去三天，才发现自己只带了叉子。","concerned"),_line("clerk","一把勺子，也值得单独跑一趟？","curious"),_line("npc","他早饭喝粥。已经用叉子捞了三天米粒了。","pleased")]
  "human_courier/result":return [_line("npc","他签收了，还发来一张空碗的照片。","pleased"),_line("clerk","看来这把勺子，上班第一天就很忙。","pleased")]
  "human_courier/return":return [_line("npc","他让我转告你：今天的粥，终于没凉。","pleased"),_line("clerk","那就好。下次搬家，记得先检查餐具。","warm_smile")]
  "elf_archivist/accept":return [_line("npc","这枚书签送到星港阅览室。那位管理员总把借书条夹进自己的小说。","neutral"),_line("clerk","所以大家都找不到借书条了？","curious"),_line("npc","找得到。得先听她讲完那一章。","pleased")]
  "elf_archivist/result":return [_line("npc","她说书签很合适，借书条也各就各位了。","pleased"),_line("clerk","那一章讲完了吗？","curious"),_line("npc","还没。她把下一章寄给我了。","concerned")]
  "elf_archivist/return":return [_line("npc","我看完了。原来她一直讲错了凶手。","pleased"),_line("clerk","嘘，这句可别写在包裹外面。","surprised")]
  "alien_botanist/accept":return [_line("npc","这盆幼苗要去星港窗边。见到太阳，它就会醒一会儿。","neutral"),_line("clerk","箱子上需要写什么？","curious"),_line("npc","写轻拿轻放就好。别写懒，它会不好意思。","concerned")]
  "alien_botanist/result":return [_line("npc","那边说它醒了，还朝窗户挪了半厘米。","pleased"),_line("clerk","这么小的脚程，也算顺利到家了。","warm_smile")]
  "alien_botanist/return":return [_line("npc","它现在每天替值班员看日出。今天还多长了一片叶子。","pleased"),_line("clerk","原来它也在认真上班。","pleased")]
  "robot_machinist/accept":return [_line("npc","这片旧水壶哨片，寄给星港的室友。新水壶叫得太准时了。","neutral"),_line("clerk","准时也有问题？","curious"),_line("npc","旧的会先哼两声。正好够他慢慢找杯子。","pleased")]
  "robot_machinist/result":return [_line("npc","哨片装好了。刚才他发来消息：杯子找到了。","pleased"),_line("clerk","水也开了？","curious"),_line("npc","还没有。还是熟悉的两声。","pleased")]
  "robot_machinist/return":return [_line("npc","他给我留了一个杯子。下次休息，我去星港喝茶。","pleased"),_line("clerk","这回你自己去，记得带上回程票。","warm_smile")]
 return []
