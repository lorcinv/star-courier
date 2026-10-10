extends SceneTree
## Pure math: no textures, no render loop, no production imports or save files.
const Controls=preload("res://scripts/workshop_controls.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
const Stage=preload("res://scripts/pixel_stage.gd")
var passed:int=0
var failed:int=0
var max_inverse_world:float=0
var max_inverse_screen:float=0
var max_camera_snap_pixel:float=0
var max_anchor_pixel:float=0
var max_anchor_screen:float=0
var max_roundtrip_world:float=0
func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)
func _initialize() -> void:
 mapping();camera_math();transactions()
 print("MEASURED max_inverse_world=%.9f max_inverse_screen_px=%.9f max_inverse_cell=%.12f max_snap_viewport_px=%.9f max_zoom_anchor_viewport_px=%.9f max_screen_roundtrip_world=%.9f max_zoom_anchor_screen_px=%.9f"%[max_inverse_world,max_inverse_screen,max_inverse_world/72.0,max_camera_snap_pixel,max_anchor_pixel,max_roundtrip_world,max_anchor_screen])
 print("WORKSHOP_CONTROLS_MATH passed=",passed," failed=",failed)
 quit(1 if failed else 0)
func mapping() -> void:
 var stage=Stage.new()
 for window in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  for density in ["auto","balanced","low"]:
   var canvas:Vector2i=Stage.choose_canvas(window,density)
   stage.pixel_scale=maxi(1,mini(window.x/canvas.x,window.y/canvas.y))
   stage.display_rect=Rect2(((Vector2(window)-Vector2(canvas*stage.pixel_scale))*.5).floor(),Vector2(canvas*stage.pixel_scale))
   for tier in 3:
    var c=Controls.new();var extent:Vector2=Vector2(canvas);var factor:float=extent.x/1280.0
    check(c.configure(Profile.bounds(tier),Profile.assembly_origin(tier),extent,Rect2(Vector2(20,176)*factor,Vector2(912,296)*factor)),"valid geometry")
    c.fit([],true)
    var footprint:Rect2=c.grid_rect()
    check(c.usable.has_point(c.world_to_pixel(footprint.position)) and c.usable.has_point(c.world_to_pixel(footprint.end)),"whole cell footprint fits usable frame tier %d %s %s"%[tier,window,density])
    var bounds:Rect2i=Profile.bounds(tier)
    for y in range(bounds.position.y,bounds.end.y):
     for x in range(bounds.position.x,bounds.end.x):
      var cell:Vector2i=Vector2i(x,y)
      var pixel:Vector2=c.world_to_pixel(c.origin+Vector2(cell)*72.0)
      var screen:Vector2=stage.pixel_to_screen(pixel)
      max_roundtrip_world=maxf(max_roundtrip_world,c.pixel_to_world(stage.screen_to_pixel(screen)).distance_to(c.origin+Vector2(cell)*72.0))
      check(c.cell_at(stage.screen_to_pixel(screen))==cell,"every tier cell round trips through real PixelStage methods")
      var s:float=c.pixels_per_world()
      var matrix:Transform2D=Transform2D(Vector2(s,0),Vector2(0,s),extent*.5-c.rendered_center()*s)
      var inverse_error:float=(matrix.affine_inverse()*pixel).distance_to(c.pixel_to_world(pixel))
      max_inverse_world=maxf(max_inverse_world,inverse_error);max_inverse_screen=maxf(max_inverse_screen,inverse_error*c.pixels_per_world()*stage.pixel_scale)
      check(inverse_error<.001,"pure inverse agrees with rendered camera canvas transform")
    for cell in [bounds.position-Vector2i(1,0),bounds.position-Vector2i(0,1),bounds.end,bounds.end-Vector2i(0,1)]:
     check(not bounds.has_point(cell),"exclusive tier bounds do not accept outside cells")
    var zoom_before:Vector2=c.pixel_to_world(extent*.5)
    c.zoom_at(extent*.5,3)
    var anchor_delta:Vector2=((zoom_before-c.pixel_to_world(extent*.5))*c.pixels_per_world()).abs()
    max_anchor_pixel=maxf(max_anchor_pixel,maxf(anchor_delta.x,anchor_delta.y));max_anchor_screen=maxf(max_anchor_screen,maxf(anchor_delta.x,anchor_delta.y)*stage.pixel_scale)
    check(maxf(anchor_delta.x,anchor_delta.y)<.501,"cursor-preserving zoom at every canvas density")
    var anchor:Vector2=c.world_to_pixel(c.origin)
    if c.contains_pixel(anchor):check(c.cell_at(stage.screen_to_pixel(stage.pixel_to_screen(anchor)))==Vector2i.ZERO,"mapping after zoom")
    c.begin_pan(extent*.5);c.pan_to(extent*.5+Vector2(34,-27)*factor);c.cancel()
    anchor=c.world_to_pixel(c.origin)
    check(c.cell_at(stage.screen_to_pixel(stage.pixel_to_screen(anchor)))==Vector2i.ZERO,"mapping after pan")
    var rendered:Vector2=c.rendered_center()*c.pixels_per_world()
    max_camera_snap_pixel=maxf(max_camera_snap_pixel,rendered.distance_to(rendered.round()))
    check(rendered.distance_to(rendered.round())<.001,"camera position is integer viewport-pixel snapped")
 stage.free()
func camera_math() -> void:
 var c=Controls.new();c.configure(Profile.bounds(2),Profile.assembly_origin(2),Vector2(1280,720))
 c.set_view(c.grid_rect().get_center(),.8)
 for at in [Vector2(640,360),Vector2(200,100),Vector2(1020,580)]:
  var before:Vector2=c.pixel_to_world(at)
  check(c.zoom_at(at,1),"zoom accepted")
  var after:Vector2=c.pixel_to_world(at)
  var anchor_error:Vector2=((before-after)*c.pixels_per_world()).abs()
  max_anchor_pixel=maxf(max_anchor_pixel,maxf(anchor_error.x,anchor_error.y))
  check(((before-after)*c.pixels_per_world()).abs().x<=.501 and ((before-after)*c.pixels_per_world()).abs().y<=.501,"cursor remains anchored to half rendered pixel per axis")
 c.fit([],true);var start:Vector2=c.center
 check(c.begin_pan(Vector2(640,360)) and c.pan_to(Vector2(650,350)),"middle pan accepted")
 check(c.center.distance_to(start-Vector2(10,-10)/c.pixels_per_world())<.0001,"pan is inverse camera translation")
 check(not c.pan_to(Vector2(-1,350)) and c.gesture.is_empty(),"leaving scene cancels pan")
 c.set_view(Vector2(-1e9,1e9),2)
 check(c.center==c.clamp_center(c.center) and c.center.length()<20000,"extreme pan is bounded")
 var center:Vector2=c.center;var zoom:float=c.zoom
 check(not c.set_view(Vector2(NAN,0),1) and c.center==center and c.zoom==zoom,"nonfinite view rejected")
 check(not c.zoom_at(Vector2(640,360),NAN) and c.center==center and c.zoom==zoom,"nonfinite zoom rejected")
 c.zoom_at(Vector2(640,360),10000);check(c.zoom<=Controls.MAX_ZOOM,"maximum zoom bounded")
 c.zoom_at(Vector2(640,360),-10000);check(c.zoom>=Controls.MIN_ZOOM,"minimum zoom bounded")
 c.begin_pan(Vector2(640,360));c.configure(Profile.bounds(2),Profile.assembly_origin(2),Vector2(960,540))
 check(c.gesture.is_empty(),"resize cancels active pan")
 c.begin_pan(Vector2(400,200));var saved:Vector2=c.center
 check(not c.pan_to(Vector2(410,200),false) and c.gesture.is_empty() and c.center==saved,"missed release cannot continue camera drag")
 c.begin_pan(Vector2(400,200));c.pan_to(Vector2(410,200),true,false)
 check(c.gesture.is_empty(),"UI or modal entry cancels pan")
func part(id:int,x:int,y:int) -> Dictionary:
 return {"id":id,"type":"battery","x":x,"y":y,"rot":2,"param":9,"input_a":13,"input_b":14,"target":15}
func transactions() -> void:
 var c=Controls.new();c.configure(Profile.bounds(2),Profile.assembly_origin(2),Vector2(1280,720))
 c.fit([],true)
 var parts:Array=[part(5,0,0),part(6,1,0)];var original:Array=parts.duplicate(true)
 var source:Vector2=c.world_to_pixel(c.origin);var destination:Vector2=c.world_to_pixel(c.origin+Vector2(0,-72))
 check(c.begin_edit(source,Vector2i.ZERO,5,7),"left existing part arms relocation")
 c.update_edit(destination)
 var proposal:Dictionary=c.release_edit(destination,Vector2i(0,-1),parts,7)
 check(proposal.get("kind","")=="move" and proposal.id==5 and proposal.cell==Vector2i(0,-1),"valid empty destination proposes one move")
 check(parts==original,"accepted proposal itself does not mutate data, ID, rotation, parameters or wiring")
 check(c.release_edit(destination,Vector2i(0,-1),parts,7).is_empty(),"duplicate release cannot commit twice")
 for item in [
  {"name":"occupied","cell":Vector2i(1,0),"revision":7,"allowed":true,"cancel":false},
  {"name":"outside","cell":Vector2i(13,0),"revision":7,"allowed":true,"cancel":false},
  {"name":"stale model","cell":Vector2i(0,-1),"revision":8,"allowed":true,"cancel":false},
  {"name":"UI release","cell":Vector2i(0,-1),"revision":7,"allowed":false,"cancel":false},
  {"name":"focus/modal cancel","cell":Vector2i(0,-1),"revision":7,"allowed":true,"cancel":true}]:
  c.begin_edit(source,Vector2i.ZERO,5,7);c.update_edit(destination)
  if item.cancel:c.cancel()
  proposal=c.release_edit(destination,item.cell,parts,item.revision,item.allowed)
  check(proposal.is_empty() and parts==original,"rejected "+item.name+" preserves complete model")
 c.begin_edit(source,Vector2i.ZERO,5,7)
 check(c.release_edit(source,Vector2i.ZERO,parts,7).is_empty(),"ordinary click selects without a move")
 c.begin_edit(source,Vector2i.ZERO,5,7);c.update_edit(destination,false)
 check(c.release_edit(destination,Vector2i(0,-1),parts,7).is_empty(),"lost button state cancels move")
 c.begin_edit(source,Vector2i.ZERO,5,7);c.update_edit(destination);c.zoom_at(source,1)
 check(c.gesture.is_empty() and c.release_edit(destination,Vector2i(0,-1),parts,7).is_empty(),"wheel zoom cancels pending edit")
 c.begin_edit(source,Vector2i.ZERO,5,7);c.update_edit(Vector2(-1,30))
 check(c.release_edit(destination,Vector2i(0,-1),parts,7).is_empty(),"leaving then returning cannot commit stale move")
 source=c.world_to_pixel(c.origin+Vector2(0,-72))
 c.begin_edit(source,Vector2i(0,-1),-1,7)
 check(c.release_edit(source,Vector2i(0,-1),parts,7).get("kind","")=="place","empty-cell click proposes placement on valid release")
 c.begin_edit(source,Vector2i(0,-1),-1,7);c.update_edit(source+Vector2(30,0))
 check(c.release_edit(source,Vector2i(0,-1),parts,7).is_empty(),"dragging over empty cells does not paint or install")
 c.begin_edit(source,Vector2i(0,-1),-1,7)
 check(c.release_edit(Vector2(-1,30),Vector2i(0,-1),parts,7).is_empty(),"outside release cannot install")
 check(not Controls.valid_move(parts,99,Vector2i.ZERO,Vector2i(0,-1),c.grid_bounds),"missing part cannot move")
 check(not Controls.valid_move(parts,5,Vector2i(2,0),Vector2i(0,-1),c.grid_bounds),"changed source cannot move")
 check(parts==original,"all gestures leave caller-owned model untouched")
