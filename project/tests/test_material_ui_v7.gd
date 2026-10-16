extends Node
## Small v7 presentation gate: all environments, one real pulse, retained edits.
const Profiles=[preload("res://scripts/pilot_delivery_profile_v7.gd"),preload("res://scripts/pilot_delivery_ascent_profile_v7.gd"),preload("res://scripts/pilot_delivery_rift_profile_v7.gd")]
const Sims=[preload("res://scripts/pilot_delivery_simulation_v7.gd"),preload("res://scripts/pilot_delivery_ascent_simulation_v7.gd"),preload("res://scripts/pilot_delivery_rift_simulation_v7.gd")]
const UI=preload("res://scripts/delivery_ui_v3.gd")
const Cells=preload("res://scripts/cell_combinations_v6.gd")
const Parts=preload("res://scripts/workshop_parts_v2.gd")
const Selected=preload("res://scripts/selected_device_presentation_v2.gd")
const HUD=preload("res://scripts/game_hud.gd")
const World=preload("res://scripts/world_view_2d.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for i in 4:await get_tree().process_frame
func piece(id:int,kind:String,x:int,y:int,param:float)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"target":4 if kind=="accelerator" else -1,"input_a":-2 if kind=="accelerator" else -1,"input_b":-1}
func ship()->Array:
 return [piece(1,"cargo",-1,0,100),piece(2,"accelerator",0,0,16),piece(3,"battery",-2,0,300),piece(4,"armor",1,0,90),piece(5,"beam",2,0,32),piece(6,"beam",3,0,32),piece(7,"spring",-1,1,60),piece(8,"damper",-1,-1,8)]
func snapshot(sim)->PackedByteArray:return var_to_bytes([sim.parts,sim.bodies,sim.links,sim.telemetry,sim.route,sim.elapsed,sim.status,sim.pilot_tick])
func run()->void:
 if OS.get_environment("SC_MATERIAL_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 for version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6"]:
  check(UI.applies({"control_version":version}),"old presentation identity retained: "+version)
 check(Parts.purpose("damper",false,"pilot-delivery-v6")=="抑制船体旋转；紧邻货物时进一步摊开加速度和碰撞冲击，不耗电。","v6 damper wording remains unchanged")
 for index in Profiles.size():
  var route:Dictionary=Profiles[index].route()
  var version:String=str(route.control_version)
  check(UI.applies(route) and UI.cell_rules(route) and Parts.compatible("spring",false,version),version+" enters existing delivery controls and passive mounts")
  check("分裂" in Parts.purpose("spring",false,version) and "重载" in Parts.purpose("damper",false,version) and "阻尼" in Parts.purpose("splitter",false,version),version+" explains material split and load response in existing descriptions")
  var design:Array=ship();var sim=Sims[index].new();sim.configure(design,[],route,42);sim.release_launcher(0,0);sim.set_free_flight_input(0,0,false,false,2)
  var before:PackedByteArray=snapshot(sim)
  var tool:Dictionary=Selected.state(sim);var preview:Dictionary=tool.get("accelerator_preview",{})
  var details:Dictionary=UI.accelerator_details(preview)
  check(preview.get("can_fire",false) and not details.is_empty() and snapshot(sim)==before,version+" live tool consumes real read-only material-aware pulse prediction")
  var world=World.new();world.mode="workshop";world._live_design=design.duplicate(true);world.set_meta("assembly_context","craft")
  var hud=HUD.new();add_child(hud);hud.accelerator_preview_changed.connect(world.present_accelerator_preview)
  var state:Dictionary={"mode":"workshop","control_version":version,"activeorder":route,"assembly_mode":"craft","parts":design,"selectedpart":design[1],"settings":{"reduced_motion":true},"has_accepted_contract":true}
  hud.render(state);await settle()
  check(hud._accelerator_workshop_labels.impact.text==details.impact and world.accelerator_preview_snapshot().payload_ids==preview.payload_ids,version+" workshop matches live prediction and highlights all payload cells")
  if index==0:
   var slider:HSlider=hud.content.find_child("PartParameterSlider",true,false);slider.grab_focus();var slider_id:int=slider.get_instance_id();var count:int=hud._accelerator_blueprint_calls
   # Mirror only Main's already-tested authoritative sync after a sanitized
   # model edit, without rebuilding the control or inventing preview numbers.
   design[1].param=8;hud.sync_workshop_preview(design,design[1])
   var changed:Dictionary=Cells.preview_blueprint(design,route,2)
   check(hud._accelerator_workshop_labels.cost.text==UI.accelerator_details(changed).cost and hud._accelerator_blueprint_calls==count+1 and slider.get_instance_id()==slider_id and slider.has_focus(),"v7 retains dev25 authoritative local refresh with the same focused control")
   var predicted:float=float(preview.cargo_impacts[0].integrity_after)
   sim._accelerate(sim.parts[2],sim.parts[4],sim.body_for_part(2),1.0/120.0)
   check(absf(float(sim.parts[1].hp)/float(sim.parts[1].max_hp)-predicted)<.000001,"material-aware displayed cargo forecast equals the actual same pulse")
  state.mode="flight";state.flight=sim.telemetry.duplicate(true);state.flight.selected_tool=Selected.state(sim);hud.render(state);await settle()
  check(hud.flight_labels.has("integrity") and hud.flight_labels.has("tool_impact") and UI.coasting({"unpowered_coasting":true,"flight_status":"running"},route),version+" keeps one cargo health bar active preview and power-loss coasting")
  if index>0:
   check(hud.flight_labels.has("receipt_speed") and not UI.receipt_speed({"speed":5.0,"destination_distance":40.0},route).is_empty(),version+" retains the actual approaching-receiver speed limit")
  hud.queue_free();world.free();await settle()
 print("MATERIAL_UI_V7 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
