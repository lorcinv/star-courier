extends "res://tools/qa_audio_game.gd"
## Read-only native QA sidecar. The production scene receives only OS input.
## Diagnostics never advance a scene, dispatch an action, or author a save.
class SingleMovementObserver extends Node:
 var game
 var samples:Array=[]
 var output:String=""
 var latest:String=""
 var last_usec:int=-100000
 var capped:bool=false
 const MAX_SAMPLES:int=12000
 func _ready() -> void:
  process_mode=Node.PROCESS_MODE_ALWAYS;process_priority=100
  output=OS.get_environment("SC_QA_TELEMETRY_OUTPUT")
  latest=output.get_base_dir().path_join("cooperative-latest.json")
  print("QA_SINGLE_MOVEMENT_OBSERVER_READY ",JSON.stringify({"max_hz":30,"max_samples":MAX_SAMPLES,"output":output,"mutates_gameplay":false}))
 func json_value(value:Variant) -> Variant:
  if value is Vector2 or value is Vector2i:return [value.x,value.y]
  if value is Rect2 or value is Rect2i:return [value.position.x,value.position.y,value.size.x,value.size.y]
  if value is Dictionary:
   var result:Dictionary={}
   for key in value:result[str(key)]=json_value(value[key])
   return result
  if value is Array:
   var result:Array=[]
   for item in value:result.append(json_value(item))
   return result
  if value is float and not is_finite(value):return null
  return value
 func optional_property(node:Object,key:String) -> Variant:
  for property in node.get_property_list():
   if str(property.name)==key:return node.get(key)
  return null
 func descendant_labels(node:Node,result:Array) -> void:
  for child in node.get_children():
   if child is Label and child.is_visible_in_tree():result.append(child.text)
   descendant_labels(child,result)
 func buttons(node:Node,result:Array) -> void:
  if node is Button and node.is_visible_in_tree():
   var rect:Rect2=node.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,node.size)
   var shown:Rect2=rect.intersection(get_viewport().get_visible_rect())
   var ancestor:Node=node.get_parent()
   while is_instance_valid(ancestor):
    if ancestor is Control and ancestor.clip_contents:
     shown=shown.intersection(ancestor.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,ancestor.size))
    ancestor=ancestor.get_parent()
   var labels:Array=[];descendant_labels(node,labels)
   if shown.size.x>1.0 and shown.size.y>1.0:
    result.append({"name":str(node.name),"path":str(node.get_path()),"text":node.text,"labels":labels,"tooltip":node.tooltip_text,"disabled":node.disabled,"rect":rect,"visible_rect":shown})
  for child in node.get_children():buttons(child,result)
 func parent_to_screen(point:Vector2,parent:CanvasItem) -> Vector2:
  var pixel:Vector2=parent.get_global_transform_with_canvas()*point
  return game.view_container.pixel_to_screen(pixel)
 func rect_to_screen(rect:Rect2,parent:CanvasItem) -> Rect2:
  var points:Array[Vector2]=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
  var result:Rect2=Rect2(parent_to_screen(points[0],parent),Vector2.ZERO)
  for point in points:result=result.expand(parent_to_screen(point,parent))
  return result
 func head_measurement() -> Dictionary:
  var motion=game.world._clerk_motion
  var sprite:Sprite2D=game.world.clerk
  var rigid:Dictionary=motion.debug_snapshot()
  if bool(rigid.get("rigid_active",false)):
   var bounds:Rect2=rigid.head_bounds_parent
   var screen:Rect2=rect_to_screen(bounds,sprite.get_parent())
   return {"available":true,"method":"Actual rigid head Sprite2D bounds transformed through camera and PixelStage; no pose mutation",
    "pose":rigid.pose,"texture":rigid.head_texture,"head_reference":rigid.head_reference,"head_view":"upright",
    "head_scene_rect":bounds,"head_scene_size":bounds.size,"head_screen_rect":screen,"head_screen_size":screen.size,
    "camera_zoom":game.world.camera.zoom,"pixel_scale":float(game.view_container.pixel_scale),
    "head_camera_and_pixel_normalized":screen.size/(game.world.camera.zoom*float(game.view_container.pixel_scale))}
  var frame:Dictionary=motion.current_frame()
  var box:Variant=frame.get("head_bounds",[])
  if not box is Array or box.size()!=4:return {"available":false,"reason":"current frame has no registered head bounds"}
  var source_points:Array[Vector2]=[Vector2(box[0],box[1]),Vector2(box[2],box[1]),Vector2(box[2],box[3]),Vector2(box[0],box[3])]
  var local_rect:Rect2=Rect2(motion.anchor_local(source_points[0]),Vector2.ZERO)
  for point in source_points:local_rect=local_rect.expand(motion.anchor_local(point))
  var scene_rect:Rect2=sprite.transform*local_rect
  var screen_rect:Rect2=rect_to_screen(local_rect,sprite)
  var pixel_scale:float=float(game.view_container.pixel_scale)
  var zoom:Vector2=game.world.camera.zoom
  return {"available":true,"method":"Registered head alpha bounds on actual current raster transformed through the live Sprite2D, Camera2D and integer PixelStage; no pose or camera mutation",
   "pose":str(sprite.get_meta("pose","")),"texture":sprite.texture.resource_path if sprite.texture!=null else "",
   "head_reference":frame.get("head_reference",""),"head_view":frame.get("head_view","upright"),"source_bounds":box,
   "sprite_scale":sprite.scale,"sprite_rotation":sprite.rotation,"flip_h":sprite.flip_h,
   "head_scene_rect":scene_rect,"head_scene_size":scene_rect.size,"head_screen_rect":screen_rect,"head_screen_size":screen_rect.size,
   "camera_zoom":zoom,"pixel_scale":pixel_scale,"head_screen_divided_by_camera_zoom":screen_rect.size/zoom,
   "head_camera_and_pixel_normalized":screen_rect.size/(zoom*pixel_scale)}
 func customer_measurements() -> Array:
  var result:Array=[]
  for id in game.world.customers:
   var entry:Dictionary=game.world.customers[id]
   var actor=entry.get("node")
   if not is_instance_valid(actor):continue
   var item:Dictionary=actor.debug_snapshot()
   item.order_id=id;item.visible=actor.is_visible_in_tree();item.position=actor.position;item.texture=actor.texture.resource_path if actor.texture!=null else ""
   result.append(item)
  return result
 func _process(_delta:float) -> void:
  if not is_instance_valid(game):
   for node in get_tree().root.get_children():
    if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":game=node;break
  if not is_instance_valid(game) or not is_instance_valid(game.world):return
  var now:int=Time.get_ticks_usec()
  if now-last_usec<33333:return
  last_usec=now
  if samples.size()>=MAX_SAMPLES:capped=true;return
  var ledger:Dictionary={}
  for key in ["credits","day","phase","deliveries","jobs_today","inventory","active_contract_id","settled_ids","history","in_flight"]:
   var value:Variant=game.economy.get(key)
   ledger[key]=value.duplicate(true) if value is Dictionary or value is Array else value
  var item:Dictionary={"engine_monotonic_usec":now,"unix_seconds":Time.get_unix_time_from_system(),
   "page":game.page,"trial":game.trial,"paused":game.paused,"loading":game.world.loading_snapshot(),
   "hud_visible":game.hud.visible,"overlay_open":game.loading_overlay.is_open(),
   "dialogue_open":game.dialogue.is_open(),"dialogue_line":game.dialogue._line_index,
   "dialogue_lines":game.dialogue._conversation.get("lines",[]).size(),
   "dialogue_visible_chars":game.dialogue._visible_chars,"ledger":ledger,
   "cargo_loaded":game.economy.is_cargo_loaded(),"design":game.design.duplicate(true),
   "launch_countdown":game.launch_countdown,"window_size":game.get_window().size,
   "clerk_position":game.world.clerk.position,"clerk_z":game.world.clerk.z_index,
   "camera_position":game.world.camera.position,"camera_zoom":game.world.camera.zoom,
   "connected_joypads":Input.get_connected_joypads(),
   "head_measurement":head_measurement(),"customers":customer_measurements(),
   "pixel_stage":{"canvas_size":game.view_container.canvas_size,"pixel_scale":game.view_container.pixel_scale,"display_rect":game.view_container.display_rect},
   "sign":{"visible":game.world.shop_sign.is_visible_in_tree(),"world_bounds":game.world.shop_sign.opaque_world_rect(),"screen_bounds":rect_to_screen(game.world.shop_sign.OPAQUE_BOUNDS,game.world.shop_sign)}}
  if game.world.has_method("shop_locomotion_snapshot"):item.locomotion=game.world.shop_locomotion_snapshot()
  var input_owner:Variant=optional_property(game,"courier_input")
  if input_owner is Object and is_instance_valid(input_owner) and input_owner.has_method("debug_snapshot"):item.input=input_owner.debug_snapshot()
  var motion:Variant=optional_property(game.world,"_clerk_motion")
  if motion is Object and is_instance_valid(motion) and motion.has_method("debug_snapshot"):item.motion=motion.debug_snapshot()
  if game.sim!=null:
   item.sim_status=game.sim.status;item.sim_elapsed=game.sim.elapsed
   item.pilot_input=game._pilot_input_state()
  var focus:Control=get_viewport().gui_get_focus_owner()
  item.focus_control=str(focus.get_path()) if is_instance_valid(focus) else ""
  item=json_value(item);samples.append(item)
  var status:Dictionary=item.duplicate(true);status.buttons=[];buttons(game,status.buttons);status=json_value(status)
  var file=FileAccess.open(latest+".tmp",FileAccess.WRITE)
  if file!=null:
   file.store_string(JSON.stringify(status,"",true,true));file.close()
   DirAccess.rename_absolute(latest+".tmp",latest)
 func _exit_tree() -> void:
  if output.is_empty():return
  var file=FileAccess.open(output,FileAccess.WRITE)
  if file==null:push_error("QA single-movement observer could not write output");return
  file.store_string(JSON.stringify({"method":"Read-only 30 Hz native production observation; no synthesized gameplay input","max_hz":30,"max_samples":MAX_SAMPLES,"capped":capped,"samples":samples},"",true,true));file.close()
  print("QA_SINGLE_MOVEMENT_OBSERVER_SAVED ",JSON.stringify({"output":output,"samples":samples.size(),"capped":capped}))
func _initialize() -> void:
 super._initialize()
 var observer=SingleMovementObserver.new();observer.name="QASingleMovementReadOnlyObserver"
 root.add_child.call_deferred(observer)
