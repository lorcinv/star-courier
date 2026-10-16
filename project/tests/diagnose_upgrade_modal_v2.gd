extends "res://tests/test_mechanical_upgrade_modal_v2.gd"
func _initialize() -> void:diagnose.call_deferred()
func diagnose() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 await open_shop()
 print("FORCE_MODAL_DIAGNOSTIC ",JSON.stringify({"context_parts":host._free_upgrade_context_available("parts"),"context_force":host._free_upgrade_context_available("force"),"parts_preview":host._free_order_upgrade_preview("parts"),"force_preview":host._free_order_upgrade_preview("force"),"phase":host.economy.phase,"night":host.world.night,"page":host.page,"world_mode":host.world.mode,"counter_allowed":host.world.can_request_shop_navigation("focus_counter",host.page!="hub"),"workbench_allowed":host.world.can_request_shop_navigation("focus_workbench",host.page!="hub"),"contracts":host.economy.contracts},"",true,true))
 open_modal("upgrade_force_offers")
 print("FORCE_MODAL_OPEN_RESULT ",JSON.stringify({"pending":host._pending_free_order_upgrade,"open":host.hud.free_order_upgrade_open(),"notices":host.notices},"",true,true))
 await close_shop();quit(0)
