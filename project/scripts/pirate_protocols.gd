extends RefCounted
## Version dispatch only. Never author, upgrade, normalize or reinterpret a route.
const V1 = preload("res://scripts/pirate_encounter_profile_v1.gd")
const V2 = preload("res://scripts/pirate_encounter_profile_v2.gd")
const VERSIONS: Array = [V1.VERSION, V2.VERSION]

static func is_version(value: Variant) -> bool:
 return value is String and value in VERSIONS

static func has_markers(route: Dictionary) -> bool:
 return route.has("pirate_encounter") or is_version(route.get("control_version")) or is_version(route.get("pilot_profile"))

static func profile_for_version(version: Variant):
 match version:
  V1.VERSION: return V1
  V2.VERSION: return V2
 return null

static func route_error(route: Dictionary) -> String:
 # Shared adapter boundary: immutable versioned profiles compare Strings.
 # Reject malformed identity before dispatching into either profile owner.
 for key in ["control_version", "pilot_profile", "mode"]:
  if not route.get(key) is String: return "pirate_route_identity"
 var profile = profile_for_version(route.get("control_version"))
 if profile == null: return "unsupported_pirate_control_version"
 return profile.route_error(route)

static func snapshot_version(version: Variant) -> String:
 match version:
  V1.VERSION: return "pirate-route-native-snapshot-2"
  V2.VERSION: return "pirate-route-native-snapshot-3"
 return ""
