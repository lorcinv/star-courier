extends SceneTree
## Read-only editor feedback matched against the unchanged actual solver.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var value:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 value.merge(extra,true);return value
func design(kind:String="accelerator",source:int=-2,target:int=4) -> Array:
 return [part(4,"beam",2),part(1,"cargo",0),part(2,"battery",-1),part(3,kind,1,0,{"input_a":source,"target":target,"param":2.0}),part(5,"not_gate",1,1)]
func selected(pieces:Array) -> Dictionary:return pieces[3]
func make_sim(pieces:Array):
 var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var sim=Sim.new();sim.configure(pieces,[],route,42);return sim
func feedback(pieces:Array,version:String="pilot-free-v2",pilot:bool=true,launcher:bool=false) -> Dictionary:
 return Policy.readiness(selected(pieces),pieces,pilot,launcher,version)
func _initialize() -> void:
 triggers_and_blockers();target_resolution();cargo_risk();read_only()
 print("MECHANICAL_TARGET_FEEDBACK_DEV05 passed=%d failed=%d native_input=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
func triggers_and_blockers() -> void:
 var manual:Array=design();var result:Dictionary=feedback(manual)
 check(result.ready and "按键弹出高亮零件" in result.text and not result.warning,"manual readiness stays brief and names actual highlighted action")
 var wired:Array=design("accelerator",5);result=feedback(wired)
 check(result.ready and "等待原控制信号" in result.text and not "按键" in result.text and not "Q /" in result.text and not "空格" in result.text,"OLD FAILURE: wired accelerator never claims a cockpit trigger")
 var sim=make_sim(wired);sim.set_free_flight_input(0,0,false,true,3);sim.parts[5].signal=false
 check(not sim._enabled(sim.parts[3]),"actual solver refuses cockpit override of saved source")
 sim.parts[5].signal=true;check(sim._enabled(sim.parts[3]),"actual saved source still enables accelerator")
 for target in [1,999,3]:
  var unpowered:Array=design("accelerator",-2,target);unpowered[2].x=-10
  result=feedback(unpowered)
  check(not result.ready and result.text=="未接通电芯，无法触发。" and not result.warning,"power blocker wins over target/cargo warning %d"%target)
  var unset:Array=design("accelerator",-1,target);result=feedback(unset)
  check(not result.ready and result.text=="等待设置触发。" and not result.warning,"unset trigger wins over target/cargo warning %d"%target)
  var lost:Array=design("accelerator",888,target);result=feedback(lost)
  check(not result.ready and "控制零件已断开" in result.text and not result.warning,"lost source wins over target/cargo warning %d"%target)
 var valve:Array=design("accelerator",-2,1);valve.append(part(6,"valve",2,1,{"target":3,"param":120.0}));result=feedback(valve)
 check(not result.ready and "旧功率阀" in result.text and not result.warning,"valve blocker precedes cargo risk")
 var detached:Array=design();detached[1].x=-10;detached[2].x=3;result=feedback(detached)
 check(not result.ready and "收不到驾驶按键" in result.text and not result.warning,"cargo-control blocker remains intact")
func target_resolution() -> void:
 for kind in ["accelerator","coupler","splitter"]:
  for target in [4,999,3,-1]:
   var pieces:Array=design(kind,-2,target);var before:PackedByteArray=var_to_bytes(pieces)
   var sim=make_sim(pieces);var actual:Dictionary=sim._target(sim.parts[3],sim.body_for_part(3))
   var projected:Dictionary=Policy.effective_target(selected(pieces),pieces);var result:Dictionary=feedback(pieces)
   check(actual.id==projected.id and result.target_id==actual.id,kind+" preview/readiness matches frozen _target for saved ID "+str(target))
   var fallback:bool=target in [999,3]
   check(bool(result.warning)==fallback and (("原目标不可用" in result.text)==fallback),kind+" missing/self target warns without blocking actual fallback "+str(target))
   check(result.ready and var_to_bytes(pieces)==before and selected(pieces).target==target,kind+" fallback stays selectable and saved ID exact "+str(target))
  var far:Array=design(kind,-2,7);far.append(part(7,"beam",5));var result:Dictionary=feedback(far)
  var sim=make_sim(far);var actual:Dictionary=sim._target(sim.parts[3],sim.body_for_part(3))
  check(actual.id==7 and result.target_id==7 and not result.ready and selected(far).target==7,kind+" far existing target remains truly invalid despite adjacent alternatives")
 var no_neighbor:Array=[part(4,"beam",8),part(1,"cargo",0),part(2,"battery",-1),part(3,"accelerator",5,0,{"input_a":-2,"target":999})]
 var result:Dictionary=feedback(no_neighbor)
 check(not result.ready and "没有相邻目标" in result.text and not result.warning,"missing ID with no fallback preserves original no-target blocker")
func cargo_risk() -> void:
 var pieces:Array=design("accelerator",-2,1);var result:Dictionary=feedback(pieces)
 check(result.ready and result.warning and "弹出货舱会断开供电" in result.text and "本次弹出时安全入收件圈" in result.text,"OLD FAILURE: current cargo ejection explicitly warns about same-step safe capture")
 check(1 in result.valid_targets and selected(pieces).target==1,"risky valid cargo remains explicitly selectable")
 for version in ["","pilot-free-v1","pilot-v3","autonomous-v5","future-v99"]:
  result=feedback(pieces,version)
  check(not "断开供电" in result.text and not result.warning,"no new current-mode risk claim for "+version)
 result=feedback(design("accelerator",5,1),"pilot-free-v2",false)
 check(not "断开供电" in result.text,"nonpilot context does not inherit current-mode warning")
 result=feedback(pieces,"pilot-free-v2",true,true)
 check(not "断开供电" in result.text,"launchpad accelerator never gets craft cargo warning")
 result=feedback(design("coupler",-2,1));check(not "断开供电" in result.text,"coupler is not falsely treated as whole-cargo detach")
 var sim=make_sim(pieces);sim.set_free_flight_input(0,0,false,true,3);sim.step(1.0/120.0)
 check(sim.parts[3].spent and not sim._linked(1,2) and not sim._linked(1,3),"actual accelerator detaches cargo from every socket, including its battery")
 check(sim.status=="failed" and sim.telemetry.free_failure=="usable_energy_empty" and sim.total_energy()>0,"actual out-of-circle cargo immediately fails despite charged detached battery")
 var safe=make_sim(pieces);var at:Vector2=safe.cargo_position()+Vector2(.91,0)
 safe.route.distance=at.x;safe.route.destination_y=at.y;safe.set_free_flight_input(0,0,false,true,3);safe.step(1.0/120.0)
 check(safe.parts[3].spent and safe.status=="success","actual same-step safe capture still wins before zero-energy failure")
func read_only() -> void:
 for kind in ["accelerator","coupler","splitter"]:
  for target in [1,4,999,3,-1]:
   var saved:Dictionary={"design":design(kind,5,target),"launcher":[],"contract":{"control_version":"pilot-free-v1","contract_id":"retained"},"opaque":{"keep":[2.125,72]}}
   var restored:Dictionary=JSON.parse_string(JSON.stringify(saved));selected(restored.design).input_b=71;selected(restored.design).param=2.125
   var before:PackedByteArray=var_to_bytes(restored)
   for version in ["pilot-free-v2","pilot-free-v1",""]:
    for repeat in 3:
     feedback(restored.design,version);Policy.target_options(selected(restored.design),restored.design);Policy.effective_target(selected(restored.design),restored.design);Policy.trigger_text(selected(restored.design),restored.design,true,false,version)
   check(var_to_bytes(restored)==before,"JSON-loaded repeated read-only projections preserve all fields: %s/%d"%[kind,target])
