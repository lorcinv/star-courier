extends SceneTree
## Reproducible route-0 balance evidence using only initial inventory, legal editor
## coordinates, exposed parameters, real contract seeds and unchanged route physics.
## No data is saved. Every run owns a fresh in-memory economy and simulation.
const Sim = preload("res://scripts/simulation.gd")
const Parts = preload("res://scripts/parts.gd")
const EconomyDB = preload("res://scripts/economy.gd")
var results: Array = []
var failures: Array = []
var checks: int = 0

func _initialize() -> void:
	var baseline = run("standard_12N", starter(), pad())
	var economy_design = starter(); economy_design[3].param = 3.0
	var economy = run("economy_3N", economy_design, pad())
	var express_design = starter(); express_design[3].param = 24.0
	express_design.append(p(20, "battery", -4))
	var express = run("express_24N_spare_battery", express_design, pad())
	check(baseline.status == "success", "unchanged starter completes the representative route")
	check(economy.status == "success" and express.status == "success", "two starter-stock alternative blueprints both deliver")
	check(economy.seconds < 14.0 and express.seconds < 14.0, "both alternatives meet the standard deadline")
	check(economy.seconds > express.seconds + 5.0, "economy and express have a meaningful speed tradeoff")
	check(express.energy_J > economy.energy_J + 350.0, "express throughput requires materially more energy")
	check(economy.profit > express.profit + 60, "energy tradeoff is visible in actual settlement profit")
	check(economy.integrity_percent == 100.0 and express.integrity_percent == 100.0, "both recommended narrow builds preserve the full payload")

	# Deliberately change precisely one editor property, then restore that property.
	var faulty_design = starter(); faulty_design[3].rot = 2
	var faulty = run("single_fault_thruster_backwards", faulty_design, pad())
	faulty_design[3].rot = 0
	var fixed = run("single_fix_thruster_forward", faulty_design, pad())
	check(faulty.status == "failed" and fixed.status == "success", "one wrong rotation fails; correcting only rotation fixes delivery")
	check(faulty.lost_cost > 100.0 and fixed.lost_cost == 0.0, "rotation fix removes replacement losses")
	check(absf(fixed.seconds - baseline.seconds) < 0.0001 and absf(fixed.energy_J - baseline.energy_J) < 0.0001, "identical restored blueprints reproduce the exact result")

	# A wider outline clips the rock gate despite a balanced centre of mass.
	var wide_design = starter()
	wide_design.append(p(21, "beam", 0, -1)); wide_design.append(p(22, "beam", 0, 1))
	var wide = run("wide_symmetric_beams", wide_design, pad())
	check(wide.status == "failed", "balanced mass alone cannot compensate for a too-wide collision outline")
	check(wide.energy_J >= baseline.energy_J and wide.lost_cost > baseline.lost_cost, "wide outline visibly wastes energy and replacement cost")

	# Stress-test a tempting faster configuration, rather than recommend it.
	var overloaded = starter(); overloaded[3].param = 40.0
	overloaded.append(p(21, "beam", -2, -1)); overloaded.append(p(22, "beam", -2, 1))
	var overload = run("overload_shortcut_40N", overloaded, pad())
	check(overload.status == "success" and overload.seconds < baseline.seconds, "overloaded shortcut can deliver faster")
	check(overload.integrity_percent < baseline.integrity_percent and overload.lost_cost > 100.0 and overload.profit < 0, "shortcut exposes integrity, structural loss and negative-profit consequences")

	var coast_design = starter(); coast_design[3].param = 0.0
	var coast = run("launch_only_coast", coast_design, pad())
	check(coast.status == "success" and coast.seconds > coast.deadline, "launch-only coasting is possible but late")
	check(coast.reputation == 1 and coast.income < coast.base_income, "late coasting loses income and the top customer rating")

	# The real B contract uses seed101, matching trial and dispatch. No route mutation.
	var heavy_economy_design = starter(); heavy_economy_design[3].param = 2.0
	var heavy_economy = run("heavy_B_2N", heavy_economy_design, pad(), true)
	var heavy_default = run("heavy_B_12N", starter(), pad(), true)
	check(heavy_economy.status == "success" and heavy_economy.seconds < heavy_economy.deadline, "heavier B package has a viable low-power starter-stock solution")
	check(heavy_economy.profit > heavy_default.profit and heavy_default.seconds < heavy_economy.seconds, "heavy B also has a real profit-versus-speed choice")

	for record in results: print(JSON.stringify(record))
	for failure in failures: printerr("FAIL: " + failure)
	print("REPRESENTATIVE_ROUTE_TESTS cases=%d assertions=%d failures=%d" % [results.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func p(id: int, type: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var result = {"id": id, "type": type, "x": x, "y": y, "rot": 0, "param": Parts.defaults(type), "input_a": -1, "input_b": -1, "target": -1}
	result.merge(extra, true)
	return result

func starter() -> Array:
	return [p(1, "cargo", 0), p(2, "beam", -1), p(3, "battery", -2), p(4, "thruster", -3), p(5, "armor", 1)]

func pad() -> Array:
	return [p(10, "spring", 0, 0, {"param": 20.0}), p(11, "battery", -1), p(12, "beam", 1)]

func run(label: String, design: Array, launcher: Array, heavy: bool = false) -> Dictionary:
	var economy = EconomyDB.new()
	economy.starter_stock(starter(), pad())
	check(economy.missing_parts(design, launcher).is_empty(), label + " fits starting inventory")
	var ids: Array = []
	for assembly in [design, launcher]:
		var occupied: Dictionary = {}
		var legal = true
		for item in assembly:
			var cell = Vector2i(item.x, item.y)
			legal = legal and absi(item.x) <= 4 and absi(item.y) <= 2 and not occupied.has(cell) and not ids.has(item.id)
			legal = legal and is_equal_approx(Parts.sanitize_parameter(item.type, item.param), item.param)
			occupied[cell] = true; ids.append(item.id)
		check(legal, label + " uses legal grid positions, unique IDs and exposed parameter ranges")
	var id = "D1-B" if heavy else "D1-A"
	check(economy.accept_contract(id).ok, label + " accepts actual available day-one contract")
	var route = economy.trial_route()
	var seed = int(route.seed)
	check(seed == (101 if heavy else 100) and route.variation == 1.0, label + " uses actual bounded trial/dispatch variation")
	var credits_before = economy.credits
	var stock_before = economy.inventory.duplicate(true)
	var s = Sim.new()
	s.configure(design, launcher, route, seed)
	var safety_steps = 0
	while s.status == "running" and safety_steps < 10000:
		s.step(1.0 / 60.0)
		safety_steps += 1
	check(s.status != "running", label + " reaches a terminal outcome")
	check(economy.credits == credits_before and economy.inventory == stock_before, label + " free simulation has no economy side effect")
	var dispatch = economy.begin_dispatch(design, launcher)
	check(dispatch.ok and dispatch.snapshot.seed == seed and dispatch.snapshot.route.hazards == route.hazards, label + " tested seed and hazards exactly match paid dispatch")
	var settlement = economy.settle_contract(id, s.telemetry, s.elapsed, s.status == "success")
	check(settlement.ok, label + " settles through real contract rules")
	var report = settlement.report
	var record = {"build": label, "seed": seed, "status": s.status, "seconds": snappedf(s.elapsed, 0.001), "deadline": route.deadline, "energy_J": snappedf(s.telemetry.energy_used, 0.01), "integrity_percent": snappedf(s.telemetry.integrity * 100.0, 0.01), "income": report.income, "base_income": report.base_income, "energy_bill": report.energy, "repair_cost": report.repairs, "lost_cost": report.lost, "profit": report.profit, "reputation": report.reputation, "cargo_position": str(s.cargo_position()), "event_tail": s.events.slice(maxi(0, s.events.size() - 4))}
	results.append(record)
	return record
