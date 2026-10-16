extends SceneTree
## Real Main, world, HUD, stage, support presenter and disk saves. Input is sent
## to the GUI-local adapter boundary; event ownership is a separate dev06 suite.
## Node identities and counters establish avoided work, never FPS or hand-feel.
const Parts=preload("res://scripts/workshop_parts_v2.gd")
const CELL:float=72.0
class CountingMain extends "res://scripts/main.gd":
 var full_renders:int=0
 var save_calls:int=0
 func render() -> void:
  full_renders+=1;super.render()
 func save_game() -> bool:
  save_calls+=1;return super.save_game()
var game
var passed:int=0
var failed:int=0
var max_grab_error_px:float=0.0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(count:int=3) -> void:
 for unused in count:await process_frame
func button(at:Vector2,pressed:bool) -> InputEventMouseButton:
 var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;return event
func motion(at:Vector2,held:bool=true) -> InputEventMouseMotion:
 var event:=InputEventMouseMotion.new();event.position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;return event
func local_at(cell:Vector2i,grab:Vector2=Vector2.ZERO) -> Vector2:
 var pixel:Vector2=game.view.get_canvas_transform()*(game.world.assembly_origin+Vector2(cell)*CELL+grab)
 return game.view_container.pixel_to_screen(pixel)-game.view_container.display.position
func disk_state() -> Dictionary:
 var result:Dictionary={}
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  result[name]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
 return result
func model_state() -> Dictionary:
 return {"design":game.design.duplicate(true),"launcher":game.launcher.duplicate(true),"inventory":game.economy.inventory.duplicate(true),"credits":game.economy.credits,"next_id":game.next_id,"undo":game.undo_history.duplicate(true),"saves":game.save_calls,"disk":disk_state()}
func structure_ids() -> Dictionary:
 var parts:Dictionary={};var joints:Dictionary={}
 for node in game.world.ship_root.get_children():
  if node.has_meta("part_id"):parts[int(node.get_meta("part_id"))]=node.get_instance_id()
  if node.has_meta("structural_edge"):joints[str(node.get_meta("structural_edge"))]=node.get_instance_id()
 return {"parts":parts,"joints":joints}
func support_ids() -> Array:
 var result:Array=[game.world.workshop_support.get_instance_id()]
 for node in game.world.workshop_support.find_children("*","",true,false):result.append(node.get_instance_id())
 return result
func selected_inspector(id:int) -> bool:
 if int(game.hud.state.selectedpart.get("id",-1))!=id:return false
 for node in game.hud.content.find_children("*","Control",true,false):
  if str(node.get_meta("view_key",""))=="inspector:"+str(id):return true
 return false
func check_overlays(id:int,label:String) -> void:
 var chosen:Dictionary={}
 for part in game.active_design():
  if int(part.id)==id:chosen=part;break
 var grid=game.world.grid
 check(game.world.selected==id and grid.selected_cell==Vector2(chosen.x,chosen.y),label+" selected outline follows the installed cell")
 var mechanical:bool=game.assembly_mode=="craft" and str(chosen.type) in ["splitter","coupler","accelerator"]
 var options:Array=Parts.target_options(chosen,game.active_design()) if mechanical else []
 var expected:Array=[]
 for option in options:expected.append(Vector2(option.part.x,option.part.y))
 var target:Dictionary=Parts.effective_target(chosen,game.active_design()) if mechanical else {}
 check(grid.tool_target_cells==expected,label+" available mechanical targets match the current selection")
 if target.is_empty():check(not is_finite(grid.tool_selected_target.x) and not grid.tool_target_valid,label+" clears the previous mechanical target")
 else:
  var valid:bool=int(target.id) in options.map(func(row):return int(row.id)) and (int(chosen.get("target",-1))<0 or int(chosen.target)==int(target.id))
  check(grid.tool_selected_target==Vector2(target.x,target.y) and grid.tool_target_valid==valid,label+" preserves explicit target validity")
func setup_design() -> void:
 game.workshop_input.cancel();game.page="workshop";game.assembly_mode="craft";game.selected_id=5;game.chosen_type="battery"
 game.design=[game.part(5,"battery",0,0),game.part(6,"coupler",1,0),game.part(7,"beam",2,0),game.part(8,"accelerator",1,-1),game.part(9,"beam",-1,1),game.part(10,"splitter",0,-1)]
 game.design[1].target=7;game.design[1].rot=2;game.design[1].param=17;game.design[1].input_a=-1;game.design[1].input_b=5
 game.design[3].target=9 # Saved explicit non-neighbor must remain invalid.
 game.design[5].target=5
 game.launcher=[Parts.new_part(20,"beam",0,0,[],true,true),Parts.new_part(21,"spring",1,0,[],true,true)]
 game.next_id=30;game.undo_history.clear();game.hud.settings_open=false
 game.render();game.workshop_input.fit();game.save_game()
func select_at(id:int,cell:Vector2i,label:String) -> void:
 var before:Dictionary=model_state();var ids:Dictionary=structure_ids();var support:Array=support_ids()
 var full:int=game.full_renders;var hud_generation:int=game.hud._render_generation
 var source:Vector2=local_at(cell)
 game.workshop_input.handle(button(source,true))
 check(game.selected_id==id and selected_inspector(id),label+" refreshes real inspector")
 check(game.full_renders==full and game.hud._render_generation==hud_generation+1,label+" refreshes HUD once without Main.render")
 check(structure_ids()==ids and support_ids()==support,label+" preserves module, joint and support node identities")
 check_overlays(id,label)
 game.workshop_input.handle(button(source,false))
 check(model_state()==before and game.workshop_input.camera.gesture.is_empty(),label+" selection-only click has no durable edit")
func matrix_case(extent:Vector2i,density:String) -> void:
 root.size=extent;game.settings.pixel_density=density;game._apply_quality();await settle()
 setup_design();await settle()
 # Open the existing palette without changing selection. The next different-part
 # pickup must close it, as full HUD render did before this optimization.
 game.hud.palette_open=true;game.hud.render(game.hud.state);game.workshop_input.after_render();await settle()
 var a=game.workshop_input
 a.controller_begin();a.controller_pickup()
 check(a.controller_moving(),"fixture starts with controller pickup "+str(extent)+" "+density)
 var before:Dictionary=model_state();var ids:Dictionary=structure_ids();var supports:Array=support_ids();var support_state:Dictionary=game.world.workshop_support.debug_snapshot()
 var full:int=game.full_renders;var hud_generation:int=game.hud._render_generation
 var center:Vector2=a.camera.center;var zoom:float=a.camera.zoom;var canvas:Transform2D=game.view.get_canvas_transform()
 var grab:Vector2=Vector2(17,-11);var source:Vector2=local_at(Vector2i(1,0),grab)
 var stage=game.view_container
 check(stage.pixel_scale>=2 and stage.display_rect.position.y>0,"fixture is integer-scaled and letterboxed "+str(extent)+" "+density)
 check(a._allowed_screen(stage.display.position+source),"off-center press reaches unobscured workbench")
 a.handle(button(source,true))
 check(game.selected_id==6 and a.camera.gesture=="move" and not a.controller_moving(),"different-module mouse press selects and cancels controller pickup")
 check(game.full_renders==full and game.hud._render_generation==hud_generation+1,"different-module press performs one HUD refresh and no Main.render")
 check(structure_ids()==ids,"different-module press preserves every real module and joint instance")
 check(support_ids()==supports and game.world.workshop_support.debug_snapshot()==support_state,"different-module press preserves grounded support presentation")
 check(selected_inspector(6) and not game.hud.palette_open,"new inspector is shown and palette closes")
 check(a.camera.center==center and a.camera.zoom==zoom and game.view.get_canvas_transform()==canvas,"pickup preserves live camera center, zoom and canvas transform")
 check(a._grab_offset.distance_to(grab)<.001,"pickup preserves original off-center world grab offset")
 check_overlays(6,"coupler pickup")
 check(model_state()==before and not game.world.workshop_drag_snapshot().visible,"press has no ghost displacement, undo or disk write")
 var destination:Vector2=local_at(Vector2i(1,1),grab+Vector2(3,2))
 a.handle(motion(destination))
 var ghost:Dictionary=game.world.workshop_drag_snapshot()
 var pixel:Vector2=stage.screen_to_pixel(stage.display.position+destination)
 var expected:Vector2=game.world.workshop_point_at(pixel)-grab
 var error:float=(game.view.get_canvas_transform()*ghost.ghost_center-game.view.get_canvas_transform()*expected).length()*stage.pixel_scale
 max_grab_error_px=maxf(max_grab_error_px,error)
 check(ghost.visible and ghost.valid and ghost.source_id==6 and error<.01,"first held motion follows exact transformed pointer with original grab offset")
 check(ghost.target_center==game.world.assembly_origin+Vector2(1,1)*CELL,"preview snaps the intended empty destination")
 check(structure_ids()==ids and game.full_renders==full and model_state()==before,"held motion preserves all nodes and has no pre-drop writes")
 a.handle(button(destination,false))
 check(game.selected_part().x==1 and game.selected_part().y==1 and game.save_calls==int(before.saves)+1 and game.undo_history.size()==1,"first release commits once with one save and undo")
 var expected_design:Array=before.design.duplicate(true);expected_design[1].y=1
 check(game.design==expected_design and game.launcher==before.launcher and game.economy.inventory==before.inventory and game.economy.credits==before.credits,"drop changes only the selected module cell and retains parameters, wiring, stock and money")
 check(game.full_renders==full+1 and structure_ids()!=ids,"real drop retains the full world edit refresh")
 check(game.undo_history[0].design==before.design and game.undo_history[0].launcher==before.launcher,"release records exact pre-drag designs for undo")
 check(not game.world.workshop_drag_snapshot().visible and a.camera.gesture.is_empty(),"release consumes gesture and ghost")
 var saved:Dictionary=model_state();a.handle(button(destination,false))
 check(model_state()==saved,"duplicate release cannot repeat the transaction")
 var persisted=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(persisted is Dictionary and persisted.design==JSON.parse_string(JSON.stringify(game.design)),"one release is represented in real save bytes")
 game.undo_assembly()
 check(game.design==before.design and game.launcher==before.launcher and game.undo_history.is_empty() and game.save_calls==int(before.saves)+2,"one real undo restores exact original designs and saves once")
func cancellation_case(kind:String) -> void:
 setup_design();await settle()
 var a=game.workshop_input;var before:Dictionary=model_state()
 var source:Vector2=local_at(Vector2i(1,0),Vector2(17,-11));a.handle(button(source,true))
 var dest:Vector2=local_at(Vector2i(1,1),Vector2(17,-11));a.handle(motion(dest))
 check(a.camera.gesture=="move" and game.world.workshop_drag_snapshot().visible,kind+" cancellation starts with held ghost")
 match kind:
  "focus":game._on_focus_exited();game._on_focus_entered()
  "modal":game.hud.settings_open=true;a.tick();game.hud.settings_open=false
  "lost-button":a.handle(motion(dest,false))
  "explicit":a.cancel()
 a.handle(button(dest,false))
 check(model_state()==before and a.camera.gesture.is_empty() and not game.world.workshop_drag_snapshot().visible,kind+" cancellation keeps exact disk/model/undo state")
 var source_node:CanvasItem=game.world.ship_root.get_node("Part6")
 check(is_equal_approx(source_node.self_modulate.a,1.0),kind+" cancellation restores source sprite opacity")
func run() -> void:
 # Refuse anything except an empty, isolated runner-owned data directory.
 if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/courier-dev06-"):
  print("Fresh isolated /tmp/courier-dev06-* XDG_DATA_HOME required");quit(2);return
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+name):
   print("Fixture refuses an existing save: ",name);quit(2);return
 game=load("res://scenes/main.tscn").instantiate();game.set_script(CountingMain);root.add_child(game);game.set_process(false);await settle(5)
 game.world.set_process(false)
 for item in [{"extent":Vector2i(1280,800),"density":"low"},{"extent":Vector2i(1920,1200),"density":"balanced"},{"extent":Vector2i(2560,1600),"density":"low"}]:await matrix_case(item.extent,item.density)
 setup_design();await settle()
 select_at(8,Vector2i(1,-1),"invalid-explicit accelerator")
 check(not game.world.grid.tool_target_valid,"saved non-neighbor target stays invalid and is never silently repaired")
 select_at(10,Vector2i(0,-1),"splitter")
 select_at(5,Vector2i(0,0),"ordinary battery")
 # Shared selected-part formatting still agrees with the original full renderer.
 var selected_data:Dictionary=game.hud.state.selectedpart.duplicate(true);game.render()
 check(game.hud.state.selectedpart==selected_data,"selection-only inspector data exactly matches full render")
 game.assembly_mode="launcher";game.selected_id=20;game.render();game.workshop_input.fit();await settle()
 select_at(21,Vector2i(1,0),"launcher spring")
 for kind in ["focus","modal","lost-button","explicit"]:await cancellation_case(kind)
 game.queue_free();await settle(5)
 if passed+failed!=117:check(false,"all selection pickup assertions ran")
 print("WORKSHOP_SELECTION_PICKUP_DEV06 passed=%d failed=%d max_grab_error_screen_px=%.9f input=adapter_gui_local real_main_world_hud=true fps_claim=false"%[passed,failed,max_grab_error_px])
 quit(1 if failed else 0)
