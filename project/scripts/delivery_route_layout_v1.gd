extends RefCounted
## Content identity only. The saved circles are consumed by the unchanged v8
## solver. Authoring never receives an already displayed or committed order.
const SCHEMA:String="delivery-route-layout-v1"
const FRAGILE_ID:String="fragile-dual-rock-v1"
const ROCKBELT_ID:String="fragile-optional-rockbelt-v1"
const HEAVY_ID:String="heavy-uplift-rock-v1"
const HAZARDS:Array=[
 {"id":"chapter-fragile-upper","x":48.0,"y":-18.2,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true},
 {"id":"chapter-fragile-lower","x":48.0,"y":-1.8,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true}
]
const HEAVY_HAZARDS:Array=[
 {"id":"chapter-heavy-uplift","x":62.0,"y":-64.0,"radius":9.0,"type":"rock","health":120.0,"mass":80.0,"destructible":true,"conductive":true}
]

const ROCKBELT_HAZARDS:Array=[
 {"id":"optional-belt-0","x":48.0,"y":-38.0,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true},
 {"id":"optional-belt-1","x":48.0,"y":-24.0,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true},
 {"id":"optional-belt-2","x":48.0,"y":-10.0,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true},
 {"id":"optional-belt-3","x":48.0,"y":4.0,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true},
 {"id":"optional-belt-4","x":48.0,"y":18.0,"radius":7.0,"type":"rock","health":100.0,"mass":70.0,"destructible":true,"conductive":true}
]

static func author_rockbelt(base:Dictionary)->Dictionary:
 for key in ["contract_id","status","generation","accepted_day","control_version","pilot_profile","route_layout"]:
  if base.has(key):return {}
 if base.get("chapter_level")!=3 or base.get("cargo_kind")!="fragile" or base.get("chapter_progression")!=false or base.get("recovery_offer")!=false:return {}
 var result:Dictionary=base.duplicate(true)
 result.route_layout={"schema":SCHEMA,"id":ROCKBELT_ID}
 result.hazards=ROCKBELT_HAZARDS.duplicate(true)
 result.variation=0.0
 result.risk="碎石带挡住直线；可从上方或下方绕远，也可用钻头接触切开岩石。切割耗电且接触可能伤货，先免费试飞。"
 return result

static func author_heavy(base:Dictionary)->Dictionary:
 for key in ["contract_id","status","generation","accepted_day","control_version","pilot_profile","route_layout"]:
  if base.has(key):return {}
 if base.get("chapter_level")!=2 or base.get("cargo_kind")!="heavy":return {}
 var result:Dictionary=base.duplicate(true)
 result.route_layout={"schema":SCHEMA,"id":HEAVY_ID}
 result.distance=110.0;result.destination_y=-72.0
 result.hazards=HEAVY_HAZARDS.duplicate(true)
 result.variation=0.0
 result.risk="重货需升至72米并绕开实体浮石；可加强台上动力件和支撑，或给飞船增加推进，先免费试飞。"
 return result

static func author_fragile(base:Dictionary)->Dictionary:
 for key in ["contract_id","status","generation","accepted_day","control_version","pilot_profile","route_layout"]:
  if base.has(key):return {}
 if base.get("chapter_level")!=3 or base.get("cargo_kind")!="fragile":return {}
 var result:Dictionary=base.duplicate(true)
 result.route_layout={"schema":SCHEMA,"id":FRAGILE_ID}
 result.hazards=HAZARDS.duplicate(true)
 result.variation=0.0
 result.risk="浮石间有窄道，上下方可绕行；留意整船高度、转动和碰撞，先免费试飞。"
 return result

static func has_markers(route:Dictionary)->bool:
 for key in route:
  if str(key)=="route_layout" or str(key).begins_with("route_layout_"):return true
 return false

static func validation_error(route:Dictionary)->String:
 if not has_markers(route):return ""
 for key in route:
  if str(key).begins_with("route_layout_"):return "未知航线布局字段。"
 var identity:Variant=route.get("route_layout")
 if not identity is Dictionary or identity.size()!=2 or not identity.get("schema") is String or not identity.get("id") is String:return "航线布局身份不完整。"
 if identity.schema!=SCHEMA or identity.id not in [FRAGILE_ID,HEAVY_ID,ROCKBELT_ID]:return "这份航线使用了暂不支持的布局。"
 var heavy:bool=identity.id==HEAVY_ID
 if route.get("control_version")!="pilot-delivery-v8" or route.get("chapter_level")!=(2 if heavy else 3) or route.get("chapter_id")!=1 or route.get("cargo_kind")!=("heavy" if heavy else "fragile") or route.get("route_kind")!="ground":return "航线布局与委托身份不一致。"
 for key in ["distance","destination_y","delivery_radius","variation"]:
  if not _number(route.get(key)):return "航线布局坐标无效。"
 if absf(float(route.distance))>100000.0 or absf(float(route.destination_y))>100000.0 or float(route.delivery_radius)<=0.0 or float(route.delivery_radius)>1000.0 or float(route.variation)!=0.0:return "航线布局范围无效。"
 if heavy:
  # This new content identity freezes the approved ascent and original terms.
  # No historical unmarked heavy route is compared with this template.
  var fixed:Dictionary={"distance":110.0,"destination_y":-72.0,"delivery_radius":8.0,"weight":4.0,"min_delivery_integrity":0.75,"required":75.0,"max_delivery_speed":10.0,"gravity":0.35,"pilot_drag":0.025}
  for key in fixed:
   if not _number(route.get(key)) or float(route[key])!=float(fixed[key]):return "重货航线与冻结布局不一致。"
  if not route.get("wind") is Array or route.wind.size()!=2 or not _number(route.wind[0]) or not _number(route.wind[1]) or float(route.wind[0])!=-0.10 or float(route.wind[1])!=0.15:return "重货风场与冻结布局不一致。"
 if identity.id==ROCKBELT_ID and (route.get("chapter_progression")!=false or route.get("recovery_offer")!=false):return "碎石带仅用于自选复送。"
 var expected_hazards:Array=HEAVY_HAZARDS if heavy else ROCKBELT_HAZARDS if identity.id==ROCKBELT_ID else HAZARDS
 var hazards:Variant=route.get("hazards")
 if not hazards is Array or hazards.size()!=expected_hazards.size():return "航线实体浮石记录不完整。"
 for index in hazards.size():
  var actual:Variant=hazards[index]
  var expected:Dictionary=expected_hazards[index]
  if not actual is Dictionary or actual.size()!=expected.size():return "航线实体浮石字段不一致。"
  for key in expected:
   if expected[key] is float:
    if not _number(actual.get(key)) or float(actual[key])!=float(expected[key]):return "航线实体浮石与冻结布局不一致。"
   elif typeof(actual.get(key))!=typeof(expected[key]) or actual[key]!=expected[key]:return "航线实体浮石与冻结布局不一致。"
 return ""

static func preview(route:Dictionary)->Dictionary:
 if not has_markers(route) or not validation_error(route).is_empty():return {}
 # Read the quote's actual geometry, never today’s authoring template or prose.
 var circles:Array=[]
 for h in route.hazards:
  circles.append({"id":str(h.id),"position":Vector2(float(h.x),float(h.y)),"radius":float(h.radius)})
 var result:Dictionary={"schema":SCHEMA,"layout_id":str(route.route_layout.id),"circles":circles,
  "launch":Vector2.ZERO,"receiver":Vector2(float(route.distance),float(route.destination_y)),"receiver_radius":float(route.delivery_radius),
  "altitude_m":-float(route.destination_y)}
 # Do not tighten the original fragile layout reader. Expose only valid actual
 # optional terms; never fabricate fallback mass or receipt requirements.
 # Total cargo mass follows simulation.gd, including multiple cargo cells.
 if _number(route.get("weight")) and float(route.weight)>0.0 and float(route.weight)<=1000.0:result.cargo_mass_kg=3.0*maxf(0.1,float(route.weight))
 if _number(route.get("min_delivery_integrity")) and float(route.min_delivery_integrity)>=0.0 and float(route.min_delivery_integrity)<=1.0:result.min_delivery_integrity=float(route.min_delivery_integrity)
 if _number(route.get("max_delivery_speed")) and float(route.max_delivery_speed)>0.0:result.max_delivery_speed=float(route.max_delivery_speed)
 if route.route_layout.id==FRAGILE_ID:
  var a:Dictionary=circles[0];var b:Dictionary=circles[1]
  var direction:Vector2=(b.position-a.position).normalized()
  var edge_a:Vector2=a.position+direction*a.radius
  var edge_b:Vector2=b.position-direction*b.radius
  result.passage_center=(edge_a+edge_b)*0.5;result.clearance_m=edge_a.distance_to(edge_b)
 return result

static func summary(route:Dictionary)->String:
 var data:Dictionary=preview(route)
 if data.is_empty():return ""
 if data.layout_id==ROCKBELT_ID:return "碎石带：上下绕远，或接触切石；切割可能伤货。"
 if data.layout_id==HEAVY_ID:return "收件高度 %.0f m · 货物 %.0f kg · 最低完整度 %.0f%%；绕开实体浮石。"%[float(data.altitude_m),float(data.cargo_mass_kg),float(data.min_delivery_integrity)*100.0]
 return "窄道净空 %.1f m；可从浮石上方或下方绕行。"%float(data.clearance_m)

static func _number(value:Variant)->bool:
 return (value is int or value is float) and is_finite(float(value))
