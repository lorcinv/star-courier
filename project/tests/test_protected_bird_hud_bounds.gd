extends SceneTree
## Real Control transforms and PixelStage density; no simulated HUD coordinates.
const World = preload("res://scripts/world_view_2d.gd")
const Stage = preload("res://scripts/pixel_stage.gd")
const Parts = preload("res://scripts/parts.gd")
var checks = 0
var failures = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func panel(parent: Control, name_value: String, rect: Rect2) -> PanelContainer:
	var result = PanelContainer.new(); result.name = name_value
	var style = StyleBoxFlat.new(); style.bg_color = Color("17243a")
	result.add_theme_stylebox_override("panel",style)
	result.position = rect.position; result.size = rect.size; parent.add_child(result)
	return result
func run() -> void:
	var stage = Stage.new(); root.add_child(stage); stage.size = Vector2(1280,800); stage.set_density_mode("auto")
	var world = World.new(); world.catalog = Parts.catalog(); world.catalog.cargo = Parts.cargo_spec()
	world.screen_mapper = stage; stage.viewport.add_child(world); world.set_process(false)
	var canvas = CanvasLayer.new(); root.add_child(canvas)
	var hud_root = Control.new(); canvas.add_child(hud_root)
	world.protected_bird_hud_root = hud_root
	var content = Control.new(); content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud_root.add_child(content)
	var cue = panel(content,"AscentCue",Rect2(20,108,260,78))
	var resource = panel(content,"FlightResources",Rect2(20,198,260,112))
	var receipt = panel(content,"FlightEventReceipt",Rect2(20,586,444,42))
	var transparent = panel(content,"TransparentRoot",Rect2(0,0,1280,720))
	var empty = StyleBoxFlat.new(); empty.bg_color = Color(0,0,0,0); empty.set_border_width_all(0)
	transparent.add_theme_stylebox_override("panel",empty)
	var dimmer = ColorRect.new(); dimmer.color = Color(0,0,0,0); dimmer.size = Vector2(1280,720); content.add_child(dimmer)
	var hidden = panel(content,"HiddenPanel",Rect2(0,0,1280,720)); hidden.hide()
	var modal = panel(content,"PauseModal",Rect2(400,200,480,320)); modal.hide()
	for native in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
		stage.size = Vector2(native); stage.set_density_mode("auto"); stage._resize_canvas()
		var ui_scale = clampi(floori(stage.display_rect.size.y / 720.0),1,3)
		hud_root.position = stage.display_rect.position; hud_root.scale = Vector2.ONE * ui_scale
		hud_root.size = stage.display_rect.size / ui_scale
		receipt.position.y = hud_root.size.y - 134
		world.smooth_zoom = 0.27; world.smooth_center = Vector2(81000,-10000); world._update_camera()
		await process_frame
		var regions: Array = world._protected_bird_hud_rects()
		check(regions.size() == 3, "only three actual visible blocking HUD panels at " + str(native))
		for widget in [cue,resource,receipt]:
			var expected: Vector2 = widget.get_global_transform_with_canvas() * Vector2.ZERO
			var expected_end: Vector2 = widget.get_global_transform_with_canvas() * widget.size
			var matched = false
			for rect in regions:
				var got: Vector2 = world._screen_point(rect.position)
				var got_end: Vector2 = world._screen_point(rect.end)
				if got.distance_to(expected) < 0.1 and got_end.distance_to(expected_end) < 0.1: matched = true
			check(matched, "native " + str(widget.name) + " bounds survive canvas density/resize mapping at " + str(native))
		modal.show()
		check(world._protected_bird_hud_rects().size() == 4, "pause modal adds its actual blocking panel")
		modal.hide()
		check(world._protected_bird_hud_rects().size() == 3, "dismissed modal is no longer counted")
		transparent.modulate.a = 0.0
		check(world._protected_bird_hud_rects().size() == 3, "transparent full-screen containers and dimmers never hide the encounter")
		transparent.modulate.a = 1.0
	world.protected_bird_hud_root = null
	check(world._protected_bird_hud_rects().is_empty(), "unbound isolated fixture reports no actual native occluders")
	stage.queue_free(); canvas.queue_free(); await process_frame
	print("PROTECTED_BIRD_HUD_BOUNDS checks=%d failures=%d" % [checks,failures]); quit(1 if failures else 0)
