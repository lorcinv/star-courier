extends SceneTree
# Supplemental active-order replacement regression. Await engine slot before running.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
const IDENTITIES={"human_courier":"human","elf_archivist":"elf","alien_botanist":"alien","robot_machinist":"robot"}
var passed:int=0
var failed:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1
 else:failed.append(label);push_error(label)
func painted(a) -> bool:
 return a.texture!=null and a.texture.resource_path in ["res://assets/2d_v5/npcs/elf_archivist/handoff-pixel.png","res://assets/2d_v5/npcs/alien_botanist/handoff-pixel.png","res://assets/2d_v5/npcs/robot_machinist/handoff-pixel.png"]
func count(w) -> int:
 var result:int=int(w.parcel.is_visible_in_tree())
 for customer in w.customers.values():result+=int(customer.node.is_visible_in_tree() and painted(customer.node))
 return result
func run() -> void:
 for old_id in IDENTITIES:
  for new_id in IDENTITIES:
   for phase in ["customer_handoff","counter_transfer"]:
    var label:String=old_id+" to "+new_id+"/"+phase
    var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
    var w=World.new();viewport.add_child(w);w.set_process(false);w.assembly_feedback.set_process(false)
    w.show_design(Profile.starter_design());w.focus("hub",true)
    var old={"contract_id":"old","status":"accepted","appearance_id":old_id,"species":IDENTITIES[old_id],"accessory_id":"none"}
    var fresh={"contract_id":"new","status":"available","appearance_id":new_id,"species":IDENTITIES[new_id],"accessory_id":"none"}
    var data={"phase":"morning","active_contract_id":"old","handoff_released":false,"contracts":[old,fresh]}
    w.update_shop_state(data)
    for i in 250:w.visual_time+=.01;w._step_customers(.01)
    w.parcel_state="counter";w._parcel_phase="customer_handoff";w._set_counter_poses("old");w._sync_customer_parcel()
    var old_generation:int=w._parcel_generation
    if phase=="counter_transfer":w._begin_counter_transfer("old",old_generation);w._move_counter_parcel(.5,"old",old_generation)
    w.set_focus_active(false)
    old.status="cancelled";fresh.status="accepted";data.active_contract_id="new";w.update_shop_state(data)
    check(w.active_id=="new" and w._parcel_generation>old_generation,label+" fresh generation owns new order")
    check(count(w)==1 and not painted(w.customers.old.node),label+" exactly one painted/live parcel across both actors")
    var pos:Vector2=w.parcel.position;var live:bool=w.parcel.visible
    w._begin_counter_transfer("old",old_generation);w._move_counter_parcel(1.0,"old",old_generation);w._receive_counter_parcel("old",old_generation);w._finish_counter_handoff("old",old_generation)
    check(count(w)==1 and w.parcel.position==pos and w.parcel.visible==live and w.active_id=="new",label+" old callbacks cannot revive old parcel")
    w.set_focus_active(true);w._process(.01)
    check(count(w)==1,label+" one parcel after focus resumes")
    w.free();viewport.free();await process_frame
 var result={"passed":passed,"failures":failed,"scope":"32 synthetic two-actor replacement combinations, all species to all species, giving and transfer, while focus-frozen; actual inspected PNG resource classification."}
 var out=FileAccess.open("user://replacement-results.json",FileAccess.WRITE)
 if out!=null:out.store_string(JSON.stringify(result," "))
 print("PARCEL_REPLACEMENT passed=",passed," failed=",failed.size())
 quit(1 if not failed.is_empty() else 0)
