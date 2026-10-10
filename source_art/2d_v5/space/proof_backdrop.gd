extends SceneTree
const Backdrop=preload("res://scripts/flight_backdrop_2d.gd")
var backdrop
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,720)
 var canvas:CanvasLayer=CanvasLayer.new();root.add_child(canvas)
 var stage:Node2D=Node2D.new();canvas.add_child(stage)
 backdrop=Backdrop.new();stage.add_child(backdrop);backdrop.configure_route({})
 var cases:Array=[
  {"name":"city","at":Vector2(10,0),"speed":Vector2(5.5,0),"progress":0.12},
  {"name":"atmosphere","at":Vector2(55,3),"speed":Vector2(5.5,0),"progress":0.4},
  {"name":"orbit_crisp","at":Vector2(115,0),"speed":Vector2.ZERO,"progress":0.8},
  {"name":"orbit_fast","at":Vector2(115,0),"speed":Vector2(8,1),"progress":0.8},
  {"name":"orbit_reverse","at":Vector2(-115,0),"speed":Vector2(-8,-1),"progress":0.8}]
 for item in cases:
  backdrop.update_flight(item.at,item.speed,item.progress)
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("/tmp/courier-backdrop-test/"+item.name+".png")
  print("Rendered ",item.name)
 # Stable-input proof: screen pixels cannot drift between frames, even though
 # the renderer is still running and the speed blur remains on.
 var first:PackedByteArray=root.get_texture().get_image().get_data()
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 var second:PackedByteArray=root.get_texture().get_image().get_data()
 print("Paused/stable render exact match: ",first==second)
 var stable:bool=first==second
 var snapshot:Dictionary=backdrop.debug_snapshot()
 root.size=Vector2i(1920,1080);stage.scale=Vector2(1.5,1.5)
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/courier-backdrop-test/orbit_resize_1920.png")
 print("Resize preserves phase: ",backdrop.debug_snapshot()==snapshot)
 quit(0 if stable and backdrop.debug_snapshot()==snapshot else 1)
