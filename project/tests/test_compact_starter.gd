extends SceneTree
## Production regression for the honest 4x2 starter. Run with fresh isolated XDG data.
const Sim = preload("res://scripts/simulation.gd")
const Parts = preload("res://scripts/parts.gd")
const Econ = preload("res://scripts/economy.gd")
const FIXED_DT = 1.0 / 120.0
const EXPECTED_STOCK = {"cargo":1,"beam":4,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1,"not_gate":1}
const LEGACY_STOCK = {"cargo":1,"beam":4,"battery":3,"thruster":1,"armor":1,"spring":1,"probe":1,"delay":1,"not_gate":1,"coupler":1}
var checks: int = 0
var failures: Array = []
var cases: int = 0
var starter: Array = []
var launcher: Array = []

class Controller extends "res://scripts/main.gd":
	# Exercise the production _ready/save-loading path, replacing only presentation.
	func _build_ui() -> void: pass
	func _apply_quality() -> void: pass
	func render() -> void: pass
	func notify(_message: String) -> void: pass
	func _play_music(_flying: bool) -> void: pass

func _initialize() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("Compact starter tests require a fresh isolated XDG_DATA_HOME.");quit(2);return
	if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
		printerr("Compact starter tests refuse to overwrite an existing save. Use fresh XDG data.");quit(2);return
	run.call_deferred()

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition: failures.append(title)

func same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func p(id: int, type: String, x: int, y: int = 0, param: float = NAN) -> Dictionary:
	return {"id":id,"type":type,"x":x,"y":y,"rot":0,"param":Parts.defaults(type) if is_nan(param) else param,"input_a":-1,"input_b":-1,"target":-1}

func expected_starter() -> Array:
	return [p(1,"cargo",0,0),p(2,"beam",-1,0),p(3,"battery",0,1),p(4,"thruster",-2,0,3.0),p(5,"armor",1,1),p(6,"thruster",-2,1,3.0),p(7,"beam",-1,1),p(8,"coupler",1,0)]

func old_starter() -> Array:
	return [p(1,"cargo",0),p(2,"beam",-1),p(3,"battery",-2),p(4,"thruster",-3),p(5,"armor",1)]

func expected_launcher() -> Array:
	return [p(10,"spring",0,0,20.0),p(11,"battery",-1),p(12,"beam",1)]

func stock_value(stock: Dictionary) -> int:
	var value = 0
	for type in stock:
		var spec = Parts.cargo_spec() if type == "cargo" else Parts.catalog()[type]
		value += int(stock[type]) * int(spec.price)
	return value

func run() -> void:
	_test_production_starter()
	_test_route_and_inventory()
	_test_flights()
	await _test_existing_save()
	for failure in failures: printerr("FAIL: " + failure)
	print("COMPACT_STARTER_TESTS cases=%d passed=%d failed=%d total=%d" % [cases,checks-failures.size(),failures.size(),checks])
	quit(0 if failures.is_empty() else 1)

func _test_production_starter() -> void:
	var controller = Controller.new()
	controller._starter()
	starter = controller.design.duplicate(true); launcher = controller.launcher.duplicate(true)
	check(same(starter,expected_starter()),"actual main._starter uses the exact artist-facing IDs, coordinates, parameters and wires")
	check(same(launcher,expected_launcher()),"actual launcher remains the original three-part 20 J pad")
	check(controller.next_id == 20,"starter IDs 1-8 and launcher IDs 10-12 preserve next_id 20")
	var low = Vector2(INF,INF); var high = Vector2(-INF,-INF)
	var row_masses = {0:0.0,1:0.0}
	for item in starter:
		low = low.min(Vector2(item.x,item.y)); high = high.max(Vector2(item.x,item.y))
		var spec = Parts.cargo_spec() if item.type == "cargo" else Parts.catalog()[item.type]
		row_masses[item.y] = float(row_masses.get(item.y,0.0)) + float(spec.mass)
	check(high-low == Vector2(3,1),"real module centres occupy four columns and two rows")
	check(is_equal_approx(row_masses[0],5.1) and is_equal_approx(row_masses[1],5.1),"standard rows each carry 5.1 kg without changing part masses")
	controller.free()

func _test_route_and_inventory() -> void:
	var economy = Econ.new(); economy.starter_stock(starter,launcher)
	check(same(economy.inventory,EXPECTED_STOCK),"new-game stock is the fixed value-neutral inventory")
	check(stock_value(economy.inventory)==375 and stock_value(LEGACY_STOCK)==375,"old and new starting hardware both cost exactly 375 credits")
	check(economy.credits==260,"compact starter leaves starting cash at 260")
	check(economy.missing_parts(starter,launcher).is_empty(),"actual starter and launcher are fully owned")
	var remaining = economy.inventory.duplicate(true)
	for item in starter+launcher: remaining[item.type] -= 1
	remaining = remaining.duplicate(true)
	for type in remaining.keys():
		if int(remaining[type])==0: remaining.erase(type)
	check(same(remaining,{"beam":1,"battery":1,"not_gate":1}),"new-game leftover stock is one beam, one battery and one not gate")
	var inflated = starter.duplicate(true); inflated.append(p(99,"thruster",4,2))
	economy.starter_stock(inflated,launcher)
	check(same(economy.inventory,EXPECTED_STOCK),"passing a larger blueprint cannot mint extra starter inventory")
	var route = economy.routes()[0]
	check(same(route.hazards,[{"x":35.0,"y":-2.6,"radius":1.15,"type":"rock"},{"x":35.0,"y":2.6,"radius":1.15,"type":"rock"}]),"only the intended symmetric first-route gap geometry is used")
	check(route.distance==64.0 and route.weight==1.0 and route.deadline==14.0 and route.reward==165,"first-route distance, standard cargo, deadline and reward are preserved")
	check(route.gravity==0.0 and route.wind==0.0 and route.delivery_radius==5.0 and route.max_delivery_speed==24.0,"first-route dynamics and receiver constraints are preserved")
	var heavy = economy.contract_by_id("D1-B")
	check(is_equal_approx(heavy.weight,1.55) and heavy.deadline==17.0 and heavy.reward==220,"heavy contract keeps its original weight, deadline and reward")

func _test_flights() -> void:
	for day in [1,2,3,7,14,20]:
		for heavy in [false,true]:
			var design = starter.duplicate(true)
			if heavy: design[3].param = 4.0
			var result = fly(design,heavy,day,[],day==1)
			check_delivery(result,heavy,"day %d %s" % [day,"B" if heavy else "A"])
			if day==1:
				check(result.bounded_clearance>(0.08 if heavy else 0.269),"whole allowed hazard-position rectangle has positive clearance for "+("B" if heavy else "A"))
				check(result.maximum_energy_excess<0.001,"finite battery and launcher energy bound kinetic energy for "+("B" if heavy else "A"))
	# Independently place both rocks at every allowed x/y extreme, not favorable seeds.
	for heavy in [false,true]:
		var design = starter.duplicate(true)
		if heavy: design[3].param = 4.0
		for ax in [-0.4,0.4]:
			for ay in [-0.25,0.25]:
				for bx in [-0.4,0.4]:
					for by in [-0.25,0.25]:
						var hazards = [{"x":35.0+ax,"y":-2.6+ay,"radius":1.15,"type":"rock"},{"x":35.0+bx,"y":2.6+by,"radius":1.15,"type":"rock"}]
						check_delivery(fly(design,heavy,1,hazards),heavy,"extreme [%s,%s,%s,%s] %s" % [ax,ay,bx,by,"B" if heavy else "A"])
	var efficient = starter.duplicate(true); efficient[3].param=2.0; efficient[5].param=2.0
	var economy_flight = fly(efficient)
	check(economy_flight.status=="success" and economy_flight.ticks==1639 and economy_flight.report.profit==115,"2 N / 2 N is a deterministic on-time higher-profit alternative")
	check(economy_flight.incidents.is_empty() and absf(economy_flight.energy-274.501088351)<0.001,"economy setting retains all hardware and uses the measured finite energy")
	var untuned = fly(starter,true)
	check(untuned.status=="failed" and untuned.report.profit<0,"heavy cargo genuinely shifts the COM and untuned equal thrust fails")
	var backwards = starter.duplicate(true); backwards[3].rot=2
	check(fly(backwards).status=="failed","one backwards engine genuinely fails without scripted success")
	backwards[3].rot=0
	check_delivery(fly(backwards),false,"restoring only the wrong engine rotation")
	for heavy in [false,true]:
		var legacy = fly(old_starter(),heavy)
		check(legacy.status=="success" and legacy.ticks==(1160 if heavy else 1055),"legacy narrow blueprint retains its exact flight time for "+("B" if heavy else "A"))
		check(legacy.report.profit==(162 if heavy else 107) and legacy.incidents.is_empty(),"legacy narrow blueprint retains intact delivery and profit for "+("B" if heavy else "A"))

func check_delivery(result: Dictionary, heavy: bool, label: String) -> void:
	check(result.status=="success",label+" succeeds")
	check(result.ticks==(1459 if heavy else 1418),label+" retains the exact deterministic fixed-step count")
	check(result.elapsed<(17.0 if heavy else 14.0),label+" beats its unchanged deadline")
	check(absf(result.energy-320.0)<0.00001,label+" consumes exactly the finite 300 J battery plus 20 J launch")
	check(result.integrity==1.0 and result.incidents.is_empty(),label+" preserves all cargo and hardware without contact damage")
	check(result.report.income==(220 if heavy else 165) and result.report.energy==58,label+" earns the unchanged full reward and pays the real energy bill")
	check(result.report.repairs==0 and result.report.lost==0 and result.report.profit==(162 if heavy else 107),label+" has no repairs/losses and the expected real settlement profit")

func fly(design: Array, heavy: bool = false, day: int = 1, hazards: Array = [], measure: bool = false) -> Dictionary:
	cases += 1
	var economy = Econ.new(); economy.day=day; economy.starter_stock(starter,launcher)
	var id = "D%d-%s" % [day,"B" if heavy else "A"]
	check(economy.missing_parts(design,launcher).is_empty(),id+" test blueprint fits real starting stock")
	check(economy.accept_contract(id).ok,id+" accepts an actual available contract")
	var route = economy.trial_route(); var seed = int(route.seed)
	check(seed==day*100+(1 if heavy else 0) and route.variation==1.0,id+" uses the actual paid/trial seed formula and bounded variation")
	var boundary_route = route.duplicate(true)
	if not hazards.is_empty(): route.hazards=hazards.duplicate(true); route.variation=0.0
	var sim = Sim.new(); sim.configure(design,launcher,route,seed)
	var ticks=0; var bounded_clearance=INF; var maximum_energy_excess=0.0
	while sim.status=="running" and ticks<10000:
		sim.step(FIXED_DT); ticks+=1
		if not measure: continue
		var kinetic=0.0
		for body in sim.bodies: kinetic+=0.5*body.mass*body.velocity.length_squared()+0.5*body.inertia*body.angular_velocity*body.angular_velocity
		maximum_energy_excess=maxf(maximum_energy_excess,kinetic+sim.telemetry.heat-sim.telemetry.energy_used)
		for item in sim.parts.values():
			if not item.alive or item.delivered: continue
			var at=sim.part_world_position(item.id)
			for hazard in boundary_route.hazards:
				var dx=maxf(hazard.x-0.4-at.x,maxf(0.0,at.x-hazard.x-0.4))
				var dy=maxf(hazard.y-0.25-at.y,maxf(0.0,at.y-hazard.y-0.25))
				bounded_clearance=minf(bounded_clearance,Vector2(dx,dy).length()-hazard.radius-0.43*item.scale)
	check(sim.status!="running",id+" reaches a terminal outcome")
	check(economy.credits==260 and economy.history.is_empty(),id+" free simulation has no financial side effects")
	var dispatch=economy.begin_dispatch(design,launcher)
	check(dispatch.ok and dispatch.snapshot.seed==seed,id+" real dispatch retains the tested seed")
	if hazards.is_empty(): check(same(dispatch.snapshot.route.hazards,route.hazards),id+" paid dispatch retains exactly the tested production hazards")
	var settlement=economy.settle_contract(id,sim.telemetry,sim.elapsed,sim.status=="success")
	check(settlement.ok,id+" settles through production economy rules")
	return {"status":sim.status,"ticks":ticks,"elapsed":sim.elapsed,"energy":sim.telemetry.energy_used,"integrity":sim.telemetry.integrity,"incidents":sim.incidents.duplicate(true),"report":settlement.report,"bounded_clearance":bounded_clearance,"maximum_energy_excess":maximum_energy_excess}

func _test_existing_save() -> void:
	var old_design=old_starter(); old_design[3].param=7.0
	var old_pad=expected_launcher(); old_pad[0].param=16.0
	var old_economy=Econ.new(); old_economy.inventory=LEGACY_STOCK.duplicate(true); old_economy.credits=713; old_economy.day=7
	old_economy.designs["workbench"]={"design":old_design.duplicate(true),"launcher":old_pad.duplicate(true)}
	check(old_economy.save_state(old_design,old_pad,{"volume":0.2,"fullscreen":false}),"writes a pre-existing custom five-part blueprint and legacy stock")
	var controller=Controller.new(); root.add_child(controller); controller.set_process(false)
	await process_frame
	check(same(controller.design,old_design) and same(controller.launcher,old_pad),"real main._ready restores saved coordinates/parameters instead of replacing them with the new starter")
	check(same(controller.economy.inventory,LEGACY_STOCK),"old saved stock keeps its probe/delay and single engine without an unsolicited conversion")
	check(controller.economy.credits==713 and controller.economy.day==7,"old saved business progress survives new starter initialization")
	check(same(controller.economy.designs,old_economy.designs),"old named blueprint slots remain unchanged")
	controller.queue_free(); await process_frame; await process_frame
	for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
		var path="user://"+name
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
