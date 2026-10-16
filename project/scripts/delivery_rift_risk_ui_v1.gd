extends RefCounted
## Presentation only: freeze a view of this quote's own validated environment.
## No authoring defaults, simulation, damage, contracts or economy are changed.
const V5=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const V6=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const V7=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const V8=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const ID:String="rift-frozen-risk-view-v1"

static func applies(order:Dictionary)->bool:
 return order.get("control_version") in [V5.VERSION,V6.VERSION,V7.VERSION,V8.VERSION]

static func preview(order:Dictionary)->Dictionary:
 var validator
 match order.get("control_version"):
  V5.VERSION:validator=V5
  V6.VERSION:validator=V6
  V7.VERSION:validator=V7
  V8.VERSION:validator=V8
  _:return {}
 if not validator.validation_error(order).is_empty():return {}
 var gate:Dictionary=order.rift_portal;var bio:Dictionary=order.rift_biology;var field:Dictionary=order.rift_turbulence
 return {"layout_id":ID,"launch":Vector2.ZERO,"receiver":Vector2(float(order.distance),float(order.destination_y)),
  "entry":_point(gate.entry),"exit":_point(gate.exit),"aperture_radius":float(gate.aperture_radius),"margin":float(gate.margin),
  "cold_bounds":_rect(bio.cold_bounds),"turbulence_bounds":_rect(field.bounds),
  "grace_seconds":float(bio.grace_seconds),"damage_hp_per_second":float(bio.damage_hp_per_second),
  "warm_temperature_c":float(bio.warm_temperature_c),"cold_temperature_c":float(bio.cold_temperature_c),
  "period_seconds":float(field.period_seconds),"active_seconds":float(field.active_seconds),
  "pirate_position":_point(order.rift_pirate.position),"pirate_radius":float(order.rift_pirate.radius)}

static func number(value:float)->String:
 return "%.0f"%value if is_equal_approx(value,roundf(value)) else "%.2f"%value if not is_equal_approx(value*10.0,roundf(value*10.0)) else "%.1f"%value

static func route_copy(order:Dictionary)->String:
 var view:Dictionary=preview(order)
 if view.is_empty():return ""
 var prefix:String="寒带横穿 · " if order.get("rift_delivery_layout") in ["rift-cold-long-crossing-v1","rift-cold-mainline-v1"] else ""
 return prefix+"门口 %s m · 冷区宽限 %s s · 超时 %s HP/s"%[number(view.aperture_radius*2.0),number(view.grace_seconds),number(view.damage_hp_per_second)]

static func guidance(order:Dictionary)->String:
 if preview(order).is_empty():return ""
 if order.get("rift_delivery_layout") in ["rift-cold-long-crossing-v1","rift-cold-mainline-v1"]:
  return "保温需直连货物且有电，不能免伤。\n不带保温可提前减速，从上下暖区绕。\n直穿较短；货损赔偿与电费照实结算。"
 return "冷区看货物中心，乱流看刚体重心。\n暖区可绕；离冷区停止冷损，不会修复。\n门按整船保守包络；旋转不保证能过。"

static func tooltip(order:Dictionary)->String:
 var view:Dictionary=preview(order)
 if view.is_empty():return ""
 return "本单冻结位置与边界。冷区按货物中心连续暴露计时；超出 %s s 后每秒记录 %s HP 冷损。乱流按每个刚体重心判定，周期 %s s / 活跃 %s s。门户按整船保守包络加 %s m 余量检查；还需出口安全。图中暖区只表示不受冷损，不保证无海盗或碰撞风险；护盾不保温。"%[number(view.grace_seconds),number(view.damage_hp_per_second),number(view.period_seconds),number(view.active_seconds),number(view.margin)]

static func biology(data:Dictionary,order:Dictionary)->Dictionary:
 if not applies(order) or not data.get("portal_crossing_tick") is int or data.portal_crossing_tick<0 or data.get("region")!="greenhouse":return {}
 var view:Dictionary=preview(order)
 if view.is_empty():return {}
 for key in ["biological_exposure_seconds","biological_temperature_c"]:
  if not _number(data.get(key)):return {}
 var exposure:float=float(data.biological_exposure_seconds);var temperature:float=float(data.biological_temperature_c)
 if exposure<0.0:return {}
 var cold:bool=temperature<float(view.warm_temperature_c)
 return {"cold":cold,"text":"冷区 %.1f/%s s · %s HP/s"%[exposure,number(view.grace_seconds),number(view.damage_hp_per_second)] if cold else "暖区 %s°C · 当前不增冷损"%number(temperature),
  "note":"超宽限正受冷损 · 离开冷区可停止" if cold and exposure>float(view.grace_seconds) else "连续暴露超宽限后冷损" if cold else "已有冷损不会自动修复"}

static func report_copy(report:Dictionary,order:Dictionary)->String:
 if not applies(report) or report.get("control_version")!=order.get("control_version") or preview(order).is_empty():return ""
 if not report.get("contract_id") is String or report.contract_id.is_empty() or report.contract_id!=order.get("contract_id"):return ""
 if not _number(report.get("biological_damage")) or float(report.biological_damage)<0.0:return ""
 var damage:float=float(report.biological_damage)
 return "本次记录冷损 %s HP；离开冷区可停止新增冷损，已有损伤不会修复。"%number(damage) if damage>0.0 else "本次记录冷损 0 HP；其他货损仍按实际记录结算。"

static func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
static func _point(value:Array)->Vector2:return Vector2(float(value[0]),float(value[1]))
static func _rect(value:Array)->Rect2:return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
