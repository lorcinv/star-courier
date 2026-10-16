extends SceneTree
## Actual Main guard/World integration with a synthetic visual position fixture.
## No saved profile, trade, timeline command, gameplay success or native-GUI claim.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Receipt=preload("res://scripts/mosslight_receipt_v2.gd")
const Simulation=preload("res://scripts/pilot_free_simulation_v2.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Main=preload("res://scripts/main.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:call_deferred("_run")
func snapshot(sim) -> PackedByteArray:
 return var_to_bytes([sim.route,sim.parts,sim.bodies,sim.obstacles,sim.telemetry,sim.elapsed,sim.status])
func _run() -> void:
 var route:Dictionary=Profile.route(Content.fresh_catalog())
 if route.is_empty() or not Receipt.route_error(route).is_empty():
  check(false,"registered mosslight content and art required for integration fixture");quit(1);return
 var gate=Main.new()
 check(gate._recovery_route_error(route).is_empty(),"Main accepts fully registered ordinary mosslight route")
 var invalid:Dictionary=route.duplicate(true);invalid.mosslight_schema="future-v99"
 check(not gate._recovery_route_error(invalid).is_empty(),"Main rejects new malformed identity before generic free return")
 gate.free()
 # Main normally parents World under a 1280x720 SubViewport. A standalone
 # --headless SceneTree root may only be 64x64; its HUD-safe area collapses
 # to one pixel and makes the inherited free camera zoom approximately zero.
 # Reproduce the real supported viewport contract rather than that tiny root.
 var view:SubViewport=SubViewport.new();view.size=Vector2i(1280,720)
 view.render_target_update_mode=SubViewport.UPDATE_DISABLED;root.add_child(view)
 var world=World.new();world.catalog=Parts.catalog();view.add_child(world);world.set_process(false)
 print("MOSSLIGHT_VIEWPORT_FIXTURE root=",root.size," world=",world.get_viewport_rect().size)
 check(world.get_viewport_rect().size==Vector2(1280,720),"fixture uses the real Main logical viewport extent")
 var sim=Simulation.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),route,27)
 check(sim.free_route_error.is_empty(),"unmodified free-v2 solver accepts exact ordinary route")
 # This is deliberately a presentation fixture, not an assertion that these
 # coordinates were reached by flight or earned any settlement.
 var body:Dictionary=sim.body_for_part(1)
 body.position+=Vector2(180,-18)-sim.cargo_position()
 var before:PackedByteArray=snapshot(sim)
 world.start_flight(sim,true);world.settle_resumed_flight(sim)
 var presenter=world.mosslight_presentation
 check(world.mode=="flight" and presenter.route_enabled(),"World enables independent mosslight presenter")
 check(world.camera.zoom.is_finite() and world.camera.zoom.x>.01 and world.smooth_zoom>.01,"restored camera has finite nonzero supported-size zoom")
 check(world.otherworld_presentation==null and world.moon_presentation==null and not world.lunar_presentation.route_enabled(),"new ordinary environment does not instantiate old special presenters")
 check(world.flight_nodes.destination==presenter.receiver_node(),"free framing receives the exact registered greenhouse sprite")
 check(not world.flight_nodes.receipt_label.visible and world.flight_nodes.cues.get_meta("suppress_capture"),"generic receipt label and duplicate capture ring are suppressed")
 check(world.launch_age==1.35 and not world.flight_nodes.launch_burst.visible,"restored flight does not replay ignition")
 check(presenter.debug_snapshot().sample_camera.is_equal_approx((world.camera.position-world.flight_origin)/72.0),"restored backdrop samples the settled camera rather than old shop camera")
 check(not world.flight_nodes.has("h0") and not world.flight_nodes.has("h1") and not world.flight_nodes.has("h2"),"generic obstacle art is not duplicated under registered physical rocks")
 world.show_flight(sim,true)
 var center:Vector2=world.smooth_center;var zoom:float=world.smooth_zoom
 var sample:Vector2=presenter.debug_snapshot().sample_camera
 for tick in range(20):world._process(1.0/30.0);world.show_flight(sim,true)
 check(world.smooth_center==center and world.smooth_zoom==zoom,"paused new environment has no camera easing drift")
 check(presenter.debug_snapshot().sample_camera==sample,"paused new environment has no backdrop phase drift")
 check(snapshot(sim)==before,"World presentation never changes authoritative simulation state")
 var field_children:int=presenter._props.get_child_count()
 for cycle in range(3):
  world.start_flight(sim,true);world.settle_resumed_flight(sim)
  check(presenter.get_child_count()==2 and presenter._props.get_child_count()==field_children,"repeated restore retains bounded field: "+str(cycle))
  check(not world.flight_nodes.launch_burst.visible,"restore remains non-replaying: "+str(cycle))
 world.focus("workshop",true)
 check(not presenter.visible and not presenter._props.visible,"temporary focus away hides both environment and registered world props")
 world.focus("flight",true);world.show_flight(sim,true)
 check(presenter.visible and presenter._props.visible,"returning focus reuses the existing environment")
 world.leave_flight()
 check(not presenter.route_enabled() and presenter.get_child_count()==0 and world.flight_root.get_child_count()==0,"leaving flight releases new art and registered world props")
 var ordinary:Dictionary=Profile.route({"id":0,"name":"fixture","distance":90.0,"destination_y":0.0,"delivery_radius":7.0,"max_delivery_speed":24.0,"hazards":[],"gravity":0.0,"wind":[0.0,0.0]})
 # The immutable production ground catalog has richer fields; the broad free
 # source route here is sufficient to prove that this presenter stays disabled.
 if not ordinary.is_empty():
  var other=Simulation.new();other.configure(Profile.starter_design(),Profile.starter_launcher(),ordinary,28)
  world.start_flight(other,true);world.settle_resumed_flight(other)
  check(not presenter.route_enabled(),"following ordinary route has no leaked mosslight presentation")
  world.leave_flight()
 else:check(false,"ordinary free fixture authors before cross-route isolation check")
 world.free();view.free()
 print("MOSSLIGHT_WORLD_LIFECYCLE_V2_TESTS passed=",passed," failed=",failed," native_gui=NOT_RUN")
 quit(1 if failed else 0)
