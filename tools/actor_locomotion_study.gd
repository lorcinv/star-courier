extends SceneTree
## Real-clock native renderer proof at actual gameplay height. No fixed-FPS,
## movie mode, simulation time injection or authored video speedup.
const Motion=preload("res://scripts/actor_motion_2d.gd")
var rows:Array=[]
var age:float=0.0
var live:bool=false
var samples:Array=[]
var sample_age:float=0.0
const OUT:String="res://docs/qa/v5/locomotion-v2-native"
func _initialize() -> void:run.call_deferred()
func label(text:String,at:Vector2) -> Label:
 var l:=Label.new();l.text=text;l.position=at;l.add_theme_font_size_override("font_size",19);root.add_child(l);return l
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 root.size=Vector2i(1280,720);root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
 var bg:=ColorRect.new();bg.color=Color("182538");bg.size=Vector2(1280,720);root.add_child(bg)
 label("PURE2D RASTER LOCOMOTION | actual210px height | real process clock | stop and reverse",Vector2(18,12))
 for i in 2:
  var y:float=342.0+330.0*i
  var floorline:=Line2D.new();floorline.width=1;floorline.default_color=Color("607a91");floorline.add_point(Vector2(20,y));floorline.add_point(Vector2(1260,y));root.add_child(floorline)
  for x in range(50,1250,50):
   var tick:=Line2D.new();tick.width=1;tick.default_color=Color("49647b");tick.add_point(Vector2(x,y));tick.add_point(Vector2(x,y+7));root.add_child(tick)
  var s:=Sprite2D.new();root.add_child(s);s.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png");s.centered=false;s.offset=-Vector2(86,248);s.scale=Vector2.ONE*210/240;s.position=Vector2(110,y)
  var m=Motion.new(s,"clerk",210)
  var l:=label("",Vector2(24,61+330*i))
  rows.append({"sprite":s,"motion":m,"distance":0.0,"speed":155.0 if i==0 else 300.0,"gait":"walk" if i==0 else "run","label":l,"facing":true})
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));live=true
func _process(delta:float) -> bool:
 if not live:return false
 age+=delta
 var lap:float=fposmod(age,5.0)
 var moving:bool=lap<2.0 or (lap>=2.5 and lap<4.5)
 var right:bool=lap<2.5
 for a in rows:
  if moving:
   var dx:float=float(a.speed)*delta*(1 if right else -1)
   a.sprite.position.x+=dx;a.distance+=absf(dx);a.facing=right
   if a.gait=="walk":a.motion.apply_walk(a.distance,right)
   else:a.motion.apply_run(a.distance,right)
  else:a.motion.apply_idle(a.facing)
  var snap:Dictionary=a.motion.debug_snapshot()
  a.label.text=("WALK155px/s" if a.gait=="walk" else "RUN300px/s")+" | "+str(snap.pose)+" | "+("right" if a.facing else "left")+" | sample"+str(snap.frame_index)+(" | FLIGHT" if snap.flight else "")
 sample_age+=delta
 if sample_age>=1.0/60.0:
  sample_age=0
  var r:Dictionary={"elapsed":age,"rows":[]}
  for a in rows:r.rows.append({"gait":a.gait,"distance":a.distance,"position":a.sprite.position,"motion":a.motion.debug_snapshot()})
  samples.append(r)
 if age>=10.5:
  var f:=FileAccess.open(OUT+"/telemetry.json",FileAccess.WRITE);f.store_string(JSON.stringify({"real_process_clock":true,"fixed_fps":false,"speedup":false,"height":210,"samples":samples},"  "));f.close();live=false;quit()
 return false
