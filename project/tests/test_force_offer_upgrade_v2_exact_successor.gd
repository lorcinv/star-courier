extends "res://tests/test_force_offer_upgrade_v2.gd"
## Original test retained. Lead diagnostic proved all seven raw-JSON failures
## were exactly equal int/float values, without missing/different fields.
## Reuse the established exact recursive comparator: no epsilon, no ignored keys.
const Exact=preload("res://scripts/pilot_protected_bird_profile.gd")
func same(a:Variant,b:Variant,label:String) -> void:
 var wording:String=label.replace("byte-equivalent","exact-value equivalent")
 check(Exact.same_value(a,b),wording)
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("Fresh isolated XDG_DATA_HOME required");quit(2);return
 check(Exact.same_value({"amount":220},{"amount":220.0}),"JSON numeric storage type does not change exact amount")
 check(not Exact.same_value({"amount":220.0},{"amount":220.000000000001}),"any representable changed amount is rejected without epsilon")
 check(not Exact.same_value({"amount":0},{"amount":false}),"boolean is never an equivalent amount")
 check(not Exact.same_value({"amount":1},{"amount":1,"extra":null}),"extra key is not ignored")
 check(not Exact.same_value([1,2],[2,1]),"array order remains exact")
 test_upgrade_and_restart();test_failed_stale();test_accepted_retained();test_inflight_and_paid_retained();test_receipt_markers()
 clean();print("FORCE_OFFER_UPGRADE_V2_EXACT_SUCCESSOR passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
