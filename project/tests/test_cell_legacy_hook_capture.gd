extends RefCounted
## Local headless compatibility capture. Runtime source is never mutated.
const V3 = preload("res://scripts/pilot_delivery_simulation_v3.gd")
const P3 = preload("res://scripts/pilot_delivery_profile_v3.gd")
const V4 = preload("res://scripts/pilot_delivery_ascent_simulation_v4.gd")
const P4 = preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const V5 = preload("res://scripts/pilot_delivery_rift_simulation_v5.gd")
const P5 = preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
var compared_leaves: int = 0
var differences: Array = []
func digest(value: Variant) -> String:
 var context = HashingContext.new()
 context.start(HashingContext.HASH_SHA256)
 context.update(var_to_bytes(value))
 return context.finish().hex_encode()
func capture(sim) -> Dictionary:
 var result: Dictionary = {
  "parts": sim.parts.duplicate(true), "bodies": sim.bodies.duplicate(true),
  "links": sim.links.duplicate(true), "telemetry": sim.telemetry.duplicate(true),
  "events": sim.events.duplicate(true), "incidents": sim.incidents.duplicate(true),
  "effects": sim.effects.duplicate(true), "obstacles": sim.obstacles.duplicate(true),
  "launcher_parts": sim.launcher_parts.duplicate(true), "route": sim.route.duplicate(true),
  "status": sim.status, "elapsed": sim.elapsed, "pilot_tick": sim.pilot_tick,
  "launch_released": sim.launch_released,
  "cargo_filtered_acceleration": sim._cargo_filtered_acceleration.duplicate(true),
  "delivery_contact_parts": sim._delivery_contact_parts.duplicate(true),
  "rng_state": sim._rng.state, "accumulator": sim._accumulator,
 }
 if sim is V4: result["ascent_events"] = sim.ascent_meteors.snapshot().duplicate(true)
 if sim is V5:
  result["portal_crossings"] = sim.portal_crossings.duplicate(true)
  result["rift_threats"] = sim._rift_threats.snapshot().duplicate(true)
 return result
func command(tick: int) -> Array:
 if tick < 90: return [800, -600, true, false, -1, false]
 if tick < 150: return [0, 0, false, false, -1, false]
 if tick < 210: return [0, 0, false, false, -1, true]
 return [600, -800, false, false, -1, false]
func compare(a: Variant, b: Variant, at: String) -> void:
 if typeof(a) != typeof(b):
  differences.append({"path": at, "reason": "type", "baseline": typeof(a), "candidate": typeof(b)})
  return
 if a is Dictionary:
  if a.size() != b.size(): differences.append({"path": at, "reason": "dictionary_size", "baseline": a.size(), "candidate": b.size()})
  for key in a:
   if not b.has(key): differences.append({"path": at + "/" + str(key), "reason": "missing_key"})
   else: compare(a[key], b[key], at + "/" + str(key))
 elif a is Array:
  if a.size() != b.size(): differences.append({"path": at, "reason": "array_size", "baseline": a.size(), "candidate": b.size()})
  for i in range(mini(a.size(), b.size())): compare(a[i], b[i], at + "/" + str(i))
 else:
  compared_leaves += 1
  if var_to_bytes(a) != var_to_bytes(b): differences.append({"path": at, "reason": "value_bytes", "baseline": str(a), "candidate": str(b)})
func run(output: String, baseline: String = "") -> int:
 DirAccess.make_dir_recursive_absolute(output)
 var report: Dictionary = {"seed": 42, "ticks": 240, "dt": 1.0 / 60.0, "release": [35.0, 1.0], "protocols": {}, "differences": []}
 var classes: Array = [V3, V4, V5]
 var profiles: Array = [P3, P4, P5]
 for index in range(3):
  var name: String = "v%d" % (index + 3)
  var sim = classes[index].new()
  var route: Dictionary = profiles[index].route()
  if route.is_empty() or not profiles[index].validation_error(route).is_empty():
   push_error("invalid legal profile route " + name)
   return 2
  sim.configure(P3.starter_design(), P3.starter_launcher(), route, 42)
  var trace: Array = [capture(sim)]
  var released: Dictionary = sim.release_launcher(35.0, 1.0)
  if not released.get("released", false):
   push_error("release failed " + name)
   return 2
  trace.append({"release": released.duplicate(true), "state": capture(sim)})
  var commands: Array = []
  var running_frames: int = 0
  for tick in range(240):
   var input: Array = command(tick)
   commands.append(input)
   sim.set_free_flight_input(input[0], input[1], input[2], input[3], input[4], input[5])
   sim.step(1.0 / 60.0)
   if sim.status == "running": running_frames += 1
   trace.append(capture(sim))
  var data: Dictionary = {"commands": commands, "trace": trace}
  var bytes: PackedByteArray = var_to_bytes(data)
  var binary = FileAccess.open(output.path_join(name + ".bin"), FileAccess.WRITE)
  binary.store_buffer(bytes)
  binary.close()
  var per_field: Dictionary = {}
  for key in trace[-1]:
   var series: Array = []
   for snapshot in trace:
    if snapshot.has(key): series.append(snapshot[key])
    elif snapshot.has("state"): series.append(snapshot.state[key])
   per_field[key] = digest(series)
  var result: Dictionary = {"snapshots": trace.size(), "input_frames": commands.size(), "running_frames": running_frames, "final_status": sim.status, "final_elapsed": sim.elapsed, "final_pilot_tick": sim.pilot_tick, "bytes": bytes.size(), "sha256": digest(data), "field_sha256": per_field, "final_position": str(sim.cargo_position()), "energy_used": sim.telemetry.energy_used, "cargo_integrity": sim.ship_integrity()}
  if not baseline.is_empty():
   var prior_file = FileAccess.open(baseline.path_join(name + ".bin"), FileAccess.READ)
   if prior_file == null: return 2
   var prior_bytes: PackedByteArray = prior_file.get_buffer(prior_file.get_length())
   prior_file.close()
   var start: int = compared_leaves
   var previous_count: int = differences.size()
   compare(bytes_to_var(prior_bytes), data, name)
   result["binary_equal"] = prior_bytes == bytes
   result["compared_leaves"] = compared_leaves - start
   result["differences"] = differences.size() - previous_count
  report.protocols[name] = result
  print("LEGACY_HOOK_CAPTURE ", name, " frames=", commands.size(), " elapsed=", sim.elapsed, " sha256=", result.sha256, " binary_equal=", result.get("binary_equal", "baseline"))
 report.differences = differences
 report["compared_leaves"] = compared_leaves
 var json = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
 json.store_string(JSON.stringify(report, "  ", true, true) + "\n")
 json.close()
 return 0 if differences.is_empty() else 1
