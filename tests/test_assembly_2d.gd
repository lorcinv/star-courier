extends SceneTree
## Presentation isolation, exact restoration, interruption safety and hard budgets.
const Assembly=preload("res://scripts/assembly_2d.gd")
const Econ=preload("res://scripts/economy.gd")
const Sim=preload("res://scripts/simulation.gd")
var passed:int=0
var failed:int=0
var stage:Node2D
var parts:Node2D
var assembly

func _initialize() -> void:run.call_deferred()
func check(ok:bool,title:String) -> void:
 if ok:passed+=1;print("PASS ",title)
 else:failed+=1;push_error("FAIL "+title)
func p(id:int,type:String="battery",x:int=0,y:int=0,rot:int=0) -> Dictionary:
 return {"id":id,"type":type,"x":x,"y":y,"rot":rot,"param":12.0,"input_a":-1,"input_b":-1,"target":-1}
func module(part:Dictionary) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new();node.name="Part"+str(part.id)
 node.texture=load("res://assets/2d_v5/modules/battery-pixel.png")
 node.position=Vector2(part.x,part.y)*72;node.rotation=float(part.rot)*PI*.5
 node.scale=Vector2(.65,.7);node.self_modulate=Color(.8,.9,1,1);parts.add_child(node)
 return node
func advance(seconds:float) -> void:
 var steps:int=maxi(1,ceili(seconds*120))
 for i in range(steps):assembly._process(seconds/steps)
func run() -> void:
 stage=Node2D.new();root.add_child(stage)
 parts=Node2D.new();parts.name="LiveModelSprites";parts.position=Vector2(728,288);parts.z_index=5;stage.add_child(parts)
 assembly=Assembly.new();stage.add_child(assembly);assembly.set_process(false)
 assembly.configure(Vector2(728,288),72);assembly.bind_part_root(parts)
 var data:Dictionary=p(7);var before:Dictionary=data.duplicate(true)
 var part_sprite:Sprite2D=module(data);var instance:int=part_sprite.get_instance_id()
 var texture:Texture2D=part_sprite.texture;var base_scale:Vector2=part_sprite.scale;var base_tint:Color=part_sprite.self_modulate
 var node_count:int=assembly.find_children("*","Node",true,false).size()
 var tween_count:int=get_processed_tweens().size()
 check(assembly.debug_snapshot().cached_robot_textures==9,"legacy poses, empty hands and generated frontal inbetween preload once")
 check(assembly.robot.offset==Vector2(-80,-136) and not assembly.robot.centered,"poses share registered body/foot origin")
 check(assembly.z_index==4 and assembly.sparks_root.z_index==2,"robot behind modules and counter; latch above modules")
 check(not assembly.lift_arm.z_as_relative and assembly.lift_arm.z_index==9,"connected mechanical arm is above counter and below the single parcel")
 check(assembly.robot.texture.resource_path.ends_with("carry-empty.png"),"idle uses the same empty body as transport without a baked-parcel pose pop")
 check(assembly.robot_root.position==Vector2(516,486),"robot rests on canonical floor clear of customer")
 advance(5)
 check(assembly.robot_state=="idle" and assembly.debug_snapshot().actions==0,"idle does not invent assembly or move parts")
 assembly.on_committed_edit("place",data)
 check(assembly.debug_snapshot().actions==1 and part_sprite.position==Vector2(0,-10),"successful place aligns the real module immediately")
 check(part_sprite.get_instance_id()==instance and part_sprite.texture==texture,"feedback reuses actual module sprite and generated texture")
 check(data==before,"committed dictionary remains unchanged")
 var malformed:Dictionary=p(99);malformed.rot=NAN
 assembly.on_committed_edit("rotate",malformed)
 check(assembly.debug_snapshot().actions==1,"nonfinite visual transforms are rejected without disturbing valid work")
 advance(.185)
 check(assembly.debug_snapshot().visible_sparks==1,"one restrained generated latch spark fires at alignment")
 assembly.on_committed_edit("place",data)
 check(assembly.debug_snapshot().visible_sparks==0,"new same-part commit cancels its earlier latch spark")
 advance(.4)
 check(part_sprite.position==Vector2.ZERO and is_equal_approx(part_sprite.rotation,0) and part_sprite.scale==base_scale and part_sprite.self_modulate==base_tint,"completion restores exact committed transform and tint")
 check(assembly.debug_snapshot().actions==0 and assembly.debug_snapshot().visible_sparks==0,"completion releases actions and hides pooled sparks")
 for i in range(200):
  data.x=i%3;data.rot=i%4
  assembly.on_committed_edit("rotate",data)
 check(assembly.debug_snapshot().actions==1,"rapid repeated edits merge into latest action for one part")
 advance(.4)
 check(part_sprite.position==Vector2(data.x,0)*72 and is_equal_approx(part_sprite.rotation,float(data.rot)*PI*.5),"rapid edit completion uses latest canonical position and rotation")
 for i in range(30):
  var item:Dictionary=p(100+i,"battery",i%5,i%2);module(item);assembly.on_committed_edit("place",item)
 check(assembly.debug_snapshot().actions==Assembly.MAX_ACTIONS,"many distinct commits obey four-action budget")
 check(parts.get_node("Part100").position==Vector2.ZERO,"evicted action restores its module immediately")
 advance(.19)
 check(assembly.debug_snapshot().visible_sparks<=Assembly.MAX_SPARKS and assembly.debug_snapshot().spark_nodes==Assembly.MAX_SPARKS,"bursts reuse four fixed spark nodes")
 check(assembly.find_children("*","Node",true,false).size()==node_count and get_processed_tweens().size()==tween_count,"repeated edits allocate no scene nodes or retained Tweens")
 assembly.reset();assembly.on_committed_edit("move",data)
 parts.remove_child(part_sprite);part_sprite.free()
 var replacement:Sprite2D=module(data)
 advance(.06)
 check(replacement.position!=Vector2(data.x,data.y)*72,"redraw safely rebinds the current Part{id} sprite")
 advance(.4)
 check(replacement.position==Vector2(data.x,data.y)*72 and replacement.scale==base_scale,"replacement sprite restores exact canonical pose")
 assembly.on_committed_edit("place",data)
 parts.remove_child(replacement);replacement.free();assembly.on_committed_edit("remove",data)
 advance(.1)
 check(assembly.debug_snapshot().actions==0,"remove cancels pending action without resurrecting a sprite")
 assembly.reset();assembly.on_order_changed("D1-A","accepted");advance(.4)
 check(assembly.robot_state=="idle","accepted snapshot does not invent a duplicate parcel delivery")
 assembly.acquire_transport("D1-A");assembly.drive_transport("D1-A","robot_carry",580,true,"carry-empty")
 var prior_x:float=assembly.debug_snapshot().robot_x
 assembly.on_order_changed("D1-A","loading");advance(.5)
 check(assembly.debug_snapshot().robot_x==prior_x and assembly.robot_state=="robot_carry","world parcel owns robot while ordinary component clock advances")
 assembly.on_committed_edit("remove",data)
 check(assembly.robot_state=="robot_carry" and assembly.robot_pose=="carry-empty","part edit cannot steal active cargo intent or show a second box")
 assembly.release_transport("D1-A");advance(5)
 check(assembly.robot_state=="idle" and is_equal_approx(assembly.debug_snapshot().robot_x,516),"released courier terminates at dock without idle loops")
 assembly.acquire_transport("D1-A");assembly.drive_transport("D1-A","robot_insert",640,true,"carry-empty")
 assembly.release_transport_at_workbench("D1-A",640)
 assembly.on_order_changed("","empty")
 check(assembly.transport_current_x()==640 and assembly.robot_state=="idle","loaded cancellation bookkeeping never teleports a robot to its canonical dock")
 assembly.on_order_changed("D1-B","accepted");assembly.acquire_transport("D1-B")
 check(assembly.transport_current_x()==640 and assembly.debug_snapshot().transport_owner=="D1-B","new order bookkeeping and acquisition preserve the actual previous-order position")
 assembly.drive_transport("D1-B","robot_carry",590,true,"carry-empty")
 assembly.hold_transport_position("wrong-order")
 check(assembly.transport_current_x()==590 and assembly.debug_snapshot().transport_owner=="D1-B","wrong-order hold cannot release the current transport")
 assembly.hold_transport_position("D1-B");advance(.5)
 check(assembly.transport_current_x()==590 and assembly.debug_snapshot().transport_owner.is_empty() and assembly.robot_state=="idle","world can release a cancelled robot in place while its clerk clears the route")
 assembly.release_transport();advance(5)
 assembly.on_order_changed("D1-B","accepted");assembly.acquire_transport("D1-B");assembly.on_order_changed("D1-B","cancelled")
 check(assembly.robot_state=="idle" and assembly.debug_snapshot().actions==0 and assembly.debug_snapshot().transport_owner.is_empty(),"cancelled order interrupts courier and part feedback")
 assembly.on_order_changed("D1-C","accepted");assembly.acquire_transport("D1-C");assembly.set_scene_visible(false)
 var hidden_x:float=assembly.debug_snapshot().robot_x;advance(5)
 check(not assembly.visible and assembly.debug_snapshot().robot_x==hidden_x and assembly.robot_state=="idle","flight/navigation hide clears jobs and cannot run hidden deliveries")
 assembly.set_scene_visible(true);advance(.3)
 check(assembly.robot_state=="idle" and assembly.debug_snapshot().visible_sparks==0,"returning to shop never replays stale feedback")
 assembly.on_order_changed("D1-C","loaded");assembly.on_order_changed("D1-D","accepted")
 check(assembly.order_id=="D1-D" and assembly.robot_state=="idle","new accepted order is a passive snapshot until real cargo requests transport")
 replacement=module(data);assembly.on_committed_edit("move",data)
 assembly.reduced_motion=true
 check(assembly.debug_snapshot().actions==0 and replacement.position==Vector2(data.x,data.y)*72,"enabling reduced motion restores in-progress actual module")
 var reduced_x:float=assembly.debug_snapshot().robot_x
 assembly.on_committed_edit("place",data);assembly.on_order_changed("D1-E","accepted");advance(2)
 check(assembly.debug_snapshot().robot_x==516 and assembly.debug_snapshot().actions==0 and assembly.debug_snapshot().visible_sparks==0,"reduced motion suppresses travel, displacement and flashes")
 # Route velocity is real presentation position, with smooth acceleration and
 # braking rather than a crossfade, secondary ghost, or a moving fake parcel.
 assembly.reduced_motion=false;assembly.reset()
 var leg_time:float=assembly.transport_travel_duration(444,640)
 var midpoint:float=assembly.sample_transport_velocity(444,640,leg_time*.5,leg_time)
 var start_speed:float=assembly.sample_transport_velocity(444,640,.02,leg_time)
 var end_speed:float=assembly.sample_transport_velocity(444,640,leg_time-.02,leg_time)
 check(start_speed>0 and start_speed<midpoint and is_equal_approx(start_speed,end_speed),"travel eases actual velocity into cruise and symmetrically into braking")
 var monotone:bool=true;var last_x:float=444
 for i in 201:
  var x:float=assembly.sample_transport_x(444,640,leg_time*float(i)/200.0,leg_time)
  monotone=monotone and x>=last_x and x<=640;last_x=x
 check(monotone and is_equal_approx(last_x,640) and assembly.sample_transport_velocity(444,640,leg_time,leg_time)==0,"analytic travel reaches the exact dock at zero speed without overshoot")
 assembly.configure_transport_bounds(436,3220,486,220,2.4)
 check(assembly.transport_dock_x(Vector2(2780,198))==2692 and assembly.transport_travel_duration(444,2692)<=2.4,"expanded cargo uses its actual bay and a bounded trip, never the old 818 clamp")
 assembly.acquire_transport("long-leg");assembly.drive_transport("long-leg","robot_insert",2692,true,"carry-empty")
 assembly.grip_transport_parcel("long-leg",Vector2(2780,198))
 var grip_scale:Vector2=assembly._lift_claw.scale;var joint_scale:Vector2=assembly._lift_joint.scale
 check(assembly.debug_snapshot().robot_x==2692 and assembly.robot_root.position.y==486 and assembly.transport_grip_point().distance_to(Vector2(2780,198))<.001,"high-bay mechanical hand stays on the true parcel while robot feet remain on the floor")
 assembly.grip_transport_parcel("long-leg",assembly.transport_hand_point())
 check(assembly._lift_claw.scale==grip_scale and assembly._lift_joint.scale==joint_scale and assembly.lift_arm.scale==Vector2.ONE,"short carry and tall insertion never resize generated claw, shoulder or whole arm")
 var registered:bool=true
 for i in 21:
  assembly.drive_transport_turn("long-leg",2692,float(i)/20.0)
  assembly.grip_transport_parcel("long-leg",assembly.transport_hand_point())
  registered=registered and assembly.robot.offset==Vector2(-80,-136) and assembly.robot.scale==Vector2.ONE and assembly.robot_root.scale.abs()==Vector2.ONE and assembly.robot_root.position==Vector2(2692,486)
  registered=registered and assembly.transport_grip_point().distance_to(assembly.transport_hand_point())<.001
 check(registered,"turn keeps one opaque registered body and connected fixed-size hand, with no squash or ghost")
 assembly.drive_transport_turn("long-leg",2692,.5)
 check(assembly.robot_pose=="turn-front" and assembly.robot.texture.resource_path.ends_with("turn-front.png"),"mid-turn selects the authentic generated frontal view")
 var owned:Dictionary=assembly.debug_snapshot();assembly.acquire_transport("long-leg")
 check(assembly.debug_snapshot()==owned,"same-order acquisition is idempotent even halfway through a turn")
 assembly.release_transport("long-leg");assembly.set_focus_active(false)
 var paused:Dictionary=assembly.debug_snapshot();advance(1.0)
 check(assembly.debug_snapshot()==paused,"focus loss freezes return turning and eased floor motion")
 assembly.set_focus_active(true);advance(3.0)
 check(assembly.robot_state=="idle" and assembly.debug_snapshot().robot_x==516,"expanded-bay return settles once within its bounded visual budget")
 assembly.configure_transport_bounds(436,818);assembly.reset()
 # A presentation pass must not touch even unrelated live accounting / simulation.
 var econ=Econ.new();econ.ensure_contracts();var econ_snapshot:Dictionary=econ.inventory.duplicate(true);var credits:int=econ.credits
 var sim=Sim.new();var design:Array=[p(1,"cargo"),p(2,"battery",-1)]
 sim.configure(design,[],{"distance":1000.0,"time_limit":90.0,"hazards":[]},19)
 var energy:float=sim.total_energy();var momentum:Vector2=sim.total_momentum();var telemetry:Dictionary=sim.telemetry.duplicate(true);var design_snapshot:Array=design.duplicate(true)
 assembly.reduced_motion=false
 for i in range(100):assembly.on_committed_edit("move",data);advance(.02)
 advance(3)
 check(econ.inventory==econ_snapshot and econ.credits==credits and sim.total_energy()==energy and sim.total_momentum()==momentum and sim.telemetry==telemetry and design==design_snapshot,"visual work cannot change stock, credits, part data, simulation energy or momentum")
 check(assembly.find_children("*","Control",true,false).is_empty() and assembly.find_children("*","CollisionObject2D",true,false).is_empty(),"component creates no click-blocking control or collision objects")
 assembly.on_committed_edit("move",data);stage.hide()
 check(assembly.debug_snapshot().actions==0 and assembly.robot_state=="idle","ancestor visibility interruption also restores feedback")
 stage.show();assembly.reset()
 check(assembly.order_id.is_empty() and assembly.order_stage.is_empty() and assembly.robot_state=="idle","full reset clears stale order state")
 stage.queue_free();await process_frame;await process_frame
 print("ASSEMBLY_2D_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
