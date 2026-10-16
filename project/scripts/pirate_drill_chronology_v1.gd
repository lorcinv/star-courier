extends RefCounted
## Bounded drill exposure added to the reviewed contact/structure event clock.
const Common = preload("res://scripts/pirate_chronology_v1.gd")
const ContactPlan = preload("res://scripts/drill_contact_plan_v1.gd")
const MAX_EVENTS = 512

static func run(owner, dt: float, observer = null) -> Dictionary:
	var fraction = 0.0
	for ordinal in range(MAX_EVENTS):
		owner._chrono_rebuild(); owner._chrono_fields()
		if not owner.chrono_error.is_empty(): return Common._hold(owner, fraction, owner.chrono_error)
		var entities: Array = owner._chrono_entities()
		var remaining = dt * (1.0 - fraction)
		var force: Dictionary = owner._chrono_force_boundary(remaining)
		var force_finish = 1.0 if force.seconds == remaining else fraction + force.seconds / dt
		var finish = force_finish
		var stress: Dictionary = owner._chrono_stress_boundary()
		var drill: Dictionary = owner._drill_boundary()
		finish = minf(finish, minf(stress.fraction, drill.fraction))
		var observed: Dictionary = {"fraction": 2.0, "state": "miss"}
		if observer != null:
			observed = observer._route_boundary()
			finish = minf(finish, observed.fraction)
		var breaks: Array = stress.ids if stress.fraction == finish else []
		var deaths: Array = drill.ids if drill.fraction == finish else []
		var emission: bool = owner._chrono_emission_due()
		if emission or owner._chrono_stress_due() or owner._drill_death_due(): finish = fraction; breaks = []; deaths = []
		var seconds: float = force.seconds if finish == force_finish else (finish - fraction) * dt
		var hit: Dictionary = ContactPlan.next(owner, entities, finish, observed if observer != null and observed.state == "hit" else {})
		if hit.get("state", "") == "unresolved": return Common._hold(owner, fraction, hit.get("reason", "unresolved_contact"))
		if hit.get("state", "") == "hit":
			var at: float = hit.fraction
			_advance(owner, entities, hit.seconds, at, breaks if at == finish else [], deaths if at == finish else [])
			fraction = at
			var event: Dictionary = Common._impulse(hit)
			event.contact_bracket_fraction = hit.contact_bracket_fraction
			event.tick = owner.pilot_tick - 1; event.fraction = fraction; event.ordinal = ordinal; event.phase = 0
			owner._chrono_contact(event)
			if not owner._chrono_commit_actor(fraction): return Common._hold(owner, fraction, owner.chrono_error)
			continue
		if owner._chrono_stress_due(): owner._chrono_break_stress(ordinal); continue
		if owner._drill_death_due(): owner._drill_commit_deaths(ordinal); continue
		if emission:
			var emitted: Dictionary = owner._chrono_emit()
			if not emitted.ok: return Common._hold(owner, fraction, emitted.get("error", "emission_failed"))
			for ray in emitted.get("intents", []): owner._chrono_ray(ray, Common.nearest_ray(entities, ray), ordinal)
			continue
		if observed.state == "unresolved" and observed.fraction <= finish: return Common._hold(owner, fraction, observed.reason)
		if observer != null and observed.fraction == fraction:
			observer._route_commit(observed, ordinal)
			if owner.status != "running": return {"ok": true, "fraction": fraction, "events": ordinal + 1}
			continue
		if observer != null:
			var order_error: String = observer._route_guard_local_boundary(observed, finish, force.ids if finish == force_finish else [], breaks, deaths, entities)
			if not order_error.is_empty(): return Common._hold(owner, fraction, order_error)
		_advance(owner, entities, seconds, finish, breaks, deaths)
		fraction = finish
		if finish == force_finish: owner._chrono_exhaust(force.ids)
		if not owner._chrono_commit_actor(fraction): return Common._hold(owner, fraction, owner.chrono_error)
		if fraction == 1.0 and not owner._chrono_stress_due() and not owner._drill_death_due() and (observer == null or observed.fraction != fraction):
			return {"ok": true, "fraction": fraction, "events": ordinal + 1}
	return Common._hold(owner, fraction, "drill_event_budget")

static func _advance(owner, entities: Array, seconds: float, fraction: float, breaks: Array, deaths: Array) -> void:
	owner._chrono_apply_resources_at(seconds, fraction)
	owner._drill_apply(fraction, deaths)
	for entity in entities: owner._drill_advance_at(entity.body, fraction)
	owner.chrono_fraction = fraction
	owner._chrono_apply_stress(fraction, breaks)
