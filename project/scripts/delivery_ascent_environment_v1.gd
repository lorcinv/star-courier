extends RefCounted
## Altitude-local external fields, in the same world metres as cargo/collisions.
## No time/x-progress staging, route mutation, hidden propulsion, or battery grant.
const SCHEMA:String="continuous-altitude-v1"
static func at(route:Dictionary,position:Vector2)->Dictionary:
 var altitude:float=float(route.get("background_ground_y_m",0.0))-position.y
 var layers:Array=route.get("ascent_layers",[])
 if layers.is_empty():return {"altitude_m":altitude,"phase":"ground","gravity":0.0,"wind":Vector2.ZERO,"drag":0.0}
 var index:int=0
 for i in range(layers.size()):
  if altitude>=float(layers[i].start_altitude_m):index=i
 var current:Dictionary=layers[index]
 var result:Dictionary={"altitude_m":altitude,"phase":str(current.phase),"gravity":float(current.gravity),"wind":Vector2(current.wind[0],current.wind[1]),"drag":float(current.drag)}
 var width:float=float(route.get("ascent_transition_metres",20.0))
 for i in range(1,layers.size()):
  var boundary:float=float(layers[i].start_altitude_m)
  if absf(altitude-boundary)>width*0.5:continue
  var u:float=clampf((altitude-boundary)/width+0.5,0.0,1.0);u=u*u*(3.0-2.0*u)
  var lower:Dictionary=layers[i-1];var upper:Dictionary=layers[i]
  result.gravity=lerpf(float(lower.gravity),float(upper.gravity),u)
  result.wind=Vector2(lower.wind[0],lower.wind[1]).lerp(Vector2(upper.wind[0],upper.wind[1]),u)
  result.drag=lerpf(float(lower.drag),float(upper.drag),u)
  break
 return result
