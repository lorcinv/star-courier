extends RefCounted
## Structural phases injected into the same motion/contact/resource kernel.
const Common = preload("res://scripts/pirate_chronology_v1.gd")
const MAX_EVENTS = 256

static func run(owner, dt: float) -> Dictionary:
	var fraction = 0.0
	for ordinal in range(MAX_EVENTS):
		owner._chrono_rebuild(); owner._chrono_fields()
		var entities: Array = owner._chrono_entities()
		var remaining = dt * (1.0 - fraction)
		var force: Dictionary = owner._chrono_force_boundary(remaining)
		var finish = 1.0 if force.seconds == remaining else fraction + force.seconds / dt
		var seconds: float = force.seconds
		var stress: Dictionary = owner._chrono_stress_boundary()
		var breaks: Array = []
		if stress.fraction <= finish:
			finish = stress.fraction; seconds = (finish - fraction) * dt; breaks = stress.ids
		var emission: bool = owner._chrono_emission_due()
		if emission or owner._chrono_stress_due(): finish = fraction; seconds = 0.0; breaks = []
		var hit: Dictionary = Common._next_contact(entities, seconds)
		if hit.get("state", "") == "unresolved": return Common._hold(owner, fraction, hit.get("reason", "unresolved_contact"))
		if hit.get("state", "") == "hit":
			var at = finish if hit.seconds == seconds else fraction + hit.seconds / dt
			_advance(owner, entities, hit.seconds, at, breaks if hit.seconds == seconds else [])
			fraction = at
			var event: Dictionary = Common._impulse(hit)
			event.tick = owner.pilot_tick - 1; event.fraction = fraction; event.ordinal = ordinal; event.phase = 0
			owner._chrono_contact(event)
			if not owner._chrono_commit_actor(fraction): return Common._hold(owner, fraction, owner.chrono_error)
			continue
		if owner._chrono_stress_due():
			owner._chrono_break_stress(ordinal)
			continue
		if emission:
			var emitted: Dictionary = owner._chrono_emit()
			if not emitted.ok: return Common._hold(owner, fraction, emitted.get("error", "emission_failed"))
			for ray in emitted.get("intents", []): owner._chrono_ray(ray, Common.nearest_ray(entities, ray), ordinal)
			continue
		_advance(owner, entities, seconds, finish, breaks)
		fraction = finish
		if seconds == force.seconds: owner._chrono_exhaust(force.ids)
		if not owner._chrono_commit_actor(fraction): return Common._hold(owner, fraction, owner.chrono_error)
		# Endpoint break is resolved before returning to the next tick. TickT/1
		# and tickT+1/0 are one physical instant, with no epsilon adjustment.
		if fraction == 1.0 and not owner._chrono_stress_due(): return {"ok": true, "fraction": 1.0, "events": ordinal + 1}
	return Common._hold(owner, fraction, "structural_event_budget")

static func _advance(owner, entities: Array, seconds: float, fraction: float, breaks: Array) -> void:
	owner._chrono_apply_resources_at(seconds, fraction)
	for entity in entities: Common.Motion.advance(entity.body, seconds)
	owner.chrono_fraction = fraction
	owner._chrono_apply_stress(fraction, breaks)
