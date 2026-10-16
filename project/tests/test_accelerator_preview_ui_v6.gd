extends Node
## Narrow shared impulse prediction, all-group projection and invalidation gate.
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Cells=preload("res://scripts/cell_combinations_v6.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
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
func part(id:int,kind:String,x:int,y:int=0,param:float=0.0)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"target":4 if kind=="accelerator" else -1,"input_a":-2 if kind=="accelerator" else -1,"input_b":-1}
func ship(strength:float=16.0)->Array:
 return [part(1,"cargo",-1),part(2,"accelerator",0,0,strength),part(3,"battery",-2,0,300),part(4,"armor",1),part(5,"beam",2),part(6,"beam",3)]
func snapshot(sim)->PackedByteArray:return var_to_bytes([sim.parts,sim.bodies,sim.links,sim.telemetry,sim.route,sim.elapsed,sim.status,sim.pilot_tick])
func fit(label:Label)->bool:return label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x<=label.size.x
func run()->void:
 if OS.get_environment("SC_PULSE_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 var route:Dictionary=Profile.route({"distance":100.0,"min_delivery_integrity":.9,"cargo_safe_acceleration":1.0,"cargo_damage_per_excess_mps":6.0})
 var design:Array=ship();var sim=Sim.new();sim.configure(design,[],route,42);sim.release_launcher(0,0);sim.set_free_flight_input(0,0,false,false,2)
 var before:PackedByteArray=snapshot(sim)
 var tool:Dictionary=Selected.state(sim);var preview:Dictionary=tool.accelerator_preview
 var details:Dictionary=UI.accelerator_details(preview)
 check(not details.is_empty() and preview.can_fire and details.below_minimum,"real high-pulse prediction warns below exact 90% without preventing fire")
 check(preview.payload_ids==[4,5,6] and preview.ammo_part_ids==[4,5,6] and preview.ammo_cost==45.0,"preview sources actual armor plus two beam ammunition cost")
 check("45" in details.cost and "3格原价" in details.cost and "后续" in details.scope,"cost identifies consumed group and bounds forecast to this trigger")
 check(snapshot(sim)==before,"selected device and formatting do not change complete simulation snapshot")
 var world=World.new();world.mode="workshop";world._live_design=design.duplicate(true);world.set_meta("assembly_context","craft");world.smooth_zoom=1.0
 var hud=HUD.new();add_child(hud);hud.accelerator_preview_changed.connect(world.present_accelerator_preview)
 var fixture:Dictionary={"mode":"workshop","control_version":Profile.VERSION,"activeorder":route,"assembly_mode":"craft","parts":design,"selectedpart":design[1],"settings":{"reduced_motion":true},"has_accepted_contract":true}
 hud.render(fixture);await settle()
 var visual:Dictionary=world.accelerator_preview_snapshot()
 check(visual.visible and visual.payload_ids==[4,5,6] and visual.boxes.size()==3,"workshop highlights every payload cell instead of target alone")
 check(visual.arrows.size()==2 and visual.arrows[0].direction==preview.payload_delta_v and visual.arrows[1].direction==preview.carrier_delta_v,"both arrows project actual payload and carrier delta-v")
 var impact:Label=hud.content.find_child("AcceleratorImpactPreview",true,false)
 check(impact!=null and "不合格" in impact.text and impact.get_theme_color("font_color")==hud.CORAL,"workshop below-line pulse is visibly red")
 var calls:int=hud._accelerator_blueprint_calls
 for frame in 60:await get_tree().process_frame
 hud.render(fixture);await settle()
 check(hud._accelerator_blueprint_calls==calls,"unchanged selection over 60 frames plus render does not rebuild preview solver")
 fixture.parts=ship(2.0);fixture.selectedpart=fixture.parts[1];world._live_design=fixture.parts.duplicate(true)
 hud.render(fixture);await settle()
 check(hud._accelerator_blueprint_calls==calls+1,"changing actual accelerator setting recomputes once")
 impact=hud.content.find_child("AcceleratorImpactPreview",true,false)
 check(not "不合格" in impact.text and impact.get_theme_color("font_color")==hud.TEAL,"lower actual impulse recomputes green cargo forecast")
 fixture.selectedpart=fixture.parts[0];hud.render(fixture);await settle()
 check(not world.accelerator_preview_snapshot().visible,"selecting another module clears all old payload marks")
 fixture.selectedpart=fixture.parts[1];fixture.activeorder.weight=2.0;hud.render(fixture);await settle()
 check(hud._accelerator_blueprint_calls==calls+2,"changing real order mass invalidates cache")
 # Runtime feeds the one owner snapshot into HUD and world; no second solver.
 world.mode="flight";world.flight_nodes={}
 for id in sim.parts:
  var sprite:Sprite2D=Sprite2D.new();sprite.texture=load("res://assets/2d_v5/modules/cargo.png")
  sprite.position=world.flight_origin+sim.part_world_position(id)*72.0;sprite.rotation=.25;sprite.scale=Vector2.ONE*72.0/Vector2(sprite.texture.get_size());world.add_child(sprite);world.flight_nodes["p"+str(id)]=sprite
 fixture.mode="flight";fixture.activeorder=route;fixture.flight=sim.telemetry.duplicate(true);fixture.flight.selected_tool=tool
 before=snapshot(sim);hud.render(fixture);await settle()
 visual=world.accelerator_preview_snapshot()
 check(visual.payload_ids==[4,5,6] and visual.boxes[0].position==world.flight_nodes.p4.position and visual.boxes[0].angle==world.flight_nodes.p4.rotation,"flight marks every exact live sprite position and angle")
 check(snapshot(sim)==before,"flight preview projection leaves actual positions energy HP and events unchanged")
 check(hud.flight_labels.tool_impact.text==details.impact and hud.flight_labels.tool_cost.text==details.cost,"flight and workshop show the same predicted HP and actual cost source")
 for key in ["tool_state","tool_motion","tool_impact","tool_cost","tool_scope","tool_keys"]:check(fit(hud.flight_labels[key]),"runtime line fits existing tool card: "+key)
 var panel:Control=hud.content.get_node("SelectedFlightTool")
 check(hud.flight_labels.tool_keys.get_global_rect().end.y<=panel.get_global_rect().end.y,"expanded selected-tool details keep trigger keys inside card")
 check(hud.flight_labels.integrity.text=="100%","forecast does not replace current cargo-only health")
 var predicted:float=float(preview.cargo_impacts[0].integrity_after)
 sim._accelerate(sim.parts[2],sim.parts[4],sim.body_for_part(2),1.0/120.0)
 check(absf(float(sim.parts[1].hp)/float(sim.parts[1].max_hp)-predicted)<.000001 and sim.parts[2].spent,"red prediction remains actionable and matches actual same-trigger cargo HP")
 check(is_equal_approx(sim.telemetry.ammo_cost,preview.ammo_cost) and is_equal_approx(sim.telemetry.energy_used,preview.energy_required),"same trigger actually pays displayed energy and ammo")
 fixture.flight=sim.telemetry.duplicate(true);fixture.flight.selected_tool=Selected.state(sim);hud.update_flight(fixture.flight);await settle()
 check(not world.accelerator_preview_snapshot().visible and not hud.flight_labels.tool_impact.visible,"spent accelerator clears future forecast and old highlights")
 fixture.control_version="pilot-delivery-v3";fixture.activeorder.control_version="pilot-delivery-v3";fixture.flight.selected_tool={"name":"加速器","status":"可用","direction":"→"}
 hud.render(fixture);await settle()
 check(not hud.flight_labels.has("tool_impact") and not world.accelerator_preview_snapshot().visible,"legacy contract tool layout stays unchanged")
 hud.queue_free();world.free();await settle()
 print("ACCELERATOR_PREVIEW_UI_V6 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
