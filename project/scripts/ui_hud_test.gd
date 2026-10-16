extends SceneTree
const HUD = preload("res://scripts/game_hud.gd")
const Parts = preload("res://scripts/parts.gd")
var hud
var test_data:Dictionary
func _initialize() -> void:
 var bg:=ColorRect.new();bg.color=Color("81d9dc");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(bg)
 hud=HUD.new();root.add_child(hud)
 var catalog:=Parts.catalog();catalog["cargo"]=Parts.cargo_spec()
 var inv:Dictionary={}
 for key in catalog:inv[key]=4
 test_data={"mode":"hub","day":3,"credits":745,"reputation":8,"catalog":catalog,"inventory":inv,"chosen_type":"thruster","activeorder":{"name":"给云端农场的种子","cargo":"耐寒种子","distance":160,"deadline":40,"required":90},"contracts":[{"id":0,"name":"给云端农场的种子","cargo":"耐寒种子","distance":160,"deadline":40,"required":90,"client":"阿禾 / 云端农场","story":"这一袋种子，是下个春天的颜色。","risk":"低空浮岩，需要稳住航向。","reward":240}],"selectedpart":{"id":4,"type":"thruster","name":"推进喷口","description":"沿箭头持续施力，偏离重心的推力产生转矩。","param":12,"controls":[{"kind":"number","key":"param","label":"推力","unit":"N","min":0,"max":40,"step":0.5,"value":12},{"kind":"input","key":"input_a","label":"信号输入 A","options":[{"id":-1,"label":"— 默认工作 —"},{"id":3,"label":"#3 距离探头"}]}]},"ship_stats":{"parts":7,"mass":7.4,"energy":300,"warning":""},"parts":[],"report":{"success":false,"trial":true,"cause":"12.4 秒：电芯与推进器断开，货物失去动力。","elapsed":18.2,"integrity":82,"comparison":"比上次多前进 24 m，完整度提高 12%。","events":["02.0 s  发射台释放","12.4 s  结构梁断裂","18.2 s  航行结束"]},"flight":{"elapsed":6.4,"distance":73,"total_distance":160,"integrity":94,"energy":42.2,"events":["02.0 s  发射台释放","04.1 s  距离探头触发","06.3 s  货物通过第一处浮岩"]},"hotspots":[{"id":"counter","label":"委托柜台","position":Vector2(.27,.45)},{"id":"workbench","label":"装配工位","position":Vector2(.48,.59)},{"id":"supply","label":"补给货架","position":Vector2(.72,.38)}]}
 run.call_deferred()
func run() -> void:
 if "--compact" in OS.get_cmdline_user_args():
  root.content_scale_size=Vector2i(1280,800);root.size=Vector2i(1280,800)
 var modes=["hub","contracts","workshop","supply","flight","report","help"]
 for mode in modes:
  test_data.mode=mode;hud.render(test_data)
  await process_frame;await process_frame
  await create_timer(.2).timeout
  print("HUD_MODE_OK ",mode," SIZE ",root.get_visible_rect().size)
  inspect(hud.content)
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("/tmp/hud-"+mode+".png")
 test_data.mode="workshop"
 test_data.selectedpart={"id":2,"type":"beam","spec":{"name":"结构梁"},"schema":{"editable":false},"controls":{"inputs":0,"accepts_target":false}}
 hud.render(test_data)
 await process_frame;await process_frame
 assert(find_by_type(hud.content,"SpinBox").is_empty(),"Structure-only parts must not expose a parameter")
 assert(find_by_type(hud.content,"OptionButton").is_empty(),"Structure-only parts must not expose signal controls")
 var emissions:Array=[]
 hud.action_requested.connect(func(action,payload):emissions.append([action,payload]))
 for button in find_by_type(hud.content,"Button"):
  if button.text=="旋转 90°  [R]":button.pressed.emit()
 assert(emissions.size()==1 and emissions[0][0]=="rotate_part" and emissions[0][1]==2,"Rotate must forward selected part id")
 hud.settings_open=true;hud.render(test_data);await process_frame;await process_frame
 inspect(hud.content)
 print("HUD_TYPED_CONTROLS_AND_ACTIONS_OK")
 hud.settings_open=false
 test_data.mode="contracts";test_data.contracts[0]["contract_id"]="D3-A";test_data.contracts[0]["weight"]=1.4;test_data.contracts[0]["time_limit"]=65;test_data.contracts[0]["delivery_radius"]=2.0;test_data.contracts[0]["max_delivery_speed"]=9.0
 hud.render(test_data);await process_frame;await process_frame
 emissions.clear()
 find_text("接下这单  →").pressed.emit();find_text("婉拒").pressed.emit()
 assert(emissions==[["accept_contract","D3-A"],["decline_contract","D3-A"]],"Offer actions must carry contract_id")
 test_data.mode="hub";test_data.activeorder["contract_id"]="D3-A";test_data.activeorder["accepted"]=true
 hud.render(test_data);await process_frame;await process_frame
 emissions.clear();find_text("取消委托").pressed.emit()
 assert(emissions.is_empty(),"First cancel click must not emit cancellation")
 await process_frame;await process_frame
 find_text("确认取消？").pressed.emit()
 assert(emissions==[["cancel_contract","D3-A"]],"Confirmed cancellation must carry contract id")
 var first_id:int=hud._hotspot_buttons["counter"].get_instance_id()
 hud.update_hotspots(test_data.hotspots)
 assert(hud._hotspot_buttons["counter"].get_instance_id()==first_id,"Position refresh must preserve hotspot buttons")
 test_data.mode="supply";test_data.phase="day";test_data.activeorder["accepted"]=false;hud.render(test_data)
 assert(is_instance_valid(find_text("结束营业，进入夜间补给  →")),"Daytime supply must close the day")
 test_data.phase="night";hud.render(test_data)
 assert(is_instance_valid(find_text("开门，迎接第 4 天  →")),"Night supply must open the next day")
 test_data.mode="report";test_data.report["trial"]=false;hud.render(test_data)
 assert(find_text("再试一次")==null,"Settled delivery must not offer trial retry")
 print("HUD_CONTRACT_PHASE_AND_CANCELLATION_OK")
 print("HUD_ALL_MODES_OK")
 quit()

func inspect(node: Node, in_scroll:bool=false) -> void:
 var scrolling:bool=in_scroll or node is ScrollContainer
 if node is Control and not scrolling:
  var rect:Rect2=node.get_global_rect()
  if rect.end.x>root.get_visible_rect().size.x+4 or rect.end.y>root.get_visible_rect().size.y+4 or rect.position.x< -4 or rect.position.y< -4:
   print("OVERFLOW ",node.name," ",node.get_class()," ",rect)
 for child in node.get_children():inspect(child,scrolling)

func find_by_type(node: Node, type: String) -> Array:
 var found:Array=[]
 if node.is_class(type):found.append(node)
 for child in node.get_children():found.append_array(find_by_type(child,type))
 return found

func find_text(value: String) -> Button:
 for button in find_by_type(hud.content,"Button"):
  if button.text==value:return button
 return null
