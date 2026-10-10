extends SceneTree
## Actual Godot rendered phase proof with manual deterministic presentation steps.
## This is scene-level composition evidence, not native-input end-to-end QA.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_ascent_profile.gd")
var world
var prefix:String=""
var order:Dictionary={"contract_id":"proof","status":"accepted","appearance_id":"elf_archivist","species":"elf","appearance_seed":123,"accessory_id":"map_case","handoff_released":false,"cargo_loaded":false}
func _initialize() -> void:run.call_deferred()
func step(seconds:float) -> void:
 for i in ceili(seconds*120):
  if world._parcel_tween!=null:world._parcel_tween.custom_step(1.0/120.0)
  world._process(1.0/120.0);world.assembly_feedback._process(1.0/120.0)
func reach(phase:String) -> void:
 for i in 500:
  if world._parcel_phase==phase:return
  step(1.0/120.0)
func capture(label:String) -> void:
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/cargo-transport-proof/"+prefix+label+".png")
 print("CARGO_RENDERED ",label," ",world.loading_snapshot()," ",world.assembly_feedback.debug_snapshot())
func run() -> void:
 if "--human" in OS.get_cmdline_user_args():
  order.appearance_id="human_courier";order.species="human";order.accessory_id="none";prefix="human-"
 root.size=Vector2i(1280,720);world=World.new();root.add_child(world)
 world.set_process(false);world.assembly_feedback.set_process(false)
 world.show_design(Profile.starter_design());world.focus("hub",true)
 world.update_shop_state({"contracts":[order],"active_contract_id":"proof"});world.customers.proof.node.position=Vector2(148,488);world._sync_customer_parcel()
 await capture("01-waiting-customer")
 order.handoff_released=true;world.update_shop_state({"contracts":[order],"active_contract_id":"proof"});world._parcel_tween.pause()
 await capture("02-customer-handoff")
 reach("counter_transfer");step(.2);await capture("03-counter-transfer")
 reach("clerk_handoff");await capture("04-clerk-receiving")
 reach("robot_pickup");step(.12);await capture("05-robot-pickup")
 reach("robot_turn");step(.08);await capture("06-robot-turn")
 reach("robot_carry");step(.40);await capture("07-floor-carry")
 reach("robot_insert");step(.17);await capture("08-connected-arm-insert")
 reach("loaded");await capture("09-loaded")
 root.remove_child(world);world.free();quit()
