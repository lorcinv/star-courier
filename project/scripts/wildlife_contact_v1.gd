extends RefCounted
## UNINTEGRATED source preparation. Calling this function is not evidence of a
## collision: the new simulator must first establish a real swept narrowphase hit.
## Frozen proposal for one small soft-body bird; does not mutate any world state.
const VERSION: String = "protected-bird-contact-v1"
const BIRD_MASS: float = 0.125
const BIRD_RADIUS: float = 0.375
const BIRD_MAX_HP: float = 8.0
const SOFT_CONTACT_ALLOWANCE_J: float = 0.125
const DAMAGE_HP_PER_J: float = 1.0
const RESTITUTION: float = 0.0

static func solve(ship_mass: float, ship_inertia: float, ship_velocity: Vector2,
        ship_angular_velocity: float, contact_arm: Vector2, bird_velocity: Vector2,
        normal_from_bird: Vector2, bird_hp: float) -> Dictionary:
    for value in [ship_mass, ship_inertia, ship_angular_velocity, bird_hp]:
        if not is_finite(value): return _error("nonfinite_scalar")
    if ship_mass <= 0.0 or ship_inertia <= 0.0: return _error("invalid_ship_mass_or_inertia")
    if bird_hp < 0.0 or bird_hp > BIRD_MAX_HP: return _error("invalid_bird_hp")
    for value in [ship_velocity, contact_arm, bird_velocity, normal_from_bird]:
        if not value.is_finite(): return _error("nonfinite_vector")
    if normal_from_bird.length_squared() < 0.000000000001: return _error("missing_contact_normal")
    var normal: Vector2 = normal_from_bird.normalized()
    var contact_velocity: Vector2 = ship_velocity + Vector2(-contact_arm.y, contact_arm.x) * ship_angular_velocity
    var relative: float = (contact_velocity - bird_velocity).dot(normal)
    var denominator: float = 1.0 / ship_mass + pow(contact_arm.cross(normal), 2.0) / ship_inertia + 1.0 / BIRD_MASS
    if not is_finite(relative) or not is_finite(denominator) or denominator <= 0.0: return _error("invalid_contact_arithmetic")
    var impulse: float = 0.0
    var dissipated: float = 0.0
    if bird_hp > 0.0 and relative < 0.0:
        impulse = -(1.0 + RESTITUTION) * relative / denominator
        dissipated = 0.5 * (1.0 - RESTITUTION * RESTITUTION) * relative * relative / denominator
    var requested_damage: float = maxf(0.0, dissipated - SOFT_CONTACT_ALLOWANCE_J) * DAMAGE_HP_PER_J
    var after: float = maxf(0.0, bird_hp - requested_damage)
    var impulse_vector: Vector2 = normal * impulse
    return {
        "ok": true, "version": VERSION, "impulse": impulse_vector,
        "ship_velocity_delta": impulse_vector / ship_mass,
        "ship_angular_velocity_delta": contact_arm.cross(impulse_vector) / ship_inertia,
        "bird_velocity_delta": -impulse_vector / BIRD_MASS,
        "normal_dissipated_j": dissipated,
        "hp_before": bird_hp, "hp_after": after, "hp_delta": bird_hp - after,
        "ship_hp_damage": 0.0
    }

static func _error(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
