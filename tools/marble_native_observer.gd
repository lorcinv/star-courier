extends SceneTree
## Read-only runtime observer. All gameplay intent comes from OS XTest input.
## Captures actual main viewport; never moves/opens/closes/steps/sets game state.
var game
var out:String=""
var age:float=0.0
var busy:bool=false
var last_frame:String=""
var sequence:int=0
func _initialize() -> void:run.call_deferred()
func run() -> void:
 if DisplayServer.get_name()=="headless":push_error("Native proof requires approved graphical session");quit(2);return
 var args=OS.get_cmdline_user_args();out=args[0] if not args.is_empty() else ""
 if out.is_empty():quit(3);return
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(1280,800);root.title="Star Courier Marble QA"
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
 var prop:Sprite2D=game.world.foreground_root.get_node("StoredBlackMarble")
 var snap:Dictionary={"unix_seconds":Time.get_unix_time_from_system(),"page":game.page,"open":game._investigation_is_open(),"phone":game._review_phone_is_open(),"context":game.courier_input.context,"focused":game.courier_input.focused,"position":[game.world.clerk.position.x,game.world.clerk.position.y],"rig":rig_pose(),"depth":game.world.clerk.z_index,"pose":str(game.world._clerk_motion.debug_snapshot().pose),"buttons":buttons,"focus_key":str(owner.name) if owner!=null else "","ledger":ledger(),"size":[root.size.x,root.size.y],"window_position":[root.position.x,root.position.y],"native_handle":DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE),"panel_rect":rect_value(game.investigation._canvas.get_global_rect()),"close_rect":rect_value(game.investigation._close.get_global_rect()),"hint":game.courier_input._hint.text,"hint_visible":game.courier_input._hint.visible,"text":game.investigation._body.text,"body_lines":game.investigation._body.get_line_count(),"pixel_canvas":[game.view.size.x,game.view.size.y],"inspection_owner":game.world._investigation_owner,"phone_owner":game.world._review_phone_owner,"prop_world_rect":rect_value(Rect2(prop.position-prop.texture.get_size()*prop.scale*.5,prop.texture.get_size()*prop.scale))}
 var file=FileAccess.open(out+"/latest.json",FileAccess.WRITE);file.store_string(JSON.stringify(snap));file.close()
 var state:String=str(snap.open)+"-"+str(root.size)+"-"+str(snap.context)+"-"+str(snap.hint.contains("弹珠"))
 if state!=last_frame and not busy:
  last_frame=state;capture(state)
 return false
func ledger() -> String:
 return JSON.stringify({"credits":game.economy.credits,"reputation":game.economy.reputation,"reviews":game.economy.review_state,"story":game.economy.story_state,"day":game.economy.day,"design":game.design,"launcher":game.launcher})
func rig_pose() -> String:
 var parts:Array=[]
 for node in game.world._clerk_motion._parts.values():parts.append([str(node.name),str(node.transform),str(node.texture.resource_path),node.visible])
 return JSON.stringify({"root":str(game.world.clerk.transform),"z":game.world.clerk.z_index,"rig":game.world._clerk_motion._rig.visible,"parts":parts,"facing":game.world._clerk_motion.debug_snapshot().facing_right})
func rect_value(value:Rect2) -> Array:return [value.position.x,value.position.y,value.size.x,value.size.y]
func capture(label:String) -> void:
 busy=true
 for unused in 3:await process_frame
 await RenderingServer.frame_post_draw
 var file:String=out+"/%03d-%s.png"%[sequence,label.replace(" ","").replace("(","").replace(")","").replace(",","x")]
 root.get_texture().get_image().save_png(file);sequence+=1;busy=false
