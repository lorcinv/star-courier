extends SceneTree
## Read-only runtime observer. Native driver alone sends user events. No phone
## opening, economy mutation, manual stepping or gameplay API is invoked here.
var game
var out:String=""
var age:float=0.0
var busy:bool=false
var last_frame:String=""
var sequence:int=0
func _initialize() -> void:run.call_deferred()
func run() -> void:
 if DisplayServer.get_name()=="headless":push_error("Native observer requires approved graphical session");quit(2);return
 var args=OS.get_cmdline_user_args();out=args[0] if not args.is_empty() else ""
 if out.is_empty():quit(3);return
 DirAccess.make_dir_recursive_absolute(out)
 root.size=Vector2i(1280,800);root.title="Star Courier Phone QA"
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
func _process(delta:float) -> bool:
 if not is_instance_valid(game) or not is_instance_valid(game.courier_input):return false
 age+=delta
 if age<.08:return false
 age=0.0
 var buttons:Array=[]
 for node in game.hud.content.find_children("*","Button",true,false):
  if node.is_visible_in_tree():buttons.append({"text":node.text,"key":str(node.get_meta("view_key","")),"rect":rect_value(node.get_global_rect())})
 var owner:Control=root.gui_get_focus_owner()
 var snap:Dictionary={"unix_seconds":Time.get_unix_time_from_system(),"page":game.page,"phone":game._review_phone_is_open(),"context":game.courier_input.context,"focused":game.courier_input.focused,"position":[game.world.clerk.position.x,game.world.clerk.position.y],"owner_scale":[game.world.clerk.scale.x,game.world.clerk.scale.y],"draw_registration":clerk_registration(),"depth":game.world.clerk.z_index,"pose":str(game.world._clerk_motion.debug_snapshot().pose),"buttons":buttons,"focus_key":str(owner.get_meta("view_key","")) if owner!=null else "","reviews":game.economy.customer_reviews().size(),"credits":game.economy.credits,"reputation":game.economy.reputation,"size":[root.size.x,root.size.y],"window_position":[root.position.x,root.position.y],"native_handle":DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE),"phone_rect":rect_value(game.review_phone._panel.get_global_rect()),"close_rect":rect_value(game.review_phone._close.get_global_rect()),"scroll":game.review_phone._scroll.scroll_vertical}
 var file=FileAccess.open(out+"/latest.json",FileAccess.WRITE);file.store_string(JSON.stringify(snap));file.close()
 var state:String=str(snap.phone)+"-"+str(root.size)
 if state!=last_frame and not busy:
  last_frame=state;capture(state)
 return false
func clerk_registration() -> Dictionary:
 var sprite:Sprite2D=game.world.clerk;var motion=game.world._clerk_motion
 var snap:Dictionary=motion.debug_snapshot();var frame:Dictionary=motion.current_frame()
 var rigid:bool=bool(snap.get("rigid_active",false));var rig:Node2D=sprite.get_node_or_null("ClerkRigidCutouts") as Node2D
 var actual:Transform2D=sprite.transform
 var single:bool=sprite.texture!=null and (rig==null or not rig.visible)
 if rigid:
  var head:Sprite2D=motion._parts.head
  actual=sprite.transform*head.transform
  single=sprite.texture==null and rig!=null and rig.visible and head.visible
  for part in rig.get_children():single=single and part.visible
 var draw_scale:=Vector2(actual.x.length(),actual.y.length())
 var bounds:Array=frame.head_bounds
 var source_size:=Vector2(float(bounds[2])-float(bounds[0]),float(bounds[3])-float(bounds[1]))
 var head_size:Vector2=snap.head_size_parent
 var rendered_right:bool=actual.x.x>0 if rigid else not sprite.flip_h
 return {"draw_scale":[draw_scale.x,draw_scale.y],"body_height":draw_scale.y*float(frame.body_height),
  "head_size":[head_size.x,head_size.y],"head_source_size":[source_size.x,source_size.y],
  "head_registered":head_size.is_equal_approx(source_size*draw_scale),"head_reference":str(snap.head_reference),
  "single_representation":single,"facing_right":bool(snap.facing_right),"rendered_facing_right":rendered_right,"rigid":rigid}
func rect_value(value:Rect2) -> Array:return [value.position.x,value.position.y,value.size.x,value.size.y]
func capture(label:String) -> void:
 busy=true
 for unused in 3:await process_frame
 await RenderingServer.frame_post_draw
 var file:String=out+"/%03d-%s.png"%[sequence,label.replace(" ","").replace("(","").replace(")","").replace(",","x")]
 root.get_texture().get_image().save_png(file);sequence+=1;busy=false
