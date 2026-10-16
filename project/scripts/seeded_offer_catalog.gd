extends RefCounted
## STAGED CONTENT ONLY. No SceneTree, clock, viewport, global RNG or save writes.
## Explicit arithmetic and fixed draw order are frozen for seeded-offers-v1.
const VERSION = "seeded-offers-v1"
const Ground = preload("res://scripts/pilot_ground_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Stories = preload("res://scripts/courier_stories.gd")
const Guard = preload("res://scripts/seeded_offer_guard.gd")
const MAX_SEED = 2147483646
const Templates = preload("res://scripts/seeded_offer_templates.gd")
const LAYOUTS = Templates.LAYOUTS
const OPENINGS = Templates.OPENINGS
const LocalStream = Templates.LocalStream

static func stable_seed(text: String) -> int:
	return Templates.stable_seed(text)

static func derived_seed(world_seed: int, day: int, slot: int, kind: String, domain: String) -> int:
	return Templates.derived_seed(world_seed,day,slot,kind,domain)

static func initialize_save(raw: Dictionary, explicit_seed: Variant) -> Dictionary:
	# Returning a proposed copy does not commit it. Caller must atomically save
	# the seed WITH the first materialized offers before presenting them.
	var result = raw.duplicate(true)
	if result.has("offer_generation_state"):
		var error = Guard.seed_state_error(result.offer_generation_state)
		return {"ok":error.is_empty(), "save":result, "error":error, "changed":false}
	if not Guard.integer_in(explicit_seed, 0, MAX_SEED):
		return {"ok":false, "save":result, "error":"An explicit JSON-safe shop seed is required.", "changed":false}
	result.offer_generation_state = {"version":VERSION, "world_seed":int(explicit_seed)}
	return {"ok":true, "save":result, "error":"", "changed":true}

static func create_new_offer(base: Dictionary, seed_state: Dictionary, day: Variant, slot: Variant, kind: String, appearance_id: String) -> Dictionary:
	var error = _request_error(base, seed_state, day, slot, kind, appearance_id)
	if not error.is_empty(): return {"ok":false, "offer":{}, "error":error}
	var context = {"world_seed":int(seed_state.world_seed), "day":int(day), "slot":int(slot), "kind":kind, "appearance_id":appearance_id}
	var candidate = _build(base, context, false)
	return accept_candidate_or_fallback(candidate, base, seed_state, day, slot, kind, appearance_id)

static func _request_error(base: Dictionary, seed_state: Dictionary, day: Variant, slot: Variant, kind: String, appearance_id: String) -> String:
	var error = Guard.seed_state_error(seed_state)
	if not error.is_empty(): return error
	if seed_state.version != VERSION: return "This generation version cannot author new offers; preserve saved offers."
	if not Guard.integer_in(day, 1, 1000000) or not Guard.integer_in(slot, 0, 1): return "Invalid new-offer day or slot."
	if not kind in LAYOUTS or not appearance_id in Stories.IDS: return "Unsupported route or customer template."
	for key in ["contract_id", "status", "generation", "input_commands", "ticks", "wormhole_portal", "moon_schema"]:
		if base.has(key): return "Only an uncommitted catalog draft may be authored; saved contracts are immutable."
	if not Guard.integer_in(base.get("id"), 0, 2) or not Guard.integer_in(base.get("reward"), 100, 400) or not Guard.integer_in(base.get("rep"), 0, 4): return "Invalid catalog commercial identity."
	var commercial:Array=[[1.0,165,0],[1.5,220,2],[2.0,280,4]][int(base.id)]
	if base.get("weight")!=commercial[0] or base.reward!=commercial[1] or base.rep!=commercial[2]: return "Catalog terms are outside this frozen authored slice."
	if (kind == "ground") != (int(base.id) == 0): return "Catalog unlock and route kind disagree."
	if kind == "ascent" and base.has("route_profile"): return "Explicit special-route content cannot be relabeled as ascent."
	if kind == "ground" and base.has("route_profile") and base.route_profile != Ground.ROUTE_PROFILE: return "Foreign ground profile."
	if not Guard.safe_json(base): return "Catalog data is not bounded finite JSON."
	return ""

static func accept_candidate_or_fallback(candidate: Dictionary, base: Dictionary, seed_state: Dictionary, day: Variant, slot: Variant, kind: String, appearance_id: String) -> Dictionary:
	# Authoring-only recovery; NEVER called by restore, trial or dispatch.
	var error = _request_error(base, seed_state, day, slot, kind, appearance_id)
	if not error.is_empty(): return {"ok":false, "offer":{}, "error":error}
	error = Guard.generated_offer_error(candidate)
	if error.is_empty():
		var meta:Dictionary=candidate.generation
		if meta.world_seed!=seed_state.world_seed or meta.day!=day or meta.slot!=slot or meta.kind!=kind or meta.dialogue.appearance_id!=appearance_id or meta.base_weight!=base.weight or meta.base_reward!=base.reward:
			error="Candidate belongs to a different authoring request."
	if error.is_empty(): return {"ok":true, "offer":candidate.duplicate(true), "error":"", "fallback":false}
	var fallback = _build(base, {"world_seed":int(seed_state.world_seed), "day":int(day), "slot":int(slot), "kind":kind, "appearance_id":appearance_id}, true)
	error = Guard.generated_offer_error(fallback)
	if not error.is_empty(): return {"ok":false, "offer":{}, "error":"The authored fallback failed validation: " + error}
	return {"ok":true, "offer":fallback, "error":"", "fallback":true}

static func restore_offer(saved: Dictionary) -> Dictionary:
	# Unknown versions are opaque metadata, not an alias for v1. Existing physics
	# support is decided separately by Economy.route_validation_error().
	var error = Guard.saved_metadata_error(saved)
	return {"ok":error.is_empty(), "offer":saved.duplicate(true), "error":error}

static func _build(base: Dictionary, context: Dictionary, fallback: bool) -> Dictionary:
	var kind: String = context.kind
	var streams: Dictionary = {}
	for domain in ["layout", "task", "dialogue"]:
		streams[domain] = LocalStream.new(derived_seed(context.world_seed, context.day, context.slot, kind, domain))
	var layout: Dictionary = LAYOUTS[kind][streams.layout.take(LAYOUTS[kind].size())]
	var result: Dictionary = Ground.route(base) if kind == "ground" else Extreme.route(base)
	var heavy: bool = context.slot == 1
	var task_index: int = streams.task.take(2)
	var load_delta: float = [-0.125, 0.0, 0.125][streams.task.take(3)]
	var task_id = ("bulk" if heavy else "standard") + ("-careful" if task_index == 1 else "-steady")
	result.weight = snappedf(float(base.weight) * (1.55 if heavy else 1.0) + load_delta, 0.125)
	result.required = 90.0 if task_index == 1 else 85.0
	result.reward = int(base.reward) + (55 if heavy else 0) + (10 if task_index == 1 else 0) + int(load_delta * 40.0)
	result.deadline = (36.0 if kind == "ground" else 50.0) + (3.0 if heavy else 0.0) + (2.0 if task_index == 1 else 0.0)
	result.time_limit = 54.0 if kind == "ground" else 74.0
	result.contract_id = "D%d-%s" % [context.day, "A" if context.slot == 0 else "B"]
	result.status = "available"; result.accepted_day = context.day
	result.variant = "重货件" if heavy else "标准件"
	result.client = Stories.PROFILES[context.appearance_id].name
	result.cargo = ("加急补货 · " if heavy else "") + Stories.PROFILES[context.appearance_id].cargo
	if not fallback:
		result.distance = layout.distance + [-4.0,0.0,4.0][streams.layout.take(3)]
		result.pilot_altitude = layout.altitude
		result.destination_y = -layout.altitude
		result.pilot_climb_end = layout.climb_end
		result.pilot_gates = []; result.hazards = []
		for index in range(layout.xs.size()):
			var x: float = layout.xs[index] + [-3.0,0.0,3.0][streams.layout.take(3)]
			var offset: float = layout.offsets[index] + [-1.0,0.0,1.0][streams.layout.take(3)]
			if index == layout.xs.size()-1 and kind == "ascent": offset = 0.0
			var gap: float = (8.0 if kind == "ground" else 10.0) + 0.5 * streams.layout.take(3)
			var y: float = snappedf(Ascent.path_y(x, result)+offset, 1.0/1024.0)
			result.pilot_gates.append({"x":x,"y":y,"half_gap":gap,"index":index,"lane_offset":offset,"heading":snappedf(Ascent.path_heading(x,result),1.0/1024.0)})
			for side in [-1.0,1.0]:
				result.hazards.append({"x":x,"y":y+side*(gap+5.0),"radius":5.0,"type":"rock","health":1000000.0,"mass":1000000.0,"pilot_gate":true,"gate_index":index})
	else:
		# Frozen project-authored geometry, never unconstrained retry/reroll.
		for gate in result.pilot_gates: gate.heading = snappedf(float(gate.heading),1.0/1024.0)
	var dialogue_index: int = streams.dialogue.take(2)
	var first_line: String = OPENINGS[context.appearance_id][dialogue_index] % result.destination_name
	var dialogue = {"id":"%s-address-%d" % [context.appearance_id,dialogue_index], "appearance_id":context.appearance_id,
		"story_id":Stories.PROFILES[context.appearance_id].story_id,"cargo":Stories.PROFILES[context.appearance_id].cargo,
		"destination_name":result.destination_name,"accept_lines":[
			{"speaker":"npc","text":first_line,"expression":"neutral"},
			{"speaker":"clerk","text":"地址核对好了。我先把箱子固定稳。","expression":"warm_smile"}]}
	result.story = first_line
	var points: Array = [[0.0,0.0]]
	for gate in result.pilot_gates: points.append([gate.x,gate.y])
	points.append([result.distance,result.destination_y])
	result.generation = {"version":VERSION,"world_seed":context.world_seed,"day":context.day,"slot":context.slot,
		"kind":kind,"seed":derived_seed(context.world_seed,context.day,context.slot,kind,"offer"),
		"layout_seed":derived_seed(context.world_seed,context.day,context.slot,kind,"layout"),
		"task_seed":derived_seed(context.world_seed,context.day,context.slot,kind,"task"),
		"dialogue_seed":derived_seed(context.world_seed,context.day,context.slot,kind,"dialogue"),
		"layout_template":("authored-ground-city-v1" if kind=="ground" else "authored-ascent-v3") if fallback else layout.id,
		"task_template":task_id,"base_id":base.id,"base_rep":base.rep,"base_weight":base.weight,"base_reward":base.reward,"weight_delta":load_delta,"dialogue":dialogue,"fallback":fallback,
		"fallback_reason":"candidate_rejected" if fallback else "",
		"clearance":{"craft_radius":2.0,"margin":1.0,"preview_speed":18.0,"minimum_preview_seconds":3.5,
			"spawn_clear_until_x":30.0,"receiver_clear_from_x":result.distance-40.0,
			"exit_clear_until_x":result.distance+24.0,"witness_points":points,
			"reference":"starter-eight-modules-v3","minimum_remaining_energy":600.0}}
	return result
