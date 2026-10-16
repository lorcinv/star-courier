extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
const Policy=preload("res://scripts/workshop_parts_v1.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var hud
var actions:Array=[]
var passed:int=0
var failed:int=0
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:run.call_deferred()
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1,"spec":Parts.catalog().get(kind,{})};p.merge(extra,true);return p
func fixture(selected:Dictionary,pieces:Array=[]) -> Dictionary:
 return {"mode":"workshop","assembly_mode":"craft","control_version":"pilot-free-v1","catalog":Parts.catalog(),"inventory":{"beam":4,"battery":3,"thruster":2,"not_gate":1},"selectedpart":selected,"parts":pieces if not pieces.is_empty() else [part(1,"cargo",0),part(2,"battery",-1),selected],"settings":{"reduced_motion":true},"ship_stats":{"parts":3,"mass":8.0,"energy":6000.0},"workshop":{"size":Vector2i(9,5),"tier":0}}
func widget(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func text_in(node:Node) -> String:
 var text:String=""
 if node is Label or node is Button:text+=node.text+"\n"
 for child in node.get_children():text+=text_in(child)
 return text
func settle() -> void:
 for index in 4:await process_frame
func run() -> void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var original:Dictionary=fixture(part(3,"thruster",1,0,{"param":27.25,"input_a":99}));var before:Dictionary=original.duplicate(true)
 hud.render(original);await settle()
 check(original==before and actions.is_empty(),"render preserves arbitrary old raw parameter and wiring")
 check(hud.state.selectedpart.param==27.25 and "27.25" in text_in(hud.content),"old custom value honestly remains visible with slider")
 check(hud.content.find_child("AdvancedModuleControls",true,false)==null and not "高级设置" in text_in(hud.content),"no global or per-part Advanced disclosure remains")
 check(widget("part:3:input_a")==null and widget("part:3:startup")!=null,"old wiring has local explicit auto convenience, no signal editor wall")
 var slider:=widget("part:3:param") as HSlider
 check(slider!=null and slider.min_value==0 and slider.max_value==40,"per-part slider has exact bounded thrust range")
 slider.drag_started.emit();slider.value=30;slider.value=35;slider.value=40
 check(actions.is_empty(),"drag intermediate motion does not repeatedly save")
 slider.drag_ended.emit(true);await settle()
 check(actions==[["set_param",{"id":3,"value":40.0}]] and hud.state.selectedpart.param==40,"drag release commits one real schema parameter edit")
 actions.clear();slider.value=39;await settle()
 check(actions==[["set_param",{"id":3,"value":39.0}]],"keyboard/controller-style value step commits immediately")
 actions.clear();(widget("part:3:startup") as Button).pressed.emit();await settle()
 check(actions==[["set_input",{"id":3,"key":"input_a","source":-1}]] and hud.state.selectedpart.input_a==-1,"local convenience edits only selected input on actual press")
 actions.clear()
 var splitter:Dictionary=part(3,"splitter",1,0,{"input_a":-2,"target":1})
 var items:Array=[part(1,"cargo",0),splitter,part(2,"battery",2),part(4,"splitter",1,1),part(5,"beam",1,-1)]
 hud.render(fixture(splitter,items));await settle()
 check("当前目标是货物" in text_in(hud.content) and "同时触发" in text_in(hud.content),"splitter visibly rejects cargo and explains shared manual button")
 var target:=widget("part:3:target") as OptionButton
 check(target!=null and target.item_count==3 and "原目标" in target.get_item_text(0),"old invalid target preserved beside two recognizable valid choices")
 check("电芯" in target.get_item_text(1) and "2，0" in target.get_item_text(1) and "结构梁" in target.get_item_text(2),"target choices have real module names and grid positions")
 target.item_selected.emit(1);await settle()
 check(actions==[["set_input",{"id":3,"key":"target","source":2}]] and hud.state.selectedpart.target==2,"player selecting a valid target changes only target, never input/param")
 check(hud.state.selectedpart.input_a==-2 and "装配就绪" in text_in(hud.content),"target update becomes visibly ready using unchanged manual binding")
 actions.clear();hud.render(hud.state);await settle();check(actions.is_empty(),"repeated opening never emits a migration or save")
 var legacy:Dictionary=part(8,"and_gate",1,0,{"input_a":1,"input_b":2,"param":0})
 hud.render(fixture(legacy));await settle()
 check("旧版保留" in text_in(hud.content) and "输入 A" in text_in(hud.content) and "输入 B" in text_in(hud.content),"retired logic remains honest readable compatibility data")
 check(widget("part:8:input_a")==null and widget("part:8:startup")==null,"no replacement complex global/legacy wiring editor")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(fixture(splitter,items));await settle()
  var inspector:Control=hud.content.get_node("ModuleInspector")
  check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(inspector.get_global_rect()),"special part inspector is in frame "+str(extent))
 var pad:Dictionary=fixture(part(1001,"spring",0));pad.assembly_mode="launcher"
 hud.render(pad);await settle()
 check(widget("part:1001:param") is HSlider and widget("part:1001:target")==null and "自动弹射" in text_in(hud.content),"launcher spring has own slider and no fake target/control setup")
 hud._stop_motion();hud.queue_free();await settle()
 print("PARTS_CORE_UI_V1 passed=%d failed=%d native_input=not_tested"%[passed,failed]);quit(1 if failed else 0)
