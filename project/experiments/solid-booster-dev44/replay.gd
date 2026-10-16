extends SceneTree
const S=preload("res://scripts/pilot_delivery_ascent_simulation_v8.gd")
const T=preload("res://scripts/pilot_free_timeline_v2.gd")
const C=preload("res://scripts/delivery_chapter_v3.gd")
func _initialize():
 var f=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SC_NATIVE_SAVE")))
 var snap=f.in_flight;var timeline=T.new();assert(timeline.restore(snap.input_commands,int(snap.ticks)))
 var s=S.new();s.configure(snap.design,snap.launcher,snap.route,int(snap.seed));s.release_launcher(snap.launch_settings.angle_degrees,snap.launch_settings.power_fraction)
 for tick in range(int(snap.ticks)):
  var cmd=timeline.state_at(tick);s.set_free_flight_input(cmd.axis_x_q,cmd.axis_q,cmd.boost,cmd.active,cmd.device_id,cmd.brake);s.step(1.0/60)
 var p=s.parts[1026];var b=s.body_for_part(1)
 print("REPLAY ",JSON.stringify({"ticks":snap.ticks,"elapsed":s.elapsed,"fuel":p.solid_fuel_fraction,"lit":p.solid_lit,"mass":b.mass,"position":[s.cargo_position().x,s.cargo_position().y],"velocity":[b.velocity.x,b.velocity.y],"ammo_raw":s.telemetry.ammo_cost,"ammo_quote":C.quote(snap.route,s.telemetry,false).ammo,"energy":s.telemetry.energy_used}))
 quit()
