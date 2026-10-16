extends Node2D
## Read-only boundary between World and the independently owned solver API.
## No route authoring, physics, settlement, random sampling or animation clock.
const Presenter = preload("res://scripts/pirate_presenter_2d.gd")
const CONTROL_VERSION: String = "pilot-pirate-drill-v1"
const CONTROL_VERSIONS: Array = [CONTROL_VERSION, "pilot-pirate-drill-v2"]
const ART_ROOT: String = "res://assets/2d_v5/events/pirate/"
const TEXTURE_PINS: Dictionary = {
	"charges-2": "f588f29daff26df82800e920794f1369a309ca93dcb191471b3596f7ee603fa5",
	"charges-1": "a45c4e5c34e3414a24dd831ff373575bcec8d09c6ddbdc326a90915c31a2f7cc",
	"charges-0": "68d776e37d9b8cb4b17391ca1b71950550bdd9fb7028ad84fd7b59ee09521143",
	"disabled": "68d776e37d9b8cb4b17391ca1b71950550bdd9fb7028ad84fd7b59ee09521143"
}
const BUNDLE_KEYS: Array = ["actor_view", "clock", "ray_records", "actor_id"]
var _presenter: Node2D
var _actor_id: String = ""
var _status: Dictionary = {"ok": false, "error": "not_configured"}
var _configured: bool = false

func _init() -> void:
	set_process(false); set_physics_process(false)
	_presenter = Presenter.new(); _presenter.name = "AuthoritativePirateFrame"
	add_child(_presenter)

static func is_pirate_route(route: Variant) -> bool:
	return route is Dictionary and route.get("control_version") in CONTROL_VERSIONS

static func actor_identity(route: Variant) -> String:
	if not is_pirate_route(route) or route.get("pilot_profile") != route.get("control_version"): return ""
	var encounter: Variant = route.get("pirate_encounter")
	if not encounter is Dictionary or not encounter.get("schema") in ["pirate-orbit-encounter-v1", "pirate-ascent-encounter-v1"]: return ""
	var definition: Variant = encounter.get("definition")
	if not definition is Dictionary or not definition.get("id") is String: return ""
	return definition.id

static func capability_error(sim: Variant) -> String:
	if not sim is Object or not is_instance_valid(sim): return "missing_simulator"
	if not is_pirate_route(sim.get("route")): return "not_pirate_route"
	if actor_identity(sim.get("route")).is_empty(): return "missing_explicit_actor_identity"
	if not sim.has_method("pirate_presentation"): return "missing_pirate_presentation_capability"
	return ""

static func resources_error(root_path: String = ART_ROOT) -> String:
	for state in TEXTURE_PINS:
		var path: String = root_path + state + ".png"
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != TEXTURE_PINS[state]: return "unregistered_pirate_texture:" + state
		if not ResourceLoader.exists(path, "Texture2D"): return "unimported_pirate_texture:" + state
		var texture: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture == null or texture.get_size() != Vector2(192, 192): return "misregistered_pirate_texture:" + state
	return ""

static func route_error(route: Variant) -> String:
	# Resource receipt only; does not authorize/register a player route.
	if not is_pirate_route(route): return ""
	if actor_identity(route).is_empty(): return "海盗航线身份记录不完整，原进度已保留。"
	if not resources_error().is_empty(): return "海盗航线画面仍在恢复中，暂时无法出发。原进度已保留。"
	return ""

func configure_resources() -> Dictionary:
	var error: String = resources_error()
	if not error.is_empty():
		_configured = false; clear_frame(); _status = {"ok": false, "error": error}; return inspect_status()
	var textures: Dictionary = {}
	for state in TEXTURE_PINS: textures[state] = ResourceLoader.load(ART_ROOT + state + ".png", "Texture2D")
	_status = _presenter.configure_textures(textures)
	_configured = _status.get("ok", false)
	return inspect_status()

func update_from_sim(sim: Variant, world_to_view: Transform2D, logical_pixel: float, reduced_motion: bool = false) -> Dictionary:
	var error: String = capability_error(sim)
	if not error.is_empty(): return _reject(error)
	# This is the only owner API called; its complete sample is consumed once.
	var bundle: Variant = sim.pirate_presentation()
	return present_bundle(bundle, actor_identity(sim.route), world_to_view, logical_pixel, reduced_motion)

func present_bundle(bundle: Variant, expected_actor_id: String, world_to_view: Transform2D, logical_pixel: float, reduced_motion: bool = false) -> Dictionary:
	if not _configured: return _reject("textures_not_configured")
	if not bundle is Dictionary or bundle.size() != BUNDLE_KEYS.size(): return _reject("invalid_presentation_bundle")
	for key in BUNDLE_KEYS:
		if not bundle.has(key): return _reject("invalid_presentation_bundle")
	if expected_actor_id.is_empty() or not bundle.actor_id is String or bundle.actor_id != expected_actor_id:
		return _reject("presentation_actor_identity_mismatch")
	if _actor_id != bundle.actor_id: _presenter.clear_frame()
	_actor_id = bundle.actor_id
	_status = _presenter.present(bundle.actor_view, bundle.clock, world_to_view, logical_pixel, bundle.ray_records, bundle.actor_id, reduced_motion)
	if not _status.get("ok", false): _actor_id = ""
	return inspect_status()

func clear_frame() -> void:
	_presenter.clear_frame(); _actor_id = ""; _status = {"ok": true, "cleared": true}

func _reject(error: String) -> Dictionary:
	clear_frame(); _status = {"ok": false, "error": error}; return inspect_status()

func inspect_frame() -> Dictionary:
	return _presenter.inspect_frame()

func inspect_status() -> Dictionary:
	return _status.duplicate(true)

func actor_id() -> String:
	return _actor_id
