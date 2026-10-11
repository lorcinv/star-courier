extends SceneTree
## Headless production Main._resume_dispatch with a presentation-only stub.
## _configure_flight uses the real selected simulator and deterministic seed.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const V1=preload("res://scripts/pilot_profile.gd")
const V2=preload("res://scripts/pilot_ascent_profile.gd")
const V4=preload("res://scripts/pilot_wormhole_profile.gd")
var passed:int=0
var failed:int=0
class NoopWorld extends RefCounted:
 func settle_resumed_flight(_sim):pass
class Controller extends "res://scripts/main.gd":
 var configured:int=0
 var notices:Array=[]
 func _ready():pass
 func notify(message:String):notices.append(message)
 func _configure_flight(_trial:bool,craft:Array,pad:Array,route:Dictionary,_resuming:bool=false):
  configured+=1;flight_order=route.duplicate(true)
  sim=_simulation_for_version(str(route.get("control_version","")))
  sim.configure(craft,pad,route,route.seed)
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func write_save(path:String,value:Dictionary):
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(value,"",true,true));f.close()
func clear_files():
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  DirAccess.remove_absolute("user://"+name)
func fixture() -> Dictionary:
 clear_files();var e=Econ.new();e.enable_extreme_mode();e.ensure_contracts();e.accept_contract("D1-A");e.begin_dispatch(Profile.starter_design(),Profile.starter_launcher())
 check(e.save_state(Profile.starter_design(),Profile.starter_launcher(),{}),"create actual in-flight save")
 return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func resume(snapshot:Dictionary,expected:bool,seed_value:int=0):
 var host=Controller.new();host.world=NoopWorld.new();host.economy.in_flight=snapshot.duplicate(true)
 var before:PackedByteArray=var_to_bytes(host.economy.in_flight)
 host._resume_dispatch()
 check((host.configured==1)==expected and host.pilot_resume_blocked!=expected,"resume acceptance "+str(snapshot.get("seed")))
 check(var_to_bytes(host.economy.in_flight)==before,"resume preserves raw snapshot")
 if expected:check(host.sim!=null and host.sim.seed_value==seed_value,"real simulator retains exact seed "+str(seed_value))
 else:check(host.sim==null and not host.notices.is_empty() and not host.save_game(),"reject before any simulation or overwrite")
 host.free()
func _initialize():
 var good:Dictionary=fixture();var e=Econ.new()
 for value in ["203",203.5,true,false,null,"not a seed",{},[],NAN,INF,-INF,9007199254740992,-9007199254740992]:
  var bad:Dictionary=good.duplicate(true);bad.in_flight.seed=value
  check(not e._valid_save(bad),"known replay rejects invalid seed type/range "+str(value))
  resume(bad.in_flight,false)
 for value in [203,203.0,-1,-1.0,0,9007199254740991,-9007199254740991]:
  var valid:Dictionary=good.duplicate(true);valid.in_flight.seed=value
  check(e._valid_save(valid),"known replay accepts exact signed JSON integer "+str(value))
  resume(valid.in_flight,true,int(value))
  var decoded:Dictionary=JSON.parse_string(JSON.stringify(valid,"",true,true))
  check(e._valid_save(decoded) and float(decoded.in_flight.seed)==float(value),"JSON roundtrip retains safe integer boundary")
  resume(decoded.in_flight,true,int(value))
 var absent:Dictionary=good.in_flight.duplicate(true);absent.erase("seed");resume(absent,true,100)
 # Each shipped protocol retains the same legacy signed seed semantics.
 var base:Dictionary=Econ.new()._autonomous_routes()[0]
 for route in [base,V1.route(base),V2.route(base),Profile.route(base),V4.route(base)]:
  var legacy:Dictionary={"route":route,"design":Profile.starter_design(),"launcher":Profile.starter_launcher(),"seed":-1,"ticks":0,"input_commands":[{"tick":0,"axis_q":0,"boost":false,"active":false}]}
  if route.has("control_version"):legacy.control_version=route.control_version
  else:legacy.simulation_version="autonomous-v5"
  resume(legacy,true,-1);legacy.erase("seed");resume(legacy,true,100)
 # No seed/time conversion is attempted for unknown future payloads.
 for key in ["control_version","simulation_version","future_with_damaged_adjacent_fields"]:
  var future:Dictionary=good.duplicate(true);future.in_flight["control_version" if key=="future_with_damaged_adjacent_fields" else key]="future-v900";future.in_flight.seed=null;future.in_flight.ticks={"future":true};future.in_flight.elapsed=null
  check(e._valid_save(future),"future payload remains structurally opaque "+key)
  if key=="future_with_damaged_adjacent_fields":future.review_state={"future":"opaque"};future.settled_ids="opaque future ledger";future.version=99
  resume(future.in_flight,false)
  clear_files();write_save("user://savegame.json",future);write_save("user://savegame.backup.json",good)
  var before:String=FileAccess.get_file_as_string("user://savegame.json");var backup:String=FileAccess.get_file_as_string("user://savegame.backup.json")
  var restored=Econ.new();var loaded:Dictionary=restored.load_state()
  check(restored.review_load_blocked and loaded.in_flight["control_version" if key=="future_with_damaged_adjacent_fields" else key]=="future-v900","future primary blocks without downgrading to known backup")
  check(not restored.save_state([],[],{}) and FileAccess.get_file_as_string("user://savegame.json")==before and FileAccess.get_file_as_string("user://savegame.backup.json")==backup,"future recovery keeps both source files")
 for value in [null,"203",203.5,true,9007199254740992]:
  var bad:Dictionary=good.duplicate(true);bad.in_flight.seed=value
  clear_files();write_save("user://savegame.json",bad);write_save("user://savegame.backup.json",good)
  var before:String=FileAccess.get_file_as_string("user://savegame.json");var backup:String=FileAccess.get_file_as_string("user://savegame.backup.json")
  var restored=Econ.new();restored.load_state()
  check(not restored.review_load_blocked and restored.load_notice.contains("备份") and restored.in_flight.seed==100,"known invalid seed recovers valid backup")
  check(FileAccess.get_file_as_string("user://savegame.json")==before and FileAccess.get_file_as_string("user://savegame.backup.json")==backup,"backup load preserves source bytes")
  DirAccess.remove_absolute("user://savegame.backup.json");restored=Econ.new();var loaded:Dictionary=restored.load_state()
  check(restored.review_load_blocked and not loaded.is_empty() and not restored.save_state([],[],{}),"known bad seed without backup is recovery-only")
  check(FileAccess.get_file_as_string("user://savegame.json")==before,"failed seed recovery preserves primary")
 clear_files();print("REPLAY_SEED_INTEGRITY passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
