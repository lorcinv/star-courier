extends "res://tools/qa_audio_game.gd"
## Read-only native QA sidecar. The production scene receives only OS input.
## Diagnostics never advance a scene, dispatch an action, or author a save.
class LocomotionObserver extends Node:
 var game
 var samples:Array=[]
 var output:String=""
 var latest:String=""
 var last_usec:int=-100000
 var capped:bool=false
 const MAX_SAMPLES:int=9000
 func _ready() -> void:
  process_mode=Node.PROCESS_MODE_ALWAYS;process_priority=100
  output=OS.get_environment("SC_QA_TELEMETRY_OUTPUT")
  latest=output.get_base_dir().path_join("cooperative-latest.json")
  print("QA_LOCOMOTION_OBSERVER_READY ",JSON.stringify({"max_hz":30,"max_samples":MAX_SAMPLES,"output":output,"mutates_gameplay":false}))
 func json_value(value:Variant) -> Variant:
  if value is Vector2 or value is Vector2i:return [value.x,value.y]
  if value is Rect2 or value is Rect2i:return [value.position.x,value.position.y,value.size.x,value.size.y]
  if value is Dictionary:
   var result:Dictionary={}
   for key in value:result[str(key)]=json_value(value[key])
   return result
  if value is Array:
   var result:Array=[]
   for item in value:result.append(json_value(item))
   return result
  if value is float and not is_finite(value):return null
  return value
 func optional_property(node:Object,key:String) -> Variant:
  for property in node.get_property_list():
   if str(property.name)==key:return node.get(key)
  return null
 func buttons(node:Node,result:Array) -> void:
  if node is Button and node.is_visible_in_tree():
   var rect:Rect2=node.get_global_rect()
   result.append({"name":str(node.name),"text":node.text,"disabled":node.disabled,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
  for child in node.get_children():buttons(child,result)
 func _process(_delta:float) -> void:
  if not is_instance_valid(game):
   for node in get_tree().root.get_children():
    if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":game=node;break
  if not is_instance_valid(game) or not is_instance_valid(game.world):return
  var now:int=Time.get_ticks_usec()
  if now-last_usec<33333:return
  last_usec=now
  if samples.size()>=MAX_SAMPLES:capped=true;return
  var ledger:Dictionary={}
  for key in ["credits","day","phase","deliveries","jobs_today","inventory","active_contract_id","settled_ids","history","in_flight"]:
   var value:Variant=game.economy.get(key)
   ledger[key]=value.duplicate(true) if value is Dictionary or value is Array else value
  var item:Dictionary={"engine_monotonic_usec":now,"unix_seconds":Time.get_unix_time_from_system(),
   "page":game.page,"trial":game.trial,"paused":game.paused,"loading":game.world.loading_snapshot(),
   "hud_visible":game.hud.visible,"overlay_open":game.loading_overlay.is_open(),
   "dialogue_open":game.dialogue.is_open(),"dialogue_line":game.dialogue._line_index,
   "dialogue_lines":game.dialogue._conversation.get("lines",[]).size(),
   "dialogue_visible_chars":game.dialogue._visible_chars,"ledger":ledger,
   "cargo_loaded":game.economy.is_cargo_loaded(),"design":game.design.duplicate(true),
   "launch_countdown":game.launch_countdown,"window_size":game.get_window().size,
   "clerk_position":game.world.clerk.position,"clerk_z":game.world.clerk.z_index,
   "camera_position":game.world.camera.position,"camera_zoom":game.world.camera.zoom,
   "connected_joypads":Input.get_connected_joypads()}
  if game.world.has_method("shop_locomotion_snapshot"):item.locomotion=game.world.shop_locomotion_snapshot()
  var input_owner:Variant=optional_property(game,"courier_input")
  if input_owner is Object and is_instance_valid(input_owner) and input_owner.has_method("debug_snapshot"):item.input=input_owner.debug_snapshot()
  var motion:Variant=optional_property(game.world,"_clerk_motion")
  if motion is Object and is_instance_valid(motion) and motion.has_method("debug_snapshot"):item.motion=motion.debug_snapshot()
  if game.sim!=null:
   item.sim_status=game.sim.status;item.sim_elapsed=game.sim.elapsed
   item.pilot_input=game._pilot_input_state()
  var focus:Control=get_viewport().gui_get_focus_owner()
  item.focus_control=str(focus.get_path()) if is_instance_valid(focus) else ""
  item=json_value(item);samples.append(item)
  var status:Dictionary=item.duplicate(true);status.buttons=[];buttons(game,status.buttons)
  var file=FileAccess.open(latest+".tmp",FileAccess.WRITE)
  if file!=null:
   file.store_string(JSON.stringify(status,"",true,true));file.close()
   DirAccess.rename_absolute(latest+".tmp",latest)
 func _exit_tree() -> void:
  if output.is_empty():return
  var file=FileAccess.open(output,FileAccess.WRITE)
  if file==null:push_error("QA locomotion observer could not write output");return
  file.store_string(JSON.stringify({"method":"Read-only 30 Hz native production observation; no synthesized gameplay input","max_hz":30,"max_samples":MAX_SAMPLES,"capped":capped,"samples":samples},"",true,true));file.close()
  print("QA_LOCOMOTION_OBSERVER_SAVED ",JSON.stringify({"output":output,"samples":samples.size(),"capped":capped}))
func _initialize() -> void:
 super._initialize()
 var observer=LocomotionObserver.new();observer.name="QALocomotionReadOnlyObserver"
 root.add_child.call_deferred(observer)
