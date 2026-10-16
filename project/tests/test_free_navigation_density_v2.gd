extends SceneTree
const Cue=preload("res://scripts/delivery_direction_cue.gd")
const Metrics=preload("res://scripts/demo_display_metrics.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var cue=Cue.new();root.add_child(cue);await process_frame
 for scale in [1.0,1.5,2.0,3.0]:
  var safe:Rect2=Metrics.rect(Rect2(38,126,1204,420),scale)
  for target in [Vector2(2400,360),Vector2(-400,360),Vector2(600,-700),Vector2(600,1200)]:
   var snap:Dictionary={"status":"running","charging":false,"cargo_screen":Vector2(600,360)*scale,"receiver_screen":target*scale,"distance_m":100.0}
   cue.present(snap,Transform2D.IDENTITY,safe,scale)
   check(cue.visible,"arrow visible")
   check(safe.grow(0.01).has_point(cue._tip),"native-density tip inside actual safe rectangle")
   check(cue._distance.get_theme_font_size("font_size")==roundi(18*scale),"native text size follows density")
   check(cue._distance.size.x>=140*scale,"distance does not shrink at1080")
  var right:Dictionary={"status":"running","charging":false,"cargo_screen":Vector2(600,360)*scale,"receiver_screen":Vector2(2400,360)*scale,"distance_m":100.0}
  cue.present(right,Transform2D.IDENTITY,safe,scale)
  check(is_equal_approx(cue._tip.x,1242.0*scale),"right-edge arrow reaches true native window edge")
 cue.queue_free();await process_frame
 print("FREE_NAV_DENSITY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
