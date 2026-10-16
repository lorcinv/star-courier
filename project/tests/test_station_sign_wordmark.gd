extends SceneTree
## Focused registration checks; this file has NOT been engine-run in the lane.
const Sign=preload("res://scripts/shop_sign_2d.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func run() -> void:
 var sign=Sign.new();root.add_child(sign)
 check(sign.texture==Sign.SIGN_TEXTURE and sign.region_enabled and sign.region_rect==Rect2(0,0,436,54),"original upper hardware is reused without the obsolete emblem")
 check(sign.position==Vector2(4,46) and sign.scale==Vector2.ONE,"world registration is unchanged")
 check(sign.get_child_count()==9,"one plaque, two support bases, four lamps and two wordmark slices are created once")
 check(not sign.is_processing() and not sign.is_physics_processing(),"station sign has no per-frame processing")
 var left=sign.get_node("OriginalWordmarkLeft") as Sprite2D
 var right=sign.get_node("OriginalWordmarkRight") as Sprite2D
 check(left.scale==Vector2(0.5,0.5) and right.scale==left.scale,"original lettering has one uniform half-scale transform")
 check((left.texture as AtlasTexture).atlas==Sign.WORDMARK_TEXTURE and (right.texture as AtlasTexture).atlas==Sign.WORDMARK_TEXTURE,"both slices reference the preserved original concept")
 check((left.texture as AtlasTexture).region==Rect2(14,6,250,160) and (right.texture as AtlasTexture).region==Rect2(264,6,38,144),"notched crop excludes unrelated hair while retaining logo envelope")
 check(right.position-left.position==Vector2(125,0),"wordmark slices meet on the same source seam")
 check(sign.opaque_world_rect().end.y<266,"taller plaque clears conservative y266 actor-head boundary")
 var anchors=sign.support_anchors_world()
 check(anchors[0].is_equal_approx(Vector2(115.552941,56.603529)) and anchors[1].is_equal_approx(Vector2(328.242353,56.603529)),"original mounting anchors are unchanged")
 for node_name in ["TopOriginalLamp","BottomOriginalLamp","LeftOriginalLamp","RightOriginalLamp"]:
  var lamp=sign.get_node(node_name) as Sprite2D
  check((lamp.texture as AtlasTexture).atlas==Sign.SIGN_TEXTURE and lamp.scale==Vector2.ONE,"native source pixels retained: "+node_name)
 for child in sign.get_children():check(child.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"nearest source sampling: "+str(child.name))
 sign.queue_free();await process_frame
 print("STATION_SIGN_WORDMARK_TESTS passed=",passed," failed=",failed,"; native composition review still required")
 quit(1 if failed else 0)
