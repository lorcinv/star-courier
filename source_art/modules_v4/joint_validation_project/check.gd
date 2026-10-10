extends SceneTree
func _initialize() -> void:
 var path:String=OS.get_cmdline_user_args()[0]
 var doc:=GLTFDocument.new()
 var state:=GLTFState.new()
 var error:=doc.append_from_file(path,state)
 assert(error==OK)
 var node:=doc.generate_scene(state)
 print("JOINT_NATIVE_ROOT ",node.get_class()," children=",node.get_child_count())
 assert(node is MeshInstance3D)
 assert(node.get_child_count()==0)
 assert(node.transform.is_equal_approx(Transform3D.IDENTITY))
 assert(node.mesh.get_surface_count()==2)
 print("JOINT_NATIVE_AABB ",node.get_aabb()," surfaces=",node.mesh.get_surface_count())
 node.free()
 quit(0)
