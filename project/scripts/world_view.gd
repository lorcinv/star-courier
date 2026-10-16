extends Node3D
## Scene-first orbital post office. Visual state mirrors live contract state.
var camera:Camera3D
var catalog:Dictionary={}
var route_distance:float=64.0
var route_radius:float=5.0
var mode:String="hub"
var visual_time:float=0.0
var shader=preload("res://assets/shaders/pixel_cel.gdshader")
var screen_mapper:Control
var sun:DirectionalLight3D
var shop_lights:Array=[]
var smooth_camera_position:Vector3=Vector3(-.2,8.15,28)
var smooth_camera_look:Vector3=Vector3(-.2,2.15,0)
var smooth_camera_size:float=12.8
var outline_shader=preload("res://assets/outline.gdshader")
var cache:Dictionary={}
var materials:Array=[]
var material_cache:Dictionary={}
var flat_cache:Dictionary={}
var workshop_root:Node3D
var ship_root:Node3D
var lift_root:Node3D
var flight_root:Node3D
var city_root:Node3D
var sky_root:Node3D
var supply_root:Node3D
var actors_root:Node3D
var grid:Node3D
var fx_root:Node3D
var clerk:Node3D
var parcel:Node3D
var customers:Dictionary={}
var flight_nodes:Dictionary={}
var trails:Array=[]
var assembly_origin:Vector3=Vector3(1,3,0.5)
var flight_origin:Vector3=Vector3(1,3,0.5)
var camera_target:Vector3=Vector3(-.2,2.15,0)
var camera_look:Vector3=Vector3(-.2,2.15,0)
var camera_size:float=12.8
var desired_camera:Vector3=Vector3(-.2,8.15,28)
var night:bool=false
var active_id:String=""
var parcel_state:String="empty"
var clerk_destination:float=-7.4
var last_integrity:float=1.0
var shake:float=0.0
var selected:int=-1
var phase:String="morning"
var reduced_motion:bool=false
var terminal_age:float=-1.0
var launch_age:float=0.0
var launcher_design:Array=[]
const MAX_VISIBLE_EFFECTS:int=32
const MAX_VISIBLE_RINGS:int=24
const EFFECT_RING_SEGMENTS:int=24
var effect_mesh:ImmediateMesh
var effect_node:MeshInstance3D
var effect_material:StandardMaterial3D
var visible_effect_count:int=0
var visible_ring_count:int=0
var missing_assets:Dictionary={}
var joint_mesh:Mesh
const MAX_VISIBLE_JOINTS:int=384

func _ready() -> void:
 workshop_root=Node3D.new();add_child(workshop_root)
 lift_root=Node3D.new();lift_root.name="AdaptiveMaintenanceLifts";workshop_root.add_child(lift_root)
 city_root=Node3D.new();add_child(city_root)
 sky_root=Node3D.new();add_child(sky_root)
 ship_root=Node3D.new();add_child(ship_root)
 flight_root=Node3D.new();add_child(flight_root)
 actors_root=Node3D.new();add_child(actors_root)
 supply_root=Node3D.new();workshop_root.add_child(supply_root)
 fx_root=Node3D.new();add_child(fx_root)
 _ensure_effect_batch()
 grid=Node3D.new();grid.position=assembly_origin+Vector3(0,0,-0.8);add_child(grid)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=camera_size;camera.near=.2;camera.far=90;camera.position=desired_camera;add_child(camera);camera.look_at(camera_target);camera.current=true
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("72cdec");add_child(env)
 _build_lighting()
 workshop_root.add_child(asset("environment_v4/shop_cutaway",false))
 city_root.add_child(asset("environment_v4/orbital_city",false))
 city_root.add_child(asset("environment_v4/flight_city",false));city_root.get_child(1).hide()
 sky_root.add_child(asset("environment_v4/sky_backdrop",false))
 clerk=asset("characters_v4/clerk",false);clerk.position=Vector3(-7.4,.25,-.25);actors_root.add_child(clerk);_register_actor(clerk)
 var dais=asset("environment_v4/clerk_dais",false);dais.position=Vector3(-7.4,0,-.25);workshop_root.add_child(dais)
 parcel=asset("cargo_crate");parcel.position=Vector3(-8.0,1.6,.65);parcel.scale=Vector3.ONE*0.65;actors_root.add_child(parcel);parcel.hide()
 for x in range(-4,5):
  for y in range(-2,3):
   # Quiet socket crosses, not an engineering grid across the storefront.
   box(grid,Vector3(x,y,0),Vector3(0.11,0.012,0.018),Color("39d9d1"));box(grid,Vector3(x,y,0),Vector3(0.012,0.11,0.018),Color("39d9d1"))
 grid.hide();flight_root.hide()

func flat(color:Color) -> StandardMaterial3D:
 var key=color.to_html(true)
 if not flat_cache.has(key):
  var mat=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=color;flat_cache[key]=mat
 return flat_cache[key]

func box(parent:Node3D,pos:Vector3,size:Vector3,color:Color) -> MeshInstance3D:
 var n=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size;n.mesh=mesh;n.position=pos;n.material_override=flat(color);parent.add_child(n);return n

func asset(id:String,outlined:bool=true) -> Node3D:
 if DisplayServer.get_name()=="headless":return Node3D.new()
 var folder:String="modules_v4/" if id in ["cargo_crate","beam","cell","thruster","armor","spring","separator"] else "models/"
 var path="res://assets/"+(id if id.contains("/") else folder+id)+".glb"
 if ResourceLoader.exists(path):
  if not cache.has(path):cache[path]=load(path)
  var n=cache[path].instantiate();cel(n,outlined,.2 if "city" in id else 0.0,1.0 if "sky_backdrop" in id else (.75 if "city" in id else 0.0));return n
 if not missing_assets.has(path):
  missing_assets[path]=true
  push_error("Required scene asset could not be loaded: "+path+". Import project resources before running.")
 # A visible diagnostic avoids mistaking an empty backdrop for finished art.
 var n=Node3D.new();n.name="MissingAsset"
 box(n,Vector3.ZERO,Vector3(.8,.8,.8),Color("ff3e92"));return n

func cel(node:Node,outlined:bool=true,atmosphere:float=0.0,unlit:float=0.0) -> void:
 if node is MeshInstance3D:
  for i in range(node.mesh.get_surface_count()):
   var source=node.mesh.surface_get_material(i)
   var color:Color=source.albedo_color if source is StandardMaterial3D else Color("fff0bd")
   var texture:Texture2D=source.albedo_texture if source is StandardMaterial3D else null
   var name:String=source.resource_name if source!=null else ""
   var map:Dictionary={"SC_cream":"fff0bd","SC_orange":"ffd447","SC_navy":"142042","SC_cyan":"35d4d2","SC_metal":"5361a1","SC_red":"f56c6c","Env_Ink":"101c35","Env_Cobalt":"3044aa","Env_Indigo":"242b67","Env_Blue":"3665d2","Env_Cyan":"39d9d1","Env_Yellow":"ffdf36","Env_Coral":"fb6671","Env_Cream":"fff1cc","Env_Magenta":"bd3780","Env_Metal":"7598ad","Env_Slate":"496582","Env_Orange":"ff9748"}
   if map.has(name):color=Color(map[name])
   var emissive:bool=name.contains("Glow") or (not name.begins_with("V4_") and (name.contains("Cyan") or name.contains("cyan")))
   var key=color.to_html(true)+str(outlined)+str(emissive)+str(atmosphere)+str(unlit)+str(texture.get_instance_id() if texture!=null else 0)
   if not material_cache.has(key):
    var mat=ShaderMaterial.new();mat.shader=shader;mat.set_shader_parameter("base_color",color);mat.set_shader_parameter("night_mix",1.0 if night else 0.0);mat.set_shader_parameter("atmosphere",atmosphere);mat.set_shader_parameter("unlit_mix",unlit)
    if texture!=null:mat.set_shader_parameter("albedo_texture",texture);mat.set_shader_parameter("has_albedo_texture",true)
    if emissive:mat.set_shader_parameter("emissive",.88)
    if outlined and not name.begins_with("V4_"):
     var outline=ShaderMaterial.new();outline.shader=outline_shader;mat.next_pass=outline
    material_cache[key]=mat;materials.append(weakref(mat))
   node.set_surface_override_material(i,material_cache[key])
  if unlit>.1:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 for child in node.get_children():cel(child,outlined,atmosphere,unlit)

func focus(target:String,instant:bool=false) -> void:
 mode=target
 var airborne:bool=target=="flight"
 workshop_root.visible=not airborne;actors_root.visible=not airborne;ship_root.visible=not airborne;flight_root.visible=airborne
 grid.visible=target=="workshop"
 if target=="workshop":camera_target=Vector3(1.25,2.45,0);camera_size=11.8;clerk_destination=-4.65
 elif target=="contracts":camera_target=Vector3(-6.75,1.6,0);camera_size=7.7;clerk_destination=-7.4
 elif target=="supply":camera_target=Vector3(-2.4,2.7,0);camera_size=12.0;clerk_destination=-4.65
 elif not airborne:camera_target=Vector3(-.2,2.15,0);camera_size=12.8;clerk_destination=-7.4
 if not airborne:desired_camera=camera_target+Vector3(0,6.0 if target=="hub" else 4.2,28)
 for lamp in shop_lights:lamp.visible=not airborne
 if instant:
  smooth_camera_position=desired_camera;smooth_camera_look=camera_target;smooth_camera_size=camera_size
  camera.position=desired_camera;camera.size=camera_size;camera.look_at(camera_target)

func _clear(node:Node) -> void:
 for child in node.get_children():node.remove_child(child);child.queue_free()

func show_design(design:Array,chosen:int=-1) -> void:
 selected=chosen;_clear(ship_root);ship_root.position=assembly_origin;trails.clear();last_integrity=1.0
 _update_maintenance_lifts(design)
 var joints=_new_joint_batch(ship_root,"WorkshopStructuralJoints")
 var joint_poses:Array[Transform3D]=[];var joint_ids:Array=[]
 for i in range(design.size()):
  for j in range(i+1,design.size()):
   var a:Dictionary=design[i];var b:Dictionary=design[j]
   if absi(int(a.x)-int(b.x))+absi(int(a.y)-int(b.y))!=1:continue
   joint_poses.append(_joint_pose(Vector3(a.x,-a.y,0),Vector3(b.x,-b.y,0),.93));joint_ids.append([int(a.id),int(b.id)])
 _set_joint_instances(joints,joint_poses,joint_ids)
 for p in design:
  var n=asset(str(catalog.get(str(p.type),{}).get("model","cargo_crate")));n.position=Vector3(float(p.x),-float(p.y),0);n.rotation.z=-int(p.get("rot",0))*PI/2;n.scale=Vector3.ONE*0.93;ship_root.add_child(n)
  if int(p.id)==chosen:
   for side in [-1,1]:
    box(n,Vector3(side*0.5,0,0.58),Vector3(0.045,0.98,0.025),Color("fff0bd"));box(n,Vector3(0,side*0.5,0.58),Vector3(0.98,0.045,0.025),Color("ffd447"))
  for key in ["input_a","input_b"]:
   for q in design:
    if int(q.id)==int(p.get(key,-1)):
     line(ship_root,Vector3(p.x,-p.y,0.67),Vector3(q.x,-q.y,0.67),Color("f56c6c") if key=="input_a" else Color("35d4d2"))

func cell_at(pos:Vector2) -> Vector2i:
 var origin=camera.project_ray_origin(pos);var direction=camera.project_ray_normal(pos)
 var hit=origin+direction*((assembly_origin.z-origin.z)/direction.z)-assembly_origin
 return Vector2i(roundi(hit.x),-roundi(hit.y))

func update_shop_state(data:Dictionary) -> void:
 phase=str(data.get("phase","morning"));var next_night:bool=phase=="night"
 if next_night!=night:
  night=next_night
  for w in materials:
   var m=w.get_ref();if m!=null:m.set_shader_parameter("night_mix",1.0 if night else 0.0)
 var contracts:Array=data.get("contracts",[]);var seen:Array=[];var label_shown:bool=false
 for i in range(contracts.size()):
  var c:Dictionary=contracts[i];var id:String=str(c.contract_id);seen.append(id)
  if not customers.has(id):
   var variant:int=(i+int(data.get("day",1))-1)%3
   var n=asset("characters_v4/customer",false);n.position=Vector3(-15.5-float(i)*1.5,0.02,1.65);actors_root.add_child(n);_register_actor(n);customers[id]={"node":n,"target":Vector3(-10.2-float(i)*1.5,.02,1.65),"phase":str(c.status),"index":i}
  var customer:Dictionary=customers[id];customer.phase=str(c.status)
  var figure:Node3D=customer.node
  var tag=figure.get_node_or_null("CustomerTag")
  if tag==null:
   tag=Label3D.new();tag.name="CustomerTag";tag.font=load("res://assets/fonts/ChineseSans.otf");tag.font_size=64;tag.pixel_size=.006;tag.position=Vector3(0,2.15,.2);tag.modulate=Color("fff0bd");tag.outline_modulate=Color("142042");tag.outline_size=8;tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED;figure.add_child(tag)
  tag.text=str(c.client)+"的委托"+(" · 重货" if str(c.contract_id).ends_with("B") else "")
  tag.visible=false # Client identity belongs to the native-resolution order ticket.
  if tag.visible:label_shown=true
  var held=figure.get_node_or_null("WaitingParcel")
  if held==null:
   held=asset("cargo_crate",false);held.name="WaitingParcel";held.scale=Vector3.ONE*.35;held.position=Vector3(.3,.95,.55);figure.add_child(held)
  held.visible=str(c.status)=="available"
  customer.target=Vector3(-15.5-float(i),.02,1.65) if str(c.status) in ["declined","cancelled","settled"] or night or (i>0 and str(contracts[0].status) in ["available","accepted"]) else Vector3(-10.2,.02,1.65)
 for id in customers.keys():
  if not id in seen:customers[id].node.queue_free();customers.erase(id)
 var current:String=str(data.get("active_contract_id",""))
 if current!=active_id:
  active_id=current
  if not current.is_empty():
   parcel.show();parcel.position=Vector3(-9.1,1.5,1.0);parcel_state="counter"
   var tween=create_tween();tween.tween_property(parcel,"position",Vector3(-8.0,1.6,.65),0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
  else:parcel.hide();parcel_state="empty"
 _clear(supply_root)
 var stock:Dictionary=data.get("inventory",{}).duplicate()
 for installed in data.get("installed",[]):stock[str(installed.type)]=int(stock.get(str(installed.type),0))-1
 var visible_stock:int=0
 for type in stock:
  if int(stock[type])<=0 or not catalog.has(type):continue
  var sample=asset(str(catalog[type].model),false);sample.scale=Vector3.ONE*.32;sample.position=Vector3(-3.9+float(visible_stock%2)*.42,.7+float(visible_stock/2)*.42,1.35);supply_root.add_child(sample);visible_stock+=1
  if visible_stock>=6:break
 # Visible upgrade lamps reflect actual charger level.
 var level:int=int(data.get("research",0))
 for i in range(3):
  var name="UpgradeLamp"+str(i);var lamp=workshop_root.get_node_or_null(name)
  if lamp==null:lamp=box(workshop_root,Vector3(5.7,1.7+float(i)*.25,1.0),Vector3(0.18,0.12,0.12),Color("142042"));lamp.name=name
  lamp.material_override=flat(Color("35d4d2") if i<level else Color("142042"))

func pack_parcel() -> void:
 if parcel_state!="counter":return
 parcel_state="loaded"
 var tween=create_tween();tween.tween_property(parcel,"position",assembly_origin+Vector3(0,0,0.4),0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT);tween.tween_callback(parcel.hide)

func hotspot_positions() -> Array:
 if mode=="flight":return []
 return [{"id":"focus_counter","label":"柜台 · 接待客户","position":_screen_point(Vector3(-8,2,1.0))},{"id":"focus_workbench","label":"工位 · 拼装装置","position":_screen_point(Vector3(1,4.7,1))},{"id":"focus_supply","label":"供应箱 · 夜间准备" if night else "供应商傍晚到店","position":_screen_point(Vector3(-3.8,1.6,1.4))}]

func line(parent:Node3D,a:Vector3,b:Vector3,color:Color) -> void:
 var mesh=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES,flat(color));mesh.surface_add_vertex(a);mesh.surface_add_vertex(b);mesh.surface_end();var node=MeshInstance3D.new();node.mesh=mesh;parent.add_child(node)

func _flight_part(p:Dictionary) -> Node3D:
 var key="p"+str(p.id)
 if not flight_nodes.has(key):
  var n=asset(str(catalog.get(str(p.type),{}).get("model","cargo_crate")));flight_root.add_child(n);flight_nodes[key]=n
  if p.type=="thruster":
   var flame=Node3D.new();flame.name="Flame";n.add_child(flame)
   for layer in [[1.1,.25,"35d4d2"],[.72,.17,"fff0bd"]]:
    var plume=MeshInstance3D.new();var cone=CylinderMesh.new();cone.top_radius=0;cone.bottom_radius=float(layer[1]);cone.height=float(layer[0]);cone.radial_segments=8;plume.mesh=cone;plume.rotation.z=PI/2;plume.position=Vector3(-.46-float(layer[0])*.5,0,.04);plume.material_override=flat(Color(str(layer[2])));flame.add_child(plume)
 return flight_nodes[key]

func start_flight(sim=null) -> void:
 _clear(flight_root);flight_nodes={};trails=[];last_integrity=1;terminal_age=-1;launch_age=0;focus("flight")
 if sim!=null:_build_launch_pad(sim)

func show_flight(sim) -> void:
 if mode!="flight":start_flight(sim)
 var cargo:Vector2=sim.cargo_position();var at=Vector3(cargo.x,-cargo.y,0)+flight_origin
 camera_target=at+Vector3(4,0.7,0);desired_camera=camera_target+Vector3(0,2.8,28);camera_size=12.5 if reduced_motion else 12.5+clampf(float(sim.telemetry.get("speed",0))*.035,0,.7)
 var launch_recoil:float=0.0
 if launch_age<1.35 and not reduced_motion:
  var charge:float=clampf(launch_age/.7,0,1)
  if launch_age<.7:
   launch_recoil=-.12*charge;camera_size=lerpf(10.5,8.7,charge);camera_target=at+Vector3(-1,.5,0)
  elif launch_age<.95:
   var ignite:float=(launch_age-.7)/.25;launch_recoil=.08*sin(ignite*PI);camera_size=lerpf(8.7,10.6,ignite);camera_target=at+Vector3(-1-.45*sin(ignite*PI),.5,0)
  else:
   var release:float=(launch_age-.95)/.4;camera_size=lerpf(10.6,12.5,release);camera_target=at+Vector3(lerpf(-1,4,release),.5,0)
  desired_camera=camera_target+Vector3(0,2.8,28)
 city_root.get_child(0).hide();city_root.get_child(1).show();city_root.position=Vector3(cargo.x*.72,-1,-6);city_root.scale=Vector3.ONE*.65;sky_root.position=Vector3(cargo.x*.3,0,0)
 for p in sim.parts.values():
  var n=_flight_part(p);n.visible=bool(p.get("alive",false)) and (not bool(p.get("delivered",false)) or sim.status=="success")
  if not n.visible:continue
  var pos:Vector2=sim.part_world_position(int(p.id));n.position=Vector3(pos.x,-pos.y,0)+flight_origin
  n.position+=Vector3(launch_recoil,0,0)
  n.rotation.z=-float(p.get("world_angle",0));n.scale=Vector3.ONE*.93*float(p.get("scale",1))
  var flame=n.get_node_or_null("Flame")
  if flame!=null:flame.visible=bool(p.get("active",false)) and sim.status=="running";flame.scale.x=1.0+0.2*sin(visual_time*40)
 _update_flight_joints(sim,launch_recoil)
 if not flight_nodes.has("launch_pad"):
  _build_launch_pad(sim)
 var fixed_pad:Node3D=flight_nodes.launch_pad;fixed_pad.visible=cargo.x<9.0
 for object in fixed_pad.get_children():
  if str(object.name).begins_with("Spring"):
   object.scale.x=.78*(1.0-.36*clampf(launch_age/.7,0,1)) if launch_age<.7 else .78*(1.0+.18*sin(clampf((launch_age-.7)/.25,0,1)*PI))
 if not flight_nodes.has("launch_burst"):
  var burst=Node3D.new();flight_root.add_child(burst);flight_nodes.launch_burst=burst
  for ray in range(12):
   var angle:float=float(ray)*TAU/12;var stroke=box(burst,Vector3(cos(angle)*2.5,sin(angle)*2.5,-.7),Vector3(1.25,.085,.05),Color("fff0bd") if ray%2==0 else Color("f56c6c"));stroke.rotation.z=angle
 var launch_burst:Node3D=flight_nodes.launch_burst
 launch_burst.visible=not reduced_motion and launch_age>=.7 and launch_age<1.12
 launch_burst.position=at+Vector3(-1,0,0);launch_burst.scale=Vector3.ONE*(.65+clampf((launch_age-.7)/.42,0,1)*.6)
 for i in range(sim.obstacles.size()):
  var h=sim.obstacles[i];var key="h"+str(i);var type=str(h.get("type","rock"))
  if not flight_nodes.has(key):
   var n=asset("accelerator" if type=="turret" else ("decoy" if type=="tracker" else "asteroid_"+str(i%3)));flight_root.add_child(n);flight_nodes[key]=n
  var n:Node3D=flight_nodes[key];n.visible=float(h.health)>0;n.position=Vector3(h.position.x,-h.position.y,0)+flight_origin;n.scale=Vector3.ONE*float(h.radius)
  if type in ["tracker","turret"]:n.rotation.z=atan2(at.y-n.position.y,at.x-n.position.x)
 if not flight_nodes.has("destination"):
  var pad=asset("environment_v2/destination_kiosk",false);pad.position=flight_origin+Vector3(route_distance,-route_radius-1.4,0);flight_root.add_child(pad);flight_nodes.destination=pad
  var hoop=MeshInstance3D.new();var circle=TorusMesh.new();circle.inner_radius=route_radius-.055;circle.outer_radius=route_radius+.055;circle.rings=64;circle.ring_segments=8;hoop.mesh=circle;hoop.rotation.x=PI/2;hoop.position=flight_origin+Vector3(route_distance,0,-.15);hoop.material_override=flat(Color("fff0bd"));flight_root.add_child(hoop)
  var sign=Label3D.new();sign.font=load("res://assets/fonts/ChineseSans.otf");sign.font_size=48;sign.pixel_size=.014;sign.text="收件区域";sign.modulate=Color("fff0bd");sign.outline_modulate=Color("142042");sign.outline_size=9;sign.position=flight_origin+Vector3(route_distance,route_radius+.7,0);flight_root.add_child(sign)
 if sim.status!="running":
  if terminal_age<0:terminal_age=0
  camera_target=at+Vector3(0,.4,0);desired_camera=camera_target+Vector3(0,2.8,28);camera_size=13.5
  if not flight_nodes.has("arrival"):
   var label=Label3D.new();label.font=load("res://assets/fonts/ChineseSans.otf");label.font_size=72;label.pixel_size=.018;label.text="已签收 ✓" if sim.status=="success" else "航行中断";label.modulate=Color("fff0bd") if sim.status=="success" else Color("f56c6c");label.outline_modulate=Color("142042");label.outline_size=12;label.position=at+Vector3(0,2,1);flight_root.add_child(label);flight_nodes.arrival=label
 if trails.is_empty() or Vector2(trails.back()).distance_to(cargo)>0.25:trails.append(cargo)
 if trails.size()>55:trails.pop_front()
 _draw_flight_effects(sim,at)
 var integrity:float=float(sim.telemetry.get("integrity",1))
 if integrity<last_integrity-0.001 and not reduced_motion:shake=0.2
 last_integrity=integrity

func leave_flight() -> void:
 effect_mesh.clear_surfaces();effect_node.hide();visible_effect_count=0;visible_ring_count=0
 _clear(flight_root);flight_nodes={};city_root.get_child(0).show();city_root.get_child(1).hide();city_root.position=Vector3.ZERO;city_root.scale=Vector3.ONE*.75;sky_root.position=Vector3.ZERO;focus("hub")

func _build_launch_pad(sim) -> void:
 # The actual anchored modules use the simulation's socket coordinates behind
 # the craft. A fixed cradle makes their ground contact intelligible on screen.
 var fixed_pad=Node3D.new();fixed_pad.name="AnchoredLauncher";flight_root.add_child(fixed_pad);flight_nodes.launch_pad=fixed_pad
 if sim.launcher_parts.is_empty():return
 var left:float=INF;var right:float=-INF;var bottom:float=0.0
 var support_points:Array=[]
 for module in sim.launcher_parts:
  var pos:Vector2=module.world_pos
  left=minf(left,pos.x-.55);right=maxf(right,pos.x+.55);bottom=maxf(bottom,pos.y+.55)
  var object=asset(str(catalog.get(str(module.type),{}).get("model","beam")))
  object.position=Vector3(pos.x,-pos.y,-.15)+flight_origin;object.rotation.z=-float(module.local_angle);object.scale=Vector3.ONE*.78
  object.name="Spring"+str(module.id) if module.type=="spring" else "Pad"+str(module.id);fixed_pad.add_child(object)
  if module.type!="spring":support_points.append({"id":module.id,"x":pos.x+flight_origin.x,"bottom":flight_origin.y-pos.y-.41})
 var craft_right:float=right
 for part in sim.parts.values():
  var pos:Vector2=sim.part_world_position(int(part.id));craft_right=maxf(craft_right,pos.x+.65);bottom=maxf(bottom,pos.y+.55)
 var floor_y:float=flight_origin.y-bottom+.03
 var middle:float=(left+craft_right)*.5+flight_origin.x;var width:float=craft_right-left+.5
 var rail=asset("environment_v4/launch_rail",false);rail.position=Vector3(middle,floor_y,flight_origin.z-.2);rail.scale.x=width;fixed_pad.add_child(rail)
 for support_x in [left+.3,right-.2,craft_right-.25]:
  var x:float=float(support_x)+flight_origin.x
  var pier=asset("environment_v4/launch_pier",false);pier.position=Vector3(x,floor_y-1.55,flight_origin.z-.2);fixed_pad.add_child(pier)
 for point in support_points:
  var contact:float=float(point.bottom)-floor_y
  if contact<.08:continue
  var stand=asset("environment_v4/assembly_lift",false);stand.name="AnchoredModuleSupport"+str(point.id)
  # The compact two-row craft leaves only0.61m under its fixed launcher.
  # Compress the support vertically below its authored minimum extension,
  # rather than dropping a required bracket and leaving modules floating.
  var vertical_scale:float=minf(1.0,contact/.66)
  var local_contact:float=contact/vertical_scale
  stand.position=Vector3(point.x,floor_y,flight_origin.z-.15);stand.scale.y=vertical_scale;fixed_pad.add_child(stand)
  stand.set_meta("support_contact_y",float(point.bottom))
  var piston=stand.find_child("PistonRod",true,false);var saddle=stand.find_child("TopSaddle",true,false)
  if piston!=null and saddle!=null:saddle.position.y=local_contact;piston.scale.y=maxf(.02,local_contact-.43)
 var pad_joints=_new_joint_batch(fixed_pad,"AnchoredStructuralJoints");var pad_poses:Array[Transform3D]=[];var pad_ids:Array=[]
 for i in range(sim.launcher_parts.size()):
  for j in range(i+1,sim.launcher_parts.size()):
   var a:Dictionary=sim.launcher_parts[i];var b:Dictionary=sim.launcher_parts[j]
   if absi(int(a.x)-int(b.x))+absi(int(a.y)-int(b.y))!=1:continue
   var pa:Vector3=Vector3(a.world_pos.x,-a.world_pos.y,-.15)+flight_origin;var pb:Vector3=Vector3(b.world_pos.x,-b.world_pos.y,-.15)+flight_origin
   pad_poses.append(_joint_pose(pa,pb,1.15));pad_ids.append([int(a.id),int(b.id)])
 _set_joint_instances(pad_joints,pad_poses,pad_ids)

func _structural_joint_mesh() -> Mesh:
 if joint_mesh!=null:return joint_mesh
 if DisplayServer.get_name()=="headless":
  var placeholder=BoxMesh.new();placeholder.size=Vector3(.32,.48,.68);joint_mesh=placeholder;return joint_mesh
 var source=asset("modules_v4/joint_sleeve",false)
 var meshes=source.find_children("*","MeshInstance3D",true,false)
 if source is MeshInstance3D:meshes.push_front(source)
 if not meshes.is_empty():
  var authored:MeshInstance3D=meshes[0];joint_mesh=authored.mesh.duplicate()
  for surface in range(joint_mesh.get_surface_count()):joint_mesh.surface_set_material(surface,authored.get_surface_override_material(surface))
 source.free()
 return joint_mesh

func _new_joint_batch(parent:Node3D,node_name:String) -> MultiMeshInstance3D:
 var node=MultiMeshInstance3D.new();node.name=node_name;node.multimesh=MultiMesh.new();node.multimesh.transform_format=MultiMesh.TRANSFORM_3D;node.multimesh.mesh=_structural_joint_mesh();parent.add_child(node);return node

func _joint_pose(a:Vector3,b:Vector3,scale_factor:float=1.0) -> Transform3D:
 var delta:Vector3=b-a
 return Transform3D(Basis(Vector3.BACK,atan2(delta.y,delta.x)).scaled(Vector3.ONE*scale_factor),(a+b)*.5)

func _set_joint_instances(node:MultiMeshInstance3D,poses:Array[Transform3D],ids:Array) -> void:
 var count:int=mini(poses.size(),MAX_VISIBLE_JOINTS)
 if node.multimesh.instance_count!=count:node.multimesh.instance_count=count
 for i in range(count):node.multimesh.set_instance_transform(i,poses[i])
 node.visible=count>0;node.set_meta("structural_edges",ids.slice(0,count))

func _update_flight_joints(sim,recoil:float=0.0) -> void:
 if not flight_nodes.has("structural_joints"):flight_nodes.structural_joints=_new_joint_batch(flight_root,"LiveStructuralJoints")
 var poses:Array[Transform3D]=[];var ids:Array=[]
 for link in sim.links:
  if not sim.parts.has(link.a) or not sim.parts.has(link.b):continue
  var a:Dictionary=sim.parts[link.a];var b:Dictionary=sim.parts[link.b]
  if not bool(a.alive) or not bool(b.alive) or int(a.body_id)!=int(b.body_id):continue
  if (bool(a.delivered) or bool(b.delivered)) and sim.status!="success":continue
  var p:Vector2=sim.part_world_position(int(a.id));var q:Vector2=sim.part_world_position(int(b.id))
  var pa:Vector3=Vector3(p.x,-p.y,0)+flight_origin+Vector3(recoil,0,0);var pb:Vector3=Vector3(q.x,-q.y,0)+flight_origin+Vector3(recoil,0,0)
  poses.append(_joint_pose(pa,pb,.93*minf(float(a.scale),float(b.scale))));ids.append([int(a.id),int(b.id)])
 _set_joint_instances(flight_nodes.structural_joints,poses,ids)

func _ensure_effect_batch() -> void:
 if is_instance_valid(effect_node):return
 effect_material=StandardMaterial3D.new();effect_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;effect_material.vertex_color_use_as_albedo=true;effect_material.cull_mode=BaseMaterial3D.CULL_DISABLED
 effect_mesh=ImmediateMesh.new();effect_node=MeshInstance3D.new();effect_node.name="FlightEffectsBatch";effect_node.mesh=effect_mesh;effect_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;fx_root.add_child(effect_node);effect_node.hide()

func _effect_line(a:Vector3,b:Vector3,color:Color) -> void:
 effect_mesh.surface_set_color(color);effect_mesh.surface_add_vertex(a);effect_mesh.surface_add_vertex(b)

func _effect_ring(center:Vector3,inner:float,outer:float,color:Color) -> void:
 effect_mesh.surface_set_color(color)
 for segment in range(EFFECT_RING_SEGMENTS):
  var a:float=TAU*float(segment)/EFFECT_RING_SEGMENTS;var b:float=TAU*float(segment+1)/EFFECT_RING_SEGMENTS
  var ai:Vector3=center+Vector3(cos(a),sin(a),0)*inner;var ao:Vector3=center+Vector3(cos(a),sin(a),0)*outer
  var bi:Vector3=center+Vector3(cos(b),sin(b),0)*inner;var bo:Vector3=center+Vector3(cos(b),sin(b),0)*outer
  for vertex in [ai,ao,bo,ai,bo,bi]:effect_mesh.surface_add_vertex(vertex)

func _draw_flight_effects(sim,at:Vector3) -> void:
 _ensure_effect_batch();effect_mesh.clear_surfaces();effect_node.show();visible_effect_count=0;visible_ring_count=0
 var visible:Array=[];var rings:Array=[];var ring_cells:Dictionary={}
 # Bound visible work independently of the simulation's complete event list.
 # The newest nearby events win, and coincident teleport rings are one flash.
 for i in range(sim.effects.size()-1,-1,-1):
  if visible_effect_count>=MAX_VISIBLE_EFFECTS:break
  var e:Dictionary=sim.effects[i];var a:Vector2=e.get("from",Vector2.ZERO);var b:Vector2=e.get("to",a);var kind:String=str(e.get("type",""))
  var center:Vector2=sim.cargo_position()
  if a.distance_to(center)>camera_size*2.0 and (kind=="explosion" or b.distance_to(center)>camera_size*2.0):continue
  visible.append(e);visible_effect_count+=1
  if kind=="explosion" and rings.size()<MAX_VISIBLE_RINGS:
   rings.append({"position":Vector3(a.x,-a.y,.3)+flight_origin,"inner":maxf(.1,b.x-.1),"outer":maxf(.2,b.x),"color":Color("ffd447")})
  elif kind=="teleport":
   for point in [a,b]:
    if rings.size()>=MAX_VISIBLE_RINGS:break
    var cell:=Vector2i(roundi(point.x*3),roundi(point.y*3))
    if ring_cells.has(cell):continue
    ring_cells[cell]=true;var scale:float=1.0+float(e.get("ttl",0))
    rings.append({"position":Vector3(point.x,-point.y,.4)+flight_origin,"inner":.65*scale,"outer":.78*scale,"color":Color("35d4d2")})
 visible_ring_count=rings.size()
 # A single line surface contains the trajectory, speed strokes and beams.
 effect_mesh.surface_begin(Mesh.PRIMITIVE_LINES,effect_material)
 var line_count:int=0
 if not reduced_motion and sim.status=="running" and float(sim.telemetry.get("speed",0))>4:
  for stripe in range(5):
   var offset=fposmod(visual_time*(8+stripe)+float(stripe)*3.7,18)-9
   var y:float=(-3.4 if stripe%2==0 else 3.4)+float(stripe)*.15
   _effect_line(at+Vector3(offset,y,-3),at+Vector3(offset-1.1-float(stripe)*.15,y,-3),Color("a9e7dc"));line_count+=1
 for i in range(1,trails.size()):
  var a:Vector2=trails[i-1];var b:Vector2=trails[i]
  _effect_line(Vector3(a.x,-a.y,-.6)+flight_origin,Vector3(b.x,-b.y,-.6)+flight_origin,Color("b7e9e1"));line_count+=1
 for e in visible:
  var a:Vector2=e.get("from",Vector2.ZERO);var b:Vector2=e.get("to",a);var kind:String=str(e.get("type",""))
  if kind=="explosion":continue
  var color:Color=Color("35d4d2") if kind=="teleport" else (Color("f56c6c") if kind=="enemy" else Color("fff0bd"))
  _effect_line(Vector3(a.x,-a.y,.5)+flight_origin,Vector3(b.x,-b.y,.5)+flight_origin,color);line_count+=1
 # ImmediateMesh requires a nonempty surface; this degenerate segment is invisible.
 if line_count==0:_effect_line(Vector3.ZERO,Vector3.ZERO,Color.TRANSPARENT)
 effect_mesh.surface_end()
 if not rings.is_empty():
  effect_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,effect_material)
  for ring in rings:_effect_ring(ring.position,ring.inner,ring.outer,ring.color)
  effect_mesh.surface_end()

func _register_actor(actor:Node3D) -> void:
 var pivots:Array=[]
 for node in actor.find_children("*Pivot*","Node3D",true,false):
  if not node is MeshInstance3D:pivots.append({"node":node,"rest":node.rotation,"name":str(node.name)})
 actor.set_meta("pose_pivots",pivots)

func _animate_actor(actor:Node3D,moving:bool,offset:float=0.0,gesturing:bool=false) -> void:
 for pivot in actor.get_meta("pose_pivots",[]):
  var node:Node3D=pivot.node;var pose:Vector3=pivot.rest;var name:String=pivot.name
  if not reduced_motion:
   var walk:float=sin(visual_time*10+offset)
   if name.begins_with("LeftLeg"):pose.z+=walk*.16 if moving else 0.0
   elif name.begins_with("RightLeg"):pose.z-=walk*.16 if moving else 0.0
   elif name.begins_with("LeftArm"):pose.z-=walk*.10 if moving else sin(visual_time*2.2+offset)*(.08 if gesturing else .025)
   elif name.begins_with("RightArm"):pose.z+=walk*.10 if moving else sin(visual_time*2.2+offset+1)*(.10 if gesturing else .025)
   elif name.begins_with("Head"):pose.z+=sin(visual_time*1.7+offset)*.025
  node.rotation=pose

func _process(delta:float) -> void:
 visual_time+=delta
 if terminal_age>=0:terminal_age+=delta
 var blend:float=1.0-exp(-delta*6.0)
 if mode=="flight" and launch_age<1.35 and not reduced_motion:
  smooth_camera_position=desired_camera;smooth_camera_size=camera_size;smooth_camera_look=camera_target
 else:
  smooth_camera_position=smooth_camera_position.lerp(desired_camera,blend);smooth_camera_size=lerpf(smooth_camera_size,camera_size,blend);smooth_camera_look=smooth_camera_look.lerp(camera_target,blend)
 camera.size=smooth_camera_size;camera.position=smooth_camera_position;camera_look=smooth_camera_look
 # This authored side view has no yaw/roll. A deterministic pitch avoids tiny
 # look_at basis changes when an otherwise rigid camera translates vertically.
 var pitch:float=snappedf(atan2(camera_look.y-camera.position.y,camera.position.z-camera_look.z),.000001)
 camera.rotation=Vector3(pitch,0,0)
 # Snap the rendered camera, not the smoothing state, so movement does not stick.
 var pixel:float=camera.size/maxf(1,float(get_viewport().size.y))
 var right:Vector3=camera.basis.x;var up:Vector3=camera.basis.y;var back:Vector3=camera.basis.z
 var horizontal:float=snappedf(camera.position.dot(right),pixel);var vertical:float=snappedf(camera.position.dot(up),pixel)
 var depth:float=snappedf(camera.position.dot(back),pixel)
 camera.position=right*horizontal+up*vertical+back*depth
 if shake>0 and not reduced_motion:shake=maxf(0,shake-delta);camera.h_offset=roundf(sin(visual_time*75)*shake*.35/pixel)*pixel;camera.v_offset=roundf(cos(visual_time*60)*shake*.25/pixel)*pixel
 else:camera.h_offset=0;camera.v_offset=0
 if mode!="flight":
  ship_root.position.y=assembly_origin.y
  clerk.position.x=move_toward(clerk.position.x,clerk_destination,delta*4.0)
  var moving:bool=absf(clerk.position.x-clerk_destination)>0.1
  var standing_height:float=lerpf(.02,.25,clampf((-5.4-clerk.position.x)/1.2,0,1))
  clerk.position.y=standing_height+absf(sin(visual_time*10))*.035 if moving else standing_height+sin(visual_time*2)*.008
  _animate_actor(clerk,moving,0.0,mode=="contracts")
  for record in customers.values():
   var n:Node3D=record.node;var distance=n.position.distance_to(record.target)
   n.position=n.position.move_toward(record.target,delta*3.0);n.position.y=.02+absf(sin(visual_time*8+float(record.index)))*.035 if distance>.15 else .02+sin(visual_time*2+record.index)*.008
   _animate_actor(n,distance>.15,float(record.index)*1.7,mode=="contracts" and int(record.index)==0)

func _screen_point(point:Vector3) -> Vector2:
 var pixel:Vector2=camera.unproject_position(point)
 return screen_mapper.pixel_to_screen(pixel) if is_instance_valid(screen_mapper) else pixel

func _build_lighting() -> void:
 sun=DirectionalLight3D.new();sun.name="WarmUpperRightSun";sun.rotation_degrees=Vector3(-40,50,0)
 sun.light_color=Color("ffe3ad");sun.light_energy=1.08;sun.shadow_enabled=true
 sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=60
 sun.directional_shadow_fade_start=1.0;sun.directional_shadow_pancake_size=0
 sun.shadow_bias=.05;sun.shadow_normal_bias=1.0;add_child(sun)
 for position in [Vector3(-8,5.8,1.2),Vector3(1,6.7,.5)]:
  var lamp=OmniLight3D.new();lamp.position=position;lamp.light_color=Color("ffbd64");lamp.light_energy=.48
  lamp.omni_range=8.0;lamp.omni_attenuation=1.25;lamp.shadow_enabled=false;add_child(lamp);shop_lights.append(lamp)

 for location in [Vector3(-10.68,5.37,.25),Vector3(-5.07,5.75,.25)]:
  var practical=SpotLight3D.new();practical.position=location;practical.light_color=Color("ffca7b");practical.light_energy=2.1
  practical.spot_range=6.7;practical.spot_angle=42;practical.spot_attenuation=1.0;practical.spot_angle_attenuation=1.5
  practical.shadow_enabled=true;practical.shadow_bias=.04;practical.shadow_normal_bias=.8
  add_child(practical);practical.look_at(Vector3(location.x,1.1,-.75),Vector3.FORWARD);shop_lights.append(practical)
 var daylight=SpotLight3D.new();daylight.name="OpenBayWarmBounce";daylight.position=Vector3(8,7,3.6)
 daylight.light_color=Color("ffe0a2");daylight.light_energy=.4;daylight.spot_range=20;daylight.spot_angle=48;daylight.spot_attenuation=.55;daylight.spot_angle_attenuation=.75
 daylight.shadow_enabled=true;daylight.shadow_bias=.15;daylight.shadow_normal_bias=1.2;daylight.shadow_blur=0.0
 add_child(daylight);daylight.look_at(Vector3(-1,0,-.8),Vector3.UP);shop_lights.append(daylight)

func apply_quality(profile:String) -> void:
 var size:int=1024 if profile=="low" else (4096 if profile=="high" else 2048)
 RenderingServer.directional_shadow_atlas_set_size(size,false)
 if get_viewport() is SubViewport:get_viewport().positional_shadow_atlas_size=512 if profile=="low" else (2048 if profile=="high" else 1024)

func _update_maintenance_lifts(design:Array) -> void:
 _clear(lift_root)
 if design.is_empty():return
 var left:float=INF;var right:float=-INF;var bottom:float=INF
 for part in design:
  left=minf(left,assembly_origin.x+float(part.x));right=maxf(right,assembly_origin.x+float(part.x))
  bottom=minf(bottom,assembly_origin.y-float(part.y)-.53)
 var contact:float=bottom-.46
 if contact<.66:return # Lowest row rests directly on the workshop platform.
 var span:float=right-left
 var places:Array=[(left+right)*.5] if span<1.5 else [left+.5,right-.5]
 for x in places:
  var stand=asset("environment_v4/assembly_lift",false);stand.position=Vector3(x,.46,.35);lift_root.add_child(stand)
  var piston=stand.find_child("PistonRod",true,false);var saddle=stand.find_child("TopSaddle",true,false)
  if piston!=null and saddle!=null:saddle.position.y=contact;piston.scale.y=maxf(.02,contact-.43)
