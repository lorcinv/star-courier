extends RefCounted
## Private v2-only presentation experiment. Never selected for any v1 snapshot.
## Preserve world-to-physics scale; refuse the readability guarantee outside the
## fixed budget rather than shrinking the craft to fit arbitrary future hazards.
const Shared=preload("res://scripts/moon_framing_2d.gd")
const Legacy=preload("res://scripts/corridor_framing_2d.gd")
const VERSION="seeded-offers-v2-readable-a1"
const POLICY="readable-fixed-envelope-a1"
const ZOOM:float=.28
const ANCHOR_X:float=60.0
static func applies(route:Dictionary) -> bool:
 # Keep the original v2/v3 domain explicit when Legacy gains new families.
 if not str(route.get("control_version","")) in ["pilot-v2","pilot-v3"]:return false
 var metadata:Variant=route.get("generation")
 if not metadata is Dictionary or metadata.get("version")!=VERSION or metadata.get("policy")!=POLICY:return false
 # Forward-edge framing belongs only to the reviewed ordinary families.
 # Reject special/pursuit identities even when called outside Economy.
 var kind:Variant=metadata.get("kind")
 var route_kind:Variant=route.get("route_kind","")
 if not kind is String or not route_kind is String:return false
 return ((kind=="ground" and route_kind=="ground") or (kind=="ascent" and route_kind=="")) and Legacy.applies(route)
static func compose(sim,origin:Vector2,cell:float,extent:Vector2,mapper:Control=null,previous:Dictionary={}) -> Dictionary:
 var craft:Rect2=Shared.craft_bounds(sim,origin,cell)
 var body_m:Rect2=Rect2((craft.position-origin)/cell,craft.size/cell)
 var scene:Vector2=extent*1280.0/maxf(1.0,extent.x)
 var safe:Rect2=Legacy.safe_rect(extent,mapper)
 var art:Vector2=mapper.display_rect.size if mapper!=null else extent
 var unit:float=clampf(floorf(art.y/720.0),1.0,3.0)*1280.0/maxf(1.0,art.x)
 var geometry:Rect2=Rect2(Vector2(12,124)*unit,Vector2(scene.x-24.0*unit,scene.y-188.0*unit))
 var velocity:Vector2=sim._cargo_body().get("velocity",Vector2.ZERO)
 var gate_index:int=-1;var next_x:float=INF
 for h in sim.obstacles:
  if bool(h.get("pilot_gate",false)) and float(h.health)>0 and float(h.position.x)+float(h.radius)>=body_m.position.x-4.0 and float(h.position.x)<next_x:
   gate_index=int(h.get("gate_index",-1));next_x=float(h.position.x)
 var low:float=body_m.position.y;var high:float=body_m.end.y
 var points:Array=[]
 var horizon:float=80.0
 for h in sim.obstacles:
  if int(h.get("gate_index",-2))!=gate_index or float(h.health)<=0:continue
  var dx:float=float(h.position.x)-float(h.radius)-body_m.end.x
  if dx>horizon:continue
  var pair_y:float=0.0;var pair_count:int=0
  for other in sim.obstacles:
   if int(other.get("gate_index",-2))==gate_index:pair_y+=float(other.position.y);pair_count+=1
  pair_y/=maxi(1,pair_count)
  var weight:float=smoothstep(horizon,55.0,maxf(0.0,dx))
  weight*=1.0-smoothstep(0.0,4.0,maxf(0.0,body_m.position.x-(float(h.position.x)+float(h.radius))))
  for sample in 9:
   var angle:float=(PI*.25 if float(h.position.y)<pair_y else -PI*.75)+PI*.5*float(sample)/8.0
   var at:Vector2=Vector2(h.position)+Vector2.from_angle(angle)*float(h.radius)
   var y:float=lerpf(sim.cargo_position().y,at.y,weight)
   low=minf(low,y-1.0*weight);high=maxf(high,y+1.0*weight)
   points.append({"point_m":at,"weight":weight,"required_gate":true})
 # The new envelope never uses speed pullback or a gate-dependent zoom floor.
 # Oversized connected craft alone may require containment; that is reported.
 var zoom:float=minf(ZOOM,minf(safe.size.x*.56/maxf(1.0,craft.size.x),safe.size.y*.82/maxf(1.0,craft.size.y)))
 var anchor:Vector2=Vector2(maxf(ANCHOR_X,safe.position.x+Shared.INSET+craft.size.x*zoom*.5),safe.get_center().y)
 var center:Vector2=craft.get_center()+(scene*.5-anchor)/zoom
 var wanted_y:float=origin.y+(low+high)*.5*cell+(scene.y*.5-(geometry.get_center().y-16.0))/zoom
 var offset:float=wanted_y-craft.get_center().y
 if not previous.is_empty() and previous.get("scene_size",Vector2.ZERO)==scene:
  var dt:float=clampf(float(sim.elapsed)-float(previous.get("elapsed",sim.elapsed)),0,.1)
  offset=move_toward(float(previous.get("focus_offset",offset)),offset,96.0/zoom*dt)
 center.y=craft.get_center().y+offset
 var fit:Dictionary=Shared.constrain(center,zoom,craft,safe,scene)
 var geometry_speed_limit:float=((geometry.end.x-1.0-anchor.x)/(cell*ZOOM)-body_m.size.x*.5-5.0-5.0/sqrt(2.0))/2.5
 var fit_y:bool=(high-low)*cell*ZOOM<=geometry.size.y-24.0
 fit.merge({"craft":craft,"safe":safe,"craft_safe":safe,"geometry_safe":geometry,"occluders":[],"scene_size":scene,"viewport_extent":extent,"art_extent":art,"velocity":velocity,"elapsed":sim.elapsed,"focus_offset":offset,"focus_points":points,"next_gate":gate_index,"required_zoom":ZOOM,"bounded_geometry_fit":fit_y and fit.zoom>=ZOOM-.000001,"body_below_provisional_review_floor":minf(craft.size.x,craft.size.y)*fit.zoom<60.0,"provisional_review_body_pixels":60.0*art.x/1280.0,"policy":POLICY,"geometry_speed_limit":geometry_speed_limit,"outside_reference_speed":velocity.x>geometry_speed_limit,"outside_reference_body":craft.size.x/cell>7.5 or craft.size.y/cell>7.5},true)
 return fit

static func release_frame(craft:Rect2,launch_center:Vector2,launch_zoom:float,cruise_center:Vector2,cruise_zoom:float,scene:Vector2,safe:Rect2,progress:float) -> Dictionary:
 # Blend the visible anchor, not a far-ahead world center times a changing
 # zoom. The latter product can send the craft beyond both safe endpoints.
 # This helper is called only by exact future-readable release presentation.
 var amount:float=clampf(progress,0.0,1.0)
 var zoom:float=lerpf(launch_zoom,cruise_zoom,amount)
 var at:Vector2=craft.get_center()
 var from_anchor:Vector2=(at-launch_center)*launch_zoom+scene*.5
 var to_anchor:Vector2=(at-cruise_center)*cruise_zoom+scene*.5
 var anchor:Vector2=from_anchor.lerp(to_anchor,amount)
 var center:Vector2=at+(scene*.5-anchor)/maxf(.00001,zoom)
 # Module centers are rounded in world_view. One world pixel contains that
 # visual rounding without scaling any sprite or changing physical geometry.
 var fit:Dictionary=Shared.constrain(center,zoom,craft.grow(1.0),safe,scene)
 fit.anchor=anchor;fit.release_progress=amount
 return fit
