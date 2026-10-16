extends SceneTree
const Pose=preload("res://scripts/clerk_rigid_pose_2d.gd")
const Motion=preload("res://scripts/clerk_rigid_motion_2d.gd")
var passed:int=0
var failed:int=0
var record:Dictionary={}
var max_support_drift:float=0.0
var max_stop_entry_delta:float=0.0
var max_reach_error:float=0.0
var max_settled_knee_flex:float=0.0
var min_settled_knee_flex:float=180.0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func model(height:float=210.0) -> RefCounted:
 var p=Pose.new();check(p.configure(record,height),"model config");return p
func validate(p:RefCounted, previous:Dictionary={}) -> void:
 check(p.feet.near.planted or p.feet.far.planted,"at least one real support")
 for side in ["far","near"]:
  var joint:Dictionary=p.joints[side];var leg:Dictionary=record.legs[side]
  var scale:float=p.target_height/240.0
  check(absf(joint.hip.distance_to(joint.knee)-float(leg.thigh_length)*scale)<.001,"rigid thigh length")
  check(absf(joint.knee.distance_to(joint.ankle)-float(leg.shin_length)*scale)<.001,"rigid shin length")
  if not previous.is_empty() and previous.feet[side].planted and p.feet[side].planted and previous.feet[side].landing_id==p.feet[side].landing_id:
   var drift:float=previous.feet[side].position.distance_to(p.feet[side].position)
   max_support_drift=maxf(max_support_drift,drift)
   check(drift<.001,"same support shoe never slides")
 max_reach_error=maxf(max_reach_error,p.max_reach_error)
 check(p.max_reach_error<.001,"IK can reach exact ankle without scaling")
func run() -> void:
 record=JSON.parse_string(FileAccess.get_file_as_string("res://assets/2d_v5/actors/rig_motion_v1/rig-registration.json"))
 for height in [120.0,210.0,240.0]:
  for right in [true,false]:
   var sign_x:float=1.0 if right else -1.0
   for phase in 65:
    var p=model(height);var origin:=Vector2(400,496);var d:float=0;var clock:float=0
    p.update("idle",d,origin,right,clock)
    for i in range(phase+1):
     var before:Dictionary=p.snapshot();d+=p.half_step()/32.0;origin.x+=sign_x*p.half_step()/32.0;clock+=1.0/60.0
     p.update("start" if i<4 else "move",d,origin,right,clock);validate(p,before)
    var before_stop:Dictionary=p.snapshot()
    p.update("stop",d,origin,right,clock+.016,.01)
    for side in ["near","far"]:
     var jump:float=p.feet[side].position.distance_to(before_stop.feet[side].position)
     max_stop_entry_delta=maxf(max_stop_entry_delta,jump)
     check(jump<.001,"stop capture has no first-frame snap")
    var support:String=p.support;var planted:Vector2=p.feet[support].position
    for i in 30:
     var before:Dictionary=p.snapshot();clock+=1.0/60.0
     p.update("stop" if i<7 else "idle",d,origin,right,clock,minf(.12,i/60.0));validate(p,before)
     check(p.feet[support].position.distance_to(planted)<.001,"selected stop support remains latched")
    check(p.settled and not p.settling,"recovery reaches supported idle")
    for side in ["near","far"]:
     var j:Dictionary=p.joints[side]
     var flex:float=rad_to_deg(acos(clampf((j.knee-j.hip).normalized().dot((j.ankle-j.knee).normalized()),-1.0,1.0)))
     max_settled_knee_flex=maxf(max_settled_knee_flex,flex);min_settled_knee_flex=minf(min_settled_knee_flex,flex)
    var resting:Dictionary=p.snapshot()
    for i in 40:
     clock+=1.0/60.0;p.update("idle",d,origin,right,clock)
     for side in ["near","far"]:check(p.feet[side].position==resting.feet[side].position,"settled stance persists through idle")
    var frozen:Dictionary=p.snapshot();p.update("idle",d,origin,right,clock+10,0,false)
    check(p.snapshot()==frozen,"inactive freeze is visually exact")
    p.update("idle",d,origin,right,clock+12)
    check(absf(p.pose_time-frozen.pose_time)<0.000000001,"resume excludes inactive elapsed time")
    # Reverse from the supported stance; root input/physics remain external.
    for i in 70:
     var before:Dictionary=p.snapshot();d+=.75;origin.x-=sign_x*.75;clock+=1.0/60.0
     p.update("start" if i<8 else "move",d,origin,not right,clock+12);validate(p,before)
    # The obstacle case has travel state but no actual displacement.
    var blocked:Dictionary=p.snapshot()
    for i in 10:p.update("move",d+10,origin,not right,clock+13)
    for side in ["near","far"]:check(p.feet[side].position==blocked.feet[side].position,"no actual displacement means no marching")
    check(not p.update("run",d,origin,right,clock),"no run state")
    check(not p.update("move",NAN,origin,right,clock),"invalid input rejected")
    p.update("idle",0,origin,right,clock+20);check(p.distance_rebases>0,"distance reset rebased")
 # Diagonal connector (world feet are not a horizontal-only shader illusion).
 var route=model();var at:=Vector2(400,496);var dist:float=0;route.update("idle",0,at,true,0)
 for i in 300:
  var before:Dictionary=route.snapshot();var delta:=Vector2(1,.25) if i<80 else Vector2(1,0)
  at+=delta;dist+=delta.length();route.update("move",dist,at,true,i/60.0);validate(route,before)
 test_adapter()
 print("RIGID CLERK STAGING: ",passed," passed, ",failed," failed; support drift=",max_support_drift,"; stop entry=",max_stop_entry_delta,"; reach error=",max_reach_error)
 print("Settled knee flex range across phase/facing/scale: ",min_settled_knee_flex," to ",max_settled_knee_flex," degrees")
 print("Mechanics only. No GPU, native pixels, visual acceptance or final joint-art approval.")
 quit(1 if failed else 0)
func test_adapter() -> void:
 for right in [true,false]:
  var sprite:=Sprite2D.new();root.add_child(sprite);sprite.position=Vector2(400,496)
  sprite.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png");sprite.centered=false;sprite.scale=Vector2.ONE*.875
  var m=Motion.new(sprite,"clerk",210.0)
  check(m._rig_ready,"adapter art and rig loaded")
  check(m.apply_idle(right),"rig idle")
  var nodes:int=sprite.get_child_count()+m._rig.get_child_count();var textures:int=m._rig_textures.size()
  var previous_layer:int=-1000
  for part in m._rig.get_children():
   check(part.z_index==0,"all rigid pieces inherit actor shop depth")
   var layer:int=int(part.get_meta("rig_layer"))
   check(layer>=previous_layer,"near/far/torso order comes from sorted siblings")
   previous_layer=layer
  var distance:float=0
  for i in 180:
   distance+=1.1;sprite.position.x+=1.1*(1 if right else -1)
   m.set_visual_context(i/60.0,true,false)
   check(m.apply_walk(distance,right),"escort/shared walk API")
   var snap:Dictionary=m.debug_snapshot()
   check(snap.head_size_parent==Vector2(91,79.625),"audited canonical head scale preserved")
   check(sprite.rotation==0 and sprite.scale==Vector2.ONE and sprite.material==null,"no owner rocking/shear/resize")
   for side in ["near","far"]:
    var boot:Sprite2D=m._parts[side+"_boot"]
    var spec:Dictionary=m._rig_data.parts[side+"_boot"]
    var sole:Vector2=boot.transform*Vector2(spec.sole[0],spec.sole[1])+sprite.position
    check(sole.distance_to(m._model.feet[side].position)<.001,"real boot transform agrees with sole target")
  m.apply_player_pose("stop",distance,right,true,3.1,0)
  for i in 30:m.advance_visual(3.1+i/60.0)
  check(m._model.settled,"shared owner clock advances settle into idle")
  var before:Dictionary=m.debug_snapshot();sprite.hide()
  m.advance_visual(10);check(m.debug_snapshot()==before,"hidden entire rig frozen")
  sprite.show();m.advance_visual(11)
  for gesture in ["reach","align","ready"]:
   check(m.apply_gesture(gesture,right),"accepted tablet gesture retained")
   check(not m._rig.visible and sprite.texture!=null,"one representation only during tablet")
   check(sprite.texture.resource_path=="res://"+str(m._record.gestures[gesture].runtime),"exact tablet source retained")
   check(m.current_frame().body_height==240,"tablet registration scale retained")
  for handoff in [false,true]:
   var expected:Vector2=m.dialogue_anchor_parent("parcel",right)
   check(m.apply_dialogue(handoff,right),"dialogue path remains explicit")
   if handoff:check(expected.distance_to(m.pose_anchor_parent("parcel"))<.001,"future parcel query equals actual exact handoff")
  m.restore_original();check(m._rig.visible and sprite.texture==null,"quiet return only relaxed empty rig hands")
  check(sprite.get_child_count()+m._rig.get_child_count()==nodes and m._rig_textures.size()==textures,"fixed nodes/textures plateau")
  check(m.apply_run(distance,right) and m.debug_snapshot().pose=="walk","legacy run cannot select run art")
  sprite.free();check(not m.apply_idle(right),"freed target rejected")
