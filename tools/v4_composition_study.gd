extends SceneTree
## Live geometry/light composition study. Does not alter gameplay or saved art.
var game
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(1920,1080)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.settings.quality="standard";game._apply_quality();game.view_container.set_canvas_size(Vector2i(960,540))
 await create_timer(2).timeout
 game.set_process(false);game.world.set_process(false)
 var world=game.world
 var bay:=SpotLight3D.new();bay.name="CompositionBayDaylight";bay.position=Vector3(8,7,3.6)
 bay.light_color=Color("ffe0a2");bay.light_energy=.3;bay.spot_range=20;bay.spot_angle=48;bay.spot_attenuation=.55;bay.spot_angle_attenuation=.75
 bay.shadow_enabled=true;bay.shadow_bias=.15;bay.shadow_normal_bias=1.2;bay.shadow_blur=0.0
 world.add_child(bay);bay.look_at(Vector3(-1,0,-.8),Vector3.UP)
 world.sun.rotation_degrees=Vector3(-42,60,0)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/qa/v4/composition"))
 for choice in [["sun-only",12.6,Vector3(0,2.15,0),6.0,0.0],["bay-soft",12.6,Vector3(0,2.15,0),6.0,.22],["bay-warm",12.6,Vector3(0,2.15,0),6.0,.4]]:
  bay.light_energy=float(choice[4])
  world.camera_size=float(choice[1]);world.camera_target=choice[2];world.desired_camera=world.camera_target+Vector3(0,float(choice[3]),28)
  world.smooth_camera_size=world.camera_size;world.smooth_camera_position=world.desired_camera;world.smooth_camera_look=world.camera_target;world._process(0)
  await process_frame;await RenderingServer.frame_post_draw
  await game._capture("v4/composition/"+str(choice[0]))
 print("V4_COMPOSITION_STUDY_COMPLETE")
 await game._quit_cleanly()
