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
var portal_hardware:Array=[]
var protected_bird_path:Array=[]
var protected_bird_zoom:float=1.0

func update_state(sim,new_origin:Vector2,new_cell:float) -> void:
 origin=new_origin;cell=new_cell
 destination=origin+Vector2(float(sim.route.get("distance",64)),float(sim.route.get("destination_y",0)))*cell
 receiver_radius=float(sim.route.get("delivery_radius",5))*cell
 delivered=sim.status=="success"
 effects=sim.effects.slice(maxi(0,sim.effects.size()-LIMIT))
 warning_zones=[]
 portal_hardware=[]
 for h in sim.obstacles:
  if h.health>0 and h.type=="gravity" and warning_zones.size()<LIMIT:warning_zones.append({"point":origin+h.position*cell,"radius":float(h.radius)*cell})
  if str(sim.route.get("control_version","")) in ["pilot-v4-wormhole","pilot-v5-protected-bird"] and h.health>0 and bool(h.get("wormhole_hardware",false)) and portal_hardware.size()<LIMIT:
   portal_hardware.append({"point":origin+h.position*cell,"radius":float(h.radius)*cell})
 queue_redraw()

func set_protected_bird_cue(cue:Dictionary) -> void:
 protected_bird_path=[]
 if cue.get("active") is bool and cue.active and cue.get("points") is Array and cue.points.size()<=3 and cue.get("zoom") is float and is_finite(cue.zoom) and cue.zoom>0.0:
  for point in cue.points:
   if not point is Vector2 or not point.is_finite():protected_bird_path=[];queue_redraw();return
   protected_bird_path.append(origin+point*cell)
  protected_bird_zoom=cue.zoom
 queue_redraw()

func _draw() -> void:
 # Small native route chevrons, not targets or a guaranteed-clearance tube.
 for point in protected_bird_path:
  var size:float=7.0/protected_bird_zoom
  draw_line(point+Vector2(-size,-size),point,Color("b2d9b5"),1.5/protected_bird_zoom,false)
  draw_line(point,point+Vector2(-size,size),Color("b2d9b5"),1.5/protected_bird_zoom,false)
 var receipt_color:Color=Color("b2efa5") if delivered else Color("70e9eb")
 for i in range(16):
  var start:float=TAU*float(i)/16.0
  draw_arc(destination,receiver_radius,start,start+TAU/24.0,6,receipt_color,2,false)
 draw_line(destination-Vector2(16,0),destination+Vector2(16,0),receipt_color,2,false)
 draw_line(destination-Vector2(0,16),destination+Vector2(0,16),receipt_color,2,false)
 for zone in warning_zones:
  draw_arc(zone.point,zone.radius,0,TAU,48,Color("ac9cdf"),2,false)
 for zone in portal_hardware:
  # Exact physical circle, independent of the scalloped generated cap alpha.
  # A restrained guard outline discloses the real collision boundary.
  draw_arc(zone.point,zone.radius,0,TAU,40,Color(1.0,.76,.36,.48),4,false)
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
