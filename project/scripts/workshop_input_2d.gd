extends RefCounted
## Thin owner-facing adapter. The model mutates only when an edit proposal passes
## release validation. Camera gestures touch camera fields only, never render().
const Controls=preload("res://scripts/workshop_controls.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
var host
var camera=Controls.new()
var _press_snapshot:Array=[]
var _press_mode:String=""
var _press_type:String=""
var _view_assembly_mode:String=""
var _press_part:Dictionary={}
var _grab_offset:Vector2=Vector2.ZERO
var _preview_cell:Vector2i=Vector2i.ZERO
var _preview_cell_set:bool=false
var _preview_valid:bool=false

func bind(owner_node) -> void:host=owner_node

func cancel() -> void:
 camera.cancel();_press_snapshot.clear();_press_mode="";_press_type="";controller_cancel()
 _clear_drag_preview()

func enabled() -> bool:
 if is_instance_valid(host) and host.has_method("_review_phone_is_open") and host._review_phone_is_open():return false
 return is_instance_valid(host) and host.page=="workshop" and not host.closing and not host._dialogue_is_open() and not (host.has_method("_loading_scene_active") and host._loading_scene_active()) and is_instance_valid(host.hud) and not host.hud.is_blocking_modal()

func _allowed_screen(screen:Vector2) -> bool:
 return enabled() and host.view_container.display_rect.has_point(screen) and not host.hud.blocks_workshop_pointer(screen)

func _sync() -> bool:
 var screen_rect:Rect2=host.hud.workshop_scene_rect()
 var stage=host.view_container
 var usable:Rect2=Rect2(stage.screen_to_pixel(screen_rect.position),screen_rect.size/float(stage.pixel_scale))
 var was_configured:bool=camera.configured
 var support_bounds:Rect2=host.world.workshop_support_fit_rect() if host.world.has_method("workshop_support_fit_rect") else Rect2()
 if not camera.configure(Profile.bounds(int(host.economy.workshop_tier)),host.world.assembly_origin,Vector2(host.view.size),usable,host.active_design(),support_bounds):return false
 if was_configured and _view_assembly_mode!=host.assembly_mode:controller_cancel();camera.fit(host.active_design(),true)
 _view_assembly_mode=host.assembly_mode
 return true

func _apply_camera() -> void:host.world.apply_workshop_camera(camera.center,camera.zoom)

func after_render() -> void:
 if not enabled():cancel();return
 # Edits outside this transaction invalidate its preview immediately.
 if camera.gesture in ["move","place"] and (_press_snapshot!=host.active_design() or _press_mode!=host.assembly_mode or _press_type!=host.chosen_type):cancel()
 if _sync():_apply_camera()
 if camera.gesture.is_empty():_clear_drag_preview()

func fit() -> void:
 if not enabled() or not _sync():return
 cancel();camera.fit(host.active_design(),true);_apply_camera()

func tick() -> void:
 if not camera.gesture.is_empty() and not enabled():cancel()

func observe(event:InputEvent) -> void:
 # _input runs before GUI capture. It can cancel, never place/move. Explicit HUD
 # geometry avoids Godot's mouse-capture target masking the control under release.
 if camera.gesture.is_empty():return
 if not enabled():cancel();return
 if event is InputEventMouse:
  if not _allowed_screen(event.position):cancel();return
  if event is InputEventMouseMotion:
   var mask:int=MOUSE_BUTTON_MASK_MIDDLE if camera.gesture=="pan" else MOUSE_BUTTON_MASK_LEFT
   if not bool(event.button_mask&mask):cancel()
  elif event is InputEventMouseButton:
   if event.pressed and event.button_index!=camera.gesture_button:cancel()
   elif not event.pressed and event.button_index==camera.gesture_button:
    # A valid display release consumes this epoch synchronously. If a GUI control
    # steals it, clear the orphaned gesture at end of the same event cycle.
    _finish_unhandled_release.call_deferred(camera.epoch)

func _finish_unhandled_release(token:int) -> void:
 if camera.epoch==token:cancel()

func handle(event:InputEvent) -> void:
 if not enabled():cancel();return
 if not event is InputEventMouse:return
 var stage=host.view_container
 # GUI positions are display-local, whereas PixelStage expects the art-frame
 # coordinate system. Convert with its existing inverse, not a window ratio.
 var screen:Vector2=stage.display.position+event.position
 if not _allowed_screen(screen):cancel();return
 var pixel:Vector2=stage.screen_to_pixel(screen)
 if event is InputEventMouseMotion:
  # Geometry is configured on render / button boundaries. Motion must never
  # rebuild the design fit, the HUD, joints, or any simulation state.
  if not camera.configured:return
  if camera.gesture=="pan":
   if camera.pan_to(pixel,bool(event.button_mask&MOUSE_BUTTON_MASK_MIDDLE)):_apply_camera()
  elif camera.gesture in ["move","place"]:
   camera.update_edit(pixel,bool(event.button_mask&MOUSE_BUTTON_MASK_LEFT))
   if camera.gesture.is_empty():cancel()
   else:_update_drag_preview(pixel)
  return
 if not event is InputEventMouseButton:return
 if not _sync():return
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if event.pressed:
   cancel()
   if camera.zoom_at(pixel,(1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0)*maxf(.01,event.factor)):_apply_camera()
  return
 if event.button_index==MOUSE_BUTTON_MIDDLE:
  if event.pressed:cancel();camera.begin_pan(pixel)
  else:cancel()
  return
 var cell:Vector2i=host.world.cell_at(pixel) # The live rendered canvas is authoritative.
 if event.button_index==MOUSE_BUTTON_RIGHT:
  if event.pressed:
   cancel()
   var id:int=_part_at(cell)
   if id>=0:host.selected_id=id;host.remove_part()
  return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 if event.pressed:
  cancel()
  var id:int=_part_at(cell)
  if id<0 and not camera.grid_bounds.has_point(cell):return
  # A selection change refreshes the inspector and guide, not the unchanged
  # installed structure. cancel() still clears earlier mouse/controller edits.
  # Older hosts keep their full-render contract; Main owns the narrow refresh.
  if id>=0 and host.selected_id!=id:
   host.selected_id=id
   if host.has_method("refresh_workshop_selection"):host.refresh_workshop_selection()
   else:host.render()
   if not enabled() or not _sync():return
  _press_snapshot=host.active_design().duplicate(true);_press_mode=host.assembly_mode;_press_type=host.chosen_type
  camera.begin_edit(pixel,cell,id,0)
  if id>=0:
   for part in host.active_design():
    if int(part.id)==id:_press_part=part.duplicate(true);break
   _grab_offset=_world_at(pixel)-(host.world.assembly_origin+Vector2(cell)*Controls.CELL)
 else:
  var same:bool=_press_mode==host.assembly_mode and _press_type==host.chosen_type and _press_snapshot==host.active_design()
  if camera.gesture=="move" and not _press_part.is_empty():cell=_drag_cell(pixel)
  var proposal:Dictionary=camera.release_edit(pixel,cell,host.active_design(),0,same)
  _press_snapshot.clear();_press_mode="";_press_type="";_clear_drag_preview()
  if not proposal.is_empty():_commit(proposal)

func _world_at(pixel:Vector2) -> Vector2:
 # The production canvas inverse includes the live, pixel-rounded camera.
 if host.world.has_method("workshop_point_at"):return host.world.workshop_point_at(pixel)
 return camera.pixel_to_world(pixel)

func _drag_cell(pixel:Vector2) -> Vector2i:
 return Vector2i(((_world_at(pixel)-_grab_offset-host.world.assembly_origin)/Controls.CELL).round())

func _update_drag_preview(pixel:Vector2) -> void:
 if camera.gesture!="move" or not camera.dragged or _press_part.is_empty():return
 if _press_mode!=host.assembly_mode or _press_type!=host.chosen_type:cancel();return
 var pointer_center:Vector2=_world_at(pixel)-_grab_offset
 var cell:Vector2i=Vector2i(((pointer_center-host.world.assembly_origin)/Controls.CELL).round())
 # Occupancy is checked when the footprint changes, then revalidated on release.
 if not _preview_cell_set or cell!=_preview_cell:
  _preview_cell=cell;_preview_cell_set=true
  _preview_valid=Controls.valid_move(host.active_design(),camera.press_id,camera.press_cell,cell,camera.grid_bounds)
 if host.world.has_method("show_workshop_drag"):
  host.world.show_workshop_drag(_press_part,pointer_center,host.world.assembly_origin+Vector2(cell)*Controls.CELL,_preview_valid)

func _clear_drag_preview() -> void:
 _press_part.clear();_grab_offset=Vector2.ZERO;_preview_cell_set=false;_preview_valid=false
 if is_instance_valid(host) and is_instance_valid(host.world) and host.world.has_method("clear_workshop_drag"):host.world.clear_workshop_drag()

func _part_at(cell:Vector2i) -> int:
 for part in host.active_design():
  if Vector2i(int(part.x),int(part.y))==cell:return int(part.id)
 return -1

func _commit(proposal:Dictionary) -> void:
 if not enabled():return
 var cell:Vector2i=proposal.cell
 if str(proposal.kind)=="move":
  if not Controls.valid_move(host.active_design(),int(proposal.id),proposal.from,cell,camera.grid_bounds):return
  for part in host.active_design():
   if int(part.id)==int(proposal.id):
    host._remember_assembly();part.x=cell.x;part.y=cell.y;host.selected_id=int(part.id)
    host.render();host.save_game();host.world.committed_edit("move",part);host._sound("module_snap");return
 else:
  if not camera.grid_bounds.has_point(cell) or Controls.occupied(host.active_design(),cell):return
  if not host.WorkshopParts.compatible(host.chosen_type,host.assembly_mode=="launcher",host.workshop_control_version()):
   host.notify(host.WorkshopParts.placement_error(host.chosen_type,host.assembly_mode=="launcher",host.workshop_control_version()));return
  if int(host.economy.inventory.get(host.chosen_type,0))<=host._installed_count(host.chosen_type):host.notify("手头没有多余的这件零件，收工后可向供应商采购。");return
  var part:Dictionary=host.part(host.next_id,host.chosen_type,cell.x,cell.y)
  if part.is_empty():return
  host._remember_assembly()
  host.next_id+=1;host.active_design().append(part);host.selected_id=int(part.id)
  host.render();host.save_game();host.world.committed_edit("place",part);host._sound("module_snap")

# Controller grid mode is explicit. Navigation in HUD never reaches these edits.
var controller_cell:Vector2i=Vector2i.ZERO
var _controller_move:Dictionary={}

func controller_begin() -> void:
 cancel();controller_cancel()
 if not enabled() or not _sync():return
 var chosen:Dictionary=host.selected_part()
 controller_cell=Vector2i(int(chosen.x),int(chosen.y)) if not chosen.is_empty() else Vector2i.ZERO
 if chosen.is_empty():controller_cell=controller_cell.clamp(camera.grid_bounds.position,camera.grid_bounds.end-Vector2i.ONE)

func controller_cancel() -> void:_controller_move.clear()
func controller_moving() -> bool:return not _controller_move.is_empty()

func controller_step(direction:Vector2i) -> void:
 if not enabled() or not _sync():controller_cancel();return
 controller_cell=(controller_cell+direction).clamp(camera.grid_bounds.position,camera.grid_bounds.end-Vector2i.ONE)
 # Follow the cursor only when it approaches the usable workbench edge.
 var pixel:Vector2=camera.world_to_pixel(camera.origin+Vector2(controller_cell)*Controls.CELL)
 var safe:Rect2=camera.usable.grow(-Controls.CELL*camera.pixels_per_world()*.6)
 var correction:Vector2=pixel-pixel.clamp(safe.position,safe.end)
 if not correction.is_zero_approx():camera.center=camera.clamp_center(camera.center+correction/camera.pixels_per_world());_apply_camera()

func controller_confirm() -> void:
 if not enabled() or not _sync():controller_cancel();return
 if not _controller_move.is_empty():
  var proposal:Dictionary=_controller_move.duplicate(true)
  if str(proposal.mode)!=host.assembly_mode or proposal.snapshot!=host.active_design():controller_cancel();return
  proposal.cell=controller_cell;controller_cancel();_commit(proposal);return
 var id:int=_part_at(controller_cell)
 if id>=0:host.selected_id=id;host.render()
 else:_commit({"kind":"place","cell":controller_cell})

func controller_pickup() -> void:
 if not enabled() or not _sync():return
 var id:int=_part_at(controller_cell)
 if id<0:return
 host.selected_id=id;host.render()
 _controller_move={"kind":"move","id":id,"from":controller_cell,"mode":host.assembly_mode,"snapshot":host.active_design().duplicate(true)}

func controller_pan(direction:Vector2) -> void:
 if not enabled() or not _sync() or direction.is_zero_approx():return
 camera.center=camera.clamp_center(camera.center+direction*620.0/maxf(camera.zoom,.25));_apply_camera()

func controller_cursor_rect() -> Rect2:
 if not enabled() or not camera.configured:return Rect2()
 var center:Vector2=camera.world_to_pixel(camera.origin+Vector2(controller_cell)*Controls.CELL)
 var extent:Vector2=Vector2.ONE*Controls.CELL*camera.pixels_per_world()
 var stage=host.view_container
 var rect:Rect2=Rect2(stage.pixel_to_screen(center-extent*.5),extent*float(stage.pixel_scale))
 return rect.intersection(host.hud.workshop_scene_rect()).intersection(stage.display_rect)

func controller_select_next() -> void:
 if not enabled() or not _sync() or host.active_design().is_empty():return
 controller_cancel()
 var parts:Array=host.active_design();var index:int=-1
 for n in parts.size():
  if int(parts[n].id)==host.selected_id:index=n;break
 var chosen:Dictionary=parts[posmod(index+1,parts.size())]
 host.selected_id=int(chosen.id);controller_cell=Vector2i(int(chosen.x),int(chosen.y));host.render()
 # Retained out-of-tier parts remain selectable for recovery, as with the mouse.
 var target:Vector2=camera.origin+Vector2(controller_cell)*Controls.CELL
 camera.center=camera.clamp_center(target-(camera.usable.get_center()-camera.extent*.5)/camera.pixels_per_world());_apply_camera()
