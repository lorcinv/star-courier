extends SceneTree
## Source03 acceptance. Source02 fixtures remain unchanged historical evidence.
## Scripted HUD signals only; no player saves, native input or gameplay balance.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const UI=preload("res://scripts/module_controls_ui.gd")
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func part(id:int,kind:String,value:float=-999.0,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"rot":1,"param":Parts.defaults(kind) if value==-999.0 else value,"input_a":source,"input_b":-1,"target":-1,"schema":Parts.parameter_schema(kind),"controls":Parts.controls(kind),"spec":Parts.catalog().get(kind,{}),"default_behavior":Parts.controls(kind).default_behavior}
func fixture(selected:Dictionary,assembly:String="craft") -> Dictionary:
 return {"mode":"workshop","assembly_mode":assembly,"control_version":"pilot-v3","catalog":Parts.catalog(),"inventory":{"beam":1,"battery":1,"thruster":0,"spring":0,"not_gate":1},"selectedpart":selected,"parts":[selected,{"id":1,"type":"cargo"},{"id":2,"type":"battery"},{"id":3,"type":"not_gate"}],"settings":{"reduced_motion":true},"ship_stats":{"parts":8,"mass":13.7,"energy":888,"warning":""},"workshop":{"size":Vector2i(9,5),"tier":0}}
func control(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func button(label:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==label:return node
 return null
func inspector() -> Control:return hud.content.get_node("ModuleInspector")
func text_in(node:Node) -> String:
 var result:String=""
 if node is Label or node is Button:result+=node.text+"\n"
 for child in node.get_children():result+=text_in(child)
 return result
func settle() -> void:
 for i in 4:await process_frame
func press(key:String) -> void:
 (control(key) as Button).pressed.emit();await settle()
func run() -> void:
 var catalogue:Dictionary=Parts.catalog();var catalogue_entries:Array=[]
 for kind in catalogue:
  var entry:Dictionary=catalogue[kind].duplicate(true);entry.type=kind;entry.launcher_compatible=kind in Parts.launcher_types();catalogue_entries.append(entry)
 var basic_ids:Array=[]
 for group in UI.BASIC_GROUPS:
  basic_ids.append_array(UI.visible_entries(catalogue_entries,[],{},group,false).map(func(row):return row.type))
 var advanced_ids:Array=UI.visible_entries(catalogue_entries,[],{},"高级零件",false).map(func(row):return row.type)
 check(basic_ids.size()==9 and advanced_ids.size()==17,"source03 explicitly narrows to nine basic and seventeen optional advanced part kinds")
 check(UI.BASIC_GROUPS.get("动力")==["thruster","spring"] and UI.BASIC_GROUPS.get("防护工具")==["armor","shield","drill"],"basic propulsion and protection groups use the newly agreed smaller scope")
 for kind in ["rotator","accelerator","coupler","lance","arc"]:
  check(kind in advanced_ids and not kind in basic_ids,kind+" moves to optional advanced without registry deletion")
 check(basic_ids.size()+advanced_ids.size()==catalogue.size() and not "cargo" in basic_ids and not "cargo" in advanced_ids,"all original placeable IDs remain discoverable with no fabricated cargo")
 var total_schemas:int=0
 for kind in Parts.catalog():
  var schema:Dictionary=Parts.parameter_schema(kind)
  if not bool(schema.editable):continue
  total_schemas+=1
  var input:Dictionary=part(40,kind)
  var schema_row:Dictionary=schema.duplicate(true);schema_row.key="param";schema_row.value=input.param
  var snapshot:Dictionary=input.duplicate(true)
  var preset:Dictionary=UI.preset_control(input,schema_row)
  check(not preset.is_empty() and preset.get("values",[]).size()==3,kind+" has three simple options for its real parameter")
  for value in preset.get("values",[]):
   check(float(value)==Parts.sanitize_parameter(kind,value),kind+" preset is already legal under existing sanitize")
  check(input==snapshot,kind+" preset description does not alter saved data")
 check(total_schemas==14,"all existing editable kinds are covered; no new parameter schema")
 check(UI.PRESETS.thruster.get("values")==[12.0,28.0,40.0] and UI.PRESETS.spring.get("values")==[14.0,20.0,40.0],"thruster and spring use the agreed exact old-parameter mappings")
 var near:Dictionary=part(4,"thruster",28.000001)
 check(UI.preset_control(near,{"key":"param","value":near.param}).selected==-1,"nearby saved values remain custom rather than silently snapped")
 var array_options:Array=[{"id":-1,"label":"默认"},{"id":-2,"label":"驾驶回路"},{"id":3,"label":"已有零件"}]
 var options_copy:Array=array_options.duplicate(true)
 check(UI.usable_wire_options(array_options,true).map(func(row):return row.id)==[-1,3],"launchpad excludes only the ineffective cockpit source")
 check(array_options==options_copy and UI.usable_wire_options(array_options,false)==array_options,"source filtering does not mutate old options and leaves craft sources intact")
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var data:Dictionary=fixture(part(4,"thruster",27.5));var saved:Dictionary=data.duplicate(true)
 hud.render(data);await settle()
 check(data==saved and actions.is_empty() and hud.state.selectedpart.param==27.5,"default render preserves arbitrary old values and emits no save action")
 check(control("part:4:param")==null and control("part:4:input_a")==null,"exact values and wires are absent from basic UI")
 check((control("part:4:preset_label") as Label).text=="动力 · 自定义","old custom value is honestly indicated without arithmetic")
 check(button("低")!=null and button("中")!=null and button("高")!=null,"three obvious basic strength actions remain usable")
 var basic_text:String=text_in(inspector())
 check(not "MODULE" in basic_text and not "#4" in basic_text and not "°" in basic_text and not " N" in basic_text,"basic module view omits IDs angles force units")
 check(basic_text.contains("接通电池，给飞行器提供推力。") and not basic_text.contains("转矩"),"basic purpose is one short game-facing sentence")
 check((inspector().find_child("ModuleFacing",true,false) as Label).text=="↓","installation direction is retained as an arrow")
 var scene_text:String=text_in(hud.content)
 check(not "13.7 kg" in scene_text and not "储能 888 J" in scene_text and not "8 模块" in scene_text and not "9 × 5 格" in scene_text,"default workbench omits engineering totals and grid-size exposition")
 check(button("试飞 · 免费")!=null and button("发射配送  ↗")!=null and button("打开零件箱")!=null,"inventory trial and dispatch remain available")
 await press("part:4:preset:1")
 check(actions==[["set_param",{"id":4,"value":28.0}]] and hud.state.selectedpart.param==28.0,"middle preset emits one existing set_param action with exact mapped value")
 check(hud.state.selectedpart.input_a==-1 and hud.state.selectedpart.target==-1,"changing strength cannot rewrite wiring or target")
 check((control("part:4:preset:1") as Button).button_pressed and not (control("part:4:preset:0") as Button).button_pressed,"basic selection feedback matches the chosen level")
 check((control("part:4:preset_label") as Label).text=="动力","preset choice removes only the custom marker")
 actions.clear();await press("part:4:preset:1")
 check(actions.is_empty(),"pressing the already selected preset does not create a duplicate edit")
 await press("part:4:advanced")
 check(actions.is_empty() and hud.state.selectedpart.param==28.0,"opening advanced does not alter parameter or save state")
 var spin:=control("part:4:param") as SpinBox
 check(spin!=null and spin.min_value==0 and spin.max_value==40 and spin.step==1 and spin.suffix=="N" and spin.value==28,"advanced retains original numerical schema bounds units precision")
 check(control("part:4:input_a")!=null and text_in(inspector()).contains("零件 #4"),"exact identity and functional signal settings remain available when requested")
 var spin_id:int=spin.get_instance_id();spin.value=19;await settle()
 check(actions==[["set_param",{"id":4,"value":19.0}]] and hud.state.selectedpart.param==19,"advanced exact editing uses the unchanged parameter payload")
 check((control("part:4:preset_label") as Label).text=="动力 · 自定义","exact editing immediately updates basic custom feedback")
 check(not (control("part:4:preset:0") as Button).button_pressed and not (control("part:4:preset:1") as Button).button_pressed and not (control("part:4:preset:2") as Button).button_pressed,"custom exact value never selects a misleading preset")
 check((control("part:4:param") as SpinBox).get_instance_id()==spin_id,"precise editing does not rebuild or interrupt its editor")
 actions.clear();await press("part:4:preset:2")
 check(actions==[["set_param",{"id":4,"value":40.0}]] and (control("part:4:param") as SpinBox).value==40,"preset selection updates exact editor without duplicate action")
 actions.clear();await press("part:4:advanced")
 check(control("part:4:param")==null and actions.is_empty() and hud.state.selectedpart.param==40,"closing advanced preserves the chosen parameter")
 var rotate:Button=hud._workshop_labels.rotate;rotate.pressed.emit();await settle()
 check(actions==[["rotate_part",4]] and not "90" in rotate.text,"plain rotate action preserves its existing payload")
 hud.set_input_context("grid");hud.set_input_device(true)
 check(rotate.text=="转向  [X]","controller refresh does not restore engineering angles")
 hud.set_input_device(false);hud.set_input_context("ui")
 check(rotate.text=="转向  [R]","keyboard refresh preserves usable rotate shortcut")
 actions.clear();data=fixture(part(1001,"spring",20,-2),"launcher");data.selectedpart.target=77
 hud.render(data);await settle()
 check(control("part:1001:param")==null and control("part:1001:target")==null and (control("part:1001:preset:1") as Button).button_pressed,"launchpad starts with a clear middle spring setting")
 check(text_in(inspector()).contains("把飞行器弹出发射台。") and text_in(inspector()).contains("发射时自动释放"),"launchpad purpose and automatic release are stated briefly")
 check(actions.is_empty() and hud.state.selectedpart.input_a==-2 and hud.state.selectedpart.target==77,"legacy negative cockpit and ignored target data are retained untouched")
 await press("part:1001:advanced")
 check(control("part:1001:target")==null,"ineffective launchpad spring target is not exposed even in advanced")
 var source:=control("part:1001:input_a") as OptionButton;var has_cockpit:bool=false
 for i in source.item_count:
  if "驾驶回路" in source.get_item_text(i):has_cockpit=true
 check(source.item_count==4 and not has_cockpit,"advanced launcher keeps effective sources and omits Space/cockpit choice")
 check(not text_in(inspector()).contains("Space") and not text_in(inspector()).contains("作用目标") and not text_in(inspector()).contains("等待输入上升沿"),"launchpad details do not teach its ineffective target or wrong in-flight trigger behavior")
 source.item_selected.emit(3);await settle()
 check(actions==[["set_input",{"id":1001,"key":"input_a","source":3}]] and hud.state.selectedpart.input_a==3 and hud.state.selectedpart.target==77,"effective launchpad module source is still editable with original IDs")
 actions.clear();hud.render(fixture(part(5,"spring",14)));await settle()
 check(text_in(inspector()).contains("等待触发") and control("part:5:target")==null,"onboard spring keeps a truthful visible setup warning")
 await press("part:5:advanced")
 check(control("part:5:target")!=null,"onboard spring's effective target control is retained")
 source=control("part:5:input_a") as OptionButton;source.item_selected.emit(1);await settle()
 check(text_in(inspector()).contains("按下 Space"),"onboard spring still distinguishes an edge from held thruster control")
 actions.clear();data=fixture(part(6,"thruster",7.25,3));data.ship_stats.warning="货物连接已断开，先检查装配。"
 hud.render(data);await settle()
 check(text_in(hud.content).contains(data.ship_stats.warning),"real build risk stays visible despite removing informational statistics")
 check(text_in(inspector()).contains("使用已有控制") and not text_in(inspector()).contains("#3") and hud.state.selectedpart.input_a==3,"saved custom wiring remains active without default ID clutter")
 await press("part:6:advanced")
 check(hud.state.selectedpart.param==7.25 and actions.is_empty(),"opening advanced cannot silently round or write a custom saved value")
 await press("part:6:advanced")
 check((control("part:6:preset_label") as Label).text=="动力 · 自定义" and hud.state.selectedpart.param==7.25,"closing advanced preserves and redisplays the exact custom state")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(hud.state);await settle()
  check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(inspector().get_global_rect()),"compact basic inspector is in frame "+str(extent))
 hud.render(fixture(part(8,"beam")));await settle()
 check(control("part:8:param")==null and control("part:8:preset:0")==null and text_in(inspector()).contains("把零件连成船体。"),"fixed passive parts get one purpose without fake adjustable levels")
 check(control("part:8:advanced")!=null,"optional precise explanation remains available for passive parts")
 var saved_coupler:Dictionary=part(8,"coupler");saved_coupler.target=3;saved_coupler.input_a=-2
 hud.render(fixture(saved_coupler));await settle()
 check(text_in(inspector()).contains("分离扣") and hud.state.selectedpart.target==3 and hud.state.selectedpart.input_a==-2,"installed advanced coupler remains selectable with its original saved fields")
 await press("part:8:advanced")
 check(control("part:8:target")!=null and control("part:8:input_a")!=null,"moving coupler out of basic catalogue does not remove its functional controls")
 hud._stop_motion();hud.queue_free();await settle()
 print("MODULE_PLAYFUL_CONTROLS_V3 passed=%d failed=%d input=scripted_signals native_visual=not_tested"%[passed,failed]);quit(1 if failed else 0)
