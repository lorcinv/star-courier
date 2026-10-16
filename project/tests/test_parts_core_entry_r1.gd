extends SceneTree
## Read-only palette regression. No production save path, simulation or migration.
const Policy=preload("res://scripts/workshop_parts_v1.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const STARTER_STOCK:Dictionary={"cargo":1,"beam":4,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1,"not_gate":1}
var passed:int=0
var failed:int=0

func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func ids(entries:Array) -> Array:
 var result:Array=[]
 for entry in entries:result.append(Policy.kind_of(entry))
 result.sort();return result

func entries() -> Array:
 var result:Array=[]
 var catalog:Dictionary=Parts.catalog()
 catalog.cargo=Parts.cargo_spec()
 for kind in catalog:
  var entry:Dictionary=catalog[kind].duplicate(true)
  entry.type=kind;entry.launcher_compatible=kind in Parts.launcher_types();result.append(entry)
 return result

func part(id:int,kind:String,extra:Dictionary={}) -> Dictionary:
 var value:Dictionary={"id":id,"type":kind,"x":id,"y":0,"rot":3,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 value.merge(extra,true);return value

func _initialize() -> void:
 fresh_default();compatibility_only();launcher_context();read_only_json()
 print("PARTS_CORE_ENTRY_R1 passed=%d failed=%d native_input=not_tested"%[passed,failed]);quit(1 if failed else 0)

func fresh_default() -> void:
 var craft:Array=Profile.starter_design()
 var pad:Array=Profile.starter_launcher()
 var stock:Dictionary=STARTER_STOCK.duplicate(true)
 # Main sends spare counts, not total ownership, to the workshop HUD.
 for installed in craft+pad:stock[installed.type]=int(stock.get(installed.type,0))-1
 var catalog:Array=entries()
 check(Policy.DEFAULT_CATEGORY=="常用零件","short default label accurately names the core quick palette")
 check(Policy.categories(catalog,craft,stock,false)[0]==Policy.DEFAULT_CATEGORY,"fresh aircraft starts in core quick category")
 check(ids(Policy.visible_entries(catalog,craft,stock,Policy.DEFAULT_CATEGORY,false))==["armor","battery","beam","thruster"],"real fresh starter shows four owned aircraft core kinds")
 check(ids(Policy.visible_entries(catalog,craft,stock,"旧版保留",false))==["coupler","not_gate"],"installed coupler and spare NOT remain explicitly reachable")
 check(ids(Policy.visible_entries(catalog,craft,stock,"路线工具",false))==["drill","splitter","teleporter"],"unowned new route tools remain discoverable in their group")
 check(not "发射台" in Policy.categories(catalog,craft,stock,false),"aircraft does not advertise the launcher-only group")

func compatibility_only() -> void:
 var catalog:Array=entries()
 var installed:Array=[part(81,"coupler",{"param":7.25,"input_a":93,"input_b":94,"target":77}),part(82,"and_gate",{"input_a":81,"input_b":99})]
 var stock:Dictionary={"coupler":0,"and_gate":0,"not_gate":2,"spring":1,"delay":0,"probe":-1}
 var expected:Array=["and_gate","coupler","not_gate","spring"]
 check(ids(Policy.visible_entries(catalog,installed,stock,"旧版保留",false))==expected,"positive stock and zero-spare equipped legacy entries remain in compatibility")
 for category in Policy.categories(catalog,installed,stock,false):
  var shown:Array=ids(Policy.visible_entries(catalog,installed,stock,category,false))
  if category!="旧版保留":
   for legacy in expected:check(not legacy in shown,legacy+" absent outside compatibility: "+str(category))
 check(not "旧版保留" in Policy.categories(catalog,[],{"not_gate":0,"probe":-1},false),"zero or negative stock never invents legacy ownership")
 check(Policy.visible_entries(catalog,[],{},Policy.DEFAULT_CATEGORY,false).is_empty(),"empty quick view never grants or invents inventory")
 var retained:Array=Policy.visible_entries(catalog,installed,stock,"旧版保留",false)
 for item in retained:
  var source:Dictionary=Parts.catalog()[item.type]
  check(item.name==source.name and item.mass==source.mass and item.price==source.price,"retained "+str(item.type)+" has exact catalog identity, mass and price")

func launcher_context() -> void:
 var catalog:Array=entries()
 var stock:Dictionary={}
 var installed:Array=[]
 var index:int=1
 for kind in Parts.catalog():
  stock[kind]=1;installed.append(part(index,kind));index+=1
 check(ids(Policy.visible_entries(catalog,installed,stock,Policy.DEFAULT_CATEGORY,false))==["armor","battery","beam","drill","shield","splitter","teleporter","thruster"],"aircraft quick view is bounded to the eight ship kinds, even for all-owned old saves")
 check(ids(Policy.visible_entries(catalog,installed,stock,Policy.DEFAULT_CATEGORY,true))==["battery","beam","spring","thruster"],"launcher quick view is bounded to the four pad kinds, even with unsupported old installations")
 check("spring" in ids(Policy.visible_entries(catalog,installed,stock,"旧版保留",false)),"an owned or equipped aircraft spring remains available only as compatibility")
 check(ids(Policy.visible_entries(catalog,installed,stock,"发射台",true))==["spring"],"launcher spring remains available under its real category")
 check(not "spring" in ids(Policy.visible_entries(catalog,installed,stock,"旧版保留",true)),"launcher spring is not mislabeled legacy")
 for kind in Parts.catalog():
  if not Policy.is_core(kind):
   check(kind in ids(Policy.visible_entries(catalog,installed,stock,"旧版保留",false)),"equipped old "+kind+" remains reachable on aircraft")
   check(kind in ids(Policy.visible_entries(catalog,installed,stock,"旧版保留",true)),"equipped old "+kind+" remains reachable on launcher")

func read_only_json() -> void:
 var saved:Dictionary={"design":[part(77,"beam"),part(81,"coupler",{"param":7.25,"input_a":93,"input_b":94,"target":77}),part(93,"not_gate",{"param":2.5,"input_a":81,"target":-7})],"launcher":[part(101,"spring",{"param":19.125,"input_a":93,"target":77})],"inventory":STARTER_STOCK.duplicate(true),"accepted_order":{"contract_id":"retained-order","control_version":"pilot-v3","route":{"distance":64.0}},"in_flight":{"ticks":17,"design":[part(93,"not_gate",{"input_a":-2})]},"settings":{"legacy_extension":{"unknown":true}}}
 var saved_json:String=JSON.stringify(saved)
 var parsed:Dictionary=JSON.parse_string(saved_json)
 var before:String=JSON.stringify(parsed)
 var catalog:Array=entries()
 var catalog_before:String=JSON.stringify(catalog)
 for launcher in [false,true]:
  var design:Array=parsed.launcher if launcher else parsed.design
  for category in Policy.categories(catalog,design,parsed.inventory,launcher):
   Policy.visible_entries(catalog,design,parsed.inventory,category,launcher)
  for installed in design:
   Policy.local_controls(installed,launcher)
   Policy.trigger_text(installed,design,true,launcher)
 check(JSON.stringify(parsed)==before,"render policy leaves full restored JSON including raw wires, params, accepted route and in-flight snapshot unchanged")
 check(JSON.stringify(catalog)==catalog_before,"palette filtering never rewrites original catalog entries")
 check(JSON.stringify(saved)==saved_json,"original serialized save source remains byte-for-byte unchanged")
