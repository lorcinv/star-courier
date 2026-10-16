extends SceneTree
const Controls=preload("res://scripts/workshop_controls.gd")
const Profile=preload("res://scripts/workshop_profile.gd")
var passed:int=0
var failed:int=0
func check(value:bool,label:String) -> void:
 if value:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:
 for extent in [Vector2(1280,720),Vector2(960,540),Vector2(640,360)]:
  var scale:float=extent.x/1280.0
  var usable=Rect2(Vector2(20,100)*scale,Vector2(940,410)*scale)
  for tier in range(3):
   var c=Controls.new();var bounds:Rect2i=Profile.bounds(tier)
   var origin=Vector2(728,288)
   var grid=Rect2(origin+(Vector2(bounds.position)-Vector2.ONE*.5)*72.0,Vector2(bounds.size)*72.0)
   var support=Rect2(grid.position,Vector2(grid.size.x,maxf(grid.end.y,502.0)-grid.position.y))
   check(c.configure(bounds,origin,extent,usable,[],support),"tier config")
   for point in [support.position,Vector2(support.end.x,support.position.y),support.end,Vector2(support.position.x,support.end.y)]:
    check(usable.grow(.001).has_point(c.world_to_pixel(point)),"floor and grid fit above HUD")
   for x in range(bounds.position.x,bounds.end.x):
    for y in range(bounds.position.y,bounds.end.y):
     var cell=Vector2i(x,y);check(c.cell_at(c.world_to_pixel(origin+Vector2(cell)*72.0))==cell,"cell inverse unchanged")
   var before=Vector2(c.center);var zoom=float(c.zoom)
   check(c.configure(bounds,origin,extent,usable,[],support) and c.center.is_equal_approx(before) and is_equal_approx(c.zoom,zoom),"ordinary render keeps camera")
 print("RECOVERY_WORKSHOP_FIT passed=",passed," failed=",failed);quit(1 if failed else 0)
