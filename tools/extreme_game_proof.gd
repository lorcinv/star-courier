extends SceneTree
## SCRIPTED composition proof, not keyboard acceptance or route success.
## Runs the real main/controller, v3 physics, raster stage and HUD. Uses isolated
## XDG state. Open-route/contact fixtures are disclosed in each JSON record.
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Probe=preload("res://tools/extreme_build_probe.gd")
var game
var output_dir:String="v5/extreme-presentation"
var manifest:Array=[]
func _initialize() -> void:run.call_deferred()
func settle() -> void:
 game._process(0)
 await create_timer(.7).timeout
func begin_fixture(design:Array,route:Dictionary) -> void:
 game._configure_flight(true,design,[],route)
 game.paused=true;game.launch_age=2;game.launch_sfx_played=true
 game.world.reduced_motion=false
func capture(label:String,detail:Dictionary={}) -> void:
 await settle()
 await RenderingServer.frame_post_draw
 var prefix:String=output_dir+"/"+str(game.view.size.x)+"-"+label
 await game._capture(prefix)
 var record:Dictionary={"image":prefix+".png","scripted":true,"native_keyboard":false,"window":str(root.size),"native_raster":str(game.view.size),"pixel_scale":game.view_container.pixel_scale,"control_version":game.sim.route.control_version,"elapsed":game.sim.elapsed,"camera_zoom":game.world.smooth_zoom,"telemetry":game.sim.telemetry.duplicate(true),"thrust_caption":game.hud.flight_labels.thrust.text}
 record.merge(detail);manifest.append(record);print("EXTREME_FRAME ",JSON.stringify(record))
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output_dir=arg.trim_prefix("--output=")
 if DisplayServer.get_name()=="headless":printerr("Graphical proof requires an actual rendering display.");quit(1);return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/"+output_dir))
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.settings.pixel_density="auto";game.settings.motion_blur=false;game.settings.reduced_motion=false;game._apply_quality()
 game.set_process(false)
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;await create_timer(.3).timeout
  begin_fixture(Profile.reinforced_design(),Profile.route());game.launch_age=.4
  await capture("01-eight-engine-charge",{"fixture":"real reinforced build at rest on production ascent route; paused charge"})
  begin_fixture(Profile.reinforced_design(),Probe.open_route())
  game.sim.set_pilot_input(0,true,false)
  for i in 144:game.sim.step(1.0/120.0)
  await capture("02-eight-engine-full-power",{"fixture":"open zero-drag comparison from rest;1.2s paid full power; no launch impulse"})
  var drill_design:Array=[Profile.part(1,"cargo",0),Profile.part(2,"battery",-1),Profile.part(3,"drill",1,0,{"input_a":-2})]
  begin_fixture(drill_design,Probe.open_route())
  game.sim.obstacles.append({"position":game.sim.part_world_position(3)+Vector2(1.255,0),"radius":.8,"health":80.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO})
  game.sim.set_pilot_input(0,false,true);game.sim.step(1.0/120.0)
  await capture("03-paid-drill-contact",{"fixture":"stationary true forward contact; one1/120s paid cutting step"})
  # Keep the renderer's registered drill anchor inspectable in a clearly
  # disclosed detail frame. Only the camera changes, never a physics pose.
  game._process(0);game.world.set_process(false)
  game.world.smooth_center=game.world.flight_origin+game.sim.cargo_position()*72+Vector2(100,0);game.world.smooth_zoom=1.25;game.world._update_camera()
  await RenderingServer.frame_post_draw
  await game._capture(output_dir+"/"+str(game.view.size.x)+"-04-drill-camera-detail")
  manifest.append({"image":output_dir+"/"+str(game.view.size.x)+"-04-drill-camera-detail.png","scripted":true,"native_keyboard":false,"camera_detail_only":true,"native_raster":str(game.view.size),"simulation_unchanged":true})
  game.world.set_process(true)
  # A real engine accelerates into a rock; the cue comes from a funded impact,
  # not from assigning damage/counters or from attaching a fake shield bubble.
  var shield_design:Array=Profile.starter_design();shield_design.append(Profile.part(9,"shield",-1,-1))
  begin_fixture(shield_design,Probe.open_route())
  game.sim.obstacles.append({"position":Vector2(8,0),"radius":.8,"health":800.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO})
  for i in 480:
   game.sim.set_pilot_input(0,false,false);game.sim.step(1.0/120.0)
   if game.sim.telemetry.impact_absorbed>0 or game.sim.status!="running":break
  await capture("05-funded-shield-impact",{"fixture":"actual powered acceleration from rest into800HP rock; stop on first funded shield absorption"})
  if game.sim.telemetry.impact_absorbed<=0:printerr("Shield fixture failed to reach paid impact.");quit(1);return
 var file:=FileAccess.open("res://docs/qa/"+output_dir+"/manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify({"evidence_kind":"scripted paused composition, not native-input QA","frames":manifest},"  "));file.close()
 print("EXTREME_GAME_PROOF_COMPLETE frames=",manifest.size())
 await game._quit_cleanly()
