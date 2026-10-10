extends SceneTree
## Actual rendered composition snapshots with scripted controller time.
## Not native keyboard acceptance; no settled rewards are written.
var game
var output:String="v5/grounded-launch-study"
func _initialize() -> void:run.call_deferred()
func capture(label:String) -> void:
 await create_timer(.20).timeout
 await RenderingServer.frame_post_draw
 await game._capture(output+"/"+label)
 print("GROUNDED_FRAME ",label," age=",game.launch_age," transfer=",game.launch_transfer_remaining," physics=",game.sim.elapsed if game.sim!=null else -1)
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 game.settings.pixel_density="auto";game.settings.reduced_motion=false;game._apply_quality()
 root.size=Vector2i(1920,1080);await create_timer(.2).timeout
 game.world.focus("hub",true);await capture("01-shop")
 game.navigate("workshop");game.world.focus("workshop",true);await capture("02-assembled")
 game._configure_flight(true,game.design,game.launcher,game.ExtremeProfile.route())
 await capture("03-same-craft-at-transfer-start")
 game._process(.31);await capture("04-mid-transfer")
 game._process(.31);await capture("05-rest-on-pad")
 game._process(.4);await capture("06-grounded-charge")
 game._process(.35);await capture("07-grounded-ignition")
 for i in 45:game._process(1.0/60.0)
 await capture("08-leaving-shop")
 for i in 120:game._process(1.0/60.0)
 await capture("09-continuous-ascent")
 print("GROUNDED_STUDY_COMPLETE")
 await game._quit_cleanly()
