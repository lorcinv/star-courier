extends SceneTree
## Isolated CPU/headless evidence only. No production scene or graphical renderer.
const Catalog = preload("res://scripts/seeded_offer_catalog.gd")
const Guard = preload("res://scripts/seeded_offer_guard.gd")
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ground = preload("res://scripts/pilot_ground_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")
const Stories = preload("res://scripts/courier_stories.gd")
const Econ = preload("res://scripts/economy.gd")
var failures: Array = []
var assertions = 0
var data_count = 0
var fallback_count = 0
var simulations: Array = []
var coverage: Dictionary = {"layout":{},"task":{},"dialogue":{},"length":{},"geometry":{}}
var started: int
var pause_file: String = ""

func _initialize() -> void:
	started=Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pause-file="):pause_file=arg.trim_prefix("--pause-file=")
	if "--probe-only" in OS.get_cmdline_user_args():
		print("SEED_DIGEST:",_probe_fingerprint());quit();return
	_test_prng_and_data()
	_test_faults_and_fallback()
	_test_migration_and_unknown()
	_test_economy_boundary()
	_test_failed_next_day()
	_test_frozen_sources()
	if not "--data-only" in OS.get_cmdline_user_args():
		_test_reference_inputs()
		_test_negative_controls()
	var report={"stage":"seeded-offers-v1", "engine":Engine.get_version_info().string,"assertions":assertions,"failures":failures,
		"data_offers":data_count,"unexpected_fallbacks":fallback_count,"coverage":coverage,"simulations":simulations,
		"fingerprint":_probe_fingerprint(),"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"evidence_kind":"isolated headless; synthetic W/release/S commands; not GUI, native input, human fairness or arbitrary-craft certification"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	for item in failures: printerr("FAIL ",item)
	print("SEEDED_QA assertions=%d failures=%d data=%d guided=%d seconds=%.2f"%[assertions,failures.size(),data_count,simulations.size(),report.elapsed_seconds])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	assertions+=1
	if not value: failures.append(label)

func same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in a.size():
			if not same(a[index],b[index]):return false
		return true
	return a==b

func roundtrip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value,"",true,true))

func base(kind: String) -> Dictionary:
	return {"id":0 if kind=="ground" else 2,"weight":1.0 if kind=="ground" else 2.0,"reward":165 if kind=="ground" else 280,"rep":0 if kind=="ground" else 4,"name":"catalog","cargo":"catalog","client":"catalog"}

func make(seed_value: int, kind: String, slot: int, day: int=7) -> Dictionary:
	return Catalog.create_new_offer(base(kind),{"version":Catalog.VERSION,"world_seed":seed_value},day,slot,kind,Stories.IDS[posmod((day-1)*2+slot,4)])

func _test_prng_and_data() -> void:
	var stream=Catalog.LocalStream.new(1)
	check(stream.take(2147483647)==48271 and stream.take(2147483647)==182605794,"frozen arithmetic PRNG golden vector")
	# No global RNG draws are consumed by any helper.
	seed(123456);var expected_random=randi();seed(123456)
	var initial=make(42,"ground",0)
	check(randi()==expected_random,"new offers do not consume global random state")
	check(initial.ok,"first smoke generation: "+str(initial.get("error")))
	if not initial.ok:return
	var data:Dictionary=base("ground");var old=data.duplicate(true)
	Catalog.create_new_offer(data,{"version":Catalog.VERSION,"world_seed":42},7,0,"ground","human_courier")
	check(data==old,"catalog input never mutates")
	var reordered:Dictionary={}
	var keys:Array=data.keys();keys.reverse()
	for key in keys:reordered[key]=data[key]
	var left=Catalog.create_new_offer(data,{"version":Catalog.VERSION,"world_seed":42},7,0,"ground","human_courier")
	var right=Catalog.create_new_offer(reordered,{"world_seed":42.0,"version":Catalog.VERSION},7.0,0.0,"ground","human_courier")
	check(same(left,right),"Dictionary insertion order and JSON integer types do not alter choices")
	for sample in range(512):
		var seed_value:int=[0,1,42,2147483646][sample] if sample<4 else (sample*104729)%2147483647
		var day:int=1+(sample%53)
		for kind in ["ground","ascent"]:
			for slot in [0,1]:
				var outcome=make(seed_value,kind,slot,day)
				check(outcome.ok,"seed sample %d %s/%d: %s"%[sample,kind,slot,str(outcome.get("error"))])
				if not outcome.ok:continue
				var offer:Dictionary=outcome.offer;data_count+=1
				if outcome.fallback:fallback_count+=1
				check(same(offer,make(seed_value,kind,slot,day).offer),"repeated generation has no stateful cursor")
				check(same(offer,roundtrip(offer)),"every complete route/metadata/dialogue value survives JSON exactly")
				check(Guard.saved_metadata_error(roundtrip(offer)).is_empty(),"saved snapshot validates without regenerating")
				check(Econ.route_validation_error(offer).is_empty(),"isolated economy admits safe generated snapshot")
				coverage.layout[offer.generation.layout_template]=true
				coverage.task[offer.generation.task_template]=true
				coverage.dialogue[offer.generation.dialogue.id]=true
				coverage.length[str(offer.distance)]=true
				coverage.geometry[JSON.stringify(offer.pilot_gates)]=true
	check(fallback_count==0,"all bounded generated samples pass without masking failures with fallback")
	check(coverage.layout.size()==6 and coverage.task.size()==4 and coverage.dialogue.size()==8,"all authored layout, task and customer dialogue choices are exercised")
	check(coverage.length.size()>=15 and coverage.geometry.size()>500,"seeds vary actual saved lengths and physical gate geometry")
	var reference=Guard.clearance_for_design(initial.offer,Extreme.starter_design())
	check(reference.reference_envelope and reference.rotation_independent_radius>1.8,"full eight-part rotational envelope includes diagonally placed modules")
	var large:Array=Extreme.starter_design();large.append(Extreme.part(99,"beam",20,9));var original_large=large.duplicate(true)
	var warning=Guard.clearance_for_design(initial.offer,large)
	check(not warning.reference_envelope and warning.gate_margin<0 and large==original_large,"oversized craft gets honest clearance data, not mutation or arbitrary rejection")
	# Compact the report while retaining unique counts and template coverage.
	coverage.geometry={"unique_snapshot_count":coverage.geometry.size()}

func _test_faults_and_fallback() -> void:
	var original:Dictionary=make(42,"ground",0).offer
	for value in [-1,2147483647,0.5,INF,NAN,"42",null]:
		var result=Catalog.create_new_offer(base("ground"),{"version":Catalog.VERSION,"world_seed":value},1,0,"ground","human_courier")
		check(not result.ok and result.offer.is_empty(),"bad seed rejected without default seed coercion: "+str(value))
	for context in [[0,0],[1,-1],[1,2],[1.5,0],[1,0.5]]:
		check(not Catalog.create_new_offer(base("ground"),{"version":Catalog.VERSION,"world_seed":42},context[0],context[1],"ground","human_courier").ok,"invalid day/slot rejected")
	for state in ["available","accepted","in_flight","settled","cancelled","declined"]:
		var committed:Dictionary=original.duplicate(true);committed.status=state
		var saved=committed.duplicate(true)
		check(not Catalog.create_new_offer(committed,{"version":Catalog.VERSION,"world_seed":42},2,1,"ground","human_courier").ok,"never author a saved "+state+" offer")
		check(Catalog.restore_offer(committed).offer==saved and committed==saved,"restore leaves "+state+" snapshot exact")
	var mutations:Array=[]
	var bad=original.duplicate(true);bad.pilot_gates[0].half_gap=0.5;mutations.append(bad)
	bad=original.duplicate(true);bad.hazards[0].position=[0,0];mutations.append(bad)
	bad=original.duplicate(true);bad.hazards[0].velocity=[100,0];mutations.append(bad)
	bad=original.duplicate(true);bad.pilot_gates[0].x=1.0;mutations.append(bad)
	bad=original.duplicate(true);bad.generation.clearance.witness_points[0]=[2,2];mutations.append(bad)
	bad=original.duplicate(true);bad.deadline=4.0;mutations.append(bad)
	bad=original.duplicate(true);bad.pilot_battery_multiplier=200.0;mutations.append(bad)
	bad=original.duplicate(true);bad.generation.dialogue.story_id="someone_elses_story";mutations.append(bad)
	bad=original.duplicate(true);bad.generation.dialogue.appearance_id="missing";mutations.append(bad)
	bad=original.duplicate(true);bad.generation.seed=0.1;mutations.append(bad)
	bad=original.duplicate(true);bad.distance=NAN;mutations.append(bad)
	bad=original.duplicate(true);bad.generation.clearance=null;mutations.append(bad)
	bad=original.duplicate(true);bad.generation.dialogue.accept_lines=[42,null];mutations.append(bad)
	for key in ["id","rep"]:
		bad=original.duplicate(true);bad.erase(key);mutations.append(bad)
		bad=original.duplicate(true);bad[key]="wrong";mutations.append(bad)
	bad=original.duplicate(true);bad.id=2;mutations.append(bad)
	for index in mutations.size():
		var corrupt:Dictionary=mutations[index];var before=corrupt.duplicate(true)
		check(not Guard.generated_offer_error(corrupt).is_empty(),"unsafe geometry/metadata corruption %d rejected"%index)
		var restored=Catalog.restore_offer(corrupt)
		check(not restored.ok,"corrupt saved snapshot blocks with recovery error, never fallback")
		var fallback=Catalog.accept_candidate_or_fallback(corrupt,base("ground"),{"version":Catalog.VERSION,"world_seed":42},7,0,"ground","human_courier")
		check(fallback.ok and fallback.fallback and fallback.offer.generation.fallback,"new candidate corruption %d uses one bounded authored fallback"%index)
		check(fallback.offer.distance==360.0 and fallback.offer.pilot_gates==_snapped_ground_gates(),"fallback geometry is the existing authored ground route")
	var mismatched=Catalog.accept_candidate_or_fallback(make(100,"ground",0).offer,base("ground"),{"version":Catalog.VERSION,"world_seed":42},7,0,"ground","human_courier")
	check(mismatched.ok and mismatched.fallback and mismatched.offer.generation.world_seed==42,"a valid candidate from a different request cannot replace the requested seed")
	var second=Catalog.accept_candidate_or_fallback(mutations[0],base("ground"),{"version":Catalog.VERSION,"world_seed":42},7,0,"ground","human_courier")
	check(second.offer==Catalog.accept_candidate_or_fallback(mutations[1],base("ground"),{"version":Catalog.VERSION,"world_seed":42},7,0,"ground","human_courier").offer,"fallback provenance is deterministic, with no time or extra rerolls")

func _snapped_ground_gates() -> Array:
	return Ground.route().pilot_gates

func _test_migration_and_unknown() -> void:
	for version in range(1,6):
		var authored:Dictionary=Ground.route({"contract_id":"old-A","status":"accepted","weight":1.55,"reward":220,"id":0})
		var raw={"version":version,"day":5,"contracts":[authored],"in_flight":{"route":authored.duplicate(true),"seed":501,"ticks":12,"input_commands":[{"tick":0,"axis_q":0,"boost":false,"active":false}]},"settled_ids":{"old": {"success":true,"income":99}},"credits":123,"story_state":{"world_seed":900}}
		var old=raw.duplicate(true);var migrated=Catalog.initialize_save(raw,900)
		check(migrated.ok and raw==old,"v%d seed migration never mutates source"%version)
		var without_seed=migrated.save.duplicate(true);without_seed.erase("offer_generation_state")
		check(without_seed==old,"v%d all authored routes, replay inputs and commercial state preserved"%version)
		check(Catalog.initialize_save(migrated.save,12).save==migrated.save,"repeated seed initialization never chooses another seed")
		check(same(Catalog.initialize_save(roundtrip(migrated.save),7).save,migrated.save),"JSON reload retains world seed and old snapshots")
	var future:Dictionary=make(77,"ascent",1).offer
	future.generation={"version":"seeded-offers-v999","future_template":{"opaque":["keep",123.0]},"seed":9}
	var previous=future.duplicate(true)
	check(Catalog.restore_offer(future).ok and Catalog.restore_offer(future).offer==previous,"unknown safe generation is opaque and preserved, not interpreted as v1")
	check(Econ.route_validation_error(future).is_empty(),"known saved pilot-v3 physics remains usable with opaque future content metadata")
	future.control_version="pilot-v999"
	check(not Econ.route_validation_error(future).is_empty(),"opaque generation never bypasses unsupported physics protection")
	for key in ["hazards","pilot_gates","id","rep"]:
		var unsafe_future=previous.duplicate(true)
		unsafe_future[key]=[null] if key in ["hazards","pilot_gates"] else "bad"
		check(not Catalog.restore_offer(unsafe_future).ok,"opaque generation still rejects unsafe physical/contract shape: "+key)
		check(unsafe_future.generation==previous.generation,"rejecting malformed future physics does not interpret or mutate its metadata")
	for key in ["fire_interval","tracking","conductive"]:
		var unsafe_future=previous.duplicate(true);unsafe_future.hazards[0].type="turret";unsafe_future.hazards[0][key]={}
		check(not Catalog.restore_offer(unsafe_future).ok,"future weapon/flag inputs must retain the solver-consumed type: "+key)
	for bad_metadata in [42,{"version":""},{"version":"future","bad":NAN},{"version":"future","bad":Vector2.ZERO}]:
		var invalid=previous.duplicate(true);invalid.generation=bad_metadata
		check(not Catalog.restore_offer(invalid).ok,"unsafe future metadata has recovery error without regeneration")
	var unknown_state={"version":"future-v2","world_seed":42,"extra":{"preserve":true}}
	check(Catalog.initialize_save({"offer_generation_state":unknown_state},9).save.offer_generation_state==unknown_state,"future save-generation state is retained verbatim")
	check(not Catalog.create_new_offer(base("ground"),unknown_state,1,0,"ground","human_courier").ok,"future generation state cannot create disguised v1 offers")
	for saved in [Ground.route(),Extreme.route(),{"control_version":"pilot-v1"},{"simulation_version":"autonomous-v5"}]:
		check(Catalog.restore_offer(saved).offer==saved and not Catalog.restore_offer(saved).offer.has("generation"),"authored legacy snapshot is never retrofitted")

func _test_economy_boundary() -> void:
	var economy=Econ.new();economy.enable_extreme_mode();economy.ensure_contracts()
	var old_offers=economy.contracts.duplicate(true)
	for key in ["id","rep"]:
		var malformed:Dictionary=make(42,"ground",0,1).offer;malformed.erase(key)
		var unsafe=Econ.new();unsafe.contracts=[malformed]
		check(not unsafe.accept_contract("D1-A").ok,"malformed saved "+key+" blocks before economy dereference")
	check(economy.enable_seeded_offers(456).ok,"explicit opt-in initializes private content seed")
	economy.ensure_contracts()
	check(economy.contracts==old_offers,"opt-in never replaces pre-existing available authored offers")
	var fresh=Econ.new();fresh.enable_extreme_mode();fresh.enable_seeded_offers(456);fresh.ensure_contracts()
	check(fresh.contracts.size()==2 and fresh.contracts[0].has("generation") and fresh.contracts[1].has("generation"),"only fresh new-offer boundary materializes two complete snapshots")
	if fresh.contracts.size()!=2:return
	var initial=fresh.contracts.duplicate(true)
	for iteration in range(30): fresh.ensure_contracts();fresh.available_contracts();fresh.contract_by_id("D1-A")
	check(fresh.contracts==initial,"repeated UI reads/ensure calls cannot reroll offers")
	check(fresh.accept_contract("D1-A").ok,"generated offer can use normal acceptance")
	var accepted=fresh.contracts[0].duplicate(true)
	var trial=fresh.trial_route();var trial_again=fresh.trial_route()
	check(trial==trial_again and fresh.contracts[0]==accepted,"repeated trials reuse saved geometry and task values")
	var launch=fresh.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher())
	check(launch.ok,"normal dispatch commits the generated snapshot")
	if not launch.ok:return
	var expected_route=trial.duplicate(true);expected_route.erase("seed");expected_route.status="in_flight"
	check(launch.snapshot.route==expected_route,"trial and formal dispatch share complete saved route, including generation metadata")
	check(fresh.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"isolated real atomic economy save contains complete generated snapshots")
	var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
	check(same(disk.offer_generation_state,fresh.offer_generation_state) and same(disk.in_flight,fresh.in_flight),"saved seed and committed flight coexist in one durable file")
	var reloaded=Econ.new();reloaded.load_state();var before=reloaded.contracts.duplicate(true)
	reloaded.enable_extreme_mode();reloaded.ensure_contracts();reloaded.enable_seeded_offers(999)
	check(same(reloaded.contracts,fresh.contracts) and same(reloaded.in_flight,fresh.in_flight),"restart/mode opt-in and changed caller seed cannot reroll a committed dispatch")
	check(reloaded.contracts==before and reloaded.offer_generation_state.world_seed==456,"restored seed remains authoritative")
	var saved_future=initial[1].duplicate(true);saved_future.generation={"version":"future","payload":{"keep":true}}
	reloaded.contracts=[saved_future];reloaded.enable_ascent_mode();reloaded.enable_pilot_mode();reloaded.enable_extreme_mode()
	check(reloaded.contracts[0]==saved_future,"mode migrations cannot re-author even unaccepted future generated snapshots")
	# NPC story binding stays the existing owner; generated dialogue is review-only.
	var story=Econ.new();story.enable_extreme_mode();story.enable_seeded_offers(9);story.story_state=Stories.initial_state(12);story.enable_story_mode()
	check(story.contracts[0].appearance_id==story.contracts[0].generation.dialogue.appearance_id,"normal day/slot identity agrees with saved dialogue choice")
	check(story.contracts[1].cargo.ends_with(story.contracts[1].generation.dialogue.cargo),"existing story binding and generated task cargo remain coherent")
	check(story.credits==260 and story.settled_ids.is_empty(),"generation and dialogue grant no money, reputation or settlement")

func _test_frozen_sources() -> void:
	if not FileAccess.file_exists("res://tests/fixtures/seeded_frozen_sources_v1.json"):
		check(false,"required frozen dependency manifest exists");return
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/seeded_frozen_sources_v1.json"))
	if not raw is Dictionary:
		check(false,"frozen dependency manifest parses as a dictionary");return
	var hashes:Dictionary=raw
	for filename in hashes:check(FileAccess.get_sha256("res://scripts/"+filename)==hashes[filename],"frozen solver/content dependency remains byte-identical: "+filename)

static func guide(sim) -> int:
	# Same project-authored offline reference as tests/test_ground_route.gd and
	# test_pilot_ascent.gd. W/release/S only; no velocity/position/energy writes.
	var position:Vector2=sim.cargo_position();var offset=0.0
	for gate in sim.route.pilot_gates:
		if position.x<float(gate.x)+6.5:offset=float(gate.lane_offset);break
	var normal=Ascent.path_tangent(position.x,sim.route).orthogonal()*-1.0
	var body:Dictionary=sim._cargo_body();var velocity:Vector2=body.get("velocity",Vector2.ZERO)
	var lateral=velocity.dot(normal)
	var acceleration=float(sim.route.pilot_net_force_limit)/maxf(1.0,float(body.get("mass",10.2)))
	var preview=lateral*(0.45+absf(lateral)/(2.0*acceleration*0.9))
	var error=Ascent.path_y(position.x,sim.route)+offset-position.y-preview
	return int(signf(error))*1000 if absf(error)>0.9 else 0

func sim_state(sim) -> Dictionary:
	return {"status":sim.status,"elapsed":sim.elapsed,"telemetry":sim.telemetry.duplicate(true),"position":sim.cargo_position(),
		"parts":sim.parts.values().duplicate(true),"bodies":sim.bodies.duplicate(true),"obstacles":sim.obstacles.duplicate(true),
		"events":sim.events.duplicate(true),"incidents":sim.incidents.duplicate(true),"rng_state":sim._rng.state}

func _test_reference_inputs() -> void:
	var seeds:Array=[0,1,2,42,77,456,104729,2147483646]
	if "--broad" in OS.get_cmdline_user_args():
		for index in range(8,32):seeds.append((index*16411)%2147483647)
	for seed_value in seeds:
		for kind in ["ground","ascent"]:
			for slot in [0,1]:
				var outcome=make(seed_value,kind,slot,7)
				if not outcome.ok:check(false,"simulation generation failed");continue
				var route:Dictionary=outcome.offer
				var sim=Sim.new();sim.configure(Extreme.starter_design(),Extreme.starter_launcher(),route,701+slot)
				var timeline=Timeline.new();var axis=0;var ticks=0;var minimum_energy=sim.total_energy();var finite=true
				var checkpoint:Dictionary={}
				for tick in range(int(route.time_limit*60)):
					if tick%120==0 and not pause_file.is_empty():
						while FileAccess.file_exists(pause_file):OS.delay_msec(250)
					if tick%12==0:axis=guide(sim)
					var command={"axis_q":axis,"boost":false,"active":false};timeline.record(tick,command)
					sim.set_pilot_input(axis,false,false);sim.step(1.0/60.0);ticks=tick+1
					minimum_energy=minf(minimum_energy,sim.total_energy())
					finite=finite and is_finite(sim.total_energy()) and sim.cargo_position().is_finite()
					if tick==480:checkpoint=sim_state(sim)
					if sim.status!="running":break
				var label="%s seed=%d slot=%d"%[kind,seed_value,slot]
				check(sim.status=="success" and sim.elapsed<route.deadline,label+" reference input delivers before saved deadline")
				check(sim.telemetry.swept_contacts==0 and sim.ship_integrity()==1.0 and sim.incidents.is_empty(),label+" complete assembled craft avoids all actual CCD contacts")
				check(finite and sim.telemetry.energy_used>100.0 and minimum_energy>=600.0,label+" finite real battery keeps >=600J margin")
				check(sim.telemetry.control_version=="pilot-v3",label+" unchanged solver identity")
				simulations.append({"kind":kind,"world_seed":seed_value,"slot":slot,"layout":route.generation.layout_template,"task":route.generation.task_template,
					"weight":route.weight,"distance":route.distance,"status":sim.status,"elapsed":sim.elapsed,"energy_used":sim.telemetry.energy_used,
					"remaining":sim.total_energy(),"integrity":sim.ship_integrity(),"contacts":sim.telemetry.swept_contacts,"ticks":ticks})
				if seed_value in [0,42]:
					var snapshot:Dictionary=roundtrip({"design":Extreme.starter_design(),"launcher":Extreme.starter_launcher(),"route":route,"seed":701+slot,"ticks":ticks,"commands":timeline.snapshot()})
					var replay=Sim.new();replay.configure(snapshot.design,snapshot.launcher,snapshot.route,int(snapshot.seed))
					var restored=Timeline.new();check(restored.restore(snapshot.commands,int(snapshot.ticks)),label+" sparse input timeline restores")
					for tick in range(snapshot.ticks):
						if tick%120==0 and not pause_file.is_empty():
							while FileAccess.file_exists(pause_file):OS.delay_msec(250)
						var command:Dictionary=restored.state_at(tick);replay.set_pilot_input(command.axis_q,command.boost,command.active)
						replay.step(1.0/120.0);replay.step(1.0/120.0)
						if tick==480:check(same(sim_state(replay),checkpoint),label+" midflight JSON restart checkpoint equals exact saved physics state")
						if tick%300==0:make(999,"ground",1) # content calls cannot consume physics RNG
					check(same(sim_state(sim),sim_state(replay)),label+" complete JSON replay exact, including parts/contacts/RNG/costs across two120Hz steps")
				print("GUIDED ",label," ",sim.status," time=",snappedf(sim.elapsed,0.001)," energy=",snappedf(sim.telemetry.energy_used,0.001)," contacts=",sim.telemetry.swept_contacts)


func _probe_fingerprint() -> String:
	var values:Array=[]
	for seed_value in [0,1,42,2147483646]:
		for kind in ["ground","ascent"]:
			for slot in [0,1]:values.append(make(seed_value,kind,slot,7).offer)
	return JSON.stringify(values,"",true,true).sha256_text()

func _test_negative_controls() -> void:
	for condition in ["no_engines","empty_battery","wrong_steering"]:
		var route:Dictionary=make(42,"ground",0).offer
		var design:Array=Extreme.starter_design()
		if condition=="no_engines":design=design.filter(func(part):return part.type!="thruster")
		var sim=Sim.new();sim.configure(design,Extreme.starter_launcher(),route,701)
		var energy_at_start:float=sim.telemetry.energy_used
		if condition=="empty_battery":
			for part in sim.parts.values():part.energy=0.0
		var axis:int=0
		for tick in range(int(route.time_limit*60)+1):
			if tick%120==0 and not pause_file.is_empty():
				while FileAccess.file_exists(pause_file):OS.delay_msec(250)
			if tick%12==0:axis=1000 if condition=="wrong_steering" else guide(sim)
			sim.set_pilot_input(axis,false,false);sim.step(1.0/60.0)
			if sim.status!="running":break
		check(sim.status!="success","generated route cannot grant hidden success with "+condition)
		if condition=="empty_battery":check(sim.telemetry.energy_used==energy_at_start,"empty craft receives no new energy after the finite paid launcher setup")

func _test_failed_next_day() -> void:
	var economy=Econ.new();economy.enable_extreme_mode();economy.enable_seeded_offers(91);economy.ensure_contracts();economy.close_day()
	economy.offer_generation_state.version="future-v2"
	check(economy.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"future generation state can coexist durably with supported saved offers")
	var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
	var restored=Econ.new();restored.load_state()
	var previous_story:Dictionary=restored.story_state.duplicate(true)
	var result:Dictionary=restored.next_day()
	check(not result.ok and restored.day==1 and restored.phase=="night","unsupported future authoring fails next_day and retains the previous day")
	check(same(restored.contracts,before.contracts) and same(restored.story_state,previous_story) and restored.credits==before.credits,"failed next_day preserves offers, story facts and credits")
	check(restored.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{}),"failed next_day state remains saveable without dropping opaque seed state")
	var reopened=Econ.new();reopened.load_state()
	check(reopened.day==1 and reopened.phase=="night" and same(reopened.contracts,before.contracts),"restart after authoring failure cannot advance the business day or replace contracts")
	var good=Econ.new();good.enable_extreme_mode();good.enable_seeded_offers(91);good.ensure_contracts();good.close_day()
	check(good.next_day().ok and good.day==2 and good.contracts.size()==2 and good.contracts[0].generation.day==2,"supported new-day generation still creates exactly the next two offers")
