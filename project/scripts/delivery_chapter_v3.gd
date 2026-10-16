extends RefCounted
## Snapshot-bound progression. New offers use explicit v8 physics; historical
## versions remain valid without reauthoring. Its catalog is authoring-only; old contracts and
## receipts are validated from their own terms, never rebuilt from current tuning.
const Profile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const AscentProfile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const RiftProfile=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const CellRules=preload("res://scripts/cell_rules_profile_v6.gd")
const CellGround=preload("res://scripts/pilot_delivery_profile_v6.gd")
const CellAscent=preload("res://scripts/pilot_delivery_ascent_profile_v6.gd")
const CellRift=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const MaterialGround=preload("res://scripts/pilot_delivery_profile_v7.gd")
const MaterialAscent=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const MaterialRift=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const ShieldGround=preload("res://scripts/pilot_delivery_profile_v8.gd")
const ShieldAscent=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const ShieldRift=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const RouteLayout=preload("res://scripts/delivery_route_layout_v1.gd")
const Guard=preload("res://scripts/seeded_offer_guard.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const VERSION:String="pilot-delivery-v3"
const STATE_SCHEMA:String="delivery-chapter-state-v3"
const ECONOMY_POLICY:String="delivery-economy-v3"
const RECEIPT_SCHEMA:String="delivery-receipt-v3"
const UPGRADE_SCHEMA:String="delivery-chapter-upgrade-v3"
const DELIVERY_POLICY:String="minimum-integrity-arrival-v3"
const LIABILITY_POLICY:String="actual-loss-no-cash-cap-v3"
const SAFE_INT:int=9007199254740991
const FIRST_CHAPTER_LEVEL_COUNT:int=3
const MOON_LEVEL:int=4
const LEVEL_COUNT:int=5
const ASCENT_VERSION:String="pilot-ascent-v4"
const RIFT_VERSION:String="pilot-rift-v5"
const CELL_GROUND_VERSION:String="pilot-delivery-v6"
const CELL_ASCENT_VERSION:String="pilot-ascent-v6"
const CELL_RIFT_VERSION:String="pilot-rift-v6"
const MATERIAL_GROUND_VERSION:String="pilot-delivery-v7"
const MATERIAL_ASCENT_VERSION:String="pilot-ascent-v7"
const MATERIAL_RIFT_VERSION:String="pilot-rift-v7"
const SHIELD_GROUND_VERSION:String="pilot-delivery-v8"
const SHIELD_ASCENT_VERSION:String="pilot-ascent-v8"
const SHIELD_RIFT_VERSION:String="pilot-rift-v8"
const COLD_REPEAT_ID:String="rift-cold-long-crossing-v1"
const COLD_MAINLINE_ID:String="rift-cold-mainline-v1"
const PORTAL_EVIDENCE_SCHEMA:String="rift-crossing-proof-v1"
const CARGO_KINDS:Array[String]=["light","heavy","fragile","lunar_supply","biological"]

static func initial_state() -> Dictionary:
 # chapter_id=1 is the historical sequence identity. Global unlocked_level
 # naturally becomes 4 after the original three receipts; never reset it.
 return {"schema":STATE_SCHEMA,"chapter_id":1,"unlocked_level":1,"completed_levels":{}}

static func catalog() -> Array:
 return [fresh_route(1),fresh_route(2),fresh_route(3),fresh_route(4),fresh_route(5)]

static func fresh_route(level:int,progression:bool=true,recovery:bool=false,rockbelt:bool=false,cold_repeat:bool=false,cold_mainline:bool=false) -> Dictionary:
 if level<1 or level>LEVEL_COUNT:return {}
 if rockbelt and (level!=3 or progression or recovery):return {}
 if cold_repeat and (level!=5 or progression or recovery or rockbelt or cold_mainline):return {}
 if cold_mainline and (level!=5 or not progression or recovery or rockbelt):return {}
 if level==5:
  var rift:Dictionary=_fresh_rift_route(progression,recovery)
  if (cold_repeat or cold_mainline) and not rift.is_empty():
   rift.rift_delivery_layout=COLD_MAINLINE_ID if cold_mainline else COLD_REPEAT_ID
   rift.name="第五关 · 寒带生物配送" if cold_mainline else "温室远端补送 · 寒带横穿"
   rift.variant="第三章 · 保温或暖绕" if cold_mainline else "自选复送 · 保温或暖绕"
   rift.destination_name="门后远端育苗温室";rift.distance=240.0
   rift.rift_biology.cold_bounds=[110.0,-30.0,100.0,60.0]
   rift.risk="门后是100米宽寒带。可带相连且有电的保温模块直穿，或减速转向从上下暖区绕行；保温并非免伤，护盾不保温。"
   rift.story="活体幼苗须经过门户，最低完整度80%。直穿较短但持续冷损，暖绕更远；按实际电费、货损结算。"+("" if cold_mainline else "本单不推进章节。")
  return rift
 if level==4:return _fresh_ascent_route(progression,recovery)
 var names:Array=["第一关 · 轻货起航","第二关 · 重货上坡","第三关 · 易碎花房"]
 var cargos:Array=["温室种子","货站蓄能芯","精密玻璃培养皿"]
 var thresholds:Array=[0.70,0.75,0.90]
 var weights:Array=[1.0,4.0,1.2]
 var rewards:Array=[220,340,380]
 var values:Array=[180,320,420]
 var risks:Array=["绕开浮石；发射后保留电量，靠近收件台前减速。","重货影响发射、爬升和制动；侧风与重力需要持续供能。","避免猛推、急停和硬碰撞；缓慢加速与缓冲装配都可尝试。"]
 var i:int=level-1
 var base:Dictionary={
  "id":i,"name":names[i],"client":"货站调度员","cargo":cargos[i],
  "route_profile":"delivery-chapter-1-v3","route_kind":"ground",
  "destination_id":"chapter-1-level-%d"%level,"destination_name":["社区收件台","高架货站","玻璃花房"][i],
  "distance":[80.0,110.0,95.0][i],"destination_y":[-8.0,-18.0,-10.0][i],
  "weight":weights[i],"delivery_radius":[8.0,8.0,7.0][i],"max_delivery_speed":[14.0,10.0,6.0][i],
  "gravity":[0.0,0.35,0.10][i],"wind":[[0.0,0.0],[-0.10,0.15],[0.10,0.0]][i],
  "pilot_drag":0.025,"variation":0.0,"pilot_gates":[],"boundary_y":1000.0,
  "background_route":"city","background_ground_y_m":0.0,
  "deadline":10000000.0,"time_limit":10000000.0,"reward":rewards[i],"rep":0,
  "required":float(thresholds[i])*100.0,"min_delivery_integrity":thresholds[i],
  "chapter_id":1,"chapter_level":level,"chapter_progression":progression,"recovery_offer":recovery,
  "cargo_kind":CARGO_KINDS[i],"cargo_value":values[i],
  "cargo_safe_acceleration":[40.0,25.0,4.0][i],
  "cargo_damage_per_excess_mps":[0.5,0.8,3.0][i],"cargo_contact_damage_scale":[1.0,1.0,2.0][i],
  "economy_policy":ECONOMY_POLICY,"liability_policy":LIABILITY_POLICY,
  "risk":risks[i],"story":"最低完整度 %d%%；按实际货损、修理、丢失与用能结算，余额不足会记为负债。"%roundi(float(thresholds[i])*100.0),
  "variant":"首章 · "+str(["轻货","重货","易碎"][i]),
  "hazards":[]
 }
 if level==1:
  base.hazards=[{"id":"chapter-light-rock","x":38.0,"y":-5.0,"radius":3.5,"type":"rock","health":65.0,"mass":50.0,"destructible":true,"conductive":true}]
 elif level==2:
  # Content is authored only at the empty new-day batch boundary.
  base=RouteLayout.author_heavy(base)
  if base.is_empty():return {}
 else:
  # New empty-batch quotes only. Saved old fragile routes are never reauthored.
  base=RouteLayout.author_rockbelt(base) if rockbelt else RouteLayout.author_fragile(base)
  if base.is_empty():return {}
 if not progression and level==1:
  base.name="基础轻货 · 偿债续单" if recovery else "基础轻货 · 自选续单"
  base.variant="基础轻货";base.story="用已有飞船完成轻货运输即可赚取运费。没有领款或补送零件；正式费用照常入账。"
 elif not progression and level==2:
  base.name="重货上坡 · 自选复送";base.variant="自选复送 · 重货"
  base.story="再送一箱蓄能芯到高架货站。最低完整度75%；本单不推进章节，运费与实际费用照常结算。"
 elif not progression and level==3:
  base.name="易碎花房 · 自选复送";base.variant="自选复送 · 易碎"
  base.story="再送一箱精密培养皿到玻璃花房。最低完整度90%；本单不推进章节，运费与实际费用照常结算。"
 if rockbelt:
  base.name="花房补送 · 碎石带捷径";base.variant="自选复送 · 碎石带"
  base.story="这次花房途中是一带可破坏浮石。绕远更稳，接触切石可开捷径；没有指定零件要求。本单不推进章节，原运费与实际损失照常结算。"
 return ShieldGround.route(base)

static func repeat_level(state:Dictionary,day:int,recovery:bool=false)->int:
 # Only future empty batches use this authoring policy. No saved counter or
 # migration is needed: day modulo the ascending eligible list is reproducible.
 # Light is always available; completing 2 adds heavy, completing 3 adds fragile.
 # [1,2,3] gives day 4 heavy, day 5 fragile, day 6 light, then repeats.
 # Before completing 3, [1,2] gives odd-day heavy and even-day light.
 if recovery:return 1
 var eligible:Array[int]=[1]
 var completed:Dictionary=state.get("completed_levels",{})
 for level in [2,3]:
  if completed.has(str(level)):eligible.append(level)
 return eligible[posmod(day,eligible.size())]

static func is_version(value:Variant) -> bool:
 return value is String and value in [VERSION,ASCENT_VERSION,RIFT_VERSION,CELL_GROUND_VERSION,CELL_ASCENT_VERSION,CELL_RIFT_VERSION,MATERIAL_GROUND_VERSION,MATERIAL_ASCENT_VERSION,MATERIAL_RIFT_VERSION,SHIELD_GROUND_VERSION,SHIELD_ASCENT_VERSION,SHIELD_RIFT_VERSION]

static func is_cell_version(value:Variant) -> bool:
 return value is String and value in [CELL_GROUND_VERSION,CELL_ASCENT_VERSION,CELL_RIFT_VERSION,MATERIAL_GROUND_VERSION,MATERIAL_ASCENT_VERSION,MATERIAL_RIFT_VERSION,SHIELD_GROUND_VERSION,SHIELD_ASCENT_VERSION,SHIELD_RIFT_VERSION]

static func is_rift_version(value:Variant) -> bool:
 return value is String and value in [RIFT_VERSION,CELL_RIFT_VERSION,MATERIAL_RIFT_VERSION,SHIELD_RIFT_VERSION]

# Authoring and validation are deliberately separate. A new catalog version
# never invalidates an old displayed/accepted/in-flight order or paid receipt.
static func authored_version_for_level(level:int) -> String:
 return SHIELD_GROUND_VERSION if level<=FIRST_CHAPTER_LEVEL_COUNT else (SHIELD_ASCENT_VERSION if level==MOON_LEVEL else SHIELD_RIFT_VERSION)

static func material_version_for_level(level:int) -> String:
 return MATERIAL_GROUND_VERSION if level<=FIRST_CHAPTER_LEVEL_COUNT else (MATERIAL_ASCENT_VERSION if level==MOON_LEVEL else MATERIAL_RIFT_VERSION)

static func cell_version_for_level(level:int) -> String:
 return CELL_GROUND_VERSION if level<=FIRST_CHAPTER_LEVEL_COUNT else (CELL_ASCENT_VERSION if level==MOON_LEVEL else CELL_RIFT_VERSION)

static func allowed_version_for_level(value:Variant,level:int) -> bool:
 return value is String and value in [version_for_level(level),cell_version_for_level(level),material_version_for_level(level),authored_version_for_level(level)]

static func chapter_for_level(level:int) -> int:return 1 if level<=FIRST_CHAPTER_LEVEL_COUNT else (2 if level==MOON_LEVEL else 3)
static func version_for_level(level:int) -> String:return VERSION if level<=FIRST_CHAPTER_LEVEL_COUNT else (ASCENT_VERSION if level==MOON_LEVEL else RIFT_VERSION)

static func _fresh_ascent_route(progression:bool,recovery:bool) -> Dictionary:
 # Only a new global level-four quote enters the new physical author. Neither
 # old offers nor their receipts are passed through this factory on load.
 var base:Dictionary={"id":3,"name":"第四关 · 持续升空登月","client":"月面补给站","cargo":"月面观测站补给箱",
  "destination_name":"月面观测站","deadline":10000000.0,"time_limit":10000000.0,
  "reward":620,"rep":0,"required":80.0,"min_delivery_integrity":0.8,
  "chapter_id":2,"chapter_level":4,"chapter_progression":progression,"recovery_offer":recovery,
  "cargo_kind":"lunar_supply","cargo_value":500,"economy_policy":ECONOMY_POLICY,"liability_policy":LIABILITY_POLICY,
  "variant":"第二章 · 登月补给","risk":"持续向上爬升，分配推重比与电量；躲避实体陨石，留意流星雨预警。",
  "story":"这箱补给需要一路升空送到月面观测站。最低完整度80%，按实际用能、货损和部件损失结算。"}
 return ShieldAscent.route(base)

static func _fresh_rift_route(progression:bool,recovery:bool) -> Dictionary:
 # New-day authoring only: completed moon saves already carry unlocked_level=5.
 var base:Dictionary={"id":4,"name":"第五关 · 穿门生物配送","client":"门后温室","cargo":"活体苔光幼苗",
  "destination_name":"门后育苗温室","deadline":10000000.0,"time_limit":10000000.0,
  "reward":660,"rep":0,"required":80.0,"min_delivery_integrity":0.8,
  "chapter_id":3,"chapter_level":5,"chapter_progression":progression,"recovery_offer":recovery,
  "cargo_kind":"biological","cargo_value":520,"economy_policy":ECONOMY_POLICY,"liability_policy":LIABILITY_POLICY,
  "variant":"第三章 · 必经门户","risk":"整船通过入口再送往温室；留意海盗预警，避开乱流和长时间低温暴露。",
  "story":"活体幼苗必须实际经过门户送往门后温室。最低完整度80%，受冷损伤计入同一货物完整度，按实际损失结算。"}
 return ShieldRift.route(base)

static func offer(level:int,day:int,slot:int,progression:bool=true,recovery:bool=false,rockbelt:bool=false,cold_repeat:bool=false,cold_mainline:bool=false) -> Dictionary:
 var result:Dictionary=fresh_route(level,progression,recovery,rockbelt,cold_repeat,cold_mainline)
 if result.is_empty():return {}
 result.contract_id="D%d-%s"%[day,"A" if slot==0 else "B"]
 result.status="available";result.accepted_day=day
 return result

static func has_markers(route:Dictionary) -> bool:
 return RouteLayout.has_markers(route) or is_version(route.get("control_version")) or ShieldGround.shield_markers(route) or MaterialGround.material_markers(route) or CellRules.has_markers(route) or RiftProfile.has_markers(route) or AscentProfile.has_markers(route) or route.get("economy_policy")==ECONOMY_POLICY or route.has("chapter_level") or route.get("route_profile")=="delivery-chapter-1-v3"

static func route_error(route:Dictionary) -> String:
 if route.has("rift_delivery_layout"):
  var layout=route.rift_delivery_layout
  if layout not in [COLD_REPEAT_ID,COLD_MAINLINE_ID] or route.get("chapter_level")!=5 or route.get("recovery_offer")!=false:return "寒带配送身份无效。"
  if route.get("chapter_progression")!=(layout==COLD_MAINLINE_ID):return "寒带配送进度身份无效。"
 var layout_error:String=RouteLayout.validation_error(route)
 if not layout_error.is_empty():return layout_error
 var physics_error:String=""
 if ShieldGround.shield_markers(route):
  match route.get("control_version"):
   SHIELD_GROUND_VERSION:physics_error=ShieldGround.validation_error(route)
   SHIELD_ASCENT_VERSION:physics_error=ShieldAscent.validation_error(route)
   SHIELD_RIFT_VERSION:physics_error=ShieldRift.validation_error(route)
   _:return "空间护盾规则不能套用到旧驾驶协议。"
 elif MaterialGround.material_markers(route):
  match route.get("control_version"):
   MATERIAL_GROUND_VERSION:physics_error=MaterialGround.validation_error(route)
   MATERIAL_ASCENT_VERSION:physics_error=MaterialAscent.validation_error(route)
   MATERIAL_RIFT_VERSION:physics_error=MaterialRift.validation_error(route)
   _:return "材料响应规则不能套用到旧驾驶协议。"
 elif CellRules.has_markers(route):
  match route.get("control_version"):
   CELL_GROUND_VERSION:physics_error=CellGround.validation_error(route)
   CELL_ASCENT_VERSION:physics_error=CellAscent.validation_error(route)
   CELL_RIFT_VERSION:physics_error=CellRift.validation_error(route)
   _:return "组合规则不能套用到旧驾驶协议。"
 else:
  physics_error=RiftProfile.validation_error(route) if RiftProfile.has_markers(route) else (AscentProfile.validation_error(route) if AscentProfile.has_markers(route) else Profile.validation_error(route))
 if not physics_error.is_empty():return "配送驾驶规则记录不完整。"
 if route.get("economy_policy")!=ECONOMY_POLICY or route.get("liability_policy")!=LIABILITY_POLICY:return "首章费用规则记录不完整。"
 if not Guard.integer_in(route.get("chapter_level"),1,LEVEL_COUNT):return "主线关卡身份无效。"
 if route.get("chapter_id")!=chapter_for_level(int(route.chapter_level)) or not allowed_version_for_level(route.get("control_version"),int(route.chapter_level)):return "章节与驾驶协议不一致。"
 if route.get("cargo_kind")!=CARGO_KINDS[int(route.chapter_level)-1] or not route.get("chapter_progression") is bool or not route.get("recovery_offer") is bool:return "首章货物身份无效。"
 if not Guard.number_in(route.get("min_delivery_integrity"),0.0,1.0):return "最低交付完整度无效。"
 if not Guard.number_in(route.get("required"),0.001,100.0) or not is_equal_approx(float(route.required),maxf(0.001,float(route.min_delivery_integrity)*100.0)):return "交付完整度显示与判定不一致。"
 for key in ["reward","cargo_value"]:
  if not Guard.integer_in(route.get(key),1,10000000):return "首章运费或货值无效。"
 for key in ["deadline","time_limit"]:
  if not Guard.number_in(route.get(key),0.001,10000000.0):return "首章用时记录无效。"
 if not Guard.integer_in(route.get("rep"),0,0):return "首章声望记录无效。"
 for key in ["name","client","cargo","destination_name"]:
  if not route.get(key) is String or route[key].strip_edges().is_empty():return "首章委托文字缺失。"
 if route.has("contract_id"):
  if not route.get("contract_id") is String or route.contract_id.is_empty() or not route.get("status") in ["available","accepted","in_flight","settled","declined","cancelled"]:return "首章委托身份无效。"
  if not Guard.integer_in(route.get("accepted_day"),1,1000000):return "首章委托日期无效。"
 return ""

static func integrity_of(telemetry:Dictionary) -> float:
 return float(telemetry.get("delivery_integrity",telemetry.get("integrity",0.0)))

static func telemetry_error(telemetry:Dictionary,elapsed:float) -> String:
 if not Guard.number_in(elapsed,0.0,10000000.0):return "配送用时记录不完整。"
 if not Guard.number_in(telemetry.get("delivery_integrity",telemetry.get("integrity")),0.0,1.0):return "首章完整度必须为 0 到 1。"
 if telemetry.has("integrity") and (not Guard.number_in(telemetry.integrity,0.0,1.0) or float(telemetry.integrity)!=integrity_of(telemetry)):return "货物完整度记录不一致。"
 for key in ["energy_used","ammo_cost","repair_cost","lost_cost"]:
  if not Guard.number_in(telemetry.get(key),0.0,10000000.0):return "配送实际费用记录不完整。"
 for key in ["cargo_peak_acceleration","cargo_contact_impulse"]:
  if telemetry.has(key) and not Guard.number_in(telemetry[key],0.0,1000000000.0):return "货物受力记录不完整。"
 return ""

static func cargo_damage(value:int,integrity:float) -> int:
 # Remove only floating-point roundoff at whole-credit boundaries.
 return clampi(ceili(float(value)*(1.0-integrity)-0.000000001),0,value)

static func quote(order:Dictionary,telemetry:Dictionary,success:bool) -> Dictionary:
 var integrity:float=integrity_of(telemetry)
 var qualified:bool=success and integrity>=float(order.min_delivery_integrity)
 if is_rift_version(order.get("control_version")):qualified=qualified and _portal_arrival_error(order,telemetry).is_empty()
 var tariff:float=float(order.pilot_energy_tariff)
 var energy:int=ceili(float(telemetry.get("energy_used",0.0))*tariff)
 var ammo:int=ceili(float(telemetry.get("ammo_cost",0.0)))
 var repairs:int=ceili(float(telemetry.get("repair_cost",0.0)))
 var lost:int=ceili(float(telemetry.get("lost_cost",0.0)))
 var compensation:int=cargo_damage(int(order.cargo_value),integrity)
 var actual:int=energy+ammo+repairs+lost+compensation
 var income:int=int(order.reward) if qualified else 0
 return {"receipt_schema":RECEIPT_SCHEMA,"economy_policy":ECONOMY_POLICY,"liability_policy":LIABILITY_POLICY,"control_version":str(order.control_version),"delivery_policy":DELIVERY_POLICY,"income":income,"energy":energy,"energy_tariff":tariff,"energy_j":float(telemetry.get("energy_used",0.0)),"ammo":ammo,"repairs":repairs,"lost":lost,"compensation":compensation,"actual_costs":actual,"charged_costs":actual,"profit":income-actual,"delivery_integrity":integrity,"min_delivery_integrity":float(order.min_delivery_integrity),"delivery_qualified":qualified,"cargo_value":int(order.cargo_value),"cargo_kind":order.cargo_kind,"chapter_id":int(order.chapter_id),"chapter_level":int(order.chapter_level),"chapter_progression":order.chapter_progression}

static func _portal_arrival_error(order:Dictionary,telemetry:Dictionary) -> String:
 # A visible destination or a success boolean is not portal evidence.
 if not telemetry.get("required_portal_id") is String or telemetry.required_portal_id!=order.get("required_portal_id"):return "portal_identity"
 if not Guard.integer_in(telemetry.get("portal_crossing_tick"),1,Timeline.MAX_TICKS*2):return "portal_not_crossed"
 if not telemetry.get("region") is String or telemetry.region!="greenhouse":return "portal_region"
 var events:Variant=telemetry.get("portal_crossings")
 if not events is Array or events.size()!=1:return "portal_event_missing"
 if not events[0] is Dictionary or not events[0].get("portal_id") is String or events[0].portal_id!=order.required_portal_id or not Guard.integer_in(events[0].get("tick"),1,Timeline.MAX_TICKS*2) or events[0].tick!=telemetry.portal_crossing_tick:return "portal_event_mismatch"
 return ""

static func capture_portal_evidence(order:Dictionary,snapshot:Dictionary,telemetry:Dictionary,success:bool) -> Dictionary:
 # Capture only the dispatch-bound witness, never defaults for missing values.
 # The simulator creates crossing events at the CCD transition; Main checkpoints
 # the exact completed 60 Hz command count before invoking this transaction.
 var cargo_ids:Array=[];var launch_ids:Array=[]
 if not snapshot.get("design") is Array:return {"ok":false,"error":"portal_design"}
 for part in snapshot.design:
  if not part is Dictionary or not Guard.integer_in(part.get("id"),0,Timeline.MAX_TICKS):return {"ok":false,"error":"portal_part"}
  launch_ids.append(int(part.id))
  if part.get("type")=="cargo":cargo_ids.append(int(part.id))
 var evidence:Dictionary={"schema":PORTAL_EVIDENCE_SCHEMA,"required_portal_id":order.get("required_portal_id"),
  "portal_crossing_tick":telemetry.get("portal_crossing_tick"),"portal_crossings":telemetry.get("portal_crossings"),
  "flight_ticks":snapshot.get("ticks"),"physics_ticks":telemetry.get("pilot_tick"),"region":telemetry.get("region"),
  "cargo_ids":cargo_ids,"launch_part_ids":launch_ids,"portal":order.get("rift_portal")}
 if not telemetry.get("control_version") is String or telemetry.control_version!=order.get("control_version") or not is_rift_version(telemetry.control_version) or not telemetry.get("required_portal_id") is String or telemetry.required_portal_id!=order.get("required_portal_id"):return {"ok":false,"error":"portal_protocol"}
 var error:String=portal_evidence_error(evidence,success)
 return {"ok":error.is_empty(),"error":error,"evidence":evidence.duplicate(true) if error.is_empty() else {}}

static func portal_evidence_error(value:Variant,success:bool) -> String:
 if not value is Dictionary or not _keys(value,["schema","required_portal_id","portal_crossing_tick","portal_crossings","flight_ticks","physics_ticks","region","cargo_ids","launch_part_ids","portal"]):return "missing_portal_delivery_evidence"
 if not value.schema is String or value.schema!=PORTAL_EVIDENCE_SCHEMA or not value.required_portal_id is String or value.required_portal_id!=RiftProfile.PORTAL_ID or not value.region is String:return "unknown_portal_delivery_evidence"
 if not Guard.integer_in(value.flight_ticks,0,Timeline.MAX_TICKS) or not Guard.integer_in(value.physics_ticks,0,Timeline.MAX_TICKS*2):return "invalid_portal_flight_ticks"
 # One outer input step advances two fixed physics steps, except a terminal
 # collision/receiver may stop after its first substep.
 if int(value.physics_ticks)<maxi(0,int(value.flight_ticks)*2-1) or int(value.physics_ticks)>int(value.flight_ticks)*2:return "incoherent_portal_flight_ticks"
 if not _id_list(value.launch_part_ids,false) or not _id_list(value.cargo_ids,false):return "invalid_portal_dispatch_ids"
 for id in value.cargo_ids:
  if id not in value.launch_part_ids:return "portal_cargo_not_launched"
 var portal:Variant=value.portal
 if not portal is Dictionary or not portal.get("id") is String or portal.id!=value.required_portal_id:return "invalid_portal_identity"
 for key in ["entry","exit"]:
  if not _finite_point(portal.get(key)):return "invalid_portal_geometry"
 if not Guard.number_in(portal.get("aperture_radius"),0.001,10000.0) or not Guard.number_in(portal.get("margin"),0.0,float(portal.aperture_radius)):return "invalid_portal_aperture"
 if not Guard.number_in(portal.get("exit_lookahead"),0.0,100.0):return "invalid_portal_exit"
 if not Guard.integer_in(value.portal_crossing_tick,-1,int(value.physics_ticks)) or not value.portal_crossings is Array:return "invalid_portal_crossing_tick"
 if int(value.portal_crossing_tick)==-1:
  if success or not value.portal_crossings.is_empty() or value.region!="departure":return "portal_required_before_delivery"
  return ""
 if int(value.portal_crossing_tick)<1 or value.region!="greenhouse" or value.portal_crossings.size()!=1:return "incoherent_portal_crossing"
 var event:Variant=value.portal_crossings[0]
 if not event is Dictionary or not _keys(event,["portal_id","tick","cargo_ids","part_ids","from","to","body_radius","margin"]):return "invalid_portal_event"
 if not event.portal_id is String or event.portal_id!=value.required_portal_id or not Guard.integer_in(event.tick,1,int(value.physics_ticks)) or event.tick!=value.portal_crossing_tick:return "incoherent_portal_event_identity"
 if not _id_list(event.part_ids,false) or not _id_list(event.cargo_ids,false):return "invalid_portal_event_parts"
 if event.cargo_ids.size()!=value.cargo_ids.size():return "portal_missing_cargo"
 for id in value.cargo_ids:
  if id not in event.cargo_ids or id not in event.part_ids:return "portal_missing_cargo"
 for id in event.part_ids:
  if id not in value.launch_part_ids:return "portal_foreign_part"
 if not _finite_point(event.from) or not _finite_point(event.to):return "invalid_portal_event_position"
 var from:Vector2=Vector2(float(event.from[0]),float(event.from[1]));var to:Vector2=Vector2(float(event.to[0]),float(event.to[1]))
 var entry:Vector2=Vector2(float(portal.entry[0]),float(portal.entry[1]));var exit_point:Vector2=Vector2(float(portal.exit[0]),float(portal.exit[1]))
 if not Guard.number_in(event.body_radius,0.001,float(portal.aperture_radius)) or not Guard.number_in(event.margin,0.0,float(portal.aperture_radius)) or event.margin!=portal.margin:return "invalid_portal_body_envelope"
 var clearance:float=float(event.body_radius)+float(event.margin)
 if (to-from-(exit_point-entry+Vector2(clearance,0.0))).length()>0.001:return "incoherent_portal_event_translation"
 if absf(from.x-entry.x)>0.001 or absf(from.y-entry.y)+clearance>float(portal.aperture_radius)+0.001:return "portal_event_outside_entry"
 return ""

static func _finite_point(value:Variant) -> bool:
 return value is Array and value.size()==2 and Guard.number_in(value[0],-10000000.0,10000000.0) and Guard.number_in(value[1],-10000000.0,10000000.0)

static func _id_list(value:Variant,allow_empty:bool) -> bool:
 if not value is Array or (not allow_empty and value.is_empty()) or value.size()>4096:return false
 var seen:Dictionary={}
 for id in value:
  if not Guard.integer_in(id,0,Timeline.MAX_TICKS) or seen.has(int(id)):return false
  seen[int(id)]=true
 return true

static func state_error(state:Variant,ledger:Dictionary={}) -> String:
 if not state is Dictionary or not _keys(state,["schema","chapter_id","unlocked_level","completed_levels"]):return "invalid_delivery_chapter_state"
 if state.schema!=STATE_SCHEMA or not Guard.integer_in(state.chapter_id,1,1) or not Guard.integer_in(state.unlocked_level,1,LEVEL_COUNT+1) or not state.completed_levels is Dictionary:return "unknown_delivery_chapter_state"
 if state.completed_levels.size()!=int(state.unlocked_level)-1:return "incoherent_delivery_progress"
 for level in range(1,int(state.unlocked_level)):
  var id:Variant=state.completed_levels.get(str(level))
  if not id is String or not ledger.get(id) is Dictionary:return "missing_delivery_progress_receipt"
  var receipt:Dictionary=ledger[id]
  if receipt.get("receipt_schema")!=RECEIPT_SCHEMA or receipt.get("success")!=true or receipt.get("chapter_level")!=level or receipt.get("level_completed")!=true:return "invalid_delivery_progress_receipt"
 return ""

static func advance(state:Dictionary,order:Dictionary,receipt:Dictionary) -> bool:
 if not bool(receipt.success) or not bool(order.chapter_progression) or int(order.chapter_level)!=int(state.unlocked_level) or int(state.unlocked_level)>LEVEL_COUNT:return false
 state.completed_levels[str(int(order.chapter_level))]=str(receipt.contract_id)
 state.unlocked_level=int(state.unlocked_level)+1
 return true

static func launch_settings_error(value:Variant) -> String:
 if not value is Dictionary or not _keys(value,["angle_degrees","power_fraction"]):return "发射设置记录不完整。"
 if not Guard.number_in(value.angle_degrees,0.0,90.0) or not Guard.number_in(value.power_fraction,0.0,1.0):return "发射角度或力度无效。"
 return ""

static func snapshot_error(snapshot:Dictionary) -> String:
 if not snapshot.get("route") is Dictionary or not is_version(snapshot.get("control_version")) or snapshot.get("control_version")!=snapshot.route.get("control_version") or not route_error(snapshot.route).is_empty():return "配送规则记录不完整。"
 if snapshot.get("input_schema")!=Timeline.INPUT_SCHEMA or not Guard.integer_in(snapshot.get("ticks"),0,Timeline.MAX_TICKS):return "首章驾驶记录不完整。"
 var timeline=Timeline.new()
 if not timeline.restore(snapshot.get("input_commands"),int(snapshot.ticks)):return "首章驾驶输入记录无效。"
 if not snapshot.get("contract_id") is String or snapshot.contract_id!=snapshot.route.get("contract_id"):return "首章配送身份不一致。"
 if not launch_settings_error(snapshot.get("launch_settings")).is_empty():return "首章发射设置缺失。"
 if not snapshot.get("launch_released") is bool:return "首章发射释放记录缺失。"
 if snapshot.launch_released:
  if snapshot.has("launch_preparation"):return "已释放发射不能保留准备进度。"
 else:
  var preparation:Variant=snapshot.get("launch_preparation")
  if int(snapshot.ticks)!=0 or not preparation is Dictionary or not _keys(preparation,["age","transfer_remaining"]):return "首章发射准备记录不完整。"
  if not Guard.number_in(preparation.age,0.0,0.95) or not Guard.number_in(preparation.transfer_remaining,0.0,120.0):return "首章发射准备进度无效。"
  if float(preparation.age)>0.0 and float(preparation.transfer_remaining)>0.0:return "移送与点火准备阶段不能重叠。"
 if snapshot.has("terminal_intent") and snapshot.terminal_intent!="abort":return "首章中止记录无效。"
 if snapshot.has("simulation_version") and snapshot.simulation_version!=snapshot.control_version:return "首章模拟版本不一致。"
 return ""

static func receipt_error(receipt:Dictionary) -> String:
 for pair in [["receipt_schema",RECEIPT_SCHEMA],["economy_policy",ECONOMY_POLICY],["delivery_policy",DELIVERY_POLICY],["liability_policy",LIABILITY_POLICY]]:
  if receipt.get(pair[0])!=pair[1]:return "unknown_delivery_receipt_policy"
 for key in ["success","delivery_qualified","chapter_progression","level_completed"]:
  if not receipt.get(key) is bool:return "invalid_delivery_receipt_flag"
 if receipt.success!=receipt.delivery_qualified:return "incoherent_delivery_qualification"
 for key in ["delivery_integrity","min_delivery_integrity"]:
  if not Guard.number_in(receipt.get(key),0.0,1.0):return "invalid_delivery_receipt_integrity"
 if receipt.success and float(receipt.delivery_integrity)<float(receipt.min_delivery_integrity):return "unqualified_delivery_success"
 if not Guard.number_in(receipt.get("integrity"),0.0,100.0) or not is_equal_approx(float(receipt.integrity),float(receipt.delivery_integrity)*100.0):return "incoherent_delivery_integrity_units"
 if not Guard.number_in(receipt.get("required"),0.001,100.0) or not is_equal_approx(float(receipt.required),maxf(0.001,float(receipt.min_delivery_integrity)*100.0)):return "incoherent_delivery_requirement"
 if not Guard.integer_in(receipt.get("chapter_level"),1,LEVEL_COUNT):return "invalid_delivery_receipt_level"
 if receipt.get("chapter_id")!=chapter_for_level(int(receipt.chapter_level)) or not allowed_version_for_level(receipt.get("control_version"),int(receipt.chapter_level)):return "invalid_delivery_receipt_protocol"
 if receipt.get("cargo_kind")!=CARGO_KINDS[int(receipt.chapter_level)-1]:return "invalid_delivery_receipt_cargo"
 for key in ["income","base_income","energy","ammo","repairs","lost","compensation","cargo_value","actual_costs","charged_costs","debt","debt_added"]:
  if not Guard.integer_in(receipt.get(key),0,SAFE_INT):return "invalid_delivery_receipt_amount"
 for key in ["profit","credits_before","credits_after"]:
  if not Guard.integer_in(receipt.get(key),-SAFE_INT,SAFE_INT):return "invalid_delivery_receipt_signed_amount"
 if not Guard.number_in(receipt.get("energy_j"),0.0,10000000.0) or not Guard.number_in(receipt.get("energy_tariff"),0.001,0.18):return "invalid_delivery_energy"
 if int(receipt.energy)!=ceili(float(receipt.energy_j)*float(receipt.energy_tariff)):return "incoherent_delivery_energy"
 if int(receipt.compensation)!=cargo_damage(int(receipt.cargo_value),float(receipt.delivery_integrity)):return "incoherent_delivery_compensation"
 if int(receipt.actual_costs)!=int(receipt.energy)+int(receipt.ammo)+int(receipt.repairs)+int(receipt.lost)+int(receipt.compensation) or int(receipt.charged_costs)!=int(receipt.actual_costs):return "incoherent_delivery_actual_costs"
 if int(receipt.income)!=(int(receipt.base_income) if receipt.success else 0) or int(receipt.profit)!=int(receipt.income)-int(receipt.actual_costs):return "incoherent_delivery_income"
 if int(receipt.credits_after)!=int(receipt.credits_before)+int(receipt.profit) or int(receipt.debt)!=maxi(0,-int(receipt.credits_after)) or int(receipt.debt_added)!=maxi(0,int(receipt.debt)-maxi(0,-int(receipt.credits_before))):return "incoherent_delivery_debt"
 if receipt.level_completed and (not receipt.success or not receipt.chapter_progression):return "invalid_delivery_completion"
 if is_rift_version(receipt.control_version):
  var evidence_error:String=portal_evidence_error(receipt.get("portal_delivery_evidence"),bool(receipt.success))
  if not evidence_error.is_empty():return evidence_error
 if receipt.has("insurance_coverage") or receipt.has("charge_cap"):return "mixed_delivery_insurance_policy"
 return ""

static func saved_error(raw:Dictionary) -> String:
 var settings:Variant=raw.get("settings",{})
 if not settings is Dictionary:return "invalid_delivery_settings"
 var ledger:Variant=raw.get("settled_ids",{})
 if not ledger is Dictionary:return "invalid_delivery_ledger"
 var marked:bool=raw.get("flight_mode")==VERSION or settings.has("delivery_chapter_schema") or raw.has("delivery_chapter_state") or raw.has("delivery_upgrade")
 var orders:Array=raw.get("contracts",[]).duplicate() if raw.get("contracts") is Array else []
 if raw.get("in_flight") is Dictionary and not raw.in_flight.is_empty() and raw.in_flight.get("route") is Dictionary:orders.append(raw.in_flight.route)
 for order in orders:
  if order is Dictionary and has_markers(order):
   marked=true
   if not route_error(order).is_empty():return "invalid_delivery_saved_order"
 for id in ledger:
  var receipt:Variant=ledger[id]
  if not receipt is Dictionary:continue
  if is_version(receipt.get("control_version")) or receipt.get("economy_policy")==ECONOMY_POLICY or receipt.has("receipt_schema"):
   marked=true
   var error:String=receipt_error(receipt)
   if not error.is_empty():return error
   if receipt.get("contract_id")!=id:return "invalid_delivery_receipt_identity"
 if not marked:return ""
 if raw.get("flight_mode")!=VERSION or settings.get("delivery_chapter_schema")!=STATE_SCHEMA:return "missing_delivery_chapter_marker"
 var state_error_text:String=state_error(raw.get("delivery_chapter_state"),ledger)
 if not state_error_text.is_empty():return state_error_text
 for id in ledger:
  var receipt:Variant=ledger[id]
  if receipt is Dictionary and receipt.get("receipt_schema")==RECEIPT_SCHEMA and receipt.level_completed and raw.delivery_chapter_state.completed_levels.get(str(int(receipt.chapter_level)))!=id:return "orphaned_delivery_completion"
 var aliases:Array=raw.get("history",[]).duplicate() if raw.get("history") is Array else []
 if raw.get("last_settlement") is Dictionary and not raw.last_settlement.is_empty():aliases.append(raw.last_settlement)
 for receipt in aliases:
  if receipt is Dictionary and (is_version(receipt.get("control_version")) or receipt.get("economy_policy")==ECONOMY_POLICY or receipt.has("receipt_schema")):
   if not ledger.has(receipt.get("contract_id")) or not _same(receipt,ledger[receipt.contract_id]):return "incoherent_delivery_receipt_copy"
 var upgrade:Variant=raw.get("delivery_upgrade")
 if upgrade!=null:
  if not upgrade is Dictionary or not _keys(upgrade,["schema","day","source_sha256","confirmation_token","orders"]):return "invalid_delivery_upgrade"
  if upgrade.schema!=UPGRADE_SCHEMA or settings.get("delivery_upgrade_schema")!=UPGRADE_SCHEMA or not Guard.integer_in(upgrade.day,1,1000000):return "unknown_delivery_upgrade"
  for key in ["source_sha256","confirmation_token"]:
   if not _sha(upgrade[key]):return "invalid_delivery_upgrade_hash"
  if not upgrade.orders is Array or upgrade.orders.size()>2:return "invalid_delivery_upgrade_orders"
  var seen:Dictionary={}
  for row in upgrade.orders:
   if not row is Dictionary or not _keys(row,["contract_id","original_order_sha256","replacement_order_sha256"]):return "invalid_delivery_upgrade_order"
   if not row.contract_id is String or row.contract_id.is_empty() or seen.has(row.contract_id):return "invalid_delivery_upgrade_identity"
   seen[row.contract_id]=true
   if not _sha(row.original_order_sha256) or not _sha(row.replacement_order_sha256):return "invalid_delivery_upgrade_hash"
 elif settings.has("delivery_upgrade_schema"):return "missing_delivery_upgrade"
 return ""

static func _keys(value:Dictionary,keys:Array) -> bool:
 if value.size()!=keys.size():return false
 for key in keys:
  if not value.has(key):return false
 return true
static func _same(a:Variant,b:Variant) -> bool:return JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true))
static func _sha(value:Variant) -> bool:
 if not value is String or value.length()!=64:return false
 for c in value:
  if not c in "0123456789abcdef":return false
 return true
