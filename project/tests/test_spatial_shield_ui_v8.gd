extends Node
## Exact physics snapshots projected through existing workshop/live render paths.
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Ascent=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const Rift=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Shield=preload("res://scripts/spatial_shield_v1.gd")
const HUD=preload("res://scripts/game_hud.gd")
const World=preload("res://scripts/world_view_2d.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for i in 4:await get_tree().process_frame
func piece(id:int,kind:String,x:int,y:int,param:float=1.5)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"target":2 if kind=="splitter" else -1,"input_a":-2 if kind=="splitter" else -1,"input_b":-1}
func ship()->Array:return [piece(1,"cargo",0,0,100),piece(2,"shield",1,0),piece(3,"battery",1,1,300),piece(4,"splitter",2,0,10),piece(5,"beam",3,0,32)]
func snapshot(sim)->PackedByteArray:return var_to_bytes([sim.parts,sim.bodies,sim.links,sim.telemetry,sim.route,sim.elapsed,sim.status,sim.pilot_tick])
func generation(visual:Dictionary,id:int)->Dictionary:
 for generator in visual.get("circles",[]):
  if int(generator.id)==id:return generator
 return {}
func run()->void:
 if OS.get_environment("SC_SPATIAL_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 var design:Array=ship();var route:Dictionary=Profile.route()
 for profile in [Profile,Ascent,Rift]:
  var result:Dictionary=Shield.preview_blueprint(design,profile.route(),2)
  check(result.generators.size()==1 and result.protected_ids.has(1),profile.VERSION+" real blueprint API produces local protection")
 var expected:Dictionary=Shield.preview_blueprint(design,route,2)
 check(expected.protected_ids.has(1) and not expected.protected_ids.has(5),"actual center-based gate includes nearby cargo and excludes far connected beam")
 var world=World.new();world.configure_clerk_pose_bootstrap(load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd"));add_child(world);world.set_process(false);world.set_meta("assembly_context","craft");world.focus("workshop");world.show_design(design,2)
 var hud=HUD.new();add_child(hud);hud.shield_preview_changed.connect(world.present_shield_preview)
 var data:Dictionary={"mode":"workshop","control_version":Profile.VERSION,"activeorder":route,"assembly_mode":"craft","parts":design,"selectedpart":design[1],"settings":{"reduced_motion":true},"has_accepted_contract":true}
 hud.render(data);await settle()
 var visual:Dictionary=world.shield_preview_snapshot()
 check(visual.protected_ids==expected.protected_ids and visual.centers.size()==expected.protected_ids.size(),"workshop highlights exactly the authority protected-center set")
 check(visual.circles.size()==1 and generation(visual,2).position==world.assembly_origin+Vector2(1,0)*world.CELL and is_equal_approx(generation(visual,2).radius,expected.generators[0].radius_m*world.CELL),"selected workshop circle anchors to actual cell and authority radius")
 check("可护" in hud._shield_workshop_labels.coverage.text and "按余电吸收" in hud._shield_workshop_labels.state.text and "不拦截射线" in hud._shield_workshop_labels.state.tooltip_text,"short coverage copy distinguishes eligibility from complete blocking")
 var count:int=hud._shield_blueprint_calls
 for frame in 60:await get_tree().process_frame
 hud.render(hud.state);await settle()
 check(hud._shield_blueprint_calls==count,"idle frames and unchanged render reuse blueprint without constructing a solver")
 design[1].input_a=-2;hud.sync_workshop_preview(design,design[1])
 visual=world.shield_preview_snapshot()
 check(not generation(visual,2).active and visual.protected_ids.is_empty() and visual.centers.is_empty() and "未启用" in hud._shield_workshop_labels.state.text,"actual committed input state immediately greys circle and clears protected marks")
 design[1].input_a=-1;hud.sync_workshop_preview(design,design[1])
 check(world.shield_preview_snapshot().protected_ids==expected.protected_ids and hud._shield_blueprint_calls==count+2,"re-enabling recomputes once from authoritative model")
 data.parts=design;data.selectedpart=design[0];world.show_workshop_selection(1);hud.render(data);await settle()
 check(not world.shield_preview_snapshot().visible,"changing workshop selection clears the selected shield overlay")
 data.control_version="pilot-delivery-v7";data.activeorder=preload("res://scripts/pilot_delivery_profile_v7.gd").route();data.selectedpart=design[1];hud.render(data);await settle()
 check(hud._shield_workshop_labels.is_empty() and not world.shield_preview_snapshot().visible,"old v7 contract keeps prior inspector without local coverage")
 # Exercise full existing flight presentation, not an isolated circle drawer.
 var sim=Sim.new();sim.configure(design,[],route,42);sim.release_launcher(0,0)
 world.reduced_motion=true;world.start_flight(sim,true)
 var before:PackedByteArray=snapshot(sim);world.show_flight(sim,true)
 visual=world.shield_preview_snapshot();expected=Shield.snapshot(sim)
 check(visual.protected_ids==expected.protected_ids and snapshot(sim)==before,"live show_flight consumes read-only authoritative protection set")
 check(generation(visual,2).position.distance_to(world.flight_nodes.p2.position)<1.0,"live circle matches the rendered generator position")
 var body:Dictionary=sim.body_for_part(2);body.angle=.71;body.position+=Vector2(3,-2)
 world.show_flight(sim,true);visual=world.shield_preview_snapshot()
 check(generation(visual,2).position.distance_to(world.flight_nodes.p2.position)<1.0 and visual.protected_ids==Shield.snapshot(sim).protected_ids,"real rotation and translation move coverage with actual part centers")
 sim.parts[3].energy=0.3;world.show_flight(sim,true)
 check(generation(world.shield_preview_snapshot(),2).active,"small positive energy still indicates possible partial protection")
 sim.parts[3].energy=0;world.show_flight(sim,true);visual=world.shield_preview_snapshot()
 check(not generation(visual,2).active and visual.protected_ids.is_empty() and visual.centers.is_empty(),"live energy exhaustion greys coverage and removes protected-center marks")
 sim.parts[3].energy=100;sim.parts[2].input_a=-2;world.show_flight(sim,true)
 check(not generation(world.shield_preview_snapshot(),2).active and world.shield_preview_snapshot().protected_ids.is_empty(),"live control disable refreshes without rebuilding world")
 sim.parts[2].input_a=-1
 sim._cut(1,2);sim._rebuild_bodies();world.show_flight(sim,true)
 check(not world.shield_preview_snapshot().protected_ids.has(1),"actual cargo circuit separation clears its mark even while spatially close")
 # Fresh connected body; a real split pays energy and creates a detached half.
 sim.configure(design,[],route,42);sim.release_launcher(0,0);sim._split_module(sim.parts[4],sim.parts[2],sim.body_for_part(2),1.0/120.0)
 world.show_flight(sim,true);visual=world.shield_preview_snapshot();expected=Shield.snapshot(sim)
 check(visual.circles.size()==2 and is_equal_approx(generation(visual,2).radius,expected.generators[0].radius_m*world.CELL) and is_equal_approx(generation(visual,2).radius,1.5*sqrt(.5)*world.CELL),"real split renders both half-material radii without an extra scale multiplier")
 check(visual.protected_ids==expected.protected_ids and visual.circles.any(func(g):return not g.active),"detached unpowered clone is grey and contributes no false protection")
 sim._destroy(sim.parts[2]);sim._rebuild_bodies();world.show_flight(sim,true)
 check(generation(world.shield_preview_snapshot(),2).is_empty(),"destroyed generator disappears on the next real render update")
 world.leave_flight();check(not world.shield_preview_snapshot().visible,"leaving flight clears all local shield cues")
 hud.queue_free();world.queue_free();await settle()
 print("SPATIAL_SHIELD_UI_V8 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
