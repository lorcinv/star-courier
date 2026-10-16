extends SceneTree
const Presenter=preload("res://scripts/workshop_support_presenter_2d.gd")
const Plan=preload("res://scripts/workshop_support_plan_2d.gd")
var passed:int=0
var failed:int=0
var presenter
var part_root:Node2D
var nodes:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func part(id:int,kind:String,at:Vector2,rotation:int=0) -> Sprite2D:
 var s:=Sprite2D.new();s.texture=load("res://assets/2d_v5/modules/"+kind+"-pixel.png");s.position=at;s.rotation=rotation*PI*.5;s.scale=Vector2.ONE*.98
 s.set_meta("part_id",id);part_root.add_child(s);nodes[id]=s;return s
func support_contact(s:Dictionary) -> bool:return s.floor_anchor.y==486.0 and s.rail_anchor.y==478.0 and s.contact_error<.001 and not s.missing_target
func run() -> void:
 var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 part_root=Node2D.new();viewport.add_child(part_root)
 presenter=Presenter.new();viewport.add_child(presenter);await process_frame
 part(1,"cargo",Vector2(640,280));part(2,"beam",Vector2(712,280));part(3,"battery",Vector2(784,280));part(4,"beam",Vector2(784,208))
 var edges:Array=[[1,2],[2,3],[3,4]];var before:Array=[]
 for n in nodes.values():before.append([n.position,n.rotation,n.scale,n.texture])
 presenter.sync_assembly(nodes,edges)
 var state:Dictionary=presenter.debug_snapshot()
 check(state.support_count==2,"wide connected craft gets two actual bottom-member supports")
 check(state.supports.all(support_contact),"every saddle touches actual opaque underside and rail loads to floor")
 check(state.supports.all(func(s):return s.component_id==1 and s.component_parts==[1,2,3,4]),"component identity comes from supplied graph")
 check(not state.target_ids.is_empty(),"stable real part IDs are retained")
 var ids:Array=[]
 for s in state.supports:ids.append(s.part_id)
 check(ids==[1,3],"upper member does not attract a phantom bounding-box support")
 check(presenter._arm_nodes[0].mount.distance_to(presenter._arm_nodes[1].mount)>=80.0,"rear support posts are separated instead of piled into one floating mechanism")
 for arm in presenter._arm_nodes:
  for piece in ["upper","fore"]:
   var shaft:Sprite2D=arm[piece]
   for pair in [["registered_start","expected_start"],["registered_end","expected_end"]]:
    var local:Vector2=shaft.get_meta(pair[0]);var expected:Vector2=shaft.get_meta(pair[1])
    check((shaft.transform*local).distance_to(expected)<.001,"opaque shaft endpoint reaches its registered physical joint")
    check(shaft.texture.get_image().get_pixel(floori(local.x),floori(local.y)).a>.99,"registered shaft endpoint is opaque rather than transparent padding")
   var axis:Vector2=shaft.get_meta("registered_end")-shaft.get_meta("registered_start")
   var normal:Vector2=axis.normalized().orthogonal()
   check(absf((shaft.transform.x*normal.x+shaft.transform.y*normal.y).length()-1.0)<.001,"only shaft length changes while transverse raster thickness stays fixed")
  var claw:Sprite2D=arm.claw
  var wrist:Vector2=claw.get_meta("registered_wrist")
  check((claw.transform*wrist).distance_to(claw.get_meta("expected_wrist"))<.001,"forearm meets the claw wrist, not its empty grip center")
  check(claw.texture.get_image().get_pixel(floori(wrist.x),floori(wrist.y)).a>.99,"claw wrist endpoint lies on actual opaque hinge pixels")

 for phase in ["move","seat"]:
  for i in range(21):
   for n in nodes.values():n.position.x+=4.0
   presenter.present(phase)
   check(presenter.debug_snapshot().supports.all(support_contact),"same real modules remain supported at "+phase+" sample "+str(i))
 presenter.present("retract",.5)
 check(presenter.debug_snapshot().supports.all(func(s):return s.bearing.y>s.desired_contact.y and not s.released),"retraction separates saddles downward after pad seating")
 presenter.present("retract",1.0)
 check(presenter.debug_snapshot().supports.all(func(s):return s.released and s.bearing.y==468.0),"all traveling saddles are stowed before release")
 var stopped:Dictionary=presenter.debug_snapshot()
 presenter.present("move",0.0,true)
 check(presenter.debug_snapshot()==stopped,"pause freezes presentation state and contact records")
 presenter.present("airborne",1.0)
 var anchors:Array=[]
 for s in presenter.debug_snapshot().supports:anchors.append(s.floor_anchor)
 for n in nodes.values():n.position+=Vector2(100,-100)
 presenter.present("airborne",1.0)
 var new_anchors:Array=[]
 for s in presenter.debug_snapshot().supports:new_anchors.append(s.floor_anchor)
 check(anchors==new_anchors,"released jacks do not chase airborne modules")
 # Reset a physical low row and rotate actual raster shapes.
 for n in nodes.values():n.queue_free()
 nodes.clear();await process_frame
 for rot in range(4):part(10+rot,"spring",Vector2(500+rot*72,430),rot)
 presenter.sync_assembly(nodes,[[10,11],[11,12],[12,13]])
 check(presenter.debug_snapshot().supports.all(support_contact),"quarter-turn silhouettes still receive exact measured underside contact")
 var snapshots:Array=[]
 for n in nodes.values():snapshots.append([n.position,n.rotation,n.scale,n.texture])
 for i in range(300):presenter.present("workshop");presenter.configure_stage(486.0,Vector2(404,1280))
 var after:Array=[]
 for n in nodes.values():after.append([n.position,n.rotation,n.scale,n.texture])
 check(after==snapshots,"presentation never mutates the actual module transforms or art")
 state=presenter.debug_snapshot()
 check(state.jack_pool_count<=153 and state.rail_nodes<=66 and state.arm_count==2,"repeated frames keep all pools bounded")
 presenter.sync_assembly(nodes,[])
 check(presenter.debug_snapshot().support_count==4,"disconnected components are not silently merged by a rail")
 var supplied:Array=[{"id":1,"contact":Vector2(100,100)},{"id":2,"contact":Vector2(100,200)}]
 var supplied_before:Array=supplied.duplicate(true);var selected:Array=Plan.choose(supplied,[])
 check(selected.size()==2 and selected[0].component_id!=selected[1].component_id,"stacked disconnected targets remain separate support assignments")
 check(supplied==supplied_before,"pure selector does not mutate input dictionaries")
 var mixed:Array=Plan.choose([{"id":1,"contact":Vector2(96,100),"center_x":100.0},{"id":2,"contact":Vector2(108,200),"center_x":100.0}],[[1,2]])
 check(mixed.size()==1 and mixed[0].part_id==2,"mixed artwork contact offsets never split one real structural column")
 # Replace module representation while preserving real IDs and support choices.
 var replacement:Dictionary={}
 for id in nodes:
  var s:=Sprite2D.new();s.texture=nodes[id].texture;s.position=nodes[id].position;s.rotation=nodes[id].rotation;s.scale=nodes[id].scale;part_root.add_child(s);replacement[id]=s
 var chosen:Array=[]
 for s in presenter.debug_snapshot().supports:chosen.append(s.part_id)
 presenter.bind_transfer(replacement);presenter.present("move")
 var chosen_after:Array=[]
 for s in presenter.debug_snapshot().supports:chosen_after.append(s.part_id)
 check(chosen==chosen_after,"editor-to-flight replacement preserves support target IDs")
 check(presenter.debug_snapshot().supports.all(support_contact),"replacement live sprites start in exact same contact registration")
 presenter.bind_transfer({});presenter.present("move")
 check(presenter.debug_snapshot().supports.all(func(s):return s.missing_target),"missing live IDs are exposed rather than replaced with fake craft art")
 viewport.queue_free();await process_frame;await process_frame
 print("WORKSHOP_SUPPORT_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
