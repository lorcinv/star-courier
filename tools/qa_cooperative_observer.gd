extends "res://tools/qa_audio_game.gd"
## QA-only observer of the unchanged native production scene. No controller
## calls, engine input, scene stepping, save authoring, or gameplay mutations.
class CooperativeObserver extends Node:
 var game
 var samples:Array=[]
 var output:String=""
 var latest:String=""
 var last_usec:int=-100000
 var capped:bool=false
 var count:int=0
 func _ready() -> void:
  process_mode=Node.PROCESS_MODE_ALWAYS
  process_priority=100
  output=OS.get_environment("SC_QA_TELEMETRY_OUTPUT")
  latest=output.get_base_dir().path_join("cooperative-latest.json")
  print("QA_COOPERATIVE_OBSERVER_READY ",JSON.stringify({"max_hz":20,"max_samples":12000,"output":output,"mutates_gameplay":false}))
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
  if now-last_usec<50000:return
  last_usec=now
  if samples.size()>=12000:capped=true;return
  var ledger:Dictionary={}
  for key in ["credits","day","phase","deliveries","jobs_today","inventory","active_contract_id","settled_ids","history","in_flight"]:
   var value=game.economy.get(key)
   ledger[key]=value.duplicate(true) if value is Dictionary or value is Array else value
  var item:Dictionary={"engine_monotonic_usec":now,"unix_seconds":Time.get_unix_time_from_system(),
   "page":game.page,"trial":game.trial,"paused":game.paused,"loading":game.world.loading_snapshot(),
   "hud_visible":game.hud.visible,"overlay_open":game.loading_overlay.is_open(),
   "dialogue_open":game.dialogue.is_open(),"dialogue_line":game.dialogue._line_index,
   "dialogue_lines":game.dialogue._conversation.get("lines",[]).size(),
   "dialogue_visible_chars":game.dialogue._visible_chars,
   "ledger":ledger,"cargo_loaded":game.economy.is_cargo_loaded(),
   "design":game.design.duplicate(true),"launch_countdown":game.launch_countdown,
   "window_size":[game.get_window().size.x,game.get_window().size.y]}
  if game.sim!=null:item.sim_status=game.sim.status;item.sim_elapsed=game.sim.elapsed
  samples.append(item)
  # Small read-only observation sidecar permits the OS driver to wait for a
  # visible production phase, rather than manufacturing that phase in-engine.
  var status:Dictionary=item.duplicate(true);status.buttons=[];buttons(game,status.buttons)
  var file=FileAccess.open(latest+".tmp",FileAccess.WRITE)
  if file!=null:
   file.store_string(JSON.stringify(status,"",true,true));file.close()
   DirAccess.rename_absolute(latest+".tmp",latest)
 func _exit_tree() -> void:
  if output.is_empty():return
  var file=FileAccess.open(output,FileAccess.WRITE)
  if file==null:push_error("QA cooperative observer could not write output");return
  file.store_string(JSON.stringify({"method":"Read-only 20 Hz observation of native production main process","max_hz":20,"max_samples":12000,"capped":capped,"samples":samples},"",true,true));file.close()
  print("QA_COOPERATIVE_OBSERVER_SAVED ",JSON.stringify({"output":output,"samples":samples.size(),"capped":capped}))
func _initialize() -> void:
 super._initialize()
 var observer=CooperativeObserver.new();observer.name="QACooperativeReadOnlyObserver"
 root.add_child.call_deferred(observer)
