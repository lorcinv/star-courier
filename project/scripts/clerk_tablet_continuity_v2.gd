extends "res://scripts/clerk_tablet_presentation_v1.gd"
## Pure spatial proposal. Caller owns accepted phase, gesture time and gaze.
## draw_progress: 0 stored/rest, .25 pickup, .60 lateral clearance, 1 reading.
## Same path is traversed in reverse to return. No timer or state mutation.
func _mix3(a:Vector2,b:Vector2,c:Vector2,u:float) -> Vector2:
 return a.lerp(b,_ease(u/0.5)) if u<0.5 else b.lerp(c,_ease((u-0.5)/0.5))
func evaluate(context:Dictionary) -> Dictionary:
 var out:Dictionary=super.evaluate(context)
 if not out.get("valid",false):return out
 var p:float=clampf(float(context.get("draw_progress",context.weight)),0.0,1.0)
 var f:float=1.0 if context.facing_right else -1.0
 var s:float=float(context.height)/240.0
 var u:Dictionary=context.upper_body
 var hip:Vector2=context.hip
 var placements:Dictionary=out.placements
 var ready:float=float(out.controls.ready)
 var blend:float=_ease(p)
 # Explicit storage ownership: one actual tablet behind existing torso at rest.
 var storage:Vector2=hip+_offset(Vector2(0,-22),0,s,f)
 var clearance:Vector2=hip+_offset(Vector2(48,-26),0,s,f)
 var goal:Vector2=hip+_offset(Vector2(12,lerpf(-19,-18,ready)),0,s,f)
 var pickup:float=clampf((p-0.25)/0.75,0,1)
 var prop:Vector2=storage
 var pa:float=deg_to_rad(90.0)*f
 if p>0.25:
  prop=_mix3(storage,clearance,goal,pickup)
  if pickup>0.5:pa=lerp_angle(pa,deg_to_rad(lerpf(-8,-3,ready))*f,_ease((pickup-0.5)/0.5))
 var support_tc:Vector2=Vector2(30,24)
 var support_hc:Vector2=Vector2(8.5,5.5)
 var support_delta:Vector2=_offset(support_hc-_v(tablet_parts.hand_support.root),pa,s,f,-1)
 var grip:Vector2=prop+_offset(support_tc-_v(tablet_parts.tablet.root),pa,s,f)-support_delta
 var far_rest:Vector2=_relaxed_wrist("far",u,s,f)+_v(out.joints.far.shoulder)-_v(u.shoulder_world.far)
 var far_wrist:Vector2=far_rest.lerp(grip,_ease(p/0.25)) if p<0.25 else grip
 var near_rest:Vector2=_relaxed_wrist("near",u,s,f)+_v(out.joints.near.shoulder)-_v(u.shoulder_world.near)
 var near_wrist:Vector2=near_rest.lerp(_v(out.joints.near.wrist),_ease(clampf((p-0.2)/0.8,0,1)))
 # Ready changes finger articulation only: retain wrist/root and continuous axis.
 var near_target_angle:float=float(placements.near_hand.angle)
 var near_heading0:float=((_v(rig_parts.near_arm.tip)-Vector2(13.55,60))*Vector2(f,1)).angle()+float(u.arm_world_angle.near)
 var near_heading:float=lerp_angle(near_heading0,near_target_angle+(0.0 if f>0 else PI),blend)
 var far_heading0:float=((_v(rig_parts.far_arm.tip)-Vector2(21.5,58))*Vector2(f,1)).angle()+float(u.arm_world_angle.far)
 var far_heading:float=lerp_angle(far_heading0,pa+(PI if f>0 else 0.0),_ease(p/0.25)) if p<0.25 else pa+(PI if f>0 else 0.0)
 var near_source:String="near_hand_relaxed" if p<0.3 else str(placements.near_hand.texture_key)
 var far_source:String="far_hand_relaxed" if p<0.25 else "hand_support"
 var near_axis:float=((_v(tablet_parts[near_source].tip)-_v(tablet_parts[near_source].root))*Vector2(f,1)).angle()
 var far_mirror:float=1.0 if p<0.25 else -1.0
 var far_axis:float=((_v(tablet_parts[far_source].tip)-_v(tablet_parts[far_source].root))*Vector2(f*far_mirror,1)).angle()
 placements.near_hand=_placement(near_source,near_wrist,near_heading-near_axis,_v(tablet_parts[near_source].root),48)
 placements.far_hand=_placement(far_source,far_wrist,far_heading-far_axis,_v(tablet_parts[far_source].root),47,far_mirror)
 placements.tablet=_placement("tablet",prop,pa,_v(tablet_parts.tablet.root),39 if pickup<=0.5 else 46)
 # Spatial layer transfer occurs at the lateral clearance pose, not visibility.
 var issues:Array=[]
 for side in ["near","far"]:
  var shoulder:Vector2=_v(out.joints[side].shoulder)
  var wrist:Vector2=near_wrist if side=="near" else far_wrist
  var l1:float=float(out.joints[side].upper_length);var l2:float=float(out.joints[side].fore_length)
  var solved:Dictionary=_continuous_elbow(shoulder,wrist,l1,l2,f)
  if not solved.valid:issues.append(side+":"+str(solved.reason));continue
  placements[side+"_upper"]=_segment(side+"_upper",shoulder,solved.at,f,1 if side=="far" else 35)
  placements[side+"_fore"]=_segment(side+"_fore",solved.at,wrist,f,43 if side=="far" else 45)
  out.joints[side].elbow=solved.at;out.joints[side].wrist=wrist
 # Caller hook for three physical head views. This lane does not invent art.
 var gaze:float=clampf(float(context.get("gaze_progress",blend*(1-ready))),0,1)
 if context.has("head_views") and context.head_views.size()==3:
  var ix:int=0 if gaze<0.25 else (1 if gaze<0.75 else 2)
  var view:Dictionary=context.head_views[ix]
  placements.head.texture_key=view.texture_key;placements.head.root=_v(view.root)
  out.head_profile.texture_key=view.texture_key;out.head_profile.root=_v(view.root)
  out.head_profile.abrupt_switch_unproven=true
 placements.head.angle=lerp_angle(float(u.head_world_angle),deg_to_rad(6.0)*f,gaze)
 out.valid=issues.is_empty();out.issues=issues;out.active=true;out.prop_visible=true
 out.contacts.far={"prop":prop+_offset(support_tc-_v(tablet_parts.tablet.root),pa,s,f),"hand":far_wrist+support_delta,"locked":p>=0.25}
 out.contacts.near.locked=false
 out.storage_owner="hip_storage" if p<0.25 else "far_hand"
 out.controls.draw_progress=p;out.controls.gaze_progress=gaze
 out.status="WIP spatial candidate; layer clearance and source seams require raster review"
 return out

func _continuous_elbow(shoulder:Vector2,wrist:Vector2,l1:float,l2:float,f:float) -> Dictionary:
 var check:Dictionary=_elbow(shoulder,wrist,l1,l2)
 if not check.valid:return check
 var distance:float=shoulder.distance_to(wrist)
 var toward:Vector2=(wrist-shoulder)/distance
 var along:float=(l1*l1-l2*l2+distance*distance)/(2.0*distance)
 var high:float=sqrt(maxf(0.0,l1*l1-along*along))
 # One branch over the whole caller trajectory, mirrored by facing only.
 return {"valid":true,"at":shoulder+toward*along+Vector2(-toward.y,toward.x)*high*f}
