extends "res://tests/test_mechanical_upgrade_modal_v2.gd"
## Actual Main/HUD cancellation and confirmation with mixed held/automatic drills.
const Migration=preload("res://scripts/parts_migration_v2.gd")
const Values=preload("res://scripts/pilot_protected_bird_profile.gd")
func open_shop() -> void:
 await super.open_shop()
 for row in [[902,-2,3],[903,-1,4]]:
  host.design.append({"id":row[0],"type":"drill","x":row[2],"y":2,"rot":0,"param":0.0,"input_a":row[1],"input_b":-1,"target":-1})
 host.economy.inventory["drill"]=2
 host.economy.designs["mixed"]={"design":host.design.duplicate(true),"launcher":host.launcher.duplicate(true)}
 check(host.economy.save_state(host.design,host.launcher,host.settings),"mixed held/automatic fixture saved through real Economy")
 host.render();await process_frame;await process_frame
func run() -> void:
 if OS.get_environment("SC_HELD_MIGRATION_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Fresh explicitly isolated profile required");quit(2);return
 await test_cancel_stale();await test_confirm_mixed()
 print("HELD_DRILL_MIGRATION_MODAL_DEV05 passed=%d failed=%d native_ui=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
func test_confirm_mixed() -> void:
 await open_shop()
 var held:Dictionary=host.design[-2].duplicate(true);var auto:Dictionary=host.design[-1].duplicate(true);var money:int=host.economy.credits
 host.undo_history=[{"design":host.design.duplicate(true),"launcher":host.launcher.duplicate(true),"selected":902}]
 open_modal("retire_legacy_parts");press_confirm()
 check(host.economy.parts_retirement.get("schema")=="mechanical-parts-retirement-v3","actual Main confirm commits v3 policy receipt")
 check(Values.same_value(host.design[-2],held) and Values.same_value(host.design[-1],auto),"Main apply preserves held and automatic craft records exactly")
 check(Values.same_value(host.economy.designs.mixed.design[-2],held) and Values.same_value(host.economy.designs.mixed.design[-1],auto),"Main apply preserves blueprint drill modes exactly")
 check(host.economy.credits==money and host.economy.inventory.drill==2 and not host.economy.inventory.has("not_gate"),"real modal retires gates without drill refund or money change")
 check(host.undo_history.is_empty() and not host.hud.free_order_upgrade_open(),"successful retirement clears stale undo and closes modal")
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(Migration.receipt_error(saved).is_empty() and saved.design[-2].input_a==-2 and saved.design[-1].input_a==-1,"actual confirm disk receipt and mode records coherent")
 var before:String=state();var bytes:Array=slots();host._confirm_free_order_upgrade({})
 check(state()==before and slots()==bytes,"queued duplicate confirm cannot mutate model or raw slots")
 await close_shop()
