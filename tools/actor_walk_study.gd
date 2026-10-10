extends SceneTree
## Controlled native renderer study, not gameplay/input or engine-FPS evidence.
## The real process clock drives identical eased paths; the production adapter
## sees only cumulative travelled distance. No --fixed-fps/movie mode is used.
const Motion=preload("res://scripts/actor_motion_2d.gd")
const Npc=preload("res://scripts/npc_sprite_2d.gd")
const Assembly=preload("res://scripts/assembly_2d.gd")
var actors:Array=[]
var age:float=0.0
var live:bool=false
var ruler
var observations:Array=[]
var out:String="res://docs/qa/v5/walk-refinement-native"
var sample_accumulator:float=0.0
func _initialize() -> void:run.call_deferred()
func label_at(text:String,at:Vector2) -> void:
 var label:=Label.new();label.text=text;label.position=at;label.add_theme_font_size_override("font_size",17);root.add_child(label)
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 root.size=Vector2i(1280,900);root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
 var bg:=ColorRect.new();bg.color=Color("16253b");bg.size=Vector2(1280,900);root.add_child(bg)
 label_at("NORMAL-SPEED RASTER GAIT STUDY | real process clock | renderer fixture, not gameplay",Vector2(20,8))
 ruler=Assembly.new()
 var ids:Array=["clerk","clerk","human_courier","elf_archivist","alien_botanist","robot_machinist"]
 for i in ids.size():
  var row:int=i/2;var col:int=i%2;var origin:=Vector2(col*640+110,row*280+292)
  var floorline:=Line2D.new();floorline.width=1.0;floorline.default_color=Color("56738c");floorline.add_point(Vector2(col*640+18,origin.y));floorline.add_point(Vector2(col*640+621,origin.y));root.add_child(floorline)
  label_at(("REFINED CLERK" if i==0 else "HISTORICAL CLERK: 6 drawings / repeated 3 stances") if i<2 else str(ids[i])+" / original four drawings, six beats",Vector2(col*640+20,row*280+39))
  var sprite:Sprite2D
  if i<2:
   sprite=Sprite2D.new();sprite.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png");root.add_child(sprite)
  else:
   sprite=Npc.new();root.add_child(sprite);sprite.configure({"appearance_id":ids[i],"accessory_id":"none"},210)
  sprite.position=origin
  var motion=Motion.new(sprite,ids[i],210)
  if i==1:
   var frames:Array=[]
   for n in 6:frames.append({"runtime":"assets/2d_v5/actors/cooperative/clerk-walk-%02d-pixel.png"%n,"foot_anchor":[96,248],"hip_anchor":[80,151],"body_height":240,"facing":"right","contains_parcel":false})
   motion._record={"walk":frames,"walk_cycle_distance":120}
  motion.apply_walk(0.0,true)
  actors.append({"sprite":sprite,"motion":motion,"origin":origin,"distance":0.0,"last_x":origin.x,"label":ids[i],"historical":i==1})
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out));live=true
func _process(delta:float) -> bool:
 if not live:return false
 age+=delta
 var leg:float=2.5
 var leg_index:int=int(age/leg)
 var leg_age:float=fposmod(age,leg)
 var right:bool=leg_index%2==0
 var travel:float=ruler.sample_transport_x(0.0,400.0,leg_age,leg)
 for a in actors:
  var x:float=a.origin.x+(travel if right else 400.0-travel)
  a.distance+=absf(x-float(a.last_x));a.last_x=x;a.sprite.position.x=x
  a.motion.apply_walk(float(a.distance),right)
 sample_accumulator+=delta
 if sample_accumulator>=1.0/24.0:
  sample_accumulator=0.0
  var sample:Dictionary={"elapsed":age,"actors":[]}
  for a in actors:sample.actors.append({"id":a.label,"historical":a.historical,"x":a.sprite.position.x,"y":a.sprite.position.y,"distance":a.distance,"motion":a.motion.debug_snapshot()})
  observations.append(sample)
 if age>=11.0:
  var f:=FileAccess.open(out+"/gait-study-telemetry.json",FileAccess.WRITE);f.store_string(JSON.stringify({"renderer_fixture":true,"real_process_clock":true,"fixed_fps":false,"speedup":false,"elapsed":age,"samples":observations},"  "));f.close();ruler.free();ruler=null;live=false;quit()
 return false
