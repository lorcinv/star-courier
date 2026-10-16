extends SceneTree
## HUD-only scripted-signal checks. No native input, game saves, or gameplay edits.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts.gd")
const UI=preload("res://scripts/module_controls_ui.gd")
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func control(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func has_text(needle:String) -> bool:
 for node in hud.content.find_children("*","Label",true,false):
  if needle in node.text:return true
 return false
func part(id:int,kind:String,source:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"rot":0,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":-1,"schema":Parts.parameter_schema(kind),"controls":Parts.controls(kind),"spec":Parts.catalog().get(kind,{}),"default_behavior":Parts.controls(kind).default_behavior}
func fixture(selected:Dictionary,assembly:String="craft") -> Dictionary:
 return {"mode":"workshop","assembly_mode":assembly,"control_version":"pilot-v3","catalog":Parts.catalog(),"inventory":{"beam":4,"battery":3,"thruster":2,"spring":1,"not_gate":1},"selectedpart":selected,"parts":[selected,{"id":1,"type":"cargo"},{"id":2,"type":"battery"},{"id":3,"type":"not_gate"}],"settings":{"reduced_motion":true},"ship_stats":{}}
func settle() -> void:
 for i in 4:await process_frame
func run() -> void:
 root.size=Vector2i(1280,720)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var initial:Dictionary=fixture(part(4,"thruster"));var before:Dictionary=initial.duplicate(true)
 hud.render(initial);await settle()
 check(initial==before and actions.is_empty(),"render never mutates source design or emits an edit")
 check(has_text("推力强度") and not has_text("目标推力"),"basic thruster field has a plain presentation label")
 check(has_text("启动：自动运行"),"unwired thruster truthfully advertises automatic startup")
 check(control("part:4:input_a")==null,"signal selector starts collapsed")
 var spin:=control("part:4:param") as SpinBox
 check(spin!=null and spin.min_value==0 and spin.max_value==40 and spin.step==1 and spin.value==12 and spin.suffix=="N","numeric parameter units bounds default and precision remain identical")
 var numeric_rows:Array=hud._typed_controls(initial.selectedpart,initial.selectedpart.controls)
 check(numeric_rows[0].label=="目标推力","underlying typed schema remains unchanged")
 var stored:Dictionary=hud.state.selectedpart.duplicate(true)
 (control("part:4:advanced") as Button).pressed.emit();await settle()
 check(hud.state.selectedpart==stored and actions.is_empty(),"expanding advanced controls is presentation-only")
 var source:=control("part:4:input_a") as OptionButton
 check(source!=null and source.item_count==5,"advanced dropdown retains every original source option")
 check(source.get_item_text(0)=="— 未连接 —" and source.get_item_text(1)=="驾驶回路","legacy sentinel option labels and ordering are preserved")
 check(hud._wire_options(initial.selectedpart,"input_a").map(func(row):return row.id)==[-1,-2,1,2,3],"all original source IDs remain selectable")
 source.item_selected.emit(1);await settle()
 check(actions==[["set_input",{"id":4,"key":"input_a","source":-2}]],"selecting cockpit emits exact existing set_input payload")
 check(hud.state.selectedpart.input_a==-2 and has_text("启动：按住 Space / 手柄 A"),"startup reflects held cockpit source without a toggle promise")
 check(control("part:4:input_a")!=null,"editing does not unexpectedly collapse advanced controls")
 actions.clear();(control("part:4:advanced") as Button).pressed.emit();await settle()
 check(actions.is_empty() and hud.state.selectedpart.input_a==-2 and control("part:4:input_a")==null,"collapsing preserves cockpit setting without emitting edits")
 spin=control("part:4:param") as SpinBox;spin.value=28;await settle()
 check(actions==[["set_param",{"id":4,"value":28.0}]] and hud.state.selectedpart.param==28,"strength reuses exact old param action and value")
 hud.render(hud.state);await settle()
 check((control("part:4:param") as SpinBox).value==28 and has_text("按住 Space"),"rerender preserves configured strength and startup source")
 actions.clear();hud.render(fixture(part(5,"spring")));await settle()
 check(not hud._inspector_advanced_open and control("part:5:target")==null,"new selection collapses both advanced signal and target")
 check(has_text("弹射力度") and has_text("等待触发"),"onboard spring never falsely promises automatic release")
 (control("part:5:advanced") as Button).pressed.emit();await settle()
 check(control("part:5:target")!=null and control("part:5:input_a")!=null,"onboard spring preserves both existing advanced controls")
 check(hud._wire_options(hud.state.selectedpart,"target").map(func(row):return row.id)==[-1,1,2,3],"target IDs are unchanged and never include cockpit")
 check("第一个相邻模块" in (control("part:5:target") as OptionButton).tooltip_text,"unspecified target fallback is explained accurately")
 (control("part:5:input_a") as OptionButton).item_selected.emit(1);await settle()
 check(has_text("启动：按下 Space / 手柄 A") and not has_text("启动：按住 Space"),"onboard spring describes an edge rather than a held thruster")
 hud.render(fixture(part(5,"spring",-2),"launcher"));await settle()
 check(not hud._inspector_advanced_open and has_text("发射时自动释放"),"same-ID launchpad selection resets disclosure and uses actual launchpad behavior")
 (control("part:5:advanced") as Button).pressed.emit();await settle()
 check(has_text("不读取 Space") and has_text("不使用“作用目标”"),"launchpad clearly explains special preparation and unused target")
 check("不参与发射台弹射" in (control("part:5:target") as OptionButton).tooltip_text,"existing launchpad target remains editable with accurate no-effect explanation")
 var wired:Dictionary=part(6,"thruster",3);hud.render(fixture(wired));await settle()
 check(has_text("启动：由 #3 控制") and control("part:6:input_a")==null,"saved custom wiring stays active and visible in compact status")
 var legacy:Dictionary=part(7,"thruster",-2);var legacy_data:Dictionary=fixture(legacy);legacy_data.control_version="autonomous-v1"
 hud.render(legacy_data);await settle()
 check(has_text("启动：自动运行"),"negative cockpit sentinel does not invent manual control in autonomous solver")
 check(hud._wire_options(legacy,"input_a").map(func(row):return row.id)==[-1,1,2,3],"nonpilot source list retains original absence of cockpit")
 hud.render(fixture(part(8,"beam")));await settle()
 check(control("part:8:advanced")==null and control("part:8:param")==null,"passive beam does not acquire fake settings")
 var data:Dictionary=part(9,"thruster");data.controls=[{"kind":"number","key":"param","label":"旧参数","min":0,"max":40,"step":.5,"value":7},{"kind":"input","key":"input_a","label":"旧信号","options":[{"id":-1,"label":"旧默认"},{"id":3,"label":"旧来源"}]}]
 hud.render(fixture(data));await settle();(control("part:9:advanced") as Button).pressed.emit();await settle()
 check((control("part:9:param") as SpinBox).step==.5 and (control("part:9:param") as SpinBox).value==7,"legacy array control numeric payload remains exact")
 check((control("part:9:input_a") as OptionButton).item_count==2 and (control("part:9:input_a") as OptionButton).get_item_text(0)=="旧默认","legacy array control explicit options remain exact")
 check(UI.describe(part(10,"accelerator",-2),true,false).status=="启动：按下 Space / 手柄 A","cockpit-controlled accelerator retains its rising-edge semantics")
 check(UI.describe(part(10,"accelerator"),true,false).status=="启动：自动运行","unwired accelerator retains its distinct initial automatic firing behavior")
 var status_before:Dictionary=data.duplicate(true);UI.describe(data,true,false)
 check(data==status_before,"presentation helper does not mutate input dictionaries")
 hud._stop_motion();hud.queue_free();await settle()
 print("MODULE_CONTROLS_UI_V2 passed=%d failed=%d input=scripted_signals native_visual=not_tested"%[passed,failed]);quit(1 if failed else 0)
