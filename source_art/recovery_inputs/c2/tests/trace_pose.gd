extends SceneTree
const Root = preload("res://scripts/shop_locomotion_2d.gd")
const Pose = preload("res://scripts/clerk_rigid_pose_2d.gd")
const Original = preload("res://reference/clerk_rigid_pose_original.gd")
const C1 = preload("res://reference/clerk_rigid_pose_C1r1.gd")
var reference_c1:bool=false
var output:FileAccess
var rows:int=0

func encode(v:Variant) -> Variant:
 if v is Vector2:return [v.x,v.y]
 if v is Dictionary:
  var d:Dictionary={}
  for k in v:d[str(k)]=encode(v[k])
  return d
 if v is Array:
  var a:Array=[]
  for e in v:a.append(encode(e))
  return a
 return v

func emit(model:RefCounted,root:RefCounted,case_id:String,tick:int,clock:float,h:float,stride:float,version:String,extra:Dictionary={}) -> void:
 var row:Dictionary={"case":case_id,"tick":tick,"clock":clock,"height":h,"stride":stride,"version":version,"root":root.snapshot(),"pose":model.snapshot(),"extra":extra}
 output.store_line(JSON.stringify(encode(row),"",false,true));rows+=1

func run_case(data:Dictionary,height:float,stride:float,right:bool,name:String,phase:int,original:bool) -> void:
 var root=Root.new();root.configure(100000.0)
 var start:Vector2=Vector2(2000,496)
 if name=="connector":start=Vector2(440,475)
 root.adopt_position(start);root.facing_right=right;root.set_input(0.0,true)
 var pose=C1.new() if reference_c1 else (Original.new() if original else Pose.new())
 var tune:Dictionary=data.duplicate(true);tune.half_step=stride
 if not pose.configure(tune,height):push_error("configure failed");quit(2);return
 pose.reset(root.position,right,0.0,root.distance)
 var sign_x:float=1.0 if right else -1.0
 var label:String=("R" if right else "L")+"/"+name+"/"+str(phase)
 var version:String="C1r1" if reference_c1 else ("original" if original else "C2")
 var h:float=stride*height/240.0
 var release:float=h*8.0+h*float(phase)/32.0
 var blocked_phase:float=-1.0
 var prev_snap:Dictionary={}
 var freeze_snapshot:Dictionary={}
 var freeze_exact:bool=true
 var owner_events:Array=[]
 for tick in range(1600):
  var clock:float=float(tick)/120.0
  var axis:float=0.0
  if name=="stops":axis=sign_x if root.distance<release else 0.0
  elif name=="reverse":axis=sign_x if clock<2.0 else (-sign_x if clock<4.0 else 0.0)
  elif name=="blocked":axis=sign_x if clock<3.0 else 0.0
  elif name=="interrupt":axis=sign_x if clock<1.5 or (clock>1.8 and clock<3.2) else 0.0
  elif name=="idle":axis=0.0
  elif name=="rest_turn":axis=0.0 if clock<1.0 else (-sign_x if clock<3.0 else 0.0)
  else:axis=sign_x if clock<3.5 else 0.0
  if name=="blocked" and tick==140:root.set_blockers([root.position+Vector2(sign_x*58.01,0)])
  if name=="distance_reset" and tick==180:root.distance=0.0
  var hidden:bool=name=="freeze" and tick>=150 and tick<210
  if not hidden:
   var owner_before:Dictionary=root.snapshot()
   root.set_input(axis,true);root.step(1.0/120.0)
   if root.facing_right!=bool(owner_before.facing_right):
    var crossed:bool=float(owner_before.velocity)*root.velocity<0.0
    var from_rest:bool=absf(float(owner_before.velocity))<0.000001
    owner_events.append({"owner_tick":tick,"from_right":owner_before.facing_right,"to_right":root.facing_right,"velocity_before":owner_before.velocity,"velocity_after":root.velocity,"authorized":crossed or from_rest,"reason":"zero_crossing" if crossed else ("from_rest" if from_rest else "INVALID")})
  if tick%2==0:
   if hidden:
    if tick==150:freeze_snapshot=pose.snapshot()
    pose.freeze(clock,root.distance)
    freeze_exact=freeze_exact and pose.snapshot()==freeze_snapshot
   else:
    if not pose.update(root.state,root.distance,root.position,root.facing_right,clock,root.stop_age,true,false):push_error("update failed");quit(3);return
   var extra:Dictionary={"hidden":hidden,"freeze_exact":freeze_exact,"owner_orientation_events":owner_events.duplicate(true)}
   if name=="blocked" and root.snapshot().blocked:
    if blocked_phase<0.0:blocked_phase=pose.step_fraction
    extra.blocked_phase=blocked_phase
   emit(pose,root,label,tick,clock,height,stride,version,extra)
   prev_snap=pose.snapshot();owner_events.clear()
  if clock>6.0 and name!="stops":break
  if name=="stops" and root.distance>=release and root.state=="idle" and clock>release/155.0+1.6:break

func _initialize() -> void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()<2:push_error("output and suite required");quit(1);return
 output=FileAccess.open(args[0],FileAccess.WRITE)
 if output==null:push_error("output unavailable");quit(1);return
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://contract/candidate-rig-registration-fg01.json"))
 var original:bool=args[1]=="baseline"
 reference_c1=args[1]=="c1r1"
 for height in ([210.0] if original else [120.0,210.0,240.0]):
  for right in [true,false]:
   for stride in ([46.0] if original else [40.0,43.0,46.0]):
    for phase in range(0 if args[1]=="focus" else 32):run_case(data,height,stride,right,"stops",phase,original)
    for name in ["idle","reverse","blocked","interrupt","connector","freeze","distance_reset","rest_turn"]:run_case(data,height,stride,right,name,0,original)
 output.close()
 print(JSON.stringify({"status":"TRACES_COMPLETE","rows":rows,"suite":args[1]}))
 quit(0)
