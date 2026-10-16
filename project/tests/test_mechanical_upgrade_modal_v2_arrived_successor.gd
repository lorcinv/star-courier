extends "res://tests/test_mechanical_upgrade_modal_v2.gd"
## Original fixture retained. New shop production requires a physically arrived
## customer; the old fixture froze world processing while actors were offscreen.
## Establish only that presentation fact, never bypass the production owner gate.
func open_shop() -> void:
 await super.open_shop()
 var customer_id:String=host.world.counter_customer_id(false)
 check(not customer_id.is_empty(),"fixture has a real assigned counter customer")
 if customer_id.is_empty():return
 var customer:Dictionary=host.world.customers[customer_id]
 check(host.world.counter_customer_id(true).is_empty(),"spawned customer has not yet physically arrived")
 check(customer.target==Vector2(148,488),"assigned customer's real target is the counter")
 customer.node.position=customer.target
 host.render();await process_frame
 check(host.world.counter_customer_id(true)==customer_id,"real actor has reached its assigned counter target")
 check(host._free_upgrade_context_available("force"),"existing physical counter guard now admits force modal")
