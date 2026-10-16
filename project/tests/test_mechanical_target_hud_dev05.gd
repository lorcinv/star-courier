extends SceneTree
## Real HUD and world show_design; no Main _ready, native input, or save writes.
const HUD=preload("res://scripts/game_hud.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var hud
var world
var actions:Array=[]
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 p.merge(extra,true);return p
func fixture(kind:String="accelerator",target:int=4,source:int=-2,version:String="pilot-free-v2") -> Dictionary:
 var selected:Dictionary=part(3,kind,1,0,{"input_a":source,"target":target,"param":2.125,"input_b":71})
 return {"mode":"workshop","assembly_mode":"craft","control_version":version,"catalog":Parts.catalog(),"inventory":{},"selectedpart":selected,"parts":[part(4,"beam",2),part(1,"cargo",0),part(2,"battery",-1),selected,part(5,"not_gate",1,1),part(7,"beam",5)],"settings":{"reduced_motion":true},"ship_stats":{"parts":6,"mass":8.0,"energy":6000.0},"workshop":{"size":Vector2i(9,5),"tier":0}}
func status():return hud.content.find_child("ModuleReadiness",true,false)
func settle() -> void:
 for tick in 3:await process_frame
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();world.catalog=Parts.catalog();world.catalog.cargo=Parts.cargo_spec();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 for kind in ["accelerator","coupler","splitter"]:
  var value:Dictionary=fixture(kind);var before:PackedByteArray=var_to_bytes(value)
  for repeat in 3:world.show_design(value.parts,3);hud.render(value);await settle()
  check(world.grid.tool_target_cells.has(Vector2(2,0)) and world.grid.tool_selected_target==Vector2(2,0) and world.grid.tool_target_valid,"OLD FAILURE: "+kind+" draws actual adjacent choices and selected target")
  check(var_to_bytes(value)==before and actions.is_empty(),kind+" redraw/reopen causes no edit, save request, target substitution, or source mutation")
  for target in [999,3]:
   value=fixture(kind,target);before=var_to_bytes(value);world.show_design(value.parts,3);hud.render(value);await settle()
   check(world.grid.tool_selected_target==Vector2(2,0) and not world.grid.tool_target_valid,kind+" missing/self saved ID highlights actual fallback with warning color "+str(target))
   check(status()!=null and "原目标不可用" in status().text and status().get_theme_color("font_color")==hud.YELLOW,kind+" fallback warning remains visible and yellow "+str(target))
   check(var_to_bytes(value)==before and hud.state.selectedpart.target==target and actions.is_empty(),kind+" fallback preview never saves resolved target "+str(target))
  value=fixture(kind,7);world.show_design(value.parts,3);hud.render(value);await settle()
  var choice:OptionButton=hud.content.find_child("PartTargetChoice",true,false)
  check(world.grid.tool_selected_target==Vector2(5,0) and not world.grid.tool_target_valid,kind+" remote explicit target is red at its actual cell")
  check(choice!=null and "不可用" in choice.get_item_text(choice.selected) and hud.state.selectedpart.target==7,kind+" existing unavailable dropdown placeholder preserves exact remote ID")
 world.show_design(fixture().parts,2)
 check(world.grid.tool_target_cells.is_empty() and not is_finite(world.grid.tool_selected_target.x),"changing selection clears all stale target cues")
 world.show_design(fixture().parts,-1)
 check(world.grid.tool_target_cells.is_empty(),"deselection keeps no stale target cues")
 var wired:Dictionary=fixture("accelerator",4,5);hud.render(wired);await settle()
 check("等待原控制信号" in status().text and not "空格" in status().text and not "Q /" in status().text,"actual inspector fixes wired accelerator keyboard claim")
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));hud.render(fixture("accelerator",1));await settle()
  var inspector:Control=hud.content.get_node("ModuleInspector")
  check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(inspector.get_global_rect()),"cargo-warning inspector fits "+str(extent))
  check("断开供电" in status().text and status().get_theme_color("font_color")==hud.YELLOW and status().is_visible_in_tree(),"current cargo risk is a visible yellow conditional line "+str(extent))
  var choice:OptionButton=hud.content.find_child("PartTargetChoice",true,false)
  check(choice!=null and not choice.disabled and "货" in choice.get_item_text(choice.selected),"cargo remains explicitly selectable despite risk "+str(extent))
 var route:Dictionary=fixture("accelerator",1);route.erase("control_version");route.activeorder={"control_version":"pilot-free-v2"};hud.render(route);await settle()
 check("断开供电" in status().text,"accepted explicit free-v2 route context reaches risk copy")
 route.control_version="pilot-free-v1";hud.render(route);await settle()
 check(not "断开供电" in status().text,"older explicit version wins over newer unrelated route")
 route=fixture("accelerator",1);route.assembly_mode="launcher";hud.render(route);await settle()
 check(not "断开供电" in status().text,"launchpad inspector has no craft warning")
 check(actions.is_empty(),"all redraw, reopen, target and protocol views emit zero external edit/save actions")
 hud._stop_motion();hud.queue_free();viewport.queue_free();await settle()
 print("MECHANICAL_TARGET_HUD_DEV05 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
