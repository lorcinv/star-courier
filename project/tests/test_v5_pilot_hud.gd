extends SceneTree
## Presentation contract only; input determinism and physics belong to main/sim.
const HUD=preload("res://scripts/game_hud.gd")
const EXPECTED_CHECKS=21
var hud
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle() -> void:
 for i in 6:await process_frame
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
func button(text:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==text:return node
 return null
func option_ids(key:String) -> Array:
 return hud._wire_options({"id":2},key).map(func(row):return row.id)
func run() -> void:
 root.size=Vector2i(1280,800);hud=HUD.new();root.add_child(hud);hud.set_art_frame(Rect2(0,40,1280,720))
 var data:={"mode":"flight","control_version":"pilot-v1","activeorder":{"name":"晨星社区","distance":500,"deadline":30,"time_limit":45},"settings":{"reduced_motion":true}}
 hud.render(data);await settle()
 var icons_ok:=true
 var types:Array=load("res://scripts/parts.gd").catalog().keys();types.append("cargo")
 for type in types:
  var texture:=load("res://assets/2d_v5/modules/"+type+"-pixel.png") as Texture2D
  icons_ok=icons_ok and texture!=null and texture.get_size()==Vector2(72,72)
 check(icons_ok,"all 25 modules plus cargo load their required generated 72px sprite")
 check(button("1×")==null and button("2×")==null and button("4×")==null,"pilot flight exposes no obsolete simulation-rate actions")
 check(button("暂停  [Esc / P]")!=null and button("中止本次")!=null,"pilot flight retains explicit pause and abort controls")
 var legend:=false
 for label in hud.content.find_children("*","Label",true,false):
  if label.text.contains("Shift") and label.text.contains("Space"):legend=true
 check(legend,"native text legend names steering, boost and active circuit keys")
 hud.update_flight({"forward_speed":24.5,"vertical_speed":-3.0,"energy_remaining":84.0,"pilot_boost":true,"pilot_active":true,"distance":150,"total_distance":500,"integrity":92})
 check(hud.flight_labels.status.text.contains("24.5") and hud.flight_labels.status.text.contains("-3.0"),"speed display uses actual forward and vertical telemetry")
 check(hud.flight_labels.energy.text=="电量 84 J · 冲刺中","remaining energy and held boost are readable")
 check(hud.flight_labels.pilot_signal.text=="Space 回路 · 触发中","active circuit input shows its live trigger state")
 check(is_equal_approx(hud.progress_bar.value,30.0),"pilot route progress still reflects actual distance")
 hud.update_flight({"paused":true,"energy_remaining":0,"pilot_active":false})
 check(button("继续  [Esc / P]")!=null,"paused pilot button offers Continue instead of Pause")
 check(hud.flight_labels.status.text=="已暂停" and hud.flight_labels.energy.text.contains("电量耗尽"),"pause and exhausted energy have unambiguous states")
 check(hud.flight_labels.pilot_signal.text.ends_with("待命"),"released cockpit signal returns to standby")
 hud.update_flight({"charging":true})
 check(button("暂停  [Esc / P]")!=null,"resumed pilot button returns to Pause")
 check(hud.flight_labels.hint.text.is_empty(),"pilot charge does not duplicate launch status with coaching copy")
 hud.update_launch(.5,"charge");await settle()
 check(hud._launch_layer.position.y==108,"pilot launch ribbon remains above the tall starter craft")
 hud.state.mode="workshop";hud.state.parts=[{"id":1,"type":"battery"},{"id":2,"type":"thruster"}]
 check(-2 in option_ids("input_a") and -2 in option_ids("input_b"),"both pilot signal selectors offer cockpit source -2")
 check(not -2 in option_ids("target"),"physical target selectors never offer cockpit source -2")
 hud.state.selectedpart={"id":2,"type":"thruster","param":3.0,"input_a":-1}
 hud._act("set_param",{"id":2,"value":2.5});hud._act("set_input",{"id":2,"key":"input_a","source":-2})
 check(hud.state.selectedpart.param==2.5 and hud.state.selectedpart.input_a==-2,"committed inspector edits update the preserved presentation snapshot")
 hud.state.erase("control_version")
 check(not -2 in option_ids("input_a"),"legacy signal selectors do not expose the new cockpit source")
 data.erase("control_version");hud.render(data);await settle()
 check(button("1×")!=null and button("2×")!=null and button("4×")!=null,"legacy replay presentation retains its original rate controls")
 hud.update_flight({"speed":2,"energy_used":18})
 check(hud.flight_labels.status.text.ends_with("2×") and hud.flight_labels.energy.text.begins_with("消耗 18.0"),"legacy telemetry remains distinct from piloted energy and speed")
 hud.queue_free();for i in 6:await process_frame
 check(get_processed_tweens().is_empty(),"pilot/legacy HUD teardown releases every processed Tween")
 if passed+failed!=EXPECTED_CHECKS:check(false,"every pilot presentation assertion ran")
 print("V5_PILOT_HUD passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
