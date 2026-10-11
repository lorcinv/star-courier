extends SceneTree
## Isolated snapshot fixtures, not collision, controller or human-play evidence.
const Presentation = preload("res://scripts/protected_bird_presentation_2d.gd")
const Profile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Otherworld = preload("res://scripts/otherworld_presentation_2d.gd")
const Cues = preload("res://scripts/flight_cues_2d.gd")
var passed = 0
var failed = 0
class SnapshotSim extends RefCounted:
	var route: Dictionary
	var wildlife: Dictionary
	var wildlife_error: String = ""
	var pilot_tick: int = 0
	var status: String = "running"
	var paused: bool = false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS ", label)
	else: failed += 1; push_error("FAIL " + label)
func fixture() -> SnapshotSim:
	var sim = SnapshotSim.new(); sim.route = Profile.route({}, "PRESENTATION-TEST", 42)
	var event: Dictionary = sim.route.ecology
	sim.wildlife = {"event_id":event.event_id, "entity_id":event.entity_id, "species_id":event.species_id,
		"position":Vector2(1120,-153), "velocity":Vector2(-3,0.5), "mass":0.125, "radius":0.375, "hp":8.0,
		"state":"waiting", "active":false, "activated":false, "activation_tick":-1,
		"activation_fraction":0.5, "hurt_ticks":0, "fall_ticks":0, "damage_transitions":0}
	return sim
func activate(sim, tick: int = 10) -> void:
	sim.pilot_tick = tick; sim.wildlife.activation_tick = tick; sim.wildlife.active = true
	sim.wildlife.activated = true; sim.wildlife.state = "healthy"
func view_of(at: Vector2, zoom: float = 0.3) -> Rect2:
	var span = Vector2(1200,500) / zoom
	return Rect2(at * 72.0 - span * 0.5, span)
func no_colliders(node: Node) -> bool:
	if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D: return false
	for child in node.get_children():
		if not no_colliders(child): return false
	return true
func material_pose(s: Dictionary) -> Array:
	return [s.tick,s.pose,s.position_m,s.velocity_mps,s.hp,s.state,s.new_hp_notices,s.notice_until_tick,s.sprite_alpha]

func run() -> void:
	var layer = Presentation.new(); root.add_child(layer)
	check(layer.get_child_count() == 4, "one sprite and exactly three cached native labels")
	check(not layer.is_processing() and not layer.is_physics_processing(), "no autonomous visual clock")
	check(no_colliders(layer), "no synthetic collision geometry")
	for bad in [null, false, 5, "bird", [], {}, {"control_version":"pilot-v4-wormhole"}, {"control_version":[]}, {"control_version":{}}]:
		check(not Presentation.accepts_route(bad), "non-v5 or malformed route is disabled")
	var sim = fixture(); var route_before = sim.route.duplicate(true); var bird_before = sim.wildlife.duplicate(true)
	check(layer.configure(sim, Vector2.ZERO, 72.0), "valid saved v5 route configures")
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(not layer.visible and not layer.debug_snapshot().creature_visible, "waiting bird is not painted early")
	check(sim.route == route_before and sim.wildlife == bird_before, "configuration and render leave authority byte-value unchanged")
	activate(sim)
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	var live = layer.debug_snapshot()
	check(live.creature_fully_visible and live.marker_visible and not live.edge_notice_visible, "actual generated creature and protection label are visible together")
	check(live.marker_text == "保护鸟 · 请绕行", "default label conveys protection without debug or combat copy")
	check(live.physical_radius_m == 0.375 and live.torso_anchor_native == Vector2(32,32), "original anchor and physical radius are unchanged")
	check(layer.get_child(0).position == sim.wildlife.position * 72.0 and layer.get_child(0).scale == Vector2.ONE * 2.25, "art registers precisely at real body center and shared source scale")
	check(live.cached_alpha_poses == 3, "three source-alpha maps are cached once")
	var transparent_at: Vector2 = layer.get_child(0).transform * (Vector2(32.5,20.5) - Vector2(32,32))
	layer.update_from_sim(sim, Rect2(transparent_at - Vector2.ONE * 0.01,Vector2.ONE * 0.02), 0.3)
	check(not layer.debug_snapshot().creature_visible, "transparent occupied-bounds corner cannot count as visible bird")
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	var covered: Rect2 = live.creature_bounds_world_px.grow(12.0)
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3, false, [covered])
	check(not layer.debug_snapshot().creature_visible and not layer.debug_snapshot().marker_visible, "real visible HUD panel covering body prevents creature visibility credit")
	var panel_pose = material_pose(layer.debug_snapshot())
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3, true, [covered])
	check(not layer.debug_snapshot().creature_visible and material_pose(layer.debug_snapshot()) == panel_pose, "pause/modal occlusion updates without material animation")
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3, true, [])
	check(layer.debug_snapshot().creature_fully_visible and material_pose(layer.debug_snapshot()) == panel_pose, "dismissed modal restores visibility without new harm feedback")
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	var same_ids = []
	for node in layer.get_children(): same_ids.append(node.get_instance_id())
	for i in 2000: layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.debug_snapshot() == live, "two thousand repeated snapshots are idempotent")
	var same = layer.get_child_count() == 4
	for i in 4: same = same and same_ids[i] == layer.get_child(i).get_instance_id() and layer.get_child(i).material == null
	check(same, "repeated snapshots retain the same four nodes and zero materials")
	sim.pilot_tick += 14; layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.debug_snapshot().pose == "wings-up", "wing pose advances from 120 Hz simulation ticks")
	layer.reduced_motion = true; layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.debug_snapshot().pose == "wings-down" and layer.debug_snapshot().position_m == sim.wildlife.position, "reduced motion stops flap without replacing physical movement")
	layer.reduced_motion = false
	sim.pilot_tick += 1; sim.wildlife.position += Vector2(-0.4,0.1); sim.wildlife.velocity = Vector2(3,-0.5)
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.get_child(0).flip_h and layer.get_child(0).position == sim.wildlife.position * 72.0, "real position and velocity own registration and facing")
	check(layer.debug_snapshot().new_hp_notices == 0, "proximity and movement produce no injury notice")
	layer.update_from_sim(sim, view_of(Vector2(1020,-150)), 0.3)
	check(layer.debug_snapshot().edge_notice_visible and not layer.debug_snapshot().creature_visible, "edge warning explicitly does not count as visible creature")
	sim.pilot_tick += 1; sim.wildlife.hp = 6.0; sim.wildlife.damage_transitions = 1; sim.wildlife.state = "hurt"; sim.wildlife.hurt_ticks = 36
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.debug_snapshot().pose == "hurt" and layer.debug_snapshot().new_hp_notices == 1, "actual new HP decrement selects hurt pose and one notice")
	check(layer.debug_snapshot().marker_text == "保护鸟受伤了", "injury copy makes no death, intent, penalty or source claim")
	var hurt = layer.debug_snapshot()
	for i in 40: layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.debug_snapshot() == hurt, "repeated hurt snapshot never replays notice")
	sim.paused = true; layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	var paused = layer.debug_snapshot()
	sim.pilot_tick += 20; sim.wildlife.position += Vector2(40,40)
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(material_pose(layer.debug_snapshot()) == material_pose(paused), "pause freezes pose, position, opacity and tick even if caller offers newer data")
	sim.paused = false; layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3, true)
	check(material_pose(layer.debug_snapshot()) == material_pose(paused), "focus/visual pause uses the same frozen material boundary")
	check(layer.configure(sim, Vector2.ZERO, 72.0, true), "restore re-baselines current true state")
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3, true)
	check(layer.debug_snapshot().pose == "hurt" and layer.debug_snapshot().new_hp_notices == 0 and layer.debug_snapshot().notice_until_tick == -1, "resume preserves injury without replaying historical feedback")
	sim.pilot_tick += 36; sim.wildlife.state = "injured"; sim.wildlife.hurt_ticks = 0
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(layer.debug_snapshot().pose == "hurt" and layer.debug_snapshot().hp == 6.0, "nonlethal injury remains visibly injured")
	var before_regression = layer.debug_snapshot(); sim.pilot_tick -= 1
	layer.update_from_sim(sim, view_of(Vector2.ZERO), 0.3)
	check(layer.debug_snapshot() == before_regression, "regressed ticks require explicit reconstruction instead of replay")
	sim.pilot_tick += 2; sim.wildlife.hp = 0.0; sim.wildlife.damage_transitions += 1; sim.wildlife.state = "falling"; sim.wildlife.active = false; sim.wildlife.fall_ticks = 0
	var death_at: Vector2 = sim.wildlife.position
	layer.update_from_sim(sim, view_of(death_at), 0.3)
	check(layer.debug_snapshot().new_hp_notices == 1 and layer.debug_snapshot().sprite_alpha == 1.0, "new real terminal decrement reports once after resume")
	sim.pilot_tick += 24; sim.wildlife.fall_ticks = 24
	layer.update_from_sim(sim, view_of(death_at), 0.3)
	check(layer.debug_snapshot().position_m == death_at and layer.debug_snapshot().sprite_alpha == 0.5, "finite fade follows fall ticks without inventing a trajectory")
	sim.pilot_tick += 24; sim.wildlife.fall_ticks = 48; sim.wildlife.state = "gone"
	layer.update_from_sim(sim, view_of(death_at), 0.3)
	check(not layer.visible and not layer.debug_snapshot().creature_visible and not layer.cue_state().active, "gone entity releases every visible cue")
	layer.leave_flight(); layer.leave_flight()
	check(not layer.visible and layer.get_child_count() == 4 and layer.debug_snapshot().new_hp_notices == 0, "idempotent leave clears state without resource growth")
	sim = fixture(); activate(sim); sim.status = "success"
	check(layer.configure(sim, Vector2.ZERO, 72.0), "settled snapshot requires no cargo body")
	layer.update_from_sim(sim, view_of(sim.wildlife.position), 0.3)
	check(not layer.cue_state().active and not layer.debug_snapshot().edge_notice_visible, "terminal empty-body settlement cannot retain steering advice")
	for malformed in ["foreign", "foreign_type", "radius", "nan", "hp", "count", "route", "error"]:
		sim = fixture(); activate(sim); check(layer.configure(sim, Vector2.ZERO, 72.0), "new valid retry before malformed sample")
		match malformed:
			"foreign": sim.wildlife.entity_id = "another-bird"
			"foreign_type": sim.wildlife.entity_id = []
			"radius": sim.wildlife.radius = 2.0
			"nan": sim.wildlife.position = Vector2(NAN,0)
			"hp": sim.wildlife.hp = "six"
			"count": sim.wildlife.damage_transitions = 0.5
			"route": sim.route.hazards[0].radius = 9.0
			"error": sim.wildlife_error = "fixture error"
		layer.update_from_sim(sim, view_of(Vector2(1120,-153)), 0.3)
		check(not layer.debug_snapshot().enabled and not layer.visible, "malformed snapshot fails closed: " + malformed)
	var cues = Cues.new(); root.add_child(cues)
	cues.set_protected_bird_cue({"active":true,"points":[Vector2(1,1),Vector2(2,2),Vector2(3,3)],"zoom":0.3})
	check(cues.protected_bird_path.size() == 3, "only three bounded functional lower-path chevrons")
	cues.set_protected_bird_cue({"active":true,"points":[Vector2.ZERO,5,Vector2.ONE],"zoom":0.3})
	check(cues.protected_bird_path.is_empty(), "malformed path cue clears instead of retaining old direction")
	await test_otherworld()
	layer.queue_free(); cues.queue_free(); await process_frame
	print("PROTECTED_BIRD_PRESENTATION passed=%d failed=%d" % [passed,failed]); quit(1 if failed else 0)

func test_otherworld() -> void:
	var stage = Node2D.new(); root.add_child(stage)
	var layer = Otherworld.new(); root.add_child(layer)
	var v4: Dictionary = {"control_version":"pilot-v4-wormhole", "route_profile":"wormhole-otherworld-v1", "wormhole_schema":1,
		"distance":1240.0, "destination_y":-150.0, "delivery_radius":9.0,
		"wormhole_portal":{"entry":[600.0,-150.0],"exit":[1000.0,-150.0],"aperture_radius":13.0}}
	check(layer.configure_route(v4,stage,Vector2.ZERO,72.0), "original v4 route presentation still accepted")
	check(layer.sync_telemetry({"wormhole_phase":"otherworld"}) and layer.otherworld_active(), "v4 historical missing-version telemetry behavior preserved")
	layer.leave_flight()
	var v5: Dictionary = Profile.route({}, "OTHERWORLD-V5", 42); var untouched = v5.duplicate(true)
	check(layer.configure_route(v5,stage,Vector2.ZERO,72.0), "strict valid v5 presentation explicitly accepted")
	check(not layer.sync_telemetry({"wormhole_phase":"otherworld"}), "v5 telemetry cannot borrow v4 missing-version fallback")
	check(not layer.sync_telemetry({"control_version":"pilot-v4-wormhole","wormhole_phase":"otherworld"}), "foreign v4 telemetry cannot activate v5 biome")
	check(layer.sync_telemetry({"control_version":"pilot-v5-protected-bird","wormhole_phase":"otherworld"}), "true v5 authoritative cargo phase activates Mosslight")
	check(v5 == untouched and str(v5.control_version) == "pilot-v5-protected-bird", "presentation never relabels authoritative v5 route as v4")
	var bad = v5.duplicate(true); bad.ecology.radius = 1.0
	check(not layer.configure_route(bad,stage,Vector2.ZERO,72.0) and not layer.route_enabled(), "malformed v5 disables registered props")
	bad = v5.duplicate(true); bad.route_profile = "wormhole-otherworld-v1"
	check(not Otherworld.accepts_route(bad), "mixed v5/v4 identity is rejected")
	layer.queue_free(); stage.queue_free(); await process_frame
