extends SceneTree
## Presentation-only catalogue coverage, plus scripted HUD category selection.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const UI=preload("res://scripts/module_controls_ui.gd")
var passed:int=0
var failed:int=0
var hud
var actions:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if ok:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func entries() -> Array:
 var result:Array=[];var catalog:Dictionary=Parts.catalog()
 for kind in catalog:
  var entry:Dictionary=catalog[kind].duplicate(true);entry.type=kind;entry.launcher_compatible=kind in Parts.launcher_types();result.append(entry)
 return result
func ids(values:Array) -> Array:
 return values.map(func(value):return str(value.type))
func control(key:String) -> Control:
 for node in hud.content.find_children("*","Control",true,false):
  if hud._view_key(node)==key:return node
 return null
func settle() -> void:
 for i in 4:await process_frame
func run() -> void:
 var catalog:Array=entries();var original:Array=catalog.duplicate(true)
 check(UI.categories(catalog,false)==["现有库存","船体","动力","能源","防护工具","高级零件"],"four real basic groups and one explicit advanced group")
 check(UI.categories(catalog,true)==["现有库存","船体","动力","能源","高级零件"],"launcher retains compatibility filter and omits empty protection tab")
 var all_types:Array=[]
 for group in ["船体","动力","能源","防护工具","高级零件"]:
  var selected:Array=UI.visible_entries(catalog,[],{},group,false)
  var kind_ids:Array=ids(selected)
  for kind in kind_ids:
   check(not kind in all_types,kind+" appears in exactly one category")
   all_types.append(kind)
  if group in UI.BASIC_GROUPS:check(kind_ids.size()==UI.BASIC_GROUPS[group].size(),group+" contains precisely its existing catalogue members")
 check(all_types.size()==Parts.catalog().size(),"every existing placeable ID remains in the catalogue")
 for logic in ["probe","collision","delay","and_gate","or_gate","not_gate"]:
  check(logic in ids(UI.visible_entries(catalog,[],{},"高级零件",false)),logic+" stays available behind advanced category")
 var fresh:Dictionary={"cargo":1,"beam":4,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1,"not_gate":1}
 var basic:Array=ids(UI.visible_entries(catalog,[],fresh,"现有库存",false))
 check(basic.size()==6 and not "not_gate" in basic and not "cargo" in basic,"fresh inventory shows the six owned ordinary types without logical gates or fabricated cargo")
 var installed:Array=[{"id":17,"type":"beam"},{"id":18,"type":"not_gate"}]
 check(ids(UI.visible_entries(catalog,installed,{},"现有库存",false))==["beam"],"zero-spare installed basic part remains accessible while advanced is separate")
 check("not_gate" in ids(UI.visible_entries(catalog,installed,{},"高级零件",false)),"zero-spare installed advanced part remains accessible")
 var special:Array=[{"type":"cargo","category":"货物"},{"type":"legacy_extension","category":"旧模块"}]
 check(UI.categories(special,false)==["现有库存","高级零件"],"does not fabricate cargo group and safely preserves future extension types")
 check(ids(UI.visible_entries(special,[],{},"高级零件",false))==["legacy_extension"],"unknown legacy IDs remain discoverable in advanced")
 var override:Array=[{"type":"beam","available":0}]
 check(UI.visible_entries(override,[],{"beam":5},"现有库存",false).is_empty(),"availability retains installed-subtracted stock precedence")
 check(catalog==original,"category filtering never modifies registry records")
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var data:Dictionary={"mode":"workshop","assembly_mode":"craft","catalog":catalog,"inventory":fresh,"parts":installed,"settings":{"reduced_motion":true},"ship_stats":{}}
 var saved:Dictionary=data.duplicate(true);hud.render(data);await settle()
 check(data==saved and actions.is_empty(),"initial tray rendering cannot alter inventory or saved design")
 check(control("category:高级零件")!=null and control("category:全部")==null and control("category:货运")==null,"tray exposes optional advanced rather than an undifferentiated all-parts wall")
 check(control("catalog:not_gate")==null and control("catalog:beam")!=null,"initial visible tray contains familiar basic parts")
 (control("category:高级零件") as Button).pressed.emit();await settle()
 check(actions.is_empty() and control("catalog:not_gate")!=null and control("catalog:thruster")==null,"opening advanced only changes view and exposes logical modules")
 (control("catalog:not_gate") as Button).pressed.emit();await settle()
 check(actions==[["select_catalog","not_gate"]],"old advanced module uses its unchanged placement action and ID")
 actions.clear();(control("category:动力") as Button).pressed.emit();await settle()
 check(actions.is_empty() and control("catalog:thruster")!=null and control("catalog:spring")!=null and control("catalog:and_gate")==null,"ordinary propulsion group keeps signal gates out of the basic workflow")
 data.assembly_mode="launcher";hud.render(data);await settle()
 check(control("category:防护工具")==null and control("catalog:coupler")==null,"launcher category respects existing compatibility restrictions")
 hud._stop_motion();hud.queue_free();await settle()
 print("MODULE_CATALOGUE_UI_V2 passed=%d failed=%d native_visual=not_tested"%[passed,failed]);quit(1 if failed else 0)
