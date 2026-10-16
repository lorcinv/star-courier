extends SceneTree
## Real Economy disk serializer/loader. Requires an empty isolated profile.
## Fixtures and failed saves are retained, never erased by this test.
const Econ=preload("res://scripts/economy.gd")
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,extra:Dictionary={}) -> Dictionary:
 var value:Dictionary={"id":id,"type":kind,"x":x,"y":0,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 value.merge(extra,true);return value
func disk() -> Array:
 return [FileAccess.get_file_as_bytes("user://savegame.json"),FileAccess.get_file_as_bytes("user://savegame.backup.json") if FileAccess.file_exists("user://savegame.backup.json") else PackedByteArray()]
func _initialize() -> void:
 if OS.get_environment("SC_MECHANICAL_TEST_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Use SC_MECHANICAL_TEST_ISOLATED=1 and a new empty isolated XDG_DATA_HOME; existing fixtures are never erased.");quit(2);return
 var economy=Econ.new();economy.enable_force_mode()
 var launcher:Array=[part(10,"battery",0),part(11,"beam",1)]
 for kind in ["accelerator","coupler","splitter"]:
  for target in [1,4,999,3,-1]:
   var design:Array=[part(4,"beam",2),part(1,"cargo",0),part(2,"battery",-1),part(3,kind,1,{"input_a":-2,"input_b":71,"target":target,"param":2.125})]
   economy.starter_stock(design,launcher)
   var saved:bool=economy.save_state(design,launcher,{"music":0.137})
   check(saved,"real save fixture %s/%d"%[kind,target])
   if not saved:continue
   var durable:Array=disk();var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
   var loader=Econ.new();var restored:Dictionary=loader.load_state(true)
   check(not loader.review_load_blocked and restored.design==snapshot.design and restored.launcher==snapshot.launcher,"real loader preserves saved target/source/custom values %s/%d"%[kind,target])
   var before:PackedByteArray=var_to_bytes(restored)
   for version in ["pilot-free-v2","pilot-free-v1","autonomous-v5",""]:
    for repeat in 3:
     var selected:Dictionary=restored.design[3]
     Policy.readiness(selected,restored.design,true,false,version);Policy.target_warning(selected,Policy.effective_target(selected,restored.design));Policy.target_options(selected,restored.design);Policy.trigger_text(selected,restored.design,true,false,version)
   check(var_to_bytes(restored)==before and disk()==durable and restored.design[3].target==target,"loaded read-only warning/preview leaves both durable save slots byte-exact %s/%d"%[kind,target])
 print("MECHANICAL_TARGET_PERSISTENCE_DEV05 passed=%d failed=%d native_input=NOT_RUN retained_user_dir=%s"%[passed,failed,OS.get_user_data_dir()]);quit(1 if failed else 0)
