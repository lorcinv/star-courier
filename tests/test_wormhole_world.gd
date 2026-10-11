extends SceneTree
## Real renderer-owner integration. Headless state checks, not pixel approval.
const World=preload("res://scripts/world_view_2d.gd")
const Sim=preload("res://scripts/pilot_wormhole_simulation.gd")
const Profile=preload("res://scripts/pilot_wormhole_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Guide=preload("res://tools/pilot_wormhole_guidance.gd")
var passed:int=0
var failed:int=0
var tick:int=0
var axis:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for i in 4:await process_frame
func advance(sim) -> void:
 if tick%12==0:axis=Guide.guidance(sim)
 sim.set_pilot_input(axis,false,false);sim.step(1.0/60.0);tick+=1
func run() -> void:
 var vp=SubViewport.new();vp.size=Vector2i(960,540);root.add_child(vp)
 var world=World.new();vp.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 var route:Dictionary=Profile.route();route.weight=3.72
 var sim=Sim.new();sim.configure(Extreme.starter_design(),Extreme.starter_launcher(),route,42)
 world.route_distance=route.distance;world.route_radius=route.delivery_radius
 world.show_design(Extreme.starter_design());world.focus("workshop",true)
 var before:Array=sim.bodies.duplicate(true)
 world.start_flight(sim)
 check(sim.bodies==before,"v4 dispatch presentation never mutates physical state")
 var registered:bool=true
 for p in Extreme.starter_design():registered=registered and world.flight_nodes["p"+str(p.id)].position.distance_to(world.assembly_origin+Vector2(p.x,p.y)*World.CELL)<.8
 check(registered,"v4 transfer starts the same real craft at its workshop grid")
 check(world.otherworld_presentation.route_enabled() and not world.otherworld_presentation.otherworld_active(),"v4 creates cached otherworld props without changing starting biome")
 check(world.ascent_backdrop.visible and not world.flight_backdrop.visible and not world.otherworld_presentation.visible,"launch uses one original ascent background")
 check(world.flight_nodes.destination==world.otherworld_presentation.receiver_node() and not world.flight_nodes.destination.visible,"v4 replaces only its destination with the registered receiver")
 check(world.flight_nodes.receipt_label.text==route.destination_name and not world.flight_nodes.receipt_label.visible,"otherworld destination title is hidden until real transit")
 var caps:bool=true;var cap_count:int=0
 for i in sim.obstacles.size():
  var h:Dictionary=sim.obstacles[i]
  if not bool(h.get("wormhole_hardware",false)):continue
  var cap:Sprite2D=world.otherworld_presentation.hardware_node(i);cap_count+=1
  caps=caps and cap!=null and cap.global_position.distance_to(world.flight_origin+h.position*World.CELL)<.03
  caps=caps and absf(cap.global_scale.x*93.0-h.radius*World.CELL)<.03 and absf(cap.global_scale.x-cap.global_scale.y)<.001
  caps=caps and world.flight_nodes["h"+str(i)]==cap and cap.modulate==Color.WHITE
 check(caps and cap_count==4 and world.otherworld_presentation.debug_snapshot().hardware_nodes==4,"four generated side-on caps use actual physical centers/radii without duplicate rock sprites or faded hardware")
 check(world.flight_nodes.cues.portal_hardware.size()==4,"thin guard outlines disclose the exact four scalloped-cap collision circles")
 world.launch_transfer_progress=1;world.launch_age=1.35
 while sim.cargo_position().x<588.0 and sim.status=="running":advance(sim)
 world.show_flight(sim)
 check(sim.wormhole_events.is_empty() and not world.otherworld_presentation.otherworld_active(),"approaching the entrance cannot select otherworld art")
 var entry_camera:Vector2=world.smooth_center
 while sim.wormhole_events.is_empty() and sim.status=="running":advance(sim)
 check(sim.wormhole_events.size()==1 and sim.status=="running","ordinary heavy starter physically crosses once")
 before=sim.bodies.duplicate(true);var energy:float=sim.total_energy()
 world.show_flight(sim)
 var view:Dictionary=world.otherworld_presentation.debug_snapshot()
 check(sim.bodies==before and sim.total_energy()==energy,"phase synchronization has no simulation or battery side effects")
 check(view.otherworld_active and view.visible and not world.ascent_backdrop.visible and not world.flight_backdrop.visible,"actual cargo lineage switches to exactly one otherworld background")
 check(world.smooth_center==world.target_center and world.smooth_zoom==world.target_zoom and world.smooth_center.x-entry_camera.x>300*World.CELL,"camera jumps in the same frame instead of sweeping through omitted space")
 check(view.live_transitions==1 and not view.last_cut_restored and view.blur_pixels==0,"first live crossing resets background blur without an entry flash")
 check(view.transit_strength==1.0,"live crossing adds only one bounded aperture-local energy cue")
 check(world.flight_nodes.receipt_label.visible and world.flight_nodes.destination.visible,"otherworld receiver and destination title appear after cargo transit")
 var goal:Vector2=world.flight_origin+Vector2(route.distance,route.destination_y)*World.CELL
 var receiver:Sprite2D=world.flight_nodes.destination
 check((receiver.position+Vector2(167,307)*receiver.scale).distance_to(goal)<.02,"authored empty receiver mouth coincides with the real capture target")
 check(world.flight_nodes.cues.destination==goal and world.flight_nodes.cues.receiver_radius==9*World.CELL,"receipt cue retains exact saved physical geometry")
 world.focus("flight");world.show_flight(sim,true)
 check(not world.ascent_backdrop.visible and world.otherworld_presentation.visible and world.otherworld_presentation.debug_snapshot().live_transitions==1,"focus and repeated paused frames cannot restore the old sky or repeat transit")
 check(world.otherworld_presentation.debug_snapshot().blur_pixels==0,"paused render clears only background motion blur")
 var old_receiver=weakref(receiver);receiver=null
 world.leave_flight();await settle()
 check(old_receiver.get_ref()==null and world.otherworld_presentation.get_child_count()==2 and not world.otherworld_presentation.route_enabled(),"leave releases receiver/portal props while retaining the two-plane cache")
 # Main restore first configures tick zero, replays physics invisibly, then settles.
 var restored=Sim.new();restored.configure(Extreme.starter_design(),Extreme.starter_launcher(),route,42)
 world.start_flight(restored,true)
 world.settle_resumed_flight(sim)
 view=world.otherworld_presentation.debug_snapshot()
 check(view.otherworld_active and view.last_cut_restored and view.live_transitions==0,"tick-zero start followed by replay is identified as restore, not a second live transit")
 check(view.blur_pixels==0 and world.launch_age==1.35 and not world.flight_nodes.launch_burst.visible,"restored otherworld flight skips ignition and has no crossing blur")
 check(view.transit_strength==0.0,"restored transit does not replay the aperture cue")
 var physical:Array=sim.bodies.duplicate(true)
 var camera:Vector2=world.camera.position
 for i in 20:world.show_flight(sim,true)
 check(sim.bodies==physical and world.camera.position==camera and world.otherworld_presentation.debug_snapshot().live_transitions==0,"repeated restore frame stays physically and visually stationary")
 world.reduced_motion=true;world.show_flight(sim)
 check(world.otherworld_presentation.debug_snapshot().blur_pixels==0,"reduced motion keeps the correct biome with no blur")
 check(world.otherworld_presentation.debug_snapshot().transit_strength==0,"reduced motion suppresses the aperture pulse")
 while sim.status=="running":advance(sim)
 world.show_flight(sim,true)
 check(sim.status=="success" and sim.telemetry.integrity==1.0 and world.flight_nodes.receipt_label.text=="货物已签收","heavy route completes at the actual receiver without presentation-dependent success")
 check(world.otherworld_presentation.visible and world.flight_nodes.destination.visible,"receipt zoom retains the receiving world's art")
 var projected_center:Vector2=(goal-world.target_center)*world.target_zoom+World.SCENE_SIZE*.5
 var projected_radius:float=route.delivery_radius*World.CELL*world.target_zoom
 check(projected_center.y-projected_radius>100 and projected_center.y+projected_radius<World.SCENE_SIZE.y-90 and world.target_zoom<.4,"receipt composition keeps the actual capture aperture between HUD bands instead of cropping the whole dock")
 world.leave_flight();await settle()
 var count:int=world.get_child_count();var planes:int=world.otherworld_presentation.get_child_count()
 for i in 12:
  world.start_flight(restored,true);world.settle_resumed_flight(sim);world.leave_flight();await settle()
 check(world.get_child_count()==count and world.otherworld_presentation.get_child_count()==planes and world.flight_root.get_child_count()==0,"repeated start/restore/leave has bounded owner and backdrop nodes")
 check(world.ascent_backdrop.visible and not world.otherworld_presentation.visible and world.mode=="hub","return restores the shop skyline without deleting shop architecture")
 world.queue_free();vp.queue_free();await settle()
 print("Wormhole world: ",passed," passed, ",failed," failed")
 quit(1 if failed else 0)
