class_name Economy
extends RefCounted
## A finite working day. Contracts, dispatch commitments and settlement IDs persist.
const SAVE_VERSION:int=5
const WorkshopProfile=preload("res://scripts/workshop_profile.gd")
const PilotProfile=preload("res://scripts/pilot_profile.gd")
const AscentProfile=preload("res://scripts/pilot_ascent_profile.gd")
const ExtremeProfile=preload("res://scripts/pilot_extreme_profile.gd")
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
const PILOT_VERSIONS:Array=[PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION]
const Stories=preload("res://scripts/courier_stories.gd")
const DISPATCHES_PER_DAY:int=2
var credits:int=260
var reputation:int=0
var day:int=1
var phase:String="morning"
var jobs_today:int=0
var deliveries:int=0
var research:int=0
## Independent of battery research; bounds derive from this persisted tier.
var workshop_tier:int=0
var history:Array=[]
var designs:Dictionary={}
var inventory:Dictionary={}
var contracts:Array=[]
var active_contract_id:String=""
var settled_ids:Dictionary={}
var in_flight:Dictionary={}
var last_settlement:Dictionary={}
var last_trials:Dictionary={}
var save_error:String=""
var load_notice:String=""
## Presentation opts in explicitly. Legacy simulation fixtures remain unbound.
## Identity/progression shares the ledger's single atomic save, never a sidecar.
var story_mode:bool=false
var story_state:Dictionary={}
## Standalone legacy simulations/tests retain the old route catalog. The current
## game opts into pilot-v3 explicitly; saved older dispatches remain frozen.
var flight_mode:String="autonomous-v5"

func enable_story_mode() -> void:
 if story_state.is_empty():
  # This is the explicit new-shop boundary, never a render or reload path.
  # A private generator must not consume the physics/global random sequence.
  var cosmetics=RandomNumberGenerator.new();cosmetics.randomize()
  story_state=Stories.initial_state(cosmetics.randi_range(1,2147483646))
 story_mode=true
 ensure_contracts()
 _bind_story_contracts()

func _bind_story_contracts() -> void:
 if not story_mode or story_state.is_empty():return
 for slot in range(contracts.size()):
  var order:Dictionary=contracts[slot]
  # Even an existing binding may not rewrite a committed dispatch or receipt.
  if not str(order.get("status","")) in ["available","accepted"]:continue
  var bound:Dictionary=Stories.bind_contract(story_state,order,day,slot)
  story_state=bound.state;order=bound.contract
  if bound.actor.is_empty():continue
  if str(order.get("variant",""))=="重货件":order.cargo="加急补货 · "+str(order.cargo)
  var teaser:Dictionary=Stories.conversation_for(story_state,order,"accept")
  if not teaser.is_empty() and not teaser.lines.is_empty():order.story=str(teaser.lines[0].text)
  contracts[slot]=order

func story_actor(contract_id:String) -> Dictionary:
 var binding:Variant=story_state.get("contract_bindings",{}).get(contract_id)
 if not binding is Dictionary:return {}
 var actor:Dictionary=Stories.actor_metadata(binding)
 if not actor.is_empty():actor.contract_id=contract_id
 return actor

func story_conversation(contract_id:String,beat:String) -> Dictionary:
 var order:Dictionary={"contract_id":contract_id}
 for item in contracts:
  if str(item.get("contract_id",""))==contract_id:order=item;break
 if beat=="accept" and str(order.get("status",""))!="accepted":return {}
 # The financial ledger, not a display flag or estimate, authorizes receipts.
 if beat in ["result","return"] and not settled_ids.has(contract_id):return {}
 var conversation:Dictionary=Stories.conversation_for(story_state,order,beat)
 if conversation.is_empty():return {}
 var route_name:String=str(order.get("name",settled_ids.get(contract_id,{}).get("route","")))
 # New receipts retain their own destination after next_day clears contracts.
 # Old success-only receipts keep the original financial-ledger fallback.
 var saved_context:Dictionary=story_state.get("committed_contract_ids",{}).get(contract_id,{}).get("route_context",{})
 if (beat=="accept" or saved_context.is_empty()) and not route_name.is_empty():conversation.route_hint=route_name
 conversation.actor.contract_id=contract_id
 return conversation

func pending_story_returns() -> Array:
 var result:Array=[]
 for contract_id in story_state.get("pending_returns",[]):
  var conversation:Dictionary=story_conversation(str(contract_id),"return")
  if not conversation.is_empty():result.append(conversation)
 return result

func mark_story_seen(contract_id:String,dialogue_id:String) -> bool:
 if not dialogue_id in [contract_id+"/accept",contract_id+"/result",contract_id+"/return"]:return false
 var beat:String=dialogue_id.get_slice("/",1)
 if story_conversation(contract_id,beat).is_empty():return false
 story_state=Stories.mark_seen(story_state,contract_id,dialogue_id)
 return true

func routes() -> Array:
 var values:Array=_autonomous_routes()
 if flight_mode==PilotProfile.CONTROL_VERSION:
  for i in range(values.size()):values[i]=PilotProfile.route(values[i])
 elif flight_mode==AscentProfile.CONTROL_VERSION:
  for i in range(values.size()):values[i]=AscentProfile.route(values[i])
 elif flight_mode==ExtremeProfile.CONTROL_VERSION:
  for i in range(values.size()):values[i]=ExtremeProfile.route(values[i])
 return values

func enable_extreme_mode() -> void:
 var migrating:bool=flight_mode!=ExtremeProfile.CONTROL_VERSION
 flight_mode=ExtremeProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if str(contracts[i].get("status","")) in ["available","accepted"] and str(contracts[i].get("control_version",""))!=ExtremeProfile.CONTROL_VERSION:contracts[i]=ExtremeProfile.route(contracts[i])
 if migrating and not in_flight.is_empty():
  load_notice="在途配送保留原版规则；之后的新委托支持全功率推进、接触钻头与撞击护盾。"

func enable_ascent_mode() -> void:
 var migrating:bool=flight_mode!=AscentProfile.CONTROL_VERSION
 flight_mode=AscentProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if str(contracts[i].get("status","")) in ["available","accepted"]:contracts[i]=AscentProfile.route(contracts[i])
 if migrating and not in_flight.is_empty():
  load_notice="已保留在途配送的原版规则；后续新委托采用向上穿云的升空航线。"

func enable_pilot_mode() -> void:
 var migrating:bool=flight_mode!=PilotProfile.CONTROL_VERSION
 flight_mode=PilotProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if str(contracts[i].get("status","")) in ["available","accepted"]:contracts[i]=PilotProfile.route(contracts[i])
 if migrating and not in_flight.is_empty() and str(in_flight.get("control_version",""))!=PilotProfile.CONTROL_VERSION:
  load_notice="已保留进行中的自主版配送；本次仍按旧规则恢复。后续新配送使用可操控航线。"

func _autonomous_routes() -> Array:
 return [
  {"id":0,"name":"晨星社区","client":"林奶奶","cargo":"耐寒种子","distance":64.0,"weight":1.0,"deadline":14.0,"time_limit":42.0,"required":85.0,"reward":165,"rep":0,"risk":"碎石门 · 保持外形紧凑","story":"这一箱种子，是温室今年的第一场春天。帮我稳稳地送过去吧。","gravity":0.0,"wind":0.0,"max_delivery_speed":24.0,"delivery_radius":5.0,"hazards":[{"x":35.0,"y":-2.6,"radius":1.15,"type":"rock"},{"x":35.0,"y":2.6,"radius":1.15,"type":"rock"}]},
  {"id":1,"name":"碎石回廊","client":"阿堇","cargo":"精密轴承","distance":82.0,"weight":1.5,"deadline":16.0,"time_limit":45.0,"required":90.0,"reward":220,"rep":2,"risk":"窄缝 · 大轮廓更危险","story":"修好这颗轴承，驿站的发电机就能重新转起来。","gravity":0.0,"wind":0.0,"max_delivery_speed":25.0,"delivery_radius":5.0,"hazards":[{"x":30.0,"y":-2.0,"radius":1.2,"type":"rock"},{"x":43.0,"y":2.1,"radius":1.25,"type":"rock"},{"x":61.0,"y":-2.0,"radius":1.2,"type":"rock"}]},
  {"id":2,"name":"寂静灯塔","client":"守塔人","cargo":"信号放大器","distance":108.0,"weight":2.0,"deadline":20.0,"time_limit":52.0,"required":75.0,"reward":280,"rep":4,"risk":"信号追踪海盗 · 普通炮台","story":"灯亮起来，回家的船才看得见路。","gravity":0.0,"wind":0.0,"max_delivery_speed":26.0,"delivery_radius":5.0,"hazards":[{"x":36.0,"y":-3.2,"radius":1.0,"type":"tracker","damage":10.0},{"x":70.0,"y":3.2,"radius":1.0,"type":"turret","damage":10.0}]},
  {"id":3,"name":"引力果园","client":"米洛","cargo":"玻璃蜂巢","distance":112.0,"weight":2.4,"deadline":23.0,"time_limit":55.0,"required":90.0,"reward":340,"rep":7,"risk":"局部引力 · 高完整度要求","story":"蜜蜂睡着了。请让它们在果园醒来。","gravity":0.0,"wind":0.0,"max_delivery_speed":24.0,"delivery_radius":6.0,"hazards":[{"x":47.0,"y":3.3,"radius":2.0,"type":"gravity","strength":8.0},{"x":80.0,"y":-2.6,"radius":1.2,"type":"rock"}]},
  {"id":4,"name":"远岸邮局","client":"小满","cargo":"一百封手写信","distance":146.0,"weight":2.8,"deadline":28.0,"time_limit":65.0,"required":85.0,"reward":410,"rep":10,"risk":"长航程 · 混合危险","story":"有些话，值得有人亲手送到。","gravity":0.0,"wind":0.0,"max_delivery_speed":27.0,"delivery_radius":6.0,"hazards":[{"x":37.0,"y":-2.4,"radius":1.2,"type":"rock"},{"x":70.0,"y":3.0,"radius":1.0,"type":"tracker","damage":10.0},{"x":106.0,"y":-2.7,"radius":1.3,"type":"rock"}]}
 ]

func ensure_contracts() -> void:
 if not contracts.is_empty():return
 var available:Array=[]
 for route in routes():
  if reputation>=int(route.rep):
   # Content authoring boundary only: no existing order/snapshot passes here.
   # Rep-unlocked routes retain the frozen v3 ascent catalog and progression.
   if flight_mode==ExtremeProfile.CONTROL_VERSION and int(route.id)==0:route=GroundProfile.route(route)
   available.append(route)
 var first:Dictionary=available[(day-1)%available.size()].duplicate(true)
 first.contract_id="D%d-A"%day;first.status="available";first.accepted_day=day;first.variant="标准件"
 var second:Dictionary=available.back().duplicate(true)
 second.contract_id="D%d-B"%day;second.status="available";second.accepted_day=day
 second.weight=float(second.weight)*1.55;second.reward=int(second.reward)+55;second.deadline=float(second.deadline)+3.0
 second.cargo="加急补货 · "+str(second.cargo);second.variant="重货件"
 second.story="还有一箱加急补货。更重一些，运费也会多一些。先看看装置扛不扛得住。"
 contracts=[first,second]
 _bind_story_contracts()

func contract_by_id(id:String) -> Dictionary:
 ensure_contracts()
 for item in contracts:
  if str(item.contract_id)==id:return item
 return {}

func active_contract() -> Dictionary:
 return contract_by_id(active_contract_id) if not active_contract_id.is_empty() else {}

func available_contracts() -> Array:
 ensure_contracts()
 return contracts.filter(func(c):return str(c.status)=="available")

func accept_contract(id:String) -> Dictionary:
 ensure_contracts()
 if phase=="night":return _error("已经收工。明早再接新件。")
 if jobs_today>=DISPATCHES_PER_DAY:return _error("今天的发货席位已用完，先收工吧。")
 if not in_flight.is_empty():return _error("上一份委托仍在配送中。")
 var active=active_contract()
 if not active.is_empty() and active.status=="accepted" and str(active.contract_id)!=id:return _error("先处理柜台上已接下的那份委托。")
 var order=contract_by_id(id)
 if order.is_empty() or order.status!="available":return _error("这份委托已被处理，不能重复领取。")
 if reputation<int(order.rep):return _error("客户还没有开放这条航线。")
 order.status="accepted";order.cargo_loaded=false;active_contract_id=id;phase="day"
 return {"ok":true,"contract":order}

func is_cargo_loaded(contract_id:String="") -> bool:
 var order:Dictionary=active_contract() if contract_id.is_empty() else contract_by_id(contract_id)
 var value:Variant=order.get("cargo_loaded",false)
 return value is bool and value

func mark_cargo_loaded(contract_id:String) -> Dictionary:
 var order:Dictionary=active_contract()
 if order.is_empty() or str(order.get("contract_id",""))!=contract_id or str(order.get("status",""))!="accepted":return _error("这份货物已不在待装订单中。")
 var changed:bool=not is_cargo_loaded(contract_id)
 order.cargo_loaded=true
 return {"ok":true,"changed":changed}

func decline_available(id:String) -> Dictionary:
 var order=contract_by_id(id)
 if phase=="night" or order.is_empty() or order.status!="available":return _error("这位客户已不在等待接单。")
 order.status="declined"
 return {"ok":true,"message":"已婉拒这份委托，客户会另作安排。"}

func cancel_accepted() -> Dictionary:
 var order=active_contract()
 if order.is_empty() or order.status!="accepted":return _error("没有可以退回的待发委托。")
 order.status="cancelled";active_contract_id="";reputation=maxi(0,reputation-1)
 return {"ok":true,"message":"货物退回客户，声望 -1。"}

func begin_dispatch(design:Array,launcher:Array) -> Dictionary:
 var order=active_contract()
 if phase=="night" or order.is_empty() or order.status!="accepted":return _error("先在柜台确认一份待发委托。")
 if not in_flight.is_empty():return _error("不能重复发射同一份委托。")
 if jobs_today>=DISPATCHES_PER_DAY:return _error("今天的发货席位已用完。")
 if story_mode and not is_cargo_loaded(str(order.contract_id)):return _error("货物还没有装入飞船。请先让机器人完成装货。")
 order.status="in_flight";phase="day"
 var route=order.duplicate(true);route.variation=float(order.get("variation",1.0));route.battery_capacity_multiplier=1.0+0.15*research
 in_flight={"contract_id":order.contract_id,"design":design.duplicate(true),"launcher":launcher.duplicate(true),"route":route,"seed":day*100+int(order.id)*3+(1 if str(order.contract_id).ends_with("B") else 0),"elapsed":0.0}
 if str(route.get("control_version","")) in PILOT_VERSIONS:
  in_flight.control_version=str(route.control_version);in_flight.input_commands=[{"tick":0,"axis_q":0,"boost":false,"active":false}];in_flight.ticks=0
 else:in_flight.simulation_version="autonomous-v5"
 return {"ok":true,"snapshot":in_flight}

func trial_route() -> Dictionary:
 var order=active_contract()
 if order.is_empty():return {}
 var route=order.duplicate(true);route.variation=float(order.get("variation",1.0));route.battery_capacity_multiplier=1.0+0.15*research
 route.seed=day*100+int(order.id)*3+(1 if str(order.contract_id).ends_with("B") else 0)
 return route

static func energy_tariff(order:Dictionary) -> float:
 return clampf(float(order.get("pilot_energy_tariff",AscentProfile.ENERGY_TARIFF)),.001,.18) if str(order.get("control_version","")) in [AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION] else .18

func estimate_delivery(order:Dictionary,telemetry:Dictionary,elapsed:float,success:bool) -> Dictionary:
 var integrity:float=float(telemetry.get("integrity",0))
 if integrity<=1.0:integrity*=100.0
 var time_factor:float=clampf(float(order.deadline)/maxf(elapsed,float(order.deadline)),.35,1)
 var quality_factor:float=clampf(integrity/float(order.required),0,1)
 var income:int=int(int(order.reward)*time_factor*quality_factor) if success else 0
 var tariff:float=energy_tariff(order)
 var energy:int=int(ceil(float(telemetry.get("energy_used",0))*tariff))
 var ammo:int=int(ceil(float(telemetry.get("ammo_cost",0))))
 var repairs:int=int(ceil(float(telemetry.get("repair_cost",0))))
 var lost:int=int(ceil(float(telemetry.get("lost_cost",0))))
 return {"income":income,"energy":energy,"energy_tariff":tariff,"ammo":ammo,"repairs":repairs,"lost":lost,"profit":income-energy-ammo-repairs-lost}

func settle_contract(id:String,telemetry:Dictionary,elapsed:float,success:bool) -> Dictionary:
 if settled_ids.has(id):return {"ok":false,"duplicate":true,"message":"该委托已结算。","report":settled_ids[id]}
 var order=contract_by_id(id)
 if order.is_empty() or order.status!="in_flight":return _error("只有已正式发射的委托可以结算。")
 var integrity:float=float(telemetry.get("integrity",0.0))
 if integrity<=1.0:integrity*=100.0
 integrity=clampf(integrity,0.0,100.0)
 var quote=estimate_delivery(order,telemetry,elapsed,success)
 var base_income:int=int(order.reward)
 var income:int=int(quote.income);var energy:int=int(quote.energy);var ammo:int=int(quote.ammo);var repairs:int=int(quote.repairs);var lost:int=int(quote.lost);var profit:int=int(quote.profit)
 var timely:bool=elapsed<=float(order.deadline)
 var intact:bool=integrity>=float(order.required)
 var rep_change:int=(2 if timely and intact else 1) if success else -1
 var review:String
 if not success:review="没有等到货。下次发射前，咱们把问题找清楚吧。"
 elif not intact:review="货送到了，不过里面有破损。下次能不能更稳一些？"
 elif not timely:review="箱子完好。只是等得有些着急，下次早点到就更好了。"
 else:review="准时，包装也完整。谢谢你把这份心意送到了。"
 last_settlement={"contract_id":id,"income":income,"base_income":base_income,"income_adjustment":income-base_income,"energy":energy,"ammo":ammo,"repairs":repairs,"lost":lost,"profit":profit,"success":success,"integrity":integrity,"required":order.required,"elapsed":elapsed,"deadline":order.deadline,"reputation":rep_change,"review":review,"route":order.name,"client":order.client,"day":day,"restored":true,"replenishment":"费用含自动补件与维修，装置已恢复为发射前方案。"}
 last_settlement.energy_tariff=quote.energy_tariff
 credits+=profit;reputation=maxi(0,reputation+rep_change);jobs_today+=1
 if success:deliveries+=1
 order.status="settled";order.success=success;settled_ids[id]=last_settlement.duplicate(true)
 history.push_front(last_settlement.duplicate(true))
 if history.size()>30:history.pop_back()
 var story_advanced:bool=false
 if not story_state.is_empty() and story_state.get("contract_bindings",{}).has(id):
  # Accounting/status/unique-ID commit is complete before story advancement.
  # Success and failure both receive one receipt; neither story grants rewards.
  var committed:Dictionary=Stories.commit_settlement(story_state,order,last_settlement)
  story_state=committed.state;story_advanced=bool(committed.advanced)
 in_flight={};active_contract_id=""
 return {"ok":true,"report":last_settlement,"story_advanced":story_advanced}

func close_day() -> Dictionary:
 if not in_flight.is_empty():return _error("仍有货物在路上，暂时不能关店。")
 var active=active_contract()
 if not active.is_empty() and active.status=="accepted":return _error("柜台还有一份已接委托。先配送，或明确退回给客户。")
 phase="night"
 return {"ok":true,"message":"今天收工了，供应商送来了今晚的零件。"}

func next_day() -> Dictionary:
 if phase!="night":return _error("先收工，再开始下一天。")
 day+=1;jobs_today=0;phase="morning";contracts=[];active_contract_id="";last_trials={};ensure_contracts()
 return {"ok":true}

func buy_part(type:String,spec:Dictionary) -> Dictionary:
 if phase!="night":return _error("供应商傍晚到店。今天先用手头的零件试一试。")
 var price:int=int(spec.get("price",0))
 if price<0 or credits<price:return _error("资金不足。先考虑最能解决问题的一件。")
 credits-=price;inventory[type]=int(inventory.get(type,0))+1
 return {"ok":true}

func workshop_upgrade_cost() -> int:
 # -1 means there is no further paid tier, never a zero-cost max-tier purchase.
 return WorkshopProfile.purchase_cost(WorkshopProfile.next_tier(workshop_tier))

func workshop_upgrade(target_tier:int) -> Dictionary:
 # The UI must submit the exact tier it displayed, not an unbound "upgrade".
 # A stale/double click for tier 1 can therefore never buy tier 2 accidentally.
 if phase!="night":return _error("车间扩建需要收工后进行。")
 if not in_flight.is_empty():return _error("仍有货物在路上，暂时不能扩建车间。")
 if not WorkshopProfile.is_valid_tier(target_tier):return _error("没有这个车间扩建等级。")
 if target_tier<=workshop_tier:
  return {"ok":false,"changed":false,"duplicate":true,"tier":workshop_tier,"message":"这一档车间已经开放，无需再次购买。"}
 if workshop_tier>=WorkshopProfile.MAX_TIER:return _error("车间已经完成全部扩建。")
 if target_tier!=workshop_tier+1:return _error("请先完成前一档车间扩建。")
 var cost:int=WorkshopProfile.purchase_cost(target_tier)
 if cost<0 or credits<cost:return _error("资金不足，先保留下一单需要的周转资金。")
 var previous_tier:int=workshop_tier;var previous_credits:int=credits
 credits-=cost;workshop_tier=target_tier
 var size:Vector2i=WorkshopProfile.grid_size(workshop_tier)
 # Caller saves once, and restores these two fields if that atomic save fails.
 # No inventory, blueprint, route, story or settlement field is touched here.
 return {"ok":true,"changed":true,"tier":workshop_tier,"cost":cost,"previous_tier":previous_tier,"previous_credits":previous_credits,"message":"车间已扩建为 %d × %d 格。现有零件与图纸保持原位。"%[size.x,size.y]}

func research_cost() -> int:return 140+research*100

func research_upgrade() -> Dictionary:
 if phase!="night":return _error("校准充电台需要收工后进行。")
 if research>=3:return _error("充电台已经完成全部校准。")
 var cost:int=research_cost()
 if credits<cost:return _error("资金不足，先保留下一单需要的周转资金。")
 credits-=cost;research+=1
 return {"ok":true,"message":"充电台已校准：可用储能提高 15%。实际消耗仍照常计费。"}

func starter_stock(_design:Array,_launcher:Array) -> void:
 # New-game stock only. One extra engine replaces the old probe + delay spares;
 # the same 375-credit hardware budget now supports a compact twin-engine craft.
 inventory={"cargo":1,"beam":4,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1,"not_gate":1}
 ensure_contracts()

func missing_parts(design:Array,launcher:Array) -> Dictionary:
 var needed:Dictionary={};var missing:Dictionary={}
 for p in design+launcher:needed[str(p.type)]=int(needed.get(str(p.type),0))+1
 for type in needed:
  if int(needed[type])>int(inventory.get(type,0)):missing[type]=int(needed[type])-int(inventory.get(type,0))
 return missing

func _error(message:String) -> Dictionary:return {"ok":false,"message":message}

func _valid_save(value:Variant) -> bool:
 if not value is Dictionary:return false
 if not int(value.get("version",0)) in [1,2,3,4,SAVE_VERSION]:return false
 if int(value.version)==SAVE_VERSION:
  # A corrupt v5 tier cannot silently shrink a paid grid or unlock free space.
  # Reject the primary and let the existing validated-backup path recover it.
  var tier:Variant=value.get("workshop_tier")
  if not (tier is int or tier is float):return false
  if not is_finite(float(tier)) or float(tier)!=floor(float(tier)):return false
  if not WorkshopProfile.is_valid_tier(int(tier)):return false
 for key in ["design","launcher"]:
  if not value.get(key,null) is Array:return false
 for key in ["inventory","designs","settings","settled_ids","in_flight","last_settlement","last_trials","story_state"]:
  if value.has(key) and not value[key] is Dictionary:return false
 for key in ["history","contracts"]:
  if value.has(key) and not value[key] is Array:return false
 return true

func _read_save(path:String) -> Variant:
 var parser=JSON.new()
 if parser.parse(FileAccess.get_file_as_string(path))!=OK:return null
 return parser.data

func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
 save_error=""
 var data={"version":SAVE_VERSION,"flight_mode":flight_mode,"credits":credits,"reputation":reputation,"day":day,"phase":phase,"jobs_today":jobs_today,"deliveries":deliveries,"research":research,"workshop_tier":workshop_tier,"history":history,"designs":designs,"inventory":inventory,"contracts":contracts,"active_contract_id":active_contract_id,"settled_ids":settled_ids,"in_flight":in_flight,"last_settlement":last_settlement,"last_trials":last_trials,"story_state":story_state,"design":design,"launcher":launcher,"settings":settings}
 var file=FileAccess.open("user://savegame.tmp",FileAccess.WRITE)
 if file==null:save_error="无法创建临时存档，原存档未改变。";return false
 # Keep double-precision route/parameter values exact across deterministic
 # replay. Default JSON formatting rounds curved ascent gate coordinates.
 if not file.store_string(JSON.stringify(data,"",true,true)):file.close();save_error="写入存档失败，原存档未改变。";return false
 file.flush();file.close()
 if not _valid_save(_read_save("user://savegame.tmp")):save_error="临时存档校验失败。";return false
 if FileAccess.file_exists("user://savegame.json"):
  var old=_read_save("user://savegame.json")
  if _valid_save(old):DirAccess.copy_absolute("user://savegame.json","user://savegame.backup.json")
 var result=DirAccess.rename_absolute("user://savegame.tmp","user://savegame.json")
 if result!=OK:save_error="替换存档失败；原存档与备份仍保留。";return false
 return true

func load_state() -> Dictionary:
 load_notice="";var parsed:Dictionary={}
 for path in ["user://savegame.json","user://savegame.backup.json"]:
  if not FileAccess.file_exists(path):continue
  var parser=JSON.new()
  if parser.parse(FileAccess.get_file_as_string(path))!=OK:continue
  var value=parser.data
  if _valid_save(value):
   parsed=value
   if path.ends_with("backup.json"):load_notice="主存档损坏，已恢复上一份有效备份。"
   break
 if parsed.is_empty():return {}
 # Versions 1..4 predate paid expansion. Preserve their designs verbatim and
 # start at the original tier. Loading alone never rewrites the player's file.
 workshop_tier=int(parsed.workshop_tier) if int(parsed.version)==SAVE_VERSION else 0
 story_mode=false
 if parsed.get("story_state",{}).is_empty():
  # v1-v3 (and story-disabled fixtures) get a reproducible migration seed.
  # Reloading the same old file cannot reroll appearances, award old receipts,
  # or rewrite its dispatch. Binding waits for explicit enable_story_mode().
  story_state=Stories.initial_state(Stories.stable_seed("legacy-shop/"+JSON.stringify(parsed,"",true,true)))
 else:story_state=Stories.normalize_state(parsed.story_state)
 flight_mode=str(parsed.get("flight_mode","autonomous-v5"))
 credits=int(parsed.get("credits",260));reputation=maxi(0,int(parsed.get("reputation",0)));day=maxi(1,int(parsed.get("day",1)));jobs_today=clampi(int(parsed.get("jobs_today",0)),0,DISPATCHES_PER_DAY);deliveries=maxi(0,int(parsed.get("deliveries",0)));research=clampi(int(parsed.get("research",0)),0,3)
 history=parsed.get("history",[]);designs=parsed.get("designs",{});inventory=parsed.get("inventory",{})
 if int(parsed.version)==1:
  phase="morning";contracts=[];jobs_today=0;load_notice="已保留原有方案与库存，可以开始新一天的营业。"
 else:
  phase=str(parsed.get("phase","morning"));contracts=parsed.get("contracts",[]);active_contract_id=str(parsed.get("active_contract_id",""));settled_ids=parsed.get("settled_ids",{});in_flight=parsed.get("in_flight",{});last_settlement=parsed.get("last_settlement",{});last_trials=parsed.get("last_trials",{})
  if not phase in ["morning","day","night"]:phase="morning"
 ensure_contracts()
 return parsed
