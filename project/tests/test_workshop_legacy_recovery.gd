extends SceneTree
## Tiny, focused recovery check. No assets, production imports, or render loop.
const Controls=preload("res://scripts/workshop_controls.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
const Adapter=preload("res://scripts/workshop_input_2d.gd")
const Harness=preload("res://tests/test_workshop_input_2d.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)
func click(at:Vector2,which:int,pressed:bool) -> InputEventMouseButton:
 var event:=InputEventMouseButton.new();event.position=at;event.button_index=which;event.pressed=pressed;return event
func move(at:Vector2) -> InputEventMouseMotion:
 var event:=InputEventMouseMotion.new();event.position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT;return event
func pixel(h,cell:Vector2i) -> Vector2:return h.world.controls.world_to_pixel(h.world.assembly_origin+Vector2(cell)*72)
func _initialize() -> void:
 var h=Harness.FakeHost.new();var a=Adapter.new();h.adapter=a;a.bind(h)
 h.economy.workshop_tier=0;h.world.assembly_origin=Profile.assembly_origin(0)
 h.world.controls.configure(Profile.bounds(0),h.world.assembly_origin,Vector2(1280,720))
 h.design[0].x=8;h.design[0].y=-5;h.design[1].x=0;h.design[1].y=0
 h.design.append(h.part(7,"beam",0,-30))
 var original:Array=h.design.duplicate(true)
 a.after_render()
 check(a.camera.content.encloses(a.camera.design_rect(h.design)) and h.design==original,"initial geometry includes retained design without mutating it")
 check(a.camera.zoom<Controls.MIN_ZOOM and a.camera.zoom>=Controls.MIN_SAFE_ZOOM,"large legacy extent widens recovery zoom without zero or infinite scale")
 var visible:bool=true
 for p in h.design:visible=visible and a.camera.usable.has_point(pixel(h,Vector2i(int(p.x),int(p.y))))
 check(visible,"all retained outside parts are visible on first setup")
 var source:Vector2=pixel(h,Vector2i(8,-5))
 a.handle(click(source,MOUSE_BUTTON_LEFT,true));a.handle(click(source,MOUSE_BUTTON_LEFT,false))
 check(h.selected_id==5 and h.design==original and h.saves==0,"outside part can be selected without a model edit")
 h.rotate_part()
 check(h.design[0].rot==3 and h.saves==1 and h.undo.size()==1,"existing rotation path can operate on selected retained part")
 var before:Array=h.design.duplicate(true);var saves:int=h.saves;var undos:int=h.undo.size()
 for target in [Vector2i(9,-5),Vector2i(0,0)]:
  source=pixel(h,Vector2i(8,-5));var destination:Vector2=pixel(h,target)
  a.handle(click(source,MOUSE_BUTTON_LEFT,true));a.handle(move(destination));a.handle(click(destination,MOUSE_BUTTON_LEFT,false))
  check(h.design==before and h.saves==saves and h.undo.size()==undos,"outside source cannot move into locked or occupied target "+str(target))
 var empty_locked:Vector2=pixel(h,Vector2i(6,-3))
 a.handle(click(empty_locked,MOUSE_BUTTON_LEFT,true));a.handle(click(empty_locked,MOUSE_BUTTON_LEFT,false))
 check(h.design==before and h.saves==saves and a.camera.gesture.is_empty(),"empty locked cell cannot arm or place a module")
 source=pixel(h,Vector2i(8,-5));var inward:Vector2=pixel(h,Vector2i(2,-1))
 a.handle(click(source,MOUSE_BUTTON_LEFT,true));a.handle(move(inward));a.handle(click(inward,MOUSE_BUTTON_LEFT,false))
 var moved:Dictionary=h.design[0].duplicate(true);moved.x=before[0].x;moved.y=before[0].y
 check(h.design[0].x==2 and h.design[0].y==-1 and moved==before[0],"retained source moves inward preserving ID/rotation/parameters/wiring")
 check(h.saves==saves+1 and h.undo.size()==undos+1,"inward move commits exactly once")
 a.handle(click(inward,MOUSE_BUTTON_LEFT,false))
 check(h.saves==saves+1 and h.undo.size()==undos+1,"duplicate inward release cannot replay")
 var retained:Vector2=pixel(h,Vector2i(0,-30));a.handle(click(retained,MOUSE_BUTTON_RIGHT,true))
 check(h.design.size()==2 and h.design.all(func(p):return int(p.id)!=7),"right-click removal reaches an outside retained part")
 # The remaining view can be fitted again without retaining a stale far boundary.
 a.fit()
 check(a.camera.content==a.camera.grid_rect() and a.camera.zoom>=Controls.MIN_ZOOM,"explicit fit updates current extents after recovery")
 h.design.append(h.part(8,"beam",20,-40));h.assembly_mode="launcher";h.render()
 check(a.camera.usable.has_point(pixel(h,Vector2i(20,-40))),"first view after assembly-mode change fits that design too")
 var c=Controls.new();c.configure(Profile.bounds(0),Profile.assembly_origin(0),Vector2(1280,720),Rect2(),original)
 c.set_view(Vector2(1e20,-1e20),c.zoom)
 check(c.center==c.clamp_center(c.center) and c.center.is_finite() and c.center.length()<100000,"legacy content still has finite bounded panning")
 var clean:Rect2=c.design_rect(original)
 var bad:Array=original.duplicate(true);bad.append({"x":NAN,"y":0});bad.append({"x":INF,"y":0});bad.append({"x":1e39,"y":-1e39});bad.append({"x":"bad","y":0})
 check(c.design_rect(bad)==clean,"nonfinite, overflowing and nonnumeric extents are rejected")
 c.fit(bad,true)
 check(c.center.is_finite() and is_finite(c.zoom) and c.zoom>0 and Controls.finite_rect(c.content),"malformed extra coordinates cannot poison fit or camera")
 var locked:Vector2i=Vector2i(8,-5);var locked_pixel:Vector2=c.world_to_pixel(c.origin+Vector2(locked)*72)
 check(not c.begin_edit(locked_pixel,locked,-1,0),"pure helper rejects empty locked source")
 check(c.begin_edit(locked_pixel,locked,5,0),"pure helper permits identity-bearing outside source")
 c.cancel()
 a.cancel();a.host=null;h.dispose()
 print("WORKSHOP_LEGACY_RECOVERY passed=",passed," failed=",failed)
 quit(1 if failed else 0)
