extends SceneTree
## Component-only coverage. Does not touch player saves or claim main-loop QA.
const Npc=preload("res://scripts/npc_sprite_2d.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const CASES:Dictionary={
 "human_courier":{"species":"human","accessories":["none"],"foot":Vector2(73.19,247.78),"parcel":Vector2(135.23,115.37)},
 "elf_archivist":{"species":"elf","accessories":["book_pouch","map_case"],"foot":Vector2(96,248),"parcel":Vector2(141,123)},
 "alien_botanist":{"species":"alien","accessories":["seed_pod","field_vial"],"foot":Vector2(96,248),"parcel":Vector2(140,135)},
 "robot_machinist":{"species":"robot","accessories":["tool_pack","power_cell"],"foot":Vector2(96,248),"parcel":Vector2(140,132)}
}
var passed:int=0
var failed:int=0
var actor
var manifest:Dictionary={}

func _initialize() -> void:run.call_deferred()

func check(condition:bool,label:String) -> void:
 if condition:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func binding(id:String,accessory:String="none") -> Dictionary:
 return {"appearance_id":id,"species":CASES[id].species,"appearance_seed":11937,"accessory_id":accessory,"contract_id":"test-order"}

func test_cast_and_accessories() -> void:
 actor.position=Vector2(148,488)
 for id in CASES:
  var spec:Dictionary=CASES[id]
  for accessory in spec.accessories:
   var saved:Dictionary=binding(id,accessory);var before:String=JSON.stringify(saved)
   check(actor.configure(saved),"valid identity configures: "+id+"/"+accessory)
   check(JSON.stringify(saved)==before,"configure leaves caller binding untouched: "+id+"/"+accessory)
   for handoff in [false,true]:
    actor.set_pose(handoff)
    var pose:String="handoff" if handoff else "idle"
    var label:String=id+"/"+accessory+"/"+pose
    var snapshot:Dictionary=actor.debug_snapshot()
    var expected_path:String="res://assets/2d_v5/actors/customer-%s-pixel.png"%pose if id=="human_courier" else "res://assets/2d_v5/npcs/%s/%s-pixel.png"%[id,pose]
    check(actor.texture!=null and actor.texture.resource_path==expected_path,"exact identity texture: "+label)
    check(actor.get_meta("appearance_id")==id and actor.get_meta("identity")==id and actor.get_meta("species")==spec.species and actor.get_meta("pose")==pose,"identity metadata: "+label)
    check(snapshot.valid and snapshot.diagnostics.is_empty(),"clean diagnostics: "+label)
    check(actor.scale.is_equal_approx(Vector2.ONE*215.0/240.0) and not actor.centered,"uniform logical body scale: "+label)
    check(actor.offset.is_equal_approx(-spec.foot),"exact semantic foot registration: "+label)
    check(snapshot.foot_point.is_equal_approx(Vector2(148,488)) and actor.position==Vector2(148,488),"pose keeps feet stationary: "+label)
    check(actor.parcel_point().is_equal_approx(actor.position+(spec.parcel-spec.foot)*actor.scale),"handoff parcel in parent coordinates: "+label)
    check(snapshot.accessory_child_count<=1 and actor.get_child_count()<=1,"at most one accessory: "+label)
    if accessory=="none":check(not snapshot.accessory_visible,"human has no mixed-species accessory: "+pose)
    else:
     var child:Sprite2D=actor.get_node("CompatibleAccessory")
     var data:Dictionary=manifest.appearances[id].accessory_options[accessory]
     var local_anchor:Vector2=Vector2(data.local_anchor[0],data.local_anchor[1])
     var world_anchor:Vector2=Vector2(data.world_anchors[pose][0],data.world_anchors[pose][1])
     check(child.visible and child.texture.resource_path=="res://"+str(data.runtime),"exact compatible accessory pixels: "+label)
     check(child.offset==-local_anchor and child.position==world_anchor-spec.foot,"pose-specific accessory attachment: "+label)
     check(child.scale==Vector2.ONE and child.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"accessory inherits uniform actor scale: "+label)
   # The transfer point is inside the painted handoff parcel for every species.
   var parcel_pixel:Vector2i=Vector2i(spec.parcel)
   check(actor.texture.get_image().get_pixelv(parcel_pixel).a>0.9,"documented parcel point lies on opaque handoff art: "+id)

func test_saved_identity() -> void:
 var state:Dictionary=Stories.initial_state()
 for id in Stories.IDS:
  var original:Dictionary=state.roster[id]
  actor.configure(original);actor.set_pose(true)
  var resolved:Dictionary=actor.binding_snapshot()
  var texture_before:Texture2D=actor.texture
  var saved:Dictionary=JSON.parse_string(JSON.stringify(original))
  seed(3219)
  for i in 40:randi()
  actor.configure(saved);actor.set_pose(true)
  check(actor.binding_snapshot()==resolved and actor.texture==texture_before,"story identity/accessory survive JSON and global RNG changes: "+id)
  var recovered:Dictionary=JSON.parse_string(JSON.stringify(actor.binding_snapshot()))
  actor.configure(recovered)
  check(actor.binding_snapshot()==resolved,"resolved binding itself round-trips: "+id)
  actor.configure({"appearance_id":id,"accessory_id":resolved.accessory_id})
  check(actor.species==CASES[id].species,"saved appearance alone retains its species: "+id)
  # Mutating caller-owned data after configure must not replace the chosen body.
  saved.appearance_id="other";saved.species="wrong";saved.accessory_id="wrong"
  actor.set_pose(false)
  check(actor.get_meta("appearance_id")==id and actor.get_meta("accessory_id")==resolved.accessory_id,"retained identity is isolated from caller mutations: "+id)

func test_fallbacks_and_invalid_data() -> void:
 check(actor.configure({}) and actor.appearance_id=="human_courier","empty legacy contract preserves original human")
 check(actor.debug_snapshot().diagnostics==["legacy_human_default"],"legacy default is diagnostic rather than an invisible identity rewrite")
 for id in CASES:
  var species:String=CASES[id].species
  check(actor.configure({"species":species}) and actor.appearance_id==id,"known species selects only its own default: "+species)
  var expected:String="none" if species=="human" else str(manifest.appearances[id].default_accessory)
  check(actor.accessory_id==expected,"unseeded species uses authored default accessory: "+species)
  var seen:Dictionary={}
  for number in [0,1,2,3,-1,-2147483647,2147483646]:
   var saved:Dictionary={"species":species,"appearance_seed":number}
   actor.configure(saved);var first:Dictionary=actor.binding_snapshot();seen[actor.accessory_id]=true
   actor.configure(JSON.parse_string(JSON.stringify(saved)))
   check(actor.binding_snapshot()==first and actor.accessory_id in CASES[id].accessories,"seed fallback is compatible and JSON-stable: "+species+"/"+str(number))
  check(seen.size()==CASES[id].accessories.size(),"seed fallback reaches available compatible options: "+species)
  actor.configure({"species":species,"appearance_seed":{},"accessory_id":"none"})
  check(actor.debug_snapshot().valid and actor.debug_snapshot().diagnostics.has("invalid_seed_defaulted"),"malformed seed safely uses stable default: "+species)
  check(actor.accessory_id=="none" and not actor.debug_snapshot().accessory_visible,"explicit no-accessory is respected: "+species)
 var invalids:Array=[
  {"species":"dragon"},
  {"appearance_id":"missing_elf","species":"elf"},
  {"appearance_id":"human_courier","species":"elf"},
  {"appearance_id":"elf_archivist","species":"dragon"},
  {"appearance_id":{},"species":"elf"},
  {"appearance_id":"elf_archivist","species":[]}
 ]
 for bad in invalids:
  actor.configure(binding("robot_machinist","power_cell"))
  check(not actor.configure(bad),"reject invalid identity: "+JSON.stringify(bad))
  actor.set_pose(true)
  check(actor.texture==null and not actor.visible and not actor.debug_snapshot().accessory_visible,"invalid identity cannot retain stale body or disguise as human")
  check(not actor.debug_snapshot().diagnostics.is_empty() and actor.parcel_point()==actor.position,"invalid identity exposes diagnostics and safe parcel origin")
 for bad_accessory in ["power_cell","unknown",{},null]:
  var saved:Dictionary=binding("elf_archivist");saved.accessory_id=bad_accessory
  check(actor.configure(saved),"bad accessory does not erase valid elf identity")
  check(actor.species=="elf" and actor.accessory_id=="none" and not actor.debug_snapshot().accessory_visible,"incompatible/malformed accessory omitted rather than species-mixed")
  check(not actor.debug_snapshot().diagnostics.is_empty(),"incompatible accessory reports why it was omitted")
 for id in CASES:
  for donor in CASES:
   if id==donor:continue
   for wrong_accessory in CASES[donor].accessories:
    if wrong_accessory=="none":continue
    check(actor.configure(binding(id,wrong_accessory)) and actor.species==CASES[id].species and not actor.debug_snapshot().accessory_visible,"cross-species attachment blocked: "+id+"/"+wrong_accessory)
 for height in [0.0,-1.0,INF,NAN]:
  check(actor.configure(binding("human_courier"),height) and actor.scale.is_equal_approx(Vector2.ONE*215.0/240.0),"invalid height uses safe uniform default")
 actor.configure(binding("alien_botanist","field_vial"),300.0)
 check(actor.scale==Vector2.ONE*1.25 and actor.debug_snapshot().foot_point==actor.position,"custom height preserves registration without distortion")
 # Simulate missing nonhuman pose without altering shared manifests or files.
 actor._appearance=actor._appearance.duplicate(true)
 actor._appearance.poses.handoff.runtime="assets/2d_v5/npcs/missing-test-pose.png"
 actor.set_pose(true)
 check(actor.texture==null and not actor.visible and not actor.debug_snapshot().accessory_visible,"missing nonhuman pose never silently loads human or retains prior pixels")
 check(actor.debug_snapshot().diagnostics.has("missing_pose_texture:handoff"),"missing pose has actionable diagnostics")
 check(actor.configure(binding("alien_botanist","field_vial")),"valid reconfigure recovers from missing pose")

func test_bounded_switches_and_transforms() -> void:
 var original_child:Sprite2D=actor.get_node("CompatibleAccessory")
 var baseline:Dictionary=actor.debug_snapshot()
 var stable_feet:Vector2=actor.position
 var ids:Array=CASES.keys()
 var bounded:bool=true
 for i in 600:
  var id:String=ids[i%ids.size()]
  var options:Array=CASES[id].accessories
  actor.configure(binding(id,options[(i/4)%options.size()]))
  actor.set_pose(i%2==0);actor.set_pose(i%3==0)
  bounded=bounded and actor.get_child_count()==1 and actor.get_node("CompatibleAccessory")==original_child and actor.debug_snapshot().foot_point.is_equal_approx(stable_feet)
 check(bounded,"600 immediate reconfigures reuse one child without queue growth or foot drift")
 var after:Dictionary=actor.debug_snapshot()
 check(after.manifest_load_count==1 and baseline.manifest_load_count==after.manifest_load_count,"manifests load only once across identities")
 check(baseline.texture_cache_size==after.texture_cache_size and baseline.texture_load_count==after.texture_load_count,"rapid switches reuse cached body/accessory textures")
 actor.hide();actor.set_pose(actor.pose=="handoff")
 check(not actor.visible,"unchanged-pose update does not override caller visibility")
 actor.configure(binding("elf_archivist","map_case"));actor.set_pose(true)
 actor.rotation=0.37;actor.skew=0.12
 var local_point:Vector2=CASES.elf_archivist.parcel-CASES.elf_archivist.foot
 check(actor.parcel_point().is_equal_approx(actor.transform*local_point),"parcel point respects complete parent-local transform")
 check(actor.debug_snapshot().foot_point.is_equal_approx(actor.position),"rotation and skew pivot at the exact semantic feet")
 actor.rotation=0;actor.skew=0
 var duplicate=Npc.new();root.add_child(duplicate);duplicate.configure(binding("elf_archivist","map_case"));duplicate.set_pose(true)
 check(duplicate.texture==actor.texture and duplicate.debug_snapshot().manifest_load_count==1,"independent NPC instances share the same resource cache")
 duplicate.free()

func run() -> void:
 manifest=JSON.parse_string(FileAccess.get_file_as_string(Npc.NPC_MANIFEST))
 actor=Npc.new();root.add_child(actor)
 test_cast_and_accessories()
 test_saved_identity()
 test_fallbacks_and_invalid_data()
 test_bounded_switches_and_transforms()
 actor.free()
 print("NPC SPRITE 2D: ",passed," passed, ",failed," failed")
 quit(1 if failed>0 else 0)
