extends SceneTree
## Actual v4 imports plus truthful, bounded structural-connection rendering.
const World=preload("res://scripts/world_view.gd")
const Sim=preload("res://scripts/simulation.gd")
const Parts=preload("res://scripts/parts.gd")
var passed:int=0
var failed:int=0
class JointProbe extends "res://scripts/world_view.gd":
 var submitted:Dictionary={}
 func _set_joint_instances(node:MultiMeshInstance3D,poses:Array[Transform3D],ids:Array) -> void:
  submitted[str(node.name)]=poses.duplicate()
  super._set_joint_instances(node,poses,ids)
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run() -> void:
 var required:Array=[]
 for name in ["shop_cutaway","orbital_city","flight_city","sky_backdrop","assembly_lift","clerk_dais","launch_rail","launch_pier"]:required.append("environment_v4/"+name)
 for name in ["clerk","customer"]:required.append("characters_v4/"+name)
 for name in ["cargo_crate","beam","cell","thruster","armor","separator","spring","joint_sleeve"]:required.append("modules_v4/"+name)
 for name in required:
  var path:String="res://assets/"+name+".glb";var source=load(path) if ResourceLoader.exists(path) else null
  var model=source.instantiate() if source is PackedScene else null
  var meshes:Array=model.find_children("*","MeshInstance3D",true,false) if model!=null else []
  if model is MeshInstance3D:meshes.push_front(model)
  check(not meshes.is_empty(),"v4 GLB imports real editable-model geometry: "+name)
  if model!=null:model.free()
 var world=JointProbe.new();world.catalog=Parts.catalog();world.catalog.cargo=Parts.cargo_spec();root.add_child(world);world.set_process(false)
 var controller=load("res://scripts/main.gd").new();controller._starter()
 world.show_design(controller.design)
 var shop:MultiMeshInstance3D=world.ship_root.get_node("WorkshopStructuralJoints")
 check(shop.multimesh.instance_count==10,"eight real starter modules share ten visible socket joints")
 var sim=Sim.new();var economy=load("res://scripts/economy.gd").new();sim.configure(controller.design,controller.launcher,economy.routes()[0],100)
 world.start_flight(sim);world.show_flight(sim)
 var supports=world.flight_nodes.launch_pad.find_children("AnchoredModuleSupport*","Node3D",true,false)
 check(supports.size()==2,"both fixed non-spring launcher modules remain grounded below the minimum lift extension")
 var support_pose:bool=true
 for support in supports:
  var saddle=support.find_child("TopSaddle",true,false)
  if saddle!=null:support_pose=support_pose and is_equal_approx(saddle.global_position.y,float(support.get_meta("support_contact_y")))
 check(support_pose,"actual support saddles reach their anchored module contact planes")
 var batch:MultiMeshInstance3D=world.flight_nodes.structural_joints
 check(batch.multimesh.instance_count==sim.links.size() and batch.multimesh.instance_count==10,"flight sleeves derive only from the live structural graph")
 var same:bool=true
 for i in range(sim.links.size()):
  var link:Dictionary=sim.links[i];var a:Vector2=sim.part_world_position(link.a);var b:Vector2=sim.part_world_position(link.b)
  var expected:Vector3=Vector3((a.x+b.x)*.5,-(a.y+b.y)*.5,0)+world.flight_origin
  var actual:Transform3D=world.submitted.LiveStructuralJoints[i] if DisplayServer.get_name()=="headless" else batch.multimesh.get_instance_transform(i)
  same=same and actual.origin.is_equal_approx(expected)
 check(same,"every submitted sleeve pose is centered on its two actual moving endpoints")
 var original_node:int=batch.get_instance_id();var original_mesh:int=batch.multimesh.mesh.get_instance_id()
 var energy:float=sim.total_energy();var momentum:Vector2=sim.total_momentum();var links:Array=sim.links.duplicate(true)
 for i in range(60):world._update_flight_joints(sim)
 check(batch.get_instance_id()==original_node and batch.multimesh.mesh.get_instance_id()==original_mesh,"flight frames reuse one joint node and one shared mesh")
 check(sim.total_energy()==energy and sim.total_momentum()==momentum and sim.links==links,"joint presentation cannot change mechanics or accounting")
 sim.trigger(8);sim.step(Sim.FIXED_DT);world.show_flight(sim)
 check(batch.multimesh.instance_count==9 and sim.bodies.size()==1 and not [1,8] in batch.get_meta("structural_edges",[]),"coupler cuts only its target edge; alternate structural paths stay visible")
 sim.step(Sim.FIXED_DT);sim.parts[8].target=5;sim.trigger(8);sim.step(Sim.FIXED_DT);world.show_flight(sim)
 var detached_gone:bool=true
 for edge in batch.get_meta("structural_edges",[]):detached_gone=detached_gone and not 8 in edge
 check(detached_gone and batch.multimesh.instance_count==sim.links.size() and sim.bodies.size()>1,"triggered coupler genuinely detaches and loses every connecting sleeve")
 sim._damage_part(sim.parts[2],10000.0,"test");sim.step(Sim.FIXED_DT);world.show_flight(sim)
 var destroyed_gone:bool=true
 for edge in batch.get_meta("structural_edges",[]):destroyed_gone=destroyed_gone and not 2 in edge
 check(destroyed_gone,"destroyed modules leave no ghost structural sleeve")
 var maximum:Array=[];var id:int=100
 for y in range(-2,3):
  for x in range(-4,5):maximum.append(controller.part(id,"beam",x,y));id+=1
 world.leave_flight();world.show_design(maximum)
 shop=world.ship_root.get_node("WorkshopStructuralJoints")
 check(shop.multimesh.instance_count==76 and shop.multimesh.instance_count<=World.MAX_VISIBLE_JOINTS,"full45-cell workbench batches all76 joints within the presentation bound")
 check(world.ship_root.get_child_count()==46,"full workbench adds one joint batch, not76 extra scene subtrees")
 var actor=load("res://assets/characters_v4/clerk.glb").instantiate();world.actors_root.add_child(actor);world._register_actor(actor)
 check(actor.get_meta("pose_pivots",[]).size()==6,"Q clerk retains six original rigid gesture pivots without claiming Spine")
 world.reduced_motion=true;world._animate_actor(actor,true,0,true);var rests:bool=true
 for pivot in actor.get_meta("pose_pivots",[]):rests=rests and pivot.node.rotation.is_equal_approx(pivot.rest)
 check(rests,"reduced motion preserves the Q model's authored rest pose")
 controller.free();world.queue_free();await process_frame;await process_frame
 print("V4_PRESENTATION_TESTS passed=",passed," failed=",failed);quit(1 if failed else 0)
