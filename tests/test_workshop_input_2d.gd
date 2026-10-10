extends SceneTree
## No rendered scene: fake host/viewport tests real event routing and mutation APIs.
const Adapter=preload("res://scripts/workshop_input_2d.gd")
const Controls=preload("res://scripts/workshop_controls.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
const Stage=preload("res://scripts/pixel_stage.gd")
var passed:int=0
var failed:int=0
class PartTypes:
 static func launcher_types() -> Array:return ["beam","battery"]
class FakeEconomy extends RefCounted:
 var workshop_tier:int=2
 var inventory:Dictionary={"battery":8,"beam":4}
class FakeView extends RefCounted:
 var size:Vector2i=Vector2i(1280,720)
class FakeHud extends RefCounted:
 var modal:bool=false
 var blocker:Rect2=Rect2()
 func is_blocking_modal() -> bool:return modal
 func blocks_workshop_pointer(screen:Vector2) -> bool:return blocker.has_point(screen)
 func workshop_scene_rect() -> Rect2:return Rect2(20,176,912,456)
class FakeWorld extends RefCounted:
 var assembly_origin:Vector2=Profile.assembly_origin(2)
 var controls=Controls.new()
 var updates:int=0
 var edits:Array=[]
 func _init() -> void:controls.configure(Profile.bounds(2),assembly_origin,Vector2(1280,720))
 func apply_workshop_camera(center:Vector2,zoom:float) -> void:
  updates+=1;controls.center=center;controls.zoom=zoom
 func cell_at(pixel:Vector2) -> Vector2i:return controls.cell_at(pixel)
 func committed_edit(kind:String,p:Dictionary) -> void:edits.append([kind,p.duplicate(true)])
class FakeHost extends RefCounted:
 const PartsDB=PartTypes
 var page:String="workshop"
 var closing:bool=false
 var dialogue_open:bool=false
 var assembly_mode:String="craft"
 var chosen_type:String="battery"
 var selected_id:int=-1
 var next_id:int=20
 var economy=FakeEconomy.new()
 var view=FakeView.new()
 var hud=FakeHud.new()
 var world=FakeWorld.new()
 var view_container=Stage.new()
 var adapter
 var design:Array=[{"id":5,"type":"battery","x":0,"y":0,"rot":2,"param":9,"input_a":6,"input_b":-1,"target":6},{"id":6,"type":"beam","x":1,"y":0,"rot":1,"param":3,"input_a":-1,"input_b":-1,"target":-1}]
 var undo:Array=[]
 var renders:int=0
 var saves:int=0
 var sounds:int=0
 var notices:Array=[]
 func _init() -> void:
  view_container.pixel_scale=1;view_container.display_rect=Rect2(0,40,1280,720)
  view_container.display=TextureRect.new();view_container.display.position=Vector2(0,40)
 func _dialogue_is_open() -> bool:return dialogue_open
 func active_design() -> Array:return design
 func render() -> void:renders+=1;adapter.after_render()
 func save_game() -> bool:saves+=1;return true
 func _remember_assembly() -> void:undo.append(design.duplicate(true))
 func _sound(_name:String) -> void:sounds+=1
 func notify(message:String) -> void:notices.append(message)
 func _installed_count(type:String) -> int:
  var n:int=0
  for p in design:
   if str(p.type)==type:n+=1
  return n
 func part(id:int,type:String,x:int,y:int) -> Dictionary:
  return {"id":id,"type":type,"x":x,"y":y,"rot":0,"param":0,"input_a":-1,"input_b":-1,"target":-1}
 func rotate_part() -> void:
  adapter.cancel()
  for p in design:
   if int(p.id)==selected_id:
    _remember_assembly();p.rot=(int(p.rot)+1)%4;render();save_game();return
 func remove_part() -> void:
  for p in design:
   if int(p.id)==selected_id:
    _remember_assembly();design.erase(p);render();save_game();return
 func dispose() -> void:
  view_container.display.free();view_container.free();adapter=null
func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)
func button(at:Vector2,which:int,pressed:bool) -> InputEventMouseButton:
 var event:=InputEventMouseButton.new();event.position=at;event.button_index=which;event.pressed=pressed;return event
func motion(at:Vector2,mask:int) -> InputEventMouseMotion:
 var event:=InputEventMouseMotion.new();event.position=at;event.button_mask=mask;return event
func pixel(host,cell:Vector2i) -> Vector2:return host.world.controls.world_to_pixel(host.world.assembly_origin+Vector2(cell)*72)
func _initialize() -> void:
 var h=FakeHost.new();var a=Adapter.new();h.adapter=a;a.bind(h);a.after_render()
 var empty:Vector2=pixel(h,Vector2i(0,-1));var before:Array=h.design.duplicate(true)
 a.handle(button(empty,MOUSE_BUTTON_LEFT,true))
 check(h.design==before and h.saves==0 and h.undo.is_empty(),"press does not install early")
 a.handle(button(empty,MOUSE_BUTTON_LEFT,false))
 check(h.design.size()==3 and h.saves==1 and h.undo.size()==1 and h.next_id==21,"same-cell release installs once")
 a.handle(button(empty,MOUSE_BUTTON_LEFT,false))
 check(h.design.size()==3 and h.saves==1 and h.undo.size()==1,"duplicate placement release changes nothing")
 var initial:Dictionary=h.design[0].duplicate(true);var inventory:Dictionary=h.economy.inventory.duplicate(true)
 var source:Vector2=pixel(h,Vector2i.ZERO);var dest:Vector2=pixel(h,Vector2i(0,-2))
 a.handle(button(source,MOUSE_BUTTON_LEFT,true));a.handle(motion(dest,MOUSE_BUTTON_MASK_LEFT))
 check(h.design[0]==initial and h.selected_id==5,"left drag selects but does not mutate model before release")
 a.handle(button(dest,MOUSE_BUTTON_LEFT,false));var moved:Dictionary=h.design[0].duplicate(true);moved.x=initial.x;moved.y=initial.y
 check(h.design[0].y==-2 and moved==initial and h.economy.inventory==inventory,"move preserves ID, rotation, parameter, circuit targets and inventory")
 check(h.undo.size()==2 and h.saves==2 and h.world.edits.back()[0]=="move","move is one undo snapshot, one save, one committed edit")
 before=h.design.duplicate(true);var saves:int=h.saves;var undos:int=h.undo.size()
 source=pixel(h,Vector2i(0,-2));dest=pixel(h,Vector2i(1,0))
 a.handle(button(source,MOUSE_BUTTON_LEFT,true));a.handle(motion(dest,MOUSE_BUTTON_MASK_LEFT));a.handle(button(dest,MOUSE_BUTTON_LEFT,false))
 check(h.design==before and h.saves==saves and h.undo.size()==undos,"occupied release has no model/save/undo mutation")
 # Cancellations go through global _input observation or the explicit lifecycle hook.
 for reason in ["HUD","outside","modal","focus","resize","navigation","lost_button","changed_model","wrong_button"]:
  source=pixel(h,Vector2i(0,-2));dest=pixel(h,Vector2i(2,-2))
  a.handle(button(source,MOUSE_BUTTON_LEFT,true));a.handle(motion(dest,MOUSE_BUTTON_MASK_LEFT))
  var global_dest:Vector2=dest+h.view_container.display.position
  match reason:
   "HUD":h.hud.blocker=Rect2(global_dest-Vector2.ONE*3,Vector2.ONE*6);a.observe(button(global_dest,MOUSE_BUTTON_LEFT,false));h.hud.blocker=Rect2()
   "outside":a.observe(button(Vector2(200,-10),MOUSE_BUTTON_LEFT,false))
   "modal":h.hud.modal=true;a.tick();h.hud.modal=false
   "focus","resize":a.cancel()
   "navigation":h.page="hub";a.tick();h.page="workshop"
   "lost_button":a.observe(motion(global_dest,0))
   "changed_model":h.design[1].param=99
   "wrong_button":a.observe(button(global_dest,MOUSE_BUTTON_MIDDLE,true))
  a.handle(button(dest,MOUSE_BUTTON_LEFT,false))
  if reason=="changed_model":h.design[1].param=before[1].param
  check(h.design==before and h.saves==saves and h.undo.size()==undos,"cancel "+reason+" cannot replay move")
 var camera_renders:int=h.renders;var camera_saves:int=h.saves;var updates:int=h.world.updates
 var at:Vector2=Vector2(640,360)
 a.handle(button(at,MOUSE_BUTTON_MIDDLE,true));a.handle(motion(at+Vector2(20,12),MOUSE_BUTTON_MASK_MIDDLE));a.handle(button(at+Vector2(20,12),MOUSE_BUTTON_MIDDLE,false))
 a.handle(button(at,MOUSE_BUTTON_WHEEL_UP,true));a.fit()
 check(h.world.updates>updates and h.renders==camera_renders and h.saves==camera_saves and h.design==before,"pan, zoom and F fit apply only camera, without render or persistence")
 var saved_center:Vector2=a.camera.center;var saved_zoom:float=a.camera.zoom
 h.page="hub";a.after_render();h.page="workshop";a.after_render()
 check(a.camera.center.is_equal_approx(saved_center) and is_equal_approx(a.camera.zoom,saved_zoom),"interim hub presentation cannot discard persistent workshop camera")
 empty=pixel(h,Vector2i(2,-2));a.handle(button(empty,MOUSE_BUTTON_LEFT,true));var token:int=a.camera.epoch
 a._finish_unhandled_release(token);a.handle(button(empty,MOUSE_BUTTON_LEFT,false))
 check(h.design==before and h.saves==saves,"stolen GUI release cleanup prevents delayed placement")
 a.handle(button(empty,MOUSE_BUTTON_LEFT,true));h.economy.inventory.battery=h._installed_count("battery");a.handle(button(empty,MOUSE_BUTTON_LEFT,false))
 check(h.design==before and h.saves==saves and not h.notices.is_empty(),"stock is rechecked at release")
 h.economy.inventory.battery=8
 a.handle(button(empty,MOUSE_BUTTON_LEFT,true));h.chosen_type="beam";a.handle(button(empty,MOUSE_BUTTON_LEFT,false))
 check(h.design==before and h.saves==saves,"catalog change during held click cancels placement")
 a.cancel();a.host=null;h.dispose()
 print("WORKSHOP_INPUT_ADAPTER passed=",passed," failed=",failed)
 quit(1 if failed else 0)
