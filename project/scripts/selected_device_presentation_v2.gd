extends RefCounted
## Read-only projection from the live solver. It grants no firing authority.
const DeliveryUI=preload("res://scripts/delivery_ui_v3.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const CouplerCutPreview=preload("res://scripts/coupler_cut_preview.gd")
static func state(sim) -> Dictionary:
 if sim==null or sim.route.get("control_version") not in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:return {}
 var id:int=int(sim.pilot_device_id)
 if id<0:return {}
 var p:Dictionary=sim.parts.get(id,{})
 if p.is_empty():return {"name":"装置","direction":"","status":"已失联"}
 var kind:String=str(p.type)
 var name:String=str(Parts.catalog().get(kind,{}).get("name","装置"))
 if kind=="coupler":name="分离扣"
 var result:Dictionary={"name":name,"direction":"","status":"可用"}
 if not id in sim.selectable_device_ids():result.status="已失联";return result
 var body:Dictionary=sim.body_for_part(id)
 if body.is_empty():result.status="已失联";return result
 var direction:Vector2=sim.teleport_direction(body,p) if kind=="teleporter" else Vector2.RIGHT.rotated(float(body.angle)+float(p.local_angle))
 result.direction=arrow(direction)
 if kind=="shield" and str(sim.route.get("control_version","")) in DeliveryUI.SHIELD_VERSIONS:
  result.shield_preview=sim.shield_coverage_snapshot(id)
  var covered:Array=result.shield_preview.get("protected_ids",[])
  result.status="局部可保护 %d 格"%covered.size() if not covered.is_empty() else "局部护盾未供能或未启用"
  return result
 if kind=="solid_booster":
  var fuel:float=clampf(float(p.get("solid_fuel_fraction",1.0)),0.0,1.0)
  result.status="燃尽 · 剩壳可分离" if fuel<=sim.EPS else ("燃烧 %.0f%% · 不可关停"%[fuel*100.0] if bool(p.get("solid_lit",false)) else "未点火 · 燃料100%")
  return result
 if kind=="drill":
  # Selection already requires a live, cargo-connected cockpit source. This is
  # the solver's paid output, not evidence of cutting. A control clear can
  # precede the next tick, so stale paid output alone must not claim running.
  result.hold_to_use=true
  var paid:float=float(p.get("drill_power_ratio",0.0))
  var output:float=float(p.get("output_factor",1.0))
  if paid>sim.EPS and sim._enabled(p):result.status="钻头运转 · 供电不足" if paid+sim.EPS<output else "钻头运转"
  elif not sim._can_supply(body,Parts.DRILL_POWER*sim.FIXED_DT*output,id,sim.FIXED_DT):result.status="电量不足"
  else:result.status="按住启动 · 慢推破岩"
  return result
 if bool(p.get("spent",false)) and kind=="accelerator":result.status="已发射";return result
 var target:Dictionary=sim._target(p,body)
 if kind in ["coupler","splitter","accelerator"]:
  if target.is_empty() or not sim._linked(id,int(target.id)) or target.body_id!=body.id:result.status="未连接目标";return result
  if kind=="splitter" and (target.type in ["cargo","splitter"] or float(target.mass)<.05 or sim.parts.size()>=sim.MAX_SIM_PARTS):result.status="目标不能分裂";return result
 var cost:float=25.0 if kind=="teleporter" else 10.0 if kind=="splitter" else 0.0
 if kind=="teleporter" and sim.route.get("control_version") in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:cost=sim.teleport_energy_cost(body,float(p.param))
 if kind=="accelerator" and str(sim.route.get("control_version","")) in DeliveryUI.CELL_VERSIONS:
  if not sim.has_method("preview_accelerator"):result.status="弹射预览待更新";return result
  var preview:Dictionary=sim.preview_accelerator(id)
  preview.accelerator_id=id
  result.status=DeliveryUI.accelerator_copy(preview,true);result.accelerator_preview=preview.duplicate(true)
  return result
 if kind=="accelerator":
  var carrier_mass:float=float(body.mass)-float(target.mass)
  if carrier_mass<=sim.EPS:result.status="未连接目标";return result
  cost=.5*carrier_mass*float(target.mass)/float(body.mass)*float(p.param)*float(p.param)
 if cost>0.0 and not sim._can_supply(body,cost,id,1.0/60.0):result.status="电量不足";return result
 if kind=="coupler":result.status=CouplerCutPreview.text(CouplerCutPreview.from_live(sim,p,target,body))
 if kind=="teleporter" and not sim.destination_clear(body,direction*float(p.param)):result.status="落点受阻"
 return result

static func arrow(direction:Vector2) -> String:
 if not direction.is_finite() or direction.length_squared()<.000001:return ""
 var directions:Array[String]=["→","↘","↓","↙","←","↖","↑","↗"]
 return directions[posmod(roundi(direction.angle()/(PI/4.0)),8)]
