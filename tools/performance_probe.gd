extends SceneTree
## Bounded rendered-engine benchmark. Not video-frame-rate evidence.
## Run on an isolated Xorg display with a fresh XDG_DATA_HOME; never user saves.
const Parts = preload("res://scripts/parts.gd")
const Sim = preload("res://scripts/simulation.gd")
var scene
var output: Dictionary = {"samples": [], "cycle_snapshots": [], "stress": {}, "failures": []}
var output_path = "res://docs/qa/performance-runtime.json"

func _initialize() -> void:
 run.call_deferred()

func save_result() -> void:
 var file = FileAccess.open(output_path, FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(output, "  "))

func snapshot(label: String) -> Dictionary:
 var dead_refs = 0
 for ref in scene.world.materials:
  if ref.get_ref() == null: dead_refs += 1
 var rss_kib = -1
 var rss_output: Array = []
 if OS.execute("/usr/bin/awk", ["/^VmRSS:/ {print $2}", "/proc/%d/status" % OS.get_process_id()], rss_output) == 0 and not rss_output.is_empty():
  rss_kib = int(str(rss_output[0]).strip_edges())
 return {"label":label, "render_view_size":str(scene.view.size), "msaa_enum":scene.view.msaa_3d, "render_3d_scale":scene.view.scaling_3d_scale, "quality_profile":scene.get("quality_profile"), "nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)), "resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), "orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)), "rss_kib":rss_kib, "material_refs":scene.world.materials.size(), "dead_material_refs":dead_refs, "model_cache_entries":scene.world.cache.size(), "flight_nodes":scene.world.flight_nodes.size(), "fx_nodes":scene.world.fx_root.get_child_count(), "visible_effects":scene.world.visible_effect_count, "visible_rings":scene.world.visible_ring_count, "hud_tweens":scene.hud._motion_tweens.size(), "trails":scene.world.trails.size()}

func frames(count: int) -> void:
 for i in range(count): await process_frame

func warm(seconds: float) -> void:
 var until = Time.get_ticks_usec() + int(seconds * 1000000)
 while Time.get_ticks_usec() < until: await process_frame

func sample(label: String, seconds: float = 3.0, warm_seconds: float = 2.0) -> void:
 await warm(warm_seconds)
 var values: Array = []
 var process_ms: Array = []
 var draws: Array = []
 var engine_fps: Array = []
 var before = Time.get_ticks_usec()
 var previous = before
 while Time.get_ticks_usec() - before < int(seconds * 1000000):
  await process_frame
  var now = Time.get_ticks_usec()
  values.append(float(now - previous) / 1000.0)
  process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
  draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
  engine_fps.append(float(Performance.get_monitor(Performance.TIME_FPS)))
  previous = now
 var duration = float(previous - before) / 1000000.0
 values.sort(); process_ms.sort(); draws.sort(); engine_fps.sort()
 var record = snapshot(label)
 record.merge({"sample_seconds":duration, "frames":values.size(), "actual_mean_fps":float(values.size()) / duration, "frame_ms_p50":percentile(values, .50), "frame_ms_p95":percentile(values, .95), "frame_ms_p99":percentile(values,.99), "frame_ms_max":values.back(), "process_ms_p50":percentile(process_ms,.50), "process_ms_p95":percentile(process_ms,.95), "draw_calls_p50":percentile(draws,.50), "engine_fps_p50":percentile(engine_fps,.50), "page":scene.page})
 if scene.sim != null:
  record.sim_parts=scene.sim.parts.size();record.sim_bodies=scene.sim.bodies.size();record.sim_effects=scene.sim.effects.size();record.sim_elapsed=scene.sim.elapsed;record.sim_status=scene.sim.status
 output.samples.append(record);save_result();print("PERF_SAMPLE ",JSON.stringify(record))

func percentile(values: Array, p: float) -> float:
 return float(values[clampi(int(ceil(values.size() * p)) - 1, 0, values.size() - 1)])

func p(id: int, type: String, x: int, y: int) -> Dictionary:
 return {"id":id,"type":type,"x":x,"y":y,"rot":0,"param":Parts.defaults(type),"input_a":-1,"input_b":-1,"target":-1}

func maximum_craft() -> Array:
 var craft: Array = []
 var names = Parts.catalog().keys()
 var id = 1
 for y in range(-2,3):
  for x in range(-4,5):
   var type = "cargo" if x == 0 and y == 0 else str(names[(id-1)%names.size()])
   if id == 45: type = "and_gate"
   var part = p(id,type,x,y)
   if Parts.controls(type).inputs > 0: part.input_a=45
   craft.append(part); id += 1
 return craft

func maximum_launcher() -> Array:
 var pad: Array = []
 var names = Parts.launcher_types()
 var id = 1001
 for y in range(-2,3):
  for x in range(-4,5):
   pad.append(p(id,str(names[(id-1001)%names.size()]),x,y)); id += 1
 return pad

func split_craft() -> Array:
 # Twenty linked splitter/battery pairs, a self-oscillating NOT signal,
 # one cargo and three support beams. All fit 45 unique editor cells.
 var craft: Array = []
 var pairs: Array = []
 var id = 1
 for y in range(-2,3):
  for x in [-4,-2,0,2]:
   var splitter = p(id,"splitter",x,y); id += 1
   var battery = p(id,"battery",x+1,y); id += 1
   splitter.target=battery.id;splitter.input_a=41
   craft.append(splitter);craft.append(battery);pairs.append([splitter.id,battery.id])
 var oscillator=p(41,"not_gate",4,-2);oscillator.input_a=41;craft.append(oscillator)
 craft.append(p(42,"cargo",4,0))
 craft.append(p(43,"beam",4,-1));craft.append(p(44,"beam",4,1));craft.append(p(45,"beam",4,2))
 return craft

func neutral_route() -> Dictionary:
 return {"distance":10000.0,"delivery_radius":5.0,"max_delivery_speed":45.0,"time_limit":90.0,"boundary_y":80.0,"weight":1.0,"hazards":[],"gravity":0.0,"wind":Vector2.ZERO,"seed":100,"contract_id":"BENCHMARK","variation":0.0,"deadline":90.0,"required":80.0,"reward":0}

func legal_assembly(craft: Array, pad: Array) -> bool:
 var ids: Dictionary = {}
 for assembly in [craft,pad]:
  var cells: Dictionary = {}
  for part in assembly:
   var cell=Vector2i(part.x,part.y)
   if abs(part.x)>4 or abs(part.y)>2 or cells.has(cell) or ids.has(part.id):return false
   cells[cell]=true;ids[part.id]=true
   if assembly==pad and not str(part.type) in Parts.launcher_types():return false
   if Parts.sanitize_parameter(part.type,part.param)!=part.param:return false
 return craft.size()<=45 and pad.size()<=45

func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--result="):output_path="res://docs/qa/"+arg.trim_prefix("--result=")
 var focused="--focused" in OS.get_cmdline_user_args()
 var quality_only="--quality-only" in OS.get_cmdline_user_args()
 var effects_only="--effects-only" in OS.get_cmdline_user_args()
 var cycles_only="--cycles-only" in OS.get_cmdline_user_args()
 var quality="standard";var density="auto"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--quality="):quality=arg.trim_prefix("--quality=")
  elif arg.begins_with("--density="):density=arg.trim_prefix("--density=")
  elif arg.begins_with("--window="):
   var dims=arg.trim_prefix("--window=");root.size=Vector2i(int(dims.get_slice("x",0)),int(dims.get_slice("x",1)))
 Engine.max_fps=0
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 output.environment={"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"api":RenderingServer.get_video_adapter_api_version(),"window_size":str(DisplayServer.window_get_size()),"vsync":"probe requests disabled; llvmpipe/Xorg reports mode switching unsupported","fps_cap":0,"viewport":"integer nearest pixel stage; no MSAA; actual canvas in every sample","measurement":"monotonic actual process-frame wall times after 2s warmup; no movie/FFmpeg capture; concurrent cloud load uncontrolled","caveat":"Software llvmpipe cloud test, not production GPU minimum-spec evidence. Synthetic neutral route isolates maximum editor/legal split load and is not a customer route."}
 scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);await frames(3)
 if scene.has_method("_apply_quality"):
  scene.settings.quality=quality;scene.settings.pixel_density=density;scene._apply_quality()
 output.environment.requested_quality=quality;output.environment.requested_density=density
 scene.economy=load("res://scripts/economy.gd").new();scene._starter();scene.economy.starter_stock(scene.design,scene.launcher);scene.page="hub";scene.render()
 scene.economy.accept_contract("D1-A");scene.render()
 if focused:
  await focused_stress();return
 if effects_only:
  await effects_stress();return
 if cycles_only:
  await cycles_stress();return
 await sample("starter_hub")
 scene.navigate("workshop");await sample("starter_workshop")
 var launch_start=Time.get_ticks_usec()
 scene.start_flight(true)
 output.stress.starter_launch_configuration_ms=float(Time.get_ticks_usec()-launch_start)/1000.0
 await sample("starter_launch_transition",1.5,0.0)
 await sample("starter_flight",4.0)
 if quality_only:
  output.complete=true;save_result();print("PERFORMANCE_QUALITY_COMPLETE ",quality)
  scene.music.stop();scene.music.stream=null;scene.sfx.stop();scene.sfx.stream=null
  scene.queue_free();await frames(3);quit(0);return
 scene.abort_flight();scene.navigate("hub");await warm(1.0)
 # Match stable visible state after each abort/retry cycle, flushing queued frees.
 for cycle in range(21):
  if cycle>0:
   scene.navigate("workshop");await frames(2)
   scene.start_flight(true);scene.launch_countdown=0;await frames(3)
   scene.abort_flight();await frames(2)
   scene.start_flight(true);scene.launch_countdown=0;await frames(3)
   scene.abort_flight();scene.navigate("hub");await frames(3)
  var record=snapshot("cycle_%02d"%cycle);record.cycle=cycle
  output.cycle_snapshots.append(record)
  if cycle%5==0:save_result();print("PERF_CYCLE ",JSON.stringify(record))
 output.cycles_complete=true;save_result();print("PERF_BASELINE_CYCLES_COMPLETE")
 var craft=maximum_craft();var pad=maximum_launcher()
 output.stress.maximum_legal=legal_assembly(craft,pad)
 output.stress.maximum_craft_count=craft.size();output.stress.maximum_launcher_count=pad.size()
 for type in Parts.catalog():scene.economy.inventory[type]=100
 scene.design=craft;scene.launcher=pad;scene.assembly_mode="craft";scene.navigate("workshop")
 await sample("maximum_45_craft_workshop")
 scene.assembly_mode="launcher";scene.render();await sample("maximum_45_launcher_workshop")
 scene._configure_flight(true,craft,pad,neutral_route());await sample("maximum_45_craft_45_launcher_flight",4.0)
 scene.abort_flight();scene.navigate("hub")
 var split_design=split_craft()
 output.stress.split_input_legal=legal_assembly(split_design,pad)
 var sim=Sim.new();var start=Time.get_ticks_usec();sim.configure(split_design,[],neutral_route(),100)
 output.stress.split_configure_ms=float(Time.get_ticks_usec()-start)/1000.0
 var steps: Array=[];var peak_parts=sim.parts.size();var peak_bodies=sim.bodies.size();var peak_effects=0
 for i in range(180):
  var before=Time.get_ticks_usec();sim.step(1.0/60.0);steps.append(float(Time.get_ticks_usec()-before)/1000.0)
  peak_parts=maxi(peak_parts,sim.parts.size());peak_bodies=maxi(peak_bodies,sim.bodies.size());peak_effects=maxi(peak_effects,sim.effects.size())
 steps.sort()
 output.stress.merge({"split_wall_ms":float(Time.get_ticks_usec()-start)/1000.0,"split_simulated_seconds":sim.elapsed,"split_status":sim.status,"split_peak_parts":peak_parts,"split_peak_bodies":peak_bodies,"split_peak_effects":peak_effects,"split_step_1_60_ms_p50":percentile(steps,.5),"split_step_1_60_ms_p95":percentile(steps,.95),"split_events":sim.events.size(),"split_incidents":sim.incidents.size()})
 scene._configure_flight(true,split_design,[],neutral_route());scene.sim=sim;scene.launch_countdown=0
 await sample("legal_split_stress_flight",4.0)
 output.stress.final_split_parts=scene.sim.parts.size();output.stress.final_split_bodies=scene.sim.bodies.size();output.stress.final_split_status=scene.sim.status
 scene.abort_flight();scene._starter();scene.page="hub";scene.assembly_mode="craft";scene.render()
 for pixel_mode in ["low","balanced","auto"]:
  scene.settings.pixel_density=pixel_mode;scene._apply_quality()
  await sample("starter_hub_density_"+pixel_mode)
  scene.navigate("workshop");await sample("starter_workshop_density_"+pixel_mode)
  scene.start_flight(true);await sample("starter_flight_density_"+pixel_mode,4.0)
  scene.abort_flight();scene.page="hub";scene.render()
 output.complete=true;save_result();print("PERFORMANCE_PROBE_COMPLETE ",output_path)
 scene.music.stop();scene.music.stream=null;scene.sfx.stop();scene.sfx.stream=null
 scene.queue_free();await frames(3);quit(0)

func focused_stress() -> void:
 var split=split_craft();var sim=Sim.new();sim.configure(split,[],neutral_route(),100)
 var times:Array=[];var start=Time.get_ticks_usec()
 for i in range(180):
  var before=Time.get_ticks_usec();sim.step(1.0/60.0);times.append(float(Time.get_ticks_usec()-before)/1000.0)
 times.sort()
 output.stress={"split_step_1_60_ms_p50":percentile(times,.5),"split_step_1_60_ms_p95":percentile(times,.95),"split_wall_ms":float(Time.get_ticks_usec()-start)/1000.0,"split_parts":sim.parts.size(),"split_bodies":sim.bodies.size(),"split_elapsed":sim.elapsed,"split_status":sim.status}
 scene._configure_flight(true,split,[],neutral_route());scene.sim=sim;scene.launch_countdown=0
 await sample("legal_split_stress_flight_optimized",6.0)
 output.complete=true;save_result();print("PERFORMANCE_FOCUSED_COMPLETE ",JSON.stringify(output.stress))
 scene.music.stop();scene.music.stream=null;scene.sfx.stop();scene.sfx.stream=null
 scene.queue_free();await frames(3);quit(0)

func effects_stress() -> void:
 var craft=split_craft()
 var teleports=0
 for module in craft:
  if module.type=="splitter":
   module.type="teleporter";module.param=.5;module.target=-1;module.rot=0 if teleports%2==0 else 2;teleports+=1
 var sim=Sim.new();sim.configure(craft,[],neutral_route(),100)
 for i in range(12):sim.step(1.0/60.0)
 output.stress={"input_legal":legal_assembly(craft,[]),"modules":craft.size(),"teleporters":teleports,"effects":sim.effects.size(),"status":sim.status,"elapsed":sim.elapsed,"energy_used":sim.telemetry.energy_used,"mode":"player-paused at finite-energy legal teleport burst to retain worst-case live effects"}
 scene._configure_flight(true,craft,[],neutral_route());scene.sim=sim;scene.launch_countdown=0;scene.paused=true
 await sample("legal_teleport_peak_paused",3.0,1.0)
 output.complete=true;save_result();print("PERFORMANCE_EFFECTS_COMPLETE ",JSON.stringify(output.stress))
 scene.music.stop();scene.music.stream=null;scene.sfx.stop();scene.sfx.stream=null
 scene.queue_free();await frames(3);quit(0)

func cycles_stress() -> void:
 scene.navigate("workshop");scene.start_flight(true);await warm(1.7);scene.abort_flight();scene.navigate("hub");await warm(1)
 for cycle in range(21):
  if cycle>0:
   scene.navigate("workshop");await frames(2)
   scene.start_flight(true);scene.launch_countdown=0;await frames(3)
   scene.abort_flight();await frames(2)
   scene.start_flight(true);scene.launch_countdown=0;await frames(3)
   scene.abort_flight();scene.navigate("hub");await frames(3)
  var record=snapshot("cycle_%02d"%cycle);record.cycle=cycle;output.cycle_snapshots.append(record)
  if cycle%5==0:save_result();print("PERF_CYCLE ",JSON.stringify(record))
 await warm(.7)
 output.settled_snapshot=snapshot("after_all_motion_settled")
 output.complete=true;save_result();print("PERFORMANCE_CYCLES_COMPLETE")
 scene.music.stop();scene.music.stream=null;scene.sfx.stop();scene.sfx.stream=null
 scene.queue_free();await frames(3);quit(0)
