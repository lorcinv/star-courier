extends RefCounted
## Read-only camera policy for the explicit free-flight controller only.
## No path, lane, boundary, obstacle ownership, force or simulation mutation.
const Shared=preload("res://scripts/moon_framing_2d.gd")
const Receipt=preload("res://scripts/ground_receipt_framing_2d.gd")
const DisplayMetrics=preload("res://scripts/demo_display_metrics.gd")
const VERSION:String="pilot-free-v1"
const CRUISE_ZOOM:float=.52
const MAX_ZOOM:float=.90
const MIN_BODY_PIXELS:float=48.0
const MIN_MODULE_PIXELS:float=16.0
const LOOKAHEAD_SECONDS:float=.70
const LOOKAHEAD_SLEW:float=240.0
const ARRIVAL_MARGIN_M:float=2.0
const PREVIEW_MARGIN_M:float=18.0

static func applies(route:Dictionary) -> bool:
 return str(route.get("control_version","")) in [VERSION,"pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]

static func is_ground_route(route:Dictionary) -> bool:
 if route.get("control_version") in ["pilot-delivery-v3","pilot-delivery-v6","pilot-delivery-v7","pilot-delivery-v8"]:return route.get("route_kind")=="ground"
 return applies(route) and str(route.get("route_profile",""))=="free-ground-choice-v1" and str(route.get("free_ground_schema",""))=="free-ground-choice-v1"

static func safe_rect(extent:Vector2,mapper:Control=null) -> Rect2:
 var scene:Vector2=extent*1280.0/maxf(1.0,extent.x)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=DisplayMetrics.factor(art)*1280.0/maxf(1.0,art.x)
 # Same native density as the free HUD: top cards end at 108, the event
 # panel begins at height-122. Retain their shadow/gap even when hidden.
 var low:Vector2=Vector2(12,120)*unit
 var high:Vector2=Vector2(scene.x-12.0*unit,scene.y-134.0*unit)
 return Rect2(low,(high-low).max(Vector2.ONE))

static func craft_bounds(sim,origin:Vector2,cell:float) -> Rect2:
 # Track every live cargo-connected body, excluding unrelated debris. Recovered
 # modules retain their exact detached pose after success (or partial capture).
 var low:Vector2=Vector2(INF,INF);var high:Vector2=Vector2(-INF,-INF)
 for body in sim.bodies:
  if not body.parts.any(func(p):return p.type=="cargo" and bool(p.alive) and not bool(p.get("delivered",false))):continue
  for p in body.parts:
   if not bool(p.alive):continue
   var box:Rect2=_part_bounds(sim,p,origin,cell,float(body.angle)+float(p.local_angle))
   low=low.min(box.position);high=high.max(box.end)
 for p in sim.parts.values():
  if not bool(p.get("alive",false)) or not bool(p.get("delivered",false)):continue
  var box:Rect2=_part_bounds(sim,p,origin,cell,float(p.get("world_angle",0.0)))
  low=low.min(box.position);high=high.max(box.end)
 if not low.is_finite():return Receipt.craft_bounds(sim,origin,cell).grow(1.0)
 return Rect2(low,high-low).grow(1.0)

static func _part_bounds(sim,p:Dictionary,origin:Vector2,cell:float,angle:float) -> Rect2:
 # This is the actual square module sizing and live rotation in WorldView2D.
 var half:float=cell*.49*float(p.get("scale",1.0))*(absf(sin(angle))+absf(cos(angle)))
 var at:Vector2=origin+sim.part_world_position(int(p.id))*cell
 return Rect2(at-Vector2.ONE*half,Vector2.ONE*half*2.0)

static func compose(sim,origin:Vector2,cell:float,receiver:Sprite2D,extent:Vector2,mapper:Control=null,previous:Dictionary={},visual_offset:Vector2=Vector2.ZERO) -> Dictionary:
 if not applies(sim.route):return {}
 var craft:Rect2=craft_bounds(sim,origin,cell)
 craft.position+=visual_offset
 var cargo:Vector2=origin+sim.cargo_position()*cell+visual_offset
 var goal:Vector2=origin+Vector2(float(sim.route.distance),float(sim.route.destination_y))*cell
 var radius:float=float(sim.route.delivery_radius)*cell
 # Fit the real capture mouth as well as the entire painted roof/deck. The
 # kiosk's deck lies below the mouth, so its sprite bounds alone are incomplete.
 var mouth:Rect2=Rect2(goal-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
 # One world-pixel safety pad prevents float32 Rect2.merge from rounding the
 # painted far edge inward. This changes framing only, never the collider.
 var receiver_box:Rect2=(mouth.merge(Receipt.receiver_bounds(receiver)) if receiver!=null else mouth).grow(1.0)
 var velocity:Vector2=Vector2.ZERO
 for body in sim.bodies:
  if body.parts.any(func(p):return p.type=="cargo" and bool(p.alive)):
   velocity=body.velocity;break
 var scene:Vector2=extent*1280.0/maxf(1.0,extent.x)
 var safe:Rect2=safe_rect(extent,mapper)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=DisplayMetrics.factor(art)*1280.0/maxf(1.0,art.x)
 var frame:Dictionary=compose_bounds(craft,cargo,goal,receiver_box,radius,velocity,cell,scene,safe,float(sim.elapsed),str(sim.status),previous,unit)
 frame.merge({"viewport_extent":extent,"art_extent":art,"visual_offset":visual_offset},true)
 return frame

static func compose_bounds(craft:Rect2,cargo:Vector2,goal:Vector2,receiver:Rect2,radius:float,velocity:Vector2,cell:float,scene:Vector2,safe:Rect2,elapsed:float,status:String,previous:Dictionary={},unit:float=1.0) -> Dictionary:
 var inner:Rect2=safe.grow(-Shared.INSET)
 var readable_zoom:float=maxf(MIN_BODY_PIXELS*unit/maxf(1.0,minf(craft.size.x,craft.size.y)),MIN_MODULE_PIXELS*unit/maxf(1.0,cell*.98))
 var cruise:float=minf(MAX_ZOOM,maxf(CRUISE_ZOOM,readable_zoom))
 cruise=minf(cruise,minf(inner.size.x*.72/maxf(1.0,craft.size.x),inner.size.y*.72/maxf(1.0,craft.size.y)))
 cruise=maxf(.00001,cruise)
 # Signed X AND Y velocity choose the lead. Reverse travel needs no mandatory
 # forward anchor; abrupt reversals are slewed against simulation elapsed time.
 var limit:Vector2=Vector2(minf(160.0*unit,inner.size.x*.20),minf(80.0*unit,inner.size.y*.18))/cruise
 var lead:Vector2=(velocity*cell*LOOKAHEAD_SECONDS).clamp(-limit,limit)
 if not previous.is_empty() and elapsed>=float(previous.get("elapsed",elapsed)):
  var old:Vector2=previous.get("lookahead",lead)
  var dt:float=clampf(elapsed-float(previous.get("elapsed",elapsed)),0.0,.1)
  lead=old.move_toward(lead,LOOKAHEAD_SLEW*unit/cruise*dt) if status=="running" else old
  lead=lead.clamp(-limit,limit)
 var distance:float=cargo.distance_to(goal)
 var arrival_radius:float=radius+ARRIVAL_MARGIN_M*cell
 var preview_radius:float=arrival_radius+PREVIEW_MARGIN_M*cell
 var weight:float=1.0-smoothstep(arrival_radius,preview_radius,distance)
 var full:Rect2=craft.merge(receiver)
 var fit_zoom:float=minf(cruise,minf(inner.size.x/maxf(1.0,full.size.x),inner.size.y/maxf(1.0,full.size.y)))
 var zoom:float=maxf(.00001,lerpf(cruise,fit_zoom,weight))
 var focus:Vector2=(craft.get_center()+lead).lerp(full.get_center(),weight)
 var center:Vector2=focus+(scene*.5-safe.get_center())/zoom
 # Arrival is a geometric near-field interval on ANY side of the receiver.
 # Never interpolate required bounds: when arrival starts, every actual frame
 # must contain the whole craft, mouth, roof and deck, even while camera eases.
 var arrival:bool=distance<=arrival_radius
 var required:Rect2=full if arrival else craft
 var fit:Dictionary=Shared.constrain(center,zoom,required,safe,scene)
 fit.merge({"craft":craft,"receiver":receiver,"full":full,"bounds":required,"craft_safe":safe,"scene_size":scene,"lookahead":lead,"elapsed":elapsed,"arrival":arrival,"approach_weight":weight,"distance_m":distance/cell,"arrival_radius_m":arrival_radius/cell,"minimum_readable_zoom":readable_zoom,"readability_limited":float(fit.zoom)+.000001<readable_zoom,"policy":"free-bidirectional-whole-arrival-v2"},true)
 return fit

static func constrain(center:Vector2,zoom:float,frame:Dictionary,extent:Vector2,mapper:Control=null) -> Dictionary:
 var scene:Vector2=extent*1280.0/maxf(1.0,extent.x)
 # Project after EVERY world-camera interpolation and resize. A readable floor
 # applies when geometrically possible; containment wins for oversized builds
 # or receiver art, with an explicit diagnostic rather than a false guarantee.
 var fit:Dictionary=Shared.constrain(center,maxf(zoom,float(frame.minimum_readable_zoom)),frame.bounds,safe_rect(extent,mapper),scene)
 fit.readability_limited=float(fit.zoom)+.000001<float(frame.minimum_readable_zoom)
 return fit

static func release_frame(craft:Rect2,launch_center:Vector2,launch_zoom:float,frame:Dictionary,progress:float) -> Dictionary:
 # Blend screen anchors, not a far camera center multiplied by changing zoom.
 var amount:float=clampf(progress,0.0,1.0)
 var zoom:float=lerpf(launch_zoom,float(frame.zoom),amount)
 var scene:Vector2=frame.scene_size
 var from:Vector2=Shared.project(craft.get_center(),launch_center,launch_zoom,scene)
 var to:Vector2=Shared.project(craft.get_center(),frame.center,float(frame.zoom),scene)
 var center:Vector2=craft.get_center()+(scene*.5-from.lerp(to,amount))/maxf(.00001,zoom)
 return Shared.constrain(center,zoom,frame.bounds,frame.craft_safe,scene)
