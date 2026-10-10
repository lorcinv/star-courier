extends SceneTree
## Renderer-only choreography proof: generated actor frames and one parcel.
## Captures are labelled fixtures, not a native-input or earned-gameplay claim.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
var world
var out:String="res://docs/qa/v5/cooperative-cargo"
var captures:Dictionary={}
func _initialize() -> void:run.call_deferred()
func save_frame(label:String) -> void:
 await process_frame
 await RenderingServer.frame_post_draw
 var path:String=out+"/"+label+".png"
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
 print("COOPERATIVE_CAPTURE ",path)
func step(dt:float) -> void:
 if world._parcel_tween!=null:world._parcel_tween.custom_step(dt)
 world._process(dt);world.assembly_feedback._process(dt)
func start_order(id:String,tier:int=0) -> void:
 world.update_shop_state({"contracts":[],"active_contract_id":""})
 for i in 1800:
  if world.prepare_counter_interaction():break
  step(1.0/60.0)
 world.set_workshop_tier(tier);world.show_design(Profile.starter_design());world.focus("contracts",true)
 var contract:Dictionary={"contract_id":id,"status":"accepted","appearance_id":"human_courier","species":"human","appearance_seed":712,"accessory_id":"none","handoff_released":false,"cargo_loaded":false}
 world.update_shop_state({"contracts":[contract],"active_contract_id":id})
 world.customers[id].node.position=world.customers[id].target;world._sync_customer_parcel()
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--out="):out=argument.trim_prefix("--out=")
 root.size=Vector2i(1280,720)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
 world=World.new();root.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 start_order("proof-base")
 await save_frame("00-waiting-customer")
 world.begin_loading();world._parcel_tween.pause()
 for i in 540:
  step(1.0/60.0)
  var phase:String=world._parcel_phase
  var at_mid:bool=world._transport_age>.15
  if phase in ["robot_fetch","robot_pickup","robot_turn","clerk_round_counter","clerk_join","robot_carry","robot_insert","clerk_align","clerk_confirm"] and at_mid and not captures.has(phase):
   captures[phase]=true;await save_frame("base-%03d-"%i+phase)
  if world.is_parcel_loaded():break
 await save_frame("base-loaded-ready")
 world.focus("workshop")
 for i in 60:step(1.0/60.0)
 await save_frame("base-loaded-workshop")
 world.prepare_counter_interaction()
 for i in 200:
  step(1.0/60.0)
  if world._clerk_state=="return_behind" and not captures.has("return"):
   captures["return"]=true;await save_frame("base-clerk-return-behind-edge")
 start_order("proof-expanded",2);world.begin_loading();world._parcel_tween.pause();captures.clear()
 for i in 1400:
  step(1.0/60.0)
  if world._parcel_phase=="robot_carry" and world._transport_x>1700 and not captures.has("travel"):
   captures["travel"]=true;await save_frame("expanded-following-walk")
  if world._parcel_phase=="robot_insert" and world._transport_age>.2 and not captures.has("insert"):
   captures["insert"]=true;await save_frame("expanded-real-cargo-insert")
  if world.is_parcel_loaded():break
 await save_frame("expanded-loaded-ready")
 world.queue_free();await process_frame;await process_frame
 print("COOPERATIVE_SCENE_PROOF_COMPLETE");quit()
