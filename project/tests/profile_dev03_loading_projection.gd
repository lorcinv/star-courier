extends SceneTree
## Optional microbenchmark for the approved engine owner. Does not save, step
## simulation or alter presentation authority. Not a frame-rate acceptance test.
const World=preload("res://scripts/world_view_2d.gd")
const Bootstrap=preload("res://scripts/clerk_runtime_bootstrap_observed_v4.gd")
const BATCHES:int=40
const QUERIES_PER_BATCH:int=100
var sink:int=0

func _initialize() -> void:run.call_deferred()

func _measure(query:Callable) -> float:
 var start:int=Time.get_ticks_usec()
 for unused in QUERIES_PER_BATCH:
  var value:Dictionary=query.call()
  sink+=value.size()
 return float(Time.get_ticks_usec()-start)/float(QUERIES_PER_BATCH)

func _summary(values:Array[float]) -> Dictionary:
 values.sort()
 return {"unit":"microseconds_per_query","batches":values.size(),"queries_per_batch":QUERIES_PER_BATCH,
  "p50":values[int(values.size()*.50)],"p95":values[int(values.size()*.95)],"max":values[-1]}

func run() -> void:
 var world=World.new()
 if not world.configure_clerk_pose_bootstrap(Bootstrap):
  push_error("clerk bootstrap configuration rejected");world.free();quit(2);return
 root.add_child(world);world.set_process(false)
 if world.assembly_feedback!=null:world.assembly_feedback.set_process(false)
 await process_frame
 if not world._clerk_pose_setup_error.is_empty() or not world._clerk_pose_consumer_enabled:
  push_error("real imported clerk bootstrap unavailable: "+world._clerk_pose_setup_error)
  world.queue_free();await process_frame;quit(2);return
 var full:Dictionary=world.loading_snapshot()
 var small:Dictionary=world.loading_ui_state()
 for key in small:
  if small[key]!=full[key]:
   push_error("loading projection mismatch: "+str(key));world.queue_free();await process_frame;quit(1);return
 var old_query:Callable=world.loading_snapshot
 var new_query:Callable=world.loading_ui_state
 for unused in 5:_measure(old_query);_measure(new_query)
 var old_times:Array[float]=[];var new_times:Array[float]=[]
 # Alternate order to reduce the effect of a warm-cache/order bias.
 for batch in BATCHES:
  if batch%2==0:old_times.append(_measure(old_query));new_times.append(_measure(new_query))
  else:new_times.append(_measure(new_query));old_times.append(_measure(old_query))
 print("DEV03_LOADING_PROJECTION_PROFILE ",JSON.stringify({"scope":"idle real coupled-world query microbenchmark only","display":DisplayServer.get_name(),
  "engine":Engine.get_version_info(),"full_diagnostics":_summary(old_times),"overlay_scalars":_summary(new_times),
  "windows_fps_acceptance":false,"native_visual_acceptance":false,"sink":sink}))
 world.queue_free();await process_frame;quit(0)
