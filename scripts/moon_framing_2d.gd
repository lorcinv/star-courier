extends RefCounted
## Read-only presentation policy. Circles outside this frame retain their real
## art/collision size. Boundary cues are warnings, never visibility substitutes.
const ZOOM:float=.30
const MIN_RUNNING_ZOOM:float=.24
const MIN_ASCENT_ZOOM:float=.14
const ASCENT_LOOKAHEAD:float=6.0
const LOOKAHEAD:float=3.5
const MAX_CUES:int=6
const WIDTH:float=1280.0
const INSET:float=18.0

static func safe_rect(extent:Vector2,mapper:Control=null) -> Rect2:
 var scene:Vector2=extent*WIDTH/maxf(1.0,extent.x)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=clampf(floorf(art.y/720.0),1.0,3.0)*WIDTH/maxf(1.0,art.x)
 # Existing native HUD: left cards 280, top strip 96, event/control band 134.
 # The full craft, cues and nearest physical faces use this unobscured region.
 var low:Vector2=Vector2(12,144)*unit
 var high:Vector2=Vector2(scene.x-12.0*unit,scene.y-146.0*unit)
 return Rect2(low,(high-low).max(Vector2.ONE))

static func craft_bounds(sim,origin:Vector2,cell:float) -> Rect2:
 var body:Dictionary={}
 for p in sim.parts.values():
  if p.type=="cargo" and bool(p.alive):body=sim.body_for_part(int(p.id));break
 var low:Vector2=Vector2(INF,INF);var high:Vector2=Vector2(-INF,-INF)
 for p in body.get("parts",[]):
  if not bool(p.alive):continue
  var angle:float=float(body.angle)+float(p.local_angle)
  var half:float=cell*.49*float(p.get("scale",1.0))*(absf(sin(angle))+absf(cos(angle)))
  var at:Vector2=origin+sim.part_world_position(int(p.id))*cell
  low=low.min(at-Vector2.ONE*half);high=high.max(at+Vector2.ONE*half)
 if not low.is_finite():
  var at:Vector2=origin+sim.cargo_position()*cell
  return Rect2(at-Vector2.ONE*cell*.49,Vector2.ONE*cell*.98)
 return Rect2(low,high-low)

static func compose(sim,origin:Vector2,cell:float,extent:Vector2,mapper:Control,retained_zoom:float=ZOOM,previous:Dictionary={}) -> Dictionary:
 var craft:Rect2=craft_bounds(sim,origin,cell)
 var safe:Rect2=safe_rect(extent,mapper)
 var scene:Vector2=extent*WIDTH/maxf(1.0,extent.x)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=clampf(floorf(art.y/720.0),1.0,3.0)*WIDTH/maxf(1.0,art.x)
 # Existing Moon cue moves to the unused top-left HUD slot in this
 # candidate. This opens the left-center playfield without hiding any data.
 var craft_safe:Rect2=safe
 # Forward geometry may use the area above the controls even while a
 # receipt occupies the lower-left. Test exact conservative occluders below.
 var geometry_safe:Rect2=safe
 geometry_safe.size.y=scene.y-76.0*unit-geometry_safe.position.y
 var occluders:Array=[Rect2(Vector2(20.0*unit,scene.y-134.0*unit),Vector2(444,42)*unit)]
 var velocity:Vector2=Vector2.ZERO
 for body in sim.bodies:
  if body.parts.any(func(p):return p.type=="cargo" and bool(p.alive)):velocity=body.velocity;break
 var cargo_m:Vector2=sim.cargo_position()
 var body_m:Rect2=Rect2((craft.position-origin)/cell,craft.size/cell)
 var top_m:float=body_m.position.y;var bottom_m:float=body_m.end.y
 var last_gate_right:float=-INF
 for h in sim.obstacles:
  if bool(h.get("pilot_gate",false)):last_gate_right=maxf(last_gate_right,float(h.position.x)+float(h.radius))
 var ascent_end:float=last_gate_right+12.0
 var recovery_end:float=maxf(ascent_end+60.0,float(sim.route.get("moon_approach_start",560.0)))
 var ascent:bool=is_finite(last_gate_right) and body_m.position.x<ascent_end
 var recovery:float=smoothstep(ascent_end,recovery_end,body_m.position.x) if is_finite(last_gate_right) else 1.0
 var phase:String="ascent" if ascent else ("return_to_lunar" if recovery<1.0 else "lunar")
 # Only the nearest still-required paired aperture owns ascent framing.
 # Target offset slew below makes ownership changes continuous on screen.
 var next_gate:int=-1;var next_gate_x:float=INF
 if ascent:
  for h in sim.obstacles:
   if bool(h.get("pilot_gate",false)) and float(h.health)>0 and float(h.position.x)+float(h.radius)>=body_m.position.x-4.0 and float(h.position.x)<next_gate_x:
    next_gate=int(h.get("gate_index",-1));next_gate_x=float(h.position.x)
 var focus_points:Array=[]
 var horizon:float=maxf(90.0,absf(velocity.x)*ASCENT_LOOKAHEAD) if ascent else maxf(50.0,velocity.length()*LOOKAHEAD)
 var right_m:float=body_m.end.x
 for h in sim.obstacles:
  if float(h.health)<=0:continue
  var radius:float=float(h.radius)
  var dx:float=float(h.position.x)-radius-body_m.end.x
  if h.position.x+radius<body_m.position.x-40.0 or dx>horizon:continue
  if ascent:
   if not bool(h.get("pilot_gate",false)) or int(h.get("gate_index",-1))!=next_gate:continue
   # The saved paired-gate index is used only to choose the physical face.
   # Fit nine samples of the inward-facing quarter arc, with 3.5 m padding.
   # No outer station hardware or future complete-circle union is fitted.
   var pair_center_y:float=float(h.position.y)
   for other in sim.obstacles:
    if bool(other.get("pilot_gate",false)) and int(other.get("gate_index",-1))==int(h.get("gate_index",-2)) and other!=h:
     pair_center_y=(float(h.position.y)+float(other.position.y))*.5;break
   var upper:bool=float(h.position.y)<pair_center_y
   var weight:float=smoothstep(horizon,horizon*.65,maxf(0.0,dx))
   weight*=1.0-smoothstep(0.0,40.0,maxf(0.0,body_m.position.x-(float(h.position.x)+radius)))
   for sample in 9:
    var angle:float=(PI*.25 if upper else -PI*.75)+PI*.5*float(sample)/8.0
    var point:Vector2=Vector2(h.position)+Vector2.from_angle(angle)*radius
    var weighted:Vector2=cargo_m.lerp(point,weight)
    top_m=minf(top_m,weighted.y-3.5*weight);bottom_m=maxf(bottom_m,weighted.y+3.5*weight)
    right_m=maxf(right_m,weighted.x+1.0*weight)
    focus_points.append({"point_m":point,"weight":weight,"required_gate":true})
  else:
   if bool(h.get("pilot_gate",false)):continue
   # Exterior backs cannot dictate the approach camera before capture.
   if str(h.get("moon_role",""))=="airlock" and h.position.x-radius>float(sim.route.distance)+3.0:continue
   var point:Vector2=closest_circle_point(body_m,h)
   var weight:float=smoothstep(horizon,horizon*.38,maxf(0.0,dx))
   weight*=1.0-smoothstep(0.0,40.0,maxf(0.0,body_m.position.x-(float(h.position.x)+radius)))
   var y:float=lerpf(cargo_m.y,point.y,weight)
   top_m=minf(top_m,y-1.0*weight);bottom_m=maxf(bottom_m,y+1.0*weight)
   focus_points.append({"point_m":point,"weight":weight})
 var focus_safe:Rect2=safe.grow(-28.0) if ascent else geometry_safe
 var focus_zoom:float=focus_safe.size.y/maxf(1.0,(bottom_m-top_m)*cell)
 if ascent:focus_zoom=minf(focus_zoom,(safe.end.x-INSET-190.0)/maxf(1.0,(right_m-body_m.get_center().x)*cell))
 var lunar_limit:float=float(previous.get("lunar_limit",ZOOM))
 if not ascent:lunar_limit=minf(lunar_limit,maxf(MIN_RUNNING_ZOOM,focus_zoom))
 var ascent_exit_zoom:float=float(previous.get("ascent_exit_zoom",retained_zoom))
 var zoom:float
 if ascent:
  zoom=minf(retained_zoom,maxf(MIN_ASCENT_ZOOM,focus_zoom))
  ascent_exit_zoom=zoom
 else:
  # One distance-based recovery after the last required gate. It freezes
  # with the simulation, restores coherently, and cannot hunt per obstacle.
  if previous.is_empty():ascent_exit_zoom=lunar_limit
  zoom=lerpf(ascent_exit_zoom,lunar_limit,recovery)
 zoom=minf(ZOOM,minf(zoom,minf(craft_safe.size.x*.56/maxf(1.0,craft.size.x),craft_safe.size.y*.70/maxf(1.0,craft.size.y))))
 zoom=maxf(.00001,zoom)
 var anchor:Vector2=Vector2(maxf(190.0,safe.position.x+INSET+craft.size.x*zoom*.5),safe.get_center().y)
 var center:Vector2=craft.get_center()+(scene*.5-anchor)/zoom
 var focus_y:float=origin.y+(top_m+bottom_m)*.5*cell+(scene.y*.5-focus_safe.get_center().y)/zoom
 # Geometry contributes a continuous distance-weighted vertical bias. The
 # 52px player dead band still applies when no obstacle constrains the shot.
 if focus_points.is_empty() and not previous.is_empty() and previous.get("scene_size",Vector2.ZERO)==scene:
  var old_y:float=float(previous.center.y)
  center.y=old_y+signf(center.y-old_y)*maxf(0.0,absf(center.y-old_y)-26.0/zoom)
 else:center.y=focus_y
 # Bound only geometry-induced offset change, while retaining real cargo
 # movement. Dropped/destroyed groups cannot snap the tracking target.
 var focus_offset:float=center.y-craft.get_center().y
 if not previous.is_empty() and previous.get("scene_size",Vector2.ZERO)==scene:
  var dt:float=clampf(float(sim.elapsed)-float(previous.get("elapsed",sim.elapsed)),0.0,.1)
  focus_offset=move_toward(float(previous.get("focus_offset",focus_offset)),focus_offset,72.0/maxf(.00001,zoom)*dt)
  center.y=craft.get_center().y+focus_offset
 if sim.status=="success":
  # The terminal shot keeps the actual capture aperture centered vertically.
  # Normal world easing performs this single receipt adjustment; no new clock.
  center.y=origin.y+float(sim.route.destination_y)*cell+(scene.y*.5-safe.get_center().y)/zoom
  focus_offset=center.y-craft.get_center().y
 var fit:Dictionary=constrain(center,zoom,craft,craft_safe,scene)
 fit.merge({"craft":craft,"safe":safe,"craft_safe":craft_safe,"geometry_safe":geometry_safe,"occluders":occluders,"viewport_extent":extent,"art_extent":art,"scene_size":scene,"velocity":velocity,"forward_m":maxf(60.0,velocity.length()*LOOKAHEAD),"receipt":sim.status=="success","elapsed":sim.elapsed,"focus_offset":focus_offset,"focus_points":focus_points,"phase":phase,"ascent_exit_zoom":ascent_exit_zoom,"lunar_limit":lunar_limit,"recovery":recovery,"policy":"readable-body/required-ascent-arcs-v3"},true)
 return fit

static func constrain(center:Vector2,zoom:float,craft:Rect2,safe:Rect2,scene:Vector2) -> Dictionary:
 # This final, local containment constraint applies only to the player. A new
 # gate cannot cause a hard recenter. Resize/large rotation may require fit.
 var inner:Rect2=safe.grow(-INSET)
 zoom=minf(zoom,minf(inner.size.x/maxf(1.0,craft.size.x),inner.size.y/maxf(1.0,craft.size.y)))
 zoom=maxf(.00001,zoom)
 var low:Vector2=craft.end-(inner.end-scene*.5)/zoom
 var high:Vector2=craft.position-(inner.position-scene*.5)/zoom
 for axis in [0,1]:
  center[axis]=(low[axis]+high[axis])*.5 if low[axis]>high[axis] else clampf(center[axis],low[axis],high[axis])
 return {"center":center,"zoom":zoom}

static func project(at:Vector2,center:Vector2,zoom:float,scene:Vector2) -> Vector2:
 return (at-center)*zoom+scene*.5

static func closest_circle_point(craft_m:Rect2,hazard:Dictionary) -> Vector2:
 var at:Vector2=hazard.position
 var nearest:Vector2=at.clamp(craft_m.position,craft_m.end)
 var direction:Vector2=(nearest-at).normalized()
 if direction==Vector2.ZERO:direction=(craft_m.get_center()-at).normalized()
 if direction==Vector2.ZERO:direction=Vector2.UP
 return at+direction*float(hazard.radius)

static func ray_edge(from:Vector2,toward:Vector2,box:Rect2) -> Vector2:
 var start:Vector2=from.clamp(box.position+Vector2.ONE,box.end-Vector2.ONE)
 var direction:Vector2=toward-start
 var t:float=1.0
 for axis in [0,1]:
  if direction[axis]>0:t=minf(t,(box.end[axis]-start[axis])/direction[axis])
  elif direction[axis]<0:t=minf(t,(box.position[axis]-start[axis])/direction[axis])
 return start+direction*t

static func point_clear(point:Vector2,frame:Dictionary) -> bool:
 if not frame.geometry_safe.has_point(point):return false
 for box in frame.occluders:
  if box.has_point(point):return false
 return true

static func visibility(sim,origin:Vector2,cell:float,frame:Dictionary,center:Vector2,zoom:float) -> Dictionary:
 var safe:Rect2=frame.safe;var scene:Vector2=frame.scene_size
 var craft:Rect2=frame.craft;var craft_m:Rect2=Rect2((craft.position-origin)/cell,craft.size/cell)
 var cargo_screen:Vector2=project(craft.get_center(),center,zoom,scene)
 var visible_samples:Array=[];var groups:Dictionary={};var cues:Array=[]
 var horizon:float=float(frame.forward_m)
 for index in sim.obstacles.size():
  var h:Dictionary=sim.obstacles[index]
  if float(h.health)<=0 or h.position.x+float(h.radius)<craft_m.position.x-4.0 or h.position.x-float(h.radius)>craft_m.end.x+horizon:continue
  var point_m:Vector2=closest_circle_point(craft_m,h)
  var nearest:Vector2=point_m.clamp(craft_m.position,craft_m.end)
  var distance:float=point_m.distance_to(nearest)
  if distance>horizon:continue
  var point:Vector2=project(origin+point_m*cell,center,zoom,scene)
  var circle_center:Vector2=project(origin+Vector2(h.position)*cell,center,zoom,scene)
  var radius:float=float(h.radius)*cell*zoom
  var circle_box:Rect2=Rect2(circle_center-Vector2.ONE*radius,Vector2.ONE*radius*2)
  var inside:bool=point_clear(point,frame)
  var visible_arc_samples:int=0
  for sample in 32:
   var arc:Vector2=circle_center+Vector2.from_angle(TAU*sample/32.0)*radius
   if point_clear(arc,frame):visible_arc_samples+=1
  var inward_visible:int=0
  if bool(h.get("pilot_gate",false)):
   var pair_center_y:float=float(h.position.y)
   for other in sim.obstacles:
    if bool(other.get("pilot_gate",false)) and int(other.get("gate_index",-1))==int(h.get("gate_index",-2)) and other!=h:
     pair_center_y=(float(h.position.y)+float(other.position.y))*.5;break
   for sample in 9:
    var angle:float=(PI*.25 if float(h.position.y)<pair_center_y else -PI*.75)+PI*.5*float(sample)/8.0
    if point_clear(circle_center+Vector2.from_angle(angle)*radius,frame):inward_visible+=1
  var item:Dictionary={"inward_arc_visible_samples":inward_visible,"index":index,"id":str(h.get("id","gate-"+str(index))),"point_m":point_m,"point":point,"distance_m":distance,"visible_arc_samples":visible_arc_samples,"nearest_visible":inside,"complete_circle_visible":safe.encloses(circle_box),"circle_box":circle_box}
  visible_samples.append(item)
  if inside:continue
  var direction:Vector2=point-cargo_screen
  var quadrant:int=(0 if direction.x>=0 else 2)+(0 if direction.y<0 else 1)
  if not groups.has(quadrant) or distance<float(groups[quadrant].distance_m):groups[quadrant]=item
 for key in groups:
  var item:Dictionary=groups[key].duplicate()
  item.kind="hazard";item.screen=ray_edge(cargo_screen,item.point,safe.grow(-INSET))
  item.direction=(item.point-item.screen).normalized()
  if item.direction==Vector2.ZERO:item.direction=(item.point-cargo_screen).normalized()
  cues.append(item)
 # Saved failure boundaries are not decorative regolith. They get distinct
 # ticks only when their actual distance enters this same bounded horizon.
 var limit:float=float(sim.route.get("boundary_y",230.0))
 for side in [-1,1]:
  var y:float=limit*side
  var distance:float=absf(y-(craft_m.position.y if side<0 else craft_m.end.y))
  if distance>horizon:continue
  var point:Vector2=project(origin+Vector2(craft_m.get_center().x,y)*cell,center,zoom,scene)
  cues.append({"on_screen":safe.has_point(point),"span":Vector2(safe.position.x+INSET,safe.end.x-INSET),"kind":"boundary","id":"upper-boundary" if side<0 else "lower-boundary","distance_m":distance,"point":point,"screen":ray_edge(cargo_screen,point,safe.grow(-INSET)),"direction":Vector2(0,side)})
 return {"cues":cues.slice(0,MAX_CUES),"hazards":visible_samples,"maximum_cues":MAX_CUES,"coverage":"nearest physical point visibility and edge warning are distinct"}
