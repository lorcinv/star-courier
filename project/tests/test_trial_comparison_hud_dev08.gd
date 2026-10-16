extends SceneTree
## Display-only regression. The exact native dev07 A/B saves are read, never
## loaded into Main/Economy or written. Input here is synthetic, not native QA.
const HUD=preload("res://scripts/game_hud.gd")
const A_SHA256:String="7a6b962d3855234739558ce60903cfce8255c1ad571270de74b23d9a073a3125"
const B_SHA256:String="599d0d589f74b4494afef7e6a62bf37c42533c4172ef7d056dcb4672336b34ad"
const MISSING:String="暂无可用的上次试飞对比。"
const NOTE:String="正负值表示本次减去上次；完整度按百分点比较。结果也受操作和结束时机影响。"
const OMITTED:String="（内容较长，已省略）"
const ROWS:Array=[
 ["航时","航时变化：","TrialComparisonElapsed"],
 ["耗能","耗能变化：","TrialComparisonEnergy"],
 ["完整度","完整度变化：","TrialComparisonIntegrity"],
 ["预计净收益","预计结余变化：","TrialComparisonProfit"]
]
const ACTIONS:Array=["focus_workbench","trial_retry","dispatch"]
const BUTTON_TEXT:Array=["回工位调整","再试一次","正式配送"]
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
var a_save:Dictionary={}
var b_save:Dictionary={}
var original_saves:PackedByteArray

func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 8:await process_frame
 if is_instance_valid(hud):
  for tween in hud._motion_tweens.values():
   if tween.is_valid():tween.custom_step(1.0)
 await process_frame
func named(name:String) -> Node:
 return hud.content.find_child(name,true,false)
func label_text(name:String) -> String:
 var node:=named(name) as Label
 return node.text if node!=null else ""
func control(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func action_button(action:String) -> Button:
 return control("action:"+action+":null") as Button
func comparison_copy() -> String:
 var section:=named("TrialComparison");var text:String=""
 if section!=null:
  for node in section.find_children("*","Label",true,false):text+=node.text+"\n"
 return text
func body_scroll() -> ScrollContainer:
 var section:=named("TrialComparison")
 return section.get_parent().get_parent() as ScrollContainer if section!=null else null
func details_button() -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if hud._view_key(node).begins_with("details:report:"):return node
 return null
func capture_action(action:String,payload:Variant) -> void:actions.append([action,payload])
func read_fixture(path:String,expected:String,label:String) -> Dictionary:
 if path.is_empty() or not FileAccess.file_exists(path):
  check(false,label+" fixture path is required");return {}
 check(FileAccess.get_sha256(path)==expected,label+" fixture has the frozen native hash")
 if FileAccess.get_sha256(path)!=expected:return {}
 var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(value is Dictionary,label+" fixture parses as a save dictionary")
 return value if value is Dictionary else {}
func fixture(report:Dictionary) -> Dictionary:
 # Keep the entire saved craft and economic ledger reachable as mutation
 # sentinels, including fields this renderer has no reason to inspect.
 var data:Dictionary=b_save.duplicate(true)
 data.mode="report";data.report=report.duplicate(true);data.trial=true
 data.has_accepted_contract=true;data.activeorder=b_save.contracts[0].duplicate(true)
 data.settings.reduced_motion=true
 data.undo_history=[{"design":a_save.design.duplicate(true),"launcher":a_save.launcher.duplicate(true)}]
 return data
func report_with(comparison:Variant) -> Dictionary:
 var report:Dictionary=b_save.last_trials["D6-A"].latest.duplicate(true)
 report.comparison=comparison
 return report
func render_case(data:Dictionary,title:String) -> void:
 var input_before:PackedByteArray=var_to_bytes(data)
 var count:int=actions.size()
 hud.render(data);await settle()
 check(var_to_bytes(data)==input_before and var_to_bytes(hud.state)==input_before,title+" preserves full report, assembly, undo, credits, inventory and ledger inputs")
 check(var_to_bytes([a_save,b_save])==original_saves and actions.size()==count,title+" leaves original saves and action count unchanged")
 check(not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),title+" writes neither save slot")
func expect_missing(title:String) -> void:
 var section:=named("TrialComparison")
 check(section!=null and section.get_child_count()==1 and label_text("TrialComparisonMissing")==MISSING,title+" shows only the unavailable comparison message")
 check(named("TrialComparisonHeading")==null and not comparison_copy().contains("首次"),title+" invents neither zeros nor a first-trial claim")
func button_signature() -> Array:
 var result:Array=[]
 for action in ACTIONS:
  var node:=action_button(action)
  result.append([node.text,hud._view_key(node),node.disabled,node.focus_mode,node.custom_minimum_size,node.get_global_rect()] if node!=null else [])
 return result
func check_buttons(frame:Rect2,title:String) -> void:
 var buttons:Array=[]
 for index in ACTIONS.size():
  var node:=action_button(ACTIONS[index]);buttons.append(node)
  check(node!=null and node.text==BUTTON_TEXT[index] and not node.disabled and node.focus_mode==Control.FOCUS_ALL,title+" retains action "+ACTIONS[index])
  if node==null:continue
  check(frame.encloses(node.get_global_rect()) and not body_scroll().is_ancestor_of(node),title+" keeps "+ACTIONS[index]+" visible outside the scroll area")
  if index>0 and buttons[index-1]!=null:
   check(buttons[index-1].get_parent()==node.get_parent() and buttons[index-1].get_index()<node.get_index() and not buttons[index-1].get_global_rect().intersects(node.get_global_rect()),title+" preserves bottom button order and separation")
func pointer(position:Vector2) -> void:
 var event:=InputEventMouseMotion.new();event.position=position;event.global_position=position;root.push_input(event);await process_frame
func mouse(position:Vector2,down:bool,index:int=MOUSE_BUTTON_LEFT) -> void:
 var event:=InputEventMouseButton.new();event.position=position;event.global_position=position;event.button_index=index;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down and index==MOUSE_BUTTON_LEFT else 0;root.push_input(event);await process_frame
func click(node:Control) -> void:
 var point:=node.get_global_rect().get_center();await pointer(point);await mouse(point,true);await mouse(point,false);await settle()
func key(code:int) -> void:
 for down in [true,false]:
  var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event);await process_frame
 await settle()
func joy(index:int) -> void:
 for down in [true,false]:
  var event:=InputEventJoypadButton.new();event.button_index=index;event.pressed=down;root.push_input(event);await process_frame
 await settle()
func set_extent(extent:Vector2i) -> Rect2:
 root.size=extent
 var frame:Rect2=Rect2(0,(extent.y-720)/2.0,1280,720) if extent.x==1280 else Rect2(Vector2.ZERO,Vector2(extent))
 hud.set_art_frame(frame)
 return frame
func finish() -> void:
 if is_instance_valid(hud):hud._stop_motion();hud.queue_free()
 for i in 8:await process_frame
 print("TRIAL_COMPARISON_HUD_DEV08 passed=%d failed=%d native_input=NOT_RUN flight_physics=NOT_RUN input=synthetic_HUD_only"%[passed,failed])
 quit(1 if failed else 0)

func run() -> void:
 if OS.get_environment("SC_TRIAL_COMPARISON_TEST_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Use SC_TRIAL_COMPARISON_TEST_ISOLATED=1, a new empty XDG_DATA_HOME, and SC_TRIAL_COMPARISON_A_SAVE / SC_TRIAL_COMPARISON_B_SAVE paths; no existing profile is used.");quit(2);return
 var a_path:String=OS.get_environment("SC_TRIAL_COMPARISON_A_SAVE")
 var b_path:String=OS.get_environment("SC_TRIAL_COMPARISON_B_SAVE")
 a_save=read_fixture(a_path,A_SHA256,"A");b_save=read_fixture(b_path,B_SHA256,"B")
 if a_save.is_empty() or b_save.is_empty():quit(2);return
 original_saves=var_to_bytes([a_save,b_save])
 var a:Dictionary=a_save.last_trials["D6-A"].latest
 var b:Dictionary=b_save.last_trials["D6-A"].latest
 check(b_save.last_trials["D6-A"].previous==a,"native B retains exact A as the previous trial")
 check(a.comparison["本次改动"]=="装置未改动。" and b.comparison["本次改动"]=="结构梁换了位置","fixture changes are the corrected dev07 native records")
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(capture_action)
 set_extent(Vector2i(1280,720))
 await render_case(fixture(b),"native B initial render")
 check(named("TrialComparison")!=null,"saved trial comparison is rendered (frozen dev07 baseline must fail here)")
 # This is also the deliberate baseline-red seam: avoid null dereferences if
 # the same test is run on an untouched source02 copy before the overlay.
 if named("TrialComparison")==null:
  await finish();return
 for pair in [["A",a],["B",b]]:
  await render_case(fixture(pair[1]),"native "+pair[0])
  check(label_text("TrialComparisonHeading")=="与上次同委托试飞比较" and label_text("TrialComparisonChanges")=="本次装配改动："+pair[1].comparison["本次改动"],"native "+pair[0]+" shows the saved comparison and change statement")
  for row in ROWS:
   check(label_text(row[2])==row[1]+pair[1].comparison[row[0]],"native "+pair[0]+" preserves saved "+row[0]+" verbatim")
  check(label_text("TrialComparisonNote")==NOTE,"native "+pair[0]+" explains subtraction, percentage points and operating uncertainty")
  var section:=named("TrialComparison") as Control
  check(section.is_visible_in_tree() and body_scroll()!=null and section.get_index()<details_button().get_index(),"comparison starts expanded before the existing flight details")
  check(details_button().text=="查看 · 飞行详情" and not (named("OptionalDetails") as Control).visible,"flight details retain their initially collapsed state")
  check(not hud.is_blocking_modal() and section.find_children("*","BaseButton",true,false).is_empty(),"comparison introduces no popup or action")
  var uniform:bool=true
  for row in ROWS:uniform=uniform and (named(row[2]) as Label).get_theme_color("font_color")==HUD.DIM
  check(uniform and not comparison_copy().contains("提升") and not comparison_copy().contains("更优") and not comparison_copy().contains("改装带来"),"saved differences have neutral colors and no causal claim")
 var absent:Dictionary=b.duplicate(true);absent.erase("comparison")
 await render_case(fixture(absent),"missing comparison");expect_missing("missing comparison")
 for value in [null,{},[],[1,2],"bad comparison",123,true]:
  await render_case(fixture(report_with(value)),"unusable comparison container");expect_missing("unusable comparison container")
 await render_case(fixture(report_with({"陌生字段":"DO_NOT_SHOW","航时":" \t\r\n ","本次改动":"\u0001\u007f\u0085"})),"empty whitelist");expect_missing("empty whitelist")
 for bad in [1,2.5,true,[],{"secret":"DO_NOT_SHOW"},null," \t\r\n "]:
  var partial:Dictionary={"航时":"+1.00 秒","耗能":bad,"完整度":bad,"预计净收益":bad,"本次改动":bad,"未知键":"DO_NOT_SHOW"}
  await render_case(fixture(report_with(partial)),"partial bad field")
  check(label_text("TrialComparisonElapsed")=="航时变化：+1.00 秒" and label_text("TrialComparisonEnergy")=="耗能变化：—" and label_text("TrialComparisonIntegrity")=="完整度变化：—" and label_text("TrialComparisonProfit")=="预计结余变化：—" and label_text("TrialComparisonChanges")=="本次装配改动：未记录","only nonempty whitelisted strings are shown")
  check(not comparison_copy().contains("DO_NOT_SHOW") and not comparison_copy().contains("装置未改动"),"invalid and unknown fields are neither stringified nor invented")
 await render_case(fixture(report_with({"本次改动":"旧记录按原样保留"})),"change-only comparison")
 check(label_text("TrialComparisonChanges")=="本次装配改动：旧记录按原样保留" and label_text("TrialComparisonElapsed")=="航时变化：—","a saved change alone is a usable comparison")
 for flag in [false,"false","true",0,1,1.0,null,[],{}]:
  var typed:Dictionary=fixture(b);typed.report.trial=flag;typed.trial=true
  await render_case(typed,"explicit invalid or false trial flag")
  check(named("TrialComparison")==null,"present report flag never falls back to state or coerces into a comparison")
  check(control("action:close_drawer:null")!=null and control("action:next_contract:null")!=null and action_button("trial_retry")==null,"malformed or false flag completes a non-trial result render instead of aborting")
 for flag in [true,false,"true",1,null]:
  var legacy:Dictionary=fixture(b);legacy.report.erase("trial");legacy.trial=flag
  await render_case(legacy,"legacy trial state flag")
  check((named("TrialComparison")!=null)==(flag is bool and flag==true),"only a missing report flag may use a real true state bool")
  check(action_button("trial_retry")!=null if flag is bool and flag else control("action:close_drawer:null")!=null,"legacy flag always completes the correct result render")
 var explicit_trial:Dictionary=fixture(b);explicit_trial.trial=false
 await render_case(explicit_trial,"saved trial overrides current state")
 check(named("TrialComparison")!=null and action_button("trial_retry")!=null,"saved true trial remains authoritative even when current state says false")
 var no_flag:Dictionary=fixture(b);no_flag.report.erase("trial");no_flag.erase("trial")
 await render_case(no_flag,"no trial flags");check(named("TrialComparison")==null,"missing flags do not imply a trial")
 var paid:Dictionary=fixture(b);paid.report.trial=false;paid.report.profit=-4
 await render_case(paid,"paid report with accidental comparison")
 check(named("TrialComparison")==null and control("action:close_drawer:null")!=null and control("action:next_contract:null")!=null and action_button("trial_retry")==null,"paid result keeps its existing actions and has no trial comparison")
 var signed:Dictionary={"航时":"-1.25 秒","耗能":"+0.0 J","完整度":"-0.1%","预计净收益":"¥ +20","本次改动":"装置未改动。"}
 await render_case(fixture(report_with(signed)),"signed saved strings")
 for row in ROWS:check(label_text(row[2])==row[1]+signed[row[0]],"signed display keeps saved "+row[0]+" without recomputation")
 var different_order:Dictionary=fixture(b)
 different_order.activeorder.contract_id="OTHER-CONTRACT";different_order.last_trials={"OTHER-CONTRACT":{"latest":{"comparison":{"本次改动":"DO_NOT_SHOW"}}}}
 different_order.design=[];different_order.launcher=[]
 await render_case(different_order,"changed active state")
 check(label_text("TrialComparisonChanges")=="本次装配改动：结构梁换了位置" and label_text("TrialComparisonElapsed")=="航时变化：-19.67 秒","display reads the report without recomputing from active order, craft or latest history")
 var boundary:Dictionary={"航时":"1".repeat(64),"耗能":"2".repeat(65),"完整度":"3".repeat(4000),"预计净收益":"\t¥\r\n +0\u00a0","本次改动":"梁".repeat(4096)}
 await render_case(fixture(report_with(boundary)),"exact text bounds")
 check(label_text("TrialComparisonElapsed")=="航时变化："+"1".repeat(64) and label_text("TrialComparisonEnergy")=="耗能变化：—" and label_text("TrialComparisonIntegrity")=="完整度变化：—","numeric strings accept 64 characters and reject longer data without numeric truncation")
 check(label_text("TrialComparisonChanges")=="本次装配改动："+"梁".repeat(4096) and not comparison_copy().contains(OMITTED),"4096 changes characters fit without an omission claim")
 check(label_text("TrialComparisonProfit")=="预计结余变化：¥ +0","control and Unicode whitespace normalize locally")
 await render_case(fixture(report_with({"本次改动":"梁".repeat(4097)})),"over-limit change")
 check(label_text("TrialComparisonChanges")=="本次装配改动："+"梁".repeat(4096)+OMITTED,"long changes show a bounded prefix and explicit omission marker")
 await render_case(fixture(report_with({"本次改动":" \n\n甲\t\r\n乙\u0001\u007f\u0085\u2028\u3000丙 \n"})),"control whitespace")
 check(label_text("TrialComparisonChanges")=="本次装配改动：甲 乙 丙","control whitespace collapses without tall blank runs")
 # The Godot 4.6.3 string parser converts unsupported NUL to U+FFFD before
 # this renderer can inspect it. U+FFFD is visible content, not whitespace.
 await render_case(fixture(report_with({"本次改动":"甲�乙"})),"literal replacement character")
 check(label_text("TrialComparisonChanges")=="本次装配改动：甲�乙","literal U+FFFD remains visible and is never swallowed as whitespace")
 var long_report:Dictionary=report_with({"航时":"+0.00 秒","耗能":"-1.0 J","完整度":"+0.0%","预计净收益":"¥ +0","本次改动":"[b]"+"ASCIIWITHOUTBREAK".repeat(300)+"[/b]"})
 var round_trip:Array=[]
 for extent in [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1280,812),Vector2i(1920,1080),Vector2i(3840,2160),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,720)]:
  var frame:Rect2=set_extent(extent)
  await render_case(fixture(absent),"layout missing "+str(extent));var before_buttons:Array=button_signature()
  await render_case(fixture(long_report),"layout long ASCII "+str(extent))
  check(button_signature()==before_buttons,"long comparison does not move or change existing bottom actions "+str(extent))
  check_buttons(frame,"layout "+str(extent))
  var scroll:ScrollContainer=body_scroll();var section:=named("TrialComparison") as Control
  var panel:Control=scroll.get_parent().get_parent()
  check(frame.encloses(panel.get_global_rect()) and scroll.size.y>0 and scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"report panel and nonzero body remain contained without horizontal scrolling "+str(extent))
  var width_ok:bool=true
  for node in section.find_children("*","Label",true,false):
   width_ok=width_ok and node.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART and node.size.x<=scroll.size.x+1.0 and node.get_minimum_size().x<=node.size.x+1.0
  check(width_ok and section.find_children("*","RichTextLabel",true,false).is_empty() and label_text("TrialComparisonChanges").contains("[b]ASCIIWITHOUTBREAK"),"all comparison labels wrap long ASCII as literal plain text "+str(extent))
  scroll.scroll_vertical=0;await settle()
  var point:Vector2=scroll.get_global_rect().get_center()
  await pointer(point)
  for i in 4:await mouse(point,true,MOUSE_BUTTON_WHEEL_DOWN);await mouse(point,false,MOUSE_BUTTON_WHEEL_DOWN)
  await settle();check(scroll.scroll_vertical>0,"mouse wheel reaches long comparison content "+str(extent))
  var offset:int=scroll.scroll_vertical;var detail_key:String=hud._view_key(details_button())
  await render_case(hud.state,"repeat long comparison "+str(extent));scroll=body_scroll()
  check(scroll.scroll_vertical==offset and hud._view_key(details_button())==detail_key,"rerender preserves existing scroll and detail identity "+str(extent))
  scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);await settle()
  check(scroll.get_global_rect().encloses(details_button().get_global_rect()),"body can scroll to the existing flight detail toggle "+str(extent))
  details_button().pressed.emit();await settle()
  check((named("OptionalDetails") as Control).visible,"existing flight details still expand "+str(extent))
  await render_case(hud.state,"open details rerender "+str(extent))
  check((named("OptionalDetails") as Control).visible and details_button().text=="收起 · 飞行详情","detail disclosure survives comparison rerender "+str(extent))
  details_button().pressed.emit();await settle()
  check(not (named("OptionalDetails") as Control).visible,"existing flight details still collapse "+str(extent))
  action_button("focus_workbench").grab_focus();await key(KEY_TAB)
  check(root.gui_get_focus_owner()==action_button("trial_retry"),"Tab reaches the existing retry button "+str(extent))
  hud.set_input_device(true);action_button("focus_workbench").grab_focus();await joy(JOY_BUTTON_DPAD_RIGHT)
  check(root.gui_get_focus_owner()==action_button("trial_retry"),"synthetic gamepad navigation reaches the existing retry button "+str(extent))
  hud.set_input_device(false)
  if extent==Vector2i(1280,720):round_trip.append(button_signature())
 check(round_trip.size()==3 and round_trip[0]==round_trip[1] and round_trip[1]==round_trip[2],"720 to 1080 to 720 restores exact bottom button geometry")
 set_extent(Vector2i(1280,720));await render_case(fixture(b),"action verification")
 var state_before:PackedByteArray=var_to_bytes(hud.state)
 actions.clear();await click(action_button("focus_workbench"));await click(action_button("trial_retry"))
 check(actions==[["focus_workbench",null],["trial_retry",null]],"real HUD button connections emit each unchanged adjustment/retry intent exactly once")
 actions.clear();await click(action_button("dispatch"))
 check(hud.dispatch_confirmation_open and actions.is_empty() and root.gui_get_focus_owner()==control("dispatch:cancel"),"formal dispatch retains its confirmation and safe initial focus")
 await key(KEY_ESCAPE)
 check(not hud.dispatch_confirmation_open and actions.is_empty(),"cancelling formal dispatch makes no delivery request")
 # A test-only receiver owns all intents; there is no Main, simulation or
 # Economy. Confirm solely to verify the unchanged signal cardinality.
 await click(action_button("dispatch"));await click(control("dispatch:confirm"))
 check(actions==[["dispatch",null]] and not hud.dispatch_confirmation_open,"formal confirmation emits the original dispatch intent exactly once to the test receiver")
 actions.clear()
 check(var_to_bytes(hud.state)==state_before,"scroll, disclosure, focus and action intent checks leave assembly and economic state unchanged")
 await render_case(fixture(a),"switch back to report A")
 check(label_text("TrialComparisonChanges")=="本次装配改动：装置未改动。","switching reports replaces the shown saved comparison")
 await render_case(fixture(b),"switch back to report B")
 check(label_text("TrialComparisonChanges")=="本次装配改动：结构梁换了位置","switching reports never reuses another report's comparison")
 check(FileAccess.get_sha256(a_path)==A_SHA256 and FileAccess.get_sha256(b_path)==B_SHA256 and var_to_bytes([a_save,b_save])==original_saves,"both full native save files and parsed dictionaries remain byte-exact")
 check(not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"all display and synthetic input checks create no save or backup")
 await finish()
