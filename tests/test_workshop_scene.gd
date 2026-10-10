extends SceneTree
## Actual world registration, generated-art clearance, transport and grounded launch.
const World=preload("res://scripts/world_view_2d.gd")
const Tier=preload("res://scripts/workshop_profile.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
var passed:int=0
var failed:int=0
var world
var viewport:SubViewport
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func large_design(tier:int) -> Array:
 var bounds:Rect2i=Tier.bounds(tier);var result:Array=[];var id:int=1
 for x in range(bounds.position.x,bounds.end.x):
  result.append(Profile.part(id,"battery" if x==bounds.position.x else "beam",x,bounds.end.y-1));id+=1
 for y in range(bounds.position.y,bounds.end.y-1):
  result.append(Profile.part(id,"cargo" if y==bounds.position.y else "beam",bounds.end.x-1,y));id+=1
 return result
func opaque_in(image:Image,rect:Rect2) -> bool:
 var clipped:Rect2=rect.intersection(Rect2(Vector2.ZERO,Vector2(image.get_size())))
 if not clipped.has_area():return false
 # The checked derivative is an exact 2px pixel grid, but include both edges.
 for y in range(floori(clipped.position.y),ceili(clipped.end.y)):
  for x in range(floori(clipped.position.x),ceili(clipped.end.x)):
   if image.get_pixel(x,y).a>=.5:return true
 return false
func craft_rect() -> Rect2:
 var result:Rect2;var first:bool=true
 for key in world.flight_nodes:
  if str(key).begins_with("p") and world.flight_nodes[key] is Sprite2D:
   var rect:Rect2=Rect2(world.flight_nodes[key].position-Vector2.ONE*World.CELL*.49,Vector2.ONE*World.CELL*.98)
   result=rect if first else result.merge(rect);first=false
 return result
func visible_parcels() -> int:
 var count:int=1 if world.parcel.visible else 0
 for entry in world.customers.values():
  if entry.node.visible and entry.node.pose_contains_parcel():count+=1
 for node in world.ship_root.get_children():
  if node is Sprite2D and bool(node.get_meta("is_cargo",false)) and node.visible:count+=1
 return count
func step(dt:float) -> void:
 if world._parcel_tween!=null:world._parcel_tween.custom_step(dt)
 world._process(dt);world.assembly_feedback._process(dt)
func test_tier(tier:int) -> void:
 world.update_shop_state({"contracts":[],"active_contract_id":""})
 # Each tier is an independent workshop-clearance fixture. Cancellation now
 # returns the robot physically after the clerk clears the aisle; waiting only
 # for the clerk silently started the next tier with the robot still far away.
 for i in 4000:
  var clerk_home:bool=world.prepare_counter_interaction()
  if clerk_home and not world._robot_return_pending and world.assembly_feedback.robot_state=="idle" and is_equal_approx(world.assembly_feedback.transport_current_x(),world.AssemblyFeedback.DOCK_X):break
  step(1.0/120.0)
 check(world.prepare_counter_interaction() and is_equal_approx(world.assembly_feedback.transport_current_x(),world.AssemblyFeedback.DOCK_X),"tier %d fixture starts only after both coworkers physically return home"%tier)
 world.set_workshop_tier(tier);world.show_design(Profile.starter_design());world.focus("workshop",true)
 var bounds:Rect2i=Tier.bounds(tier)
 check(world.assembly_origin==Tier.assembly_origin(tier) and world.grid.bounds==bounds and world.grid.position==world.assembly_origin,"tier %d exact dynamic grid origin/bounds"%tier)
 check(world.shell.position==Vector2(640,360) and world.shell.scale==Vector2.ONE,"tier %d original shop remains unscaled in place"%tier)
 var mapping:bool=true
 for x in range(bounds.position.x,bounds.end.x):
  for y in range(bounds.position.y,bounds.end.y):
   var cell:Vector2i=Vector2i(x,y)
   var pixel:Vector2=viewport.get_canvas_transform()*(world.assembly_origin+Vector2(cell)*World.CELL)
   mapping=mapping and world.cell_at(pixel)==cell
 check(mapping,"tier %d every grid marker maps through actual camera back to its real cell"%tier)
 var center:Vector2=world.assembly_origin+Vector2(31,-44);var zoom:float=.63
 world.apply_workshop_camera(center,zoom)
 var bay_id:int=world.workshop_bay.get_instance_id();var parcel_id:int=world.parcel.get_instance_id()
 for i in 12:
  world.set_workshop_tier(tier);world.show_design(Profile.starter_design());world.focus("hub");world.focus("workshop")
 check(world._workshop_view_saved and world.target_center==center and world.target_zoom==zoom and world.workshop_bay.get_instance_id()==bay_id,"tier %d repeated renders and focus preserve pan/zoom without rebuilding bay"%tier)
 var image:Image
 if tier>0:
  image=world.workshop_bay.texture.get_image()
  check(world.workshop_bay.visible and world.workshop_bay.position==Tier.bay_top_left(tier) and world.workshop_bay.scale==Vector2.ONE,"tier %d generated bay uses native registered texture"%tier)
  var footprint:Rect2=world.workshop_grid_rect();footprint.position-=world.workshop_bay.position
  check(not opaque_in(image,footprint),"tier %d complete editable footprint including half-cell edges clears artwork"%tier)
  var corridor:Rect2=Rect2(footprint.position,Vector2(float(image.get_width())-footprint.position.x,footprint.size.y))
  check(not opaque_in(image,corridor),"tier %d whole rightward exit corridor clears artwork"%tier)
 else:
  check(not world.workshop_bay.visible and world.shop_cradle.visible and not world.expanded_cradle.visible,"tier zero retains original shop/cradle representation")
 # Put the actual cargo at the farthest paid upper/right cell and traverse the
 # ordinary customer/clerk/robot chain. No fake cargo marker or second parcel.
 var design:Array=large_design(tier);world.show_design(design);world.focus("hub",true)
 var cargo:Dictionary=design[-(bounds.size.y-1)]
 var expected:Vector2=world.assembly_origin+Vector2(cargo.x,cargo.y)*World.CELL
 var id:String="scene-tier-%d"%tier
 var contract:Dictionary={"contract_id":id,"status":"accepted","appearance_id":"human_courier","species":"human","appearance_seed":7,"accessory_id":"none","handoff_released":true,"cargo_loaded":false}
 world.update_shop_state({"contracts":[contract],"active_contract_id":id})
 world.customers[id].node.position=world.customers[id].target
 if world._parcel_tween!=null:world._parcel_tween.pause()
 var elapsed:float=0.0;var one:bool=true;var grounded:bool=true;var farthest:float=0.0
 while not world.is_parcel_loaded(id) and elapsed<24.0:
  step(1.0/120.0);elapsed+=1.0/120.0
  one=one and visible_parcels()==1 and world.parcel.get_instance_id()==parcel_id
  grounded=grounded and world.assembly_feedback.robot_root.position.y==Tier.FLOOR_Y
  farthest=maxf(farthest,world.assembly_feedback.robot_root.position.x)
 check(world.is_parcel_loaded(id) and world._cargo_destination==expected and world.parcel.position==expected,"tier %d robot inserts into actual far upper/right cargo within bounded chain"%tier)
 check(one and grounded and elapsed<24.0 and farthest>=expected.x-88.01,"tier %d one parcel and both coworkers reach paid extent on floor at real walking speed"%tier)
 world.focus("hub",true)
 var frame:Rect2=Rect2(Vector2.ZERO,Vector2(viewport.size))
 check(frame.has_point(viewport.get_canvas_transform()*Vector2(148,486)) and frame.has_point(viewport.get_canvas_transform()*expected),"tier %d hub camera includes customer and far cargo together"%tier)
 world.focus("workshop",true)
 var sim=Sim.new();sim.configure(design,Profile.starter_launcher(),Profile.route(),3)
 var bodies:Array=sim.bodies.duplicate(true);var parts:Dictionary=sim.parts.duplicate(true);var launcher:Array=sim.launcher_parts.duplicate(true)
 var energy:float=sim.total_energy();var elapsed_before:float=sim.elapsed
 world.start_flight(sim)
 var registered:bool=true
 for part in design:registered=registered and world.flight_nodes["p"+str(part.id)].position.distance_to(world.assembly_origin+Vector2(part.x,part.y)*World.CELL)<.8
 check(registered,"tier %d launch begins on exactly the same real assembly cells"%tier)
 var original:Rect2=craft_rect();var last_left:float=original.position.x;var rightward:bool=true;var clear:bool=true
 for i in range(21):
  world.launch_transfer_progress=float(i)/20.0;world.show_flight(sim,true)
  var rect:Rect2=craft_rect();rightward=rightward and rect.position.x>=last_left-.8;last_left=rect.position.x
  if tier>0:
   var local:Rect2=rect;local.position-=world.workshop_bay.position
   clear=clear and not opaque_in(image,local)
 check(rightward and (tier==0 or craft_rect().position.x>=world.workshop_exit_x()+24.0),"tier %d whole craft transfers right to this bay exit"%tier)
 check(clear,"tier %d large connected craft stays clear of generated ceiling/pillar/deck through transfer"%tier)
 check(absf(craft_rect().end.y-World.CRADLE_CONTACT_Y)<.8,"tier %d large craft underside meets fixed pad contact plane"%tier)
 var support_ok:bool=true;var support_count:int=0
 for node in world.flight_nodes.launch_pad.get_children():
  if node.has_meta("floor_anchor"):
   var anchor:Vector2=node.get_meta("floor_anchor")
   support_ok=support_ok and anchor.y==Tier.FLOOR_Y
   if tier>0:support_ok=support_ok and anchor.x-32.0>=world.workshop_exit_x() and anchor.x+32.0<=world._departure_right_edge
   support_count+=1
 check(support_ok and support_count==sim.launcher_parts.size(),"tier %d every real launcher support has floor under both feet"%tier)
 var floor_ok:bool=true
 for tile in world.departure_deck.get_children():
  floor_ok=floor_ok and tile.scale==Vector2.ONE and tile.position.y>=World.CRADLE_CONTACT_Y and tile.region_rect.size.x<=512.0
 check(floor_ok and world.departure_deck.get_child_count()<=World.MAX_DEPARTURE_TILES,"tier %d native generated floor regions are grounded, clear and bounded"%tier)
 check(sim.bodies==bodies and sim.parts==parts and sim.launcher_parts==launcher and sim.total_energy()==energy and sim.elapsed==elapsed_before,"tier %d editor/loading/camera/launch presentation never mutates simulation"%tier)
 world.leave_flight()
func run() -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();viewport.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 for tier in 3:test_tier(tier)
 world.apply_workshop_camera(Vector2(2100,100),.5)
 check(not world.set_workshop_tier(99) and world.workshop_tier==2 and world._workshop_view_saved,"invalid tier cannot change geometry or saved camera")
 world.set_workshop_tier(1)
 check(not world._workshop_view_saved and world.assembly_origin==Tier.assembly_origin(1),"real tier change resets the saved workshop camera once")
 viewport.queue_free();await process_frame;await process_frame
 print("WORKSHOP_SCENE_TESTS passed=",passed," failed=",failed);quit(1 if failed else 0)
