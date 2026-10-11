extends SceneTree
## Prepared only; NOT RUN. In the private candidate, place the helper at the
## referenced path and run this harness only after the Godot lane is allocated.
const Contact = preload("res://scripts/wildlife_contact_v1.gd")
var failures: int = 0
var checks: int = 0

func _init() -> void:
    var hit: Dictionary = Contact.solve(20.0, 12.0, Vector2(18.0, 0.0), 0.0,
        Vector2.ZERO, Vector2.ZERO, Vector2.LEFT, Contact.BIRD_MAX_HP)
    check(hit.ok and hit.hp_delta > 0.0, "Actual approaching contact has finite damage")
    check(hit.ship_velocity_delta.length() < 0.12, "Small bird does not stop or reverse large ship")
    check(hit.ship_hp_damage == 0.0, "Soft wildlife contact adds no hull repair damage")
    check((hit.ship_velocity_delta * 20.0 + hit.bird_velocity_delta * Contact.BIRD_MASS).length() < 0.00001,
        "Equal and opposite impulse conserves linear momentum")
    check(hit.hp_delta == Contact.BIRD_MAX_HP and hit.hp_after == 0.0,
        "Actual HP decrement is clamped, not requested overkill")
    var ship_after: Vector2 = Vector2(18.0, 0.0) + hit.ship_velocity_delta
    var bird_after: Vector2 = hit.bird_velocity_delta
    var before_energy: float = 0.5 * 20.0 * 18.0 * 18.0
    var after_energy: float = 0.5 * 20.0 * ship_after.length_squared() + 0.5 * Contact.BIRD_MASS * bird_after.length_squared()
    check(absf(before_energy - after_energy - hit.normal_dissipated_j) < 0.001,
        "Dissipated energy matches kinetic-energy loss")
    var gentle: Dictionary = Contact.solve(20.0, 12.0, Vector2(1.0, 0.0), 0.0,
        Vector2.ZERO, Vector2.ZERO, Vector2.LEFT, Contact.BIRD_MAX_HP)
    check(gentle.ok and gentle.impulse.length() > 0.0 and gentle.hp_delta == 0.0,
        "Gentle real contact can exchange momentum without harm")
    for velocity in [Vector2(-18.0, 0.0), Vector2(0.0, 18.0), Vector2.ZERO]:
        var harmless: Dictionary = Contact.solve(20.0, 12.0, velocity, 0.0,
            Vector2.ZERO, Vector2.ZERO, Vector2.LEFT, Contact.BIRD_MAX_HP)
        check(harmless.ok and harmless.impulse == Vector2.ZERO and harmless.hp_delta == 0.0,
            "Separating or tangent contact cannot damage")
    var dead: Dictionary = Contact.solve(20.0, 12.0, Vector2(18.0, 0.0), 0.0,
        Vector2.ZERO, Vector2.ZERO, Vector2.LEFT, 0.0)
    check(dead.ok and dead.hp_delta == 0.0 and dead.impulse == Vector2.ZERO,
        "An already-dead bird cannot be damaged or collide again")
    var arm: Vector2 = Vector2(0.0, 2.0)
    var offcenter: Dictionary = Contact.solve(20.0, 12.0, Vector2(18.0, 0.0), 0.0,
        arm, Vector2.ZERO, Vector2.LEFT, Contact.BIRD_MAX_HP)
    check(offcenter.ok and absf(offcenter.ship_angular_velocity_delta) > 0.0,
        "Off-center real contact creates real torque")
    check(offcenter.normal_dissipated_j < hit.normal_dissipated_j,
        "Rotational compliance participates in the denominator")
    var off_ship: Vector2 = Vector2(18.0, 0.0) + offcenter.ship_velocity_delta
    var off_energy: float = 0.5 * 20.0 * off_ship.length_squared() + 0.5 * 12.0 * pow(offcenter.ship_angular_velocity_delta, 2.0) + 0.5 * Contact.BIRD_MASS * offcenter.bird_velocity_delta.length_squared()
    check(absf(before_energy - off_energy - offcenter.normal_dissipated_j) < 0.001,
        "Off-center energy accounting includes rotation")
    check(not Contact.solve(0.0, 12.0, Vector2.ZERO, 0.0, Vector2.ZERO, Vector2.ZERO,
        Vector2.LEFT, 8.0).ok, "Invalid mass is rejected")
    check(not Contact.solve(20.0, 12.0, Vector2.ZERO, 0.0, Vector2.ZERO, Vector2.ZERO,
        Vector2.ZERO, 8.0).ok, "Missing narrowphase normal is rejected")
    print("WILDLIFE_CONTACT_PREPARED_TEST checks=%d failures=%d" % [checks, failures])
    quit(1 if failures else 0)

func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(label)
