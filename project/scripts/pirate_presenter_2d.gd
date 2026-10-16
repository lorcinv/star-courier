extends Node2D
## Small adapter for an existing world parent; no camera, simulation or clock.
const Model = preload("res://scripts/pirate_view_model_v1.gd")
const INK := Color("081725")
const CYAN := Color("74f4ff")
const DIM_CYAN := Color("56a9b4")
const WHITE := Color("efffff")
var _textures: Dictionary = {}
var _frame: Dictionary = {}
var _body: Sprite2D

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false); set_physics_process(false)
	_body = Sprite2D.new(); _body.name = "AcceptedRasterSolidHull"
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)
	_body.hide()
	# Parent's draw happens before child body; overlays need their own front child.
	var overlay := Overlay.new(); overlay.name = "FunctionalFrozenLockCues"
	overlay.presenter = self; add_child(overlay)

func configure_textures(textures: Dictionary) -> Dictionary:
	for key in ["charges-2", "charges-1", "charges-0", "disabled"]:
		if not textures.get(key) is Texture2D or textures[key].get_size() != Vector2(192, 192):
			clear_frame(); _textures.clear(); return {"ok": false, "error": "missing_or_misregistered_texture"}
	_textures = textures.duplicate()
	return {"ok": true}

func present(actor_view: Variant, clock: Variant, world_to_view: Transform2D, logical_pixel: float, ray_records: Variant = [], actor_id: String = "", reduced_motion: bool = false) -> Dictionary:
	var next: Dictionary = Model.compose(actor_view, clock, world_to_view, logical_pixel, ray_records, actor_id, reduced_motion)
	if not next.ok or _textures.is_empty():
		clear_frame()
		return next if not next.ok else {"ok": false, "error": "textures_not_configured"}
	_frame = next
	_body.texture = _textures[_frame.body_state]
	_body.transform = _frame.body_transform
	_body.show()
	get_child(1).queue_redraw()
	return {"ok": true, "rejected_cues": _frame.rejected_cues.duplicate()}

func clear_frame() -> void:
	_frame = {}; _body.hide()
	get_child(1).queue_redraw()

func inspect_frame() -> Dictionary:
	# A detached diagnostic copy, never the mutable stored frame.
	return _frame.duplicate(true)

class Overlay extends Node2D:
	var presenter: Node2D
	func _draw() -> void:
		var f: Dictionary = presenter._frame
		if f.is_empty(): return
		var pixel: float = f.logical_pixel
		var w: Dictionary = f.warning
		if not w.is_empty():
			# Only this dashed segment denotes the locked warning trajectory.
			_dashed(w.origin, w.target, DIM_CYAN, pixel)
			# Short, subordinate association is distinct from the physical ray.
			if w.live_muzzle.distance_to(w.origin) > 2.0 * pixel:
				_line(w.live_muzzle, w.link_end, DIM_CYAN, 1.0 * pixel, pixel)
				_box(w.live_muzzle, 2.5 * pixel, DIM_CYAN, pixel)
			_reticle(w.origin, w.target - w.origin, CYAN, pixel)
			# A monotonic charge bar, never a wall-clock blink or a hit claim.
			var start: Vector2 = w.origin + Vector2(-8, 15) * pixel
			_line(start, start + Vector2(16, 0) * pixel, INK, 4.0 * pixel, pixel)
			if w.progress > 0.0: _line(start, start + Vector2(16.0 * w.progress, 0) * pixel, CYAN, 2.0 * pixel, pixel)
		for ray in f.rays:
			var color := CYAN; color.a = ray.alpha
			if ray.pulse:
				_line(ray.origin, ray.end, color, 2.0 * pixel, pixel)
				_reticle(ray.origin, ray.end - ray.origin, color, pixel)
			if ray.impact:
				# Exact event witness, fixed-size functional ticks. No explosion art.
				for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
					_line(ray.end + d * 4.0 * pixel, ray.end + d * 8.0 * pixel, color, 2.0 * pixel, pixel)
	func _line(a: Vector2, b: Vector2, color: Color, width: float, pixel: float) -> void:
		var ink := INK; ink.a = color.a
		draw_line(a, b, ink, width + 3.0 * pixel, false)
		draw_line(a, b, color, width, false)
	func _box(at: Vector2, radius: float, color: Color, pixel: float) -> void:
		var rect := Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		draw_rect(rect, INK, false, 4.0 * pixel, false)
		draw_rect(rect, color, false, 1.5 * pixel, false)
	func _reticle(at: Vector2, direction: Vector2, color: Color, pixel: float) -> void:
		# Cyan diamond + cardinal ticks reads as a fixed lock even over hull pixels.
		var points := [Vector2(-8, 0), Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0)]
		for i in range(4): _line(at + points[i] * pixel, at + points[i + 1] * pixel, color, 2.0 * pixel, pixel)
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_line(at + d * 11.0 * pixel, at + d * 15.0 * pixel, color, 2.0 * pixel, pixel)
		if direction.length_squared() > 0.0001:
			var dir := direction.normalized()
			_line(at + dir * 18.0 * pixel, at + dir * 25.0 * pixel, color, 2.0 * pixel, pixel)
	func _dashed(a: Vector2, b: Vector2, color: Color, pixel: float) -> void:
		var delta := b - a
		var length := delta.length()
		if length < 0.001: return
		var direction := delta / length
		# Bounded dash count; long off-screen rays cannot create unbounded draws.
		var step: float = maxf(14.0 * pixel, length / 256.0)
		for i in range(mini(256, int(ceil(length / step)))):
			var start: float = float(i) * step
			_line(a + direction * start, a + direction * minf(start + step * 0.5, length), color, 1.0 * pixel, pixel)
