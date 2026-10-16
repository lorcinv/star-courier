extends Control
## Pure projection of launcher_v3.preview trajectory and velocity. No ballistic
## formula, speed estimate, simulation step or control input lives in this view.
var _snapshot:Dictionary={}
var _ready_preview:bool=false

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 clip_contents=true
 resized.connect(queue_redraw)

func present(snapshot:Dictionary,ready:bool) -> void:
 _snapshot=snapshot.duplicate(true)
 _ready_preview=ready
 queue_redraw()

func projected_path() -> PackedVector2Array:
 var result:=PackedVector2Array()
 if not _ready_preview:return result
 var raw:Variant=_snapshot.get("trajectory",[])
 if not (raw is Array or raw is PackedVector2Array) or raw.size()<2 or raw.size()>257:return result
 var low:Vector2=raw[0] if raw[0] is Vector2 else Vector2(INF,INF)
 var high:Vector2=low
 for point in raw:
  if not point is Vector2 or not point.is_finite():return PackedVector2Array()
  low=low.min(point);high=high.max(point)
 var inset:float=12.0*float(get_meta(&"demo_native_density_v2",1.0))
 var bounds:Vector2=(high-low).max(Vector2(.001,.001))
 var inner:Vector2=(size-Vector2.ONE*inset*2.0).max(Vector2.ONE)
 var scale_value:float=minf(inner.x/bounds.x,inner.y/bounds.y)
 var offset:Vector2=(size-bounds*scale_value)*.5
 for point in raw:result.append(offset+(point-low)*scale_value)
 return result

func _draw() -> void:
 var path:PackedVector2Array=projected_path()
 if path.size()<2:return
 var density:float=float(get_meta(&"demo_native_density_v2",1.0))
 draw_polyline(path,Color("49cce5"),2.0*density,false)
 draw_circle(path[0],3.0*density,Color("ffca57"))
 var velocity:Vector2=_snapshot.get("velocity",Vector2.ZERO)
 if not velocity.is_finite() or velocity.length_squared()<.000001:return
 var direction:Vector2=velocity.normalized()
 var tip:Vector2=path[0]+direction*24.0*density
 draw_line(path[0],tip,Color("ffca57"),2.0*density,false)
 draw_line(tip,tip-direction.rotated(.6)*8.0*density,Color("ffca57"),2.0*density,false)
 draw_line(tip,tip-direction.rotated(-.6)*8.0*density,Color("ffca57"),2.0*density,false)
