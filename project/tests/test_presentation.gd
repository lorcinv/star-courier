extends SceneTree
## Import integrity, presentation budgets and rest-pose safety. No GPU FPS gate.
const World=preload("res://scripts/world_view.gd")
const Parts=preload("res://scripts/parts.gd")
const Sim=preload("res://scripts/simulation.gd")
var passed:int=0
var failed:int=0

func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)

func _initialize() -> void:run.call_deferred()

func run() -> void:
 var names:Array=["environment_v2/shop_cutaway","environment_v2/orbital_city","environment_v2/flight_city","environment_v2/sky_backdrop","environment_v2/destination_kiosk","environment_v2/courier_clerk","environment_v2/customer","environment_v2/customer_2","environment_v2/customer_3"]
 for spec in Parts.catalog().values():names.append("models/"+str(spec.model))
 names.append("models/cargo_crate")
 for name in names:
  var path:String="res://assets/"+name+".glb"
  var scene=load(path) if ResourceLoader.exists(path) else null
  var imported:bool=scene is PackedScene
  var model=scene.instantiate() if imported else null
  check(imported and model.find_children("*","MeshInstance3D",true,false).size()>0,"required GLB imports real mesh geometry: "+name)
  if is_instance_valid(model):model.free()
 var world=World.new();world.catalog=Parts.catalog();world.catalog.cargo=Parts.cargo_spec();root.add_child(world);await process_frame
 var actor=load("res://assets/environment_v2/courier_clerk.glb").instantiate();world.actors_root.add_child(actor);world._register_actor(actor)
 check(actor.get_meta("pose_pivots",[]).size()==6,"character import preserves six rigid gesture pivots")
 var poses:Array=actor.get_meta("pose_pivots",[])
 world.visual_time=.6;world._animate_actor(actor,true,0.0,true)
 var changed:bool=false
 for pose in poses:changed=changed or not pose.node.rotation.is_equal_approx(pose.rest)
 check(changed,"rigid character pivots visibly animate from authored rest pose")
 world.reduced_motion=true;world._animate_actor(actor,true,0.0,true)
 var exact:bool=true
 for pose in poses:exact=exact and pose.node.rotation.is_equal_approx(pose.rest)
 check(exact,"reduced motion restores imported rest rotations without zeroing authored gestures")
 world.reduced_motion=false
 var p=func(id,type,x):return {"id":id,"type":type,"x":x,"y":0,"rot":0,"param":Parts.defaults(type),"input_a":-1,"input_b":-1,"target":-1}
 var sim=Sim.new();sim.configure([p.call(1,"cargo",0),p.call(2,"battery",-1)],[p.call(10,"spring",0),p.call(11,"battery",-1),p.call(12,"beam",1)],{"distance":10000.0,"delivery_radius":5.0,"max_delivery_speed":45.0,"time_limit":90.0,"boundary_y":80.0,"weight":1.0,"hazards":[],"gravity":0.0,"wind":Vector2.ZERO,"seed":100,"variation":0.0},100)
 for i in range(192):sim._effect("teleport",Vector2(float(i%8)*.5,0),Vector2(float(i%8)*.5+1,0),.2)
 var count:int=sim.effects.size();var telemetry:Dictionary=sim.telemetry.duplicate(true);var energy:float=sim.total_energy();var momentum:Vector2=sim.total_momentum()
 world._draw_flight_effects(sim,world.flight_origin)
 check(world.fx_root.get_child_count()==1,"192 live events render through one persistent FX node")
 check(world.effect_mesh.get_surface_count()<=2,"trajectory, beams and rings require at most two batch surfaces")
 check(world.visible_effect_count<=World.MAX_VISIBLE_EFFECTS and world.visible_ring_count<=World.MAX_VISIBLE_RINGS,"visible effects and rings obey independent presentation budgets")
 check(world.visible_ring_count<world.visible_effect_count*2,"coincident teleport endpoints merge into one readable flash")
 check(sim.effects.size()==count and sim.telemetry==telemetry and sim.total_energy()==energy and sim.total_momentum()==momentum,"visual batching and culling do not change simulation events, energy, momentum or accounting")
 var batch_id:int=world.effect_node.get_instance_id();var mesh_id:int=world.effect_mesh.get_instance_id()
 for i in range(120):world._draw_flight_effects(sim,world.flight_origin)
 check(world.effect_node.get_instance_id()==batch_id and world.effect_mesh.get_instance_id()==mesh_id and world.fx_root.get_child_count()==1,"repeated effect frames reuse the same node, mesh and bounded surfaces")
 world._build_launch_pad(sim)
 var socket_matches:bool=true
 for part in sim.launcher_parts:
  var module=world.flight_nodes.launch_pad.get_node(("Spring" if part.type=="spring" else "Pad")+str(part.id))
  var pos:Vector2=part.world_pos
  socket_matches=socket_matches and module.position.is_equal_approx(Vector3(pos.x,-pos.y,-.15)+world.flight_origin)
 check(socket_matches,"visible launcher uses actual fixed simulation socket positions behind craft")
 world.leave_flight()
 check(not world.effect_node.visible and world.effect_mesh.get_surface_count()==0 and world.fx_root.get_child_count()==1,"leaving flight clears batch geometry and retains only reusable FX node")
 world.queue_free();await process_frame;await process_frame
 print("PRESENTATION_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
