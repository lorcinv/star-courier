extends Node2D
## Raster-only presentation. Never owns design, simulation, cargo, or input.
## sync_assembly is called after committed edits; bind_transfer follows the same
## real part IDs as the editor-to-flight representation changes. No own clock.
const Plan=preload("res://scripts/workshop_support_plan_2d.gd")
const ROOT:String="res://assets/2d_v5/workshop-support/"
const MAX_RAIL_TILES:int=64
const MAX_ARMS:int=2
const MAX_JACKS:int=153
var floor_y:float=486.0
var rail_span:Vector2=Vector2(404,1280)
var _rail:Node2D
var _jacks:Node2D
var _arms:Node2D
var _targets:Dictionary={}
var _records:Array=[]
var _jack_nodes:Array=[]
var _arm_nodes:Array=[]
var _textures:Dictionary={}
var _contact_cache:Dictionary={}
var _phase:String="workshop"
var _release:float=0.0
var _scene_visible:bool=true
var _last_contacts:Dictionary={}
var _last_debug:Array=[]
var _registered:Dictionary={}

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 z_index=2
 _rail=Node2D.new();_rail.name="RasterFloorRail";add_child(_rail)
 _arms=Node2D.new();_arms.name="BackgroundHoldingArms";_arms.z_index=-1;add_child(_arms)
 _jacks=Node2D.new();_jacks.name="TravelingUnderbodyJacks";add_child(_jacks)
 var path:String=ROOT+"registration.json"
 if FileAccess.file_exists(path):
  var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
  if parsed is Dictionary:_registered=parsed
 _build_rail();_build_arms()

func configure_stage(new_floor_y:float,new_rail_span:Vector2) -> bool:
 if not is_finite(new_floor_y) or not new_rail_span.is_finite() or new_rail_span.y<=new_rail_span.x:return false
 if is_equal_approx(floor_y,new_floor_y) and rail_span==new_rail_span:return true
 floor_y=new_floor_y;rail_span=new_rail_span
 if is_instance_valid(_rail):_build_rail()
 return true

func _texture(key:String) -> Texture2D:
 if _textures.has(key):return _textures[key]
 var path:String=ROOT+key+".png"
 var texture:Texture2D=load(path) as Texture2D if ResourceLoader.exists(path) else null
 _textures[key]=texture
 return texture

func _sprite(key:String,parent:Node) -> Sprite2D:
 var sprite:=Sprite2D.new();sprite.texture=_texture(key);sprite.centered=false;sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 sprite.set_meta("art_id",key);parent.add_child(sprite);return sprite

func _clear(node:Node) -> void:
 for child in node.get_children():node.remove_child(child);child.queue_free()

func _build_rail() -> void:
 _clear(_rail)
 var texture:Texture2D=_texture("rail-middle")
 if texture==null:return
 var x:float=rail_span.x;var width:float=float(texture.get_width());var count:int=0
 while x<rail_span.y and count<MAX_RAIL_TILES:
  var tile:Sprite2D=_sprite("rail-middle",_rail)
  tile.region_enabled=true;tile.region_rect=Rect2(0,0,minf(width,rail_span.y-x),texture.get_height())
  tile.position=Vector2(x,floor_y-float(texture.get_height()));x+=tile.region_rect.size.x;count+=1
 for side in ["left","right"]:
  var cap:Sprite2D=_sprite("rail-"+side,_rail)
  if cap.texture!=null:cap.position=Vector2(rail_span.x if side=="left" else rail_span.y-cap.texture.get_width(),floor_y-cap.texture.get_height())

func _contact(node:Sprite2D) -> Vector2:
 # The bearing is measured from actual opaque raster pixels, including rotation.
 # Work in the texture's local space; do not assume a universal cell-box bottom.
 var texture:Texture2D=node.texture
 if texture==null:return node.global_position
 var angle_quarters:int=posmod(roundi(node.global_rotation/(PI*.5)),4)
 var key:String=str(texture.get_rid())+":"+str(angle_quarters)
 var local_contact:Vector2
 if _contact_cache.has(key):local_contact=_contact_cache[key]
 else:
  var im:Image=texture.get_image();var w:int=im.get_width();var h:int=im.get_height()
  var original_center:Vector2=Vector2(w,h)*.5
  var best:Vector2=Vector2(0,-INF)
  # Keep a central bearing band; a one-pixel outer decoration is never chosen.
  for y in range(h):
   for x in range(w):
    if im.get_pixel(x,y).a<.5:continue
    var p:Vector2=(Vector2(x+.5,y+1.0)-original_center).rotated(float(angle_quarters)*PI*.5)
    if absf(p.x)>float(w)*.13:continue
    if p.y>best.y or (is_equal_approx(p.y,best.y) and absf(p.x)<absf(best.x)):best=p
  if not best.is_finite():best=Vector2.ZERO
  # Cache original coordinates, so the actual final sprite transform supplies
  # scaling and position exactly once. Quarter-turn art matches runtime modules.
  local_contact=best.rotated(-float(angle_quarters)*PI*.5)
  _contact_cache[key]=local_contact
 return node.global_transform*local_contact

func sync_assembly(part_nodes:Dictionary,edges:Array) -> void:
 _targets.clear();var parts:Array=[]
 var ids:Array=part_nodes.keys();ids.sort()
 for id in ids:
  var node=part_nodes[id]
  if not node is Sprite2D or not is_instance_valid(node) or node.texture==null:continue
  if _targets.size()>=MAX_JACKS:break
  _targets[int(id)]=weakref(node)
  parts.append({"id":int(id),"contact":_contact(node),"center_x":node.global_position.x})
 _records=Plan.choose(parts,edges)
 _phase="workshop";_release=0.0;_last_contacts.clear()
 _ensure_jacks();present("workshop",0.0)

func bind_transfer(part_nodes:Dictionary) -> void:
 # Do not reseat or choose new support IDs when editor sprites are replaced by
 # flight sprites. An absent ID is a reported missing contact, never a fake ship.
 _targets.clear()
 for record in _records:
  var id:int=int(record.part_id)
  if part_nodes.has(id) and part_nodes[id] is Sprite2D and is_instance_valid(part_nodes[id]):_targets[id]=weakref(part_nodes[id])
 _phase="move";_release=0.0

func _ensure_jacks() -> void:
 while _jack_nodes.size()<_records.size() and _jack_nodes.size()<MAX_JACKS:
  var root:=Node2D.new();root.name="TravelJack"+str(_jack_nodes.size());_jacks.add_child(root)
  var piston:Sprite2D=_sprite("jack-piston",root)
  var cylinder:Sprite2D=_sprite("jack-cylinder",root)
  var base:Sprite2D=_sprite("jack-carriage",root)
  var saddle:Sprite2D=_sprite("jack-saddle",root)
  _jack_nodes.append({"root":root,"piston":piston,"cylinder":cylinder,"base":base,"saddle":saddle})
 for i in range(_jack_nodes.size()):_jack_nodes[i].root.visible=i<_records.size() and _scene_visible

func present(phase:String,release_progress:float=0.0,paused:bool=false) -> void:
 if not is_instance_valid(_jacks) or paused:return
 _phase=phase;_release=clampf(release_progress,0,1)
 var retract:bool=phase in ["retract","airborne"]
 if phase=="airborne":_release=1.0
 _last_debug.clear()
 for i in range(_records.size()):
  var record:Dictionary=_records[i];var id:int=int(record.part_id);var node:Sprite2D=null
  if _targets.has(id):node=_targets[id].get_ref() as Sprite2D
  var valid:bool=is_instance_valid(node) and node.texture!=null
  var desired:Vector2=_contact(node) if valid and phase!="airborne" else _last_contacts.get(id,Vector2(NAN,NAN))
  if desired.is_finite() and phase!="airborne":_last_contacts[id]=desired
  if not desired.is_finite():_jack_nodes[i].root.hide();_last_debug.append({"part_id":id,"missing_target":true});continue
  var minimum:float=float(_registered.get("minimum_contact_height",18.0))
  var bearing:Vector2=desired
  if retract:bearing.y=lerpf(desired.y,floor_y-minimum,_release)
  var foot:Vector2=Vector2(bearing.x,floor_y-float(_registered.get("rail_running_surface_offset",8.0)))
  _position_jack(_jack_nodes[i],bearing,foot)
  _jack_nodes[i].root.visible=_scene_visible
  _last_debug.append({"part_id":id,"component_id":record.component_id,"component_parts":record.component_parts.duplicate(),"desired_contact":desired,"bearing":bearing,"rail_anchor":foot,"floor_anchor":Vector2(foot.x,floor_y),"contact_error":bearing.distance_to(desired),"released":retract and _release>=1.0,"missing_target":not valid,"too_low":desired.y>floor_y-minimum+.5})
 _present_arms(phase)

func _position_jack(nodes:Dictionary,bearing:Vector2,foot:Vector2) -> void:
 var saddle:Sprite2D=nodes.saddle;var base:Sprite2D=nodes.base
 var cylinder:Sprite2D=nodes.cylinder;var piston:Sprite2D=nodes.piston
 var saddle_anchor:Array=_registered.get("saddle_contact",[18,7])
 var carriage_floor:Array=_registered.get("carriage_floor",[24,18])
 saddle.position=bearing-Vector2(float(saddle_anchor[0]),float(saddle_anchor[1]))
 base.position=foot-Vector2(float(carriage_floor[0]),float(carriage_floor[1]))
 var underside:float=saddle.position.y+float(saddle.texture.get_height())-3.0 if saddle.texture!=null else bearing.y+6.0
 var base_top:float=base.position.y+5.0
 var space:float=maxf(0.0,base_top-underside)
 if cylinder.texture!=null:
  var ch:float=minf(float(cylinder.texture.get_height()),space)
  cylinder.region_enabled=true;cylinder.region_rect=Rect2(0,0,cylinder.texture.get_width(),ch)
  cylinder.position=Vector2(foot.x-cylinder.texture.get_width()*.5,base_top-ch);cylinder.visible=ch>0
 if piston.texture!=null:
  var end_y:float=cylinder.position.y+3.0 if cylinder.visible else base_top
  var length:float=maxf(0.0,end_y-underside)
  piston.position=Vector2(foot.x-piston.texture.get_width()*.5,underside)
  piston.scale=Vector2(1.0,length/maxf(1.0,float(piston.texture.get_height())));piston.visible=length>0

func _build_arms() -> void:
 for i in range(MAX_ARMS):
  var root:=Node2D.new();root.name="RearHoldingArm"+str(i);_arms.add_child(root)
  _arm_nodes.append({"root":root,"post":_sprite("arm-post",root),"upper":_sprite("arm-link",root),"fore":_sprite("arm-link",root),"shoulder":_sprite("arm-joint",root),"elbow":_sprite("arm-joint",root),"claw":_sprite("arm-claw",root)})

func _link(sprite:Sprite2D,a:Vector2,b:Vector2) -> void:
 if sprite.texture==null:return
 var ends:Array=_registered.get("arm_link_endpoints",[[.5,6.5],[17.5,6.5]])
 var start:Vector2=Vector2(float(ends[0][0]),float(ends[0][1]))
 var finish:Vector2=Vector2(float(ends[1][0]),float(ends[1][1]))
 var source_axis:Vector2=finish-start;var destination_axis:Vector2=b-a
 if source_axis.length()<.001 or destination_axis.length()<.001:sprite.hide();return
 sprite.show()
 var source_unit:Vector2=source_axis.normalized();var source_normal:Vector2=source_unit.orthogonal()
 var destination_unit:Vector2=destination_axis.normalized();var destination_normal:Vector2=destination_unit.orthogonal()
 var stretch:float=destination_axis.length()/source_axis.length()
 # Only the plain shaft length changes. Its perpendicular thickness stays1;
 # endpoints are measured on actual opaque pixels, not transparent canvas edges.
 var basis_x:Vector2=destination_unit*source_unit.x*stretch+destination_normal*source_normal.x
 var basis_y:Vector2=destination_unit*source_unit.y*stretch+destination_normal*source_normal.y
 var transform_value:=Transform2D(basis_x,basis_y,Vector2.ZERO)
 transform_value.origin=a-transform_value*start;sprite.transform=transform_value
 sprite.set_meta("registered_start",start);sprite.set_meta("registered_end",finish)
 sprite.set_meta("expected_start",a);sprite.set_meta("expected_end",b)

func _place_joint(sprite:Sprite2D,point:Vector2) -> void:
 if sprite.texture==null:return
 var anchor:Array=_registered.get("arm_joint_pivot",[9.7,10.67])
 sprite.position=point-Vector2(float(anchor[0]),float(anchor[1]))

func _present_arms(phase:String) -> void:
 # Arms stay rear-mounted. They fold before transport; the traveling jacks keep
 # the load. Their post footprints never become robot collision/input blockers.
 for i in range(_arm_nodes.size()):
  var a:Dictionary=_arm_nodes[i]
  if _records.is_empty():a.root.hide();continue
  var rec:Dictionary=_records[mini(i,_records.size()-1)]
  var contact:Vector2=_last_contacts.get(int(rec.part_id),Vector2(rail_span.x+80,floor_y-100))
  var mount:Vector2=Vector2(clampf(contact.x+(-70.0 if i%2==0 else 70.0),rail_span.x+20.0,rail_span.y-20.0),floor_y)
  # Freeze rear mounts once movement begins, preventing chase of the ship.
  if phase=="workshop":a["mount"]=mount
  else:mount=a.get("mount",mount)
  var shoulder:Vector2=mount+Vector2(0,-26)
  var held:Vector2=contact+Vector2(0,-8)
  var parked:Vector2=shoulder+Vector2(30.0 if i%2==0 else -30.0,-16)
  var target:Vector2=held if phase=="workshop" else (held.lerp(parked,_release) if phase=="unclamp" else parked)
  var delta:Vector2=target-shoulder
  a["holding"]=phase=="workshop" and delta.length()<=240.0
  if delta.length()>240.0:target=parked
  var elbow:Vector2=(shoulder+target)*.5+Vector2(25.0 if i%2==0 else -25.0,-26)
  if a.post.texture!=null:a.post.position=mount-Vector2(a.post.texture.get_width()*.5,a.post.texture.get_height())
  var grip:Array=_registered.get("arm_claw_grip",[22.87,11.745])
  var wrist_anchor:Array=_registered.get("arm_claw_wrist",[7.0,5.107])
  var claw_origin:Vector2=target-Vector2(float(grip[0]),float(grip[1]))
  var wrist:Vector2=claw_origin+Vector2(float(wrist_anchor[0]),float(wrist_anchor[1]))
  _link(a.upper,shoulder,elbow);_link(a.fore,elbow,wrist)
  _place_joint(a.shoulder,shoulder);_place_joint(a.elbow,elbow)
  if a.claw.texture!=null:
   a.claw.position=claw_origin
   a.claw.set_meta("registered_wrist",Vector2(float(wrist_anchor[0]),float(wrist_anchor[1])))
   a.claw.set_meta("expected_wrist",wrist)
  a.root.visible=_scene_visible

func set_scene_visible(value:bool) -> void:
 _scene_visible=value;visible=value

func debug_snapshot() -> Dictionary:
 return {"phase":_phase,"release":_release,"floor_y":floor_y,"rail_span":rail_span,"supports":_last_debug.duplicate(true),"support_count":_records.size(),"jack_pool_count":_jack_nodes.size(),"rail_nodes":_rail.get_child_count() if is_instance_valid(_rail) else 0,"arm_count":_arm_nodes.size(),"arm_holding":_arm_nodes.map(func(a):return bool(a.get("holding",false))),"target_ids":_targets.keys()}
