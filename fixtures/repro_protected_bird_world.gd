extends SceneTree
## Deterministic from-rest scripted guidance + actual WorldView2D adapter.
## Optional renderer captures are fixtures, not OS-input or human-play evidence.
const World = preload("res://scripts/world_view_2d.gd")
const Parts = preload("res://scripts/parts.gd")
const Sim = preload("res://scripts/pilot_protected_bird_simulation.gd")
const Profile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Extreme = preload("res://scripts/pilot_extreme_profile.gd")
const PixelStage = preload("res://scripts/pixel_stage.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
var checks = 0
var failures: Array = []
var capture = false
var out = "res://reports/world-repro"
var viewport: SubViewport
var world
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out = arg.trim_prefix("--output=")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func material_pose(s: Dictionary) -> Array:
	return [s.tick,s.pose,s.position_m,s.velocity_mps,s.hp,s.state,s.new_hp_notices,s.notice_until_tick,s.sprite_alpha]

func guidance(sim, harm: bool) -> int:
	var pos: Vector2 = sim.cargo_position()
	var offset = 0.0
	for gate in sim.route.pilot_gates:
		if pos.x < float(gate.x) + 6.5: offset = float(gate.lane_offset); break
	if pos.x > 980.0 and pos.x < 1120.0: offset = 0.0 if harm else 7.0
	var normal = Ascent.path_tangent(pos.x, sim.route).orthogonal() * -1.0
	# At collection all cargo can leave the bodies array. Never index it then.
	var body: Dictionary = sim._cargo_body()
	if body.is_empty(): return 0
	var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
	var lateral = velocity.dot(normal)
	var acceleration = float(sim.route.pilot_net_force_limit) / maxf(1.0, float(body.get("mass",10.2)))
	var preview = lateral * (0.45 + absf(lateral) / (2.0 * acceleration * 0.9))
	var error = Ascent.path_y(pos.x, sim.route) + offset - pos.y - preview
	return int(signf(error)) * 1000 if absf(error) > 0.9 else 0
func projections(state: Dictionary, zoom: float) -> Array:
	var result = []
	for native in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
		var grid: Vector2i = PixelStage.choose_canvas(native,"auto")
		var scale = maxi(1,mini(native.x / grid.x,native.y / grid.y))
		var render_factor = zoom * float(grid.x) / 1280.0
		var display_factor = render_factor * scale
		var actual_bounds: Rect2 = state.creature_bounds_world_px
		result.append({"native_window":native,"render_grid":grid,"integer_display_scale":scale,"camera_zoom":zoom,
			"physical_core_display_px":54.0 * display_factor,"physical_core_render_texels":54.0 * render_factor,
			"source_torso_length_display_px":23.27199602132503 * 2.25 * display_factor,
			"rotated_occupied_silhouette_display_px":actual_bounds.size * display_factor,
			"rotated_occupied_silhouette_render_texels":actual_bounds.size * render_factor,
			"pose":state.pose,"method":"source geometry projected through current measured camera zoom and exact auto-density rule; native capture still required"})
	return result

func save_json(name: String, value: Variant) -> void:
	var file = FileAccess.open(out + "/" + name + ".json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "  ", true, true))
func shot(name: String) -> void:
	if not capture: return
	await process_frame; await RenderingServer.frame_post_draw
	var result = viewport.get_texture().get_image().save_png(out + "/" + name + ".png")
	check(result == OK, "capture written: " + name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	viewport = SubViewport.new(); viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	world = World.new(); world.catalog = Parts.catalog(); world.catalog.cargo = Parts.cargo_spec()
	viewport.add_child(world); world.set_process(false)
	var runs = []
	for harm in [false,true]: runs.append(await route_witness(harm))
	check(world.flight_nodes.is_empty(), "leave releases bird/cues and all flight references")
	save_json("summary", {"checks":checks, "failures":failures, "runs":runs,
		"method":"from-rest deterministic scripted physics; WorldView2D render fixture",
		"native_os_input":"not tested", "human_fairness":"not established", "fps":"not measured",
		"raster_visibility_metric":"cached opaque-texel centers for partial entry, full raster AABB for complete visibility; not an occlusion/native-pixel-proof verdict",
		"capture_enabled":capture, "hud":"full production HUD not instantiated in this isolated fixture"})
	viewport.queue_free(); await process_frame
	print("PROTECTED_BIRD_WORLD checks=%d failures=%d" % [checks,failures.size()]); quit(1 if not failures.is_empty() else 0)
func route_witness(harm: bool) -> Dictionary:
	var label = "harm" if harm else "safe"
	var route = Profile.route({"weight":1.0}, "PRESENTATION-" + label, 42)
	var route_before = route.duplicate(true)
	var sim = Sim.new(); sim.configure(Extreme.starter_design(), Extreme.starter_launcher(), route, 42)
	world.route_distance = float(route.distance); world.route_radius = float(route.delivery_radius)
	world.start_flight(sim); world.launch_age = 1.35; world.launch_transfer_progress = 1.0
	check(world.flight_nodes.has("protected_bird"), "World registers exactly one v5 bird adapter")
	check(world.otherworld_presentation.route_enabled(), "real v5 route retains registered Mosslight hardware")
	var bird = world.flight_nodes.protected_bird
	var first_pixel = -1.0; var first_full = -1.0; var first_protected = -1.0; var first_edge = -1.0; var first_harm = -1.0
	var full_pose = {}; var harm_pose = {}; var axis = 0; var tested_pause = false
	var full_projection = []; var minimum_clearance = INF
	var frames = []
	for tick in range(6000):
		if tick % 12 == 0: axis = guidance(sim,harm)
		sim.set_pilot_input(axis,false,false); sim.step(1.0/60.0)
		var authority_before = sim.wildlife.duplicate(true)
		var facts_before = sim.wildlife_result().duplicate(true)
		world.show_flight(sim); world._process(1.0/60.0)
		var state: Dictionary = bird.debug_snapshot()
		if sim.wildlife.active:
			for part in sim.parts.values():
				if part.alive and not part.delivered:
					minimum_clearance = minf(minimum_clearance,sim.part_world_position(part.id).distance_to(sim.wildlife.position) - 0.43 * part.scale - float(sim.wildlife.radius))
		if sim.wildlife != authority_before or sim.wildlife_result() != facts_before:
			check(false, "presentation mutated wildlife/evidence"); break
		if state.edge_notice_visible and first_edge < 0.0:
			first_edge = sim.elapsed; await shot(label + "-edge-only")
		if state.creature_visible and first_pixel < 0.0: first_pixel = sim.elapsed
		if state.creature_fully_visible and first_full < 0.0:
			first_full = sim.elapsed; full_pose = state.duplicate(true); full_projection = projections(state,world.smooth_zoom)
			await shot(label + "-first-full-creature")
		if state.full_body_with_marker and first_protected < 0.0: first_protected = sim.elapsed
		if not sim.first_harm.is_empty() and first_harm < 0.0:
			first_harm = sim.elapsed; harm_pose = state.duplicate(true)
			await shot(label + "-real-contact")
		if state.creature_fully_visible and not tested_pause and not harm:
			tested_pause = true
			world.show_flight(sim,true); var frozen: Dictionary = bird.debug_snapshot()
			for i in 12: world._process(1.0/60.0)
			check(material_pose(bird.debug_snapshot()) == material_pose(frozen), "World visual pause freezes the existing bird shot")
			world.set_focus_active(false)
			for i in 12: world._process(1.0/60.0)
			check(material_pose(bird.debug_snapshot()) == material_pose(frozen), "World focus loss cannot animate bird")
			world.set_focus_active(true); world.show_flight(sim)
		if sim.wildlife.activated and tick % 12 == 0:
			frames.append({"time":sim.elapsed,"tick":sim.pilot_tick,"cargo":sim.cargo_position(),"bird":state,
				"camera":world.camera.position,"zoom":world.smooth_zoom,"otherworld":world.otherworld_presentation.otherworld_active()})
		if sim.status != "running": break
	check(sim.status == "success" and sim.ship_integrity() == 1.0, "from-rest " + label + " witness delivers intact")
	check(sim.wildlife_result().harms.size() == (1 if harm else 0), "presentation leaves canonical harm count unchanged")
	check(route == route_before, "saved route and IDs remain read-only")
	check(first_full > 0.0, "actual creature reaches the safe view rectangle")
	check(first_edge > 0.0 and first_edge < first_full, "advance edge cue is measured separately")
	if harm: check(first_full < first_harm and first_protected < first_harm and float(full_pose.hp) == 8.0, "actual healthy sprite is fully in view before real harm")
	check(bird.get_child_count() == 4 and bird.debug_snapshot().materials == 0, "whole route retains four cached nodes and no materials")
	check(sim._cargo_body().is_empty(), "fixture exercises genuinely empty settled cargo body")
	world.show_flight(sim,true); await shot(label + "-receipt")
	world.settle_resumed_flight(sim)
	check(bird.debug_snapshot().new_hp_notices == 0, "settled restore does not replay historical injury notices")
	var actual_contact_time = (float(sim.first_harm.physics_tick) - 1.0 + float(sim.first_harm.substep_fraction)) / 120.0 if harm and not sim.first_harm.is_empty() else -1.0
	var result = {"route":label,"status":sim.status,"elapsed":sim.elapsed,"intact":sim.ship_integrity(),
		"first_edge_notice":first_edge,"first_opaque_texel_center":first_pixel,"first_full_raster_bounds":first_full,
		"first_full_body_with_protection_marker":first_protected,"first_full_projection":full_projection,
		"actual_contact_time_from_tick_fraction":actual_contact_time,"full_protected_body_lead_seconds":actual_contact_time - first_protected if actual_contact_time >= 0.0 else null,
		"edge_lead_seconds_separate":actual_contact_time - first_edge if actual_contact_time >= 0.0 else null,
		"minimum_sampled_full_craft_clearance_m":minimum_clearance if is_finite(minimum_clearance) else null,
		"remaining_energy_j":sim.total_energy(),"first_harm_sample":first_harm,"first_full_pose":full_pose,"harm_pose":harm_pose,
		"facts":sim.wildlife_result(),"frames":frames}
	save_json(label,result)
	world.leave_flight(); world.leave_flight()
	return result
