extends SceneTree
## Bounded read-only preview checks using the actual current v8 adapter.
## No saves, route changes, alternate launch formula or runtime overlays.
const Sim=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
const Launcher=preload("res://scripts/launcher_v3.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
var passed:int=0
var failed:int=0

func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func part(id:int,kind:String,x:int,y:int=0,param:float=0.0)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":param,"input_a":-1,"input_b":-1,"target":-1}

func make(pad:Array):
 var sim=Sim.new()
 sim.configure(Profile.starter_design(),pad,Profile.route({"weight":1.0}),42)
 return sim

func limited_pad(offset:int=0,first_id:int=2001,spring:float=60.0)->Array:
 return [part(first_id,"battery",offset,0,300),part(first_id+1,"spring",offset+1,0,spring),part(first_id+2,"spring",offset+1,1,spring),part(first_id+3,"beam",offset,1,32)]

func cells(sim,energy:float)->void:
 for p in sim.launcher_parts:
  if p.type=="battery":p.energy=energy

func state_bytes(sim)->PackedByteArray:
 return var_to_bytes([sim.parts,sim.launcher_parts,sim.bodies,sim.links,sim.telemetry,sim.events,sim.effects,sim.launch_released,sim.status])

func preview(sim,power:float=1.0)->Dictionary:
 var before:PackedByteArray=state_bytes(sim)
 var result:Dictionary=sim.preview_launcher(35.0,power)
 check(state_bytes(sim)==before,"actual v8 preview leaves live state unchanged")
 return result

func release_matches(sim,snapshot:Dictionary)->void:
 var expected:Dictionary=snapshot.duplicate(true)
 expected.erase("group_limits");expected.released=true;expected.can_release=false
 var result:Dictionary=sim.release_launcher(snapshot.angle_degrees,snapshot.power_fraction)
 check(var_to_bytes(result)==var_to_bytes(expected),"release retains all original output keys and exact preview values")
 check(sim.body_for_part(1).velocity.distance_to(snapshot.velocity)<0.00001 and sim.telemetry.launch_energy_drawn==snapshot.energy_used,"actual release velocity and bill match shown values within Vector2 roundoff")
 var before:PackedByteArray=state_bytes(sim)
 var repeated:Dictionary=sim.release_launcher(snapshot.angle_degrees,snapshot.power_fraction)
 check(not repeated.can_release and not repeated.has("group_limits") and state_bytes(sim)==before,"repeat release remains a no-op without observational output keys")

func _initialize()->void:
 var sim=make(Launcher.starter_launcher());var first:Dictionary=preview(sim)
 check(sim.status=="running" and sim.route.control_version=="pilot-delivery-v8","actual current v8 adapter accepts the fixture")
 check(first.group_limits.size()==1 and not first.has("components"),"only safe per-group summaries escape the plan")
 var group:Dictionary=first.group_limits[0]
 check(group=={"group_id":1001,"capacity":240.0,"desired":240.0,"supported":256.0,"available":6000.0,"used":240.0,"limits":["capacity"]},"default motor capacity explains 6000J available versus 240J used")
 check(first.group_limits.is_read_only() and group.is_read_only() and group.limits.is_read_only(),"array dictionary and tied-source list are immutable")
 var copy:String=UI.launch_copy(first,{"angle_degrees":35.0,"power_fraction":1.0})
 check(copy.ends_with("动力上限 240 J · 动力已用满") and copy.split("\n").size()==3 and first.warning.is_empty(),"default explanation is one extra short line with no warning")
 var low:Dictionary=preview(sim,.2)
 check(low.group_limits[0].capacity==240.0 and low.group_limits[0].desired==48.0 and low.group_limits[0].limits==["power"],"low power names the actual request rather than the full capacity")
 check(UI.launch_limits_copy(low)=="动力上限 240 J · 力度请求 48 J","low-power copy does not falsely claim the motors are full")
 var zero:Dictionary=preview(sim,0.0)
 check(zero.group_limits[0].limits==["power"] and zero.energy_used==0.0 and not "已用满" in UI.launch_limits_copy(zero),"zero power is not a motor ceiling")
 release_matches(sim,first)
 check(group.available==6000.0 and group.used==240.0,"release cannot mutate an earlier immutable summary")

 sim=make(limited_pad());var support:Dictionary=preview(sim)
 check(support.group_limits[0].capacity==120.0 and support.group_limits[0].supported==64.0 and support.group_limits[0].used==64.0 and support.group_limits[0].limits==["support"],"real connected support bottleneck uses the existing plan work")
 check(support.support_limited and support.warning.begins_with("支撑承载") and UI.launch_limits_copy(support)=="动力上限 120 J","existing support warning is not repeated in the numbers")
 release_matches(sim,support)

 sim=make(limited_pad());cells(sim,30.0);var energy:Dictionary=preview(sim)
 check(energy.group_limits[0].available==30.0 and energy.group_limits[0].used==30.0 and energy.group_limits[0].limits==["energy"],"actual residual cell energy sets the per-group output")
 check(energy.energy_limited and energy.warning.begins_with("台上电量") and UI.launch_limits_copy(energy)=="动力上限 120 J","existing energy warning is not repeated in the numbers")
 release_matches(sim,energy)

 sim=make(limited_pad());cells(sim,64.0);var equal_bounds:Dictionary=preview(sim)
 check(equal_bounds.group_limits[0].desired==120.0 and equal_bounds.energy_used==64.0 and equal_bounds.group_limits[0].limits==["support","energy"],"equal support and energy bounds both constrain the higher actual request")
 check(not equal_bounds.support_limited and not equal_bounds.energy_limited and equal_bounds.warning.is_empty() and UI.launch_limits_copy(equal_bounds).ends_with("并列限制：支撑 / 电量"),"tie copy fills the existing warning gap without changing legacy booleans")

 sim=make(limited_pad(0,2001,32.0));cells(sim,64.0);var tied:Dictionary=preview(sim)
 check(tied.group_limits[0].limits==["capacity","support","energy"] and not tied.support_limited and not tied.energy_limited,"all three exact ties are visible without changing legacy warning booleans")
 check(UI.launch_limits_copy(tied).ends_with("并列限制：动力 / 支撑 / 电量"),"tied bounds never claim a single upgrade will raise output")
 cells(sim,32.0);tied=preview(sim,.5)
 check(tied.group_limits[0].limits==["power","energy"] and UI.launch_limits_copy(tied).ends_with("并列限制：力度 / 电量"),"low-power ties retain both the setting and cell bound")

 var pad:Array=limited_pad(0,2001,30.0)+limited_pad(10,3001)+[part(4001,"battery",30,0,300)]
 sim=make(pad)
 for p in sim.launcher_parts:
  if p.id==3001:p.energy=30.0
 var split:Dictionary=preview(sim)
 check(split.group_limits.size()==2 and split.group_limits[0].limits==["capacity"] and split.group_limits[1].limits==["energy"],"disconnected groups retain their different limiting sources")
 check(split.energy_used==90.0 and split.available_energy==6030.0 and split.group_limits[1].used==30.0,"neither spare disconnected cell nor first-group excess supplies the second group")
 copy=UI.launch_limits_copy(split)
 check(copy=="2组独立 · 各组动力上限 60–120 J\n各组瓶颈不同：动力 / 电量" and not "180" in copy,"multi-group copy shows a range rather than a transferable capacity sum")
 release_matches(sim,split)
 var earlier:PackedByteArray=var_to_bytes(split.group_limits)
 cells(sim,1.0)
 check(var_to_bytes(split.group_limits)==earlier,"live cell edits cannot alter a previously returned summary")
 var old:Dictionary=first.duplicate(true);old.erase("group_limits")
 check(UI.launch_copy(old,{"angle_degrees":35.0,"power_fraction":1.0}).split("\n").size()==2,"older snapshots keep their previous two-line copy")
 check(UI.launch_copy(first,{"angle_degrees":35.0,"power_fraction":.2})=="发射预览待更新","stale settings do not display a new or old explanation")
 var bad:Dictionary=first.duplicate(true);bad.group_limits=[{"capacity":INF}]
 check(UI.launch_limits_copy(bad).is_empty(),"invalid optional summary cannot fabricate a bound")
 print("LAUNCHER_LIMITS_DEV33 passed=%d failed=%d"%[passed,failed])
 quit(1 if failed else 0)
