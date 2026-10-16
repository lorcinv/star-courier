extends SceneTree
## Component-only reconstruction gate. Does not claim original art restoration,
## main-loop QA, final gaze/head acceptance or correction of C2 motion failures.
const Clerk=preload("res://scripts/clerk_recovery_motion_2d.gd")
const Npc=preload("res://scripts/npc_sprite_2d.gd")
var passed:int=0
var failed:int=0
const CAST:Dictionary={"human_courier":"human","elf_archivist":"elf","alien_botanist":"alien","robot_machinist":"robot"}
const ACCESSORIES:Dictionary={"human_courier":["none"],"elf_archivist":["none","book_pouch","map_case"],"alien_botanist":["none","seed_pod","field_vial"],"robot_machinist":["none","tool_pack","power_cell"]}
const PARCEL:Dictionary={"human_courier":Vector2(135.23,115.37),"elf_archivist":Vector2(141,123),"alien_botanist":Vector2(140,135),"robot_machinist":Vector2(140,132)}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func run() -> void:
 test_clerk()
 test_npcs()
 print("RECOVERY_PROFILE_RESULT passed=",passed," failed=",failed)
 quit(1 if failed else 0)

func test_clerk() -> void:
 for height in [120.0,210.0,240.0]:
  for right in [true,false]:
   var sprite:=Sprite2D.new();root.add_child(sprite);sprite.position=Vector2(400,496)
   var motion=Clerk.new(sprite,"clerk",height)
   check(motion.apply_idle(right),"clerk quiet available")
   check(motion._rig_ready and motion._rig.visible and sprite.texture==null,"one recovered rigid body")
   check(motion._record.run.is_empty() and motion._record.walk.is_empty(),"no canonical phantom/run frames")
   check(motion.debug_snapshot().diagnostics.is_empty(),"clerk recovery has no missing assets")
   check(is_equal_approx(motion.walk_cycle_distance(),92.0*height/240.0),"actual rigid cycle length")
   var target:Vector2=motion.dialogue_anchor_parent("parcel",right)
   var relative:=Vector2(30.26,107.3)-Vector2(85.59,247.59)
   if right:relative.x=-relative.x
   check(target.distance_to(sprite.position+relative*height/240.0)<0.001,"pure future authored parcel")
   check(not motion.pose_anchor_parent("parcel").is_finite(),"quiet hands never own parcel")
   var child_count:int=sprite.get_child_count()+motion._rig.get_child_count()
   var rig_textures:int=motion._rig_textures.size()
   var distance:float=0.0
   for state in ["start","move","inertial_stop","stop","idle"]:
    if state in ["start","move","inertial_stop"]:
     distance+=1.0;sprite.position.x+=1.0 if right else -1.0
    check(motion.apply_player_pose(state,distance,right,true,distance/60.0),"clerk state "+state)
    check(motion.debug_snapshot().player_state==state,"clerk preserves five-state API")
   target=motion.dialogue_anchor_parent("parcel",right)
   for gesture in ["reach","align","ready"]:
    check(motion.apply_gesture(gesture,right),"clerk tablet "+gesture)
    check(not motion._rig.visible and sprite.texture!=null,"tablet one full body")
    check(motion.dialogue_anchor_parent("parcel",right).distance_to(target)<0.001,"tablet cannot alter future parcel")
   for handoff in [false,true]:
    check(motion.apply_dialogue(handoff,right),"historical explicit dialogue")
    check(not motion._rig.visible and sprite.texture!=null,"dialogue one full body")
    if handoff:check(motion.pose_anchor_parent("parcel").distance_to(target)<0.001,"future equals actual handoff")
   motion.restore_original()
   check(motion._rig.visible and sprite.texture==null,"quiet return no waving")
   check(sprite.get_child_count()+motion._rig.get_child_count()==child_count and motion._rig_textures.size()==rig_textures,"clerk node/texture plateau")
   sprite.hide();var before:Dictionary=motion.debug_snapshot()
   check(not motion.apply_dialogue(true,right),"hidden clerk dialogue refused")
   check(not motion.apply_player_pose("move",distance+1,right,true,10),"hidden clerk pose refused")
   check(motion.debug_snapshot()==before,"hidden clerk visual snapshot stable")
   sprite.show();motion.apply_idle(right)
   motion.set_visual_context(12,false)
   check(not motion.apply_dialogue(true,right),"disabled clerk full pose frozen")
   motion.set_visual_context(13,true)
   sprite.free()
   check(not motion.apply_idle(right),"freed clerk weak target safe")

func test_npcs() -> void:
 for id in CAST:
  for accessory in ACCESSORIES[id]:
   for height in [120.0,215.0,240.0]:
    var actor=Npc.new();root.add_child(actor);actor.position=Vector2(150,488)
    var binding:Dictionary={"appearance_id":id,"species":CAST[id],"appearance_seed":157,"accessory_id":accessory}
    var saved:String=JSON.stringify(binding)
    check(actor.configure(binding,height),"NPC config "+id+"/"+accessory)
    check(JSON.stringify(binding)==saved,"caller binding immutable")
    check(not actor.has_rigid_motion(),"raster never claims rigid")
    check(actor.supports_state_locomotion()==(id=="human_courier"),"preserved state scope")
    check(actor.supports_counter_transfer_pose()==(id=="human_courier"),"preserved human handoff scope")
    check(actor.texture.resource_path=="res://assets/2d_v5/npcs/walk_exit/"+id+"/neutral-pixel.png","exact neutral raster")
    check(actor.pose=="idle" and not actor.pose_contains_parcel(),"quiet lowered empty hands")
    check(actor.debug_snapshot().foot_point.distance_to(actor.position)<0.001,"neutral foot registered")
    var handoff_foot:=Vector2(73.19,247.78) if id=="human_courier" else Vector2(96,248)
    var target:Vector2=actor.position+(PARCEL[id]-handoff_foot)*height/240.0
    check(actor.parcel_point().distance_to(target)<0.001,"neutral future handoff stable")
    for right in [true,false]:
     check(actor.set_walk(0,right),"NPC start walk")
     check(actor.set_walk(2,right),"NPC advances walk")
     check(actor.parcel_point().distance_to(target)<0.001,"walk does not donate parcel anchor")
     actor._rig_facing_right=right;actor.set_pose(false)
     check(actor.texture.resource_path.ends_with("/neutral-pixel.png") and actor.flip_h==right,"native-left neutral facing")
     if accessory!="none":
      check(actor._accessory.visible and actor._accessory.flip_h==not right,"semantic accessory mirroring")
      var hip:Vector2=actor._point(actor._motion_frame.hip_anchor)
      check(actor._accessory.position.distance_to(actor._art_point(hip))<0.001,"neutral accessory follows actual hip")
    actor.set_conversation(true)
    check(actor.pose=="conversation" and actor.texture.resource_path.ends_with("/idle-pixel.png") if id!="human_courier" else actor.pose=="conversation" and actor.texture.resource_path.ends_with("/customer-idle-pixel.png"),"raised hands only explicit conversation")
    actor.set_pose(true)
    check(actor.pose=="handoff" and actor.pose_contains_parcel()==(id!="human_courier"),"historical painted parcel semantics")
    check(actor.parcel_point().distance_to(target)<0.001,"handoff same parcel target")
    actor.set_conversation(false);actor.set_pose(false)
    check(actor.texture.resource_path.ends_with("/neutral-pixel.png"),"conversation closes to neutral")
    if id=="human_courier":
     for state in ["idle","start","move","inertial_stop","stop"]:
      check(actor.set_locomotion(state,3,true,2),"human state "+state)
    var nodes:int=actor.get_child_count();var texture_count:int=actor.debug_snapshot().texture_cache_size
    for i in 10:
     actor.set_conversation(true);actor.set_pose(true);actor.set_conversation(false);actor.set_pose(false)
    check(actor.get_child_count()==nodes and actor.debug_snapshot().texture_cache_size==texture_count,"NPC cache/layer plateau")
    actor.hide();var art:Texture2D=actor.texture
    actor.set_conversation(true);actor.set_conversation(false)
    check(not actor.visible,"conversation cannot revive hidden NPC")
    check(not actor.set_walk(500,true) and actor.texture==art,"hidden motion frozen")
    actor.show();actor.set_visual_context(50,false)
    art=actor.texture
    check(not actor.set_walk(501,true) and actor.texture==art,"disabled motion frozen")
    actor.set_visual_context(51,true);actor.set_pose(false)
    check(actor.binding_snapshot()==binding,"identity/accessory stable across poses")
    check(actor.debug_snapshot().diagnostics.is_empty(),"NPC recovery no asset errors")
    actor.free()
