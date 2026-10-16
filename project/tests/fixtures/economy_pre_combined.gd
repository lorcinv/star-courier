extends RefCounted
## A finite working day. Contracts, dispatch commitments and settlement IDs persist.
const SAVE_VERSION:int=5
const SeededOffers=preload("res://scripts/seeded_offer_catalog.gd")
const SeededGuard=preload("res://scripts/seeded_offer_guard.gd")
const AuthoringPolicy=preload("res://scripts/protected_bird_authoring_policy.gd")
const BirdOffer=preload("res://scripts/protected_bird_offer_v1.gd")
const BirdProfile=preload("res://scripts/pilot_protected_bird_profile.gd")
const BirdSettlement=preload("res://scripts/protected_bird_settlement_v1.gd")
const MeteorOffers=preload("res://scripts/orbital_meteor_offers.gd")
const WorkshopProfile=preload("res://scripts/workshop_profile.gd")
const PilotProfile=preload("res://scripts/pilot_profile.gd")
const AscentProfile=preload("res://scripts/pilot_ascent_profile.gd")
const ExtremeProfile=preload("res://scripts/pilot_extreme_profile.gd")
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
const MoonProfile=preload("res://scripts/pilot_moon_profile.gd")
const WormholeProfile=preload("res://scripts/pilot_wormhole_profile.gd")
const PILOT_VERSIONS:Array=[PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION]
const Stories=preload("res://scripts/courier_stories.gd")
const Reviews=preload("res://scripts/customer_reviews_v2.gd")
const DISPATCHES_PER_DAY:int=2
const WORMHOLE_ROUTE_ID:int=3
const WORMHOLE_REPUTATION:int=7
const MOON_ROUTE_ID:int=4
const MOON_REPUTATION:int=10
const MOON_FIRST_DAY:int=4
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
## Null only before new-shop/legacy initialization; saved states are validated.
var review_state:Variant=null
var review_load_blocked:bool=false
## Standalone legacy simulations/tests retain the old route catalog. The current
## game opts into pilot-v3 explicitly; saved older dispatches remain frozen.
var flight_mode:String="autonomous-v5"
## Versioned content authoring; existing offers remain immutable on enable/load.
var offer_generation_state:Dictionary={}

func enable_seeded_offers(explicit_seed:Variant) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var raw:Dictionary={}
 if not offer_generation_state.is_empty():raw.offer_generation_state=offer_generation_state
 var initialized:Dictionary=SeededOffers.initialize_save(raw,explicit_seed)
 if not initialized.ok:return initialized
 offer_generation_state=initialized.save.offer_generation_state
 # No ensure_contracts() here: existing offers, even available ones, stay exact.
 return {"ok":true,"changed":initialized.changed}

func _new_seeded_offer(catalog:Dictionary,slot:int) -> Dictionary:
 if offer_generation_state.is_empty():return {}
 var kind:String="ground" if int(catalog.id)==0 else "ascent"
 if not int(catalog.id) in [0,1,2]:return {} # Moon/wormhole are not rewritten.
 var actor_id:String=Stories.IDS[posmod((day-1)*2+slot,Stories.IDS.size())]
 var fresh:Dictionary=_autonomous_routes()[int(catalog.id)]
 return AuthoringPolicy.author(catalog,fresh,offer_generation_state,day,slot,kind,actor_id)

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
  if not route_validation_error(order).is_empty():continue
  # Future content is an opaque committed snapshot, including its customer,
  # parcel and saved copy. Current story templates cannot rebind that identity.
  if _opaque_generated_offer(order):continue
  var bound:Dictionary=Stories.bind_contract(story_state,order,day,slot)
  story_state=bound.state;order=bound.contract
  if bound.actor.is_empty():continue
  if str(order.get("variant",""))=="重货件":order.cargo="加急补货 · "+str(order.cargo)
  var teaser:Dictionary=Stories.conversation_for(story_state,order,"accept")
  if not teaser.is_empty():teaser=_with_saved_opening(order,teaser)
  if not teaser.is_empty() and not teaser.lines.is_empty():order.story=str(teaser.lines[0].text)
  contracts[slot]=order

static func _opaque_generated_offer(order:Dictionary) -> bool:
 var metadata:Variant=order.get("generation")
 return metadata is Dictionary and not AuthoringPolicy.known_offer(str(metadata.get("version","")))

static func _review_order(order:Dictionary) -> Dictionary:
 # Review-only projection shared by new receipts and old saved validation.
 # Opaque generated identity stays untouched in the actual contract/ledger.
 if not _opaque_generated_offer(order):return order
 var projected:Dictionary=order.duplicate(true);projected.appearance_id=""
 return projected

func story_actor(contract_id:String) -> Dictionary:
 for order in contracts:
  if str(order.get("contract_id",""))==contract_id and _opaque_generated_offer(order):return {}
 var binding:Variant=story_state.get("contract_bindings",{}).get(contract_id)
 if not binding is Dictionary:return {}
 var actor:Dictionary=Stories.actor_metadata(binding)
 if not actor.is_empty():actor.contract_id=contract_id
 return actor

func story_conversation(contract_id:String,beat:String) -> Dictionary:
 var order:Dictionary={"contract_id":contract_id}
 for item in contracts:
  if str(item.get("contract_id",""))==contract_id:order=item;break
 if _opaque_generated_offer(order):return {} # No current arc is guessed for future identity.
 if beat=="accept" and str(order.get("status",""))!="accepted":return {}
 # The financial ledger, not a display flag or estimate, authorizes receipts.
 if beat in ["result","return"] and not settled_ids.has(contract_id):return {}
 var conversation:Dictionary=Stories.conversation_for(story_state,order,beat)
 if conversation.is_empty():return {}
 if beat=="accept":conversation=_with_saved_opening(order,conversation)
 var route_name:String=str(order.get("name",settled_ids.get(contract_id,{}).get("route","")))
 # New receipts retain their own destination after next_day clears contracts.
 # Old success-only receipts keep the original financial-ledger fallback.
 var saved_context:Dictionary=story_state.get("committed_contract_ids",{}).get(contract_id,{}).get("route_context",{})
 if (beat=="accept" or saved_context.is_empty()) and not route_name.is_empty():conversation.route_hint=route_name
 conversation.actor.contract_id=contract_id
 return conversation

func _with_saved_opening(order:Dictionary,conversation:Dictionary) -> Dictionary:
 # No reroll, template lookup or RNG at dialogue time. Unknown content versions
 # keep their existing story instead of being interpreted as this version.
 var metadata:Variant=order.get("generation")
 if not metadata is Dictionary or not AuthoringPolicy.known_offer(str(metadata.get("version",""))):return conversation
 if not route_validation_error(order).is_empty():return conversation
 var saved:Dictionary=metadata.dialogue
 if str(conversation.get("actor",{}).get("appearance_id",""))!=str(saved.appearance_id):return conversation
 var result:Dictionary=conversation.duplicate(true)
 result.lines.push_front(saved.accept_lines[0].duplicate(true))
 return result

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

static func route_validation_error(route:Dictionary) -> String:
 if BirdOffer.has_markers(route):
  return "" if BirdOffer.validation_error(route).is_empty() else "这份航线记录不完整，暂时无法出发。"
 var generated_error:String=MeteorOffers.validation_error(route) if MeteorOffers.has_markers(route) else SeededGuard.saved_metadata_error(route)
 if not generated_error.is_empty():return "这份航线记录不完整，暂时无法出发。"
 # Inspect explicit identity only. Never reauthor or guess from names/geometry.
 for key in ["control_version","pilot_profile","mode","route_profile","route_kind","destination_id"]:
  if route.has(key) and not route[key] is String:return "航线记录不完整，暂时无法出发。"
 var version:String=str(route.get("control_version",""))
 if not version in ([""]+PILOT_VERSIONS):return "这份航线使用了暂不支持的驾驶规则。"
 if str(route.get("mode",""))=="pilot" and version.is_empty():return "航线缺少驾驶规则，暂时无法出发。"
 if route.has("pilot_profile") and str(route.pilot_profile)!=version:return "航线的驾驶规则不一致，暂时无法出发。"
 # New Moon identity is content, not a new solver. Any partial marker must
 # validate before the v4 branch so mixed Moon/portal saves cannot slip through.
 if MoonProfile.has_moon_markers(route):return MoonProfile.validation_error(route)
 # Older known protocols keep their established route and replay semantics.
 # Portal markers on an older protocol cannot silently become a paid v4 trip.
 if version==WormholeProfile.CONTROL_VERSION:return WormholeProfile.validation_error(route)
 if str(route.get("route_profile",""))==WormholeProfile.ROUTE_PROFILE or route.has("wormhole_portal") or route.has("wormhole_schema"):
  return "虫洞航线的驾驶规则不一致，暂时无法出发。"
 return ""

func _can_upgrade_available(order:Dictionary) -> bool:
 # Available old offers keep the established migration policy. Acceptance is
 # the route commitment boundary, including before a first formal launch.
 if str(order.get("status",""))!="available" or order.has("generation"):return false
 if not route_validation_error(order).is_empty():return false
 return str(order.get("control_version",""))!=WormholeProfile.CONTROL_VERSION and not MoonProfile.has_moon_markers(order)

func enable_extreme_mode() -> void:
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):
  load_notice="存档的驾驶规则暂不受支持，原航线已保留。";return
 var migrating:bool=flight_mode!=ExtremeProfile.CONTROL_VERSION
 # v3 stays the workshop/default authoring mode; v4 belongs to its own routes.
 flight_mode=ExtremeProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if _can_upgrade_available(contracts[i]) and str(contracts[i].get("control_version",""))!=ExtremeProfile.CONTROL_VERSION:contracts[i]=ExtremeProfile.route(contracts[i])
 if migrating and not in_flight.is_empty():
  load_notice="在途配送保留原版规则；之后的新委托支持全功率推进、接触钻头与撞击护盾。"

func enable_ascent_mode() -> void:
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return
 var migrating:bool=flight_mode!=AscentProfile.CONTROL_VERSION
 flight_mode=AscentProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if _can_upgrade_available(contracts[i]):contracts[i]=AscentProfile.route(contracts[i])
 if migrating and not in_flight.is_empty():
  load_notice="已保留在途配送的原版规则；后续新委托采用向上穿云的升空航线。"

func enable_pilot_mode() -> void:
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return
 var migrating:bool=flight_mode!=PilotProfile.CONTROL_VERSION
 flight_mode=PilotProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if _can_upgrade_available(contracts[i]):contracts[i]=PilotProfile.route(contracts[i])
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
 if not contracts.is_empty() or not in_flight.is_empty():return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return
 if not offer_generation_state.is_empty() and not AuthoringPolicy.supported_root(offer_generation_state):
  load_notice="今日航线暂时无法整理，原进度已保留。请使用对应版本继续。";return
 var available:Array=[]
 for route in routes():
  if reputation>=int(route.rep):
   # Content authoring boundary only: no existing order/snapshot passes here.
   # Only newly authored rep-7 offers open the otherworld lane. Existing
   # available, accepted, in-flight and settled orders never pass this boundary.
   if flight_mode==ExtremeProfile.CONTROL_VERSION:
    if int(route.id)==0:route=GroundProfile.route(route)
    elif int(route.id)==WORMHOLE_ROUTE_ID and reputation>=WORMHOLE_REPUTATION:route=WormholeProfile.route(route)
    elif int(route.id)==MOON_ROUTE_ID and day>=MOON_FIRST_DAY and reputation>=MOON_REPUTATION:route=MoonProfile.route(route)
   available.append(route)
 var first:Dictionary=available[(day-1)%available.size()].duplicate(true)
 var second:Dictionary=available.back().duplicate(true)
 # Generate only at this already-existing empty-contract authoring boundary.
 # The explicit seed and both realized snapshots must be atomically saved by
 # the normal controller before presentation. Enabling never rerolls today.
 var generated_first:Dictionary=_new_seeded_offer(first,0) if flight_mode==ExtremeProfile.CONTROL_VERSION else {}
 var generated_second:Dictionary=_new_seeded_offer(second,1) if flight_mode==ExtremeProfile.CONTROL_VERSION else {}
 for outcome in [generated_first,generated_second]:
  if not outcome.is_empty() and not outcome.ok:
   load_notice="今日航线暂时无法整理，原进度已保留。请使用对应版本继续。";return # no reroll or silent new seed
 first.contract_id="D%d-A"%day;first.status="available";first.accepted_day=day;first.variant="标准件"
 second.contract_id="D%d-B"%day;second.status="available";second.accepted_day=day
 second.weight=float(second.weight)*1.55;second.reward=int(second.reward)+55;second.deadline=float(second.deadline)+3.0
 # Canonicalize only new explicit v4/Moon cargo at its creation boundary.
 # Multiplication can carry a low ULP that JSON normalizes on reload. Existing
 # orders never pass here and retain their saved commercial numbers verbatim.
 if str(second.get("control_version",""))==WormholeProfile.CONTROL_VERSION or MoonProfile.is_moon_route(second):second.weight=float("%.2f"%float(second.weight))
 second.cargo="加急补货 · "+str(second.cargo);second.variant="重货件"
 second.story="还有一箱加急补货。更重一些，运费也会多一些。先看看装置扛不扛得住。"
 if not generated_first.is_empty():first=generated_first.offer
 if not generated_second.is_empty():second=generated_second.offer
 if flight_mode==ExtremeProfile.CONTROL_VERSION and AuthoringPolicy.selects_bird(offer_generation_state,day,reputation,first):
  var bird:Dictionary=BirdOffer.create_new_offer(offer_generation_state,day,Stories.IDS[posmod((day-1)*2,Stories.IDS.size())])
  if not bird.ok:load_notice="保护区委托记录不完整，原进度已保留。";return
  first=bird.offer
  offer_generation_state=offer_generation_state.duplicate(true);offer_generation_state.introduced_day=day
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
 if order.is_empty():return _error("这份委托已被处理，不能重复领取。")
 var route_error:String=route_validation_error(order)
 if not route_error.is_empty():return _error(route_error)
 if str(order.get("status",""))!="available":return _error("这份委托已被处理，不能重复领取。")
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
 if review_load_blocked:return _error(load_notice)
 var order=active_contract()
 if order.is_empty() or order.status!="accepted":return _error("没有可以退回的待发委托。")
 order.status="cancelled";active_contract_id="";reputation=maxi(0,reputation-1)
 return {"ok":true,"message":"货物退回客户，声望 -1。"}

func begin_dispatch(design:Array,launcher:Array) -> Dictionary:
 var order=active_contract()
 if phase=="night" or order.is_empty() or order.status!="accepted":return _error("先在柜台确认一份待发委托。")
 var route_error:String=route_validation_error(order)
 if not route_error.is_empty():return _error(route_error)
 if not in_flight.is_empty():return _error("不能重复发射同一份委托。")
 if jobs_today>=DISPATCHES_PER_DAY:return _error("今天的发货席位已用完。")
 if story_mode and not is_cargo_loaded(str(order.contract_id)):return _error("货物还没有装入飞船。请先让机器人完成装货。")
 order.status="in_flight";phase="day"
 var route=order.duplicate(true);route.variation=float(order.get("variation",1.0));route.battery_capacity_multiplier=1.0+0.15*research
 in_flight={"contract_id":order.contract_id,"design":design.duplicate(true),"launcher":launcher.duplicate(true),"route":route,"seed":day*100+int(order.id)*3+(1 if str(order.contract_id).ends_with("B") else 0),"elapsed":0.0}
 if BirdOffer.has_markers(route):in_flight.seed=int(route.seed)
 if str(route.get("control_version","")) in PILOT_VERSIONS:
  in_flight.control_version=str(route.control_version);in_flight.input_commands=[{"tick":0,"axis_q":0,"boost":false,"active":false}];in_flight.ticks=0
 else:in_flight.simulation_version="autonomous-v5"
 return {"ok":true,"snapshot":in_flight}

func trial_route() -> Dictionary:
 var order=active_contract()
 if order.is_empty() or not route_validation_error(order).is_empty():return {}
 var route=order.duplicate(true);route.variation=float(order.get("variation",1.0));route.battery_capacity_multiplier=1.0+0.15*research
 route.seed=int(order.seed) if BirdOffer.has_markers(order) else day*100+int(order.id)*3+(1 if str(order.contract_id).ends_with("B") else 0)
 return route

static func energy_tariff(order:Dictionary) -> float:
 return clampf(float(order.get("pilot_energy_tariff",AscentProfile.ENERGY_TARIFF)),.001,.18) if str(order.get("control_version","")) in [AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION] else .18

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
 var quote:Dictionary={"income":income,"energy":energy,"energy_tariff":tariff,"ammo":ammo,"repairs":repairs,"lost":lost,"profit":income-energy-ammo-repairs-lost}
 if str(order.get("control_version","")) in [WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION]:
  # The simulator already includes station draw in energy_used. These fields
  # explain that same bill; do not add or separately round a second charge.
  quote.energy_j=float(telemetry.get("energy_used",0.0))
  quote.wormhole_energy_j=float(telemetry.get("wormhole_energy_used",0.0))
  quote.wormhole_transits=int(telemetry.get("wormhole_transits",0))
  quote.wormhole_station_remaining=float(telemetry.get("wormhole_station_remaining",order.get("wormhole_portal",{}).get("station_energy_j",0.0)))
 return quote

func settle_contract(id:String,telemetry:Dictionary,elapsed:float,success:bool,completion:Dictionary={}) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if settled_ids.has(id):return {"ok":false,"duplicate":true,"message":"该委托已结算。","report":settled_ids[id]}
 var order=contract_by_id(id)
 if order.is_empty() or order.status!="in_flight":return _error("只有已正式发射的委托可以结算。")
 var route_error:String=route_validation_error(order)
 if not route_error.is_empty():return _error(route_error)
 var bird_capture:Dictionary={}
 if BirdOffer.has_markers(order):
  bird_capture=BirdSettlement.capture(order,in_flight,telemetry,elapsed,success,completion)
  if not bird_capture.ok:
   var rejected:Dictionary=_error("这次配送暂时无法结算，记录已保留。")
   rejected.diagnostic_error=bird_capture.error
   return rejected
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
 if str(order.get("control_version","")) in [WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION]:
  for key in ["energy_j","wormhole_energy_j","wormhole_transits","wormhole_station_remaining"]:last_settlement[key]=quote[key]
  last_settlement.control_version=str(order.control_version)
  last_settlement.route_context={"route_profile":order.route_profile,"route_name":order.name,"destination_name":order.destination_name}
 if MoonProfile.is_moon_route(order):
  # Receipt copy identifies the actual destination after next_day removes offers.
  # Energy was already billed once by estimate_delivery; Moon adds no fee/reward.
  last_settlement.control_version=str(order.control_version)
  last_settlement.route_context={"route_profile":order.route_profile,"route_kind":order.route_kind,"destination_id":order.destination_id,"route_name":order.name,"destination_name":order.destination_name}
 if not bird_capture.is_empty():
  last_settlement.wildlife_evidence=bird_capture.evidence
  last_settlement.erase("review") # This version stores facts now; customer copy is authored next morning.
 credits+=profit;reputation=maxi(0,reputation+rep_change);jobs_today+=1
 if success:deliveries+=1
 order.status="settled";order.success=success
 # New receipts retain review-only destination/appearance evidence even after
 # contracts are cleared. This does not reinterpret older missing evidence.
 var review_order:Dictionary=_review_order(order)
 last_settlement.review_context={"version":Reviews.VERSION,"destination_name":review_order.get("destination_name",order.name),"appearance_id":review_order.get("appearance_id","")}
 settled_ids[id]=last_settlement.duplicate(true)
 history.push_front(last_settlement.duplicate(true))
 if history.size()>30:history.pop_back()
 var story_advanced:bool=false
 if not _opaque_generated_offer(order) and not story_state.is_empty() and story_state.get("contract_bindings",{}).has(id):
  # Accounting/status/unique-ID commit is complete before story advancement.
  # Success and failure both receive one receipt; neither story grants rewards.
  var committed:Dictionary=Stories.commit_settlement(story_state,order,last_settlement)
  story_state=committed.state;story_advanced=bool(committed.advanced)
 # Only the authoritative unique formal receipt can create pending facts.
 # Future content keeps its own client/parcel/appearance snapshot. Reviews
 # can still report the real outcome with generic wording, without pretending
 # an unknown identity belongs to one of our current recurring characters.
 var review_capture:Dictionary=Reviews.capture_settlement(review_state,review_order,settled_ids,day)
 if review_capture.ok:review_state=review_capture.state
 else:load_notice="这份客户留言未能记录，配送账单已保留。"
 in_flight={};active_contract_id=""
 # Direct, unsaved legacy callers retain accounting semantics but must inspect
 # this explicit outcome. The player-facing transactional API below is strict.
 return {"ok":true,"report":last_settlement,"story_advanced":story_advanced,"review_pending":bool(review_capture.ok),"review_error":str(review_capture.get("reason",""))}

func settle_contract_and_save(id:String,telemetry:Dictionary,elapsed:float,success:bool,design:Array,launcher:Array,settings:Dictionary,completion:Dictionary={}) -> Dictionary:
 var previous:Dictionary={}
 for key in ["credits","reputation","jobs_today","deliveries","contracts","settled_ids","history","last_settlement","story_state","review_state","in_flight","active_contract_id","load_notice"]:
  var value:Variant=get(key)
  previous[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 var result:Dictionary=settle_contract(id,telemetry,elapsed,success,completion)
 if not result.ok:
  for key in previous:set(key,previous[key])
  return result
 if not bool(result.get("review_pending",false)):
  for key in previous:set(key,previous[key])
  return _error("结算记录不完整，本次尚未保存。请重试或重新载入存档。")
 if save_state(design,launcher,settings):return result
 for key in previous:set(key,previous[key])
 return _error(save_error)

func close_day() -> Dictionary:
 if not in_flight.is_empty():return _error("仍有货物在路上，暂时不能关店。")
 var active=active_contract()
 if not active.is_empty() and active.status=="accepted":return _error("柜台还有一份已接委托。先配送，或明确退回给客户。")
 phase="night"
 return {"ok":true,"message":"今天收工了，供应商送来了今晚的零件。"}

func next_day() -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if phase!="night":return _error("先收工，再开始下一天。")
 var publication:Dictionary=Reviews.publish_next_day(review_state,day,day+1)
 if not publication.ok:return _error("客户留言记录不完整，请重新载入有效存档。")
 var previous:Dictionary={"day":day,"jobs_today":jobs_today,"phase":phase,"contracts":contracts.duplicate(true),"active_contract_id":active_contract_id,"last_trials":last_trials.duplicate(true),"story_state":story_state.duplicate(true),"offer_generation_state":offer_generation_state.duplicate(true),"load_notice":load_notice}
 if not offer_generation_state.is_empty():
  var transition:Dictionary=AuthoringPolicy.next_day_root(offer_generation_state,day+1)
  if not transition.ok:return _error("今日航线使用了暂不支持的版本，原进度已保留。")
  offer_generation_state=transition.state
 day+=1;jobs_today=0;phase="morning";contracts=[];active_contract_id="";last_trials={};ensure_contracts()
 if not offer_generation_state.is_empty() and contracts.size()!=DISPATCHES_PER_DAY:
  var message:String=load_notice if not load_notice.is_empty() else "今日航线暂时无法整理，原进度已保留。"
  for key in previous:set(key,previous[key])
  return _error(message)
 # Publication follows successful offer authoring. The saved wrapper below
 # rolls both sides back if this candidate morning cannot be persisted.
 review_state=publication.state
 return {"ok":true,"published_reviews":publication.published_count}

func next_day_and_save(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 # No UI/render/signal observes the candidate morning until the atomic save.
 var previous:Dictionary={}
 for key in ["day","jobs_today","phase","contracts","active_contract_id","last_trials","story_state","review_state","offer_generation_state","load_notice"]:
  var value:Variant=get(key)
  previous[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 var result:Dictionary=next_day()
 if not result.ok:
  for key in previous:set(key,previous[key])
  return result
 if save_state(design,launcher,settings):return result
 for key in previous:set(key,previous[key])
 return _error(save_error)

func customer_reviews() -> Array:
 if review_load_blocked:return []
 return Reviews.visible_reviews(review_state,day)

func buy_part(type:String,spec:Dictionary) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if phase!="night":return _error("供应商傍晚到店。今天先用手头的零件试一试。")
 var price:int=int(spec.get("price",0))
 if price<0 or credits<price:return _error("资金不足。先考虑最能解决问题的一件。")
 credits-=price;inventory[type]=int(inventory.get(type,0))+1
 return {"ok":true}

func workshop_upgrade_cost() -> int:
 # -1 means there is no further paid tier, never a zero-cost max-tier purchase.
 return WorkshopProfile.purchase_cost(WorkshopProfile.next_tier(workshop_tier))

func workshop_upgrade(target_tier:int) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
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
 if review_load_blocked:return _error(load_notice)
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

# Replay protocol identity is inspected before interpreting its payload. Unknown
# future records stay opaque; they are loaded only into recovery, never treated
# as corrupt legacy data in order to fall back to an older playable snapshot.
static func replay_protocol_error(snapshot:Dictionary) -> String:
 if snapshot.is_empty():return ""
 if not snapshot.get("route") is Dictionary:return "配送存档不完整，无法继续。原始记录已保留。"
 var route:Dictionary=snapshot.route
 for key in ["control_version","simulation_version"]:
  if snapshot.has(key) and not snapshot[key] is String:return "此配送存档暂时无法继续。原始记录已保留，请勿覆盖。"
 for key in ["control_version","mode"]:
  if route.has(key) and not route[key] is String:return "此配送存档暂时无法继续。原始记录已保留，请勿覆盖。"
 var control_version:String=snapshot.get("control_version",route.get("control_version",""))
 var route_version:String=route.get("control_version","")
 var simulation_version:String=snapshot.get("simulation_version","")
 var conflict:bool=(not route_version.is_empty() and snapshot.has("control_version") and route_version!=control_version) or (simulation_version=="autonomous-v5" and control_version in PILOT_VERSIONS) or (simulation_version in PILOT_VERSIONS and simulation_version!=control_version) or (route.get("mode","")=="pilot" and control_version.is_empty())
 if conflict or not control_version in ([""]+PILOT_VERSIONS) or not route_version in ([""]+PILOT_VERSIONS) or not simulation_version in (["","autonomous-v5"]+PILOT_VERSIONS):
  return "此配送存档暂时无法继续。原始记录已保留，请勿覆盖。"
 return ""

static func replay_seed_error(snapshot:Dictionary) -> String:
 # All supported legacy formats share the signed deterministic seed. Absence
 # retains the established day*100 default, but explicit null is not absence.
 # Keep the interoperable JSON-safe integer range +/- (2^53 - 1).
 # Convert integer bounds explicitly: decimal float literals lose a unit here.
 if not snapshot.has("seed"):return ""
 var seed_value:Variant=snapshot.seed
 if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or float(seed_value)!=floor(float(seed_value)) or float(seed_value)<float(-9007199254740991) or float(seed_value)>float(9007199254740991):
  return "配送存档损坏，无法继续。原始记录已保留。"
 return ""

func _valid_save(value:Variant,check_integrity:bool=true) -> bool:
 if not value is Dictionary:return false
 var raw_version:Variant=value.get("version")
 if not (raw_version is int or raw_version is float):return false
 if not is_finite(float(raw_version)) or float(raw_version)!=floor(float(raw_version)):return false
 if float(raw_version)<1.0 or float(raw_version)>float(SAVE_VERSION):return false
 if int(value.version)==SAVE_VERSION:
  # A corrupt v5 tier cannot silently shrink a paid grid or unlock free space.
  # Reject the primary and let the existing validated-backup path recover it.
  var tier:Variant=value.get("workshop_tier")
  if not (tier is int or tier is float):return false
  if not is_finite(float(tier)) or float(tier)!=floor(float(tier)):return false
  if not WorkshopProfile.is_valid_tier(int(tier)):return false
 if check_integrity and value.has("review_state"):
  if not Reviews._integer(value.get("day"),1,Reviews.MAX_DAY):return false
  if not value.review_state is Dictionary:return false
  var normalized:Dictionary=Reviews.normalize_state(value.review_state,int(value.get("day",0)))
  if not normalized.ok or not value.get("settled_ids",{}) is Dictionary or not value.get("contracts",[]) is Array:return false
  var review_contracts:Array=[]
  for saved_order in value.get("contracts",[]):
   review_contracts.append(_review_order(saved_order) if saved_order is Dictionary else saved_order)
  if not Reviews.ledger_validation_error(normalized.state,value.get("settled_ids",{}),review_contracts).is_empty():return false
 # Validate original identity bytes BEFORE normalize_state can substitute 0
 # or truncate a fractional seed. A valid backup must win over corrupt identity.
 # Entirely absent/empty pre-story state retains the deterministic legacy path.
 if value.get("story_state") is Dictionary and not value.story_state.is_empty():
  if not SeededGuard.integer_in(value.story_state.get("world_seed"),0,SeededOffers.MAX_SEED):return false
 if value.has("offer_generation_state") and not SeededGuard.seed_state_error(value.offer_generation_state).is_empty():return false
 if value.get("offer_generation_state") is Dictionary and value.offer_generation_state.get("version")==AuthoringPolicy.VERSION and not AuthoringPolicy.supported_root(value.offer_generation_state):return false
 var offer_settings:Variant=value.get("settings",{})
 if offer_settings is Dictionary and offer_settings.has("offer_generation_schema"):
  if not Reviews._integer(offer_settings.offer_generation_schema,1,1) or not value.has("offer_generation_state"):return false
 # An authored snapshot without its shop seed must never be silently enabled
 # with a replacement seed after an older writer dropped the root field.
 var saved_offers:Array=value.get("contracts",[]).duplicate() if value.get("contracts") is Array else []
 if value.get("in_flight") is Dictionary and value.in_flight.get("route") is Dictionary:saved_offers.append(value.in_flight.route)
 for saved in saved_offers:
  if not saved is Dictionary:continue
  if MeteorOffers.has_markers(saved) and not MeteorOffers.validation_error(saved).is_empty():return false
  if BirdOffer.has_markers(saved) and not BirdOffer.validation_error(saved).is_empty():return false
  if BirdOffer.has_markers(saved) and (not value.get("offer_generation_state") is Dictionary or not Reviews._integer(value.offer_generation_state.get("introduced_day"),int(saved.accepted_day),int(saved.accepted_day))):return false
  if not saved.has("generation"):continue
  if not value.has("offer_generation_state"):return false
  var metadata:Variant=saved.generation
  if metadata is Dictionary and AuthoringPolicy.known_offer(str(metadata.get("version",""))):
   if metadata.get("world_seed")!=value.offer_generation_state.world_seed:return false
 # A reviewed older writer can retain this setting while dropping/downgrading
 # the root. Detect that exact inconsistency in the existing save subsystem.
 if offer_settings is Dictionary and offer_settings.has("offer_authoring_policy"):
  if not offer_settings.offer_authoring_policy is String or not value.has("offer_generation_state") or offer_settings.offer_authoring_policy!=value.offer_generation_state.version:return false
 var review_settings:Variant=value.get("settings",{})
 if check_integrity and review_settings is Dictionary and review_settings.has("customer_reviews_schema"):
  if not value.has("review_state") or not Reviews._integer(review_settings.customer_reviews_schema,Reviews.schema_version(value.review_state),Reviews.schema_version(value.review_state)):return false
 for key in ["design","launcher"]:
  if not value.get(key,null) is Array:return false
 for key in ["inventory","designs","settings","settled_ids","in_flight","last_settlement","last_trials","story_state"]:
  if value.has(key) and not value[key] is Dictionary:return false
 for key in ["history","contracts"]:
  if value.has(key) and not value[key] is Array:return false
 if check_integrity:
  if not Reviews.opaque_error(value).is_empty():return false
  if review_settings is Dictionary and review_settings.has("protected_bird_schema"):
   if not Reviews._integer(review_settings.protected_bird_schema,1,1) or not value.has("offer_generation_state") or value.offer_generation_state.get("version")!=AuthoringPolicy.VERSION:return false
  for receipt in value.get("settled_ids",{}).values():
   if receipt is Dictionary and (receipt.has("wildlife_evidence") or receipt.get("control_version")==BirdProfile.CONTROL_VERSION):
    if not BirdSettlement.receipt_validation_error(receipt).is_empty():return false
    var identity:Dictionary=receipt.wildlife_evidence.dispatch_identity
    if not value.get("offer_generation_state") is Dictionary or not Reviews._integer(value.offer_generation_state.get("introduced_day"),int(identity.delivery_day),int(identity.delivery_day)):return false
    if not BirdProfile.same_value(receipt.wildlife_evidence.seed,BirdOffer.derived_seed(int(value.offer_generation_state.world_seed),int(identity.delivery_day))):return false
 var snapshot:Dictionary=value.get("in_flight",{})
 if check_integrity and replay_protocol_error(snapshot).is_empty() and not replay_seed_error(snapshot).is_empty():return false
 return true

func _read_save(path:String) -> Variant:
 var parser=JSON.new()
 if parser.parse(FileAccess.get_file_as_string(path))!=OK:return null
 return parser.data

func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
 save_error=""
 if review_load_blocked:save_error=load_notice;return false
 var reviews:Dictionary=Reviews.normalize_state(review_state,day)
 if not reviews.ok:save_error="客户留言记录校验失败，原存档未改变。";return false
 review_state=reviews.state
 # Older v5 main preserves unknown settings even when its economy drops new
 # top-level fields. This marker detects that known downgrade loss on return.
 var saved_settings:Dictionary=settings.duplicate(true);saved_settings.customer_reviews_schema=Reviews.schema_version(review_state)
 if Reviews.schema_version(review_state)==2 or offer_generation_state.get("version")==AuthoringPolicy.VERSION:saved_settings.protected_bird_schema=1
 if not offer_generation_state.is_empty():
  if not SeededGuard.seed_state_error(offer_generation_state).is_empty():save_error="航线种子记录不完整，原存档未改变。";return false
  saved_settings.offer_generation_schema=1
  if offer_generation_state.version in [AuthoringPolicy.VERSION,AuthoringPolicy.Legacy.VERSION]:saved_settings.offer_authoring_policy=offer_generation_state.version
 var data={"version":SAVE_VERSION,"flight_mode":flight_mode,"credits":credits,"reputation":reputation,"day":day,"phase":phase,"jobs_today":jobs_today,"deliveries":deliveries,"research":research,"workshop_tier":workshop_tier,"history":history,"designs":designs,"inventory":inventory,"contracts":contracts,"active_contract_id":active_contract_id,"settled_ids":settled_ids,"in_flight":in_flight,"last_settlement":last_settlement,"last_trials":last_trials,"story_state":story_state,"review_state":review_state,"design":design,"launcher":launcher,"settings":saved_settings}
 if not offer_generation_state.is_empty():data.offer_generation_state=offer_generation_state.duplicate(true)
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
 load_notice="";review_load_blocked=false;var parsed:Dictionary={};var blocked_integrity_save:Dictionary={};var existing_save:bool=false
 for path in ["user://savegame.json","user://savegame.backup.json"]:
  if not FileAccess.file_exists(path):continue
  existing_save=true
  var parser=JSON.new()
  if parser.parse(FileAccess.get_file_as_string(path))!=OK:continue
  var value=parser.data
  if value is Dictionary and not Reviews.opaque_error(value).is_empty():
   parsed=value;review_load_blocked=true;load_notice="此存档含暂不支持的客户留言或保护鸟记录。原始记录已保留，请勿覆盖。";break
  # Protocol rejection outranks fallback: even damaged adjacent review fields
  # cannot authorize interpreting/downgrading an opaque future dispatch.
  if value is Dictionary and value.get("in_flight") is Dictionary:
   var identity_error:String=replay_protocol_error(value.in_flight)
   if not identity_error.is_empty():
    parsed=value;review_load_blocked=true;load_notice=identity_error;break
  if value is Dictionary and not _valid_save(value) and blocked_integrity_save.is_empty() and _valid_save(value,false):
   # Structural-only inspection retains the actual rejected record for a
   # read-only recovery screen; it is never a migration or a save candidate.
   blocked_integrity_save=value
  if _valid_save(value):
   parsed=value
   if path.ends_with("backup.json"):load_notice="主存档损坏，已恢复上一份有效备份。"
   break
 if parsed.is_empty():
  if blocked_integrity_save.is_empty():
   if existing_save:review_load_blocked=true;load_notice="存档记录损坏，原文件已保留。请恢复有效备份后继续。"
   return {}
  # Keep the real ledger readable, but never replace the damaged source with a
  # fabricated new shop or reset its customer history. Existing valid backups
  # win above. No usable backup means explicit recovery is required.
  parsed=blocked_integrity_save;review_load_blocked=true
  load_notice="存档记录损坏，配送记录与原存档已保留。请恢复有效备份后继续。"

 # Recovery records remain opaque, including their ledger and in-flight copy.
 # Main shows its recovery-only screen before authoring contracts or actors.
 if review_load_blocked:
  in_flight=parsed.get("in_flight",{}).duplicate(true)
  if parsed.get("settled_ids",{}) is Dictionary:settled_ids=parsed.get("settled_ids",{}).duplicate(true)
  if Reviews._integer(parsed.get("credits"),-9007199254740991,9007199254740991):credits=int(parsed.credits)
  return parsed

 # Versions 1..4 predate paid expansion. Preserve their designs verbatim and
 # start at the original tier. Loading alone never rewrites the player's file.
 workshop_tier=int(parsed.workshop_tier) if int(parsed.version)==SAVE_VERSION else 0
 offer_generation_state=parsed.get("offer_generation_state",{}).duplicate(true)
 story_mode=false
 if parsed.get("story_state",{}).is_empty():
  # v1-v3 (and story-disabled fixtures) get a reproducible migration seed.
  # Reloading the same old file cannot reroll appearances, award old receipts,
  # or rewrite its dispatch. Binding waits for explicit enable_story_mode().
  story_state=Stories.initial_state(Stories.stable_seed("legacy-shop/"+JSON.stringify(parsed,"",true,true)))
 else:story_state=Stories.normalize_state(parsed.story_state)
 flight_mode=str(parsed.get("flight_mode","autonomous-v5"))
 credits=int(parsed.get("credits",260));reputation=maxi(0,int(parsed.get("reputation",0)));day=maxi(1,int(parsed.get("day",1)));jobs_today=clampi(int(parsed.get("jobs_today",0)),0,DISPATCHES_PER_DAY);deliveries=maxi(0,int(parsed.get("deliveries",0)));research=clampi(int(parsed.get("research",0)),0,3)
 # Missing legacy field starts empty today, never from old financial receipts.
 review_state=Reviews.normalize_state(parsed.get("review_state"),day).state
 history=parsed.get("history",[]);designs=parsed.get("designs",{});inventory=parsed.get("inventory",{})
 if int(parsed.version)==1:
  phase="morning";contracts=[];jobs_today=0;load_notice="已保留原有方案与库存，可以开始新一天的营业。"
 else:
  phase=str(parsed.get("phase","morning"));contracts=parsed.get("contracts",[]);active_contract_id=str(parsed.get("active_contract_id",""));settled_ids=parsed.get("settled_ids",{});in_flight=parsed.get("in_flight",{});last_settlement=parsed.get("last_settlement",{});last_trials=parsed.get("last_trials",{})
  if not phase in ["morning","day","night"]:phase="morning"
 ensure_contracts()
 return parsed
