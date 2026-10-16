extends Control
## Geometry-only diagram of this order's frozen route. Dashed alternatives are
## route choices, never a launch prediction or a promise of collision-free flight.
const Layout=preload("res://scripts/delivery_route_layout_v1.gd")
const RiftRisk=preload("res://scripts/delivery_rift_risk_ui_v1.gd")
var _snapshot:Dictionary={}

func _ready()->void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 clip_contents=true
 resized.connect(queue_redraw)

func present(order:Dictionary)->void:
 _snapshot=(RiftRisk.preview(order) if RiftRisk.applies(order) else Layout.preview(order)).duplicate(true)
 visible=not _snapshot.is_empty()
 tooltip_text="圆圈为本单岩石边界；只标发射处和高架收件位置，不是飞行轨迹。需绕开岩石并给整船留出余量。" if _snapshot.get("layout_id")==Layout.HEAVY_ID else "圆圈为本单浮石边界；虚线仅提示绕行方向，不是飞行轨迹。需给整船留出余量。"
 if RiftRisk.applies(order):tooltip_text=RiftRisk.tooltip(order)
 queue_redraw()

func snapshot()->Dictionary:return _snapshot.duplicate(true)

func projected_geometry()->Dictionary:
 if _snapshot.is_empty():return {}
 if _snapshot.layout_id==RiftRisk.ID:return _project_rift()
 var circles:Array=_snapshot.circles
 var launch:Vector2=_snapshot.launch;var receiver:Vector2=_snapshot.receiver
 var low:Vector2=launch.min(receiver);var high:Vector2=launch.max(receiver)
 var radius:float=0.0
 for circle in circles:
  var r:float=float(circle.radius);radius=maxf(radius,r)
  low=low.min(circle.position-Vector2.ONE*r);high=high.max(circle.position+Vector2.ONE*r)
 var upper:float=low.y-radius*.8;var lower:float=high.y+radius*.8
 # A single elevated rock has no authored safe corridor. Mark the actual
 # terrain and endpoints only; a schematic line would imply a flight solution.
 var paths:Array=[]
 if _snapshot.layout_id==Layout.FRAGILE_ID:
  var center:Vector2=_snapshot.passage_center
  var left:float=center.x-radius*2.8;var right:float=center.x+radius*2.8
  paths=[PackedVector2Array([launch,center,receiver]),PackedVector2Array([launch,Vector2(left,upper),Vector2(right,upper),receiver]),PackedVector2Array([launch,Vector2(left,lower),Vector2(right,lower),receiver])]
 if _snapshot.layout_id==Layout.ROCKBELT_ID:
  var center:Vector2=circles[2].position
  var left:float=center.x-radius*2.8;var right:float=center.x+radius*2.8
  paths=[PackedVector2Array(),PackedVector2Array([launch,Vector2(left,upper),Vector2(right,upper),receiver]),PackedVector2Array([launch,Vector2(left,lower),Vector2(right,lower),receiver])]
 low.y=upper;high.y=lower
 var density:float=float(get_meta(&"demo_native_density_v2",1.0))
 var inset:Vector2=Vector2(20,10)*density
 var bounds:Vector2=(high-low).max(Vector2(.001,.001))
 var inner:Vector2=(size-inset*2.0).max(Vector2.ONE)
 var ratio:float=minf(inner.x/bounds.x,inner.y/bounds.y)
 var offset:Vector2=(size-bounds*ratio)*.5-low*ratio
 var projected_circles:Array=[];var projected_paths:Array=[]
 for circle in circles:projected_circles.append({"id":circle.id,"position":offset+circle.position*ratio,"radius":circle.radius*ratio})
 for path in paths:
  var points:=PackedVector2Array()
  for point in path:points.append(offset+point*ratio)
  projected_paths.append(points)
 return {"circles":projected_circles,"paths":projected_paths,"scale":ratio,"launch":offset+launch*ratio,"receiver":offset+receiver*ratio}

func _draw()->void:
 var view:Dictionary=projected_geometry()
 if view.is_empty():return
 if _snapshot.layout_id==RiftRisk.ID:
  _draw_rift(view);return
 var density:float=float(get_meta(&"demo_native_density_v2",1.0))
 draw_rect(Rect2(Vector2.ZERO,size),Color("101a30"))
 for index in range(1,view.paths.size()):
  var path:PackedVector2Array=view.paths[index]
  for i in range(path.size()-1):draw_dashed_line(path[i],path[i+1],Color("49cce5"),1.0*density,4.0*density,false)
 if not view.paths.is_empty() and not view.paths[0].is_empty():draw_polyline(view.paths[0],Color("ffca57"),1.5*density,false)
 for circle in view.circles:
  draw_circle(circle.position,circle.radius,Color("52647c"))
  draw_arc(circle.position,circle.radius,0,TAU,64,Color("eeaa7f"),1.0*density,false)
 draw_circle(view.launch,3.0*density,Color("ffca57"))
 draw_arc(view.receiver,4.0*density,0,TAU,24,Color("49cce5"),1.5*density,false)
 var font:Font=get_theme_default_font()
 var launch_label_offset:Vector2=Vector2(-27,4) if _snapshot.layout_id==Layout.HEAVY_ID else Vector2(-27,17)
 draw_string(font,view.launch+launch_label_offset*density,"发射",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(11*density),Color("fff3d7"))
 draw_string(font,view.receiver+Vector2(7,4)*density,"收件",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(11*density),Color("fff3d7"))


func _project_rift()->Dictionary:
 var cold:Rect2=_snapshot.cold_bounds;var field:Rect2=_snapshot.turbulence_bounds
 var low:Vector2=_snapshot.launch.min(_snapshot.receiver).min(cold.position).min(field.position)
 var high:Vector2=_snapshot.launch.max(_snapshot.receiver).max(cold.end).max(field.end)
 for key in ["entry","exit"]:
  low=low.min(_snapshot[key]-Vector2(0,_snapshot.aperture_radius))
  high=high.max(_snapshot[key]+Vector2(0,_snapshot.aperture_radius))
 low=low.min(_snapshot.pirate_position-Vector2.ONE*_snapshot.pirate_radius)
 high=high.max(_snapshot.pirate_position+Vector2.ONE*_snapshot.pirate_radius)
 # Deliberately show empty space beyond both real rectangular field edges.
 # No route line is drawn: warm space does not guarantee safe travel.
 low.y-=12.0;high.y+=12.0
 var density:float=float(get_meta(&"demo_native_density_v2",1.0))
 var inset:Vector2=Vector2(15,16)*density
 var span:Vector2=(high-low).max(Vector2.ONE)
 var inner:Vector2=(size-inset*2.0).max(Vector2.ONE)
 var scale:float=minf(inner.x/span.x,inner.y/span.y)
 var offset:Vector2=(size-span*scale)*.5-low*scale
 var view:Dictionary={"scale":scale,"paths":[],"circles":[],"cold_bounds":Rect2(offset+cold.position*scale,cold.size*scale),"turbulence_bounds":Rect2(offset+field.position*scale,field.size*scale),"aperture_radius":_snapshot.aperture_radius*scale,"pirate_radius":_snapshot.pirate_radius*scale}
 for key in ["launch","receiver","entry","exit","pirate_position"]:view[key]=offset+_snapshot[key]*scale
 return view

func _draw_rift(view:Dictionary)->void:
 var density:float=float(get_meta(&"demo_native_density_v2",1.0))
 var font:Font=get_theme_default_font();var text_size:int=roundi(10*density)
 draw_rect(Rect2(Vector2.ZERO,size),Color("101a30"))
 draw_rect(view.cold_bounds,Color(.30,.68,.88,.20))
 draw_rect(view.cold_bounds,Color("8dcfe9"),false,1.0*density)
 draw_rect(view.turbulence_bounds,Color("e9aa70"),false,1.5*density)
 for key in ["entry","exit"]:
  var at:Vector2=view[key];var color:Color=Color("49cce5") if key=="entry" else Color("b7a0f4")
  draw_line(at-Vector2(0,view.aperture_radius),at+Vector2(0,view.aperture_radius),color,2.0*density)
  draw_line(at-Vector2(4,0)*density,at+Vector2(6,0)*density,color,1.0*density)
  draw_string(font,at+Vector2(-10,-view.aperture_radius/density-3)*density,"入口" if key=="entry" else "出口",HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,color)
 draw_circle(view.launch,2*density,Color("ffca57"))
 draw_arc(view.receiver,3*density,0,TAU,24,Color("49cce5"),1.0*density)
 draw_string(font,view.receiver+Vector2(-10,14)*density,"收件",HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,Color("fff3d7"))
 draw_circle(view.pirate_position,maxf(2*density,view.pirate_radius),Color("f2a288"))
 draw_string(font,view.pirate_position+Vector2(5,-2)*density,"海盗",HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,Color("f2a288"))
 # Labels identify distinct sampling boundaries rather than a full-ship wall.
 draw_string(font,Vector2(6*density,size.y-5*density),"冷区",HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,Color("8dcfe9"))
 draw_string(font,Vector2(34*density,size.y-5*density),"乱流",HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,Color("e9aa70"))
 draw_string(font,Vector2(6,12)*density,"蓝框外暖区可绕",HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,Color("9ed5b6"))
