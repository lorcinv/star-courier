extends RefCounted
## V4 contact-driven arm phase with bounded dev03 running amplitude.
## Observe accepted body state; never advance owner/body/contact time.
## Scalar double math keeps near-straight IK out of Vector2 float32 cancellation.
## Placements: root-relative actor pixels, world radians; mirror source x once.
const TAU:float=0.045
const SPEED:float=155.0
const MAX_SEGMENT:float=1.0/120.0
const SOURCE:Dictionary={
 "near_upper":{"root":[21.06,12.24],"tip":[16.875,39.15]},
 "near_fore":{"root":[16.875,4.149999999999999],"tip":[13.55,25.0]},
 "far_upper":{"root":[11.79,11.52],"tip":[17.325,37.845]},
 "far_fore":{"root":[17.325,3.844999999999999],"tip":[21.5,24.0]}
}
var _scale:float=0.0
var _phase:float=0.0
var _time:float=0.0
var _samples:int=0
var _pose:Dictionary={}

func configure(height:float) -> bool:
 if not is_finite(height) or height<=0.0:return false
 var proposed_scale:float=height/240.0
 if not is_finite(proposed_scale) or proposed_scale<=0.0:return false
 _scale=proposed_scale;_phase=0.0;_time=0.0;_samples=0;_pose={}
 return true

func snapshot() -> Dictionary:return _pose.duplicate(true)

func _number(x:Variant) -> bool:
 return (x is float or x is int) and is_finite(float(x))
func _point(x:Variant) -> bool:
 if x is Vector2:return x.is_finite()
 return x is Array and x.size()==2 and _number(x[0]) and _number(x[1])
func _a(x:Variant) -> Array:return [float(x.x),float(x.y)] if x is Vector2 else [float(x[0]),float(x[1])]
func _add(a:Array,b:Array) -> Array:return [a[0]+b[0],a[1]+b[1]]
func _sub(a:Array,b:Array) -> Array:return [a[0]-b[0],a[1]-b[1]]
func _mul(a:Array,s:float) -> Array:return [a[0]*s,a[1]*s]
func _len(a:Array) -> float:return sqrt(a[0]*a[0]+a[1]*a[1])
func _angle(a:Array) -> float:return atan2(a[1],a[0])
func _rotate(a:Array,r:float) -> Array:
 var c:float=cos(r);var s:float=sin(r)
 return [a[0]*c-a[1]*s,a[0]*s+a[1]*c]
func _reflect(a:Array,f:float) -> Array:return [a[0]*f,a[1]]
func _finite_tree(x:Variant) -> bool:
 if x is float:return is_finite(x)
 if x is Vector2:return x.is_finite()
 if x is Dictionary:
  for k in x:
   if not _finite_tree(x[k]):return false
 if x is Array:
  for v in x:
   if not _finite_tree(v):return false
 return true
func _body_ok(b:Dictionary) -> bool:
 if not b.has_all(["origin","facing_right","upper_body","joints"]):return false
 if not _point(b.origin) or not b.facing_right is bool:return false
 if not b.upper_body is Dictionary or not b.joints is Dictionary:return false
 var u:Dictionary=b.upper_body
 if not u.has_all(["shoulder_world","arm_world_angle","torso_world_angle"]):return false
 if not _number(u.torso_world_angle) or not u.shoulder_world is Dictionary or not u.arm_world_angle is Dictionary:return false
 for side in ["near","far"]:
  if not u.shoulder_world.has(side) or not _point(u.shoulder_world[side]):return false
  if not u.arm_world_angle.has(side) or not _number(u.arm_world_angle[side]):return false
  if not b.joints.has(side) or not b.joints[side] is Dictionary:return false
  if not b.joints[side].has_all(["ankle","hip"]):return false
  if not _point(b.joints[side].ankle) or not _point(b.joints[side].hip):return false
 return true

func _elbow(sh:Array,wr:Array,l1:float,l2:float,f:float) -> Array:
 var v:Array=_sub(wr,sh);var d:float=_len(v)
 if not is_finite(d) or d<=0.0:return [NAN,NAN]
 var t:Array=_mul(v,1.0/d)
 var x:float=(l1*l1-l2*l2+d*d)/(2.0*d)
 var h:float=sqrt(maxf(0.0,l1*l1-x*x))
 return _add(_add(sh,_mul(t,x)),_mul([-t[1],t[0]],h*f))

func advance(body:Dictionary,owner_velocity:float,accepted_time:float) -> bool:
 if _scale<=0.0 or not is_finite(owner_velocity) or not is_finite(accepted_time) or accepted_time<0.0 or not _body_ok(body):return false
 var dt:float=0.0 if _samples==0 else accepted_time-_time
 # Duplicate/reversed time cannot mutate even if the caller supplies a changed pose.
 if _samples>0 and (dt<=0.0 or dt>MAX_SEGMENT+0.000000000001):return false
 var f:float=1.0 if body.facing_right else -1.0
 var n:Array=_sub(_a(body.joints.near.ankle),_a(body.joints.near.hip))
 var far:Array=_sub(_a(body.joints.far.ankle),_a(body.joints.far.hip))
 var raw:float=clampf((n[0]-far[0])*f/_scale/32.0,-1.0,1.0)
 var phase:float=_phase+(raw-_phase)*(1.0-exp(-dt/TAU))
 var env:float=minf(1.0,absf(owner_velocity)/SPEED)
 var run:float=clampf((absf(owner_velocity)-185.0)/75.0,0.0,1.0)
 var origin:Array=_a(body.origin);var u:Dictionary=body.upper_body
 var arms:Dictionary={};var placements:Dictionary={}
 for side in ["near","far"]:
  var q:float=-phase if side=="near" else phase
  var v1:Array=_sub(SOURCE[side+"_upper"].tip,SOURCE[side+"_upper"].root)
  var v2:Array=_sub(SOURCE[side+"_fore"].tip,SOURCE[side+"_fore"].root)
  var l1:float=_len(v1)*_scale;var l2:float=_len(v2)*_scale
  var resttheta:float=_angle(_add(v1,v2));var restbend:float=absf(_angle(v2)-_angle(v1))
  var bend:float=restbend+env*(0.70+0.60*q+0.22*run)
  var radius:float=sqrt(l1*l1+l2*l2+2.0*l1*l2*cos(bend))
  var theta:float=resttheta-(0.42 if side=="near" else 0.24)*q*env*(1.0+0.30*run)
  var base:float=float(u.torso_world_angle)+(float(u.arm_world_angle[side])-float(u.torso_world_angle))*(1.0-env)
  # Solve in original world scalar space, matching the authoritative CPU order.
  var sh:Array=_a(u.shoulder_world[side])
  var wr:Array=_add(sh,_rotate(_reflect([radius*cos(theta),radius*sin(theta)],f),base))
  var el:Array=_elbow(sh,wr,l1,l2,f)
  var upper_angle:float=_angle(_sub(el,sh))-_angle(_reflect(v1,f))
  var fore_angle:float=_angle(_sub(wr,el))-_angle(_reflect(v2,f))
  var neutral_wr:Array=_add(sh,_rotate(_mul(_reflect(_add(v1,v2),f),_scale),float(u.arm_world_angle[side])))
  var neutral_el:Array=_elbow(sh,neutral_wr,l1,l2,f)
  var neutral_fore:float=_angle(_sub(neutral_wr,neutral_el))-_angle(_reflect(v2,f))
  var hand_angle:float=fore_angle-neutral_fore+float(u.arm_world_angle[side])
  var local_sh:Array=_sub(sh,origin);var local_el:Array=_sub(el,origin);var local_wr:Array=_sub(wr,origin)
  var local_places:Dictionary={}
  for item in [[side+"_upper",local_sh,upper_angle],[side+"_fore",local_el,fore_angle],[side+"_hand_relaxed",local_wr,hand_angle]]:
   var placement:Dictionary={"at":Vector2(item[1][0],item[1][1]),"angle":item[2]}
   placements[item[0]]=placement;local_places[item[0]]=placement.duplicate(true)
  arms[side]={"shoulder":local_sh,"elbow":local_el,"wrist":local_wr,"lengths":[l1,l2],"progression":q*env,"filtered_phase":q,"bend_radians":bend,"radius":radius,"target_clamp":0,"placements":local_places}
 var proposal:Dictionary={"valid":true,"source_time":accepted_time,"accepted_samples":_samples+1,"facing_right":body.facing_right,"height":_scale*240.0,"space":"root_relative_actor_pixels","velocity_envelope":env,"run_weight":run,"branch_source":1,"raw_phase":raw,"phase":phase,"arms":arms,"placements":placements}
 if not _finite_tree(proposal):return false
 # Commit only after all input and output checks. No body/owner writes.
 _phase=phase;_time=accepted_time;_samples+=1;_pose=proposal
 return true
