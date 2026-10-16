extends SceneTree
## Component geometry/input bounds fixture, not a full-game native acceptance run.
const Metrics=preload("res://scripts/demo_display_metrics.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Phone=preload("res://scripts/customer_review_phone.gd")
const Dialogue=preload("res://scripts/dialogue_panel.gd")
const Stage=preload("res://scripts/pixel_stage.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(count:int=5) -> void:
 for i in count:await process_frame
func finish_motion(hud:Node) -> void:
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 var hud=HUD.new();root.add_child(hud)
 var phone=Phone.new();root.add_child(phone);phone.set_existing_theme(hud.root.theme)
 var dialogue=Dialogue.new();root.add_child(dialogue)
 var hub:Dictionary={"mode":"hub","day":1,"credits":1800,"settings":{"reduced_motion":true},"has_accepted_contract":true,"activeorder":{"name":"显示尺寸测试","distance":100,"contract_id":"display-v2"}}
 var records:Array=[{"client":"测试收件人","rating":5,"body":"包裹收到，谢谢。","delivery_day":1,"published_day":2}]
 var conversation:Dictionary={"id":"display-v2","lines":[{"speaker":"npc","text":"请按这张运单，把包裹送到星港中转站。","expression":"neutral"},{"speaker":"clerk","text":"收到，路上会照顾好它。","expression":"neutral"}]}
 for extent in [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1920,1080),Vector2i(1280,800),Vector2i(1920,1080)]:
  root.size=extent;await settle()
  var density:float=Metrics.factor(Vector2(extent))
  var frame:Rect2=Metrics.stage_rect(Vector2(extent))
  hud.set_art_frame(frame);hud.render(hub);await settle();finish_motion(hud)
  var tag:String=str(extent)+" / "+str(density)
  check(hud.root.scale==Vector2.ONE and hud.root.get_global_rect()==frame,"native HUD root "+tag)
  check(hud._size==Vector2(1280,720),"unchanged HUD design composition "+tag)
  var dock:Button=null
  for child in hud.content.get_children():
   if child is Button and child.has_meta("scene_action"):dock=child;break
  check(dock!=null and dock.size==Metrics.point(Vector2(164,48),density) and frame.encloses(dock.get_global_rect()),"dock native hit target "+tag)
  var waybill:Control=hud.content.get_node("CurrentWaybill")
  check(frame.encloses(waybill.get_global_rect()),"waybill bounded "+tag)
  var phone_launcher:Control=hud.content.get_node("PhoneLauncher")
  check(frame.encloses(phone_launcher.get_global_rect()),"phone launcher bounded "+tag)
  hud.toast("新的提示仍然在当前画面内。");await settle()
  check(frame.encloses(hud.toast_panel.get_global_rect()) and hud.toast_label.get_theme_font_size("font_size")==Metrics.font_size(16,density),"native toast "+tag)
  var workshop:Dictionary=hub.duplicate(true);workshop.mode="workshop";workshop.catalog={};workshop.ship_stats={"parts":3,"mass":20,"energy":100};workshop.workshop={"size":Vector2i(9,5),"tier":0}
  hud.render(workshop);await settle();finish_motion(hud)
  var expected:Rect2=Metrics.rect(Rect2(20,176,912,300),density);expected.position+=frame.position
  check(hud.workshop_scene_rect()==expected,"workshop fit/pointer bounds share native metrics "+tag)
  phone.set_art_frame(frame,frame.position+frame.size*Vector2(0.8,0.6))
  check(phone.open_from_player(records,2),"phone opens "+tag);await settle()
  check(phone._device.scale==Vector2.ONE and phone._device.size==Metrics.point(Vector2(395,624),density),"native phone destination "+tag)
  check(frame.encloses(phone._device.get_global_rect()),"phone shell bounded "+tag)
  check(phone._casing.patch_margin_left==25 and phone._casing.patch_margin_top==56,"phone source-pixel corners preserved "+tag)
  check(phone._panel.size==phone._device.size-Vector2(51,124),"phone aperture follows native shell "+tag)
  phone.open_reviews_app();await settle()
  var entry:Control=null
  for child in phone._list.get_children():
   if child.has_meta("phone_review"):entry=child;break
  check(entry!=null and entry.get_child(0).get_child(1).get_theme_font_size("font_size")==Metrics.font_size(18,density),"phone body font rerasterized "+tag)
  phone.close_phone()
  check(dialogue.begin(conversation,{}, {"reduced_motion":true,"dialogue_muted":true}),"dialogue opens "+tag);dialogue.advance();await settle()
  check(dialogue._canvas.scale==Vector2.ONE and dialogue._canvas.get_global_rect()==frame,"native dialogue frame "+tag)
  check(dialogue._body.get_theme_font_size("font_size")==Metrics.font_size(27,density),"native dialogue body font "+tag)
  check(dialogue._left_portrait.texture.get_size()==Vector2(202,202) and dialogue._left_portrait.size==Vector2(404,404)*density,"portrait integer2x/3x source grid "+tag)
  check(is_equal_approx(dialogue._name.get_global_rect().get_center().x,dialogue._left_portrait.get_global_rect().get_center().x),"speaker name follows portrait "+tag)
  check(frame.encloses(dialogue._continue.get_global_rect()),"dialogue continue target bounded "+tag)
  dialogue.skip_conversation()
 check(Stage.choose_canvas(Vector2i(1920,1080),"auto")==Vector2i(960,540),"auto world remains960x540 integer2x")
 check(Stage.choose_canvas(Vector2i(1920,1080),"low")==Vector2i(640,360),"low world remains640x360 integer3x")
 # New menu children and changing style/separation do not recapture a native rect.
 var stage:=Control.new();root.add_child(stage)
 var panel:=PanelContainer.new();panel.position=Vector2(786,55);panel.size=Vector2(430,600);stage.add_child(panel)
 var menu:=VBoxContainer.new();panel.add_child(menu);menu.add_theme_constant_override("separation",14)
 var label:=Label.new();label.add_theme_font_size_override("font_size",20);label.text="新游戏";menu.add_child(label)
 Metrics.apply_stage(stage,1.5);Metrics.apply_stage(stage,1.5)
 check(panel.position==Vector2(1179,83) and label.get_theme_font_size("font_size")==30,"repeat metric application does not compound")
 Metrics.set_constant_override(menu,"separation",6);Metrics.apply_stage(stage,1.5)
 check(menu.get_theme_constant("separation")==9 and panel.position==Vector2(1179,83),"menu changes preserve native rectangle")
 Metrics.apply_stage(stage,1.0)
 check(panel.position==Vector2(786,55) and label.get_theme_font_size("font_size")==20,"resize round-trip restores authored metrics")
 hud.queue_free();phone.queue_free();dialogue.queue_free();stage.queue_free();await settle()
 print("DEMO_DISPLAY_METRICS_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
