extends "res://tests/test_shop_transaction_boundaries_dev03_r1.gd"
## Preserve the dev03 failure evidence. The new guard requires its actual
## assigned customer to reach the counter; this transaction fixture otherwise
## freezes World at its entrance spawn. No production guard is bypassed.
func fresh() -> void:
 await super.fresh()
 var id:String=game.world.counter_customer_id(false)
 check(not id.is_empty(),"transaction fixture has a real assigned customer")
 if id.is_empty():return
 var customer:Dictionary=game.world.customers[id]
 check(customer.target==Vector2(148,488),"transaction fixture uses the assigned counter target")
 customer.node.position=customer.target
 game.render();await frames()
 check(game.world.counter_customer_id()==id,"actual counter identity authorizes transaction fixture")
