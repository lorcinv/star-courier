extends RefCounted
## Read-only delivery presentation contract. All launch numbers and trajectory
## samples are produced by launcher_v3; this helper never estimates physics.
const RouteLayout=preload("res://scripts/delivery_route_layout_v1.gd")
const RiftRisk=preload("res://scripts/delivery_rift_risk_ui_v1.gd")
const VERSION:String="pilot-delivery-v3"
const ASCENT_VERSION:String="pilot-ascent-v4"
const RIFT_VERSION:String="pilot-rift-v5"
const CELL_VERSIONS:Array[String]=["pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const MATERIAL_VERSIONS:Array[String]=["pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const SHIELD_VERSIONS:Array[String]=["pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const LAUNCH_SCHEMA:String="delivery-launch-v3"

static func applies(order:Dictionary) -> bool:
 return str(order.get("control_version","")) in [VERSION,ASCENT_VERSION,RIFT_VERSION]+CELL_VERSIONS

static func fraction(value:Variant) -> float:
 if not (value is float or value is int):return NAN
 var result:float=float(value)
 return result if is_finite(result) and result>=0.0 and result<=1.0 else NAN

static func percent(value:float) -> String:
 if not is_finite(value):return "—"
 var scaled:float=value*100.0
 return ("%.0f%%"%scaled) if is_equal_approx(scaled,roundf(scaled)) else ("%.1f%%"%scaled)

static func requirement(order:Dictionary) -> String:
 return "最低交付完整度 "+percent(fraction(order.get("min_delivery_integrity")))

static func integrity(data:Dictionary,order:Dictionary) -> Dictionary:
 # Explicit normalized field only. In particular, 0.5 means 50%, while the
 # historical report.integrity is still percent and must never be guessed.
 var current:float=fraction(data.get("delivery_integrity"))
 var minimum:float=fraction(order.get("min_delivery_integrity"))
 var known:bool=is_finite(current) and is_finite(minimum)
 var qualified:bool=known and current>=minimum
 return {"current":current,"minimum":minimum,"known":known,"qualified":qualified,
  "current_text":percent(current),"minimum_text":"最低 "+percent(minimum),
  "status":"低于最低线 · 不合格" if known and not qualified else "完整度达标" if known else "完整度数据待确认"}

static func launch_settings(data:Dictionary) -> Dictionary:
 var settings:Dictionary=data.get("launch_settings",{})
 var angle:float=float(settings.get("angle_degrees",0.0))
 var power:float=float(settings.get("power_fraction",1.0))
 return {"angle_degrees":clampf(angle,0.0,90.0) if is_finite(angle) else 0.0,"power_fraction":clampf(power,0.0,1.0) if is_finite(power) else 1.0}

static func preview_matches(preview:Dictionary,settings:Dictionary) -> bool:
 if str(preview.get("schema",""))!=LAUNCH_SCHEMA:return false
 for key in ["angle_degrees","power_fraction"]:
  var value:float=float(preview.get(key,NAN))
  if not is_finite(value) or not is_equal_approx(value,float(settings.get(key,NAN))):return false
 for key in ["mass","available_energy","energy_used","speed"]:
  var value:float=float(preview.get(key,NAN))
  if not is_finite(value) or value<0.0:return false
 return preview.get("velocity") is Vector2 and preview.velocity.is_finite()

static func launch_copy(preview:Dictionary,settings:Dictionary) -> String:
 if not preview_matches(preview,settings):return "发射预览待更新"
 var limits:String=launch_limits_copy(preview)
 return "整船 %.1f kg · 初速 %.1f m/s\n可用储能 %.0f J · 本次使用 %.0f J"%[float(preview.mass),float(preview.speed),float(preview.available_energy),float(preview.energy_used)]+("\n"+limits if not limits.is_empty() else "")

static func launch_limits_copy(preview:Dictionary) -> String:
 # Optional observational data: old snapshots retain their original copy.
 # Only report copied plan values and source labels; no physics is inferred.
 var groups:Variant=preview.get("group_limits")
 if not groups is Array or groups.is_empty():return ""
 var names:Dictionary={"capacity":"动力","power":"力度","support":"支撑","energy":"电量"}
 var capacity_low:float=INF;var capacity_high:float=0.0
 var desired_low:float=INF;var desired_high:float=0.0
 var all_limits:Array[String]=[];var same_limits:bool=true
 for group in groups:
  if not group is Dictionary:return ""
  for key in ["capacity","desired","supported","available","used"]:
   var value:Variant=group.get(key)
   if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0.0:return ""
  var sources:Variant=group.get("limits")
  if not sources is Array or sources.is_empty():return ""
  for source in sources:
   if not source is String or not names.has(source):return ""
   if not all_limits.has(source):all_limits.append(source)
  same_limits=same_limits and sources==groups[0].limits
  capacity_low=minf(capacity_low,float(group.capacity));capacity_high=maxf(capacity_high,float(group.capacity))
  desired_low=minf(desired_low,float(group.desired));desired_high=maxf(desired_high,float(group.desired))
 var low_power:bool=float(preview.get("power_fraction",1.0))<1.0
 var copy:String="动力上限 %.0f J"%capacity_low if groups.size()==1 else "%d组独立 · 各组动力上限 %s J"%[groups.size(),_launch_range(capacity_low,capacity_high)]
 if low_power:copy+=(" · 力度请求 %.0f J"%desired_low if groups.size()==1 else "\n各组力度请求 %s J"%_launch_range(desired_low,desired_high))
 if same_limits and all_limits==["capacity"] and capacity_low>0.0:
  copy+=" · 动力已用满" if groups.size()==1 else "\n各组动力已用满"
 elif not same_limits or all_limits.size()>1:
  var labels:Array[String]=[]
  for source in names:
   if all_limits.has(source):labels.append(names[source])
  copy+="\n"+("并列限制：" if groups.size()==1 else "各组并列限制：" if same_limits else "各组瓶颈不同：")+" / ".join(labels)
 # Sole support/energy limits are already explained by the warning label.
 return copy

static func _launch_range(low:float,high:float) -> String:
 return "%.0f"%low if is_equal_approx(low,high) else "%.0f–%.0f"%[low,high]

static func liability(order:Dictionary) -> String:
 return "按实际货损赔偿，整箱上限 ¥%d；另计能源与零件损耗，余额不足会形成债务。"%int(order.get("cargo_value",0))

static func receipt_speed(data:Dictionary,order:Dictionary) -> Dictionary:
 # An early informational cue, never a speed cap or a braking simulation.
 if str(order.get("control_version","")) not in [ASCENT_VERSION,RIFT_VERSION,"pilot-ascent-v6","pilot-rift-v6","pilot-ascent-v7","pilot-rift-v7","pilot-ascent-v8","pilot-rift-v8"] and not heavy_route(order):return {}
 var values:Array=[order.get("max_delivery_speed"),order.get("delivery_radius"),data.get("destination_distance"),data.get("speed")]
 for value in values:
  if not (value is int or value is float) or not is_finite(float(value)):return {}
 var limit:float=float(values[0]);var radius:float=float(values[1]);var distance:float=float(values[2]);var speed:float=float(values[3])
 if limit<=0.0 or radius<=0.0 or distance<0.0 or speed<0.0:return {}
 if distance>radius+maxf(60.0,speed*6.0):return {}
 if str(data.get("flight_status","running"))!="running" or bool(data.get("charging",false)):return {}
 return {"text":"收件 ≤ %.1f m/s"%limit,"overspeed":speed>limit,"limit":limit,"speed":speed}

static func cell_rules(order:Dictionary) -> bool:
 return str(order.get("control_version","")) in CELL_VERSIONS

static func coasting(data:Dictionary,order:Dictionary) -> bool:
 return cell_rules(order) and str(data.get("flight_status","running"))=="running" and bool(data.get("unpowered_coasting",false))

static func accelerator_copy(preview:Dictionary,compact:bool=false) -> String:
 if preview.is_empty():return "弹射预览待更新"
 var reason:String=str(preview.get("reason",""))
 var blocked:String=str({"spent":"已发射","target_not_linked":"未连接目标","bypass_connection":"旁路仍相连，不能弹射","no_payload":"没有可分离载荷","insufficient_energy":"电量不足","exit_blocked":"弹射净空不足","no_impulse":"弹出速度为零","invalid_route":"订单预览不可用","wrong_protocol":"订单规则不匹配"}.get(reason,""))
 var ids:Variant=preview.get("payload_ids",[])
 var mass:float=float(preview.get("payload_mass",NAN))
 if not ids is Array or ids.is_empty() or not is_finite(mass) or mass<=0:return blocked if not blocked.is_empty() else "弹射预览待更新"
 var group:String="弹出 %d 格 · %.1f kg"%[ids.size(),mass]
 if compact:return blocked if not blocked.is_empty() else group
 var details:Dictionary=accelerator_details(preview)
 return group+("\n"+blocked if not blocked.is_empty() else "")+("\n"+details.motion+"\n"+details.impact+"\n"+details.cost+"\n"+details.scope if not details.is_empty() else "")

static func direction_arrow(value:Variant) -> String:
 if not value is Vector2 or not value.is_finite() or value.length_squared()<0.0000001:return "·"
 return ["→","↘","↓","↙","←","↖","↑","↗"][posmod(roundi(value.angle()/(PI/4.0)),8)]

static func accelerator_details(preview:Dictionary) -> Dictionary:
 # These are only the owner's one-trigger predictions. No future movement,
 # damage, lost-carrier bill or ballistic travel is estimated in presentation.
 if not bool(preview.get("can_fire",false)):return {}
 for key in ["carrier_delta_v","payload_delta_v"]:
  if not preview.get(key) is Vector2 or not preview[key].is_finite():return {}
 var impacts:Variant=preview.get("cargo_impacts",[])
 if not impacts is Array:return {}
 var worst:Dictionary={};var below:bool=false;var impact_lines:Array[String]=[]
 for item in impacts:
  if not item is Dictionary:continue
  var before:float=fraction(item.get("integrity_before"));var after:float=fraction(item.get("integrity_after"));var minimum:float=fraction(item.get("min_delivery_integrity"))
  if not is_finite(before) or not is_finite(after) or not is_finite(minimum):continue
  if worst.is_empty() or after-minimum<float(worst.integrity_after)-float(worst.min_delivery_integrity):worst=item
  below=below or after<minimum
  impact_lines.append("货物 #%s：%s → %s；最低 %s"%[str(item.get("cargo_id","?")),percent(before),percent(after),percent(minimum)])
 var impact:String="本次无货物冲击" if worst.is_empty() else ("货物 " if impacts.size()==1 else "最险货物 ")+percent(float(worst.integrity_before))+" → "+percent(float(worst.integrity_after))+" · 最低 "+percent(float(worst.min_delivery_integrity))
 if below:impact+=" 不合格"
 var energy:float=float(preview.get("energy_required",NAN));var ammo:float=float(preview.get("ammo_cost",NAN))
 var ammo_ids:Variant=preview.get("ammo_part_ids",[])
 if not is_finite(energy) or energy<0 or not is_finite(ammo) or ammo<0 or not ammo_ids is Array:return {}
 var ids:Array[String]=[]
 for id in ammo_ids:ids.append("#"+str(id))
 return {"motion":"弹出 %s Δv%.1f · 反冲 %s Δv%.1f m/s"%[direction_arrow(preview.payload_delta_v),preview.payload_delta_v.length(),direction_arrow(preview.carrier_delta_v),preview.carrier_delta_v.length()],
  "impact":impact,"cost":"耗电 %.0f J · 弹药 ¥%.0f"%[energy,ammo]+("（%d格原价）"%ammo_ids.size() if not ammo_ids.is_empty() else ""),
  "scope":"仅本次触发 · 不含后续损失","below_minimum":below,
  "tooltip":"\n".join(impact_lines)+"\n弹药来源："+(", ".join(ids) if not ids.is_empty() else "本次无计费耗用零件")+"。不含未来遗失、修理或碰撞；条件变化会重算。"}


static func route_preview(order:Dictionary)->Dictionary:
 return RiftRisk.preview(order) if RiftRisk.applies(order) else RouteLayout.preview(order)

static func repeat_copy(order:Dictionary)->String:
 # Frozen quote intent only: a later completion cannot relabel a first run,
 # and basic debt-recovery work must not be advertised as a chosen repeat.
 if not applies(order):return ""
 if not order.get("chapter_progression") is bool or order.chapter_progression:return ""
 if not order.get("recovery_offer") is bool or order.recovery_offer:return ""
 var level:Variant=order.get("chapter_level")
 if not (level is int or level is float) or not is_finite(float(level)):return ""
 if float(level)!=floorf(float(level)) or float(level)<1.0 or float(level)>5.0:return ""
 return "自选复送 · 不推进章节"

static func completed_chapter_copy(data:Dictionary)->String:
 var status:Variant=data.get("delivery_chapter_status")
 if not status is Dictionary:return ""
 if not status.get("enabled") is bool or not status.enabled:return ""
 if not status.get("complete") is bool or not status.complete:return ""
 var unlocked:Variant=status.get("unlocked_level")
 if not (unlocked is int or unlocked is float) or not is_finite(float(unlocked)) or float(unlocked)!=6.0:return ""
 return "五关已完成"

static func ascent_geometry_copy(order:Dictionary)->String:
 # Frozen order coordinates only. distance is horizontal displacement, not
 # flown path length. Never regenerate a route from chapter/day defaults.
 if str(order.get("control_version","")) not in [ASCENT_VERSION,"pilot-ascent-v6","pilot-ascent-v7","pilot-ascent-v8"] or str(order.get("route_kind",""))!="ascent":return ""
 for key in ["distance","destination_y","background_ground_y_m"]:
  var value:Variant=order.get(key)
  if not (value is int or value is float) or not is_finite(float(value)):return ""
 var height:float=float(order.background_ground_y_m)-float(order.destination_y)
 if height<=0.0:return ""
 return "水平间距 %.0f m · 目标离地 %.0f m"%[absf(float(order.distance)),height]

static func order_distance_copy(order:Dictionary)->String:
 var ascent:String=ascent_geometry_copy(order)
 return ascent if not ascent.is_empty() else "路程 %s m"%order.get("distance",0)

static func route_copy(order:Dictionary)->String:
 var repeat:String=repeat_copy(order)
 var copy:String=""
 if not ascent_geometry_copy(order).is_empty():
  copy=ascent_geometry_copy(order)+"\n需船上持续推进；绕开岩石，接近收件站时减速。"
 elif RiftRisk.applies(order):copy=RiftRisk.route_copy(order)
 else:
  var route:Dictionary=route_preview(order)
  if not route.is_empty():
   if route.layout_id==RouteLayout.ROCKBELT_ID:copy="碎石带：上下绕远更稳，接触切石耗电且可能伤货"
   else:copy="高架 %.0f m · 货重 %.1f kg · 完整度 ≥ %s"%[float(route.altitude_m),float(route.cargo_mass_kg),percent(fraction(route.min_delivery_integrity))] if route.layout_id==RouteLayout.HEAVY_ID else "窄道 %.1f m · 可从上 / 下方绕行"%float(route.clearance_m)
 return repeat+("\n"+copy if not copy.is_empty() else "") if not repeat.is_empty() else copy


static func heavy_route(order:Dictionary)->bool:
 var route:Dictionary=route_preview(order)
 return not route.is_empty() and route.layout_id==RouteLayout.HEAVY_ID

static func route_guidance(order:Dictionary)->String:
 if not heavy_route(order):return ""
 return "默认台推裸重货爬不够高；加强台上动力件与支撑，或加船上推进。"

static func heavy_retry_copy(report:Dictionary,order:Dictionary)->String:
 # The report's actual order must be supplied by the flight owner. Current
 # offers, cargo names and generic failure messages cannot identify this route.
 if not report.get("success") is bool or report.success:return ""
 var id:Variant=report.get("contract_id")
 if not id is String or id.is_empty() or not order.get("contract_id") is String or order.contract_id!=id:return ""
 if not report.get("control_version") is String or not heavy_route(order) or report.control_version!=order.control_version:return ""
 return "再试前：加强台上动力件与支撑，或加船上推进；绕开岩石，减速收件。"

static func debt_recovery_copy(report:Dictionary,data:Dictionary)->String:
 # Both current chapter mode and this restored receipt must be explicit. A
 # negative number alone never promises that an old or trial craft was restored.
 if not applies(report) or not applies({"control_version":data.get("control_version")}):return ""
 if not report.get("restored") is bool or not report.restored:return ""
 var trial:Variant=report.get("trial") if report.has("trial") else data.get("trial")
 if not trial is bool or trial:return ""
 var credits:Variant=data.get("credits");var debt:Variant=report.get("debt")
 if not (credits is int or credits is float) or not is_finite(float(credits)) or float(credits)>=0.0:return ""
 if not (debt is int or debt is float) or not is_finite(float(debt)) or float(debt)<=0.0:return ""
 return "原装配已恢复，可继续用现有零件；打烊后可接轻货赚运费。"
