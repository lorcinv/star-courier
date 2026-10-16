extends RefCounted
## PURE presentation solver. It never owns time, actors, contacts or a model.
## All positions in evaluate(context) are actor-origin-relative parent pixels.
## Angles are WORLD radians. Reflect source-local x once, then rotate.
const ANATOMY_SHA:String="1408d8b47146e7a42e3df937821432be57624af013d5744593cd2f621c7056fc"
const READING_SOURCE_SHA:String="56efe92b767c4b16b675496541e0d3492b6137181196e1d2632357b9fda3491e"
const READING_DERIVATIVE_SHA:String="012597845de8090b013c58ee12aa7d9e3250645dd1577b53409dfccd92f08727"
const LEVEL_DERIVATIVE_SHA:String="7be2749bdb3dfe41be424144a198f0b7597f50921b46ef6618a40834bde0e0eb"
const SOURCE_HEAD_SCALE:float=91.0/976.0
const READING_ROOT:Vector2=Vector2(53.80532786885246,91.65266393442623)
const LEVEL_ROOT:Vector2=Vector2(53.35194672131147,91.0)
const READY_SECONDS:float=0.12
const TAP_APPROACH_SECONDS:float=0.08
const TAP_HOLD_END_SECONDS:float=0.16
const TAP_RETURN_END_SECONDS:float=0.28
var tablet_parts:Dictionary={}
var rig_parts:Dictionary={}

func configure(tablet:Dictionary,rig:Dictionary) -> bool:
 for key in ["near_upper","near_fore","far_upper","far_fore","hand_tap","hand_hold","hand_support","tablet"]:
  if not tablet.has(key) or not tablet[key].has_all(["root","tip"]):return false
 for key in ["torso","head","near_arm","far_arm"]:
  if not rig.has(key):return false
 if not rig.head.has("attachment_offset"):return false
 # Deep copies prohibit accidental mutation of the shared body registration.
 tablet_parts=tablet.duplicate(true);rig_parts=rig.duplicate(true)
 return true

func _v(value:Variant) -> Vector2:
 if value is Vector2:return value
 return Vector2(float(value[0]),float(value[1]))

func _ease(value:float) -> float:
 var u:float=clampf(value,0.0,1.0)
 return u*u*(3.0-2.0*u)

func tap_envelope(gesture:String,age:float) -> float:
 if gesture!="align" or age<0.0:return 0.0
 if age<TAP_APPROACH_SECONDS:return _ease(age/TAP_APPROACH_SECONDS)
 if age<TAP_HOLD_END_SECONDS:return 1.0
 if age<TAP_RETURN_END_SECONDS:return 1.0-_ease((age-TAP_HOLD_END_SECONDS)/(TAP_RETURN_END_SECONDS-TAP_HOLD_END_SECONDS))
 return 0.0

func _offset(point:Vector2,angle:float,scale_px:float,sign_x:float,local_mirror:float=1.0) -> Vector2:
 return (point*Vector2(sign_x*local_mirror,1.0)*scale_px).rotated(angle)

func _placement(texture:String,at:Vector2,angle:float,root:Vector2,z:int,mirror:float=1.0) -> Dictionary:
 return {"texture_key":texture,"at":at,"angle":angle,"root":root,"z":z,"mirror":mirror}

func _segment(key:String,from:Vector2,to:Vector2,sign_x:float,z:int) -> Dictionary:
 var source:Vector2=(_v(tablet_parts[key].tip)-_v(tablet_parts[key].root))*Vector2(sign_x,1.0)
 return _placement(key,from,(to-from).angle()-source.angle(),_v(tablet_parts[key].root),z)

func _elbow(shoulder:Vector2,wrist:Vector2,l1:float,l2:float) -> Dictionary:
 var distance:float=shoulder.distance_to(wrist)
 if distance<=0.0000001 or distance>l1+l2+0.00001 or distance<absf(l1-l2)-0.00001:
  return {"valid":false,"reason":"wrist_outside_fixed_arm_annulus","distance":distance,"lengths":Vector2(l1,l2)}
 var toward:Vector2=(wrist-shoulder)/distance
 var along:float=(l1*l1-l2*l2+distance*distance)/(2.0*distance)
 var high:float=sqrt(maxf(0.0,l1*l1-along*along))
 var center:Vector2=shoulder+toward*along
 var normal:Vector2=Vector2(-toward.y,toward.x)*high
 # Downward elbow branch in parent/world space, independent of facing.
 var first:Vector2=center+normal;var second:Vector2=center-normal
 return {"valid":true,"at":first if first.y>=second.y else second}

func evaluate(context:Dictionary) -> Dictionary:
 if tablet_parts.is_empty() or rig_parts.is_empty():return {"valid":false,"issues":["unconfigured"]}
 if not context.has_all(["hip","upper_body","height","facing_right","weight","gesture"]):
  return {"valid":false,"issues":["missing_context"]}
 var weight:float=clampf(float(context.weight),0.0,1.0)
 var scale_px:float=float(context.height)/240.0
 if not is_finite(scale_px) or scale_px<=0.0:return {"valid":false,"issues":["invalid_scale"]}
 var sign_x:float=1.0 if bool(context.facing_right) else -1.0
 var upper:Dictionary=context.upper_body
 var hip:Vector2=context.hip
 var gesture:String=str(context.gesture)
 var blend:float=_ease(weight)
 var ready:float=clampf(float(context.get("ready_blend",1.0 if gesture=="ready" else 0.0)),0.0,1.0)
 var tap:float=float(context.get("tap_blend",tap_envelope(gesture,float(context.get("gesture_age",0.0)))))
 tap=clampf(tap,0.0,1.0)*(1.0-ready)
 var torso_target:float=deg_to_rad(lerpf(3.0+tap,1.0,ready))*sign_x
 var torso_angle:float=lerp_angle(float(upper.torso_world_angle),torso_target,blend)
 var torso_at:Vector2=upper.torso_pivot_world
 var neck_goal:Vector2=hip+_offset(_v(rig_parts.head.attachment_offset),torso_angle,scale_px,sign_x)
 var neck:Vector2=_v(upper.neck_world).lerp(neck_goal,blend)
 var head_angle:float=lerp_angle(float(upper.head_world_angle),0.0,blend)
 var shoulders:Dictionary={}
 for side in ["near","far"]:
  var goal:Vector2=hip+_offset(_v(rig_parts[side+"_arm"].attachment_offset),torso_angle,scale_px,sign_x)
  shoulders[side]=_v(upper.shoulder_world[side]).lerp(goal,blend)
 var prop_angle:float=deg_to_rad(lerpf(-8.0,-3.0,ready))*sign_x
 var support_angle:float=prop_angle
 var prop_goal:Vector2=hip+_offset(Vector2(12.0,lerpf(-19.0,-18.0,ready)),0.0,scale_px,sign_x)
 var prop_root:Vector2=_v(tablet_parts.tablet.root)
 var support_tc:Vector2=Vector2(30.0,24.0)
 var support_hc:Vector2=Vector2(8.5,5.5)
 var support_delta:Vector2=_offset(support_hc-_v(tablet_parts.hand_support.root),support_angle,scale_px,sign_x,-1.0)
 var far_goal:Vector2=prop_goal+_offset(support_tc-prop_root,prop_angle,scale_px,sign_x)-support_delta
 var far_relaxed:Vector2=_relaxed_wrist("far",upper,scale_px,sign_x)
 var far_wrist:Vector2=far_relaxed.lerp(far_goal,blend)
 # Far wrist carries the prop for the entire visible raise/lower trajectory.
 var prop:Vector2=far_wrist+support_delta-_offset(support_tc-prop_root,prop_angle,scale_px,sign_x)
 var near_tc:Vector2=Vector2(13.0,11.0).lerp(Vector2(6.0,19.0),ready)
 var near_angle:float=deg_to_rad(lerpf(lerpf(-18.0,-15.0,tap),0.0,ready))*sign_x
 var tap_delta:Vector2=Vector2(12.5,3.0)-_v(tablet_parts.hand_tap.root)
 var hold_delta:Vector2=Vector2(8.5,4.0)-_v(tablet_parts.hand_hold.root)
 var near_delta:Vector2=_offset(tap_delta.lerp(hold_delta,ready),near_angle,scale_px,sign_x)
 var hover_native:Vector2=Vector2(-5.0,-5.0)*(1.0-tap)*(1.0-ready)
 var hover:Vector2=_offset(hover_native,0.0,scale_px,sign_x)
 var near_contact:Vector2=prop+_offset(near_tc-prop_root,prop_angle,scale_px,sign_x)
 var near_goal:Vector2=near_contact+hover-near_delta
 var near_wrist:Vector2=_relaxed_wrist("near",upper,scale_px,sign_x).lerp(near_goal,blend)
 # Wrist positions remain continuous through the hand texture event. During
 # grip change the near hand is explicitly released, not falsely contact-locked.
 var near_texture:String="hand_hold" if ready>=0.6 else "hand_tap"
 var reading:bool=weight>=0.45 and ready<0.6
 var head_texture:String="head_reading" if reading else "head_level"
 var head_root:Vector2=READING_ROOT if reading else LEVEL_ROOT
 var placements:Dictionary={
  "torso":_placement("torso",torso_at,torso_angle,_v(rig_parts.torso.root),40),
  "head":_placement(head_texture,neck,head_angle,head_root,60),
  "tablet":_placement("tablet",prop,prop_angle,prop_root,46),
  "far_hand":_placement("hand_support",far_wrist,support_angle,_v(tablet_parts.hand_support.root),47,-1.0),
  "near_hand":_placement(near_texture,near_wrist,near_angle,_v(tablet_parts[near_texture].root),48)}
 var joints:Dictionary={};var issues:Array=[]
 for side in ["far","near"]:
  var wrist:Vector2=far_wrist if side=="far" else near_wrist
  var l1:float=(_v(tablet_parts[side+"_upper"].tip)-_v(tablet_parts[side+"_upper"].root)).length()*scale_px
  var l2:float=(_v(tablet_parts[side+"_fore"].tip)-_v(tablet_parts[side+"_fore"].root)).length()*scale_px
  var solve:Dictionary=_elbow(shoulders[side],wrist,l1,l2)
  if not bool(solve.valid):issues.append(side+":"+str(solve.reason));continue
  var elbow:Vector2=solve.at
  placements[side+"_upper"]=_segment(side+"_upper",shoulders[side],elbow,sign_x,35 if side=="far" else 44)
  placements[side+"_fore"]=_segment(side+"_fore",elbow,wrist,sign_x,43 if side=="far" else 45)
  joints[side]={"shoulder":shoulders[side],"elbow":elbow,"wrist":wrist,"upper_length":l1,"fore_length":l2}
 var support_contact:Vector2=prop+_offset(support_tc-prop_root,prop_angle,scale_px,sign_x)
 var near_hc:Vector2=Vector2(8.5,4.0) if near_texture=="hand_hold" else Vector2(12.5,3.0)
 var near_actual:Vector2=near_wrist+_offset(near_hc-_v(tablet_parts[near_texture].root),near_angle,scale_px,sign_x)
 return {"valid":issues.is_empty(),"active":weight>0.000001,"prop_visible":weight>0.08,
  "scale":scale_px,"placements":placements,"joints":joints,"issues":issues,
  "contacts":{"far":{"tablet_local":support_tc,"hand_local":support_hc,"prop":support_contact,"hand":far_wrist+support_delta,"locked":true},
   "near":{"tablet_local":near_tc,"hand_local":near_hc,"prop":near_contact,"hand":near_actual,"intended_hover":hover,
    "locked":weight>=0.999999 and (ready<=0.000001 or ready>=0.999999),"grip_transition":ready>0.000001 and ready<0.999999}},
  "head_profile":{"texture_key":head_texture,"root":head_root,"canvas":Vector2(105,92) if reading else Vector2(104,91),
   "scale":scale_px,"source_scale":SOURCE_HEAD_SCALE,"abrupt_switch_unproven":true},
  "timing_status":"accepted-owner-input" if context.has_all(["gesture_age","ready_blend"]) else "endpoint-only; accepted owner timing pending",
  "controls":{"weight":weight,"ready":ready,"tap":tap},"gaze":"reading" if reading else "outward",
  "status":"source-only candidate; head and hand texture transitions require motion review"}

func _relaxed_wrist(side:String,upper:Dictionary,scale_px:float,sign_x:float) -> Vector2:
 var a:Dictionary=tablet_parts[side+"_upper"];var b:Dictionary=tablet_parts[side+"_fore"]
 var vector:Vector2=_v(a.tip)-_v(a.root)+_v(b.tip)-_v(b.root)
 return _v(upper.shoulder_world[side])+_offset(vector,float(upper.arm_world_angle[side]),scale_px,sign_x)
