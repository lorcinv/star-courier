extends SceneTree
## Presentation integration only: real generated NPC sprites and registered
## transfer poses. No player save, economy mutation, GUI proof or Spine claim.
const World=preload("res://scripts/world_view_2d.gd")
const Npc=preload("res://scripts/npc_sprite_2d.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const CASES:Dictionary={
 "human_courier":{"species":"human","accessories":["none"]},
 "elf_archivist":{"species":"elf","accessories":["book_pouch","map_case"]},
 "alien_botanist":{"species":"alien","accessories":["seed_pod","field_vial"]},
 "robot_machinist":{"species":"robot","accessories":["tool_pack","power_cell"]}
}
var passed:int=0
var failed:int=0
var viewport:SubViewport
var world
var manifest:Dictionary={}

func _initialize() -> void:run.call_deferred()

func check(condition:bool,label:String) -> void:
 if condition:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func order(id:String,appearance:String="elf_archivist",accessory:String="map_case") -> Dictionary:
 return {"contract_id":id,"status":"accepted","appearance_id":appearance,"appearance_seed":18391,"species":CASES[appearance].species,"accessory_id":accessory,"story_id":Stories.PROFILES[appearance].story_id,"story_node":2}

func update(contracts:Array,current:String="",phase:String="day") -> void:
 world.update_shop_state({"phase":phase,"contracts":contracts,"active_contract_id":current})

func accept(contract:Dictionary) -> Tween:
 update([],"")
 var available:Dictionary=contract.duplicate(true);available.status="available"
 update([available]);world._process(3.0)
 update([contract],str(contract.contract_id))
 var tween:Tween=world._parcel_tween
 if tween!=null:tween.pause()
 return tween

func counter_parcels() -> int:
 var count:int=1 if world.parcel.visible else 0
 # Verified on actual generated pixels: the clerk receives with empty hands.
 # Human customer and clerk have empty hands; three nonhuman poses have boxes.
 for entry in world.customers.values():
  if entry.node.visible and entry.node.pose_contains_parcel():count+=1
 return count

func idle_poses() -> bool:
 if world.clerk.get_meta("pose","")!="idle":return false
 for entry in world.customers.values():
  if entry.node.pose!="idle":return false
 return true

func pose_accessory_registered(actor,pose:String) -> bool:
 if actor.accessory_id=="none":return actor.get_child_count()==0 or not actor.get_child(0).visible
 var data:Dictionary=manifest.appearances[actor.appearance_id].accessory_options[actor.accessory_id]
 var sprite:Sprite2D=actor.get_node("CompatibleAccessory")
 var anchor:Vector2=Vector2(data.world_anchors[pose][0],data.world_anchors[pose][1])
 var local_anchor:Vector2=Vector2(data.local_anchor[0],data.local_anchor[1])
 return sprite.visible and sprite.texture.resource_path=="res://"+str(data.runtime) and sprite.position==actor.offset+anchor and sprite.offset==-local_anchor and sprite.scale==Vector2.ONE

func test_species_and_phases() -> void:
 for appearance in CASES:
  for accessory in CASES[appearance].accessories:
   var contract:Dictionary=order("cast/"+appearance+"/"+accessory,appearance,accessory)
   var before:String=JSON.stringify(contract)
   var tween:Tween=accept(contract)
   var actor=world.customers[contract.contract_id].node
   var label:String=appearance+"/"+accessory
   check(actor.get_script()==Npc and actor.appearance_id==appearance and actor.species==CASES[appearance].species,"world creates exact saved species: "+label)
   check(actor.accessory_id==accessory and actor.appearance_seed==18391,"world retains saved compatible accessory and seed: "+label)
   check(actor.get_meta("contract_id")==contract.contract_id and actor.get_meta("story_id")==contract.story_id and actor.get_meta("story_node")==2,"story metadata stays bound to world actor: "+label)
   var portrait:Dictionary=Stories.actor_metadata(contract)
   check(portrait.appearance_id==actor.appearance_id and portrait.species==actor.species and portrait.accessory_id==actor.accessory_id and ResourceLoader.exists(portrait.portraits.neutral),"world and portrait resolve the same persisted identity: "+label)
   check(JSON.stringify(contract)==before,"presentation does not mutate bound contract: "+label)
   check(actor.position==Vector2(148,488) and actor.debug_snapshot().foot_point.is_equal_approx(actor.position) and actor.scale.is_equal_approx(Vector2.ONE*215.0/240.0),"uniform Q body and real feet stay registered: "+label)
   check(actor.z_index==10 and world.actors_root.z_index==3 and world.foreground_root.z_index==8 and world.clerk.z_index==0,"approved customer-front clerk-behind counter ordering: "+label)
   check(world._parcel_phase=="customer_handoff" and actor.pose=="handoff" and world.parcel.visible==not actor.pose_contains_parcel() and world.clerk.get_meta("pose")=="idle" and counter_parcels()==1,"customer handoff chooses one parcel from verified pose pixels: "+label)
   check(pose_accessory_registered(actor,"handoff"),"handoff accessory uses its registered anchor: "+label)
   var registered_origin:Vector2=actor.parcel_point()
   tween.custom_step(World.CUSTOMER_HANDOFF_DURATION+.01)
   check(world._parcel_phase=="counter_transfer" and idle_poses() and world.parcel.visible and counter_parcels()==1,"external transfer begins only after both actors are idle: "+label)
   check(world._counter_transfer_start.is_equal_approx(registered_origin) and world.parcel.position.distance_to(registered_origin)<3.0,"external parcel leaves species-specific painted hand anchor: "+label)
   check(pose_accessory_registered(actor,"idle"),"idle accessory returns to its registered anchor: "+label)
   tween.custom_step(World.COUNTER_TRANSFER_DURATION)
   check(world._parcel_phase=="clerk_handoff" and actor.pose=="idle" and world.clerk.get_meta("pose")=="handoff" and world.parcel.visible and counter_parcels()==1,"empty-handed clerk receives one continuously visible external parcel: "+label)
   check(world.parcel.position.is_equal_approx(world._actor_parcel_point(world.clerk,"clerk")),"external parcel meets the clerk's registered receiving-hands anchor: "+label)
   tween.custom_step(World.CLERK_HANDOFF_DURATION+.02)
   check(world._parcel_phase=="counter" and world.parcel_state=="counter" and world._parcel_tween==null and idle_poses() and world.parcel.visible and counter_parcels()==1,"completed handoff has one counter parcel and no live tween: "+label)
   check(actor.debug_snapshot().foot_point.is_equal_approx(Vector2(148,488)),"pose cycle cannot move feet/root registration: "+label)

func test_repeat_updates_and_bindings() -> void:
 var contract:Dictionary=order("stable")
 var tween:Tween=accept(contract)
 var actor=world.customers.stable.node
 var original_actor:int=actor.get_instance_id()
 var original_child:int=actor.get_child(0).get_instance_id()
 var original_generation:int=world._parcel_generation
 var original_texture:Texture2D=actor.texture
 var stable:bool=true
 seed(4729)
 for i in 300:
  randi();var copy:Dictionary=JSON.parse_string(JSON.stringify(contract));copy.story_node=i%4
  update([copy],"stable")
  stable=stable and world.customers.stable.node.get_instance_id()==original_actor and actor.get_child(0).get_instance_id()==original_child and actor.texture==original_texture and actor.pose=="handoff" and world._parcel_generation==original_generation and world._parcel_tween==tween and actor.get_child_count()==1
 check(stable,"300 JSON/status/story updates reuse body, accessory, pose, tween and saved identity without RNG drift")
 tween.custom_step(1.0)
 for i in 50:update([contract],"stable")
 check(world._parcel_phase=="counter" and world._parcel_tween==null and counter_parcels()==1,"completed transfer cannot restart on repeated renders")
 var changed:Dictionary=order("stable","alien_botanist","field_vial")
 update([changed],"stable")
 check(world.customers.stable.node.get_instance_id()==original_actor and actor.appearance_id=="alien_botanist" and actor.accessory_id=="field_vial" and actor.get_child_count()==1 and actor.get_child(0).get_instance_id()==original_child,"explicit replacement binding safely reuses one actor/accessory node")
 update([{"contract_id":"legacy","status":"available"}])
 check(world.customers.legacy.node.appearance_id=="human_courier" and world.customers.legacy.node.accessory_id=="none","legacy unbound order remains an explicit human fallback")
 var invalid:Dictionary=order("legacy");invalid.species="robot"
 update([invalid])
 check(not world.customers.legacy.node.visible and world.customers.legacy.node.texture==null and world.customers.legacy.node.debug_snapshot().diagnostics.has("species_appearance_mismatch"),"invalid replacement binding cannot leave a stale or falsely human customer")
 var a:Dictionary=order("queue-a","human_courier","none");a.status="available"
 var b:Dictionary=order("queue-b","robot_machinist","power_cell");b.status="available"
 update([a,b])
 check(world.customers["queue-a"].target==Vector2(148,488) and world.customers["queue-b"].target.x<0,"first available client owns the counter while next species queues offstage")
 a.status="declined";update([a,b])
 check(world.customers["queue-a"].target.x<0 and world.customers["queue-b"].target==Vector2(148,488),"declining the front client advances the next actual species")
 update([a,b],"","night")
 check(world.customers["queue-a"].target.x<0 and world.customers["queue-b"].target.x<0,"night sends all species offstage")

func reach_phase(tween:Tween,phase:String) -> void:
 if phase=="counter_transfer":tween.custom_step(World.CUSTOMER_HANDOFF_DURATION+.08)
 elif phase=="clerk_handoff":tween.custom_step(World.CUSTOMER_HANDOFF_DURATION+World.COUNTER_TRANSFER_DURATION+.02)
 elif phase=="counter":tween.custom_step(1.0)

func fire_old_callbacks(order_id:String,generation:int) -> void:
 world._begin_counter_transfer(order_id,generation)
 world._move_counter_parcel(.7,order_id,generation)
 world._receive_counter_parcel(order_id,generation)
 world._finish_counter_handoff(order_id,generation)
 world._finish_parcel_transfer(order_id,generation)

func test_pack_interruptions() -> void:
 for phase in ["customer_handoff","counter_transfer","clerk_handoff","counter"]:
  var contract:Dictionary=order("pack/"+phase,"robot_machinist","tool_pack")
  var old:Tween=accept(contract);reach_phase(old,phase)
  var origin:Vector2=world.parcel.position
  var generation:int=world._parcel_generation
  world.pack_parcel()
  check(world.is_loading() and world.parcel.position==origin,"pack queues continuous robot delivery without teleporting parcel from "+phase)
  var pack_generation:int=world._parcel_generation
  world.pack_parcel();update([contract],str(contract.contract_id))
  check(world._parcel_generation==pack_generation and world.is_loading(),"repeat pack/render cannot create a second load transfer: "+phase)
  if old!=null and old.is_valid():old.custom_step(1.0)
  check(world._parcel_phase=="robot_fetch" and world.parcel.visible and counter_parcels()==1,"completed counter handoff gives exactly one real parcel to robot sequence: "+phase)
  fire_old_callbacks(str(contract.contract_id),generation)
  check(world._parcel_phase=="robot_fetch" and world.parcel.visible,"old handoff callbacks cannot bypass robot sequence: "+phase)
  for i in 1200:world._process(1.0/120.0)
  check(world._parcel_phase=="loaded" and world._parcel_tween==null and not world.parcel.visible and world.parcel.position.is_equal_approx(world.assembly_origin) and counter_parcels()==0,"cooperative chain reaches real assembly origin and hides external parcel: "+phase)

func test_cancel_and_reaccept() -> void:
 for phase in ["customer_handoff","counter_transfer","clerk_handoff","counter"]:
  for same_id in [false,true]:
   var a:Dictionary=order("A","alien_botanist","seed_pod")
   var old:Tween=accept(a)
   reach_phase(old,phase)
   var old_generation:int=world._parcel_generation
   update([],"")
   check(world.parcel_state=="empty" and world._parcel_phase=="empty" and world._parcel_tween==null and not world.parcel.visible and idle_poses(),"cancel clears every representation from "+phase)
   var id:String="A" if same_id else "B"
   var b:Dictionary=order(id,"robot_machinist","power_cell")
   var next:Tween=accept(b);next.custom_step(1.0)
   var position:Vector2=world.parcel.position
   fire_old_callbacks("A",old_generation)
   check(world.active_id==id and world.parcel_state=="counter" and world._parcel_phase=="counter" and world.parcel.visible and world.parcel.position==position and idle_poses() and counter_parcels()==1,"stale "+phase+" callbacks cannot hide/move reaccepted "+id)
 var a:Dictionary=order("direct-a");var old:Tween=accept(a)
 var generation:int=world._parcel_generation
 var b:Dictionary=order("direct-b","human_courier","none")
 update([a,b],"direct-b");var next:Tween=world._parcel_tween;next.pause()
 check(world.customers["direct-a"].node.pose=="idle" and world.customers["direct-b"].node.pose=="handoff" and counter_parcels()==1,"direct A-to-B replacement resets A and gives the painted parcel only to B")
 fire_old_callbacks("direct-a",generation)
 check(world._parcel_tween==next and world._parcel_phase=="customer_handoff" and world.parcel.visible,"old callbacks cannot hide the parcel in empty-handed human B's handoff")
 next.custom_step(1.0)

func test_reduced_motion() -> void:
 for phase in ["customer_handoff","counter_transfer","clerk_handoff","counter"]:
  world.reduced_motion=false
  var contract:Dictionary=order("reduced/"+phase)
  var old:Tween=accept(contract)
  reach_phase(old,phase)
  var generation:int=world._parcel_generation
  world.reduced_motion=true
  check(world._parcel_tween==null and idle_poses() and world.assembly_feedback.reduced_motion,"enabling reduced motion cancels tween and settles registered poses: "+phase)
  if phase=="packing":check(world._parcel_phase=="loaded" and not world.parcel.visible and world.parcel.position==world.assembly_origin,"reduced motion finishes interrupted packing immediately")
  else:check(world._parcel_phase=="counter" and world.parcel.visible and counter_parcels()==1,"reduced motion settles interrupted handoff as one counter parcel: "+phase)
  var position:Vector2=world.parcel.position;var visible:bool=world.parcel.visible
  fire_old_callbacks(str(contract.contract_id),generation)
  check(world.parcel.position==position and world.parcel.visible==visible and world._parcel_tween==null and idle_poses(),"reduced-motion settlement invalidates all delayed callbacks: "+phase)
 var direct:Dictionary=order("reduced-direct","alien_botanist","field_vial")
 accept(direct)
 check(world._parcel_tween==null and world._parcel_phase=="counter" and counter_parcels()==1,"already-reduced acceptance creates no delay or painted duplicate")
 world.pack_parcel()
 check(world._parcel_tween==null and world._parcel_phase=="loaded" and not world.parcel.visible and counter_parcels()==0,"already-reduced pack settles without creating a tween")
 world.reduced_motion=false

func test_bounded_lifecycle() -> void:
 update([],"");await process_frame;await process_frame
 var base_children:int=world.actors_root.get_child_count()
 var base_tweens:int=get_processed_tweens().size()
 var bounded:bool=true
 for i in 96:
  var appearance:String=Stories.IDS[i%Stories.IDS.size()]
  var options:Array=CASES[appearance].accessories
  var contract:Dictionary=order("churn/"+str(i),appearance,options[i%options.size()])
  var tween:Tween=accept(contract);tween.custom_step(.13)
  if i%2==0:world.pack_parcel()
  update([],"")
  await process_frame
  bounded=bounded and world.customers.is_empty() and world.actors_root.get_child_count()==base_children and get_processed_tweens().size()<=base_tweens and world._parcel_tween==null and counter_parcels()==0
 check(bounded,"96 interrupted species orders release actors/accessories/tweens without scene-tree growth")
 var contract:Dictionary=order("runtime-b","robot_machinist","tool_pack")
 accept(contract);world._parcel_tween.play()
 await create_timer(.8).timeout
 check(world._parcel_phase=="counter" and world.parcel.visible and world._parcel_tween==null,"real SceneTree clock completes phase chain within the existing acceptance window")
 world.pack_parcel();world.set_process(true);await create_timer(7.0).timeout;world.set_process(false)
 check(world._parcel_phase=="loaded" and not world.parcel.visible and world._parcel_tween==null,"real SceneTree clock completes the current packing callback")
 accept(order("free-during-handoff"));world._parcel_tween.play()
 viewport.queue_free();await process_frame;await process_frame
 check(get_processed_tweens().size()<=base_tweens,"freeing world during handoff releases all bound tweens")

func run() -> void:
 manifest=JSON.parse_string(FileAccess.get_file_as_string(Npc.NPC_MANIFEST))
 viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 test_species_and_phases()
 test_repeat_updates_and_bindings()
 test_pack_interruptions()
 test_cancel_and_reaccept()
 test_reduced_motion()
 await test_bounded_lifecycle()
 print("COUNTER_SPECIES_INTEGRATION_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
