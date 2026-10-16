extends SceneTree
## Headless presentation/data checks, not native input or GPU image approval.
const Framing=preload("res://scripts/moon_framing_2d.gd")
const Moon=preload("res://scripts/moon_presentation_2d.gd")
const Profile=preload("res://scripts/pilot_moon_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const World=preload("res://scripts/world_view_2d.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Guide=preload("res://tools/moon_offline_guide.gd")
var passed=0
var failures:Array=[]
var result:Dictionary={"proof":"headless presentation contracts only","flights":[]}
var output=""
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failures.append(label);push_error("FAIL "+label)
func state(sim) -> PackedByteArray:
 return var_to_bytes({"parts":sim.parts,"bodies":sim.bodies,"obstacles":sim.obstacles,"telemetry":sim.telemetry,"events":sim.events,"route":sim.route})
func settle() -> void:
 for i in 3:await process_frame
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 var route=Profile.route({"id":4,"weight":2.8,"reward":410,"required":85.0,"rep":10})
 check(Moon.accepts_route(route),"complete saved Moon marker/registration accepted")
 check(Moon.accepts_route(JSON.parse_string(JSON.stringify(route))),"JSON-restored saved marker and source geometry accepted")
 var renamed=route.duplicate(true);renamed.name="任意名称";renamed.destination_name="Changed display label"
 check(Moon.accepts_route(renamed),"localized display names do not choose the biome")
 for key in ["route_profile","route_kind","destination_id","control_version","moon_schema","moon_receiver"]:
  var bad=route.duplicate(true);bad.erase(key);check(not Moon.accepts_route(bad),"missing explicit field rejected: "+key)
 for patch in [{"name":"月球","destination_name":"月面收件舱"},{"route_profile":"moon-surface-v1"}]:
  var old=Extreme.route();old.merge(patch,true);check(not Moon.accepts_route(old),"legacy v3 cannot opt into Moon via title or partial metadata")
 for value in [NAN,INF,-1.0,0.0,"9",null]:
  var bad=route.duplicate(true);bad.delivery_radius=value;check(not Moon.accepts_route(bad),"invalid capture radius rejected: "+str(value))
 var vp=SubViewport.new();vp.size=Vector2i(1280,720);root.add_child(vp)
 var parent=Node2D.new();vp.add_child(parent)
 var view=Moon.new();vp.add_child(view)
 var sim=Sim.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),route,42)
 var initial=state(sim)
 check(view.configure_route(route,parent,Vector2(100,200),72,sim.obstacles),"valid isolated configure")
 check(state(sim)==initial,"configure leaves complete physical/economic route bytes unchanged")
 check(view.debug_snapshot().planes==2 and view.debug_snapshot().props==2 and view.debug_snapshot().registered_hardware==14,"two cached raster planes and one airlock plus bounded cue owner")
 check(not view.show_hardware_audit and not view._cue.audit,"hardware-circle debug overlays default off")
 var receiver=view.receiver_node()
 check((receiver.position+Vector2(244,392)*receiver.scale).distance_to(Vector2(100,200)+Vector2(900,-125)*72)<.001,"exact capture mouth registration")
 var foot_world=(receiver.position+Vector2(217,628)*receiver.scale-Vector2(100,200))/72
 check(absf(foot_world.y-float(route.moon_surface_y))<.001,"source lowest foot exactly matches saved local surface")
 var hardware_count=0
 for i in sim.obstacles.size():
  if view.suppresses_hazard(i):hardware_count+=1;check(str(sim.obstacles[i].moon_role)=="airlock","only source-registered airlock circle suppressed")
 check(hardware_count==14,"fourteen exact hardware IDs suppressed; all crags and ore retained")
 for x in [0.0,559.0,560.0,590.0,630.0,700.0,590.0,0.0]:
  view.update_view(Vector2(x,-150),Vector2(20,0),Vector2(x+40,-130),.1)
  var snap=view.debug_snapshot();var expected=smoothstep(560,630,x)
  check(is_equal_approx(snap.moon_weight,expected),"actual reversible cargo progress controls phase at "+str(x))
 check(view.get_child_count()==2,"phase crossing allocates no extra plane or material")
 view.update_view(Vector2(700,-150),Vector2(24,0),Vector2(740,-130),.1)
 view.update_view(Vector2(701,-150),Vector2(24,0),Vector2(741,-130),.1)
 check(view.debug_snapshot().blur>0,"actual camera motion enables bounded background blur")
 check(view.receiver_node().material==null and view._cue.material==null,"blur material never touches receiver, cargo, hardware or HUD")
 view.reduced_motion=true;view.update_view(Vector2(702,-150),Vector2(24,0),Vector2(742,-130),.1)
 check(view.debug_snapshot().blur==0,"reduced motion clears blur")
 view.reduced_motion=false;view.motion_blur_enabled=false;view.update_view(Vector2(703,-150),Vector2(24,0),Vector2(743,-130),.1)
 check(view.debug_snapshot().blur==0,"blur toggle off clears blur")
 view.motion_blur_enabled=true
 var freeze=view.debug_snapshot();view.update_view(Vector2(800,-140),Vector2(24,0),Vector2(845,-125),.1,true)
 check(view.debug_snapshot().position==freeze.position and view.debug_snapshot().camera==freeze.camera and view.debug_snapshot().blur==0,"paused established sample freezes scenery and clears blur")
 view.update_view(Vector2(704,-150),Vector2.ZERO,Vector2(744,-130),.1)
 check(view.debug_snapshot().blur==0,"stationary cargo has no blur")
 for x in [-1.0e18,-800,0,1.0e18]:
  view.update_view(Vector2(700,-150),Vector2.ZERO,Vector2(x,-130),.1)
  var snap=view.debug_snapshot()
  check(snap.far_scroll.x>=-86 and snap.far_scroll.x<=-70 and snap.terrain_scroll.x>=0 and snap.terrain_scroll.x<1280,"bounded clamped sky and ordinary terrain offset: "+str(x))
 check(Moon.wrapped_offset(10,2.4)==Moon.wrapped_offset(10+1280.0/2.4,2.4),"same-orientation ordinary wrap period")
 var bad_hazards=sim.obstacles.duplicate(true);bad_hazards[14].position+=Vector2(1,0)
 view.update_hardware(bad_hazards);check(not view.suppresses_hazard(14),"moved hardware cannot be hidden by stale source registration")
 var old_velocity:Vector2=sim.bodies[0].velocity
 sim.bodies[0].velocity=Vector2(60,0)
 var fast=view.camera_target(sim)
 sim.bodies[0].velocity=old_velocity
 check(fast.forward_m==210.0,"actual high speed expands forward preview to 3.5 seconds without a speed cap")
 var unknown=sim.obstacles.duplicate(true);unknown[14].id="unregistered-hardware"
 view.configure_route(route,parent,Vector2.ZERO,72,unknown)
 check(not view.suppresses_hazard(14),"unknown hardware ID remains a real ordinary hazard sprite")
 check(not view.suppresses_hazard(10) and not view.suppresses_hazard(13),"both actual optional ore nodes keep their renderer and health semantics")
 view.set_scene_visible(false);check(not view.visible and not view.receiver_node().get_parent().visible,"scene hide covers background and world prop")
 view.set_scene_visible(true)
 check(state(sim)==initial,"all helper operations preserve actual sim bytes")
 receiver=view.receiver_node()
 var old_receiver=weakref(receiver);receiver=null
 view.leave_flight();check(old_receiver.get_ref()==null and parent.get_child_count()==0,"leave immediately releases independent world owner")
 for i in 10:
  view.configure_route(route,parent,Vector2.ZERO,72,sim.obstacles);view.update_view(Vector2(740,-148),Vector2.ZERO,Vector2(790,-120),.1,true);view.leave_flight()
 check(parent.get_child_count()==0 and view.get_child_count()==2,"ten restart/leave cycles retain bounded two-plane cache")
 view.queue_free();parent.queue_free();vp.queue_free();await settle()
 # Actual unmodified-flight fixtures drive the patched production world/HUD.
 for weight in [2.8,4.34]:await test_flight(weight)
 result.passed=passed;result.failures=failures
 if not output.is_empty():
  var f=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
 print("Moon presentation: ",passed," passed, ",failures.size()," failed")
 quit(1 if not failures.is_empty() else 0)

func test_flight(weight:float) -> void:
 var route=Profile.route({"id":4,"weight":weight,"reward":465 if weight>3 else 410,"required":85.0,"rep":10})
 if weight>3:route.deadline=67.0
 var sim=Sim.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),route,42)
 var vp=SubViewport.new();vp.size=Vector2i(1280,720);root.add_child(vp)
 var world=World.new();vp.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 var hud=HUD.new();vp.add_child(hud);hud.render({"mode":"flight","control_version":"pilot-v3","activeorder":route,"flight":sim.telemetry,"settings":{"reduced_motion":true}})
 world.route_distance=route.distance;world.route_radius=route.delivery_radius;world.start_flight(sim)
 check(world.ascent_backdrop.visible and not world.moon_presentation.visible,"real original departure sky for payload "+str(weight))
 world.launch_age=2;world.launch_transfer_progress=1
 var axis=0;var tick=0;var releases=[false,false];var sample_count=0;var all_bounds=true;var all_non_mutating=true
 var restore_checked=false
 while sim.status=="running" and tick<6000:
  if tick%12==0:axis=Guide.command_axis(sim)
  sim.set_pilot_input(axis,false,false);sim.step(1.0/60.0);tick+=1
  if not releases[0] and sim.cargo_position().x>=210:releases[0]=true;axis=0
  if not releases[1] and sim.cargo_position().x>=730:releases[1]=true;axis=0
  if tick%60==0 or sim.status!="running":
   var before=state(sim);world.show_flight(sim,true);world.smooth_center=world.target_center;world.smooth_zoom=world.target_zoom;world._update_camera()
   all_non_mutating=all_non_mutating and state(sim)==before
   if sim.status=="running":
    var frame=world.moon_presentation.debug_snapshot().frame
    var craft:Rect2=Framing.craft_bounds(sim,world.flight_origin,72)
    var projected:Rect2=Rect2((craft.position-world.smooth_center)*world.smooth_zoom+Vector2(640,360),craft.size*world.smooth_zoom)
    all_bounds=all_bounds and frame.craft_safe.grow(.1).encloses(projected)
    all_bounds=all_bounds and (world.smooth_zoom>=.24-.0001 if frame.phase=="lunar" else world.smooth_zoom>=Framing.MIN_ASCENT_ZOOM-.0001) and world.moon_presentation.debug_snapshot().framing_visibility.cues.size()<=6
   sample_count+=1
  if not restore_checked and sim.cargo_position().x>=740:
   world.start_flight(sim,true);world.settle_resumed_flight(sim)
   check(world.moon_presentation.moon_weight()==1 and not world.flight_nodes.launch_burst.visible and world.launch_age==1.35,"mid-Moon restore derives phase with no ignition replay "+str(weight))
   check(world.moon_presentation.debug_snapshot().blur==0,"first resumed frame no blur "+str(weight))
   restore_checked=true
 check(all_bounds,"readable actual cargo body inside HUD-safe view with bounded explicit edge cues at "+str(sample_count)+" sampled frames, payload "+str(weight))
 check(all_non_mutating,"render preserves every sampled full physics/route byte, payload "+str(weight))
 check(sim.status=="success" and float(sim.telemetry.integrity)==1,"unchanged guided v3 flight physically captures intact, payload "+str(weight))
 world.show_flight(sim,true)
 var goal=world.flight_origin+Vector2(route.distance,route.destination_y)*72
 var p=(goal-world.target_center)*world.target_zoom+Vector2(640,360);var radius=9*72*world.target_zoom
 check(world.target_zoom>=.24-.0001 and world.target_zoom<=.30+.0001 and p.y-radius>100 and p.y+radius<660,"interior receipt keeps actual capture aperture and readable body between HUD bands")
 var data=sim.telemetry.duplicate(true);data.merge({"elapsed":sim.elapsed,"distance":sim.cargo_position().x,"total_distance":route.distance,"paused":false,"events":sim.events},true);hud.update_flight(data)
 check(hud.flight_labels.gate.text=="货物已签收" and hud.flight_labels.gate_detail.text==route.destination_name,"live delivered telemetry confirms named Moon receipt")
 check(not hud.flight_labels.events.text.contains("自动整备") and not hud.flight_labels.events.text.contains("个模块，质量") and not hud.flight_labels.events.text.contains("压缩供能"),"source startup/recovery bookkeeping is absent from finished-flight receipt")
 check(hud.flight_labels.altitude.text.contains("126.4"),"Moon cue reports saved straight-entry height rather than stale 150m cruise target")
 result.flights.append({"weight":weight,"elapsed":sim.elapsed,"status":sim.status,"reserve_j":sim.total_energy(),"position":str(sim.cargo_position()),"samples":sample_count,"input_ticks":tick,"launch_energy_j":sim.telemetry.get("launch_energy"),"initial_energy_j":6000.0})
 world.leave_flight();world.queue_free();hud.queue_free();vp.queue_free();await settle()
