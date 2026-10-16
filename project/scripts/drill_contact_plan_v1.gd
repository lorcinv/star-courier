extends RefCounted
## Pair-local first-contact ownership. Unrelated events never re-bisect a
## local curve over a new interval; only genuine pair revisions invalidate it.
const Motion = preload("res://scripts/common_motion_v1.gd")

static func next(owner, entities: Array, finish: float, terminal: Dictionary = {}) -> Dictionary:
	var earliest: Dictionary = {}; var uncertain: Dictionary = {}
	for ai in entities.size():
		for bi in range(ai + 1, entities.size()):
			var a: Dictionary = entities[ai]; var b: Dictionary = entities[bi]
			if a.fixed and b.fixed: continue
			var ak: String = owner._drill_entity_curve_key(a); var bk: String = owner._drill_entity_curve_key(b)
			for p in a.modules:
				for q in b.modules:
					var key = "%s:%d|%s:%d" % [ak, p.id, bk, q.id]
					var plan: Dictionary = owner.chrono_contact_plans.get(key, {})
					if plan.is_empty():
						var origin = maxf(a.body.chrono_motion_start_fraction, b.body.chrono_motion_start_fraction)
						var ac: Dictionary = owner._drill_curve_at(a.body, origin); var bc: Dictionary = owner._drill_curve_at(b.body, origin)
						var duration: float = (1.0 - origin) * owner._tick_dt
						var solved = Motion.sweep(ac, p.lever, bc, q.lever, p.radius + q.radius, duration)
						if solved.state == "miss": continue
						var at = origin + float(solved.get("seconds", solved.get("at", 0.0))) / owner._tick_dt
						if solved.get("seconds", -1.0) == duration: at = 1.0
						if solved.state == "hit":
							var witness = Motion._relative(owner._drill_curve_at(a.body,at),p.lever,owner._drill_curve_at(b.body,at),q.lever,0.0)
							if not Motion._inside(witness,p.radius+q.radius): return {"state":"unresolved","reason":"canonical_contact_witness_mismatch"}
							solved.normal = witness.position.normalized(); solved.distance = witness.position.length()
						var bracket: Array = []
						for bound in solved.get("bracket_seconds", []): bracket.append(origin + bound / owner._tick_dt)
						plan = {"a": ak, "b": bk, "p": int(p.id), "q": int(q.id), "origin": origin,
							"fraction": at, "state": str(solved.state), "reason": str(solved.get("reason", "")),
							"normal": solved.get("normal", Vector2.ZERO), "distance": float(solved.get("distance", 0.0)), "bracket": bracket}
						if owner.chrono_contact_plans.size() >= 400: return {"state":"unresolved","reason":"drill_contact_plan_bound"}
						owner.chrono_contact_plans[key] = plan
					# Only the opt-in terminal observer requests this extra ordering
					# certificate. Distinct witness times with overlapping root
					# brackets cannot establish either event order. Exact represented
					# ties retain physical phase0 before terminal phase3.
					if terminal.get("kind") == "receiver" and terminal.get("cargo_curve_key", "") in [plan.a, plan.b] and plan.state == "hit" and plan.fraction != terminal.fraction:
						if minf(plan.fraction, terminal.fraction) <= finish and maxf(plan.bracket[0], terminal.bracket_fraction[0]) <= minf(plan.bracket[1], terminal.bracket_fraction[1]):
							return {"state":"unresolved","reason":"receiver_contact_order_bracket","fraction":minf(plan.fraction,terminal.fraction)}
					if plan.fraction > finish: continue
					if plan.state != "hit":
						if uncertain.is_empty() or plan.fraction < uncertain.fraction:
							uncertain = {"state":"unresolved","fraction":plan.fraction,"reason":a.key+":"+b.key+":"+plan.reason}
						continue
					if plan.fraction < owner.chrono_fraction: return {"state":"unresolved","reason":"cached_contact_precedes_clock"}
					var order = "%s:%08d:%s:%08d" % [a.key,p.id,b.key,q.id]
					if earliest.is_empty() or plan.fraction < earliest.fraction or (plan.fraction == earliest.fraction and order < earliest.key):
						earliest = {"state":"hit","fraction":plan.fraction,"seconds":(plan.fraction-owner.chrono_fraction)*owner._tick_dt,
							"normal":plan.normal,"distance":plan.distance,"contact_bracket_fraction":plan.bracket,
							"a":a,"b":b,"p":p,"q":q,"key":order}
	if not uncertain.is_empty() and (earliest.is_empty() or uncertain.fraction <= earliest.fraction): return uncertain
	return earliest
