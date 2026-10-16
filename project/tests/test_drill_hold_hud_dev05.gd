extends SceneTree
## Real inspector/buttons with synthetic presses. Native player gate is separate.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var hud
var actions:Array=[]
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:run.call_deferred()
func part(id:int,kind:String,x:int,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":0,"rot":0,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1,"spec":Parts.catalog().get(kind,{})}
func fixture(source:int=-1,version:String="pilot-free-v2",launcher:bool=false) -> Dictionary:
 var selected:Dictionary=part(3,"drill",1,source)
 return {"mode":"workshop","assembly_mode":"launcher" if launcher else "craft","control_version":version,"catalog":Parts.catalog(),"inventory":{"drill":1,"beam":3,"battery":2},"selectedpart":selected,"parts":[part(1,"cargo",0),part(2,"battery",-1),selected],"settings":{"reduced_motion":true},"ship_stats":{"parts":3,"mass":8.0,"energy":6000.0},"workshop":{"size":Vector2i(9,5),"tier":0}}
func widget() -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if hud._view_key(node)=="part:3:startup":return node
 return null
func status() -> String:
 var label=hud.content.find_child("ModuleStartupStatus",true,false)
 return label.text if label!=null else ""
func settle() -> void:
 for index in 3:await process_frame
func run() -> void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud)
 hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var original:Dictionary=fixture();var before:PackedByteArray=var_to_bytes(original)
 for repetition in 3:hud.render(original);await settle()
 check(var_to_bytes(original)==before and actions.is_empty() and hud.state.selectedpart.input_a==-1,"opening/reopening inspector leaves saved automatic source and all input fields exact")
 check(widget()!=null and widget().text=="改为按住启动" and "自动运行" in status(),"automatic drill shows current behavior and explicit held option")
 check(hud.content.find_child("AdvancedModuleControls",true,false)==null,"no global advanced settings return")
 if widget()!=null:widget().pressed.emit()
 await settle()
 check(actions==[["set_input",{"id":3,"key":"input_a","source":-2}]],"one actual button press emits existing set_input payload exactly once")
 check(hud.state.selectedpart.input_a==-2 and "按住空格 / A" in status() and widget()!=null and widget().text=="改为自动运行","held choice immediately updates status and reciprocal label")
 check(var_to_bytes(original)==before,"HUD projection never edits its source design directly")
 actions.clear()
 if widget()!=null:widget().pressed.emit()
 await settle()
 check(actions==[["set_input",{"id":3,"key":"input_a","source":-1}]] and hud.state.selectedpart.input_a==-1,"second deliberate button press restores automatic through existing action")
 actions.clear();hud.render(hud.state);await settle()
 check(actions.is_empty(),"rebuilding after toggle creates no extra edit or save request")
 for version in ["","autonomous-v5","pilot-v3","pilot-free-v1","future-v99"]:
  hud.render(fixture(-1,version));await settle()
  check(widget()==null and actions.is_empty(),version+" automatic drill has no new held option")
 hud.render(fixture(-1,"pilot-free-v2",true));await settle()
 check(widget()==null and actions.is_empty(),"launchpad automatic drill has no new held option")
 var route_context:Dictionary=fixture();route_context.erase("control_version");route_context.activeorder={"control_version":"pilot-free-v2"}
 hud.render(route_context);await settle()
 check(widget()!=null and widget().text=="改为按住启动","explicit route version fallback reaches current ship option")
 route_context.control_version="pilot-free-v1"
 hud.render(route_context);await settle()
 check(widget()==null,"explicit older presentation context is not overridden by an unrelated newer route field")
 var wired:Dictionary=fixture(99);wired.selectedpart.param=2.125;wired.selectedpart.input_b=71;wired.selectedpart.target=13
 before=var_to_bytes(wired)
 for repetition in 3:hud.render(wired);await settle()
 check(var_to_bytes(wired)==before and actions.is_empty() and hud.state.selectedpart.input_a==99,"external wire and custom fields survive repeated read-only inspection")
 check("沿用控制" in status() and widget()!=null and widget().text=="改为自动运行","wired drill retains original explicit auto reset, not new manual action")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(fixture());await settle()
  var inspector:Control=hud.content.get_node("ModuleInspector")
  check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(inspector.get_global_rect()),"drill inspector fits "+str(extent))
  check(widget()!=null and widget().is_visible_in_tree() and widget().size.y>=36,"drill option remains a visible ordinary button "+str(extent))
 hud._stop_motion();hud.queue_free();await settle()
 print("DRILL_HOLD_HUD_DEV05 passed=%d failed=%d native_input=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
