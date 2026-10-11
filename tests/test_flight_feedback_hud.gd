extends SceneTree
## Isolated, synthetic/headless presentation tests; no GPU or native input claim.
const HUD=preload("res://scripts/game_hud.gd")
const V1=preload("res://scripts/pilot_simulation.gd")
const V2=preload("res://scripts/pilot_ascent_simulation.gd")
const V3=preload("res://scripts/pilot_extreme_simulation.gd")
const V4=preload("res://scripts/pilot_wormhole_simulation.gd")
const P1=preload("res://scripts/pilot_profile.gd")
const P2=preload("res://scripts/pilot_ascent_profile.gd")
const P3=preload("res://scripts/pilot_extreme_profile.gd")
const P4=preload("res://scripts/pilot_wormhole_profile.gd")
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]

func _initialize() -> void:run.call_deferred()
func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)
func settle() -> void:
 for i in 5:await process_frame
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
 await process_frame
func action(name:String,payload:Variant) -> void:actions.append([name,payload])
func button(caption:String) -> Button:
 for node in hud.content.find_children("*","Button",true,false):
  if node.text==caption:return node
 return null
func shown_text() -> String:
 var result:String=""
 for node in hud.content.find_children("*","Label",true,false):
  if node.is_visible_in_tree():result+=node.text+"\n"
 return result
func fixture(route:Dictionary,flight:Dictionary={}) -> Dictionary:
 var result:Dictionary={"mode":"flight","control_version":str(route.control_version),"activeorder":route,"settings":{"reduced_motion":true}}
 if not flight.is_empty():result.flight=flight
 return result
func live(sim) -> Dictionary:
 var data:Dictionary=sim.telemetry.duplicate(true)
 data.merge({"elapsed":sim.elapsed,"events":sim.events,"distance":sim.cargo_position().x,"total_distance":sim.route.distance},true)
 return data
func flat_route() -> Dictionary:
 var route:Dictionary=P4.route()
 route.hazards=[];route.pilot_gates=[];route.pilot_drag=0.0
 route.pilot_altitude=0.0;route.destination_y=0.0;route.distance=320.0;route.boundary_y=500.0
 route.wormhole_portal.entry=[20.0,0.0];route.wormhole_portal.exit=[200.0,0.0]
 return route
func portal_fixture(route:Dictionary={},design:Array=[]):
 var sim=V4.new()
 sim.configure([P3.part(1,"cargo",0),P3.part(2,"battery",-1)] if design.is_empty() else design,[],flat_route() if route.is_empty() else route,42)
 return sim
func cross(sim) -> void:
 for body in sim.bodies:body.position.x+=19.0;body.velocity=Vector2(600,0)
 sim.step(1.0/120.0)
func inspect_real(sim,expected:String,title:String) -> void:
 hud.render(fixture(sim.route,live(sim)))
 var before:PackedByteArray=var_to_bytes(sim.events)
 hud.update_flight(live(sim))
 check(hud.flight_labels.events.text.contains(expected),title)
 check(var_to_bytes(sim.events)==before,title+" leaves source log bytes intact")

func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
 hud=HUD.new();root.add_child(hud);hud.action_requested.connect(action);hud.set_art_frame(Rect2(0,40,1280,720))
 for spec in [[V1,P1],[V2,P2],[V3,P3],[V4,P4]]:
  var route:Dictionary=spec[1].route();var sim=spec[0].new()
  sim.configure(P3.starter_design(),P3.starter_launcher(),route,31)
  var original:PackedByteArray=var_to_bytes(sim.events)
  var data:Dictionary=live(sim);data.charging=true
  hud.render(fixture(route,data));await settle()
  for phase in ["charge","ignition","release","done"]:
   hud.update_launch(.8,phase);hud.update_flight(data);await settle()
   check(hud.flight_labels.events.text.is_empty() and not hud.content.get_node("FlightEventReceipt").visible,"no startup narration during "+str(route.control_version)+" "+phase)
  data.charging=false;data.elapsed=40.0;hud.update_flight(data)
  check(not hud.content.get_node("FlightEventReceipt").visible,"forty-second untouched startup log is quiet in "+str(route.control_version))
  check(var_to_bytes(sim.events)==original,"HUD leaves startup/launcher trace untouched in "+str(route.control_version))
  sim._damage_part(sim.parts[1],10.0,"collision");data=live(sim)
  hud.update_flight(data)
  check(hud.flight_labels.events.text.contains("首次受损") and hud.flight_labels.events.text.contains("HP"),"actual damage remains readable in "+str(route.control_version))
  original=var_to_bytes(sim.events)
  for i in 1000:hud.update_flight(data)
  check(var_to_bytes(sim.events)==original,"repeated HUD updates cannot mutate damage trace in "+str(route.control_version))
  # Fixed-step twins: only one is observed by the candidate HUD.
  var observed=spec[0].new();var untouched=spec[0].new()
  observed.configure(P3.starter_design(),P3.starter_launcher(),route,9);untouched.configure(P3.starter_design(),P3.starter_launcher(),route,9)
  for tick in 120:
   var axis:int=-500 if tick<60 else 200
   observed.set_pilot_input(axis,tick%20<10,false);untouched.set_pilot_input(axis,tick%20<10,false)
   observed.step(1.0/60.0);untouched.step(1.0/60.0);hud.update_flight(live(observed))
  check(var_to_bytes(observed.events)==var_to_bytes(untouched.events) and var_to_bytes(observed.telemetry)==var_to_bytes(untouched.telemetry) and var_to_bytes(observed.bodies)==var_to_bytes(untouched.bodies),"observed and untouched deterministic twins match in "+str(route.control_version))
 # These are real production emitters driven by disclosed synthetic fixtures.
 var route:Dictionary=flat_route();route.hazards=[{"x":202.0,"y":0.0,"radius":1.0,"health":100.0}]
 var sim=portal_fixture(route);cross(sim)
 inspect_real(sim,"出口被挡住","real occupied portal exit reason remains visible")
 var denied:Dictionary=live(sim);denied.elapsed=40.0;hud.update_flight(denied)
 check(hud.flight_labels.events.text.contains("出口被挡住"),"unresolved blocked exit remains visible beyond event lifetime")
 denied.wormhole_phase="otherworld";hud.update_flight(denied)
 check(hud.flight_labels.events.text.is_empty(),"later successful cargo transit releases obsolete blocked-exit warning")
 route=flat_route();route.wormhole_portal.station_energy_j=1.0;sim=portal_fixture(route);cross(sim)
 inspect_real(sim,"电量不足","real station-energy denial remains visible")
 var wide:Array=[]
 for x in range(-14,15):wide.append(P3.part(x+15,"cargo" if x==0 else "armor",x))
 sim=portal_fixture({},wide);cross(sim)
 inspect_real(sim,"缩小飞船轮廓","real oversize portal denial preserves recovery action")
 sim=portal_fixture()
 for body in sim.bodies:body.position.x+=205.0;body.velocity=Vector2.ZERO
 sim.step(1.0/120.0)
 inspect_real(sim,"错过了虫洞","real bypass failure remains visible")
 sim=V3.new();sim.configure([],[],P3.route(),1)
 inspect_real(sim,"没有货物","real launch cancellation survives settlement narration filter")
 sim=V3.new();sim.configure(P3.starter_design(),[P3.part(101,"spring",0)],P3.route(),1)
 inspect_real(sim,"缺少结构梁","real unsupported-launcher warning survives narrow launch filter")
 sim=V3.new();sim.configure([P3.part(1,"cargo",0),P3.part(2,"shield",-1,1,{"input_a":-2}),P3.part(3,"battery",-1)],[],P3.route(),1)
 sim.set_pilot_input(0,false,true);hud.render(fixture(sim.route,live(sim)))
 sim._damage_part(sim.parts[1],20,"collision");hud.update_flight(live(sim))
 check(hud.flight_labels.impact.text.contains("13.0 HP") and hud.flight_labels.impact.text.contains("20 J"),"actual funded shield HP and energy receipt preserved")
 check(hud.flight_labels.events.text.contains("碰撞"),"residual damage is shown alongside shield absorption")
 sim._damage_part(sim.parts[1],200,"collision");sim._check_status();sim._refresh_telemetry()
 inspect_real(sim,"委托失败","real destroyed cargo failure survives neighboring damage events")
 sim=V1.new();sim.configure(P1.starter_design(),[],P1.route(),1);sim.elapsed=100;sim._check_status();sim._refresh_telemetry()
 inspect_real(sim,"委托超时","real timeout failure remains visible")
 sim=portal_fixture();cross(sim)
 inspect_real(sim,"已通过晨星虫洞","actual portal passage remains a brief status event")
 for body in sim.bodies:body.position+=Vector2(sim.route.distance+.1,0)-sim.cargo_position();body.velocity=Vector2.ZERO
 sim._check_status();sim._refresh_telemetry()
 var receiver_trace:PackedByteArray=var_to_bytes(sim.events)
 hud.render(fixture(sim.route,live(sim)));hud.update_flight(live(sim))
 check(not hud.flight_labels.events.text.contains("自动投递") and not hud.flight_labels.events.text.contains("货箱 1"),"actual delivery uses native receipt cue without old solver bookkeeping")
 check(var_to_bytes(sim.events)==receiver_trace,"receipt cue leaves actual success source trace intact")
 check(sim.telemetry.delivered and hud.flight_labels.gate.text=="货物已签收" and hud.flight_labels.gate_detail.text=="苔光驿站","screen receipt cue requires actual delivered telemetry")
 for malformed in [false,"true",1,null]:
  var pending:Dictionary=live(sim);pending.delivered=malformed;pending.next_gate_index=-1;pending.next_gate_time=-1;hud.update_flight(pending)
  check(hud.flight_labels.gate.text!="货物已签收","missing/malformed delivered flag cannot announce receipt: "+str(malformed))
 # Lifetime and cached telemetry through pause, settings and physical resize.
 var delivery:Dictionary=live(sim);delivery.delivered=false;delivery.elapsed=20.0;delivery.events=["020.0s  推进喷口 损坏脱落。"]
 for geometry in [[Vector2i(1280,800),Rect2(0,40,1280,720),1],[Vector2i(1920,1080),Rect2(0,0,1920,1080),1],[Vector2i(3840,2160),Rect2(0,0,3840,2160),3]]:
  root.size=geometry[0];hud.set_art_frame(geometry[1]);delivery.elapsed=20.0;delivery.paused=false
  hud.render(fixture(sim.route,delivery));await settle()
  check(shown_text().contains("苔光驿站") and not shown_text().contains("城市货站 → 晨星虫洞"),"destination has a short native screen-space title at "+str(geometry[0]))
  check(hud.root.scale==Vector2.ONE*geometry[2] and geometry[1].encloses(hud._ascent_cue.get_global_rect()),"receipt cue remains in existing reserved band at "+str(geometry[0]))
  delivery.elapsed=24.0;delivery.paused=true;hud.update_flight(delivery);button("继续  [Esc / P]").grab_focus()
  var count:int=hud.content.get_child_count()
  for i in 20:hud.render(fixture(sim.route));await settle()
  check(hud.flight_labels.events.text.contains("损坏脱落") and hud.flight_labels.elapsed.text=="航时 24.0 s" and hud.flight_labels.status.text=="已暂停","layout-only rebuild preserves paused telemetry and event age at "+str(geometry[0]))
  check(root.gui_get_focus_owner()==button("继续  [Esc / P]") and hud.content.get_child_count()==count,"rebuild preserves pause focus and bounded nodes at "+str(geometry[0]))
  hud.settings_open=true;hud.render(fixture(sim.route));await settle()
  check(hud.is_blocking_modal() and hud._view_key(root.gui_get_focus_owner())=="settings:done","receipt changes do not steal settings safe focus at "+str(geometry[0]))
  hud.controller_back();await settle();delivery.elapsed=26.1;delivery.paused=false;hud.update_flight(delivery)
  check(not hud.content.get_node("FlightEventReceipt").visible,"receipt expires after resumed active time at "+str(geometry[0]))
  hud._on_resize();await settle()
  check(hud.flight_labels.events.text.is_empty() and hud.flight_labels.elapsed.text=="航时 26.1 s","resize cannot resurrect old damage at "+str(geometry[0]))
  var received:Dictionary=delivery.duplicate(true);received.delivered=true;received.events=[];hud.update_flight(received);await settle()
  check(hud.flight_labels.gate.text=="货物已签收" and hud._ascent_cue.get_global_rect().encloses(hud.flight_labels.gate.get_global_rect()),"received cue fits original native label band at "+str(geometry[0]))
  check(hud._ascent_cue.mouse_filter==Control.MOUSE_FILTER_IGNORE and hud.flight_labels.gate.mouse_filter==Control.MOUSE_FILTER_IGNORE,"destination/received cue remains pointer transparent at "+str(geometry[0]))
  for control in hud.content.find_children("*","Button",true,false):
   if control.is_visible_in_tree():check(geometry[1].encloses(control.get_global_rect()),"flight action remains in bounds: "+control.text)
  hud.render({"mode":"hub","settings":{"reduced_motion":true}});hud.render(fixture(sim.route,{"elapsed":0.0,"events":[]}));await settle()
  check(hud.flight_labels.events.text.is_empty() and hud.flight_labels.gate.text!="货物已签收","retry clears previous flight receipt and received state at "+str(geometry[0]))
 check(actions.is_empty(),"presentation updates emit no gameplay, pause, or dispatch action")
 var glyphs:bool=true
 for character in "货物已签收苔光驿站":glyphs=glyphs and hud.root.theme.default_font.has_char(character.unicode_at(0))
 check(glyphs,"all destination and received glyphs exist in unchanged native font")
 var receipt_ref:WeakRef=weakref(hud._flight_receipt)
 hud.queue_free();for i in 8:await process_frame
 check(receipt_ref.get_ref()==null,"HUD teardown releases receipt object")
 check(get_processed_tweens().is_empty(),"feedback adds no retained Tween or callback")
 print("FLIGHT_FEEDBACK_HUD passed=%d failed=%d input=synthetic_headless"%[passed,failed]);quit(1 if failed else 0)
