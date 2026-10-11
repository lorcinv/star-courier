extends SceneTree
## Full production Main/HUD/controller with a disclosed saved fixture.
## No simulation pose, energy, collider, elapsed-time or health assignment.
## Prelude is restored through Main's real persisted-timeline replay.
const Main=preload("res://scripts/main.gd")
const Fixture=preload("res://tools/meteor_integration_fixture.gd")
var app
var out="res://evidence/native"
var fixture_path=""
var mode="evasion"
var last_time=-1.0
var observations=[]
var ready=false
var captures=[]
var captured={}
var frame_count=0
var stop_time=40.5
var capture_busy=false
var drill_commands={}
var max_nodes=0
var max_fragments=0
class DrillMain:
 extends Main
 var fixture_input_axis=0
 func _pilot_input_state() -> Dictionary:
  # Explicit scripted-analog feasibility fixture, labelled in every output.
  # The ordinary controller still records/pays/steps each real command.
  if pilot_completed_ticks%12==0:fixture_input_axis=Fixture.axis_for(sim,"drill")
  return {"axis_q":fixture_input_axis,"boost":false,"active":sim.cargo_position().x>560 and sim.obstacles[8].health>0}
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):out=arg.trim_prefix("--output=")
  elif arg.begins_with("--fixture="):fixture_path=arg.trim_prefix("--fixture=")
  elif arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
 run.call_deferred()
func run():
 root.size=Vector2i(1280,720);root.title="Star Courier Meteor Integration Fixture"
 DirAccess.make_dir_recursive_absolute(out)
 if fixture_path.is_empty():printerr("Missing explicit fixture path");quit(2);return
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
 var f=FileAccess.open("user://savegame.json",FileAccess.WRITE);f.store_string(JSON.stringify(fixture,"",true,true));f.close()
 app=DrillMain.new() if mode=="drill" else Main.new();root.add_child(app)
 await process_frame;await process_frame
 if app.sim==null or app.pilot_resume_blocked:printerr("Fixture replay refused");quit(2);return
 captures=[34.9,36.0,37.3,37.85,39.0,40.3]
 if mode=="drill":captures=[42.9,43.35,43.42,43.55,43.85,44.2];stop_time=44.5
 if mode=="restore_destroyed":captures=[app.sim.elapsed,app.sim.elapsed+.2];stop_time=app.sim.elapsed+.4
 ready=true;write_observation()
 print("NATIVE_INTEGRATION_READY ",JSON.stringify({"fixture_world_seed":59,"source":fixture_path,"start_time":app.sim.elapsed,"full_main_hud":true,"mode":mode,"input":"scripted analog feasibility fixture" if mode=="drill" else "real XTest keyboard","human_fairness":false}))
func _process(_delta):
 if not ready:return false
 frame_count+=1
 if app.sim==null:return false
 if app.sim.elapsed-last_time>=.033 or app.paused:write_observation()
 var meteor=app.world.flight_nodes.get("meteor")
 if meteor!=null:
  max_nodes=maxi(max_nodes,meteor.bounded_node_count());max_fragments=maxi(max_fragments,meteor._frame.get("fragments",[]).size())
 for t in captures:
  if not captured.has(t) and app.sim.elapsed>=float(t) and not capture_busy:
   captured[t]=true;capture_busy=true;capture.call_deferred(float(t));break
 if app.sim.elapsed>=stop_time and not capture_busy:
  app._set_paused(true);write_observation()
  var f=FileAccess.open(out+"/native-summary.json",FileAccess.WRITE)
  f.store_string(JSON.stringify({"fixture_only":true,"full_main_hud":true,"mode":mode,"human_fairness":false,"max_event_nodes":max_nodes,"max_fragments":max_fragments,"frames":frame_count,"final":observations.back(),"observations":observations,"input_commands":app.pilot_timeline.snapshot()},"  ",true,true));f.close()
  print("NATIVE_INTEGRATION_DONE ",out);ready=false
 return false
func write_observation():
 var meteor=app.world.flight_nodes.get("meteor")
 var observation={"time":app.sim.elapsed,"ticks":app.pilot_completed_ticks,"paused":app.paused,"focused":app.courier_input.focused,"axis_q":app.sim.pilot_axis_q,"contacts":app.sim.telemetry.swept_contacts,"integrity":app.sim.telemetry.integrity,"remaining_energy":app.sim.total_energy(),"rock_hp":app.sim.obstacles[8].health,"cargo":[app.sim.cargo_position().x,app.sim.cargo_position().y],"event":app.sim.route.orbital_event.events[0],"generic_h8":app.world.flight_nodes.has("h8"),"hud_mode":app.hud.mode,"viewport":[root.size.x,root.size.y],"observer":meteor.observer_checkpoint() if meteor!=null else {},"warning":meteor._active_cue if meteor!=null else false,"warning_text":meteor._label.text if meteor!=null else "","fragment_count":meteor._frame.get("fragments",[]).size() if meteor!=null else 0}
 if meteor!=null:
  var r=meteor.warning_scene_rect;observation.warning_scene_rect=[r.position.x,r.position.y,r.size.x,r.size.y]
  observation.event_node_count=meteor.bounded_node_count()
 observations.append(observation);last_time=app.sim.elapsed
 var f=FileAccess.open(out+"/native-latest.tmp",FileAccess.WRITE);f.store_string(JSON.stringify(observation));f.close();DirAccess.rename_absolute(out+"/native-latest.tmp",out+"/native-latest.json")
func capture(time_value:float):
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(out+"/frame-%.2f-at-%.3f.png"%[time_value,app.sim.elapsed]);capture_busy=false
