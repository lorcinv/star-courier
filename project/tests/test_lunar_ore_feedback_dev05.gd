extends SceneTree
## Synthetic presentation tests only. They do not alter a gameplay fixture,
## establish drill attribution, or replace the required native visual pass.
const Feedback=preload("res://scripts/lunar_ore_feedback_v2.gd")
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Presenter=preload("res://scripts/lunar_outpost_presentation_2d.gd")
var passed:int=0
var failed:int=0

class VisualFixture extends RefCounted:
 var elapsed:float=12.0
 var position:Vector2=Vector2(85.0,-15.0)
 var status:String="running"
 var paused:bool=false
 var obstacles:Array=[]
 func cargo_position() -> Vector2:return position

func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func route() -> Dictionary:return Profile.route(Content.fresh_catalog())

func rocks() -> Array:
 var result:Array=[]
 for raw in Content.HAZARDS:
  var h:Dictionary=raw.duplicate(true);h.position=Vector2(h.x,h.y)
  h.velocity=Vector2(float(h.velocity[0]),float(h.velocity[1])) if h.has("velocity") else Vector2.ZERO
  result.append(h)
 return result

func _initialize() -> void:run.call_deferred()

func run() -> void:
 transitions();clock_boundaries();bounded_and_read_only();presentation()
 print("LUNAR_ORE_FEEDBACK_DEV05 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)

func transitions() -> void:
 var observer=Feedback.new();var data:Array=rocks()
 check(observer.configure(route()),"exact new lunar route enables feedback")
 observer.observe(1,10.0,data)
 check(observer.frame().is_empty(),"first live observation does not manufacture a hit")
 data[0].health-=1.0;observer.observe(1,10.01,data)
 var hit:Array=observer.frame()
 check(hit.size()==1 and hit[0].hit_strength==1.0 and hit[0].label_alpha==0.0,"actual nonlethal ore HP loss starts a warm flash only")
 data[0].health-=1.0;observer.observe(1,10.02,data)
 check(observer.frame()[0].hit_strength<hit[0].hit_strength,"next 120 Hz damage sample does not restart the flash")
 for tick in range(3,24):
  data[0].health-=.1;observer.observe(1,10.0+float(tick)/120.0,data)
 check(observer.frame().is_empty(),"continuous contact flash expires instead of remaining bright")
 data[0].health-=1.0;observer.observe(1,10.5,data)
 check(observer.frame()[0].hit_strength==1.0,"further actual loss may flash after the bounded cooldown")
 data[0].health=0.0;observer.observe(1,10.51,data)
 var broken:Array=observer.frame()
 check(broken.size()==1 and broken[0].hit_strength==0.0 and broken[0].burst_alpha==1.0 and broken[0].label_alpha==1.0,"positive-to-zero HP produces one raster break and a local receipt")
 check(broken[0].position==data[0].position,"break anchors to the real observed ore position")
 data[0].health=-4.0;observer.observe(1,10.6,data)
 check(observer.frame()[0].burst_alpha<1.0,"already-dead ore cannot restart its break")
 observer.observe(1,12.2,data)
 check(observer.frame().is_empty() and observer.debug_snapshot().cue_count==0,"burst and label fully expire without accumulated effect records")
 data[1].health=-1.0;observer.observe(1,12.3,data)
 check(observer.frame().size()==1 and observer.frame()[0].id==Feedback.ORE_IDS[1],"impact-only death works without any drill sparks or drill telemetry")
 data[2].health=0.0;observer.observe(1,14.0,data)
 check(observer.frame().is_empty(),"drifter death never claims one of the two authored ores")

func clock_boundaries() -> void:
 var observer=Feedback.new();var data:Array=rocks();observer.configure(route())
 data[0].health=0.0;observer.observe(1,8.0,data)
 check(observer.frame().is_empty(),"Continue at already-broken health starts quietly")
 observer.configure(route());data=rocks();observer.observe(1,10.0,data)
 data[0].health=0.0;observer.observe(1,10.0,data)
 check(observer.frame().is_empty(),"same-time HP change cannot earn a fresh break")
 observer.observe(1,10.1,data)
 check(observer.frame().is_empty(),"same-time change establishes baseline so unpause does not backfill a break")
 data[0].health=42.0;observer.observe(1,10.2,data)
 data[0].health=0.0;observer.observe(1,10.3,data)
 var earned:PackedByteArray=var_to_bytes(observer.frame())
 check(not observer.frame().is_empty(),"final advancing step earns its break before a paused draw")
 for draw in 120:observer.observe(1,10.3,data)
 check(var_to_bytes(observer.frame())==earned,"repeated paused draws preserve an earned cue exactly")
 data[0].position+=Vector2(-10.0,0.0);observer.observe(1,10.3,data)
 check(var_to_bytes(observer.frame())==earned,"same-time position changes neither restart nor move an already earned break")
 observer.observe(1,9.0,data)
 check(observer.frame().is_empty(),"time reversal clears transient effects and primes current health")
 data[1].health=0.0;observer.observe(2,20.0,data)
 check(observer.frame().is_empty(),"replacement simulation never inherits the old observer’s health delta")
 observer.configure(route());data=rocks();observer.observe(2,20.0,data)
 data[0].position.x-=100.0;observer.observe(2,20.1,data)
 check(observer.frame().is_empty(),"reverse flight or camera travel without health loss causes no feedback")
 observer.observe(2,NAN,data);data[0].health=0.0;observer.observe(2,20.2,data)
 check(observer.frame().is_empty(),"invalid clock invalidates its baseline instead of causing a later false burst")
 var old:Dictionary=route();old.control_version="pilot-v3"
 check(not observer.configure(old),"old protocol cannot enable the new lunar feedback")
 observer.observe(2,20.3,data)
 check(observer.frame().is_empty() and observer.debug_snapshot().tracked_ores==0,"old route retains no health or cue state")
 observer.configure(route());data=rocks();observer.observe(-9223370000000000001,20.0,data)
 data[0].health=0.0;observer.observe(-9223370000000000001,20.1,data)
 check(observer.frame().size()==1,"signed high-bit RefCounted instance identity is a valid simulation owner")

func bounded_and_read_only() -> void:
 var observer=Feedback.new();var current:Dictionary=route();var data:Array=rocks()
 var frozen:PackedByteArray=var_to_bytes([current,data])
 observer.configure(current);observer.observe(2,0.0,data)
 for tick in 1000:
  observer.observe(2,float(tick)/120.0,data);observer.frame();observer.debug_snapshot()
 check(var_to_bytes([current,data])==frozen,"repeated presentation reads preserve route and physical obstacle bytes")
 data[0].health=0.0;data[1].health=-2.0;observer.observe(2,10.0,data)
 check(observer.frame().size()==2 and observer.debug_snapshot().cue_count==2,"simultaneous ore deaths use exactly the two bounded slots")
 var frame:Array=observer.frame();frame[0].position=Vector2(999,999);frame.clear()
 check(observer.frame()[0].position==data[0].position,"returned presentation snapshots cannot mutate stored anchors")
 var bounded:bool=true
 for tick in 1000:
  observer.observe(2,10.0+float(tick)/120.0,data)
  bounded=bounded and observer.debug_snapshot().tracked_ores<=Feedback.MAX_ORES and observer.debug_snapshot().cue_count<=Feedback.MAX_ORES
 check(bounded,"state remains bounded across 1000 subsequent samples")
 observer.clear()
 check(observer.frame().is_empty() and observer.debug_snapshot().tracked_ores==0,"leaving clears all retained ore samples")

func presentation() -> void:
 var host:Node2D=Node2D.new();root.add_child(host)
 var world:Node2D=Node2D.new();host.add_child(world)
 var presenter=Presenter.new();host.add_child(presenter)
 var model:VisualFixture=VisualFixture.new();model.obstacles=rocks()
 check(presenter.configure_route(route(),world,Vector2(30,40),72.0),"presenter configures the exact lunar successor")
 presenter.update_from_sim(model,.52,model.position)
 check(presenter._ore_nodes.size()==2 and presenter._props.get_child_count()==9,"fixed presentation adds only two raster/label pairs")
 check(presenter.debug_snapshot().ore_feedback.frame.is_empty(),"initial paused native-style sample remains quiet")
 var state_before:PackedByteArray=var_to_bytes([model.elapsed,model.obstacles,model.position,model.status])
 for draw in 50:presenter.update_from_sim(model,.52,model.position)
 check(var_to_bytes([model.elapsed,model.obstacles,model.position,model.status])==state_before,"rendering never edits the simulation-shaped input")
 model.elapsed+=.01;model.obstacles[0].health-=1.0;presenter.update_from_sim(model,.52,model.position)
 var nodes:Dictionary=presenter._ore_nodes[Feedback.ORE_IDS[0]]
 check(nodes.rock.modulate!=Color.WHITE and not nodes.burst.visible and not nodes.label.visible,"nonlethal damage only warms the existing raster art")
 model.elapsed+=.01;model.obstacles[0].health=0.0;model.paused=true
 presenter.update_from_sim(model,.52,model.position)
 check(not nodes.rock.visible and nodes.burst.visible and nodes.label.visible,"last advancing step still paints the break when the first draw is paused")
 check(nodes.label.text=="矿石已破碎" and nodes.burst.texture.resource_path=="res://assets/2d_v5/flight/impact.png","generic cause-neutral text and original generated impact raster only")
 var point:Vector2=Vector2(30,40)+model.obstacles[0].position*72.0
 check(nodes.burst.position==point,"raster burst uses true world-space break anchor")
 var alpha:float=nodes.burst.modulate.a;var cue_before:PackedByteArray=var_to_bytes(presenter._ore_feedback.frame())
 for zoom in [.35,.52,.8]:
  presenter.update_from_sim(model,zoom,model.position-Vector2(50,0))
  check(nodes.burst.modulate.a==alpha and var_to_bytes(presenter._ore_feedback.frame())==cue_before,"paused camera/zoom changes preserve the earned cue")
  check(is_equal_approx(nodes.burst.scale.x*float(nodes.burst.texture.get_width())*zoom,112.0),"raster cue has bounded screen-space size")
  check(is_equal_approx(nodes.label.scale.x*zoom,1.0),"local label remains screen-readable")
 model.elapsed+=1.7;presenter.update_from_sim(model,.52,model.position)
 check(not nodes.burst.visible and not nodes.label.visible,"local feedback ends without leaving permanent help text")
 for repeat in 8:
  presenter.configure_route(route(),world,Vector2.ZERO,72.0);presenter.update_from_sim(model,.52,model.position)
  check(presenter._props.get_child_count()==9 and presenter._ore_feedback.frame().is_empty(),"Continue/reconfigure stays bounded and never replays the prior break")
 var replacement:VisualFixture=VisualFixture.new();replacement.elapsed=model.elapsed+5.0;replacement.obstacles=rocks();replacement.obstacles[1].health=0.0
 presenter.update_from_sim(replacement,.52,replacement.position)
 check(presenter._ore_feedback.frame().is_empty(),"presentation simulator replacement primes without a cue")
 presenter.leave_flight()
 check(world.get_child_count()==0 and presenter.get_child_count()==0 and presenter._ore_nodes.is_empty(),"leave frees every added node and tracker sample")
 host.free()
