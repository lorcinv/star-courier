extends SceneTree
## Synthetic Main/HUD ownership fixture, NOT RUN. Native acceptance is separate.
const Econ=preload("res://scripts/economy.gd")
const Old=preload("res://scripts/pilot_free_profile_v1.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
var host
class Host extends "res://scripts/main.gd":
 var notices:Array[String]=[]
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func notify(message:String) -> void:notices.append(message)
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func remove(path:String) -> void:
 if FileAccess.file_exists(path):DirAccess.remove_absolute(path);return
 if not DirAccess.dir_exists_absolute(path):return
 var directory=DirAccess.open(path)
 for file in directory.get_files():remove(path.path_join(file))
 for child in directory.get_directories():remove(path.path_join(child))
 DirAccess.remove_absolute(path)
func clean() -> void:
 for item in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp","parts-retirement-v2","force-offer-upgrade-v2"]:remove("user://"+item)
func slots() -> Array:
 var result:Array=[]
 for path in ["user://savegame.json","user://savegame.backup.json"]:result.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
 return result
func state() -> String:
 var value:Dictionary={"design":host.design,"launcher":host.launcher,"settings":host.settings}
 for key in Econ.SHOP_TRANSACTION_FIELDS:value[key]=host.economy.get(key)
 return JSON.stringify(value,"",true,true)
func open_shop() -> void:
 clean();host=Host.new();host.economy=Econ.new();host.economy.enable_free_mode();host.design=Old.starter_design();host.launcher=Old.starter_launcher()
 host.economy.starter_stock(host.design,host.launcher);host.economy.inventory["not_gate"]=2
 host.catalog=Parts.catalog();host.catalog.cargo=Parts.cargo_spec()
 check(host.economy.save_state(host.design,host.launcher,host.settings),"UI fixture exact live settings persisted")
 root.add_child(host);host._build_ui();host.set_process(false);host.world.set_process(false);host.world.assembly_feedback.set_process(false)
 host.courier_input.set_process(false);host.courier_input.focused=true
 host.render();await process_frame;await process_frame
 check(host._free_upgrade_context_available("parts"),"real world owner admits parts preview")
func close_shop() -> void:
 if is_instance_valid(host):root.remove_child(host);host.free();host=null
 await process_frame
func button(key:String) -> Button:
 for candidate in host.hud.content.find_children("*","Button",true,false):
  if str(candidate.get_meta("view_key",""))==key:return candidate
 return null
func open_modal(action:String) -> Dictionary:
 host._action(action,null)
 check(host.hud.free_order_upgrade_open(),"explicit "+action+" opens shared ownership modal")
 return host._pending_free_order_upgrade.duplicate(true)
func press_confirm() -> void:
 var confirm:Button=button("free_upgrade:confirm");check(confirm!=null,"real confirm control exists")
 if confirm!=null:confirm.pressed.emit()
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Fresh isolated XDG_DATA_HOME required");quit(2);return
 await test_cancel_stale();await test_confirm_parts();await test_force_modal();await test_read_only_title_context()
 clean();print("MECHANICAL_UPGRADE_MODAL_V2 passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
func test_cancel_stale() -> void:
 await open_shop();var before:String=state();var bytes:Array=slots();var pending:Dictionary=open_modal("retire_legacy_parts")
 var generation:int=host.hud._free_upgrade_generation
 check(host.hud.is_blocking_modal(),"parts preview owns existing modal gate")
 host.hud._dismiss_free_order_upgrade(generation)
 check(not host.hud.free_order_upgrade_open() and host._pending_free_order_upgrade.is_empty(),"Cancel releases modal and pending consent")
 check(state()==before and slots()==bytes,"Cancel changes no model or durable file")
 open_modal("retire_legacy_parts")
 host.hud._confirm_free_order_upgrade(pending,generation)
 check(host.hud.free_order_upgrade_open() and state()==before,"stale confirm from earlier generation cannot approve reopened modal")
 host.hud._dismiss_free_order_upgrade()
 pending=open_modal("retire_legacy_parts")
 # Simulate a late persisted change while the confirmation is still displayed.
 host.economy.credits+=1;check(host.economy.save_state(host.design,host.launcher,host.settings),"late changed source saved")
 var changed:String=state();bytes=slots();press_confirm()
 check(host.economy.parts_retirement.is_empty() and state()==changed and slots()==bytes,"whole-source stale confirmation has no side effect")
 await close_shop()
func test_confirm_parts() -> void:
 await open_shop();host.undo_history=[{"design":host.design.duplicate(true),"launcher":host.launcher.duplicate(true),"selected":1}]
 var inventory_alias:Dictionary=host.economy.inventory;var old_count:int=int(inventory_alias.not_gate);var money:int=host.economy.credits
 open_modal("retire_legacy_parts");press_confirm()
 check(not host.economy.parts_retirement.is_empty(),"actual Main confirm commits mechanical receipt")
 check(host.economy.credits==money and not host.economy.inventory.has("not_gate"),"same-value gate replacement invents no money")
 check(inventory_alias.not_gate==old_count,"old UI inventory alias stays unchanged")
 check(host.undo_history.is_empty(),"undo cannot resurrect retired logic after success")
 check(host.chosen_type=="beam" and not host.hud.free_order_upgrade_open(),"editor returns to safe beam placement after committed replacement")
 var snapshot:String=state();host._confirm_free_order_upgrade({})
 check(state()==snapshot,"queued duplicate Main confirmation is inert")
 await close_shop()
func test_force_modal() -> void:
 await open_shop();var old:Dictionary=host.economy.free_offer_upgrade.duplicate(true);var old_design:Array=host.design.duplicate(true)
 var pending:Dictionary=open_modal("upgrade_force_offers")
 check(pending.get("kind")=="force" and pending.get("count",0)==2,"v1 upgrade modal targets two available offers")
 press_confirm()
 check(not host.economy.force_offer_upgrade.is_empty(),"actual Main confirm saves independent v2 receipt")
 check(host.economy.free_offer_upgrade==old and host.design==old_design,"force upgrade preserves earlier receipt and apparatus")
 await close_shop()
func test_read_only_title_context() -> void:
 await open_shop();var before:String=state();var bytes:Array=slots();host.entry_defer_controls=true
 host._request_free_order_upgrade("parts");host._request_free_order_upgrade("force")
 check(not host.hud.free_order_upgrade_open() and state()==before and slots()==bytes,"title-owned transition cannot open or commit upgrade")
 host.entry_defer_controls=false;host.courier_input.focused=false
 host._request_free_order_upgrade("parts")
 check(not host.hud.free_order_upgrade_open(),"lost focus cannot acquire upgrade owner")
 await close_shop()
