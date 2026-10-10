extends SceneTree
## Scripted rendered proof using the live controller; not native-input QA.
const Assembly=preload("res://scripts/assembly_2d.gd")
var game
var robot
func _initialize() -> void:run.call_deferred()
func capture(label:String) -> void:
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://source_art/2d_v5/robot/runtime-"+label+".png")
 print("ROBOT_RUNTIME_PROOF ",label," ",robot.debug_snapshot())
func advance(seconds:float) -> void:
 for i in range(ceili(seconds*120)):robot._process(1.0/120.0)
func run() -> void:
 root.size=Vector2i(1280,720)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.settings.quality="standard";game._apply_quality();game.view_container.set_canvas_size(Vector2i(640,360))
 for child in game.world.get_children():
  if child.get_script()==Assembly:robot=child
 if robot==null:
  robot=Assembly.new();game.world.add_child(robot);robot.configure(game.world.assembly_origin,72);robot.bind_part_root(game.world.ship_root)
 robot.set_process(false)
 await create_timer(1.0).timeout;await capture("01-hub")
 game._action("accept_contract","D1-A");robot.on_order_changed("D1-A","accepted");advance(.9)
 await capture("02-courier")
 game.navigate("workshop");game.selected_id=3;game.render()
 await create_timer(1.4).timeout
 game.rotate_part()
 if robot.debug_snapshot().actions==0:robot.on_committed_edit("rotate",game.selected_part())
 advance(.08)
 await capture("03-align")
 advance(.115);await capture("04-latch")
 advance(.7);await capture("05-assist")
 game.hud.palette_open=false;game.render();await capture("06-assist-drawer-collapsed")
 await game._quit_cleanly()
