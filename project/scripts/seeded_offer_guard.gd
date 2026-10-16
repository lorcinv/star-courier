extends RefCounted
## No generation during validation. Unknown generations remain opaque snapshots.
const VERSION = "seeded-offers-v1"
const Templates = preload("res://scripts/seeded_offer_templates.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
const Stories = preload("res://scripts/courier_stories.gd")

static func number_in(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func integer_in(value: Variant, low: int, high: int) -> bool:
	return number_in(value,float(low),float(high)) and float(value)==floor(float(value))

static func safe_json(value: Variant, depth: int = 0) -> bool:
	if depth > 10: return false
	if value == null or value is bool: return true
	if value is int: return value >= -9007199254740991 and value <= 9007199254740991
	if value is float: return is_finite(value) and absf(value) <= 9007199254740991.0
	if value is String: return value.length() <= 4096
	if value is Array:
		if value.size()>256: return false
		for item in value:
			if not safe_json(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size()>128: return false
		for key in value:
			if not (key is String or key is StringName) or str(key).length()>128 or not safe_json(value[key],depth+1): return false
		return true
	return false

static func seed_state_error(raw: Variant) -> String:
	if not raw is Dictionary or not safe_json(raw): return "Unsafe offer generation state; original save is preserved."
	if not raw.get("version") is String or raw.version.is_empty() or raw.version.length()>64: return "Missing offer generation version; original save is preserved."
	if not integer_in(raw.get("world_seed"),0,2147483646): return "Invalid saved shop seed; original save is preserved."
	return ""

static func saved_metadata_error(route: Dictionary) -> String:
	if not route.has("generation"): return ""
	var metadata: Variant = route.generation
	if not metadata is Dictionary or not safe_json(metadata): return "Unsafe generated-offer metadata; preserve this snapshot for recovery."
	if not metadata.get("version") is String or metadata.version.is_empty() or metadata.version.length()>64: return "Missing generated-offer version; preserve this snapshot for recovery."
	if metadata.version != VERSION: return generic_snapshot_error(route) # Opaque content; typed physics inputs still required.
	return generated_offer_error(route)

static func generic_snapshot_error(route: Dictionary) -> String:
	# Structural sanity only. No v1 templates, seed interpretation, distances,
	# gap pattern or content identity is imposed on a future generation.
	if not safe_json(route): return "Offer must contain bounded finite JSON values; preserve it for recovery."
	for key in ["id","rep"]:
		if not integer_in(route.get(key),0,1000000): return "Missing or unsafe saved contract identity: "+key
	for key in ["contract_id","status","name","client","cargo"]:
		if not route.get(key) is String or route[key].is_empty():return "Missing saved contract field: "+key
	for key in ["distance","weight","deadline","time_limit","required","reward"]:
		if not number_in(route.get(key),0.000001 if key in ["distance","weight","deadline","time_limit"] else 0.0,10000000.0):return "Unsafe saved contract/physics number: "+key
	for key in ["destination_y","delivery_radius","max_delivery_speed","boundary_y","gravity","variation","pilot_drag","pilot_cruise_speed","pilot_boost_speed","pilot_vertical_speed","pilot_net_force_limit","pilot_battery_multiplier","pilot_energy_tariff","pilot_altitude","pilot_climb_start","pilot_climb_end","lookahead_seconds","battery_capacity_multiplier"]:
		if route.has(key) and not number_in(route[key],-10000000.0,10000000.0):return "Unsafe saved physics number: "+key
	if route.has("wind") and not (number_in(route.wind,-10000000.0,10000000.0) or _json_vector(route.wind)):return "Unsafe saved wind vector."
	if not route.get("hazards") is Array:return "Missing saved collider array."
	for hazard in route.hazards:
		if not hazard is Dictionary:return "Unsafe saved collider record."
		for key in ["x","y","radius","health","mass","cooldown","range","damage","strength","fire_interval"]:
			if hazard.has(key) and not number_in(hazard[key],-10000000.0,10000000.0):return "Unsafe saved collider number."
		for key in ["position","velocity"]:
			if hazard.has(key) and not _json_vector(hazard[key]):return "Unsafe saved collider vector."
		for key in ["tracking","conductive","pilot_gate"]:
			if hazard.has(key) and not hazard[key] is bool:return "Unsafe saved collider flag."
		if hazard.has("type") and not hazard.type is String:return "Unsafe saved collider type."
		if hazard.has("radius") and float(hazard.radius)<=0.0:return "Invalid saved collider radius."
	if route.has("pilot_gates"):
		if not route.pilot_gates is Array:return "Unsafe saved gate array."
		for gate in route.pilot_gates:
			if not gate is Dictionary:return "Unsafe saved gate record."
			for key in ["x","y","half_gap"]:
				if not number_in(gate.get(key),-10000000.0,10000000.0):return "Unsafe saved gate coordinate."
			if float(gate.half_gap)<=0.0 or not integer_in(gate.get("index"),0,1000000):return "Unsafe saved gate aperture or index."
			for key in ["heading","lane_offset"]:
				if gate.has(key) and not number_in(gate[key],-10000000.0,10000000.0):return "Unsafe saved gate metadata."
	return ""

static func _json_vector(value:Variant) -> bool:
	if number_in(value,-10000000.0,10000000.0):return true
	if value is Array:return value.size()>=2 and number_in(value[0],-10000000.0,10000000.0) and number_in(value[1],-10000000.0,10000000.0)
	if value is Dictionary:return number_in(value.get("x",0.0),-10000000.0,10000000.0) and number_in(value.get("y",0.0),-10000000.0,10000000.0)
	return false

static func generated_offer_error(route: Dictionary) -> String:
	var generic_error:String=generic_snapshot_error(route)
	if not generic_error.is_empty():return generic_error
	var meta: Variant = route.get("generation")
	if not meta is Dictionary or meta.get("version") != VERSION: return "Not a known generated-offer snapshot."
	if not meta.get("kind") is String or not meta.kind in ["ground","ascent"]: return "Unknown generated route kind."
	for key in ["world_seed","seed","layout_seed","task_seed","dialogue_seed"]:
		if not integer_in(meta.get(key),0 if key=="world_seed" else 1,2147483646): return "Invalid generation seed."
	if not integer_in(meta.get("day"),1,1000000) or not integer_in(meta.get("slot"),0,1): return "Invalid generation day or slot."
	for domain in ["offer","layout","task","dialogue"]:
		var key: String = "seed" if domain=="offer" else domain+"_seed"
		if meta[key]!=Templates.derived_seed(int(meta.world_seed),int(meta.day),int(meta.slot),meta.kind,domain): return "Seed provenance disagrees with saved shop/day/slot/version."
	if not meta.get("fallback") is bool or not meta.get("fallback_reason") is String: return "Missing generation fallback provenance."
	if not meta.get("layout_template") is String or not meta.get("task_template") is String: return "Missing authored template choice."
	var layouts = ["roof-zigzag","roof-long-approach","roof-shallow"] if meta.kind=="ground" else ["orbit-zigzag","orbit-wide-turn","orbit-early-level"]
	var fallback_id = "authored-ground-city-v1" if meta.kind=="ground" else "authored-ascent-v3"
	if (meta.fallback and (meta.layout_template!=fallback_id or meta.fallback_reason!="candidate_rejected")) or (not meta.fallback and (not meta.layout_template in layouts or not meta.fallback_reason.is_empty())): return "Fallback and authored layout choices disagree."
	if not meta.task_template in ["standard-steady","standard-careful","bulk-steady","bulk-careful"] or meta.task_template.begins_with("bulk") != (int(meta.slot)==1): return "Task template and slot disagree."
	if not integer_in(meta.get("base_id"),0,2) or not integer_in(meta.get("base_rep"),0,4): return "Missing original catalog identity."
	var commercial:Array=[[1.0,165,0],[1.5,220,2],[2.0,280,4]][int(meta.base_id)]
	if route.get("id")!=meta.base_id or route.get("rep")!=meta.base_rep or meta.base_rep!=commercial[2] or meta.get("base_weight")!=commercial[0] or meta.get("base_reward")!=commercial[1] or (meta.kind=="ground")!=(int(meta.base_id)==0): return "Catalog identity, unlock and original commercial terms disagree."
	if not number_in(meta.get("base_weight"),0.75,2.0) or not integer_in(meta.get("base_reward"),100,400) or not meta.get("weight_delta") in [-0.125,0.0,0.125]: return "Invalid saved task-choice ingredients."
	var heavy: bool = int(meta.slot)==1
	var careful: bool = meta.task_template.ends_with("careful")
	if route.get("weight")!=snappedf(float(meta.base_weight)*(1.55 if heavy else 1.0)+float(meta.weight_delta),0.125) or route.get("reward")!=int(meta.base_reward)+(55 if heavy else 0)+(10 if careful else 0)+int(float(meta.weight_delta)*40.0) or route.get("required")!=(90.0 if careful else 85.0): return "Saved task choices disagree with realized commercial terms."
	if route.get("control_version")!="pilot-v3" or route.get("pilot_profile")!="pilot-v3" or route.get("mode")!="pilot": return "Generated content must retain the frozen pilot-v3 protocol."
	if meta.kind=="ground" and (route.get("route_profile")!="ground-city-v1" or route.get("route_kind")!="ground"): return "Ground presentation identity changed."
	if meta.kind=="ascent" and (route.has("route_profile") or route.has("route_kind")): return "Ascent's existing identity must remain unchanged."
	for key in ["wormhole_portal","wormhole_schema","moon_schema"]:
		if route.has(key): return "Special-biome geometry is outside this generator."
	if not route.get("contract_id") is String or route.contract_id!="D%d-%s"%[int(meta.day),"A" if int(meta.slot)==0 else "B"]: return "Offer identity and generation day/slot disagree."
	var ground: bool = meta.kind=="ground"
	var ranges = {"distance":[350.0,390.0] if ground else [510.0,550.0], "pilot_altitude":[6.0,10.0] if ground else [138.0,150.0],
		"pilot_climb_end":[165.0,175.0] if ground else [400.0,420.0], "delivery_radius":[7.0,7.0] if ground else [9.0,9.0],
		"weight":[0.625,3.25],"required":[85.0,90.0],"reward":[95.0,470.0],"deadline":[36.0,41.0] if ground else [50.0,55.0],
		"time_limit":[54.0,54.0] if ground else [74.0,74.0],"lookahead_seconds":[3.5,3.5],"boundary_y":[45.0,45.0] if ground else [230.0,230.0],
		"pilot_drag":[0.025,0.025],"pilot_climb_start":[35.0,35.0],"pilot_cruise_speed":[18.0,18.0],"pilot_boost_speed":[22.0,22.0],"pilot_vertical_speed":[5.0,5.0],
		"pilot_net_force_limit":[30.0,30.0],"pilot_battery_multiplier":[20.0,20.0],"pilot_energy_tariff":[0.025,0.025],"max_delivery_speed":[24.0,24.0],"variation":[0.0,0.0],"gravity":[0.0,0.0]}
	for key in ranges:
		if not number_in(route.get(key),ranges[key][0],ranges[key][1]): return "Out-of-envelope field: "+key
	if route.get("pilot_overdrive")!="mounted-output": return "Mounted-output control semantics changed."
	if route.has("battery_capacity_multiplier") and not number_in(route.battery_capacity_multiplier,1.0,1.45): return "Non-authored research capacity multiplier."
	if route.get("name")!=("城市货站 → 屋顶收件台" if ground else "城市升空 → 晨星轨道站") or route.get("destination_name")!=("屋顶收件台" if ground else "晨星轨道站"): return "Destination identity is outside the authored slice."
	if route.get("wind") != [0.0,0.0] or route.get("destination_y") != -route.pilot_altitude: return "Saved destination or wind changed."
	if not route.get("pilot_gates") is Array or route.pilot_gates.size() != (3 if ground else 4) or not route.get("hazards") is Array or route.hazards.size()!=route.pilot_gates.size()*2: return "Incomplete authored gate pairs."
	var clear: Variant = meta.get("clearance")
	if not clear is Dictionary: return "Missing complete-craft clearance witness."
	for key in ["craft_radius","margin","preview_speed","minimum_preview_seconds","spawn_clear_until_x","receiver_clear_from_x","exit_clear_until_x","minimum_remaining_energy"]:
		if not number_in(clear.get(key),0.0,10000.0): return "Invalid clearance witness."
	if clear.craft_radius!=2.0 or clear.margin!=1.0 or clear.preview_speed!=18.0 or clear.minimum_preview_seconds!=3.5 or clear.minimum_remaining_energy!=600.0 or clear.spawn_clear_until_x!=30.0 or clear.receiver_clear_from_x!=route.distance-40.0 or clear.exit_clear_until_x!=route.distance+24.0 or clear.get("reference")!="starter-eight-modules-v3": return "Clearance contract changed."
	var points: Variant = clear.get("witness_points")
	if not points is Array or points.size()!=route.pilot_gates.size()+2: return "Incomplete route witness."
	for point in points:
		if not point is Array or point.size()!=2 or not number_in(point[0],0.0,550.0) or not number_in(point[1],-200.0,30.0): return "Invalid route witness point."
	if points[0]!=[0.0,0.0] or points[-1]!=[route.distance,route.destination_y]: return "Witness endpoints changed."
	var layout: Dictionary = {}
	if not meta.fallback:
		for authored in Templates.LAYOUTS[meta.kind]:
			if authored.id==meta.layout_template:layout=authored
		if not route.distance-layout.distance in [-4.0,0.0,4.0] or route.pilot_altitude!=layout.altitude or route.pilot_climb_end!=layout.climb_end: return "Realized route does not match its saved authored layout choice."
	var previous_x: float = 0.0
	var previous_offset: float = 0.0
	for index in route.pilot_gates.size():
		var gate: Variant = route.pilot_gates[index]
		if not gate is Dictionary: return "Invalid gate record."
		for key in ["x","y","half_gap","lane_offset","heading"]:
			if not number_in(gate.get(key),-300.0,550.0): return "Non-finite or missing gate coordinate."
		if not integer_in(gate.get("index"),index,index): return "Gate order changed."
		if gate.half_gap<(7.5 if ground else 10.0) or gate.half_gap>(9.0 if ground else 11.0) or absf(gate.lane_offset)>9.0: return "Gate gap or lateral variation is outside its authored band."
		if not meta.fallback:
			if not gate.x-layout.xs[index] in [-3.0,0.0,3.0] or not gate.lane_offset-layout.offsets[index] in [-1.0,0.0,1.0] or not (gate.half_gap-(8.0 if ground else 10.0)) in [0.0,0.5,1.0]: return "Gate is outside its selected authored segment choices."
			if not ground and index==route.pilot_gates.size()-1 and gate.lane_offset!=0.0:return "Orbital receiver approach must be level."
		if gate.y!=snappedf(Ascent.path_y(gate.x,route)+gate.lane_offset,1.0/1024.0) or gate.heading!=snappedf(Ascent.path_heading(gate.x,route),1.0/1024.0) or points[index+1]!=[gate.x,gate.y]: return "Gate, path and witness disagree."
		var free_distance: float = gate.x-previous_x-(5.0+clear.craft_radius)*(1.0 if index==0 else 2.0)
		var available_seconds: float = free_distance/clear.preview_speed
		if available_seconds<clear.minimum_preview_seconds or available_seconds<absf(gate.lane_offset-previous_offset)/5.0+1.2: return "Insufficient preview or paid-steering transition space."
		previous_x=gate.x; previous_offset=gate.lane_offset
		for side_index in range(2):
			var hazard: Variant = route.hazards[index*2+side_index]
			if not hazard is Dictionary: return "Invalid gate collider."
			if hazard.get("x")!=gate.x or hazard.get("y")!=gate.y+(-1.0 if side_index==0 else 1.0)*(gate.half_gap+5.0) or hazard.get("radius")!=5.0 or hazard.get("type")!="rock" or hazard.get("pilot_gate")!=true or hazard.get("gate_index")!=index or hazard.get("health")!=1000000.0 or hazard.get("mass")!=1000000.0: return "Gate metadata disagrees with real circular colliders."
			for key in hazard:
				if not str(key) in ["x","y","radius","type","health","mass","pilot_gate","gate_index"]: return "Non-authored collider field."
			if hazard.has("position") or hazard.has("velocity") or hazard.has("tracking") or hazard.has("damage"): return "Hidden collider overrides are not authored."
	if route.distance-previous_x<48.0 or route.pilot_climb_end>route.distance-70.0: return "Receiver needs a level obstacle-free approach."
	var path_length: float = 0.0
	for index in range(points.size()-1):
		var start = Vector2(points[index][0],points[index][1]); var end = Vector2(points[index+1][0],points[index+1][1])
		path_length+=start.distance_to(end)
		for hazard in route.hazards:
			var distance: float = _segment_distance(Vector2(hazard.x,hazard.y),start,end)
			if distance<5.0+clear.craft_radius+clear.margin: return "No full-craft clearance tube through the authored waypoints."
	if path_length/18.0+9.0>route.deadline or route.deadline+12.0>route.time_limit: return "Insufficient nominal time or recovery allowance."
	for hazard in route.hazards:
		if hazard.x-5.0-clear.craft_radius<clear.spawn_clear_until_x: return "Spawn/departure is obstructed."
		if hazard.x+5.0+clear.craft_radius>clear.receiver_clear_from_x: return "Receiver/exit is obstructed."
	var dialogue: Variant = meta.get("dialogue")
	if not dialogue is Dictionary or not dialogue.get("appearance_id") in Stories.IDS: return "Unknown customer dialogue identity."
	var actor: Dictionary = Stories.PROFILES[dialogue.appearance_id]
	if route.get("client")!=actor.name or route.get("cargo")!=("加急补货 · " if heavy else "")+str(actor.cargo): return "Realized client and cargo disagree with their authored identity."
	if dialogue.get("story_id")!=actor.story_id or dialogue.get("cargo")!=actor.cargo or dialogue.get("destination_name")!=route.get("destination_name"): return "Customer, cargo and destination do not agree."
	if not dialogue.get("id") in [str(dialogue.appearance_id)+"-address-0",str(dialogue.appearance_id)+"-address-1"]: return "Unknown authored dialogue choice."
	if not dialogue.get("accept_lines") is Array or dialogue.accept_lines.size()!=2: return "Incomplete saved dialogue."
	for line in dialogue.accept_lines:
		if not line is Dictionary or not line.get("text") is String or line.text.is_empty() or not line.get("speaker") in ["npc","clerk"] or not line.get("expression") is String: return "Invalid saved dialogue line."
	var choice: int = int(str(dialogue.id).right(1))
	var opening: String = Templates.OPENINGS[dialogue.appearance_id][choice] % dialogue.destination_name
	if dialogue.accept_lines[0]!={"speaker":"npc","text":opening,"expression":"neutral"} or dialogue.accept_lines[1]!={"speaker":"clerk","text":"地址核对好了。我先把箱子固定稳。","expression":"warm_smile"}: return "Saved dialogue differs from its selected authored template."
	return ""

static func _segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var delta = end-start
	return point.distance_to(start+delta*clampf((point-start).dot(delta)/maxf(delta.length_squared(),0.000001),0.0,1.0))

static func clearance_for_design(route: Dictionary, design: Array) -> Dictionary:
	# Informational only. Large legal blueprints are never rejected or rewritten.
	var cargo: Vector2 = Vector2.ZERO
	var found: bool = false
	for part in design:
		if part.get("type")=="cargo": cargo=Vector2(part.get("x",0),part.get("y",0)); found=true; break
	if not found: return {"known":false,"reason":"No cargo reference."}
	var radius: float = 0.0
	for part in design: radius=maxf(radius,Vector2(part.get("x",0),part.get("y",0)).distance_to(cargo)+0.43)
	var minimum_gap: float = INF
	for gate in route.get("pilot_gates",[]): minimum_gap=minf(minimum_gap,float(gate.half_gap))
	return {"known":is_finite(minimum_gap),"rotation_independent_radius":radius,"minimum_half_gap":minimum_gap,
		"reference_envelope":radius<=2.0,"gate_margin":minimum_gap-radius,
		"note":"Starter-only route evidence; size alone does not establish thrust, energy or human controllability."}
