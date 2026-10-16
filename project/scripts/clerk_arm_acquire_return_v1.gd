extends RefCounted
## Explicit owner transition layered over frozen V4. No owner/body/contact writes.
## Authoritative root ending velocity is supplied; never reconstructed from motion.
const Walk=preload("res://scripts/clerk_walk_arm_v4.gd")
const RETURN_SECONDS:float=0.12
var _walk=Walk.new()
var _height:float=0.0
var _time:float=0.0
var _display:Dictionary={}
var _from:Dictionary={}
var _started:float=0.0
var _mode:String="walk"
var _owner:String=""
func configure(height:float) -> bool:
 var next=Walk.new()
 if not next.configure(height):return false
 _walk=next;_height=height;_time=0.0;_display={};_from={};_started=0.0;_mode="walk";_owner=""
 return true
func snapshot() -> Dictionary:return _display.duplicate(true)
func status() -> Dictionary:
 return {"mode":_mode,"owner":_owner,"pickup_ready":_mode=="neutral","accepted_time":_time,"started":_started,"duration":RETURN_SECONDS}
func acquire(owner_kind:String,accepted_time:float) -> bool:
 if not owner_kind in ["cooperative","phone"] or _display.is_empty() or not is_finite(accepted_time) or accepted_time!=_time:return false
 if _mode in ["acquire","neutral"]:return false
 # Capture the actually displayed arm shape, including an interrupted release.
 _from=_display.duplicate(true);_started=_time;_mode="acquire";_owner=owner_kind
 return true
func cancel(accepted_time:float) -> bool:
 if not _mode in ["acquire","neutral"] or not is_finite(accepted_time) or accepted_time!=_time:return false
 _from=_display.duplicate(true);_started=_time;_mode="release";_owner=""
 return true
func _heading(a:Array,b:Array,f:float) -> float:return atan2(b[1]-a[1],(b[0]-a[0])*f)
func _angle_mix(a:float,b:float,t:float) -> float:return a+atan2(sin(b-a),cos(b-a))*t
func _point(a:Array,l:float,heading:float,f:float) -> Array:return [a[0]+cos(heading)*l*f,a[1]+sin(heading)*l]
func _segment_angle(a:Array,b:Array,key:String,f:float) -> float:
 var src:Dictionary=Walk.SOURCE[key]
 return atan2(b[1]-a[1],b[0]-a[0])-atan2(src.tip[1]-src.root[1],(src.tip[0]-src.root[0])*f)
func _blend(target:Dictionary,elapsed:float) -> Dictionary:
 var t:float=clampf(elapsed/RETURN_SECONDS,0.0,1.0)
 if t>=1.0:return target.duplicate(true)
 var w:float=t*t*(3.0-2.0*t)
 var out:Dictionary=target.duplicate(true)
 var f:float=1.0 if target.facing_right else -1.0
 var old_f:float=1.0 if _from.facing_right else -1.0
 for side in ["near","far"]:
  var a:Dictionary=_from.arms[side];var b:Dictionary=target.arms[side]
  var a1:float=_heading(a.shoulder,a.elbow,old_f);var a2:float=_heading(a.elbow,a.wrist,old_f)
  var b1:float=_heading(b.shoulder,b.elbow,f);var b2:float=_heading(b.elbow,b.wrist,f)
  # A canonical upper heading and positive flexion retain the one mirrored IK branch.
  var bend_a:float=atan2(sin(a1-a2),cos(a1-a2));var bend_b:float=atan2(sin(b1-b2),cos(b1-b2))
  var heading:float=_angle_mix(a1,b1,w);var bend:float=lerpf(bend_a,bend_b,w)
  var sh:Array=b.shoulder.duplicate();var el:Array=_point(sh,b.lengths[0],heading,f)
  var wr:Array=_point(el,b.lengths[1],heading-bend,f)
  var hand_key:String=side+"_hand_relaxed"
  var hand:float=_angle_mix(float(a.placements[hand_key].angle)*old_f,float(b.placements[hand_key].angle)*f,w)*f
  var local:Dictionary={}
  for item in [[side+"_upper",sh,_segment_angle(sh,el,side+"_upper",f)],[side+"_fore",el,_segment_angle(el,wr,side+"_fore",f)],[hand_key,wr,hand]]:
   var placement:Dictionary={"at":Vector2(item[1][0],item[1][1]),"angle":item[2]}
   out.placements[item[0]]=placement;local[item[0]]=placement.duplicate(true)
  out.arms[side]={"shoulder":sh,"elbow":el,"wrist":wr,"lengths":b.lengths.duplicate(),"bend_radians":bend,"placements":local,"target_clamp":0}
 out.transition={"kind":_mode,"elapsed":elapsed,"fraction":t,"angle_weight":w}
 return out
func advance(body:Dictionary,root_ending_velocity:float,accepted_time:float) -> bool:
 # Scratch neutral solve validates current body, finite output and scale before
 # advancing persistent state. It is not a second simulation clock.
 var neutral=Walk.new()
 if not neutral.configure(_height) or not neutral.advance(body,0.0,accepted_time):return false
 if not _walk.advance(body,root_ending_velocity,accepted_time):return false
 var walking:Dictionary=_walk.snapshot()
 var result:Dictionary=walking
 if _mode!="walk":
  var target:Dictionary=walking if _mode=="release" else neutral.snapshot()
  target.accepted_samples=walking.accepted_samples
  var finished:bool=accepted_time>=_started+RETURN_SECONDS
  var elapsed:float=RETURN_SECONDS if finished else accepted_time-_started
  result=_blend(target,elapsed) if _mode in ["acquire","release"] else target
  if finished:
   if _mode=="acquire":_mode="neutral"
   elif _mode=="release":_mode="walk";_from={}
 _time=accepted_time;_display=result
 return true
