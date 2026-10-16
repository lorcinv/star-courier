extends SceneTree
## Narrow current-manual copy contract. No HUD, simulation or save writes.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const CURRENT_REPEAT:String="Q / 手柄 Y 选择此装置，再按空格 / A；松开后可再触发。"
const LEGACY_EDGE:String="空格 / A 同时触发所有手动装置；松开后可再按。"
const LAUNCHER:String="发射时自动释放；与飞行器共用库存，使用台上电芯。"
const AUTOMATIC:String="自动运行；需要用电的零件须接通电芯。"
var passed:int=0
var failed:int=0

func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)

func part(kind:String,source:int=-2) -> Dictionary:
 return {"id":4,"type":kind,"x":1,"y":0,"rot":0,"param":Parts.defaults(kind),"input_a":source,"input_b":-1,"target":8}

func hint(piece:Dictionary,parts:Array,pilot:bool=true,launcher:bool=false,version:String="pilot-free-v2") -> String:
 var before:PackedByteArray=var_to_bytes([piece,parts])
 var result:String=Policy.trigger_text(piece,parts,pilot,launcher,version)
 check(var_to_bytes([piece,parts])==before,"trigger copy preserves saved input/target/parameter and adjacent parts: "+str([piece.type,piece.input_a,pilot,launcher,version]))
 return result

func _initialize() -> void:
 var neighbor:Dictionary={"id":8,"type":"beam","x":2,"y":0,"rot":0,"param":0.0,"input_a":-1,"input_b":-1,"target":-1}
 var piece:Dictionary=part("accelerator")
 var design:Array=[piece,neighbor]
 var current:String=hint(piece,design)
 check(current.contains("Q") and current.contains("Y") and current.contains("空格") and current.contains("A"),"current manual accelerator retains both device-selection and activation controls")
 check(current.contains("选择") or current.contains("选中"),"current manual accelerator still teaches selecting this device")
 check(current.contains("一次航程") and (current.contains("发射一次") or current.contains("使用一次") or current.contains("触发一次")),"current manual accelerator makes its once-per-flight limit explicit")
 check(not current.contains("松开后可再触发") and not current.contains("松开后可再按") and not current.contains("重复") and not current.contains("再次发射"),"current manual accelerator never promises another shot after releasing the key")
 check(Policy.purpose("accelerator",false,"pilot-free-v2").contains("一次航程发射一次"),"trigger instruction agrees with the existing truthful accelerator purpose")
 var spent:Dictionary=piece.duplicate(true);spent.spent=true
 var spent_hint:String=hint(spent,[spent,neighbor])
 check(not spent_hint.contains("松开后可再触发") and not spent_hint.contains("再次发射"),"a stored spent flag cannot restore repeat-fire advice")
 # Re-entrant rendering must not toggle a hidden one-shot state or rewrite the
 # design. The frozen simulator remains the authority on actual firing.
 for i in 20:check(hint(piece,design)==current,"repeated current-manual description is stable "+str(i))
 for kind in ["teleporter","splitter"]:
  var repeatable:Dictionary=part(kind)
  check(hint(repeatable,[repeatable,neighbor])==CURRENT_REPEAT,kind+" retains exact release-and-retrigger instruction")
 for kind in ["spring","coupler","bomb"]:
  var unchanged_edge:Dictionary=part(kind)
  check(hint(unchanged_edge,[unchanged_edge,neighbor])==CURRENT_REPEAT,"unrelated current edge copy stays unchanged: "+kind)
 for kind in ["shield","drill","thruster"]:
  var held:Dictionary=part(kind)
  check(hint(held,[held,neighbor])=="选中此装置后，按住空格 / A 工作。","unrelated held action stays unchanged: "+kind)
 for version in ["","pilot-free-v1","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-free-v2-nearby"]:
  for kind in ["accelerator","teleporter","splitter"]:
   var legacy:Dictionary=part(kind)
   check(hint(legacy,[legacy,neighbor],true,false,version)==LEGACY_EDGE,"legacy protocol copy remains byte-exact: "+version+" "+kind)
 for source in [-2,-1,8]:
  var launcher:Dictionary=part("accelerator",source)
  for version in ["pilot-free-v2","pilot-free-v1","pilot-v3"]:
   check(hint(launcher,[launcher,neighbor],true,true,version)==LAUNCHER,"launchpad automatic release stays exact: "+str(source)+" "+version)
 var automatic:Dictionary=part("accelerator",-1)
 check(hint(automatic,[automatic,neighbor])==AUTOMATIC,"unwired accelerator copy remains outside the narrow manual fix")
 check(hint(piece,design,false,false)==AUTOMATIC,"non-pilot negative source does not gain current manual wording")
 var wired:Dictionary=part("accelerator",8)
 check(hint(wired,[wired,neighbor])=="沿用控制：%s；须保持结构相连。"%Policy.reference_label(neighbor),"wired accelerator still identifies its actual source")
 var lost:Dictionary=part("accelerator",99)
 check(hint(lost,[lost,neighbor])=="沿用控制：已失去的零件 #99；须保持结构相连。","lost wired source is not replaced by manual-use advice")
 check(Policy.EDGE==["spring","coupler","bomb","teleporter","splitter","accelerator"],"copy fix leaves existing edge-action registry intact")
 print("ACCELERATOR_HINT_DEV15 passed=%d failed=%d native_gui=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)
