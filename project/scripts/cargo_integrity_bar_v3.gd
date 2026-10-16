extends ProgressBar
## The sole cargo-health bar. The order threshold shares this bar, rather than
## creating an unrelated player-health resource or a second health meter.
var minimum_fraction:float=NAN
var integrity_known:bool=false

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 show_percentage=false
 min_value=0.0;max_value=100.0
 resized.connect(queue_redraw)

func present(current:float,minimum:float) -> void:
 integrity_known=is_finite(current) and is_finite(minimum)
 minimum_fraction=minimum
 value=current*100.0 if is_finite(current) else 0.0
 queue_redraw()

func marker_x() -> float:
 return clampf(size.x*minimum_fraction,1.0,maxf(1.0,size.x-1.0)) if is_finite(minimum_fraction) else NAN

func _draw() -> void:
 if not is_finite(minimum_fraction):return
 var density:float=float(get_meta(&"demo_native_density_v2",1.0))
 draw_line(Vector2(marker_x(),0),Vector2(marker_x(),size.y),Color("fff3d7"),2.0*density,false)
