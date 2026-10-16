extends SceneTree
## Real World + real Main.render handoff; no Main _ready or production saves.
const World=preload("res://scripts/world_view_2d.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
class Host extends "res://scripts/main.gd":
 var saves:int=0
 func save_game() -> bool:saves+=1;return true
 func _sound(_key:String) -> void:pass
class InputStub extends RefCounted:
 func after_render() -> void:pass
 func cancel() -> void:pass
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,target:int=-1) -> Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-2,"input_b":-1,"target":target}
func cues(world) -> bool:return not world.grid.tool_target_cells.is_empty() and is_finite(world.grid.tool_selected_target.x)
func no_cues(world) -> bool:return world.grid.tool_target_cells.is_empty() and not is_finite(world.grid.tool_selected_target.x) and not world.grid.tool_target_valid
func settle() -> void:
 for tick in 2:await process_frame
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 var world=World.new();world.catalog=Parts.catalog();world.catalog.cargo=Parts.cargo_spec();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 var craft:Array=[part(1,"cargo",0),part(2,"battery",-1),part(3,"accelerator",1,0,4),part(4,"beam",2)]
 var pad:Array=[part(10,"battery",0),part(11,"accelerator",1,0,12),part(12,"beam",2)]
 var craft_before:PackedByteArray=var_to_bytes(craft);var pad_before:PackedByteArray=var_to_bytes(pad)
 world.show_design(craft,3)
 check(cues(world) and world.grid.tool_selected_target==Vector2(2,0),"existing callers default to craft and keep accelerator target cues")
 world.set_meta("assembly_context","launcher");world.show_design(pad,11)
 check(no_cues(world),"OLD FAILURE: launcher accelerator never implies it ejects an adjacent pad part")
 world.set_workshop_tier(1)
 check(no_cues(world),"internal workshop tier redraw preserves launcher scope")
 world.set_meta("assembly_context","craft");world.show_design(craft,3)
 check(cues(world),"craft to launcher to craft restores real adjacent-target cues")
 var disconnected:Array=craft.slice(2);world.show_design(disconnected,3)
 check(cues(world) and world.grid.tool_selected_target==Vector2(2,0),"craft without cargo is still craft; no cargo-presence inference")
 for kind in ["coupler","splitter"]:
  var retained:Array=pad.duplicate(true);retained[1].type=kind
  world.set_meta("assembly_context","launcher");world.show_design(retained,11)
  check(no_cues(world),"retained unsupported launcher "+kind+" has no false adjacent-action overlay")
 var hud=HUD.new();root.add_child(hud)
 var game=Host.new();game.world=world;game.hud=hud;game.workshop_input=InputStub.new();game.catalog=Parts.catalog();game.catalog.cargo=Parts.cargo_spec()
 game.design=craft.duplicate(true);game.launcher=pad.duplicate(true);game.economy.enable_force_mode();game.economy.starter_stock(game.design,game.launcher)
 game.page="workshop";game.assembly_mode="craft";game.selected_id=3;game.settings.reduced_motion=true
 game.render();await settle()
 check(world.get_meta("assembly_context","")=="craft" and cues(world),"actual Main.render hands craft context to World after a stale launcher view")
 game.assembly_mode="launcher";game.selected_id=11;game.render();await settle()
 check(world.get_meta("assembly_context","")=="launcher" and no_cues(world) and world._live_design==game.launcher,"actual Main.render passes launcher design and suppresses adjacent target cues")
 check(game.saves==0 and game.undo_history.is_empty(),"ordinary mode renders create no save or undo")
 game.assembly_mode="craft";game.selected_id=3;game.render();await settle()
 check(world.get_meta("assembly_context","")=="craft" and cues(world),"actual Main.render restores craft cues on return")
 # The existing explicit target action can redraw before any general render.
 game.assembly_mode="launcher";game.selected_id=11;game._action("set_input",{"id":11,"key":"target","source":10})
 check(world.get_meta("assembly_context","")=="launcher" and no_cues(world),"actual set_input redraw carries launcher context even after a stale craft view")
 check(game.launcher[1].target==10 and game.saves==1 and game.undo_history.size()==1,"explicit legacy pad target edit retains exactly one existing save and undo")
 game.assembly_mode="craft";game.selected_id=3;game._action("set_input",{"id":3,"key":"target","source":1})
 check(world.get_meta("assembly_context","")=="craft" and cues(world) and world.grid.tool_selected_target==Vector2.ZERO,"actual set_input redraw restores craft target and context")
 check(game.design[2].target==1 and game.saves==2 and game.undo_history.size()==2,"craft target edit retains exact existing save and undo count")
 check(var_to_bytes(craft)==craft_before and var_to_bytes(pad)==pad_before,"all world projections leave source craft/pad fixtures byte-exact")
 game.world=null;game.hud=null;game.free();hud._stop_motion();hud.queue_free();viewport.queue_free();await settle()
 print("MECHANICAL_TARGET_SCOPE_DEV05 passed=%d failed=%d native_input=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
