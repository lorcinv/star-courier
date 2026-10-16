extends SceneTree
const Motion=preload("res://scripts/clerk_single_walk_2d.gd")
const Original=preload("res://scripts/actor_motion_2d.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func sprite() -> Sprite2D:
 var s:=Sprite2D.new();root.add_child(s);s.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png");s.centered=false;s.offset=-Vector2(85.59,247.59);s.scale=Vector2.ONE*.875;return s
func run() -> void:
 for right in [true,false]:
  var s:=sprite();s.position=Vector2(400,496);var m=Motion.new(s,"clerk",210)
  check(m.debug_snapshot().neutral_ready,"registered neutral is available")
  check(m._record.run.is_empty(),"single-walk record has zero run frames")
  check(m.debug_snapshot().texture_cache_size==38,"only 38 clerk textures warmed; run originals are not loaded")
  var d:float=0.0
  check(m.apply_player_pose("idle",d,right),"idle applies")
  var neutral:Dictionary=m.debug_snapshot();var expected:Vector2=neutral.head_size_parent
  check(expected.is_equal_approx(Vector2(91,79.625)),"canonical head has exact existing tablet-check scale")
  check(s.texture.resource_path.ends_with("clerk-neutral-canonical-pixel.png"),"default idle has relaxed hands-down art")
  for cycle in 5:
   for state in ["start","move","inertial_stop","stop","idle"]:
    for frame in 32:
     if state in ["start","move","inertial_stop"]:d+=.75;s.position.x=400+(d if right else -d)
     check(m.apply_player_pose(state,d,right),"explicit player state applies "+state)
     var snap:Dictionary=m.debug_snapshot()
     check(snap.player_state==state,"reports caller-owned semantic state")
     check(snap.pose=="walk" if state in ["start","move","inertial_stop"] else snap.pose==state,"single cycle or neutral is used")
     check(snap.head_size_parent.is_equal_approx(expected),"idle/start/move/inertia/stop canonical head dimensions never change")
     check(snap.foot_point.distance_to(s.position)<.001,"all player states keep registered sole origin")
     check(snap.facing_right==right and s.flip_h==not right,"state facing registration")
     var snapshot:Dictionary=m.debug_snapshot()
     check(m.apply_player_pose(state,d,right) and m.debug_snapshot()==snapshot,"fixed distance has no autonomous pose motion")
  var before:Dictionary=m.debug_snapshot();s.hide()
  check(not m.apply_player_pose("move",d+50,not right) and m.debug_snapshot()==before,"hidden player freezes exact snapshot")
  s.show();m.apply_player_pose("start",d+.1,right);m.apply_player_pose("idle",d+.1,right,false)
  var freeze:Dictionary=m.debug_snapshot()
  for i in 120:m.apply_player_pose("idle",d+.1,right,true)
  check(m.debug_snapshot()==freeze,"focus resume has no extra settle animation")
  check(m.apply_run(d+.2,right) and m.debug_snapshot().pose=="walk","stale run API is restricted to single walk artwork")
  m.apply_player_pose("move",0,right);check(m.debug_snapshot().distance_rebases>0,"distance reset is rebased")
  m.apply_player_pose("move",10000,right);check(m.debug_snapshot().distance_rebases>1,"distance jump is rebased")
  for handoff in [false,true]:
   check(m.apply_dialogue(handoff,right),"dialogue pose is explicitly requested")
   check(m.debug_snapshot().head_size_parent.is_equal_approx(expected),"conversation shares exact canonical head scale")
   check(m.pose_anchor_parent("parcel").is_finite(),"registered conversation parcel anchor is available")
   var frame:Dictionary=m.current_frame();var p:=Vector2(float(frame.hand_and_parcel_anchors.parcel[0]),float(frame.hand_and_parcel_anchors.parcel[1]))
   check(m.pose_anchor_parent("parcel").distance_to(s.transform*m.anchor_local(p))<.001,"parcel anchor uses the same full scale and mirror as the pose")
   m.restore_original();check(s.texture.resource_path.ends_with("clerk-neutral-canonical-pixel.png"),"quiet restoration never invokes conversation art")
  for pose in ["reach","align","ready"]:
   check(m.apply_gesture(pose,right),"tablet pose applies unchanged")
   check(s.texture.resource_path=="res://"+str(m._record.gestures[pose].runtime),"tablet uses the exact accepted texture")
   check(s.material==null and m.debug_snapshot().foot_point.distance_to(s.position)<.001,"tablet clears stance and keeps sole registration")
   if pose=="ready":check(m.debug_snapshot().head_size_parent.is_equal_approx(expected),"upright tablet and neutral/walk/talk heads have identical dimensions")
  for current in ["neutral","tablet","walking"]:
   if current=="neutral":m.apply_idle(right)
   elif current=="tablet":m.apply_gesture("ready",right)
   else:m.apply_walk(11000,right)
   for future_right in [false,true]:
    var before_query:Dictionary=m.debug_snapshot();var texture_before:Texture2D=s.texture;var offset_before:Vector2=s.offset;var flip_before:bool=s.flip_h
    for anchor in ["left","right","parcel"]:
     var frame:Dictionary=m._dialogue.handoff;var point:Array=frame.hand_and_parcel_anchors[anchor];var foot:Array=frame.foot_anchor
     var local:=Vector2(float(point[0])-float(foot[0]),float(point[1])-float(foot[1]));local.x*=1.0 if future_right else -1.0
     var expected_anchor:Vector2=s.position+local*.875
     check(m.dialogue_anchor_parent(anchor,future_right).distance_to(expected_anchor)<.001,"future handoff query is correct while current pose is "+current)
    check(m.debug_snapshot()==before_query and s.texture==texture_before and s.offset==offset_before and s.flip_h==flip_before,"future handoff query is pure")
  m.apply_idle(right);var query_before:Vector2=m.dialogue_anchor_parent("parcel",false)
  s.offset=Vector2(333,-777);s.flip_h=not s.flip_h;s.scale=Vector2(2,3)
  check(m.dialogue_anchor_parent("parcel",false).distance_to(query_before)<.001,"future query ignores stale current offset, flip and pose scale")
  m.apply_dialogue(true,false)
  check(m.dialogue_anchor_parent("parcel",false).distance_to(m.pose_anchor_parent("parcel"))<.001,"future query equals eventual fully registered handoff anchor")
  check(not m.dialogue_anchor_parent("missing",true).is_finite(),"unknown future anchor returns invalid point without state mutation")
  check(m.debug_snapshot().texture_cache_size==38 and s.get_child_count()==0,"repeated states plateau at 38 textures and zero nodes")
  check(str(Original._actors.clerk.walk[0].runtime).contains("locomotion_v2"),"shared actor records are not mutated")
  s.free();check(not m.apply_player_pose("move",12000,right),"weak target rejects use after free")
 print("CLERK SINGLE WALK STAGING: ",passed," passed, ",failed," failed")
 quit(1 if failed else 0)
