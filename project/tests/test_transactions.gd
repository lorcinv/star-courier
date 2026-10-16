extends SceneTree
## Run with a fresh XDG_DATA_HOME, never a player's save.
const Econ = preload("res://scripts/economy.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array = []
var count = 0
class FlightWorld extends RefCounted:
 var route_distance: float = 0.0
 var route_radius: float = 5.0
 var launcher_design:Array=[]
 var launch_age:float=0.0
 var launch_transfer_progress:float=1.0
 func set_workshop_tier(_tier:int) -> void:pass
 func start_flight(_sim=null,_resuming:bool=false) -> void: pass
 func launch_transfer_duration() -> float:return 0.0
 func settle_resumed_flight(_sim) -> void:pass
 func show_flight(_sim,_paused_visual:bool=false) -> void: pass
 func hotspot_positions() -> Array:return []
class FlightHUD extends RefCounted:
 func update_flight(_data: Dictionary) -> void: pass
 func update_hotspots(_positions:Array) -> void:pass
 func is_blocking_modal() -> bool:return false
class Controller extends "res://scripts/main.gd":
 var notices: Array = []
 func _ready() -> void: pass
 func render() -> void: pass
 func notify(message: String) -> void: notices.append(message)
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():
  printerr("Transaction tests require an isolated XDG_DATA_HOME.");quit(2);return
 _clear_files()
 _test_decisions();_test_dispatch();_test_purchases();_test_blueprint();_test_trials();_test_controller_settlement();_test_resume();_test_failed_save();_test_backup()
 _clear_files()
 for failure in failures:printerr("FAIL: ",failure)
 print("TRANSACTIONS passed=%d failed=%d total=%d"%[count-failures.size(),failures.size(),count])
 quit(0 if failures.is_empty() else 1)
func check(ok:bool,title:String)->void:
 count+=1
 if not ok:failures.append(title)
func close(a:float,b:float)->bool:return absf(a-b)<0.00001
func econ():
 var e=Econ.new();e.ensure_contracts();return e
func controller():
 # This suite preserves the autonomous-v5 transaction fixture. Pilot controller
 # and disk-input history are exercised by test_pilot_input_lifecycle.gd.
 var app=Controller.new();app.catalog=Parts.catalog();app.catalog.cargo=Parts.cargo_spec()
 app.design=[app.part(1,"cargo",0,0),app.part(2,"beam",-1,0),app.part(3,"battery",0,1),app.part(4,"thruster",-2,0),app.part(5,"armor",1,1),app.part(6,"thruster",-2,1),app.part(7,"beam",-1,1),app.part(8,"coupler",1,0)]
 app.design[3].param=3;app.design[5].param=3
 app.launcher=[app.part(10,"spring",0,0),app.part(11,"battery",-1,0),app.part(12,"beam",1,0)];app.launcher[0].param=20
 app.economy=econ();app.economy.starter_stock(app.design,app.launcher);app.world=FlightWorld.new();app.hud=FlightHUD.new();return app
func values(e)->Dictionary:
 # JSON numbers are floats on load; compare equivalent persisted values.
 return JSON.parse_string(JSON.stringify({"credits":e.credits,"reputation":e.reputation,"inventory":e.inventory.duplicate(true),"deliveries":e.deliveries,"jobs":e.jobs_today,"history":e.history.duplicate(true),"settled":e.settled_ids.duplicate(true)}))
func cargo()->Array:return [{"id":1,"type":"cargo","x":0,"y":0}]
func telemetry()->Dictionary:return {"integrity":1.0,"energy_used":100.0,"ammo_cost":10.0,"repair_cost":2.0,"lost_cost":25.0}
func _clear_files()->void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func write_primary(text:String)->void:
 var f=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_string(text);f.close()
func _test_decisions()->void:
 var e=econ();var a=str(e.contracts[0].contract_id);var b=str(e.contracts[1].contract_id);var initial=values(e)
 check(not e.accept_contract("missing").ok and values(e)==initial,"unknown order cannot mutate economy")
 check(e.accept_contract(a).ok and e.phase=="day" and e.active_contract_id==a,"acceptance creates one named commitment")
 check(not e.accept_contract(a).ok and not e.accept_contract(b).ok,"cannot accept duplicate or competing commitments")
 check(not e.close_day().ok and not e.next_day().ok,"accepted order blocks closing and skipping day")
 check(not e.decline_available(a).ok,"accepted order requires cancellation, not free decline")
 check(e.decline_available(b).ok and e.contract_by_id(b).status=="declined","other available order can be declined")
 check(values(e)==initial and e.active_contract_id==a,"decline preserves funds stock reputation and existing commitment")
 check(not e.decline_available(b).ok and not e.accept_contract(b).ok,"declined order cannot be recycled")
 e.reputation=3
 check(e.cancel_accepted().ok and e.reputation==2 and e.active_contract_id.is_empty(),"cancellation releases order and charges one reputation")
 check(not e.cancel_accepted().ok and e.reputation==2,"repeat cancellation cannot charge twice")
 check(not e.accept_contract(a).ok and e.contract_by_id(a).status=="cancelled","cancelled order cannot be reclaimed")
 check(e.close_day().ok and e.phase=="night","resolved commitments permit closing")
 check(not e.accept_contract(a).ok and not e.decline_available(a).ok,"night blocks contract decisions")
 check(e.next_day().ok and e.day==2 and e.jobs_today==0 and e.contracts[0].contract_id!=a,"new day has fresh order identities")
func _test_dispatch()->void:
 var e=econ();var a=str(e.contracts[0].contract_id);var b=str(e.contracts[1].contract_id)
 check(not e.begin_dispatch(cargo(),[]).ok and not e.settle_contract(a,telemetry(),8.0,true).ok,"unaccepted order cannot dispatch or settle")
 e.accept_contract(a);var design=cargo()
 check(e.begin_dispatch(design,[]).ok and e.active_contract().status=="in_flight","formal dispatch commits accepted order")
 design[0].x=4
 check(e.in_flight.design[0].x==0,"dispatch snapshot is isolated from workbench edits")
 var before=values(e)
 check(not e.begin_dispatch(design,[]).ok and not e.cancel_accepted().ok and not e.close_day().ok and not e.accept_contract(b).ok,"in-flight order rejects conflicting actions")
 check(values(e)==before,"rejected in-flight actions do not mutate funds or counters")
 check(not e.settle_contract(b,telemetry(),8.0,true).ok,"unlaunched second contract cannot receive settlement")
 var result=e.settle_contract(a,telemetry(),8.0,true)
 check(result.ok and result.report.profit==110 and e.credits==370,"formal settlement applies income and each expense once")
 check(e.jobs_today==1 and e.deliveries==1 and e.reputation==2 and e.history.size()==1,"formal outcome updates counters once")
 check(e.in_flight.is_empty() and e.active_contract_id.is_empty() and e.contract_by_id(a).status=="settled","settlement closes commitment")
 before=values(e)
 check(not e.settle_contract(a,telemetry(),8.0,true).ok and values(e)==before,"repeat settlement cannot pay twice")
 e.accept_contract(b);e.begin_dispatch(cargo(),[])
 check(e.settle_contract(b,telemetry(),8.0,false).ok and e.jobs_today==2 and e.deliveries==1 and e.reputation==1,"failure consumes daily slot without delivery")
 check(e.last_settlement.income==0 and e.last_settlement.profit == -55,"failure still pays energy and replenishment")
 check(not e.begin_dispatch(cargo(),[]).ok,"two outcomes exhaust daily dispatch allowance")
func _test_purchases()->void:
 var e=econ();var before=values(e)
 check(not e.buy_part("beam",Parts.catalog().beam).ok and not e.research_upgrade().ok and values(e)==before,"morning blocks purchasing and research")
 e.accept_contract(str(e.contracts[0].contract_id));e.cancel_accepted()
 check(not e.buy_part("beam",Parts.catalog().beam).ok,"daytime supplier remains closed after cancellation")
 e.close_day()
 check(e.buy_part("beam",Parts.catalog().beam).ok and e.credits==250 and e.inventory.beam==1,"night purchase exchanges price for one stock unit")
 e.credits=9;before=values(e)
 check(not e.buy_part("beam",Parts.catalog().beam).ok and values(e)==before,"unaffordable purchase has no side effects")
 e.credits=200
 check(e.research_upgrade().ok and e.research==1 and e.credits==60,"night upgrade buys one level")
 check(not e.research_upgrade().ok and e.research==1 and e.credits==60,"unaffordable upgrade cannot repeat purchase")
 e.credits=5000;e.research=3
 check(not e.research_upgrade().ok and e.credits==5000,"maximum research cannot charge again")
func _test_blueprint()->void:
 var app=controller();app.save_blueprint();var original=app.design.duplicate(true);var pad=app.launcher.duplicate(true);var before=values(app.economy)
 app.economy.designs.workbench.design.append(app.part(90,"shield",0,-1))
 check(app.economy.missing_parts(app.economy.designs.workbench.design,app.economy.designs.workbench.launcher).get("shield",0)==1,"blueprint reports inventory shortage")
 app.load_blueprint()
 check(app.design==original and app.launcher==pad and values(app.economy)==before,"short blueprint leaves workbench and inventory intact")
 app.economy.inventory.shield=1;app.load_blueprint()
 check(app.design.size()==original.size()+1 and app.economy.inventory.shield==1,"owned blueprint neither manufactures nor consumes stock")
 app.economy.accept_contract(str(app.economy.contracts[0].contract_id));app.economy.inventory.shield=0;before=values(app.economy);app.start_flight(false)
 check(app.sim==null and app.economy.in_flight.is_empty() and values(app.economy)==before,"inventory-short design cannot formally dispatch")
 app.free()
func _test_trials()->void:
 var app=controller();var id=str(app.economy.contracts[0].contract_id);app.economy.accept_contract(id);var before=values(app.economy);var design=app.design.duplicate(true);var pad=app.launcher.duplicate(true)
 app.start_flight(true)
 for _i in range(30):app.sim.step(1.0/60.0)
 check(app.trial and app.page=="flight" and app.sim.telemetry.energy_used>0,"trial runs actual energy-consuming simulation")
 app.abort_flight()
 check(app.page=="report" and app.report.trial and not app.report.success,"aborted trial creates trial report")
 check(values(app.economy)==before and app.design==design and app.launcher==pad,"trial failure cannot change funds reputation inventory counters or blueprint")
 check(app.economy.active_contract().status=="accepted" and app.economy.in_flight.is_empty(),"trial preserves accepted order without formal snapshot")
 check(app.economy.last_trials.has(id),"trial comparison is separate from formal history")
 app.start_flight(true);var iterations=0
 while app.sim.status=="running" and iterations<6000:app.sim.step(1.0/60.0);iterations+=1
 app.finish_flight()
 check(app.report.has("comparison") and values(app.economy)==before,"repeat completed trial adds comparison without financial effects")
 var loaded=Econ.new();loaded.load_state()
 check(values(loaded)==before and loaded.active_contract().status=="accepted" and loaded.in_flight.is_empty(),"trial save cannot reload as charged formal delivery")
 app.free()
func _test_controller_settlement()->void:
 _clear_files();var app=controller();var id=str(app.economy.contracts[0].contract_id);app.economy.accept_contract(id);app.start_flight(false)
 check(not app.trial and app.page=="flight" and app.economy.in_flight.contract_id==id,"controller formal launch commits snapshot")
 for _i in range(10):app.sim.step(1.0/60.0)
 app.abort_flight()
 check(app.economy.jobs_today==1 and app.economy.history.size()==1 and app.sim.telemetry.settlement_finalized,"formal abort finalizes losses and settles once")
 var before=values(app.economy);app.finish_flight();app.abort_flight();app.start_flight(false)
 check(values(app.economy)==before and app.economy.in_flight.is_empty(),"repeated report abort and dispatch actions cannot settle twice")
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.settle_contract(id,telemetry(),8.0,true).ok and values(loaded)==before,"settlement guard persists across reload")
 app.free()
func _test_resume()->void:
 _clear_files();var original=controller();original.economy.accept_contract(str(original.economy.contracts[0].contract_id));original.economy.research=2;original.start_flight(false)
 for _i in range(37):original.sim.step(1.0/60.0)
 original.economy.in_flight.elapsed=original.sim.elapsed
 var position=original.sim.cargo_position();var energy=original.sim.telemetry.energy_used;var time=original.sim.elapsed;var seed_value=original.sim.seed_value
 check(original.save_game(),"mid-flight checkpoint saves")
 var restored=controller();var saved=restored.economy.load_state();restored.design=saved.design;restored.launcher=saved.launcher;restored.design[3].param=0.0;restored.economy.research=0;restored._resume_dispatch()
 check(not restored.trial and restored.page=="flight" and restored.sim.seed_value==seed_value,"resume preserves formal state and exact seed")
 check(close(restored.sim.elapsed,time),"serialized elapsed resumes on exact fixed tick (original %.12f resumed %.12f)"%[time,restored.sim.elapsed])
 check(restored.sim.cargo_position().distance_to(position)<0.00001 and close(restored.sim.telemetry.energy_used,energy),"resume reproduces exact position and energy")
 check(close(restored.sim.parts[4].param,3.0) and close(restored.sim.parts[3].capacity,390.0),"resume uses committed craft and research instead of mutable workbench")
 for _i in range(120):original.sim.step(1.0/60.0);restored.sim.step(1.0/60.0)
 check(restored.sim.cargo_position().distance_to(original.sim.cargo_position())<0.00001 and close(restored.sim.telemetry.energy_used,original.sim.telemetry.energy_used),"resumed flight continues deterministically")
 original.launch_countdown=0;original.paused=true;original._process(0.0)
 var committed=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 check(committed.in_flight.has("ticks") and int(committed.in_flight.ticks)==roundi(original.sim.elapsed*60.0),"actual controller checkpoint persists an integer replay tick")
 var explicit=controller();explicit.economy.load_state();explicit._resume_dispatch()
 check(close(explicit.sim.elapsed,original.sim.elapsed) and explicit.sim.cargo_position().distance_to(original.sim.cargo_position())<0.00001,"integer-tick checkpoint restores exact simulation state")
 original.free();restored.free();explicit.free()
func _test_failed_save()->void:
 _clear_files();var app=controller();app.economy.accept_contract(str(app.economy.contracts[0].contract_id));app.save_game();var previous=FileAccess.get_file_as_string("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp");var before=values(app.economy);app.start_flight(false)
 check(app.sim==null and app.economy.in_flight.is_empty() and app.economy.active_contract().status=="accepted","failed launch save rolls back to accepted order")
 check(FileAccess.get_file_as_string("user://savegame.json")==previous and values(app.economy)==before,"failed save preserves prior durable state and finances")
 check(not app.economy.save_error.is_empty(),"save failure carries a player-facing error")
 DirAccess.remove_absolute("user://savegame.tmp");app.free()
func _test_backup()->void:
 _clear_files();var e=econ();e.credits=111
 check(e.save_state(cargo(),[],{"volume":0.25}),"first save creates validated primary")
 e.credits=222
 check(e.save_state(cargo(),[],{"volume":0.75}) and FileAccess.file_exists("user://savegame.backup.json"),"second save retains previous version")
 var backup=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.backup.json"))
 check(backup.credits==111,"backup retains previous committed balance")
 write_primary("BROKEN");var recovered=Econ.new();var data=recovered.load_state()
 check(not data.is_empty() and recovered.credits==111 and not recovered.load_notice.is_empty(),"malformed primary recovers backup with notice")
 e.credits=333;e.save_state(cargo(),[],{});backup=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.backup.json"))
 check(backup.credits==111,"saving after malformed primary preserves good backup")
 write_primary(JSON.stringify({"version":999,"design":[],"launcher":[],"credits":9999}));e.credits=444;e.save_state(cargo(),[],{});backup=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.backup.json"))
 check(backup.version==Econ.SAVE_VERSION and backup.credits==111,"load-invalid JSON primary cannot overwrite known good backup")
 write_primary("BROKEN AGAIN");var second=Econ.new()
 check(not second.load_state().is_empty() and second.credits==111,"backup remains recoverable after schema-invalid primary")
