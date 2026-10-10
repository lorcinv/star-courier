extends SceneTree
const World=preload("res://scripts/world_view_2d.gd")
const Parts=preload("res://scripts/parts.gd")
const Sim=preload("res://scripts/simulation.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func run() -> void:
 var viewport=SubViewport.new();viewport.size=Vector2i(960,540);root.add_child(viewport)
 var world=World.new();world.catalog=Parts.catalog();world.catalog.cargo=Parts.cargo_spec();viewport.add_child(world)
 var design:Array=[];var index:int=0
 for kind in world.catalog:
  design.append({"id":index+1,"type":kind,"x":index%9-4,"y":index/9-1,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1});index+=1
 world.show_design(design);world.focus("workshop",true)
 for p in design:
  var sprite=world.ship_root.get_node("Part"+str(p.id))
  check(sprite.texture!=null and sprite.texture.get_size()==Vector2(72,72),"visible generated72px catalog sprite: "+str(p.type))
 check(world.missing_assets.is_empty(),"no silently missing world art after all26generatedmodules loaded")
 check(world._texture("modules/coupler").resource_path.ends_with("coupler-latch-pixel.png"),"coupler is a mechanical latch rather than a second cockpit")
 check(world._texture("modules/joint").get_size()==Vector2(32,28),"live structural collars use the generated connection art")
 var origin:Vector2=world.flight_origin
 check(world._pilot_cruise_center(origin+Vector2(500,90),600).y==origin.y-35,"ordinary downward steering stays visible inside camera deadzone")
 check(world._pilot_cruise_center(origin+Vector2(500,-90),600).y==origin.y-35,"ordinary upward steering stays visible inside camera deadzone")
 check(world._pilot_cruise_center(origin+Vector2(500,170),600).y==origin.y+15,"camera follows excessive displacement beyond the safe band")
 for x in range(-4,5):
  for y in range(-2,3):
   var point:Vector2=viewport.get_canvas_transform()*(world.assembly_origin+Vector2(x,y)*world.CELL)
   check(world.cell_at(point)==Vector2i(x,y),"render/pick grid roundtrip "+str(Vector2i(x,y)))
 var a:Dictionary={"contract_id":"A","status":"accepted"};var b:Dictionary={"contract_id":"B","status":"accepted"}
 world.update_shop_state({"contracts":[a],"active_contract_id":"A"});world.pack_parcel()
 await create_timer(.1).timeout
 world.update_shop_state({"contracts":[],"active_contract_id":""})
 world.update_shop_state({"contracts":[b],"active_contract_id":"B"})
 await create_timer(.8).timeout
 check(world.active_id=="B" and world.parcel_state=="counter" and world.parcel.visible,"old parcel transfer cannot hide newly accepted parcel")
 world.pack_parcel();world.fastforward_loading();await process_frame
 check(not world.parcel.visible and world.parcel_state=="loaded","current parcel transfer alone completes")
 world.show_design([design[0]]);world.committed_edit("rotate",design[0])
 check(world.assembly_feedback._actions.size()==1,"committed edit animates actual module")
 world.show_design([design[0]])
 check(world.assembly_feedback._actions.is_empty(),"design rebuild cancels stale assembly action")
 var sim=Sim.new();var hazards:Array=[]
 for kind in ["rock","turret","tracker","mine","gravity"]:hazards.append({"x":20+hazards.size()*10,"y":0,"type":kind,"radius":1.0})
 sim.configure([{"id":1,"type":"cargo","x":0,"y":0}],[],{"distance":100,"hazards":hazards},4)
 world.start_flight(sim);world.launch_age=2;world.show_flight(sim)
 for i in range(hazards.size()):
  var node=world.flight_nodes["h"+str(i)]
  check(node.texture!=null and str(node.get_meta("hazard_type"))==hazards[i].type,"typed hazard art exists: "+hazards[i].type)
 check(world.flight_nodes.h1.get_meta("art_id")!="flight/rock-2" and world.flight_nodes.h2.get_meta("art_id")!="flight/rock-1","enemylogic no longer masquerades as rock")
 check(world.flight_nodes.has("cues") and world.flight_nodes.has("receipt_label"),"actual collection boundary and receiver cue are visible")
 sim.effects=[]
 for i in range(192):sim.effects.append({"type":"teleport","from":Vector2(i,0),"to":Vector2(i+1,0),"ttl":.5})
 world.show_flight(sim)
 check(world.visible_effect_count<=32 and world.flight_nodes.cues.effects.size()<=32,"large simulation effect burst stays bounded in2Drenderer")
 world.leave_flight()
 check(not world.effect_node.visible and not world.flight_backdrop.visible and world.flight_nodes.is_empty(),"flight exit removes overlays and backdrop without stale state")
 var ascent_profile=preload("res://scripts/pilot_ascent_profile.gd")
 var ascent=preload("res://scripts/pilot_ascent_simulation.gd").new()
 ascent.configure(ascent_profile.starter_design(),ascent_profile.starter_launcher(),ascent_profile.route(),7)
 world.start_flight(ascent);world.launch_age=2
 var live:Dictionary=ascent.body_for_part(1)
 live.angle=-.55
 for p in ascent.parts.values():p.world_angle=0.0
 world.show_flight(ascent)
 for p in ascent.parts.values():
  var art:Sprite2D=world.flight_nodes["p"+str(p.id)]
  check(is_equal_approx(art.rotation,float(live.angle)+float(p.local_angle)),"live attached module follows actual climb angle: "+str(p.id))
 var turning:Dictionary=ascent.parts[1];turning.local_angle+=.3
 world.show_flight(ascent)
 check(is_equal_approx(world.flight_nodes.p1.rotation,live.angle+turning.local_angle),"servo-adjusted local angle composes with live body angle")
 turning.body_id=-1;turning.world_angle=.7;world.show_flight(ascent)
 check(is_equal_approx(world.flight_nodes.p1.rotation,.7),"detached/recovered sprite retains simulator's cached world angle")
 live.velocity=Vector2(19,-8)
 world.camera.position+=Vector2(40,-20);world.show_flight(ascent)
 world.show_flight(ascent,true)
 check(is_zero_approx(float(world.ascent_backdrop.debug_snapshot().blur_pixels)),"paused presenter explicitly clears background blur while retaining physics velocity")
 check(live.velocity==Vector2(19,-8),"presentation pause never changes physical velocity")
 var follow:Vector2=world._ascent_cruise_center(world.flight_origin+Vector2(500,470),615,0,-.55)
 check((world.flight_origin.y+470-follow.y)*.35<=152.0,"ascent framing keeps downward steering above the compact receipt and bottom controls")
 world._ascent_view_zoom=.35
 for pair in [[13.9,.35],[17.9,.30],[19.72,.27],[22.63,.24]]:
  var zoom:float=world._ascent_cruise_zoom({"forward_speed":pair[0]})
  check(is_equal_approx(zoom,pair[1]),"bounded real-corridor pullback at "+str(pair[0])+"m/s")
  var visible_m:float=world.SCENE_SIZE.x*.84/(zoom*world.CELL)
  # Include ~125ms camera-follow lag and the starter's leading module radius.
  var preview:float=(visible_m-float(pair[0])*.125-1.7)/float(pair[0])
  check(preview>=2.5,"visible rock lead exceeds2.5s including camera lag at "+str(pair[0])+"m/s")
 check(is_equal_approx(world._ascent_cruise_zoom({"forward_speed":0}),.24),"flight zoom cannot oscillate when crossing a speed threshold or pausing")
 world.leave_flight()
 check(world.ascent_backdrop.visible and world.ascent_backdrop.debug_snapshot().route_kind=="city","ordinary-wrap sky returns to shop without mirrored architecture")
 viewport.queue_free();await process_frame;await process_frame
 print("V5_PRESENTATION_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
