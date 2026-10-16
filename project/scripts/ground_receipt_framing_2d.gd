extends RefCounted
## CURRENT_PILOT_V3_ONLY: ordinary ground/ascent approach and receipt. Use the real
## painted receiver and frozen recovered module positions, never a capture snap.
const Shared=preload("res://scripts/moon_framing_2d.gd")
static func applies(route:Dictionary) -> bool:
 return str(route.get("control_version",""))=="pilot-v3" and str(route.get("route_kind","")) in ["ground",""] and not route.has("moon_schema") and not route.has("wormhole_portal") and not route.has("pirate_encounter")

static func craft_bounds(sim,origin:Vector2,cell:float) -> Rect2:
 if sim.status!="success":return Shared.craft_bounds(sim,origin,cell)
 var low:Vector2=Vector2(INF,INF);var high:Vector2=Vector2(-INF,-INF)
 # Success detaches recovered hardware from bodies. Its immutable world pose
 # remains authoritative; a cargo-body lookup alone loses the other modules.
 for p in sim.parts.values():
  if not bool(p.get("alive",false)) or not bool(p.get("delivered",false)):continue
  var angle:float=float(p.get("world_angle",0.0))
  var half:float=cell*.49*float(p.get("scale",1.0))*(absf(sin(angle))+absf(cos(angle)))
  var at:Vector2=origin+sim.part_world_position(int(p.id))*cell
  low=low.min(at-Vector2.ONE*half);high=high.max(at+Vector2.ONE*half)
 return Rect2(low,high-low) if low.is_finite() else Shared.craft_bounds(sim,origin,cell)

static func receiver_bounds(receiver:Sprite2D) -> Rect2:
 var local:Rect2=receiver.get_rect();var pose:Transform2D=receiver.transform
 var result:Rect2=Rect2(pose*local.position,Vector2.ZERO)
 for point in [local.position+Vector2(local.size.x,0),local.end,local.position+Vector2(0,local.size.y)]:result=result.expand(pose*point)
 return result

static func compose(sim,origin:Vector2,cell:float,receiver:Sprite2D,extent:Vector2,mapper:Control,cruise_center:Vector2,cruise_zoom:float) -> Dictionary:
 if not applies(sim.route) or sim.status not in ["running","success"] or receiver==null:return {}
 var distance:float=float(sim.route.get("distance",0.0))-sim.cargo_position().x
 var radius:float=float(sim.route.get("delivery_radius",5.0))
 var craft:Rect2=craft_bounds(sim,origin,cell)
 # Preserve cruise/gate ownership until the real trailing craft clears the
 # final paired obstacle. Some saved orbit gates lie inside the final 60 m.
 var start:float=60.0
 if sim.status=="running":
  var last_edge:float=-INF
  for obstacle in sim.obstacles:
   if bool(obstacle.get("pilot_gate",false)) and float(obstacle.get("health",0.0))>0.0:
    last_edge=maxf(last_edge,float(obstacle.position.x)+float(obstacle.radius))
  if is_finite(last_edge):
   var rear_m:float=sim.cargo_position().x-(craft.position.x-origin.x)/cell
   start=minf(start,float(sim.route.get("distance",0.0))-last_edge-rear_m-4.0)
  if start<=0.0 or distance>=start:return {}
 # Pull the actual deck into view before capture without changing any path.
 var weight:float=1.0 if sim.status=="success" else smoothstep(start,minf(radius+8.0,start*.35),distance)
 if weight<=0.0:return {}
 var receiver_box:Rect2=receiver_bounds(receiver)
 var full:Rect2=craft.merge(receiver_box)
 var bounds:Rect2=craft.merge(Rect2(craft.get_center().lerp(full.position,weight),full.size*weight))
 var scene:Vector2=extent*1280.0/maxf(1.0,extent.x)
 var safe:Rect2=Shared.safe_rect(extent,mapper)
 var fit_zoom:float=minf(cruise_zoom,minf((safe.size.x-48.0)/maxf(1.0,full.size.x),(safe.size.y-48.0)/maxf(1.0,full.size.y)))
 var zoom:float=lerpf(cruise_zoom,fit_zoom,weight)
 var center:Vector2=full.get_center()+(scene*.5-safe.get_center())/maxf(.00001,zoom)
 center=cruise_center.lerp(center,weight)
 var fit:Dictionary=Shared.constrain(center,zoom,bounds,safe,scene)
 fit.merge({"bounds":bounds,"craft":craft,"receiver":receiver_box,"full":full,"weight":weight,"zoom_cap":zoom},true)
 return fit

static func constrain(center:Vector2,zoom:float,frame:Dictionary,extent:Vector2,mapper:Control=null) -> Dictionary:
 var scene:Vector2=extent*1280.0/maxf(1.0,extent.x)
 # Runs after every interpolation and resize, ahead of cruise-only constraints.
 return Shared.constrain(center,minf(zoom,float(frame.zoom_cap)),frame.bounds,Shared.safe_rect(extent,mapper),scene)
