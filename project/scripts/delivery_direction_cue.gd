extends Control
## Screen-space signpost, read-only. The receiver and cargo positions come from
## the live world's existing camera projection, never from a prescribed path.
var _tip:Vector2=Vector2.ZERO
var _bearing:Vector2=Vector2.RIGHT
var _distance:Label
var _onscreen:bool=false
var _density:float=1.0

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _distance=Label.new();_distance.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _distance.add_theme_font_size_override("font_size",18)
 _distance.add_theme_color_override("font_color",Color("fff3d7"))
 _distance.add_theme_color_override("font_shadow_color",Color("101a30"))
 _distance.add_theme_constant_override("shadow_outline_size",4)
 _distance.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 _distance.custom_minimum_size=Vector2(140,26);add_child(_distance)
 hide()

static func layout(cargo:Vector2,target:Vector2,safe:Rect2) -> Dictionary:
 if not cargo.is_finite() or not target.is_finite() or safe.size.x<=0 or safe.size.y<=0:return {}
 var bearing:Vector2=target-cargo
 if bearing.length_squared()<=.000001:return {}
 bearing=bearing.normalized()
 var anchor:Vector2=Vector2(clampf(cargo.x,safe.position.x,safe.end.x),clampf(cargo.y,safe.position.y,safe.end.y))
 var point:Vector2=target
 var onscreen:bool=safe.has_point(target)
 if not onscreen:
  var ray:Vector2=(target-anchor).normalized()
  var t:float=INF
  if ray.x>.000001:t=minf(t,(safe.end.x-anchor.x)/ray.x)
  elif ray.x<-.000001:t=minf(t,(safe.position.x-anchor.x)/ray.x)
  if ray.y>.000001:t=minf(t,(safe.end.y-anchor.y)/ray.y)
  elif ray.y<-.000001:t=minf(t,(safe.position.y-anchor.y)/ray.y)
  if not is_finite(t):return {}
  point=anchor+ray*maxf(0,t)
 return {"point":point,"bearing":bearing,"onscreen":onscreen}

func present(snapshot:Dictionary,screen_to_local:Transform2D,safe:Rect2,density:float=1.0) -> void:
 hide()
 if not is_instance_valid(_distance):return
 if str(snapshot.get("status",""))!="running" or bool(snapshot.get("charging",false)):return
 if not snapshot.get("cargo_screen") is Vector2 or not snapshot.get("receiver_screen") is Vector2:return
 var meters:float=float(snapshot.get("distance_m",NAN))
 if not is_finite(meters) or meters<0:return
 var result:Dictionary=layout(screen_to_local*snapshot.cargo_screen,screen_to_local*snapshot.receiver_screen,safe)
 if result.is_empty():return
 _tip=result.point;_bearing=result.bearing;_onscreen=result.onscreen;_density=clampf(density,1.0,3.0)
 _distance.text="%.0f m"%meters
 _distance.position=Vector2(clampf(_tip.x-70*_density,safe.position.x-16*_density,maxf(safe.position.x-16*_density,safe.end.x-124*_density)),_tip.y+18*_density)
 _distance.size=Vector2(140,26)*_density
 _distance.add_theme_font_size_override("font_size",roundi(18*_density))
 _distance.tooltip_text=str(snapshot.get("destination_name","收件台"))
 show();queue_redraw()

func _draw() -> void:
 if not visible:return
 var angle:float=_bearing.angle()
 var shape:PackedVector2Array=PackedVector2Array([Vector2(16,0),Vector2(-11,-12),Vector2(-5,0),Vector2(-11,12)])
 var edge:PackedVector2Array=PackedVector2Array()
 var fill:PackedVector2Array=PackedVector2Array()
 for vertex in shape:
  edge.append(_tip+(vertex*1.28*_density).rotated(angle))
  fill.append(_tip+(vertex*_density).rotated(angle))
 draw_colored_polygon(edge,Color("101a30"));draw_colored_polygon(fill,Color("ffca57"))
 if _onscreen:draw_arc(_tip,24*_density,0,TAU,24,Color("49cce5"),2*_density,false)
