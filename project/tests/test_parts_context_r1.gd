extends SceneTree
## Reproducer for the host call site, not only Policy.new_part(pilot=false).
## Intentionally delivered unrun. No add_child/_ready, filesystem or player save.
const Main=preload("res://scripts/main.gd")
const Policy=preload("res://scripts/workshop_parts_v1.gd")
var passed:int=0
var failed:int=0
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func _initialize() -> void:
 var host=Main.new()
 host.assembly_mode="craft"
 host.design=[{"id":1,"type":"cargo","x":0,"y":0},{"id":2,"type":"battery","x":2,"y":0}]
 host.economy.flight_mode="pilot-free-v1"
 var old:Dictionary={"contract_id":"accepted-old","status":"accepted","control_version":"autonomous-v5"}
 host.economy.contracts=[old];host.economy.active_contract_id="accepted-old"
 host.economy.in_flight={"control_version":"autonomous-v5","route":old.duplicate(true),"design":host.design.duplicate(true)}
 var saved:Dictionary={"contract":old.duplicate(true),"design":host.design.duplicate(true),"in_flight":host.economy.in_flight.duplicate(true)}
 for kind in ["splitter","teleporter"]:
  var fresh:Dictionary=host.part(9,kind,1,0)
  check(fresh.input_a==-1,kind+" on accepted autonomous order never inherits newer shop cockpit binding")
  check(fresh.size()==9,kind+" still has strict original nine-field blueprint schema")
 check(old==saved.contract and host.design==saved.design and host.economy.in_flight==saved.in_flight,"placement defaults do not mutate accepted order, old design or in-flight snapshot")
 old.erase("control_version")
 check(host.part(9,"splitter",1,0).input_a==-1,"accepted historical order lacking version defaults to legacy, never shop free mode")
 old.control_version="future-unknown-v99"
 check(host.part(9,"teleporter",1,0).input_a==-1,"unknown accepted protocol cannot silently receive free controls")
 old.control_version="pilot-free-v1"
 check(host.part(9,"splitter",1,0).input_a==-2,"explicit accepted free order gets existing manual source")
 old.control_version="pilot-v2"
 check(host.part(9,"teleporter",1,0).input_a==-2,"explicit accepted older pilot route supports its existing cockpit source")
 host.economy.active_contract_id=""
 check(host.part(9,"splitter",1,0).input_a==-2,"no accepted order falls back to current free shop mode")
 host.economy.flight_mode="autonomous-v5"
 check(host.part(9,"teleporter",1,0).input_a==-1,"no accepted order in autonomous shop stays unbound")
 check(Policy.purpose("drill",false,"pilot-free-v1")=="钻穿前方石头，耗电较快；绕行更省电。","drill main purpose uses requested short player copy")
 var split_copy:String=Policy.purpose("splitter",false,"pilot-free-v1")
 check("不能复制货物" in split_copy and not " J" in split_copy and not "耐久均分" in split_copy,"splitter purpose explains outcome without resource calculation wall")
 check("60 J/s" in Policy.detail("drill") and "10 J" in Policy.detail("splitter"),"exact unchanged costs remain in optional tooltip detail")
 host.free()
 print("PARTS_CONTEXT_R1 passed=%d failed=%d native_input=not_tested"%[passed,failed]);quit(1 if failed else 0)
