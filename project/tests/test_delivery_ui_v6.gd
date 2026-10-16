extends Node
## Minimal actual group launch/coast UI bridge. No Main, save, GUI or full import.
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Cells=preload("res://scripts/cell_combinations_v6.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
const Selected=preload("res://scripts/selected_device_presentation_v2.gd")
const Workshop=preload("res://scripts/workshop_parts_v2.gd")
const HUD=preload("res://scripts/game_hud.gd")
var passed:int=0
var failed:int=0
var hud
var actions:Array=[]
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for i in 3:await get_tree().process_frame
func part(id:int,kind:String,x:int,y:int=0)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":6.0 if kind=="accelerator" else 300.0 if kind=="battery" else 0.0,"target":1 if kind=="accelerator" else -1,"input_a":-2 if kind=="accelerator" else -1,"input_b":-1}
func ship()->Array:return [part(1,"cargo",1),part(2,"accelerator",0),part(3,"battery",-1)]
func text_of(node:Node)->String:
 var result:String=node.text+"\n" if node is Label or node is Button else ""
 for child in node.get_children():result+=text_of(child)
 return result
func action_button(action:String)->Button:
 for button in hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("view_key","")).begins_with("action:"+action+":"):return button
 return null
func run()->void:
 if OS.get_environment("SC_CELL_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 var route:Dictionary=Profile.route({"distance":20.0,"delivery_radius":1.0,"weight":1.0})
 var design:Array=ship();var sim=Sim.new();sim.configure(design,[],route,42)
 var preview:Dictionary=Cells.preview_blueprint(design,route,2)
 var live:Dictionary=sim.preview_accelerator(2)
 check(preview.can_fire and preview.payload_ids==[1] and is_equal_approx(preview.payload_mass,3.0),"authoritative blueprint permits actual bare cargo mass")
 check(preview==live,"blueprint and live group preview agree before action")
 sim.set_free_flight_input(0,0,false,false,2)
 var selected:Dictionary=Selected.state(sim)
 check(selected.accelerator_preview==live and "1 件" in selected.status and "3.0 kg" in selected.status,"selected device shows actual payload group and mass")
 var group:Array=ship();group.append(part(4,"battery",2))
 var heavy:Dictionary=Profile.route({"distance":100.0,"weight":3.0})
 var grouped:Dictionary=Cells.preview_blueprint(group,heavy,2)
 check(grouped.payload_ids==[1,4] and grouped.payload_mass>9.0,"group preview includes real order cargo weight plus carried battery")
 check("2 件" in UI.accelerator_copy(grouped) and "#1, #4" in UI.accelerator_copy(grouped),"group summary identifies exactly the load-side IDs")
 var bypass:Array=ship();bypass.append(part(4,"beam",0,1));bypass.append(part(5,"beam",1,1))
 var blocked:Dictionary=Cells.preview_blueprint(bypass,route,2)
 check(blocked.reason=="bypass_connection" and UI.accelerator_copy(blocked)=="旁路仍相连，不能弹射","real bypass blocks with concise Chinese explanation")
 check("失败" not in Workshop.readiness(design[1],design,true,false,Profile.VERSION).text and "滑行" in Workshop.purpose("accelerator",false,Profile.VERSION),"v6 does not label legal bare cargo as fatal")
 check("失败" in Workshop.readiness(design[1],design,true,false,"pilot-delivery-v3").text,"legacy detachment warning remains unchanged")
 var controls:Array=Workshop.local_controls(design[1],false,Profile.VERSION)
 check(controls.any(func(row):return row.get("label")=="弹出哪侧整组"),"target picker clearly selects the group side")
 for reason in ["wrong_protocol","target_not_linked","spent","bypass_connection","no_payload","no_impulse","insufficient_energy","exit_blocked"]:
  check(not reason in UI.accelerator_copy({"reason":reason}),"denial localized: "+reason)
 hud=HUD.new();add_child(hud);hud.action_requested.connect(func(name,payload):actions.append([name,payload]))
 var fixture:Dictionary={"mode":"workshop","control_version":Profile.VERSION,"activeorder":route,"assembly_mode":"craft","parts":group,"selectedpart":group[1],"settings":{"reduced_motion":true},"has_accepted_contract":true}
 fixture.activeorder=heavy
 hud.render(fixture);await settle()
 var readiness:Label=hud.content.find_child("ModuleReadiness",true,false)
 check(readiness!=null and readiness.text==UI.accelerator_copy(grouped),"inspector uses real route-weight helper snapshot without local mass arithmetic")
 check("弹出货舱会断开供电" not in text_of(hud.content),"new inspector removes legacy immediate-failure warning")
 sim.release_launcher(0,0);sim.set_free_flight_input(0,0,false,true,2);sim.step(1.0/120.0)
 check(sim.status=="running" and sim.telemetry.unpowered_coasting and sim.parts[2].spent,"real paid accelerator leaves live unpowered cargo coasting")
 check(sim.telemetry.accelerator_last_event.payload_ids==preview.payload_ids,"fired payload is the exact previewed group")
 fixture.mode="flight";fixture.activeorder=route;fixture.flight=sim.telemetry.duplicate(true)
 hud.render(fixture);await settle()
 check(hud._free_flight_mode() and hud._force_flight_mode() and hud._delivery_mode(),"new protocol retains existing flight controls and health")
 check(hud.flight_labels.energy_warning.text=="无电滑行 · 主动装置需电" and hud.flight_labels.status.text!="配送失败","actual no-power state explains coasting without declaring failure")
 var warning:Label=hud.flight_labels.energy_warning
 check(warning.get_theme_font("font").get_string_size(warning.text,HORIZONTAL_ALIGNMENT_LEFT,-1,warning.get_theme_font_size("font_size")).x<=warning.size.x,"short coasting warning fits energy card")
 var abort:Button=action_button("abort")
 check(abort!=null and not abort.disabled and abort.is_visible_in_tree(),"existing manual abort stays available while powerless")
 actions.clear();abort.pressed.emit();check(actions.size()==1 and actions[0][0]=="abort","abort emits the unchanged normal settlement action")
 for tick in 1000:
  sim.set_free_flight_input(0,0);sim.step(1.0/120.0)
  if sim.status!="running":break
 hud.update_flight(sim.telemetry);await settle()
 check(sim.status=="success" and hud.flight_labels.status.text=="货物已签收","actual powerless payload reaches receiver and HUD reports success")
 check("无电滑行" not in hud.flight_labels.energy_warning.text,"completed delivery clears running-only coasting notice")
 var old:Dictionary=fixture.duplicate(true);old.control_version="pilot-delivery-v3";old.activeorder.control_version="pilot-delivery-v3";old.flight={"flight_status":"failed","free_failure":"usable_energy_empty","power_failure":{"code":"no_battery"},"delivery_integrity":1.0,"energy_remaining":0.0,"energy_fraction":0.0}
 hud.render(old);await settle()
 check(hud.flight_labels.status.text=="配送失败" and "滑行" not in hud.flight_labels.energy_warning.text,"old contract retains its actual terminal power rule")
 for version in UI.CELL_VERSIONS:check(UI.applies({"control_version":version}) and Workshop.compatible("spring",false,version),"new explicit version retains delivery modules: "+version)
 hud.queue_free();await settle()
 print("DELIVERY_UI_V6 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
