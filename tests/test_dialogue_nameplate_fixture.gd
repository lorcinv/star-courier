extends SceneTree
## Scripted presentation fixture using the production DialoguePanel and portraits.
## This captures actual rendered pixels, not native-input or full-gameplay QA.
const DialoguePanel=preload("res://scripts/dialogue_panel.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const OUTPUT:String="res://docs/qa/v5/dialogue-nameplates"
var panel
var passed:int=0
var failed:int=0
var captures:Array=[]
func _initialize() -> void:run.call_deferred()
func check(condition:bool,message:String) -> void:
 if condition:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 8:await process_frame
func rect_data(rect:Rect2) -> Dictionary:
 return {"x":rect.position.x,"y":rect.position.y,"width":rect.size.x,"height":rect.size.y}
func capture(speaker:String,extent:Vector2i) -> void:
 await settle()
 check(root.size==extent and root.get_visible_rect().size==Vector2(extent),"actual window and viewport dimensions: "+str(extent))
 var plate:Rect2=panel._name.get_global_rect()
 var portrait:Rect2=panel._left_portrait.get_global_rect() if speaker=="npc" else panel._right_portrait.get_global_rect()
 check(is_equal_approx(plate.get_center().x,portrait.get_center().x),"active speaker footer alignment: "+speaker+" "+str(extent))
 check(not plate.intersects(panel._counter.get_global_rect()) and not plate.intersects(panel._body.get_global_rect()),"readable counter and text: "+speaker+" "+str(extent))
 if DisplayServer.get_name()=="headless" or not "--capture" in OS.get_cmdline_user_args():return
 await RenderingServer.frame_post_draw
 var screenshot:Image=root.get_texture().get_image()
 check(screenshot.get_size()==extent,"actual rendered pixel dimensions: "+str(extent))
 var file:String="nameplate-%s-%dx%d.png"%[speaker,extent.x,extent.y]
 check(screenshot.save_png(OUTPUT+"/"+file)==OK,"saved rendered fixture: "+file)
 captures.append({"file":file,"speaker":speaker,"name":panel._name.text,"window_width":extent.x,"window_height":extent.y,"nameplate":rect_data(plate),"portrait":rect_data(portrait),"textbox":rect_data(panel._body.get_global_rect()),"counter":rect_data(panel._counter.get_global_rect())})
func run() -> void:
 root.title="Star Courier - scripted nameplate fixture"
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 var background:=ColorRect.new();background.color=Color("26354b");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(background)
 panel=DialoguePanel.new();root.add_child(panel)
 var actor:=Stories.actor_metadata(Stories.initial_state().roster.human_courier)
 var conversation:Dictionary={"id":"nameplate_fixture","title":"柜台来信","route_hint":"晨星社区 → 星港中转站","lines":[{"speaker":"npc","text":"今天这份包裹需要先送到晨星社区，再转交星港中转站。请按原来的路线飞行，途中记得查看货物完整度，平安回来。","expression":"pleased"},{"speaker":"clerk","text":"一把勺子，也值得单独跑一趟？","expression":"curious"}]}
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  panel.begin(conversation,actor,{"reduced_motion":true,"dialogue_muted":true});panel.set_process(false);panel.advance()
  await capture("npc",extent)
  panel.advance();panel.advance();await capture("clerk",extent)
  panel.skip_conversation()
 if not captures.is_empty():
  var metadata:Dictionary={"method":"Scripted fixture, production DialoguePanel and portraits, actual Godot-rendered viewport pixels; no native-input or gameplay claim","engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"display_server":DisplayServer.get_name(),"captures":captures}
  var file:=FileAccess.open(OUTPUT+"/fixture-metadata.json",FileAccess.WRITE);file.store_string(JSON.stringify(metadata,"  ")+"\n");file.close()
 panel.queue_free();background.queue_free();await settle()
 print("DIALOGUE_NAMEPLATE_FIXTURE ",passed," passed, ",failed," failed; captures=",captures.size())
 quit(1 if failed else 0)
