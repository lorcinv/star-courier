extends RefCounted
## Ordinary paired ground/ascent corridors. Presentation only; saved physics and
## geometry remain authoritative. Share the reviewed Moon body/arc primitives,
## but do not change Moon composition, lunar limits, hardware, or warnings.
const Shared=preload("res://scripts/moon_framing_2d.gd")
const WIDTH:float=1280.0
const MIN_ZOOM:float=.175
const PREVIEW_SECONDS:float=3.75
const BLEND_SECONDS:float=6.0
const PADDING_M:float=1.5

static func applies(route:Dictionary) -> bool:
 var version:String=str(route.get("control_version",""))
 var encounter:Variant=route.get("pirate_encounter")
 var pirate_ascent:bool=version in ["pilot-pirate-drill-v1","pilot-pirate-drill-v2"] and route.get("pilot_profile")==version and encounter is Dictionary and encounter.get("schema")=="pirate-ascent-encounter-v1"
 return (version in ["pilot-v2","pilot-v3"] or pirate_ascent) and str(route.get("route_kind","")) not in ["moon","wormhole"] and not route.has("moon_schema") and not route.has("wormhole_portal") and not route.get("pilot_gates",[]).is_empty()

static func safe_rect(extent:Vector2,mapper:Control=null) -> Rect2:
 var scene:Vector2=extent*WIDTH/maxf(1.0,extent.x)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=clampf(floorf(art.y/720.0),1.0,3.0)*WIDTH/maxf(1.0,art.x)
 # Three-row resources end at 116 native UI units. Receipt moved to right.
 return Rect2(Vector2(12,124)*unit,Vector2(scene.x-24.0*unit,scene.y-188.0*unit))

static func compose(sim,origin:Vector2,cell:float,extent:Vector2,mapper:Control,retained_zoom:float,previous:Dictionary={}) -> Dictionary:
 var craft:Rect2=Shared.craft_bounds(sim,origin,cell)
 var body_m:Rect2=Rect2((craft.position-origin)/cell,craft.size/cell)
 var safe:Rect2=safe_rect(extent,mapper)
 var scene:Vector2=extent*WIDTH/maxf(1.0,extent.x)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=clampf(floorf(art.y/720.0),1.0,3.0)*WIDTH/maxf(1.0,art.x)
 var geometry_safe:Rect2=Rect2(Vector2(12,108)*unit,Vector2(scene.x-24.0*unit,scene.y-172.0*unit))
 var occluders:Array=[Rect2(Vector2(scene.x-464.0*unit,scene.y-134.0*unit),Vector2(444,48)*unit),Rect2(Vector2(scene.x-304.0*unit,20.0*unit),Vector2(288,100)*unit)]
 var velocity:Vector2=Vector2.ZERO
 for body in sim.bodies:
  if body.parts.any(func(p):return p.type=="cargo" and bool(p.alive)):velocity=body.velocity;break
 var cargo_m:Vector2=sim.cargo_position()
 var next_gate:int=-1;var next_x:float=INF
 for h in sim.obstacles:
  if bool(h.get("pilot_gate",false)) and float(h.health)>0 and float(h.position.x)+float(h.radius)>=body_m.position.x-4.0 and float(h.position.x)<next_x:
   next_gate=int(h.get("gate_index",-1));next_x=float(h.position.x)
 var start_horizon:float=maxf(75.0,maxf(0.0,velocity.x)*BLEND_SECONDS)
 var full_horizon:float=maxf(50.0,maxf(0.0,velocity.x)*PREVIEW_SECONDS)
 var low:Vector2=body_m.position;var high:Vector2=body_m.end
 var points:Array=[]
 for h in sim.obstacles:
  if not bool(h.get("pilot_gate",false)) or int(h.get("gate_index",-1))!=next_gate or float(h.health)<=0:continue
  var radius:float=float(h.radius)
  var dx:float=float(h.position.x)-radius-body_m.end.x
  if dx>start_horizon:continue
  var pair_y:float=float(h.position.y)
  for other in sim.obstacles:
   if bool(other.get("pilot_gate",false)) and int(other.get("gate_index",-1))==next_gate and other!=h:
    pair_y=(float(h.position.y)+float(other.position.y))*.5;break
  var weight:float=smoothstep(start_horizon,full_horizon,maxf(0.0,dx))
  weight*=1.0-smoothstep(0.0,4.0,maxf(0.0,body_m.position.x-(float(h.position.x)+radius)))
  for sample in 9:
   var angle:float=(PI*.25 if float(h.position.y)<pair_y else -PI*.75)+PI*.5*float(sample)/8.0
   var point:Vector2=Vector2(h.position)+Vector2.from_angle(angle)*radius
   var weighted:Vector2=cargo_m.lerp(point,weight)
   low=low.min(weighted-Vector2.ONE*PADDING_M*weight)
   high=high.max(weighted+Vector2.ONE*PADDING_M*weight)
   points.append({"point_m":point,"weight":weight,"required_gate":true})
 var focus_safe:Rect2=geometry_safe.grow(-22.0)
 var required_zoom:float=focus_safe.size.y/maxf(1.0,(high.y-low.y)*cell)
 required_zoom=minf(required_zoom,(safe.end.x-Shared.INSET-190.0)/maxf(1.0,(high.x-body_m.get_center().x)*cell))
 # Retain a bounded pullback like ordinary speed-based framing. No gate-change
 # zoom-in/zoom-out cycle; restart derives an immediate shot from saved state.
 var zoom:float=minf(retained_zoom,maxf(MIN_ZOOM,required_zoom))
 zoom=minf(zoom,minf(safe.size.x*.56/maxf(1.0,craft.size.x),safe.size.y*.82/maxf(1.0,craft.size.y)))
 zoom=maxf(.00001,zoom)
 var anchor:Vector2=Vector2(maxf(190.0,safe.position.x+Shared.INSET+craft.size.x*zoom*.5),safe.get_center().y)
 var center:Vector2=craft.get_center()+(scene*.5-anchor)/zoom
 if not points.is_empty():center.y=origin.y+(low.y+high.y)*.5*cell+(scene.y*.5-focus_safe.get_center().y)/zoom
 elif not previous.is_empty() and previous.get("scene_size",Vector2.ZERO)==scene:
  var old_y:float=float(previous.center.y)
  center.y=old_y+signf(center.y-old_y)*maxf(0.0,absf(center.y-old_y)-26.0/zoom)
 var offset:float=center.y-craft.get_center().y
 if not previous.is_empty() and previous.get("scene_size",Vector2.ZERO)==scene:
  var dt:float=clampf(float(sim.elapsed)-float(previous.get("elapsed",sim.elapsed)),0.0,.1)
  offset=move_toward(float(previous.get("focus_offset",offset)),offset,144.0/zoom*dt)
  center.y=craft.get_center().y+offset
 var fit:Dictionary=Shared.constrain(center,zoom,craft,safe,scene)
 fit.merge({"craft":craft,"safe":safe,"craft_safe":safe,"geometry_safe":geometry_safe,"occluders":occluders,"scene_size":scene,"viewport_extent":extent,"art_extent":art,"velocity":velocity,"forward_m":start_horizon,"elapsed":sim.elapsed,"focus_offset":offset,"focus_points":points,"next_gate":next_gate,"required_zoom":required_zoom,"bounded_geometry_fit":required_zoom>=MIN_ZOOM,"provisional_review_body_pixels":40.0*art.x/WIDTH,"body_below_provisional_review_floor":minf(craft.size.x,craft.size.y)*zoom<40.0,"policy":"ordinary-required-inward-arcs-v1"},true)
 return fit

static func measure(sim,origin:Vector2,cell:float,frame:Dictionary,center:Vector2,zoom:float,active_occluders:Variant=null) -> Dictionary:
 if active_occluders is Array:
  frame=frame.duplicate();frame.occluders=active_occluders
 var body:Rect2=frame.craft
 var body_m:Rect2=Rect2((body.position-origin)/cell,body.size/cell)
 var results:Array=[]
 for index in sim.obstacles.size():
  var h:Dictionary=sim.obstacles[index]
  if not bool(h.get("pilot_gate",false)) or float(h.health)<=0:continue
  var middle:float=float(h.position.y)
  for other in sim.obstacles:
   if bool(other.get("pilot_gate",false)) and int(other.get("gate_index",-1))==int(h.get("gate_index",-2)) and other!=h:
    middle=(float(h.position.y)+float(other.position.y))*.5;break
  var upper:bool=float(h.position.y)<middle
  var samples:Array=[];var visible:int=0
  for sample in 9:
   var angle:float=(PI*.25 if upper else -PI*.75)+PI*.5*float(sample)/8.0
   var at_m:Vector2=Vector2(h.position)+Vector2.from_angle(angle)*float(h.radius)
   var point:Vector2=Shared.project(origin+at_m*cell,center,zoom,frame.scene_size)
   var clear:bool=Shared.point_clear(point,frame)
   if clear:visible+=1
   samples.append({"world_m":at_m,"screen":point,"visible":clear})
  var nearest_m:Vector2=Shared.closest_circle_point(body_m,h)
  var nearest:Vector2=Shared.project(origin+nearest_m*cell,center,zoom,frame.scene_size)
  var horizontal:float=float(h.position.x)-float(h.radius)-body_m.end.x
  var nearest_distance:float=nearest_m.distance_to(nearest_m.clamp(body_m.position,body_m.end))
  results.append({"index":index,"gate":int(h.get("gate_index",-1)),"side":"upper" if upper else "lower","inward_visible":visible,"inward_total":9,"samples":samples,"nearest_m":nearest_m,"nearest_visible":Shared.point_clear(nearest,frame),"nearest_distance_m":nearest_distance,"first_horizontal_overlap":horizontal<=0.0,"horizontal_clearance_m":horizontal,"horizontal_seconds":horizontal/maxf(.001,float(frame.velocity.x)),"euclidean_seconds":nearest_distance/maxf(.001,Vector2(frame.velocity).length())})
 var box:Rect2=Rect2(Shared.project(body.position,center,zoom,frame.scene_size),body.size*zoom)
 var clear:bool=frame.craft_safe.encloses(box)
 for box_hud in frame.occluders:
  if box_hud.intersects(box):clear=false
 return {"craft":box,"craft_clear":clear,"zoom":zoom,"minimum_zoom":MIN_ZOOM,"bounded_geometry_fit":frame.bounded_geometry_fit,"faces":results}
