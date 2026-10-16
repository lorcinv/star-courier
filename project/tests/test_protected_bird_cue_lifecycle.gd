extends SceneTree
## Synthetic read-only geometry/presentation fixtures, not collision evidence.
const Advice = preload("res://scripts/protected_bird_advice_2d.gd")
const Presentation = preload("res://scripts/protected_bird_presentation_2d.gd")
const Profile = preload("res://scripts/pilot_protected_bird_profile.gd")
const Receipt = preload("res://scripts/flight_receipt.gd")
const HUD = preload("res://scripts/game_hud.gd")
const Cues = preload("res://scripts/flight_cues_2d.gd")
var passed: int = 0
var failed: int = 0

class SnapshotSim extends RefCounted:
	var route: Dictionary
	var wildlife: Dictionary
	var bodies: Array = []
	var wildlife_error: String = ""
	var pilot_tick: int = 10
	var status: String = "running"
	var paused: bool = false
	var events: Array = ["0.00s  保护鸟穿越 · 从下方绕行", "0.00s  未知事件保持原样"]
	var telemetry: Dictionary = {"wildlife_contacts":0,"energy_used":3.0}
	var first_harm: Dictionary = {}
	var source_registry: Dictionary = {"fixture-source":{"owner_kind":"courier"}}
	var review_facts: Dictionary = {"pending":{},"history":[],"credits":260}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS ",label)
	else: failed += 1; push_error("FAIL " + label)
func part(kind: String = "cargo", at: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"type":kind,"alive":true,"delivered":false,"local_pos":at,"local_angle":0.0,"scale":1.0}
func body(at: Vector2, velocity: Vector2 = Vector2(10,0), modules: Array = []) -> Dictionary:
	return {"position":at,"velocity":velocity,"angle":0.0,"angular_velocity":0.0,"parts":[part()] if modules.is_empty() else modules}
func fixture() -> SnapshotSim:
	var sim = SnapshotSim.new(); sim.route = Profile.route({},"ADVICE-TEST",42)
	var event: Dictionary = sim.route.ecology
	sim.wildlife = {"event_id":event.event_id,"entity_id":event.entity_id,"species_id":event.species_id,
		"position":Vector2(1100,-146),"velocity":Vector2(-3,0),"mass":0.125,"radius":0.375,"hp":8.0,
		"state":"healthy","active":true,"activated":true,"activation_tick":10,
		"activation_fraction":0.5,"hurt_ticks":0,"fall_ticks":0,"damage_transitions":0}
	sim.bodies = [body(sim.wildlife.position + Vector2(-2,5))]
	return sim
func view_of(at: Vector2, zoom: float = 0.3) -> Rect2:
	var span = Vector2(1200,500) / zoom
	return Rect2(at * 72.0 - span * 0.5, span)
func facts(sim) -> PackedByteArray:
	return var_to_bytes([sim.route,sim.wildlife,sim.bodies,sim.wildlife_error,sim.pilot_tick,sim.status,
		sim.paused,sim.events,sim.telemetry,sim.first_harm,sim.source_registry,sim.review_facts])
func sample(layer, sim, paused_visual: bool = false, view: Rect2 = Rect2()) -> void:
	var before: PackedByteArray = facts(sim)
	layer.update_from_sim(sim,view_of(sim.wildlife.position) if view.size == Vector2.ZERO else view,0.3,paused_visual)
	check(facts(sim) == before,"presentation leaves all source facts byte-identical")
func expect_advice(layer, active: bool, label: String) -> void:
	check(layer.advisory_state().get("active") == active and layer.cue_state().active == active and layer.debug_snapshot().advice_active == active,label)
	if not active:
		check(not layer.get_node("OffscreenProtectionNotice").visible and not layer.get_node("LowerPassageNotice").visible and layer.cue_state().points.is_empty(),label + " clears every directional helper")

func geometry() -> void:
	var sim = fixture(); var bird = sim.wildlife.duplicate(true); bird.position = Vector2.ZERO; bird.velocity = Vector2.ZERO
	check(Advice.active("running",bird,[body(Vector2(-2,0))]),"approaching craft retains advice")
	check(not Advice.active("running",bird,[body(Vector2(2,0))]),"whole cargo shell past bird and diverging retires advice")
	check(Advice.active("running",bird,[body(Vector2(0.375 + Advice.REAR_CLEARANCE_M + 0.43,0))]),"rear-clearance boundary is conservative")
	var long_body = body(Vector2(10,0),Vector2(10,0),[part(),part("beam",Vector2(-12,0))])
	check(Advice.active("running",bird,[long_body]),"cargo center beyond encounter does not clear a long rear module")
	long_body.position.x = 15
	check(not Advice.active("running",bird,[long_body]),"long craft retires only after its rearmost shell clears")
	var rotated = body(Vector2(3,0),Vector2(10,0),[part(),part("beam",Vector2(0,4))])
	check(not Advice.active("running",bird,[rotated]),"unrotated vertical module footprint is clear")
	rotated.angle = PI / 2.0
	check(Advice.active("running",bird,[rotated]),"actual rotation moves rear module into actionable extent")
	rotated.angle = 0.0; rotated.angular_velocity = 4.0
	check(Advice.active("running",bird,[rotated]),"rotating rearward point velocity prevents early retirement")
	check(Advice.active("running",bird,[body(Vector2(2,20),Vector2(1,-10))]),"radially closing motion retains advice despite positive axial motion")
	check(Advice.active("running",bird,[body(Vector2(3,0),Vector2(-2,0))]),"reverse closing motion immediately re-arms predicate")
	bird.velocity = Vector2(20,0)
	check(Advice.active("running",bird,[body(Vector2(3,0))]),"faster following bird also keeps advice actionable")
	bird.velocity = Vector2(-5,0)
	check(not Advice.active("running",bird,[body(Vector2(3,0),Vector2(-2,0))]),"absolute reverse alone is not a renewed relative closing threat")
	bird.velocity = Vector2.ZERO
	var clear = body(Vector2(3,0))
	var debris = body(Vector2(-20,0),Vector2(20,0),[part("beam")])
	check(not Advice.active("running",bird,[clear,debris]),"uncontrolled detached no-cargo debris does not retain steering advice")
	debris.parts.append(part())
	check(Advice.active("running",bird,[clear,debris]),"another actual cargo-connected body must also clear")
	var dead = part("beam",Vector2(-20,0)); dead.alive = false; clear.parts.append(dead)
	check(not Advice.active("running",bird,[clear]),"dead rear module is not part of live craft")
	dead.alive = true; dead.delivered = true
	check(not Advice.active("running",bird,[body(Vector2(3,0),Vector2(10,0),[part(),dead])]),"delivered hardware is excluded")
	var drill = part("drill"); drill.local_angle = PI
	check(Advice.active("running",bird,[body(Vector2(1.08,0),Vector2(10,0),[part(),drill])]),"actual rearward drill head prevents shell-only early retirement")
	var scaled = part("beam"); scaled.scale = 4.0
	check(Advice.active("running",bird,[body(Vector2(2,0),Vector2(10,0),[part(),scaled])]),"actual module scale contributes to physical extent")
	bird.radius = 2.0
	check(Advice.active("running",bird,[body(Vector2(2,0))]),"physical bird radius participates in the test")
	bird.radius = 0.375
	check(Advice.active("running",bird,null),"unknown craft cannot establish passage")
	check(Advice.active("running",bird,[{"parts":null}]),"invalid craft cannot establish passage")
	check(not Advice.active("running",bird,[]),"absent controllable craft produces no steering advice")
	for status in ["success","failed"]: check(not Advice.active(status,bird,[body(Vector2(-2,0))]),"terminal " + status + " has no advice")
	for state in ["falling","gone","departed","waiting"]:
		bird.state = state; check(not Advice.active("running",bird,[body(Vector2(-2,0))]),state + " has no directional advice")
	var before = facts(sim)
	for i in 1000: Advice.active(sim.status,sim.wildlife,sim.bodies)
	check(facts(sim) == before,"repeated geometry reads leave source sim/telemetry/review facts unchanged")

func presentation_lifecycle() -> void:
	var layer = Presentation.new(); root.add_child(layer)
	var cues = Cues.new(); root.add_child(cues)
	var sim = fixture(); var before = facts(sim)
	check(layer.configure(sim,Vector2.ZERO,72.0),"approaching baseline configures")
	check(facts(sim) == before,"baseline construction is read-only")
	sample(layer,sim); expect_advice(layer,true,"approaching state shared with HUD")
	check(layer.debug_snapshot().marker_text == "保护鸟 · 请绕行","actionable marker retains directional copy")
	sample(layer,sim,false,view_of(sim.wildlife.position + Vector2(100,0)))
	check(layer.debug_snapshot().edge_notice_visible,"offscreen approach can show a directional edge notice")
	sim.bodies[0].position.x = sim.wildlife.position.x + 5
	for i in 12: sample(layer,sim,false,view_of(sim.wildlife.position + Vector2(i,0)))
	expect_advice(layer,true,"same-tick geometry changes/reflows do not advance navigation state")
	sim.pilot_tick += 1; sim.paused = true; sample(layer,sim)
	expect_advice(layer,true,"simulation pause does not retire frozen advice")
	sim.paused = false; sample(layer,sim,true)
	expect_advice(layer,true,"focus pause does not retire frozen advice")
	sample(layer,sim); expect_advice(layer,false,"next accepted moving tick retires passed advice")
	check(layer.debug_snapshot().creature_visible and layer.debug_snapshot().marker_visible and layer.debug_snapshot().marker_text == "保护鸟","visible creature identity remains without directional copy")
	check(layer.get_child_count() == 4 and layer.get_node("RegisteredProtectedBird").scale == Vector2.ONE * 2.25,"same bounded helpers and registered source-art scale")
	cues.set_protected_bird_cue(layer.cue_state()); check(cues.protected_bird_path.is_empty(),"world chevrons clear from shared retired state")
	var retired = layer.debug_snapshot()
	for i in 1000: layer.update_from_sim(sim,view_of(sim.wildlife.position),0.3)
	check(layer.debug_snapshot() == retired,"thousand retired reflows are idempotent")
	sample(layer,sim,false,view_of(sim.wildlife.position + Vector2(100,0)))
	expect_advice(layer,false,"offscreen passed bird cannot restore behind arrow")
	sim.bodies[0].velocity = Vector2(-20,0); sim.pilot_tick += 1
	sample(layer,sim,true); expect_advice(layer,false,"focus pause cannot re-arm newer reversed data")
	sample(layer,sim); expect_advice(layer,true,"actual next reversed closing tick re-arms advice")
	sim.bodies[0].velocity = Vector2(10,0); sim.pilot_tick += 1; sample(layer,sim)
	expect_advice(layer,false,"renewed separation retires advice again")
	check(layer.configure(sim,Vector2.ZERO,72.0,true),"restore configures passed present state")
	sample(layer,sim,true); expect_advice(layer,false,"restore does not replay obsolete navigation")
	check(layer.debug_snapshot().new_hp_notices == 0,"restore does not fabricate HP notice")
	sim.pilot_tick += 1; sim.wildlife.hp = 6.0; sim.wildlife.damage_transitions = 1; sim.wildlife.state = "hurt"; sim.wildlife.hurt_ticks = 36
	sample(layer,sim); expect_advice(layer,false,"real injury beyond the encounter does not re-arm old direction")
	check(layer.debug_snapshot().marker_text == "保护鸟受伤了" and layer.debug_snapshot().new_hp_notices == 1 and layer.debug_snapshot().pose == "hurt","true injury feedback remains visible after navigation retires")
	check(layer.configure(sim,Vector2.ZERO,72.0,true),"restore injured passed sample")
	sample(layer,sim,true)
	check(layer.debug_snapshot().pose == "hurt" and layer.debug_snapshot().new_hp_notices == 0,"restored injury identity persists without replayed feedback")
	sim.pilot_tick += 1; sim.wildlife.hp = 0.0; sim.wildlife.damage_transitions += 1; sim.wildlife.state = "falling"; sim.wildlife.active = false
	sample(layer,sim); check(layer.debug_snapshot().pose == "hurt" and layer.debug_snapshot().sprite_alpha == 1.0,"real falling feedback stays intact")
	sim.pilot_tick += 48; sim.wildlife.state = "gone"; sim.wildlife.fall_ticks = 48
	sample(layer,sim); expect_advice(layer,false,"gone clears navigation"); check(not layer.visible,"gone clears creature")
	for i in 8:
		layer.leave_flight(); layer.leave_flight(); check(layer.advisory_state().is_empty(),"cancel/leave discards HUD state")
		sim = fixture(); check(layer.configure(sim,Vector2.ZERO,72.0),"retry creates current baseline")
		sample(layer,sim); expect_advice(layer,true,"retry can advise again without stale retired latch")
	check(layer.get_child_count() == 4,"repeated cancel/retry adds no helper or timer")
	sim.status = "success"; sample(layer,sim); expect_advice(layer,false,"same-tick success drops direction without advancing geometry")
	check(layer.debug_snapshot().marker_text == "保护鸟","success retains non-directional identity")
	layer.queue_free(); cues.queue_free(); await process_frame

func receipt_lifecycle() -> void:
	var receipt = Receipt.new()
	var event: String = "10.00s  " + Receipt.BIRD_DIRECTION_COPY
	var data: Dictionary = {"elapsed":11.0,"control_version":Profile.CONTROL_VERSION,"events":[event],"protected_bird_advice":{"active":true}}
	check(receipt.update(data).size() == 1,"exact direction remains while actionable")
	data.protected_bird_advice.active = false
	var before = var_to_bytes(data)
	check(receipt.update(data).is_empty(),"exact direction retires before independent six-second timer")
	check(var_to_bytes(data) == before and Receipt.player_event(event,Profile.CONTROL_VERSION) == event,"receipt filter leaves source, tooltip projection and report history untouched")
	data.protected_bird_advice.active = true
	check(receipt.update(data).size() == 1,"fresh timestamp can accompany re-armed actual advice")
	data.elapsed = 20.0
	check(receipt.update(data).is_empty(),"re-arming cannot replay an expired logged notice")
	for state in [null,{}, {"active":0},{"active":"false"},{"active":true}]:
		receipt.reset(); data.elapsed = 11.0; data.protected_bird_advice = state
		check(receipt.update(data).size() == 1,"missing/malformed/non-retired advisory never suppresses source text")
	data.protected_bird_advice = {"active":false}
	for version in ["","pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v99"]:
		receipt.reset(); data.control_version = version
		check(receipt.update(data).size() == 1,"other protocol remains byte-compatible: " + version)
	data.control_version = Profile.CONTROL_VERSION
	for message in ["保护鸟穿越 · 从下方绕行！","保护鸟穿越 · 从下方绕行（未知）","请从下方绕行","首次受损：HP 8 → 6","保护鸟受伤了","错误：鸟已不在前方","未知事件"]:
		receipt.reset(); data.events = ["10.00s  " + message]
		var items = receipt.update(data)
		check(items.size() == 1 and items[0].text == message,"only exact emitter filtered; preserves " + message)
	receipt.reset(); data.events = ["10.00s  " + Receipt.BIRD_FAILURE_PREFIX + "fixture"]
	check(receipt.update(data)[0].text == Receipt.BIRD_FAILURE_COPY,"existing v5 error presentation remains intact")
	receipt.reset(); data.elapsed = 30.0; data.wormhole_phase = "space"; data.wormhole_last_denial = "exit_blocked"
	data.events = ["1.00s  " + Receipt.PORTAL_DENIALS.exit_blocked]
	check(receipt.update(data).size() == 1,"unresolved old portal-denial pinning survives")
	receipt.reset(); data.events = [Receipt.BIRD_DIRECTION_COPY]; data.elapsed = 0.0
	check(receipt.update(data).is_empty(),"untimed exact source is hidden while retired")
	data.elapsed = 10.0; data.protected_bird_advice.active = true
	check(receipt.update(data).is_empty(),"hidden untimed source still ages instead of becoming fresh on re-arm")
	var hud = HUD.new(); root.add_child(hud); hud.set_art_frame(Rect2(0,40,1280,720))
	var sim = fixture(); data = {"elapsed":1.0,"events":sim.events,"protected_bird_advice":{"active":false}}
	before = facts(sim)
	hud.render({"mode":"flight","control_version":Profile.CONTROL_VERSION,"activeorder":sim.route,"settings":{"reduced_motion":true},"flight":data})
	hud.update_flight(data)
	check(not hud.flight_labels.events.text.contains(Receipt.BIRD_DIRECTION_COPY) and not hud.flight_labels.events.tooltip_text.contains(Receipt.BIRD_DIRECTION_COPY),"actual HUD label and tooltip both retire exact obsolete direction")
	check(hud.flight_labels.events.text.contains("未知事件保持原样"),"actual HUD preserves unknown receipt text")
	check(facts(sim) == before,"actual HUD leaves simulation and review facts untouched")
	hud.queue_free(); await process_frame

func run() -> void:
	geometry(); await presentation_lifecycle(); await receipt_lifecycle()
	print("PROTECTED_BIRD_CUE_LIFECYCLE passed=%d failed=%d total=%d" % [passed,failed,passed+failed])
	quit(1 if failed else 0)
