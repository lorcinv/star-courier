extends SceneTree
## Synthetic HUD signals only. Run native mouse/controller checks separately.
const HUD=preload("res://scripts/game_hud.gd")
const Policy=preload("res://scripts/workshop_parts_v1.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var hud
var actions:Array=[]
var passed:int=0
var failed:int=0

func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func widget(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null

func text_in(node:Node) -> String:
 var result:String=""
 if node is Label or node is Button:result+=node.text+"\n"
 for child in node.get_children():result+=text_in(child)
 return result

func settle() -> void:
 for index in 4:await process_frame

func fixture() -> Dictionary:
 var craft:Array=Profile.starter_design()
 var pad:Array=Profile.starter_launcher()
 var stock:Dictionary={"cargo":1,"beam":4,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1,"not_gate":1}
 for item in craft+pad:stock[item.type]=int(stock[item.type])-1
 return {"mode":"workshop","assembly_mode":"craft","control_version":"pilot-free-v1","catalog":Parts.catalog(),"inventory":stock,"parts":craft,"selectedpart":{},"settings":{"reduced_motion":true},"ship_stats":{"parts":craft.size(),"mass":10.2,"energy":6000.0},"workshop":{"size":Vector2i(9,5),"tier":0}}

func click_category(category:String) -> void:
 var button:=widget("category:"+category) as Button
 check(button!=null,"category is reachable: "+category)
 if button!=null:button.pressed.emit();await settle()

func _initialize() -> void:run.call_deferred()

func run() -> void:
 root.size=Vector2i(1280,720)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var original:Dictionary=fixture()
 var original_json:String=JSON.stringify(original)
 hud.render(original);await settle()
 check(hud.palette_category==Policy.DEFAULT_CATEGORY,"fresh HUD defaults to short core category")
 check(widget("catalog:beam")!=null and widget("catalog:battery")!=null and widget("catalog:thruster")!=null and widget("catalog:armor")!=null,"actual starter default cards expose four core kinds")
 check(widget("catalog:coupler")==null and widget("catalog:not_gate")==null and widget("catalog:spring")==null,"default aircraft cards exclude both legacy newcomers and launcher spring")
 check(widget("category:旧版保留")!=null,"compatibility category is visible without another disclosure")
 check(hud.content.find_child("AdvancedModuleControls",true,false)==null and not "高级设置" in text_in(hud.content) and not "高级零件" in text_in(hud.content),"no global Advanced controls or renamed Advanced category")
 await click_category("旧版保留")
 check(widget("catalog:coupler")!=null and widget("catalog:not_gate")!=null and widget("catalog:beam")==null,"clicking compatibility reveals installed coupler and stocked NOT only")
 var coupler:=widget("catalog:coupler") as Button
 check(coupler!=null and "分离扣" in coupler.tooltip_text and "0.4 kg" in coupler.tooltip_text,"legacy card keeps coupler name and mass")
 check(actions.is_empty() and JSON.stringify(hud.state)==original_json,"view switches emit no domain action and leave saved-shaped HUD state unchanged")
 if coupler!=null:coupler.pressed.emit();await settle()
 check(actions==[["select_catalog","coupler"]],"explicit legacy selection preserves the original placement ID")
 actions.clear()
 await click_category(Policy.DEFAULT_CATEGORY)
 check(widget("catalog:not_gate")==null and widget("catalog:coupler")==null,"returning to quick category hides legacy again")
 var pad:Dictionary=original.duplicate(true)
 pad.assembly_mode="launcher";pad.parts=Profile.starter_launcher()
 hud.render(pad);await settle()
 check(widget("catalog:spring")!=null and widget("catalog:beam")!=null and widget("catalog:battery")!=null,"launcher default shows its owned working spring and structure")
 check(widget("catalog:not_gate")==null and widget("catalog:coupler")==null,"legacy stock cannot leak into launcher quick category")
 await click_category("旧版保留")
 check(widget("catalog:not_gate")!=null,"stocked launcher-compatible old logic is still reachable")
 await click_category(Policy.DEFAULT_CATEGORY)
 hud.render(original);await settle()
 check(widget("catalog:spring")==null,"switching back to aircraft removes launcher spring from quick category")
 var no_legacy:Dictionary=original.duplicate(true)
 no_legacy.inventory.not_gate=0
 no_legacy.parts=no_legacy.parts.filter(func(item):return item.type!="coupler")
 hud.palette_category="旧版保留";hud.render(no_legacy);await settle()
 check(hud.palette_category==Policy.DEFAULT_CATEGORY and widget("category:旧版保留")==null,"stale legacy selection falls back when no retained parts exist")
 hud.palette_category="unrecognized-old-view";hud.render(original);await settle()
 check(hud.palette_category==Policy.DEFAULT_CATEGORY,"unrecognized stale category also falls back to core quick view")
 hud.palette_open=false;hud.render(original);await settle()
 check(hud.content.find_child("PartsTray",true,false)==null,"closing palette removes the tray")
 hud.palette_open=true;hud.render(original);await settle()
 check(widget("catalog:not_gate")==null and widget("catalog:beam")!=null,"reopening retains the bounded default")
 check(actions.is_empty() and JSON.stringify(original)==original_json and JSON.stringify(hud.state)==original_json,"category/context/reopen operations never mutate serialized data or emit a save")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(original);await settle()
  var tray:=hud.content.get_node("PartsTray") as Control
  check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(tray.get_global_rect()),"short-label palette remains in frame "+str(extent))
 hud._stop_motion();hud.queue_free();await settle()
 print("PARTS_CORE_ENTRY_UI_R1 passed=%d failed=%d native_input=not_tested"%[passed,failed]);quit(1 if failed else 0)
