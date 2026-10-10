extends Node2D
## Bounded functional overlays. Painted hardware remains generated raster art;
## these strokes expose actual hit rays, teleport endpoints and receiver bounds.
const LIMIT:int=32
var origin:Vector2=Vector2.ZERO
var cell:float=72
var effects:Array=[]
var destination:Vector2=Vector2.ZERO
var receiver_radius:float=5
var delivered:bool=false
var warning_zones:Array=[]

func update_state(sim,new_origin:Vector2,new_cell:float) -> void:
 origin=new_origin;cell=new_cell
 destination=origin+Vector2(float(sim.route.get("distance",64)),float(sim.route.get("destination_y",0)))*cell
 receiver_radius=float(sim.route.get("delivery_radius",5))*cell
 delivered=sim.status=="success"
 effects=sim.effects.slice(maxi(0,sim.effects.size()-LIMIT))
 warning_zones=[]
 for h in sim.obstacles:
  if h.health>0 and h.type=="gravity" and warning_zones.size()<LIMIT:warning_zones.append({"point":origin+h.position*cell,"radius":float(h.radius)*cell})
 queue_redraw()

func _draw() -> void:
 var receipt_color:Color=Color("b2efa5") if delivered else Color("70e9eb")
 for i in range(16):
  var start:float=TAU*float(i)/16.0
  draw_arc(destination,receiver_radius,start,start+TAU/24.0,6,receipt_color,2,false)
 draw_line(destination-Vector2(16,0),destination+Vector2(16,0),receipt_color,2,false)
 draw_line(destination-Vector2(0,16),destination+Vector2(0,16),receipt_color,2,false)
 for zone in warning_zones:
  draw_arc(zone.point,zone.radius,0,TAU,48,Color("ac9cdf"),2,false)
 for effect in effects:
  var a:Vector2=origin+Vector2(effect.get("from",Vector2.ZERO))*cell
  var b:Vector2=origin+Vector2(effect.get("to",Vector2.ZERO))*cell
  match str(effect.get("type","")):
   "lance":draw_line(a,b,Color("fff4d2"),4,false);draw_line(a,b,Color("4fe0f9"),2,false)
   "arc":draw_line(a,b,Color("b5a4f0"),4,false)
   "enemy":draw_line(a,b,Color("f57f73"),2,false)
   "teleport":
    draw_arc(a,cell*.75,0,TAU,24,Color("91e9db"),3,false)
    draw_arc(b,cell*.75,0,TAU,24,Color("91e9db"),3,false)
   "explosion":draw_arc(a,maxf(.5,Vector2(effect.get("to",Vector2.ONE)).x)*cell,0,TAU,32,Color("ffc579"),2,false)
