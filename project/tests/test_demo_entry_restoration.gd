extends SceneTree
## Main ingress-only behavioral probes. No authored/earned save, no fake flight
## completion, no actor/physics replacement in a running game.
const Main=preload("res://scripts/main.gd")
var passed:int=0
var failed:int=0
class State extends RefCounted:
 var review_load_blocked:bool=false
 var in_flight:Dictionary={}
 var active_contract_id:String=""
 var last_settlement:Dictionary={}
 var returns:Array=[]
 var phase:String="morning"
 func pending_story_returns() -> Array:return returns
class Probe extends "res://scripts/main.gd":
 var resume_calls:int=0
 var story_calls:int=0
 var replay_seen:Dictionary={}
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
 func _input(_event:InputEvent) -> void:pass
 func _unhandled_key_input(_event:InputEvent) -> void:pass
 func _resume_dispatch() -> void:
  resume_calls+=1;replay_seen=economy.in_flight.duplicate(true)
 func _restore_story_dialogue() -> void:story_calls+=1
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func make_probe():
 var probe=Probe.new();probe.economy=State.new();probe.entry_defer_controls=true
 probe.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(probe);return probe
func run() -> void:
 var probe=make_probe()
 check(probe._title_shop_walk_allowed(),"empty daytime shop alone permits entry")
 probe.economy.in_flight={"elapsed":4.5,"seed":41,"route":{"id":"fictional-flight"}}
 check(not probe._title_shop_walk_allowed(),"in-flight state excludes shop entrance")
 var original:Dictionary=probe.economy.in_flight.duplicate(true)
 probe.prepare_title_restore();probe.prepare_title_restore()
 check(probe.resume_calls==1 and probe.replay_seen==original and probe.economy.in_flight==original,"existing replay invoked once with unchanged snapshot while quarantined")
 check(probe.process_mode==Node.PROCESS_MODE_DISABLED and probe.entry_defer_controls,"prepare replay cannot grant player control")
 probe.finish_title_entry();probe.finish_title_entry();await process_frame
 check(probe.resume_calls==1 and probe.story_calls==0,"entry release never replays twice or injects shop story into flight")
 check(not probe.entry_defer_controls and probe.process_mode==Node.PROCESS_MODE_INHERIT,"successful explicit release restores normal process mode")
 probe.free()
 for condition in ["accepted","result","return","night","recovery"]:
  probe=make_probe()
  match condition:
   "accepted":probe.economy.active_contract_id="fictional-accepted"
   "result":probe.economy.last_settlement={"contract_id":"fictional-result"}
   "return":probe.economy.returns=[{"contract_id":"fictional-return"}]
   "night":probe.economy.phase="night"
   "recovery":probe.economy.review_load_blocked=true
  check(not probe._title_shop_walk_allowed(),condition+" excludes shop entrance without resetting state")
  if condition!="recovery":
   probe.prepare_title_restore();probe.prepare_title_restore()
   check(probe.resume_calls==0 and probe.story_calls==0,condition+" title preparation leaves original story deferred")
   probe.finish_title_entry();probe.finish_title_entry();await process_frame
   check(probe.resume_calls==0 and probe.story_calls==1,condition+" release invokes original story-restoration path once")
  probe.free()
 probe=make_probe();probe.entry_defer_controls=false
 check(not probe._title_shop_walk_allowed(),"legacy non-title startup does not opt in")
 probe.prepare_title_restore();probe.finish_title_entry();await process_frame
 check(probe.resume_calls==0 and probe.story_calls==0,"unconfigured ingress helpers are no-ops")
 probe.free()
 print("DEMO_ENTRY_RESTORATION passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
