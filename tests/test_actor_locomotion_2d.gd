extends SceneTree
const Motion=preload("res://scripts/actor_motion_2d.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func make_sprite() -> Sprite2D:
 var s:=Sprite2D.new();root.add_child(s);s.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png");s.centered=false;s.offset=-Vector2(86,248);s.scale=Vector2.ONE*210.0/240.0;return s
func test_stance(kind:String,right:bool) -> void:
 var sprite:=make_sprite();sprite.position=Vector2(350,410)
 var m=Motion.new(sprite,"clerk",210)
 var cycle:float=m.walk_cycle_distance() if kind=="walk" else m.run_cycle_distance()
 var previous:Dictionary={};var max_error:float=0;var comparisons:int=0;var flights:int=0
 var initial:Dictionary=m.debug_snapshot()
 for i in 640:
  var d:float=cycle*(float(i)+.5)/320.0
  sprite.position.x=350+(d if right else -d)
  var ok:bool=m.apply_walk(d,right) if kind=="walk" else m.apply_run(d,right)
  if not ok:check(false,"applies "+kind);break
  var snap:Dictionary=m.debug_snapshot();var points:Dictionary=snap.support_points_world
  if snap.flight:flights+=1
  for id in points:
   check(absf(points[id].y-410)<.001,kind+" supporting sole remains on world floor")
   if previous.has(id):
    max_error=maxf(max_error,points[id].distance_to(previous[id]));comparisons+=1
  previous=points
 check(comparisons>100 and max_error<.001,kind+" "+str(right)+" support stays world-locked across actual distance samples; worst="+str(max_error))
 check((kind=="run" and flights==160) or (kind=="walk" and flights==0),kind+" explicit flight fraction")
 var after:Dictionary=m.debug_snapshot()
 check(initial.texture_load_count==after.texture_load_count and initial.texture_cache_size==after.texture_cache_size,kind+" movement never loads another PNG after binding")
 var d:float=cycle*.22
 m.apply_run(d,right) if kind=="run" else m.apply_walk(d,right)
 var fixed:Dictionary=m.debug_snapshot();var material:Material=sprite.material
 for i in 120:m.apply_run(d,right) if kind=="run" else m.apply_walk(d,right)
 check(m.debug_snapshot()==fixed and sprite.material==material,kind+" paused distance freezes shader/material/frame/support")
 var old_position:Vector2=sprite.position
 m.apply_run(d,not right) if kind=="run" else m.apply_walk(d,not right)
 check(sprite.position==old_position and absf(float(m.debug_snapshot().support_shift))<8,kind+" reversal replants without controller position correction")
 check(m.apply_idle(false) and m.debug_snapshot().pose=="idle" and not m.debug_snapshot().facing_right and not sprite.flip_h,kind+" idle preserves native left-facing standing pose")
 check(sprite.material==null and m.debug_snapshot().support_points_world.is_empty() and not m.debug_snapshot().flight,kind+" idle clears stance deformation and support")
 check(m.debug_snapshot().foot_point.is_equal_approx(sprite.position),kind+" mirrored idle keeps semantic floor origin")
 check(m.apply_gesture("ready",true) and sprite.material==null and m.debug_snapshot().pose=="ready",kind+" tablet remains undeformed")
 m.apply_run(cycle*.1,true);sprite.hide();var frozen:Dictionary=m.debug_snapshot()
 check(not m.apply_run(cycle*.7,false) and m.debug_snapshot()==frozen,kind+" hidden run freezes exact state")
 sprite.show();m.restore_original();check(sprite.material==null and sprite.get_child_count()==0,kind+" restoration owns no extra nodes or retained deformation")
 sprite.free();check(not m.apply_run(0),kind+" run safely rejects freed weak target")
func run() -> void:
 for kind in ["walk","run"]:
  for right in [true,false]:test_stance(kind,right)
 var s:=make_sprite();var m=Motion.new(s,"clerk",210)
 check(not m.apply_run(-1) and not m.apply_run(NAN) and not m.apply_run(INF),"run rejects invalid distance")
 check(m._record.walk.size()==32 and m._record.run.size()==32,"two bounded32-sample raster cycles")
 var warm:Dictionary=m.debug_snapshot()
 for i in 1600:
  m.apply_walk(i*.45,i%2==0);m.apply_run(i*.73,i%2==0);m.apply_idle(i%2==0);m.apply_gesture("ready");m.restore_original()
 var after:Dictionary=m.debug_snapshot()
 check(warm.texture_load_count==after.texture_load_count and warm.texture_cache_size==after.texture_cache_size,"1600walk/run/idle/tablet/restore cycles plateau texture cache")
 check(int(after.texture_cache_size)<=112 and s.get_child_count()==0,"fixed112texture cap and zero added nodes")
 s.free();print("ACTOR LOCOMOTION2D: ",passed," passed, ",failed," failed");quit(1 if failed else 0)
