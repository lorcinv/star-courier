extends SceneTree
## Isolated mechanical design study. Does not mutate production data or savegames.
const Sim = preload("res://scripts/simulation.gd")
const Parts = preload("res://scripts/parts.gd")
const EconomyDB = preload("res://scripts/economy.gd")
var results: Array = []

func p(id: int, type: String, x: int, y: int = 0, extra: Dictionary = {}) -> Dictionary:
	var value = {"id": id, "type": type, "x": x, "y": y, "rot": 0, "param": Parts.defaults(type), "input_a": -1, "input_b": -1, "target": -1}
	value.merge(extra, true)
	return value

func original() -> Array:
	return [p(1, "cargo", 0), p(2, "beam", -1), p(3, "battery", -2), p(4, "thruster", -3), p(5, "armor", 1)]

func pad(joules: float = 20.0, supports: int = 1) -> Array:
	var value = [p(10, "spring", 0, 0, {"param": joules}), p(11, "battery", -1), p(12, "beam", 1)]
	for index in range(1, supports): value.append(p(12 + index, "beam", index, -1))
	return value

func run(label: String, design: Array, launcher: Array, heavy: bool = false, seed: int = 100, gate_y: float = 2.3, deadline: float = 14.0, keep: bool = true, hazard_override: Array = []) -> Dictionary:
	var economy = EconomyDB.new()
	economy.starter_stock(original(), pad())
	# Preserve the pre-study inventory baseline even after the recommended changes ship.
	economy.inventory={"cargo":1,"beam":4,"battery":3,"thruster":1,"armor":1,"spring":1,"probe":1,"delay":1,"not_gate":1,"coupler":1}
	economy.accept_contract("D1-B" if heavy else "D1-A")
	var route = economy.trial_route()
	route.deadline = deadline + (3.0 if heavy else 0.0)
	route.hazards[0].y = -gate_y; route.hazards[1].y = gate_y
	if not hazard_override.is_empty(): route.hazards=hazard_override.duplicate(true);route.variation=0.0
	var sim = Sim.new()
	sim.configure(design, launcher, route, seed)
	var body = sim.body_for_part(1)
	var com = Vector2.ZERO
	var mass = 0.0
	for item in sim.parts.values():
		com += Vector2(item.x, item.y) * item.mass; mass += item.mass
	com /= mass
	var inertia = body.get("inertia", 0.0)
	var min_clearance = INF
	var bounded_clearance = INF
	var max_gate_y = 0.0
	var max_energy_excess=0.0
	var max_kinetic_energy=0.0
	var ticks = 0
	var last_angle = 0.0
	while sim.status == "running" and ticks < 10000:
		sim.step(1.0 / 120.0); ticks += 1
		var kinetic=0.0
		for component in sim.bodies: kinetic+=0.5*component.mass*component.velocity.length_squared()+0.5*component.inertia*component.angular_velocity*component.angular_velocity
		max_kinetic_energy=maxf(max_kinetic_energy,kinetic)
		max_energy_excess=maxf(max_energy_excess,kinetic+sim.telemetry.heat-sim.telemetry.energy_used)
		for item in sim.parts.values():
			if not item.alive or item.delivered: continue
			var at = sim.part_world_position(item.id)
			var possible_dx = maxf(34.6 - at.x, maxf(0.0, at.x - 35.4))
			for sign_y in [-1.0,1.0]:
				var bottom = sign_y * gate_y - 0.25
				var top = sign_y * gate_y + 0.25
				var possible_dy = maxf(bottom - at.y, maxf(0.0, at.y - top))
				bounded_clearance=minf(bounded_clearance,Vector2(possible_dx,possible_dy).length()-1.15-0.43*item.scale)
			if at.x >= 33.02 and at.x <= 36.98: max_gate_y=maxf(max_gate_y,absf(at.y))
			for rock in sim.obstacles:
				min_clearance = minf(min_clearance, sim.part_world_position(item.id).distance_to(rock.position) - rock.radius - 0.43 * item.scale)
		body = sim.body_for_part(1)
		if not body.is_empty(): last_angle = float(body.angle)
	var quote = economy.estimate_delivery(route, sim.telemetry, sim.elapsed, sim.status == "success")
	var record = {"label":label,"heavy":heavy,"seed":seed,"gate_y":gate_y,"status":sim.status,"ticks":ticks,"seconds":sim.elapsed,"deadline":route.deadline,"mass":mass,"centre_of_mass":[com.x,com.y],"inertia":inertia,"energy_J":sim.telemetry.energy_used,"launch_energy_J":sim.telemetry.launch_energy,"integrity_percent":sim.telemetry.integrity*100,"income":quote.income,"energy_bill":quote.energy,"repairs":quote.repairs,"lost":quote.lost,"profit":quote.profit,"final_angle_degrees":rad_to_deg(last_angle),"cargo_position":str(sim.cargo_position()),"min_clearance":min_clearance,"missing_inventory":economy.missing_parts(design,launcher),"incidents":sim.incidents,"events":sim.events}
	record.bounded_variation_clearance=bounded_clearance
	record.maximum_gate_abs_y=max_gate_y
	record.maximum_kinetic_energy_J=max_kinetic_energy
	record.maximum_energy_created_J=max_energy_excess
	record.remaining_flight_energy_J=sim.total_energy()
	record.explicit_hazard_override=hazard_override
	var old_value=stock_value(economy.inventory)
	economy.inventory.thruster+=1;economy.inventory.erase("probe");economy.inventory.erase("delay")
	record.proposed_inventory_missing=economy.missing_parts(design,launcher)
	record.old_inventory_value=old_value
	record.proposed_inventory_value=stock_value(economy.inventory)
	record.editor_legal=editor_legal(design,launcher)
	if keep:
		results.append(record)
		print(JSON.stringify(record))
	return record

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var mode = args[0] if args.size() > 0 else "initial"
	if mode == "initial": initial()
	if mode == "twin": twin()
	if mode == "candidate": candidate()
	if mode == "refine": refine()
	if mode == "robust": robust()
	if mode == "proof": proof()
	if mode == "final": final_checks()
	if mode == "artist": final_checks(true)
	var out = FileAccess.open("res://docs/qa/v4/starter-study-" + mode + ".json", FileAccess.WRITE)
	out.store_string(JSON.stringify(results, "\t")); out.close()
	quit()

func initial() -> void:
	for heavy in [false,true]:
		for thrust in [0.0,2.0,3.0,12.0]:
			var design = original(); design[3].param = thrust
			run("original_%.1fN" % thrust, design, pad(), heavy, 101 if heavy else 100)
	# Three-row compact four-cell spine; the two batteries balance the off-axis mass.
	var balanced = [p(1,"cargo",0),p(2,"beam",-1),p(3,"battery",-1,-1),p(4,"thruster",-2),p(5,"armor",1),p(20,"battery",-1,1)]
	for gate in [2.3,2.8,3.0]:
		for thrust in [2.0,3.0,6.0,12.0]:
			for heavy in [false,true]:
				balanced[3].param=thrust
				run("balanced_4x3_%.1fN" % thrust, balanced, pad(), heavy, 101 if heavy else 100,gate)
	# Five-part two-tier hull with cargo+beam above, battery/engine/nose below.
	var tiered = [p(1,"cargo",0,1),p(2,"beam",-1,1),p(3,"battery",-1),p(4,"thruster",-2),p(5,"armor",0)]
	for thrust in [0.0,0.5,1.0,2.0,3.0,6.0,12.0]:
		for heavy in [false,true]:
			tiered[3].param=thrust
			run("tiered_3x2_%.1fN" % thrust,tiered,pad(60.0,2),heavy,101 if heavy else 100)

func twins() -> Array:
	# Six genuinely connected parts. Row masses are exactly 4.6 kg for standard cargo.
	return [p(1,"cargo",0,0),p(3,"battery",-1,1),p(4,"thruster",-2,0),p(5,"armor",0,1),p(20,"thruster",-2,1),p(21,"coupler",-1,0)]

func twin() -> void:
	for gate in [2.3,2.4,2.5]:
		for thrust in [2.0,3.0,6.0]:
			for heavy in [false,true]:
				var design=twins();design[2].param=thrust;design[4].param=thrust
				run("twin_3x2_%.1fN"%thrust,design,pad(),heavy,101 if heavy else 100,gate)
	# Four-cell span retains a visible stepped upper hull and a protruding lower nose.
	var stepped=[p(1,"cargo",0,0),p(3,"battery",-1,1),p(4,"thruster",-2,0),p(5,"armor",1,0),p(20,"thruster",-2,1),p(21,"coupler",-1,0)]
	for thrust in [2.0,3.0,6.0]:
		stepped[2].param=thrust;stepped[4].param=thrust
		run("unbalanced_twin_4x2_%.1fN"%thrust,stepped,pad(),false,100,2.5)

func standard_4x2(thrust: float = 2.0) -> Array:
	return [p(1,"cargo",0,0),p(2,"beam",1,0),p(3,"battery",-1,1),p(4,"thruster",-2,0,{"param":thrust}),p(5,"armor",1,1),p(20,"thruster",-2,1,{"param":thrust}),p(21,"coupler",-1,0),p(22,"beam",0,1)]

func heavy_4x2(thrust_scale: float = 1.0) -> Array:
	return [p(1,"cargo",0,0),p(2,"beam",0,1),p(3,"battery",-1,0),p(4,"thruster",-2,0,{"param":5.0*thrust_scale}),p(5,"armor",1,0),p(20,"thruster",-2,1,{"param":2.0*thrust_scale}),p(21,"battery",-1,1)]

func candidate() -> void:
	for gate in [2.3,2.4,2.5,2.6]:
		for thrust in [2.0,3.0,6.0]:
			run("standard_4x2_%.1fN"%thrust,standard_4x2(thrust),pad(),false,100,gate)
		for scale in [1.0,2.0]:
			run("heavy_4x2_%.1fx"%scale,heavy_4x2(scale),pad(),true,101,gate)
	# A stronger paid launch makes lower continuous thrust useful without hiding torque.
	for thrust in [1.0,2.0]:
		run("standard_4x2_%.1fN_60J"%thrust,standard_4x2(thrust),pad(60.0,2),false,100,2.5)
		run("heavy_4x2_%.1fx_60J"%thrust,heavy_4x2(thrust),pad(60.0,2),true,101,2.6)

func refine() -> void:
	for gate in [2.3,2.4,2.5,2.6]:
		for thrusts in [[4.0,3.0],[8.0,6.0],[9.0,7.0],[3.0,2.0]]:
			var design=standard_4x2();design[3].param=thrusts[0];design[5].param=thrusts[1]
			run("heavy_original_4x2_%.1f_%.1fN"%thrusts,design,pad(),true,101,gate)
	# Genuine passive damping is an alternative stock change, with measurable heat.
	var damped=[p(1,"cargo",0,0),p(2,"beam",-1,0),p(3,"battery",-1,1),p(4,"thruster",-2,0),p(5,"armor",1,0),p(20,"damper",0,1,{"param":8.0})]
	for thrust in [2.0,3.0,6.0,12.0]:
		for heavy in [false,true]:
			damped[3].param=thrust
			run("damped_4x2_%.1fN"%thrust,damped,pad(),heavy,101 if heavy else 100,2.6)

func robust() -> void:
	for day in range(1,21):
		for gate in [2.4,2.5]:
			for heavy in [false,true]:
				var design=standard_4x2(3.0)
				if heavy: design[3].param=4.0;design[5].param=3.0
				run("robust_4x2_%s" % ("heavy_4_3N" if heavy else "standard_3_3N"),design,pad(),heavy,day*100+(1 if heavy else 0),gate)

func proof() -> void:
	for gate in [2.4,2.5,2.6]:
		for heavy in [false,true]:
			var design=standard_4x2(3.0)
			if heavy: design[3].param=4.0;design[5].param=3.0
			run("bounded_4x2_%s" % ("heavy_4_3N" if heavy else "standard_3_3N"),design,pad(),heavy,101 if heavy else 100,gate)
	# Preserve exact original craft as a control for every proposed gate width.
	for gate in [2.3,2.4,2.5,2.6]:
		for heavy in [false,true]: run("legacy_5x1_control",original(),pad(),heavy,101 if heavy else 100,gate)
	# The expanded two-row gate must still reject an over-wide novice silhouette.
	var wide=original();wide.append(p(21,"beam",0,-1));wide.append(p(22,"beam",0,1))
	for gate in [2.4,2.5,2.6]: run("wide_3row_control",wide,pad(),false,100,gate)

func stock_value(stock: Dictionary) -> int:
	var value=0
	for type in stock:
		var spec=Parts.cargo_spec() if type=="cargo" else Parts.catalog()[type]
		value+=int(stock[type])*int(spec.price)
	return value

func editor_legal(design: Array,launcher: Array) -> bool:
	var ids=[]
	for assembly in [design,launcher]:
		var cells=[]
		for item in assembly:
			var cell=Vector2i(item.x,item.y)
			if absi(item.x)>4 or absi(item.y)>2 or cells.has(cell) or ids.has(item.id):return false
			if not is_equal_approx(Parts.sanitize_parameter(item.type,item.param),item.param):return false
			if not is_equal_approx(snappedf(item.param,Parts.parameter_schema(item.type).step),item.param):return false
			cells.append(cell);ids.append(item.id)
	return true

func artist_4x2(thrust: float = 3.0) -> Array:
	return [p(1,"cargo",0,0),p(2,"beam",-1,0),p(3,"battery",0,1),p(4,"thruster",-2,0,{"param":thrust}),p(5,"armor",1,1),p(6,"thruster",-2,1,{"param":thrust}),p(7,"beam",-1,1),p(8,"coupler",1,0)]

func final_checks(artist: bool = false) -> void:
	for day in range(1,21):
		for heavy in [false,true]:
			var design=artist_4x2() if artist else standard_4x2(3.0)
			if heavy:design[3].param=4.0;design[5].param=3.0
			run("final_%s"%("heavy_4_3N" if heavy else "standard_3_3N"),design,pad(),heavy,day*100+(1 if heavy else 0),2.6)
	for heavy in [false,true]:
		var design=artist_4x2() if artist else standard_4x2(3.0)
		if heavy:design[3].param=4.0;design[5].param=3.0
		for ax in [-0.4,0.4]:
			for ay in [-0.25,0.25]:
				for bx in [-0.4,0.4]:
					for by in [-0.25,0.25]:
						var hazards=[{"x":35.0+ax,"y":-2.6+ay,"radius":1.15,"type":"rock"},{"x":35.0+bx,"y":2.6+by,"radius":1.15,"type":"rock"}]
						run("extremal_%s"%("heavy" if heavy else "standard"),design,pad(),heavy,101 if heavy else 100,2.6,14.0,true,hazards)
	# Economy alternative retains the same physical layout and unchanged 20 J pad.
	run("final_standard_economy_2_2N",artist_4x2(2.0) if artist else standard_4x2(2.0),pad(),false,100,2.6)
	# Retaining the standard thrust for the heavy contract exposes real COM shift.
	run("heavy_untuned_3_3N",artist_4x2() if artist else standard_4x2(3.0),pad(),true,101,2.6)
	# User-visible one-property mistake and single-property restoration.
	var faulty=artist_4x2() if artist else standard_4x2(3.0);faulty[3].rot=2
	run("wrong_cargo_row_engine_rotation",faulty,pad(),false,100,2.6)
	faulty[3].rot=0
	run("restored_cargo_row_engine_rotation",faulty,pad(),false,100,2.6)
