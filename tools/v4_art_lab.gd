extends SceneTree
## Actual GPU art study: new meshes, shadowed cel lighting and integer pixels.
## Not a gameplay substitute or a release scene. --probe uses simple geometry.
const PixelStage=preload("res://scripts/pixel_stage.gd")
const Cel=preload("res://assets/shaders/pixel_cel.gdshader")
var stage
var world:Node3D
var camera:Camera3D
var materials:Dictionary={}
var actor_roots:Array=[]
var craft:Node3D
var probe:bool=false
var seconds:float=0.0
var captured:bool=false
var moving:bool=false

func _initialize() -> void:setup.call_deferred()
func material(color:Color,glow:float=0.0,atmosphere:float=0.0,unlit:float=0.0) -> ShaderMaterial:
 var key=color.to_html()+str(glow)+str(atmosphere)+str(unlit)
 if not materials.has(key):
  var mat=ShaderMaterial.new();mat.shader=Cel;mat.set_shader_parameter("base_color",color);mat.set_shader_parameter("emissive",glow);mat.set_shader_parameter("atmosphere",atmosphere);mat.set_shader_parameter("unlit_mix",unlit);materials[key]=mat
 return materials[key]
func box(name:String,position:Vector3,size:Vector3,color:Color) -> MeshInstance3D:
 var node=MeshInstance3D.new();node.name=name;node.mesh=BoxMesh.new();node.mesh.size=size;node.position=position;node.material_override=material(color);world.add_child(node);return node
func remap_cel(node:Node,atmosphere:float=0.0,unlit:float=0.0) -> void:
 if node is MeshInstance3D:
  for i in range(node.mesh.get_surface_count()):
   var source=node.mesh.surface_get_material(i)
   var color:Color=source.albedo_color if source is StandardMaterial3D else Color("f4cf83")
   var name:String=source.resource_name if source!=null else ""
   var glow:float=.88 if "Glow" in name else 0.0
   node.set_surface_override_material(i,material(color,glow,atmosphere,unlit))
  if atmosphere>0 or unlit>.1:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 for child in node.get_children():remap_cel(child,atmosphere,unlit)
func model(path:String,position:Vector3=Vector3.ZERO,atmosphere:float=0.0,unlit:float=0.0) -> Node3D:
 if not ResourceLoader.exists(path):push_warning("V4 study asset not ready: "+path);return null
 var node=load(path).instantiate();node.position=position;world.add_child(node);remap_cel(node,atmosphere,unlit);return node
func setup() -> void:
 root.size=Vector2i(1440,900);root.title="Star Courier V4 • actual 3D art study"
 probe="--probe" in OS.get_cmdline_user_args();moving="--motion" in OS.get_cmdline_user_args()
 stage=PixelStage.new();root.add_child(stage);stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 world=Node3D.new();stage.viewport.add_child(world)
 var environment=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("67c6f0");world.add_child(environment)
 var sun=DirectionalLight3D.new();sun.name="WarmUpperRightSun";sun.rotation_degrees=Vector3(-35,42,0);sun.light_color=Color("ffe3ad");sun.light_energy=1.28;sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=70;sun.shadow_bias=.05;sun.shadow_normal_bias=1.0;sun.directional_shadow_max_distance=60;sun.directional_shadow_fade_start=1.0;sun.directional_shadow_pancake_size=0;world.add_child(sun)
 for location in [Vector3(-8,5.8,1.2),Vector3(1,6.7,0.5)]:
  var light=OmniLight3D.new();light.position=location;light.light_color=Color("ffbd64");light.light_energy=1.45;light.omni_range=8.5;light.omni_attenuation=1.1;light.shadow_enabled=false;world.add_child(light)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=17.4;camera.near=.2;camera.far=90;world.add_child(camera)
 var target:Vector3=Vector3(0,3.0,0);camera.position=target+Vector3(0,4.2,28);camera.look_at(target);camera.current=true
 if probe:
  box("Floor",Vector3(0,-.35,0),Vector3(24,.6,8),Color("b3af91"))
  box("BackWall",Vector3(0,3,-3.0),Vector3(23,6,.5),Color("526585"))
  box("Ceiling",Vector3(-6,6.2,-.5),Vector3(12,.65,5.5),Color("27364c"))
  for x in [-8,-2,4,9]:
   box("Crate",Vector3(x,1,0),Vector3(2,2,2),Color("e7ae34"))
   box("Pillar",Vector3(x+.7,3,-2.2),Vector3(.45,6,.45),Color("425678"))
 else:
  model("res://assets/environment_v4/sky_backdrop.glb",Vector3.ZERO,.0,1.0)
  model("res://assets/environment_v4/orbital_city.glb",Vector3.ZERO,.18,.55)
  model("res://assets/environment_v4/shop_cutaway.glb")
  var clerk=model("res://assets/characters_v4/clerk.glb",Vector3(-7.5,.02,-.25))
  var customer=model("res://assets/characters_v4/customer.glb",Vector3(-10.2,.02,1.65))
  for actor in [clerk,customer]:
   if actor!=null:actor_roots.append(actor)
  craft=Node3D.new();world.add_child(craft);craft.position=Vector3(1,3,.5)
  for entry in [["cargo_crate",0],["beam",-1],["cell",-2],["thruster",-3],["armor",1]]:
   var path:String="res://assets/modules_v4/"+entry[0]+".glb"
   if not ResourceLoader.exists(path):path="res://assets/models/"+entry[0]+".glb"
   var part=model(path,Vector3(float(entry[1]),0,0));if part!=null:part.reparent(craft,false)
 if probe and "--bias-series" in OS.get_cmdline_user_args():
  DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/v4"))
  for values in [[.05,0.0],[.1,1.0],[.2,2.0],[.4,0.0],[.4,2.0],[.1,5.0]]:
   sun.shadow_bias=values[0];sun.shadow_normal_bias=values[1]
   await create_timer(.5).timeout;await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://docs/qa/v4/bias-"+str(values[0])+"-"+str(values[1])+".png")
  quit();return
 await create_timer(2.0).timeout
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/v4"))
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://docs/qa/v4/"+("lighting-probe" if probe else "shop-study")+".png")
 stage.viewport.get_texture().get_image().save_png("res://docs/qa/v4/"+("lighting-probe-native" if probe else "shop-study-native")+".png")
 captured=true
 print("V4_ART_LAB_READY canvas=",stage.viewport.size," scale=",stage.pixel_scale," objects=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT)," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
 if not moving:quit()
func _process(delta:float) -> bool:
 seconds+=delta
 if not captured or not moving:return false
 var slide:float=sin(seconds*.5)*.4
 var texel:float=camera.size/float(stage.viewport.size.y)
 var x:float=round(slide/texel)*texel
 var target=Vector3(x,3,0);camera.position=target+Vector3(0,4.2,28);camera.look_at(target)
 if craft!=null:craft.rotation.z=sin(seconds)*.045
 if seconds>14:quit()
 return false
