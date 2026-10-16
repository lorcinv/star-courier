extends Node
## Real native save copy, real slider signals and Main edit paths; no UI render
## substitutes for a parameter commit. The seed stays outside the source pack.
const Main=preload("res://scripts/main.gd")
const Cells=preload("res://scripts/cell_combinations_v6.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
const Parts=preload("res://scripts/workshop_parts_v2.gd")
var passed:int=0
var failed:int=0
var main
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for i in 4:await get_tree().process_frame
func current()->Dictionary:return Cells.preview_blueprint(main.design,main.economy.active_contract(),1010)
func matches()->bool:
 var expected:Dictionary=current()
 return var_to_bytes(main.hud._accelerator_blueprint_value)==var_to_bytes(expected) and main.hud.state.parts==main.design
func select(id:int)->void:
 main.selected_id=id;main.refresh_workshop_selection()
func run()->void:
 if OS.get_environment("SC_PULSE_EDIT_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 main=Main.new();main.entry_require_existing_save=true;main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main);main.set_process(false)
 check(not main.economy.review_load_blocked and main.economy.day==2 and main.economy.credits==539,"unchanged actual native save loads day 2 balance 539")
 if main.economy.review_load_blocked:finish();return
 main.page="workshop";main.assembly_mode="craft";main.selected_id=1010;main.render();await settle()
 var hud=main.hud
 var slider:HSlider=hud.content.find_child("PartParameterSlider",true,false)
 check(slider!=null and slider.value==20 and current().payload_ids.size()==3 and is_equal_approx(current().payload_mass,13),"actual saved accelerator and three-cell 13 kg payload are selected")
 if slider==null:finish();return
 slider.grab_focus()
 var slider_id:int=slider.get_instance_id();var calls:int=hud._accelerator_blueprint_calls
 slider.value=8
 check(main.selected_part().param==8 and matches(),"real slider value_changed reaches Main then syncs authoritative blueprint")
 check(hud._accelerator_blueprint_calls==calls+1 and slider.get_instance_id()==slider_id and slider.has_focus(),"one commit recalculates once without replacing slider or losing focus")
 var low_energy:float=current().energy_required
 check(hud._accelerator_workshop_labels.cost.text==UI.accelerator_details(current()).cost,"same commit updates displayed energy and instantaneous costs")
 slider.drag_started.emit();slider.value=16;slider.value=20
 check(main.selected_part().param==8 and hud._accelerator_blueprint_calls==calls+1,"in-progress drag does not repeatedly configure preview solver")
 slider.drag_ended.emit(true)
 check(main.selected_part().param==20 and matches() and current().energy_required>low_energy,"real drag release 8 to 20 refreshes the authoritative prediction immediately")
 check(hud._accelerator_blueprint_calls==calls+2 and slider.get_instance_id()==slider_id and slider.has_focus(),"drag release computes once and retains original focused slider")
 var visual:Dictionary=main.world.accelerator_preview_snapshot();var predicted:Dictionary=current()
 check(visual.payload_ids==predicted.payload_ids and visual.arrows[0].direction==predicted.payload_delta_v and visual.arrows[1].direction==predicted.carrier_delta_v,"world groups and both arrows consume the new committed impulse")
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(float(saved.design.filter(func(p):return int(p.id)==1010)[0].param)==20,"actual fast path persists the same displayed parameter")
 for frame in 60:await get_tree().process_frame
 check(hud._accelerator_blueprint_calls==calls+2,"60 idle frames do not poll or rebuild the solver")
 hud.render(hud.state);await settle()
 check(matches() and hud._accelerator_blueprint_calls==calls+2,"later same-state render cannot restore the old cached blueprint")
 var choice:OptionButton=hud.content.find_child("PartTargetChoice",true,false)
 var options:Array=Parts.target_options(main.selected_part(),main.design)
 var battery_index:int=-1
 for i in options.size():
  if int(options[i].id)==1011:battery_index=i
 check(battery_index>=0,"actual target picker offers the adjacent battery side")
 if battery_index>=0:
  choice.item_selected.emit(battery_index);await settle()
  check(int(main.selected_part().target)==1011 and matches(),"actual target selection updates both saved part and copied connectivity")
  check(main.world.accelerator_preview_snapshot().payload_ids==current().payload_ids,"target-side change immediately replaces all group highlights")
 hud._act("set_input",{"id":1010,"key":"target","source":1});await settle()
 check(matches(),"direct input fast path also shares authoritative invalidation")
 calls=hud._accelerator_blueprint_calls
 var rotate:Button=hud._workshop_labels.rotate;rotate.pressed.emit();await settle()
 check(int(main.selected_part().rot)==1 and matches() and hud._accelerator_blueprint_calls==calls+1,"actual rotate action invalidates the same blueprint cache once")
 select(1011);await settle()
 check(not main.world.accelerator_preview_snapshot().visible,"fast selection away clears every previous payload highlight")
 var remove:Button=hud._workshop_labels.remove;remove.pressed.emit();await settle();select(1010);await settle()
 var empty:Dictionary=current()
 check(not empty.can_fire and empty.reason=="insufficient_energy" and matches(),"actual battery removal and fast reselection recompute loss of supply")
 check(hud._accelerator_workshop_labels.status.text=="电量不足","unpowered trigger explicitly explains refusal")
 check(not hud._accelerator_workshop_labels.impact.visible,"unpowered trigger hides stale instantaneous cargo damage")
 check(not hud._accelerator_workshop_labels.cost.visible,"unpowered trigger hides stale instantaneous cost")
 check(main.world.accelerator_preview_snapshot().arrows.is_empty(),"unpowered trigger removes both action arrows while valid group outlines may remain")
 finish()
func finish()->void:
 if is_instance_valid(main):main.queue_free();await settle()
 print("ACCELERATOR_PREVIEW_EDIT_EVENTS_V6 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
