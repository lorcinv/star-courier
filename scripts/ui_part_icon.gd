extends Control
## A legible blueprint glyph when an illustrated part icon is unavailable.
var part_type: String = "beam"
var thumbnail:Texture2D
var ink: Color = Color("142042")
var accent: Color = Color("294dd2")

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 var path="res://assets/icons/"+part_type+".png"
 if ResourceLoader.exists(path):thumbnail=load(path)
 queue_redraw()

func _draw() -> void:
 if thumbnail!=null:
  var edge=minf(size.x,size.y);draw_texture_rect(thumbnail,Rect2((size-Vector2.ONE*edge)*.5,Vector2.ONE*edge),false);return
 var c := size * 0.5
 var r := minf(size.x, size.y) * 0.32
 var w := maxf(2.0, size.x / 22.0)
 match part_type:
  "battery":
   draw_rect(Rect2(c - Vector2(r * 0.7, r), Vector2(r * 1.4, r * 2)), ink, false, w)
   draw_rect(Rect2(c + Vector2(-r * 0.25, -r * 1.23), Vector2(r * 0.5, r * 0.25)), ink)
   draw_polyline(PackedVector2Array([c+Vector2(r*.3,-r*.7),c+Vector2(-r*.3,0),c+Vector2(r*.25,0),c+Vector2(-r*.3,r*.65)]),accent,w)
  "thruster", "lance", "accelerator", "arc":
   draw_colored_polygon(PackedVector2Array([c+Vector2(-r,-r*.6),c+Vector2(r*.4,-r*.6),c+Vector2(r*.4,r*.6),c+Vector2(-r,r*.6)]),ink)
   draw_colored_polygon(PackedVector2Array([c+Vector2(r*.35,-r*.75),c+Vector2(r*1.25,0),c+Vector2(r*.35,r*.75)]),accent)
   draw_line(c-Vector2(r*1.3,r*.35),c-Vector2(r*.9,r*.35),accent,w)
   draw_line(c+Vector2(-r*1.3,r*.35),c+Vector2(-r*.9,r*.35),accent,w)
  "beam", "coupler", "damper", "spring":
   draw_line(c-Vector2(r,r*.65),c+Vector2(r,r*.65),ink,w*2)
   draw_line(c+Vector2(-r,r*.65),c+Vector2(r,-r*.65),accent,w*2)
   for a in [Vector2(-r,-r*.7),Vector2(r,-r*.7),Vector2(-r,r*.7),Vector2(r,r*.7)]:draw_circle(c+a,w*1.6,ink)
  "armor", "shield":
   var pts:=PackedVector2Array([c+Vector2(-r,-r*.8),c+Vector2(r,-r*.8),c+Vector2(r*.8,r*.45),c+Vector2(0,r*1.1),c+Vector2(-r*.8,r*.45),c+Vector2(-r,-r*.8)])
   draw_colored_polygon(pts,accent);draw_polyline(pts,ink,w)
   draw_line(c+Vector2(-r*.45,0),c+Vector2(-r*.1,r*.4),Color("fff0bd"),w)
   draw_line(c+Vector2(-r*.1,r*.4),c+Vector2(r*.5,-r*.4),Color("fff0bd"),w)
  "probe", "decoy", "collision":
   draw_circle(c,r*.3,ink)
   draw_arc(c,r*.7,-1.0,1.0,18,accent,w)
   draw_arc(c,r*1.15,-1.0,1.0,20,ink,w)
   draw_line(c-Vector2(r,0),c-Vector2(r*.4,0),ink,w)
  "and_gate", "or_gate", "not_gate", "delay", "valve":
   draw_rect(Rect2(c-Vector2(r*.7,r*.7),Vector2(r*1.4,r*1.4)),accent)
   for y in [-r*.45,r*.45]:
    draw_line(c+Vector2(-r*1.2,y),c+Vector2(-r*.65,y),ink,w)
   draw_line(c+Vector2(r*.65,0),c+Vector2(r*1.2,0),ink,w)
   draw_circle(c,r*.25,Color("fff0bd"),false,w)
  "cargo":
   draw_rect(Rect2(c-Vector2(r,r*.8),Vector2(r*2,r*1.6)),accent)
   draw_rect(Rect2(c-Vector2(r,r*.8),Vector2(r*2,r*1.6)),ink,false,w)
   draw_line(c+Vector2(0,-r*.8),c+Vector2(0,r*.8),Color("fff0bd"),w*2)
  _:
   draw_circle(c,r,ink,false,w)
   draw_circle(c,r*.5,accent,false,w*1.5)
   draw_line(c-Vector2(r*1.2,0),c+Vector2(r*1.2,0),ink,w)
   draw_line(c-Vector2(0,r*1.2),c+Vector2(0,r*1.2),ink,w)
