extends SceneTree
## Synthetic adapter / presentation verification. Prints input CPU timing, not FPS.
## Run together with existing workshop controls, input, recovery and controller suites.
const Adapter=preload("res://scripts/workshop_input_2d.gd")
const Controls=preload("res://scripts/workshop_controls.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
const Stage=preload("res://scripts/pixel_stage.gd")
const Preview=preload("res://scripts/workshop_drag_preview_2d.gd")
var passed:int=0
var failed:int=0
var max_pointer_screen_error:float=0.0
class PartTypes:
 static func launcher_types() -> Array:return ["beam","battery"]
class FakeEconomy extends RefCounted:
 var workshop_tier:int=2
 var credits:int=260
 var inventory:Dictionary={"battery":8,"beam":4}
class FakeView extends RefCounted:
 var size:Vector2i=Vector2i(960,540)
class FakeHud extends RefCounted:
 var modal:bool=false
 var blocker:Rect2=Rect2()
 var usable:Rect2=Rect2(30,264,1368,576)
 func is_blocking_modal() -> bool:return modal
 func blocks_workshop_pointer(screen:Vector2) -> bool:return blocker.has_point(screen)
 func workshop_scene_rect() -> Rect2:return usable
class FakeWorld extends RefCounted:
 var assembly_origin:Vector2=Profile.assembly_origin(2)
 var controls=Controls.new()
 var preview:Dictionary={"visible":false}
 var previews:int=0
 var clears:int=0
 var updates:int=0
 var edits:Array=[]
 func _init() -> void:controls.configure(Profile.bounds(2),assembly_origin,Vector2(960,540))
 func apply_workshop_camera(center:Vector2,zoom:float) -> void:
  updates+=1;controls.center=center;controls.zoom=zoom
 func workshop_point_at(pixel:Vector2) -> Vector2:return controls.pixel_to_world(pixel)
 func cell_at(pixel:Vector2) -> Vector2i:return controls.cell_at(pixel)
 func committed_edit(kind:String,p:Dictionary) -> void:edits.append([kind,p.duplicate(true)])
 func show_workshop_drag(part:Dictionary,pointer_center:Vector2,snapped_center:Vector2,valid_target:bool) -> void:
  previews+=1;preview={"visible":true,"id":int(part.id),"pointer":pointer_center,"snap":snapped_center,"valid":valid_target}
 func clear_workshop_drag() -> void:clears+=1;preview={"visible":false}
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
  view_container.pixel_scale=2;view_container.display_rect=Rect2(0,0,1920,1080)
  view_container.display=TextureRect.new();view_container.display.position=Vector2.ZERO
 func _dialogue_is_open() -> bool:return dialogue_open
 func active_design() -> Array:return design
 func selected_part() -> Dictionary:
  for p in design:
   if int(p.id)==selected_id:return p
  return {}
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
 func part(id:int,type:String,x:int,y:int) -> Dictionary:return {"id":id,"type":type,"x":x,"y":y,"rot":0,"param":0,"input_a":-1,"input_b":-1,"target":-1}
 func remove_part() -> void:pass
 func dispose() -> void:
  view_container.display.free();view_container.free();adapter=null

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func button(at:Vector2,pressed:bool,which:int=MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
 var event:=InputEventMouseButton.new();event.position=at;event.button_index=which;event.pressed=pressed;return event
func motion(at:Vector2,mask:int=MOUSE_BUTTON_MASK_LEFT) -> InputEventMouseMotion:
 var event:=InputEventMouseMotion.new();event.position=at;event.button_mask=mask;return event
func local_pixel(h,cell:Vector2i,offset:Vector2=Vector2.ZERO) -> Vector2:
 return h.world.controls.world_to_pixel(h.world.assembly_origin+Vector2(cell)*72.0+offset)*float(h.view_container.pixel_scale)
func create_host():
 var h=FakeHost.new();h.adapter=Adapter.new();h.adapter.bind(h);h.adapter.after_render();return h
func dispose(h) -> void:h.adapter.cancel();h.adapter.host=null;h.dispose()
func invariant(h,before:Array,stock:Dictionary,credits:int,saves:int,undos:int) -> bool:
 return h.design==before and h.economy.inventory==stock and h.economy.credits==credits and h.saves==saves and h.undo.size()==undos

func run() -> void:
 adapter_gestures();coordinate_matrix();presenter_state()
 print("WORKSHOP_DRAG_V2 passed=",passed," failed=",failed," max_pointer_screen_error_px=",max_pointer_screen_error)
 quit(1 if failed else 0)

func adapter_gestures() -> void:
 var h=create_host();var a=h.adapter
 var before:Array=h.design.duplicate(true);var stock:Dictionary=h.economy.inventory.duplicate(true);var credits:int=h.economy.credits
 var offset:Vector2=Vector2(17,-11)
 var source:Vector2=local_pixel(h,Vector2i.ZERO,offset)
 a.handle(button(source,true))
 var renders:int=h.renders;var updates:int=h.world.updates
 check(not h.world.preview.visible,"selection does not draw a displaced ghost before dragging")
 var at:Vector2=local_pixel(h,Vector2i(0,-1),offset+Vector2(3,2))
 a.handle(motion(at))
 var expected:Vector2=h.world.workshop_point_at(at/2.0)-offset
 check(h.world.preview.visible and h.world.preview.pointer.distance_to(expected)<.001,"first drag event follows current pointer exactly and preserves grab offset")
 var snap:Vector2=h.world.preview.snap
 a.handle(motion(at+Vector2(1.0,0)))
 check(h.world.preview.pointer.distance_to(expected)>0.0 and h.world.preview.snap==snap,"sub-cell motion moves the ghost while footprint stays snapped")
 check(h.world.preview.valid,"unoccupied in-bounds target is valid")
 check(invariant(h,before,stock,credits,0,0) and h.renders==renders and h.world.updates==updates,"drag motion leaves design, stock, money, saves, undo, camera and full render untouched")
 # Warm the same-cell path, then record synthetic CPU time without frame-rate claims.
 var bench:=motion(at);var samples:int=2000
 var started:int=Time.get_ticks_usec();var maximum:int=0
 for index in samples:
  bench.position=at+Vector2(float(index%8)*.125,0)
  var sample_started:int=Time.get_ticks_usec();a.handle(bench)
  maximum=maxi(maximum,Time.get_ticks_usec()-sample_started)
 var total:int=Time.get_ticks_usec()-started
 print("DRAG_INPUT_CPU_SYNTHETIC events=",samples," total_us=",total," mean_us=",float(total)/samples," max_us=",maximum," renders_during_motion=",h.renders-renders," camera_updates_during_motion=",h.world.updates-updates)
 a.handle(button(at,false))
 check(h.design[0].x==0 and h.design[0].y==-1 and h.undo.size()==1 and h.saves==1 and h.sounds==1,"release commits the shown snap cell exactly once")
 check(not h.world.preview.visible and h.economy.inventory==stock and h.economy.credits==credits,"successful release clears ghost with no charge or inventory mutation")
 var restored:Dictionary=h.design[0].duplicate(true);restored.x=before[0].x;restored.y=before[0].y
 check(restored==before[0],"rotation, parameters, part ID and wiring remain unchanged")
 a.handle(button(at,false))
 check(h.undo.size()==1 and h.saves==1,"duplicate release cannot create a second edit")
 h.design=h.undo.pop_back();a.cancel();h.render()
 check(h.design==before,"one undo snapshot restores the exact original design")
 var saves:int=h.saves;var undos:int=h.undo.size()
 for reason in ["occupied","outside_grid","HUD","outside_display","lost_button","modal","navigation","focus","resize","wheel","stolen_release","changed_model"]:
  source=local_pixel(h,Vector2i.ZERO,offset);at=local_pixel(h,Vector2i(0,-1),offset)
  a.handle(button(source,true));a.handle(motion(at))
  match reason:
   "occupied":at=local_pixel(h,Vector2i(1,0),offset);a.handle(motion(at));check(not h.world.preview.valid,"occupied footprint is invalid")
   "outside_grid":
    at=local_pixel(h,Vector2i(0,3),offset);a.handle(motion(at));check(not h.world.preview.get("valid",false),"locked-row footprint cannot advertise a valid drop")
   "HUD":
    h.hud.blocker=Rect2(at-Vector2.ONE*3,Vector2.ONE*6);a.observe(button(at,false));h.hud.blocker=Rect2()
   "outside_display":a.observe(button(Vector2(-10,500),false))
   "lost_button":a.observe(motion(at,0))
   "modal":h.hud.modal=true;a.tick();h.hud.modal=false
   "navigation":h.page="hub";a.tick();h.page="workshop"
   "focus","resize":a.cancel()
   "wheel":a.handle(button(at,true,MOUSE_BUTTON_WHEEL_UP))
   "stolen_release":a._finish_unhandled_release(a.camera.epoch)
   "changed_model":h.design[1].param=99
  a.handle(button(at,false))
  if reason=="changed_model":h.design[1].param=before[1].param
  check(invariant(h,before,stock,credits,saves,undos) and not h.world.preview.visible,"cancel/invalid "+reason+" restores preview and cannot commit or charge")
 a.controller_begin();a.controller_cell=Vector2i.ZERO;a.controller_pickup();a.controller_step(Vector2i(0,-1));a.controller_confirm()
 check(h.design[0].y==-1 and h.undo.size()==undos+1 and h.saves==saves+1,"keyboard/gamepad pickup, step and confirm still commit once")
 dispose(h)

func coordinate_matrix() -> void:
 for extent in [Vector2i(640,360),Vector2i(960,540),Vector2i(1280,720)]:
  var h=create_host();h.view.size=extent;h.world.controls.extent=Vector2(extent)
  var scale_value:int=maxi(1,mini(1920/extent.x,1080/extent.y))
  var display_extent:Vector2=Vector2(extent*scale_value)
  var origin:Vector2=((Vector2(1920,1080)-display_extent)*.5).floor()
  h.view_container.pixel_scale=scale_value;h.view_container.display_rect=Rect2(origin,display_extent);h.view_container.display.position=origin
  h.hud.usable=h.view_container.display_rect.grow(-40)
  h.adapter.cancel();h.adapter.after_render()
  var grab:Vector2=Vector2(-19,13);var source:Vector2=local_pixel(h,Vector2i.ZERO,grab)
  h.adapter.handle(button(source,true))
  for n in 40:
   var delta:Vector2=Vector2(31.5+float(n)*.17,-55.25+float(n)*.08)
   var target:Vector2=source+delta
   h.adapter.handle(motion(target))
   check(h.world.preview.visible,"preview appears at supported 1080 canvas density")
   if not h.world.preview.visible:continue
   var ghost_pixel:Vector2=h.world.controls.world_to_pixel(h.world.preview.pointer+grab)
   var ghost_screen:Vector2=h.view_container.pixel_to_screen(ghost_pixel)
   var pointer_screen:Vector2=origin+target
   var error:float=ghost_screen.distance_to(pointer_screen)
   max_pointer_screen_error=maxf(max_pointer_screen_error,error)
   check(error<.001,"continuous ghost roundtrip matches pointer with letterboxing and integer scale")
  h.adapter.cancel();check(not h.world.preview.visible,"coordinate-space cancellation clears preview")
  dispose(h)

func presenter_state() -> void:
 var scene:=Node2D.new();root.add_child(scene)
 var source:=Sprite2D.new();source.self_modulate=Color(.8,.7,.6,.9);scene.add_child(source)
 var image:=Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
 var texture:=ImageTexture.create_from_image(image)
 var preview:=Preview.new();scene.add_child(preview)
 preview.begin(5,source,texture,2)
 var original:Color=Color(.8,.7,.6,.9)
 check(is_equal_approx(source.self_modulate.a,original.a*.22),"pickup dims only the original sprite's presentation")
 preview.present(Vector2(100.125,87.875),Vector2(72,72),true)
 var first:Dictionary=preview.debug_snapshot()
 preview.present(Vector2(100.375,88.125),Vector2(72,72),true)
 var second:Dictionary=preview.debug_snapshot()
 check(second.ghost_center==Vector2(100.375,88.125) and first.target_center==second.target_center,"presenter has no grid quantization or delayed lerp in ghost position")
 check(second.node_count==1 and second.footprint_redraws==first.footprint_redraws,"same-cell motion reuses the ghost and footprint draw commands")
 preview.present(Vector2(111.5,88.125),Vector2(144,72),false)
 check(not preview.debug_snapshot().valid,"invalid target is rendered separately from continuous ghost")
 preview.clear()
 check(not preview.visible and source.self_modulate==original,"cancel restores exact original sprite modulation")
 preview.begin(5,source,texture,2);preview.present(Vector2(100,80),Vector2(72,72),true);preview.free()
 check(source.self_modulate==original,"preview teardown restores the source without changing its position")
 scene.free()
