extends SceneTree
## Real raster / modal-owner integration in isolated XDG saves. These headless
## checks establish lifecycle and registration, not native-window visual QA.
const Npc=preload("res://scripts/npc_sprite_2d.gd")
const Main=preload("res://scenes/main.tscn")
const CASES:Dictionary={
 "human_courier":["none"],
 "elf_archivist":["none","book_pouch","map_case"],
 "alien_botanist":["none","seed_pod","field_vial"],
 "robot_machinist":["none","tool_pack","power_cell"]
}
const FEET:Dictionary={"human_courier":Vector2(73.19,247.78),"elf_archivist":Vector2(96,248),"alien_botanist":Vector2(96,248),"robot_machinist":Vector2(96,248)}
const PARCELS:Dictionary={"human_courier":Vector2(135.23,115.37),"elf_archivist":Vector2(141,123),"alien_botanist":Vector2(140,135),"robot_machinist":Vector2(140,132)}
var passed:int=0
var failed:int=0
var records:Dictionary={}
var game

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func frames(count:int=2) -> void:
 for i in count:await process_frame
func binding(id:String,accessory:String) -> Dictionary:
 return {"appearance_id":id,"species":Npc.APPEARANCE_SPECIES[id],"appearance_seed":239,"accessory_id":accessory}
func point(v:Array) -> Vector2:return Vector2(float(v[0]),float(v[1]))
func bounded_layers(node:Sprite2D) -> bool:
 var accessory:Sprite2D=node.get_node_or_null("CompatibleAccessory")
 var arm:Sprite2D=node.get_node_or_null("NeutralFrontArm")
 var rig:Node2D=node.get_node_or_null("HumanRigidCutouts")
 var count:int=int(accessory!=null)+int(arm!=null)+int(rig!=null)
 if node.get_child_count()!=count or count>3:return false
 if rig!=null:
  if node.species!="human" or rig.get_child_count()!=15:return false
  for part in rig.get_children():
   if not part is Sprite2D or part.z_index!=0:return false
 if arm!=null and accessory==null:return false
 if accessory!=null and accessory.z_index!=1:return false
 if arm!=null and (arm.get_index()<=accessory.get_index() or arm.z_index!=2 or arm.scale!=Vector2.ONE):return false
 return true

func layers_match(actor,neutral:bool) -> bool:
 if not bounded_layers(actor):return false
 var snap:Dictionary=actor.debug_snapshot()
 var expected:bool=neutral and actor.accessory_id!="none" and snap.valid
 if bool(snap.front_arm_visible)!=expected:return false
 var arm:Sprite2D=actor.get_node_or_null("NeutralFrontArm")
 if not expected:return arm==null or (not arm.visible and arm.texture==null)
 return arm.texture.resource_path=="res://"+str(records[actor.appearance_id].poses.idle.front_arm_runtime) and arm.offset==actor.offset and arm.position==Vector2.ZERO and not arm.centered and arm.flip_h==actor.flip_h and arm.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST
func pose_raster_matches(actor,path:String) -> bool:
 if actor.species!="human":return actor.texture!=null and actor.texture.resource_path==path
 if actor.texture==null:return actor.pose=="idle" and actor.debug_snapshot().motion.rigid_active and actor._motion._rig.visible
 if actor.pose in ["conversation","handoff"]:
  return actor.texture.resource_path=="res://assets/2d_v5/actors/human_rig_motion_v1/"+actor.pose+"-body.png" and actor.debug_snapshot().motion.canonical_head_overlay
 return actor.texture.resource_path==path
func registered(actor,saved:Dictionary,feet:Vector2,parcel:Vector2) -> bool:
 var physical_scale:bool=actor.scale.is_equal_approx(Vector2.ONE*Npc.DEFAULT_HEIGHT/240.0)
 if actor.species=="human" and actor.texture==null:
  physical_scale=actor.scale==Vector2.ONE and actor.debug_snapshot().motion.head_size_parent.distance_to(Vector2(99,80)*Npc.DEFAULT_HEIGHT/240.0)<.001
 return actor.binding_snapshot()==saved and actor.debug_snapshot().foot_point.is_equal_approx(feet) and actor.parcel_point().is_equal_approx(parcel) and physical_scale
func accessory_registered(actor,pose:String) -> bool:
 if actor.accessory_id=="none":return not actor.debug_snapshot().accessory_visible
 var data:Dictionary=records[actor.appearance_id].accessory_options[actor.accessory_id]
 var child:Sprite2D=actor.get_node("CompatibleAccessory")
 var anchor:Vector2=point(data.world_anchors.get(pose,data.world_anchors.idle))
 return child.visible and child.texture.resource_path=="res://"+str(data.runtime) and child.position==actor.offset+anchor and child.offset==-point(data.local_anchor) and child.scale==Vector2.ONE
func exact_front_arm_pixels(actor) -> bool:
 var arm:Sprite2D=actor.get_node("NeutralFrontArm")
 var base:Image=actor.texture.get_image();var overlay:Image=arm.texture.get_image()
 if overlay.get_size()!=base.get_size():return false
 var painted:int=0
 for y in overlay.get_height():
  for x in overlay.get_width():
   var pixel:Color=overlay.get_pixel(x,y)
   if pixel.a>0:
    painted+=1
    if pixel.a!=1.0 or pixel!=base.get_pixel(x,y):return false
 return painted>0 and painted<base.get_width()*base.get_height()/4

func test_identity_lifecycles() -> void:
 var actor=Npc.new();root.add_child(actor);actor.position=Vector2(148,488)
 for id in CASES:
  var data:Dictionary=records[id]
  var neutral_path:String="res://assets/2d_v5/actors/customer-neutral-idle-pixel.png" if id=="human_courier" else "res://assets/2d_v5/npcs/%s/neutral-idle-pixel.png"%id
  var conversation_path:String="res://assets/2d_v5/actors/customer-idle-pixel.png" if id=="human_courier" else "res://assets/2d_v5/npcs/%s/idle-pixel.png"%id
  var handoff_path:String="res://assets/2d_v5/actors/customer-handoff-pixel.png" if id=="human_courier" else "res://assets/2d_v5/npcs/%s/handoff-pixel.png"%id
  check(data.poses.idle.get("gesture",true)==false and data.poses.idle.get("held_parcel",true)==false,"authored neutral declares relaxed empty hands: "+id)
  check("res://"+str(data.poses.conversation.runtime)==conversation_path and conversation_path!=neutral_path,"legacy raised-hand pixels have explicit conversation ownership: "+id)
  for accessory in CASES[id]:
   var saved:Dictionary=binding(id,accessory);var bytes:String=JSON.stringify(saved)
   var label:String=id+"/"+accessory
   check(actor.configure(saved),"configure neutral: "+label)
   var feet:Vector2=actor.position
   var parcel:Vector2=feet+(PARCELS[id]-FEET[id])*Npc.DEFAULT_HEIGHT/240.0
   check(actor.pose=="idle" and pose_raster_matches(actor,neutral_path) and not actor.debug_snapshot().conversation_active,"fresh actor defaults to relaxed neutral: "+label)
   check(actor.offset==-FEET[id] and registered(actor,saved,feet,parcel),"neutral retains exact original feet, identity, scale and parcel anchor: "+label)
   check(layers_match(actor,true) and accessory_registered(actor,"idle"),"neutral accessory sits beneath one exact front-arm layer: "+label)
   if accessory!="none":check(exact_front_arm_pixels(actor),"neutral front arm is an exact opaque subset of the actual body raster: "+label)
   actor.set_conversation(true)
   check(actor.pose=="conversation" and pose_raster_matches(actor,conversation_path) and actor.get_meta("pose")=="conversation","explicit conversation selects original gesture: "+label)
   check(layers_match(actor,false) and accessory_registered(actor,"conversation") and not actor.pose_contains_parcel(),"conversation retains accessory and clears neutral occluder/parcel claim: "+label)
   check(registered(actor,saved,feet,parcel),"conversation cannot move registered feet/transfer anchor or reroll identity: "+label)
   var conversation_texture:Texture2D=actor.texture
   for i in 12:actor.set_conversation(true);actor.set_pose(false)
   check(actor.texture==conversation_texture and registered(actor,saved,feet,parcel),"repeated active-modal updates are idempotent: "+label)
   actor.set_pose(true)
   check(actor.pose=="handoff" and pose_raster_matches(actor,handoff_path) and actor.pose_contains_parcel()==(id!="human_courier"),"handoff retains original painted parcel semantics: "+label)
   check(layers_match(actor,false) and accessory_registered(actor,"handoff") and registered(actor,saved,feet,parcel),"handoff keeps accessory, feet and parcel anchor with no stale neutral arm: "+label)
   actor.set_conversation(false)
   check(actor.pose=="handoff" and not actor.debug_snapshot().conversation_active and pose_raster_matches(actor,handoff_path),"closing conversation clears ownership without interrupting handoff: "+label)
   check(actor.set_walk(42,false),"walk takes over after handoff: "+label)
   var walking:Texture2D=actor.texture
   check(actor.pose=="walk" and not actor.pose_contains_parcel() and layers_match(actor,false),"walk clears neutral foreground and painted parcel claim: "+label)
   check(actor.binding_snapshot()==saved and actor.debug_snapshot().foot_point.is_equal_approx(feet) and actor.parcel_point().is_equal_approx(parcel),"reversed walk retains original identity, foot pivot and future transfer point: "+label)
   actor.set_conversation(true)
   check(actor.pose=="walk" and actor.texture==walking,"conversation ownership never interrupts an in-flight walk: "+label)
   actor.set_pose(false)
   check(actor.pose=="conversation" and pose_raster_matches(actor,conversation_path),"walk cancellation honors a still-open conversation: "+label)
   actor.set_conversation(false)
   check(actor.pose=="idle" and pose_raster_matches(actor,neutral_path) and layers_match(actor,true) and accessory_registered(actor,"idle"),"conversation completion immediately restores exact neutral and foreground: "+label)
   check(registered(actor,saved,feet,parcel) and JSON.stringify(saved)==bytes,"full pose lifecycle leaves caller binding, feet and parcel point unchanged: "+label)
 actor.free()

func test_cancel_hidden_invalid_and_bounds() -> void:
 var actor=Npc.new();root.add_child(actor);actor.position=Vector2(148,488)
 actor.configure(binding("elf_archivist","book_pouch"))
 var accessory:Sprite2D=actor.get_node("CompatibleAccessory");var arm:Sprite2D=actor.get_node("NeutralFrontArm")
 for id in CASES:
  for option in CASES[id]:
   actor.set_conversation(true);actor.set_walk(30,false)
   check(actor.configure(binding(id,option)) and actor.pose=="idle" and not actor.debug_snapshot().conversation_active and layers_match(actor,true),"reconfigure cancels old conversation/motion/foreground state: "+id+"/"+option)
 for hidden_conversation in [false,true]:
  actor.configure(binding("robot_machinist","power_cell"));actor.set_conversation(hidden_conversation);actor.hide()
  var held:Texture2D=actor.texture
  check(not actor.set_walk(90,true) and actor.texture==held and not actor.visible,"hidden actor rejects walk without revealing stale foreground")
  actor.set_conversation(not hidden_conversation)
  check(not actor.visible and not accessory.is_visible_in_tree() and not arm.is_visible_in_tree(),"toggling conversation preserves caller-hidden actor and both hidden layers")
  actor.set_conversation(hidden_conversation)
  check(not actor.visible,"closing or replacing a hidden conversation never resurrects the actor")
  actor.show();actor.set_conversation(false)
  check(actor.pose=="idle" and layers_match(actor,true),"explicit show plus conversation cancellation recovers neutral")
 for bad in [{"appearance_id":"missing"},{"appearance_id":"elf_archivist","species":"robot"},{"species":[]}]:
  actor.configure(binding("elf_archivist","map_case"));actor.set_conversation(true)
  check(not actor.configure(bad),"invalid replacement rejects stale conversation identity")
  actor.set_conversation(true);actor.set_pose(true);actor.set_conversation(false)
  check(not actor.visible and actor.texture==null and not actor.debug_snapshot().valid and not actor.debug_snapshot().accessory_visible and layers_match(actor,false),"invalid actor clears body, compatible accessory and neutral foreground")
  check(bounded_layers(actor) and actor.get_child_count()==2 and actor.parcel_point()==actor.position,"invalid actor keeps only reusable named layers and safe parcel origin")
 actor.configure(binding("alien_botanist","seed_pod"));actor._appearance=actor._appearance.duplicate(true)
 actor._appearance.poses.conversation.runtime="assets/2d_v5/npcs/missing-test-conversation.png"
 actor.set_conversation(true)
 check(not actor.visible and actor.texture==null and not actor.debug_snapshot().accessory_visible and layers_match(actor,false) and actor.debug_snapshot().diagnostics.has("missing_pose_texture:conversation"),"missing explicit conversation art fails visibly in diagnostics without substituting another species")
 # Warm all real paths before measuring shared resource growth.
 for id in CASES:
  for option in CASES[id]:
   actor.configure(binding(id,option));actor.set_conversation(true);actor.set_pose(true);actor.set_walk(40,false);actor.set_gesture("farewell",true);actor.set_conversation(false);actor.set_pose(false)
 var before:Dictionary=actor.debug_snapshot()
 var bounded:bool=true
 for i in 800:
  var ids:Array=CASES.keys();var id:String=ids[i%ids.size()];var options:Array=CASES[id]
  var saved:Dictionary=binding(id,options[(i/4)%options.size()])
  actor.configure(saved);actor.set_conversation(true);actor.set_pose(true);actor.set_walk(float(i%120),i%2==0);actor.set_conversation(false);actor.set_pose(false)
  bounded=bounded and actor.get_child_count()==(3 if id=="human_courier" else 2) and actor.get_child(0)==accessory and actor.get_child(1)==arm and bounded_layers(actor) and layers_match(actor,true) and actor.binding_snapshot()==saved and actor.debug_snapshot().foot_point.is_equal_approx(actor.position)
 var after:Dictionary=actor.debug_snapshot()
 check(bounded,"800 neutral/conversation/handoff/walk/cancel cycles retain the named accessory layers and bounded human rig without feet or identity drift")
 check(before.manifest_load_count==after.manifest_load_count and before.texture_cache_size==after.texture_cache_size and before.texture_load_count==after.texture_load_count,"800 full pose cycles create no new NPC resources or manifest loads")
 check(before.motion.texture_cache_size==after.motion.texture_cache_size and before.motion.texture_load_count==after.motion.texture_load_count,"800 full pose cycles create no new motion resources")
 actor.free()

func ledger() -> Dictionary:
 return {"credits":game.economy.credits,"inventory":game.economy.inventory.duplicate(true),"jobs":game.economy.jobs_today,"deliveries":game.economy.deliveries,"settled":game.economy.settled_ids.duplicate(true)}
func count_nodes(node:Node) -> int:
 var total:int=1
 for child in node.get_children():total+=count_nodes(child)
 return total
func open_owned_fixture(order_id:String) -> bool:
 game._active_story={"contract_id":order_id,"dialogue_id":"neutral-modal-fixture","beat":"fixture"}
 return game.dialogue.begin({"dialogue_id":"neutral-modal-fixture","lines":[{"speaker":"npc","text":"收到。"},{"speaker":"clerk","text":"好的。"}]},{},{"reduced_motion":true,"dialogue_muted":true})
func step(seconds:float) -> void:
 for i in ceili(seconds*120):
  var tween:Tween=game.world._parcel_tween
  if tween!=null:tween.pause();tween.custom_step(1.0/120.0)
  game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0);game._process(1.0/120.0)
func neutral_clerk() -> bool:
 var motion=game.world._clerk_motion;var snap:Dictionary=motion.debug_snapshot()
 if not bool(snap.get("rigid_active",false)) or str(game.world.clerk.get_meta("pose",""))!="idle":return false
 if game.world.clerk.texture!=null or not motion._rig.visible or not bool(snap.get("empty_hands",false)) or not bool(snap.get("relaxed_arms",false)):return false
 if snap.head_size_parent!=Vector2(91,79.625) or game.world.clerk.rotation!=0 or game.world.clerk.scale!=Vector2.ONE:return false
 var head:Sprite2D=motion._parts.head
 if not head.texture.resource_path.begins_with("res://assets/2d_v5/actors/rig_motion_v1/head") or head.scale.abs()!=Vector2.ONE*.875:return false
 for side in ["near","far"]:
  var spec:Dictionary=motion._rig_data.parts[side+"_boot"];var boot:Sprite2D=motion._parts[side+"_boot"]
  var actual:Vector2=boot.transform*Vector2(spec.sole[0],spec.sole[1])+game.world.clerk.position
  if actual.distance_to(snap.rig.feet[side].position)>.001:return false
 return bool(snap.rig.feet.near.planted) or bool(snap.rig.feet.far.planted)
func test_main_modal_ownership() -> void:
 game=Main.instantiate();root.add_child(game)
 game.set_process(false);game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames()
 game.dialogue.cancel(false);game._active_story.clear();game._pending_story.clear()
 game.world._process(3.0);game.world._process(.01)
 check(game.dialogue.modal_changed.is_connected(game._on_dialogue_modal_changed),"actual Main connects the real dialogue modal signal")
 check(not game.world._dialogue_active and neutral_clerk(),"new shop has a neutral clerk without implicit conversation ownership")
 var ids:Array=game.world.customers.keys()
 check(ids.size()>=2,"main fixture includes two separately bound customers")
 if ids.size()<2:return
 var a:String=str(ids[0]);var b:String=str(ids[1])
 var first=game.world.customers[a].node;var second=game.world.customers[b].node
 first.set_pose(false);second.set_pose(false)
 var finances:Dictionary=ledger();var parcel_node:int=game.world.parcel.get_instance_id()
 var parcel_state:String=game.world.parcel_state;var parcel_position:Vector2=game.world.parcel.position
 for finish_mode in ["skip","finish","cancel"]:
  check(open_owned_fixture(b),"real modal opens for explicit second customer: "+finish_mode)
  check(game.world._dialogue_active and game.world._dialogue_order_id==b and second.pose=="conversation" and first.pose=="idle","Main forwards exact story owner rather than all customers or active-contract fallback: "+finish_mode)
  check(str(game.world.clerk.get_meta("pose",""))=="dialogue" and layers_match(second,false),"open modal alone selects clerk conversation and clears NPC neutral arm: "+finish_mode)
  if finish_mode=="skip":game.dialogue.skip_conversation()
  elif finish_mode=="finish":
   for i in 4:game.dialogue.advance()
  else:game.dialogue.cancel(false)
  check(not game.dialogue.is_open() and not game.world._dialogue_active and game.world._dialogue_order_id.is_empty(),"modal dismissal clears ownership synchronously before any next frame: "+finish_mode)
  check(neutral_clerk() and first.pose=="idle" and second.pose=="idle" and layers_match(second,true),"skip/finish/cancel immediately restore neutral actor pixels: "+finish_mode)
  check(ledger()==finances and game.world.parcel.get_instance_id()==parcel_node and game.world.parcel_state==parcel_state and game.world.parcel.position==parcel_position,"dialogue-only lifecycle has no financial or parcel side effects: "+finish_mode)
 game._active_story.clear()
 var node_count:int=count_nodes(game);var tweens:int=get_processed_tweens().size()
 var actor_id:int=second.get_instance_id();var child_id:int=second.get_child(0).get_instance_id();var arm_id:int=second.get_child(1).get_instance_id()
 var bounded:bool=true
 for i in 64:
  var owner:String=a if i%2==0 else b
  bounded=bounded and open_owned_fixture(owner)
  game.dialogue.skip_conversation()
  bounded=bounded and neutral_clerk() and not game.world._dialogue_active and first.pose=="idle" and second.pose=="idle" and count_nodes(game)==node_count and second.get_instance_id()==actor_id and second.get_child(0).get_instance_id()==child_id and second.get_child(1).get_instance_id()==arm_id and get_processed_tweens().size()<=tweens
 check(bounded,"64 real Main modal cycles keep exact actor/layer nodes, no tween growth and immediate neutral state")
 check(ledger()==finances and game.world.parcel.get_instance_id()==parcel_node,"repeated modal completion cannot spend money, alter quotas or replace the parcel")
 # Complete one authentic acceptance dialogue, then let loading/return use the
 # same production controller path. Completion may intentionally own handoff art.
 game._action("accept_contract",a)
 for i in 1800:
  if game.dialogue.is_open():break
  step(1.0/120.0)
 check(game.dialogue.is_open() and game.world._dialogue_active and game.world._dialogue_order_id==a,"authentic acceptance gives dialogue ownership to its persisted order")
 var accepted:Dictionary=ledger()
 game.dialogue.skip_conversation()
 check(not game.world._dialogue_active and game.world._dialogue_order_id.is_empty() and not first.debug_snapshot().conversation_active and neutral_clerk(),"authentic skip clears gestures immediately while preserving loading handoff ownership")
 game._skip_loading_scene(a);await frames()
 check(game.economy.is_cargo_loaded(a) and game.world.is_parcel_loaded(a) and game.page=="workshop","actual acceptance still reaches one durable loaded parcel")
 check(ledger()==accepted and game.world.parcel.get_instance_id()==parcel_node,"actual loading keeps the existing financial and parcel lifecycle intact")
 game.navigate("hub");game.world.prepare_counter_interaction();step(12.0);await frames()
 check(game.world._clerk_state=="counter" and neutral_clerk() and not game.world._dialogue_active,"shop return ends in relaxed neutral without resurrecting completed conversation")
 check(not first.visible and not first.debug_snapshot().conversation_active and not game.dialogue.is_open(),"departed customer remains hidden and silent after return")
 game.queue_free();await frames()

func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():push_error("Isolated XDG_DATA_HOME is required");quit(2);return
 records=JSON.parse_string(FileAccess.get_file_as_string(Npc.NPC_MANIFEST)).appearances
 records.human_courier=JSON.parse_string(FileAccess.get_file_as_string(Npc.ACTOR_MANIFEST)).actors.customer
 test_identity_lifecycles()
 test_cancel_hidden_invalid_and_bounds()
 await test_main_modal_ownership()
 print("NEUTRAL_ACTOR_LIFECYCLE passed=",passed," failed=",failed," native_window_visuals=false")
 quit(1 if failed else 0)
