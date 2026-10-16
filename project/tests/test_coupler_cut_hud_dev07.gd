extends SceneTree
## Headless real HUD + real disk round trip; native pointer input/raster not run.
## Refuses all existing profiles; retains QA saves rather than erasing them.
const HUD=preload("res://scripts/game_hud.gd")
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const View=preload("res://scripts/selected_device_presentation_v2.gd")
const Econ=preload("res://scripts/economy.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
var hud
var actions:Array=[]
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 p.merge(extra,true);return p
func design(bridge:bool=false) -> Array:
 return [part(1,"cargo",0),part(2,"battery",-1),part(3,"thruster",0,-1,{"param":28.0}),part(4,"thruster",0,1,{"param":28.0}),part(5,"coupler",1,0,{"input_a":-2,"target":6}),part(6,"beam",2),part(7,"beam",1,1),part(8,"beam",1 if bridge else 2,2 if bridge else 1)]
func fixture(parts:Array,inventory:Dictionary) -> Dictionary:
 return {"mode":"workshop","assembly_mode":"craft","control_version":"pilot-free-v2","catalog":Parts.catalog(),"inventory":inventory,"selectedpart":parts[mini(4,parts.size()-1)],"parts":parts,"settings":{"reduced_motion":true},"ship_stats":{"parts":parts.size(),"mass":8.0,"energy":6000.0},"workshop":{"size":Vector2i(9,5),"tier":0}}
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json") if FileAccess.file_exists("user://savegame.backup.json") else PackedByteArray()]
func settle() -> void:
 for tick in 3:await process_frame
func readiness():return hud.content.find_child("ModuleReadiness",true,false)
func render_workshop(value:Dictionary,expected:String,label:String) -> void:
 var before:PackedByteArray=var_to_bytes(value)
 hud.render(value);await settle()
 var status=readiness();var inspector:Control=hud.content.get_node_or_null("ModuleInspector")
 var choice:OptionButton=hud.content.find_child("PartTargetChoice",true,false)
 check(status!=null and expected in status.text,label+" existing readiness displays actual prediction")
 check(status!=null and status.is_visible_in_tree() and inspector.get_global_rect().encloses(status.get_global_rect()),label+" readiness geometry fits inspector")
 check(choice!=null and not choice.disabled and inspector.get_global_rect().encloses(choice.get_global_rect()),label+" actual target selector remains available and inside inspector")
 check(var_to_bytes(value)==before and actions.is_empty(),label+" render changes no design/inventory and emits no edit/save action")
func _initialize() -> void:run.call_deferred()
func run() -> void:
 if OS.get_environment("SC_COUPLER_TEST_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Use SC_COUPLER_TEST_ISOLATED=1 and a new empty isolated XDG_DATA_HOME; existing saves are never erased.");quit(2);return
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud)
 hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var economy=Econ.new();economy.enable_force_mode();var d:Array=design();var launcher:Array=[part(10,"beam",0),part(11,"battery",1),part(12,"spring",2)]
 economy.starter_stock(d,launcher)
 check(economy.save_state(d,launcher,{"music":0.137}),"isolated real A blueprint save")
 check(economy.save_state(d,launcher,{"music":0.137}),"isolated real backup save slot")
 var durable:Array=disk();var loader=Econ.new();var loaded:Dictionary=loader.load_state(true)
 check(not loader.review_load_blocked and loaded.design==JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json")).design,"current save loads exact coupler blueprint")
 var loaded_before:PackedByteArray=var_to_bytes(loaded);var inventory_before:PackedByteArray=var_to_bytes(loader.inventory)
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)))
  for bridge in [false,true,false,true]:
   var value:Dictionary=fixture(design(bridge),loader.inventory)
   await render_workshop(value,"断开后会分离" if bridge else "断开后仍相连","move/restore/reopen "+str(extent)+" "+str(bridge))
  var wired:Array=design();wired[4].input_a=9;wired.append(part(9,"not_gate",1,-1))
  await render_workshop(fixture(wired,loader.inventory),"等待原控制信号；断开后仍相连","inherited control wording")
  check(not "空格" in readiness().text and not "按键" in readiness().text,"wired preview has no false manual instruction")
  for saved_target in [999,5]:
   var fallback:Array=design();fallback[4].target=saved_target
   await render_workshop(fixture(fallback,loader.inventory),"断开后仍相连","missing/self target fallback")
   check("原目标不可用" in readiness().text and readiness().get_theme_color("font_color")==hud.YELLOW,"saved fallback warning stays visible and yellow")
  for bridge in [false,true]:
   var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}));route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0
   var sim=Sim.new();sim.configure(design(bridge),[],route,42);sim.set_free_flight_input(0,0,false,false,5)
   var flight:Dictionary={"mode":"flight","control_version":"pilot-free-v2","activeorder":route,"settings":{"reduced_motion":true},"flight":{"flight_status":"running","selected_tool":View.state(sim)}}
   hud.render(flight);await settle()
   var panel:Control=hud.content.get_node_or_null("SelectedFlightTool")
   var status:Label=hud.flight_labels.get("tool_state")
   var expected:String="断开后会分离" if bridge else "断开后仍相连"
   check(panel!=null and panel.is_visible_in_tree() and status!=null and status.text==expected,"existing flight panel uses concise predicted outcome")
   check(panel.get_global_rect().encloses(status.get_global_rect()) and status.get_theme_font("font").get_string_size(status.text,HORIZONTAL_ALIGNMENT_LEFT,-1,status.get_theme_font_size("font_size")).x<=status.size.x,"actual flight status font/label geometry fits "+str(extent))
   sim.set_free_flight_input(0,0,false,true,5);sim.step(sim.FIXED_DT)
   flight.flight.selected_tool=View.state(sim);hud.render(flight);await settle()
   check(hud.flight_labels.tool_state.text=="未连接目标","postcut HUD retains actual unavailable socket state")
   await render_workshop(fixture(design(bridge),loader.inventory),expected,"return to workshop restores blueprint prediction")
 # Existing launcher UI is still its own scope and never gets ship-cut copy.
 var pad:Dictionary=fixture(loaded.launcher,loader.inventory);pad.assembly_mode="launcher";pad.selectedpart=loaded.launcher[2]
 hud.render(pad);await settle()
 check(readiness()!=null and "发射就绪" in readiness().text and not "断开后" in readiness().text,"launcher readiness untouched")
 check(var_to_bytes(loaded)==loaded_before and var_to_bytes(loader.inventory)==inventory_before and disk()==durable,"repeated live/workshop previews leave full loaded state, inventory and both save slots byte-exact")
 check(actions.is_empty(),"all presentation flows emit zero external edit/save actions")
 hud._stop_motion();hud.queue_free();await settle()
 print("COUPLER_CUT_HUD_DEV07 passed=%d failed=%d native_visual=NOT_RUN retained_user_dir=%s"%[passed,failed,OS.get_user_data_dir()]);quit(1 if failed else 0)
