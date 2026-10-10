extends SceneTree
const Econ=preload("res://scripts/economy.gd")
var pass_count:int=0
var fail_count:int=0
func check(ok:bool,message:String) -> void:
 if ok:pass_count+=1;print("PASS ",message)
 else:fail_count+=1;push_error(message)
func _initialize() -> void:
 var e=Econ.new();e.ensure_contracts();var ids=e.contracts.map(func(c):return c.contract_id)
 check(e.contracts.size()==2,"finite two morning clients")
 check(e.accept_contract(ids[0]).ok,"accept client")
 check(not e.accept_contract(ids[1]).ok,"one commitment at a time")
 var d=[{"id":1,"type":"cargo","x":0,"y":0}];var l=[]
 check(e.begin_dispatch(d,l).ok,"dispatch commits snapshot")
 check(not e.begin_dispatch(d,l).ok,"no duplicate dispatch")
 check(e.save_state(d,l,{}),"atomic launch save")
 var restored=Econ.new();var data=restored.load_state()
 check(not data.is_empty() and restored.in_flight.contract_id==ids[0],"inflight survives restart")
 var t={"integrity":1.0,"energy_used":100.0,"ammo_cost":0,"repair_cost":0,"lost_cost":0}
 check(restored.settle_contract(ids[0],t,8.0,true).ok,"committed order settles")
 var c=restored.credits;var r=restored.reputation
 check(not restored.settle_contract(ids[0],t,8.0,true).ok,"duplicate settlement blocked")
 check(restored.credits==c and restored.reputation==r,"duplicate cannot pay twice")
 check(not restored.accept_contract(ids[0]).ok,"same daily order cannot farm reputation")
 check(restored.close_day().ok,"close day after dispatch")
 check(not restored.accept_contract(ids[1]).ok,"night blocks new orders")
 check(restored.buy_part("beam",{"price":10}).ok,"night procurement")
 check(restored.research_upgrade().ok and restored.research==1,"tangible charger upgrade")
 check(restored.next_day().ok and restored.day==2 and restored.contracts[0].contract_id!=ids[0],"new day new identities")
 check(not restored.buy_part("beam",{"price":10}).ok,"day supplier is unavailable")
 restored.save_state(d,l,{})
 var f=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_string("BROKEN");f.close()
 var backup=Econ.new();check(not backup.load_state().is_empty() and not backup.load_notice.is_empty(),"corrupt primary recovers validated backup")
 print("DAY_CYCLE passed=",pass_count," failed=",fail_count)
 quit(1 if fail_count else 0)
