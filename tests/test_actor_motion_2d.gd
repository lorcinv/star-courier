extends SceneTree
## Actual-raster component integration; fails, rather than substituting idle,
## when motion manifests or textures have not been delivered/imported.
const Motion=preload("res://scripts/actor_motion_2d.gd")
const Npc=preload("res://scripts/npc_sprite_2d.gd")
const ACCESSORIES:Dictionary={"human_courier":["none"],"elf_archivist":["book_pouch","map_case"],"alien_botanist":["seed_pod","field_vial"],"robot_machinist":["tool_pack","power_cell"]}
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func point(v:Array) -> Vector2:return Vector2(float(v[0]),float(v[1]))
func distance_for_frame(data:Dictionary,index:int,height:float) -> float:
 var sequence:Array=data.get("walk_sequence",[])
 var weights:Array=data.get("walk_phase_weights",[])
 if sequence.is_empty():
  return (float(index)+0.5)/data.walk.size()*float(data.walk_cycle_distance)*height/float(data.get("walk_reference_height",height))
 var total:float=0.0
 for i in sequence.size():total+=float(weights[i]) if not weights.is_empty() else 1.0
 var before:float=0.0
 for i in sequence.size():
  var weight:float=float(weights[i]) if not weights.is_empty() else 1.0
  if int(sequence[i])==index:return (before+weight*.5)/total*float(data.walk_cycle_distance)*height/float(data.get("walk_reference_height",height))
  before+=weight
 return -1.0
func actual_records() -> Dictionary:
 var result:Dictionary={}
 for path in Motion.MANIFEST_PATHS:
  check(FileAccess.file_exists(path),"required actual motion manifest exists: "+path)
  if not FileAccess.file_exists(path):continue
  var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
  if data is Dictionary:result.merge(data.get("actors",{}))
 return result
func test_clerk(records:Dictionary) -> void:
 var sprite:=Sprite2D.new();root.add_child(sprite)
 sprite.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png")
 sprite.centered=false;sprite.offset=-Vector2(86,248);sprite.scale=Vector2.ONE*210.0/240.0;sprite.position=Vector2(276,486)
 sprite.set_meta("pose","idle");sprite.set_meta("art_id","original-clerk")
 var before:Dictionary={"texture":sprite.texture,"offset":sprite.offset,"scale":sprite.scale}
 var motion=Motion.new(sprite,"clerk",210)
 check(motion.debug_snapshot().available,"actual clerk motion manifest registered")
 if not records.has("clerk"):sprite.free();return
 var data:Dictionary=records.clerk
 var paths:Dictionary={}
 for i in data.walk.size():
  for right in [true,false]:
   check(motion.apply_walk(distance_for_frame(data,i,210.0),right),"clerk actual walk frame applies "+str(i)+"/"+str(right))
   var snap:Dictionary=motion.debug_snapshot();paths[sprite.texture.resource_path]=true
   check(snap.frame_index==i and snap.facing_right==right,"distance selects exact clerk frame and facing")
   check(snap.foot_point.is_equal_approx(sprite.position),"clerk mirrors around semantic feet")
   check(sprite.scale.is_equal_approx(Vector2.ONE*210.0/float(data.walk[i].body_height)),"clerk uses uniform anatomical height")
   check(sprite.texture.resource_path=="res://"+str(data.walk[i].runtime),"clerk uses actual declared raster")
   var captured:Texture2D=sprite.texture;var offset_before:Vector2=sprite.offset
   for repeat in 12:motion.apply_walk(distance_for_frame(data,i,210.0),right)
   check(sprite.texture==captured and sprite.offset==offset_before,"fixed caller distance freezes clerk cadence")
 check(paths.size()==data.walk.size(),"clerk walk uses distinct frame textures, never idle stand-in")
 for gesture in ["reach","align","ready"]:
  check(motion.apply_gesture(gesture,false),"clerk actual gesture applies: "+gesture)
  check(motion.debug_snapshot().foot_point.is_equal_approx(sprite.position),"gesture feet remain registered: "+gesture)
  check(data.gestures[gesture].contains_parcel==false,"tablet help gesture contains no painted parcel: "+gesture)
 sprite.rotation=0.37;sprite.skew=0.09;motion.apply_walk(42,false)
 check(motion.debug_snapshot().foot_point.is_equal_approx(sprite.position),"mirror registration respects full parent-local transform")
 sprite.rotation=0;sprite.skew=0
 motion.restore_original()
 check(sprite.texture==before.texture and sprite.offset==before.offset and sprite.scale==before.scale and not sprite.flip_h,"clerk restores exact original raster and registration")
 check(sprite.get_meta("pose")=="idle" and sprite.get_meta("art_id")=="original-clerk" and not motion.is_active(),"clerk cancel restores original metadata")
 motion.apply_walk(25,false);sprite.hide();var frozen:Texture2D=sprite.texture
 check(not motion.apply_walk(95,true) and sprite.texture==frozen and not sprite.visible,"hidden clerk freezes without forcing visibility")
 sprite.show();motion.restore_original()
 check(not motion.apply_walk(-1) and not motion.apply_walk(INF) and not motion.apply_walk(NAN),"invalid distance rejected")
 check(not motion.apply_gesture("missing") and sprite.texture==before.texture,"missing gesture reports failure without relabeling idle")
 var snap_before:Dictionary=motion.debug_snapshot()
 for i in 1000:
  motion.apply_walk(float(i%120),i%2==0);motion.apply_gesture("ready",i%2==0);motion.restore_original()
 var snap_after:Dictionary=motion.debug_snapshot()
 check(snap_before.texture_cache_size==snap_after.texture_cache_size and snap_before.texture_load_count==snap_after.texture_load_count,"1000 canceled clerk cycles reuse cached resources")
 check(sprite.get_child_count()==0,"clerk adapter creates no nodes")
 # Retaining an adapter must not retain a freed Sprite2D or crash on cancellation.
 sprite.free();motion.restore_original()
 check(not motion.apply_walk(0),"released sprite is weakly held and safely rejected")
func test_npcs(records:Dictionary) -> void:
 var actor=Npc.new();root.add_child(actor);actor.position=Vector2(190,488)
 var child_id:int=0
 for id in ACCESSORIES:
  check(records.has(id),"actual customer motion exists: "+id)
  if not records.has(id):continue
  var data:Dictionary=records[id]
  for accessory in ACCESSORIES[id]:
   var saved:Dictionary={"appearance_id":id,"species":Npc.APPEARANCE_SPECIES[id],"accessory_id":accessory,"appearance_seed":29}
   var original_saved:String=JSON.stringify(saved)
   check(actor.configure(saved),"NPC original identity configures: "+id+"/"+accessory)
   var original:Dictionary={"texture":actor.texture,"offset":actor.offset,"scale":actor.scale,"foot":actor.debug_snapshot().foot_anchor,"parcel":actor.parcel_point()}
   var seen:Dictionary={}
   for i in data.walk.size():
    for right in [false,true]:
     check(actor.set_walk(distance_for_frame(data,i,Npc.DEFAULT_HEIGHT),right),"NPC actual walk applies: "+id+"/"+accessory+"/"+str(i)+"/"+str(right))
     var snap:Dictionary=actor.debug_snapshot();seen[actor.texture.resource_path]=true
     check(snap.motion.frame_index==i and snap.foot_point.is_equal_approx(actor.position),"NPC exact cadence and semantic foot pivot")
     check(not actor.pose_contains_parcel(),"walk never claims painted handoff parcel")
     check(actor.parcel_point().is_equal_approx(original.parcel),"motion preserves original handoff transfer-point semantics")
     check(actor.binding_snapshot()==saved and JSON.stringify(saved)==original_saved,"motion never mutates identity/accessory/seed/binding")
     if accessory!="none":
      var child:Sprite2D=actor.get_node("CompatibleAccessory")
      if child_id==0:child_id=child.get_instance_id()
      var adata:Dictionary=actor._accessory_data;var mount:Vector2=point(data.walk[i].hip_anchor);var local:Vector2=point(adata.local_anchor)
      var expected:Vector2=Vector2(float(actor.texture.get_width())-mount.x if actor.flip_h else mount.x,mount.y)+actor.offset
      var anchor_local:Vector2=Vector2(float(child.texture.get_width())-local.x if child.flip_h else local.x,local.y)+child.offset
      check(child.visible and child.flip_h==(not right) and child.position.is_equal_approx(expected),"compatible accessory uses per-frame hip with consistent mirror")
      check(anchor_local.is_equal_approx(Vector2.ZERO) and child.scale==Vector2.ONE,"accessory local attachment remains registered without scaling head/body")
      check(child.get_instance_id()==child_id and actor.get_child_count()==1,"every motion frame reuses original sole accessory child")
   check(seen.size()==data.walk.size(),"customer walk textures are genuinely distinct: "+id)
   for right in [true,false]:
    check(actor.set_gesture("farewell",right),"NPC real farewell applies: "+id)
    check(not actor.pose_contains_parcel() and actor.pose=="farewell","farewell has no handoff parcel semantic")
    check(actor.debug_snapshot().foot_point.is_equal_approx(actor.position),"farewell mirrors around registered feet")
   actor.set_pose(false)
   check(actor.texture==original.texture and actor.offset==original.offset and actor.scale==original.scale and not actor.flip_h and actor.debug_snapshot().foot_anchor==original.foot,"reversed farewell restores exact original idle registration")
   actor.set_walk(35,false);actor.set_pose(true)
   check(actor.pose=="handoff" and not actor.flip_h and actor.debug_snapshot().foot_anchor==original.foot,"reversed walk restores original handoff registration")
   check(actor.pose_contains_parcel()==(id!="human_courier"),"only original nonhuman handoff owns parcel pixels")
   actor.set_pose(false)
   actor.hide();var before:Texture2D=actor.texture
   check(not actor.set_walk(84,false) and actor.texture==before and not actor.visible,"hidden NPC motion is frozen")
   actor.show()
 # No global RNG consumption: animation leaves the next simulation random draw.
 actor.configure({"appearance_id":"elf_archivist","accessory_id":"map_case"})
 seed(712);var expected_rng:int=randi();seed(712)
 for i in 60:actor.set_walk(float(i),i%2==0);actor.set_pose(false)
 check(randi()==expected_rng,"motion and cancellation never consume global RNG")
 var warmed:Dictionary=actor.debug_snapshot().motion
 var bounded:bool=true
 for i in 1200:
  var ids:Array=ACCESSORIES.keys();var id:String=ids[i%4]
  actor.configure({"appearance_id":id,"accessory_id":ACCESSORIES[id][i%ACCESSORIES[id].size()],"appearance_seed":i})
  actor.set_walk(float(i%120),i%2==0);actor.set_pose(i%3==0)
  bounded=bounded and actor.get_child_count()<=1 and actor.debug_snapshot().foot_point.is_equal_approx(actor.position)
 var after:Dictionary=actor.debug_snapshot().motion
 check(bounded,"1200 reconfigure/walk/cancel cycles keep at most one accessory and no foot drift")
 check(warmed.get("texture_load_count")==after.get("texture_load_count") and warmed.get("texture_cache_size")==after.get("texture_cache_size"),"canceled/reconfigured NPC cycles do not grow shared cache")
 check(int(after.get("manifest_load_count",0))==2 and int(after.get("texture_cache_size",999))<=Motion.MAX_CACHE_TEXTURES,"motion manifests load once each and cache has explicit hard bound")
 actor.free()
func test_invalid_art() -> void:
 var sprite:=Sprite2D.new();root.add_child(sprite)
 sprite.texture=load("res://assets/2d_v5/actors/clerk-idle-pixel.png")
 var before:Texture2D=sprite.texture
 var motion=Motion.new(sprite,"clerk",210)
 if motion._record.is_empty():sprite.free();return
 motion._record=motion._record.duplicate(true)
 motion._record.walk[0].runtime="assets/2d_v5/actors/cooperative/does-not-exist.png"
 check(not motion.apply_walk(0) and sprite.texture==before and not motion.is_active(),"missing motion raster fails explicitly, never pretends idle is animation")
 motion._record.walk[0].runtime="assets/2d_v5/actors/clerk-idle-pixel.png"
 motion._record.walk[0].contains_parcel=true
 check(not motion.apply_walk(0) and sprite.texture==before,"parcel-containing metadata is rejected for walk/farewell adapter")
 motion._record.walk[0].contains_parcel=false;motion._record.walk[0].foot_anchor=[-100,248]
 check(not motion.apply_walk(0),"out-of-texture semantic foot is rejected")
 check(not motion.debug_snapshot().diagnostics.is_empty(),"fallback diagnostics are inspectable")
 sprite.free()
func test_distance_phase_contract(records:Dictionary) -> void:
 for id in Motion.ACTOR_IDS:
  var small:=Sprite2D.new();var large:=Sprite2D.new();root.add_child(small);root.add_child(large)
  var a=Motion.new(small,id,120);var b=Motion.new(large,id,240)
  var data:Dictionary=records[id]
  check(is_equal_approx(b.walk_cycle_distance(),2*a.walk_cycle_distance()),id+" stride follows anatomical display height")
  var sequence:Array=data.walk_sequence;var weights:Array=data.walk_phase_weights
  var total:float=0.0
  for w in weights:total+=float(w)
  var accumulated:float=0.0
  for phase in sequence.size():
   var weight:float=float(weights[phase]);var fraction:float=(accumulated+weight*.5)/total
   a.apply_walk(a.walk_cycle_distance()*fraction,false);b.apply_walk(b.walk_cycle_distance()*fraction,true)
   check(a.debug_snapshot().frame_index==int(sequence[phase]) and b.debug_snapshot().frame_index==int(sequence[phase]),id+" exact weighted phase at both heights "+str(phase))
   check(a.debug_snapshot().walk_phase==phase and is_equal_approx(float(a.debug_snapshot().walk_phase_fraction),.5),id+" reports finite phase progress "+str(phase))
   check(a.debug_snapshot().foot_point.is_equal_approx(small.position) and b.debug_snapshot().foot_point.is_equal_approx(large.position),id+" supporting floor never receives a bob offset")
   accumulated+=weight
  var paused:Dictionary=a.debug_snapshot();var held:Texture2D=small.texture
  small.hide();check(not a.apply_walk(0,true) and a.debug_snapshot().walk_phase==paused.walk_phase and small.texture==held,id+" hidden actor freezes frame and phase")
  small.show();var frozen_distance:float=a.walk_cycle_distance()*.37;a.apply_walk(frozen_distance,false);var stable:Dictionary=a.debug_snapshot()
  for repeat in 120:a.apply_walk(frozen_distance,false)
  check(a.debug_snapshot()==stable,id+" repeated paused distance has no autonomous drift")
  a.apply_walk(frozen_distance+a.walk_cycle_distance()*24,false)
  check(a.debug_snapshot().frame_index==stable.frame_index and absf(float(a.debug_snapshot().walk_phase_fraction)-float(stable.walk_phase_fraction))<.0001,id+" cycles depend on travelled distance without history")
  a._record=a._record.duplicate(true);a._record.walk_sequence=[0,1,99]
  check(not a.apply_walk(0),id+" out-of-range sequence rejected")
  a._record.walk_sequence=data.walk_sequence.duplicate();a._record.walk_phase_weights=[1.0]
  check(not a.apply_walk(0),id+" mismatched weights rejected")
  small.free();large.free()
 var npc_sequence:Array=records.human_courier.walk_sequence
 check(npc_sequence.size()==6 and int(npc_sequence[3])==3 and int(npc_sequence[4])==2 and int(npc_sequence[5])==1,"NPC contact B returns through passing and down, never snaps directly to contact A")
 for frame in records.clerk.walk:
  check(is_equal_approx(float(frame.foot_anchor[0]),float(frame.hip_anchor[0])),"refined clerk pelvis and projected ground origin share X")
func run() -> void:
 var records:Dictionary=actual_records()
 test_clerk(records);test_npcs(records);test_invalid_art();test_distance_phase_contract(records)
 print("ACTOR MOTION 2D: ",passed," passed, ",failed," failed")
 quit(1 if failed>0 else 0)
