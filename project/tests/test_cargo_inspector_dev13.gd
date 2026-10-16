extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var hud
var passed:int=0
var failed:int=0
var actions:Array=[]
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize()->void:run.call_deferred()
func text_in(node:Node)->String:
 var result:String=""
 if node is Label or node is Button:result+=node.text+"\n"
 for child in node.get_children():result+=text_in(child)
 return result
func fixture(kind:String="cargo",launcher:bool=false)->Dictionary:
 var piece:Dictionary={"id":1,"type":kind,"x":0,"y":0,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1,"spec":Parts.cargo_spec() if kind=="cargo" else Parts.catalog()[kind],"name":"委托货物" if kind=="cargo" else str(Parts.catalog()[kind].name)}
 return {"mode":"workshop","assembly_mode":"launcher" if launcher else "craft","control_version":"pilot-free-v2","catalog":Parts.catalog(),"inventory":{"beam":4,"battery":3,"thruster":2,"not_gate":1},"selectedpart":piece,"parts":[piece],"settings":{"reduced_motion":true},"ship_stats":{"parts":1,"mass":4.0,"energy":0.0},"workshop":{"size":Vector2i(9,5),"tier":0}}
func run()->void:
 root.size=Vector2i(1280,720);hud=HUD.new();root.add_child(hud);hud.action_requested.connect(func(a,p):actions.append([a,p]))
 for device in [false,true]:
  hud.set_input_device(device)
  var data:Dictionary=fixture();var before:Dictionary=data.duplicate(true)
  hud.render(data)
  for n in 3:await process_frame
  var copy:String=text_in(hud.content)
  check(not "旧版保留" in copy,"cargo inspector never labels current cargo legacy "+str(device))
  check(not "退出当前装配" in copy and not "整理旧库存" in copy,"cargo inspector never sends player to retired inventory "+str(device))
  check("委托货物" in copy and "收件" in copy,"cargo purpose describes delivery "+str(device))
  check(data==before and actions.is_empty(),"cargo render does not mutate save or emit intent "+str(device))
  var ready:Dictionary=Policy.readiness(data.selectedpart,data.parts,true,false,"pilot-free-v2")
  check(ready.ready and ready.text.is_empty(),"existing cargo has no placement or false power claim "+str(device))
 check(not Policy.is_core("cargo") and not "cargo" in Policy.sale_kinds(),"cargo remains outside sale catalogue")
 check(not Policy.compatible("cargo",false) and not Policy.compatible("cargo",true),"cargo cannot be newly placed on either assembly")
 check(Policy.new_part(99,"cargo",0,0,[],false,true).is_empty(),"new cargo construction stays forbidden")
 check(not Policy.placement_error("cargo",false).is_empty(),"placement rejection remains separate from existing cargo display")
 for kind in ["not_gate","spring"]:
  var legacy:Dictionary=fixture(kind)
  hud.render(legacy)
  for n in 3:await process_frame
  check("旧版保留" in text_in(hud.content),"retired or wrong-context part still labelled "+kind)
  check(not Policy.readiness(legacy.selectedpart,legacy.parts,true,false,"pilot-free-v2").ready,"retired or wrong-context part still unready "+kind)
 var wrong:Dictionary=fixture("cargo",true)
 check(not Policy.readiness(wrong.selectedpart,wrong.parts,true,true,"pilot-free-v2").ready,"malformed launcher cargo not declared ready")
 print("CARGO_INSPECTOR_DEV13 passed=",passed," failed=",failed," native_gui=NOT_RUN")
 hud.queue_free();await process_frame;quit(1 if failed else 0)
