extends SceneTree
## Read-only editor feedback; real current/legacy solvers stay unmodified.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const CurrentSim=preload("res://scripts/pilot_free_simulation_v2.gd")
const CurrentProfile=preload("res://scripts/pilot_free_profile_v2.gd")
const LegacySim=preload("res://scripts/pilot_free_simulation_v1.gd")
const LegacyProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0

func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var value:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 value.merge(extra,true);return value

func design(source:int=-2) -> Array:
 # Deliberately no battery: the coupler is a mechanical socket.
 return [part(1,"cargo",0),part(3,"coupler",1,0,{"input_a":source,"target":4}),part(4,"beam",2)]

func coupler(parts:Array) -> Dictionary:
 for item in parts:
  if int(item.id)==3:return item
 return {}

func feedback(parts:Array,pilot:bool,ready:bool,fragment:String,label:String) -> Dictionary:
 var before:PackedByteArray=var_to_bytes(parts)
 var selected:Dictionary=coupler(parts)
 var result:Dictionary=Policy.readiness(selected,parts,pilot,false)
 check(bool(result.ready)==ready and fragment in str(result.text),label)
 check(var_to_bytes(parts)==before,label+" preserves blueprint bytes")
 return result

func make_sim(parts:Array,legacy:bool=false):
 var route:Dictionary=LegacyProfile.route(Extreme.route({"weight":1.0})) if legacy else CurrentProfile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var sim=LegacySim.new() if legacy else CurrentSim.new()
 sim.configure(parts,[],route,42)
 return sim

func press(sim,legacy:bool=false) -> void:
 if legacy:sim.set_free_flight_input(0,0,false,true)
 else:sim.set_free_flight_input(0,0,false,true,3)

func _initialize() -> void:
 var manual:Array=design()
 var view:Dictionary=feedback(manual,true,true,"接口就绪","cargo-connected manual coupler is ready without battery")
 check(view.target_id==4 and 4 in view.valid_targets,"ready panel retains exact selected adjacent target")
 check(not "Q" in str(view.text) and not "Space" in str(view.text),"readiness stays short rather than repeating trigger instructions")
 feedback(design(-1),true,false,"尚未设置触发","unwired coupler never claims its adjacent socket can fire")
 feedback(design(-3),true,false,"尚未设置触发","unknown negative saved trigger remains unset rather than silently rebound")
 feedback(manual,false,false,"尚未设置触发","cockpit sentinel is not usable outside piloted flight")
 var detached:Array=design();detached[0].x=-10
 feedback(detached,true,false,"未连接货物","manual coupler away from cargo cannot receive the cockpit trigger")
 feedback(manual.slice(1),true,false,"未连接货物","manual coupler with no cargo cannot receive the cockpit trigger")
 var connected:Array=design();connected[0].x=-1;connected.append(part(2,"beam",0))
 feedback(connected,true,true,"接口就绪","cockpit may reach coupler through an indirect structural path")

 var wired:Array=design(5);wired.append(part(5,"not_gate",1,1))
 view=feedback(wired,true,true,"等待原控制信号","connected saved signal stays ready under its own trigger")
 check(not "按键" in str(view.text) and not "空格" in str(view.text),"wired legacy coupler is never presented as a manual Space action")
 feedback(wired.slice(1),true,true,"等待原控制信号","wired coupler needs neither cargo authority nor battery")
 var disconnected_source:Array=wired.duplicate(true);disconnected_source[3].x=10
 feedback(disconnected_source,true,false,"控制零件已断开","existing but disconnected control is a visible blocker")
 feedback(design(999),true,false,"控制零件已断开","missing saved control is a visible blocker")
 for version in ["pilot-free-v2","pilot-free-v1","pilot-v3"]:
  var startup:String=Policy.trigger_text(coupler(wired),wired,true,false,version)
  check("沿用控制" in startup and "须保持结构相连" in startup and not "空格" in startup,version+" keeps the original external-trigger wording")
 check("选择此装置" in Policy.trigger_text(coupler(manual),manual,true,false,"pilot-free-v2"),"current manual trigger remains explicitly selected")
 check("同时触发所有" in Policy.trigger_text(coupler(manual),manual,true,false,"pilot-free-v1"),"legacy manual trigger retains its shared-button semantics")

 var no_target:Array=design();no_target[0].x=-10;no_target[2].x=10
 view=feedback(no_target,true,false,"先选择一个相邻零件","invalid explicit target stays the first repair instruction")
 check(view.target_id==4 and coupler(no_target).target==4,"invalid existing target stays selected instead of being rewritten")
 var wrong_target:Array=design();wrong_target.append(part(7,"beam",5));coupler(wrong_target).target=7
 view=feedback(wrong_target,true,false,"先选择一个相邻零件","nearby alternatives do not mask a remote explicit target")
 check(view.target_id==7 and coupler(wrong_target).target==7,"remote selected target is never replaced by a usable neighbor")
 var automatic_target:Array=design();coupler(automatic_target).target=-1
 view=feedback(automatic_target,true,true,"接口就绪","existing default-target behavior remains visible and usable")
 check(view.target_id==1 and coupler(automatic_target).target==-1,"default-target projection keeps frozen design-order fallback without saving it")

 # Compatibility rendering may inspect JSON-loaded dictionaries repeatedly.
 var saved:Array=JSON.parse_string(JSON.stringify(wired))
 coupler(saved).param=0.137;coupler(saved).input_b=72
 coupler(saved)["retained_payload"]={"note":"old blueprint", "values":[2.25,9]}
 var original:PackedByteArray=var_to_bytes(saved)
 for version in ["pilot-free-v2","pilot-free-v1","pilot-v3"]:
  for attempt in 3:
   Policy.readiness(coupler(saved),saved,true,false)
   Policy.trigger_text(coupler(saved),saved,true,false,version)
   Policy.local_controls(coupler(saved),false)
   Policy.target_options(coupler(saved),saved)
   Policy.convenience_source(coupler(saved),true,false)
 check(var_to_bytes(saved)==original,"repeated compatibility projection never migrates loaded parameters, wiring, target, or extra fields")
 check(Policy.sale_kinds().size()==12 and Policy.SCHEMA=="workshop-parts-mechanical-v2","feedback changes neither catalogue count nor editor schema")

 # Observe the unmodified runtime contract behind the repaired messages.
 for legacy in [false,true]:
  var version:String="legacy v1" if legacy else "current v2"
  var input:Array=design();var input_before:PackedByteArray=var_to_bytes(input)
  var sim=make_sim(input,legacy);press(sim,legacy)
  check(sim._enabled(sim.parts[3]) and sim.total_energy()==0.0,version+" really accepts a battery-free connected manual trigger")
  var energy:float=sim.total_energy()
  sim._act(sim.parts[3],sim.body_for_part(3),1.0/120.0,true)
  check(not sim._linked(3,4) and sim.total_energy()==energy,version+" opens the chosen socket for exactly zero energy")
  check(var_to_bytes(input)==input_before,version+" compatibility configure and act leave the saved blueprint untouched")
  var idle=make_sim(design(-1),legacy);press(idle,legacy)
  check(not idle._enabled(idle.parts[3]),version+" confirms original unset-trigger false-ready failure")
  var lost=make_sim(detached,legacy);press(lost,legacy)
  check(not lost._enabled(lost.parts[3]),version+" confirms original detached-cargo false-ready failure")
  var external=make_sim(wired,legacy);press(external,legacy)
  external.parts[5].signal=false
  check(not external._enabled(external.parts[3]),version+" Space cannot override an external source")
  external.parts[5].signal=true
  check(external._enabled(external.parts[3]),version+" connected original source still controls the coupler")
  external._act(external.parts[3],external.body_for_part(3),1.0/120.0,true)
  check(not external._linked(3,4) and external.total_energy()==0.0,version+" external source opens the same socket without power")
  var missing=make_sim(disconnected_source,legacy);missing.parts[5].signal=true
  check(not missing._enabled(missing.parts[3]),version+" disconnected source cannot reach the coupler")
 print("COUPLER_READINESS_DEV05 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)
