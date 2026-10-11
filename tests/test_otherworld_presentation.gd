extends SceneTree
const Presentation=preload("res://scripts/otherworld_presentation_2d.gd")
var passed:int=0
var failed:int=0
var cut_signals:int=0
var restored_signals:int=0
var layer
var world:Node2D
var stage:Node2D

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func route() -> Dictionary:
 return {"control_version":"pilot-v4-wormhole","route_profile":"wormhole-otherworld-v1","wormhole_schema":1,
 "name":"Any localized title", "distance":1240.0,"destination_y":-150.0,"delivery_radius":9.0,
 "wormhole_portal":{"entry":[600.0,-150.0],"exit":[1000.0,-150.0],"aperture_radius":13.0}}
func telemetry(phase:String) -> Dictionary:return {"control_version":"pilot-v4-wormhole","wormhole_phase":phase}
func on_cut(restored:bool) -> void:
 cut_signals+=1
 if restored:restored_signals+=1
func sprite_at(index:int) -> Sprite2D:return world.get_child(0).get_child(index) as Sprite2D
func registered(sprite:Sprite2D,anchor:Vector2,at:Vector2) -> bool:
 return (sprite.position+anchor*sprite.scale).distance_to(at)<0.02
func clear_circle(image:Image,anchor:Vector2,radius:float) -> bool:
 for y in range(image.get_height()):
  for x in range(image.get_width()):
   if image.get_pixel(x,y).a<=0.0:continue
   var nearest:Vector2=Vector2(clampf(anchor.x,float(x),float(x+1)),clampf(anchor.y,float(y),float(y+1)))
   if anchor.distance_to(nearest)<radius:return false
 return true
func no_colliders(node:Node) -> bool:
 if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D:return false
 for child in node.get_children():
  if not no_colliders(child):return false
 return true

func run() -> void:
 var canvas:CanvasLayer=CanvasLayer.new();root.add_child(canvas)
 stage=Node2D.new();canvas.add_child(stage)
 world=Node2D.new();root.add_child(world)
 layer=Presentation.new();stage.add_child(layer)
 layer.camera_cut_requested.connect(on_cut)
 check(layer.get_child_count()==2,"exactly two cached raster backdrop planes")
 check(not layer.is_processing() and not layer.is_physics_processing(),"no autonomous process or physics")
 check(not layer.visible and world.get_child_count()==0,"inactive before route configuration")
 for version in ["pilot-v1","pilot-v2","pilot-v3"]:
  var legacy:Dictionary=route();legacy.control_version=version
  check(not layer.configure_route(legacy,world,Vector2(660,345),72.0) and world.get_child_count()==0,"legacy "+version+" stays untouched")
 var false_name:Dictionary={"name":"wormhole-otherworld-v1","distance":1240,"destination_y":-150,"delivery_radius":9}
 check(not Presentation.accepts_route(false_name),"route-name string cannot enable presentation")
 var config:Dictionary=route();var unchanged:Dictionary=config.duplicate(true)
 check(layer.configure_route(config,world,Vector2(660,345),72.0),"v4 exact protocol accepted")
 check(config==unchanged,"configuration does not mutate saved route")
 check(world.get_child_count()==1 and world.get_child(0).get_child_count()==3,"one prop root with exactly two portals and one receiver")
 check(layer.receiver_node()==sprite_at(2),"receiver handoff exposes cached sprite for legacy destination replacement")
 check(registered(sprite_at(0),Presentation.PORTAL_ANCHOR,Vector2(660,345)+Vector2(600,-150)*72),"entry empty aperture registers at real entry center")
 check(registered(sprite_at(1),Presentation.PORTAL_ANCHOR,Vector2(660,345)+Vector2(1000,-150)*72),"exit empty aperture registers at real exit center")
 check(registered(sprite_at(2),Vector2(167,307),Vector2(660,345)+Vector2(1240,-150)*72),"receiver actual inner mouth registers at real capture center")
 check(is_equal_approx(sprite_at(0).scale.y*Presentation.PORTAL_CONTENT_HALF_HEIGHT,13.0*72.0) and sprite_at(0).scale.x>0.0,"energy content spans the exact 13m vertical aperture")
 check(is_equal_approx(sprite_at(2).scale.x*59.0,9.0*72.0) and sprite_at(2).scale.x==sprite_at(2).scale.y,"receiver has uniform 9m conservative capture disk")
 check(not sprite_at(0).flip_h and not sprite_at(1).flip_h and not sprite_at(2).flip_h,"portal and receiver artwork never reverse")
 check(sprite_at(0).texture.resource_path.ends_with("portal-energy-plane.png") and sprite_at(0).get_child_count()==0,"side-on route without physical hardware paints only energy, never a solid side rim")
 check(clear_circle(sprite_at(2).texture.get_image(),Vector2(167,307),59.0),"actual receiver texel rectangles leave the conservative capture disk clear")
 check(no_colliders(layer) and no_colliders(world),"decorative presentation creates zero colliders")
 check(not layer.sync_telemetry(telemetry("ascent")),"starting ascent requires no camera cut")
 layer.update_view(Vector2(2000,-150),Vector2(24,0),Vector2(2100,-150))
 check(not layer.otherworld_active() and not layer.visible,"crossing exit X without authoritative cargo transit cannot change biome")
 var separated:Dictionary=telemetry("space");separated.wormhole_transits=8
 check(not layer.sync_telemetry(separated) and not layer.otherworld_active(),"detached-body transit count cannot move cargo biome")
 check(sprite_at(0).visible and not sprite_at(1).visible and not sprite_at(2).visible,"pretransit shows only entry, leaving ascent sky ownership unchanged")
 check(layer.sync_telemetry(telemetry("otherworld")),"actual cargo phase transition requests same-frame camera cut")
 check(cut_signals==1 and restored_signals==0 and layer.debug_snapshot().live_transitions==1,"one live phase change emits one nonrestore cut")
 check(layer.visible and not sprite_at(0).visible and sprite_at(1).visible and sprite_at(2).visible,"actual transit selects otherworld, exit and receiver")
 layer.update_view(Vector2(1003,-150),Vector2(24,0),Vector2(1040,-160))
 check(layer.debug_snapshot().blur_pixels==0.0 and not layer.debug_snapshot().pending_sample_reset,"first exit-side sample has zero 400m jump smear")
 for i in range(12):check(not layer.sync_telemetry(telemetry("otherworld")),"same phase does not replay transition "+str(i))
 check(cut_signals==1 and layer.debug_snapshot().live_transitions==1,"repeat render cannot increment transition count")
 layer.update_view(Vector2(1005,-150),Vector2(24,0),Vector2(1042,-160))
 check(is_equal_approx(layer.debug_snapshot().blur_pixels,12.0),"real subsequent camera motion allows bounded background-only blur")
 layer.update_view(Vector2(1007,-150),Vector2(24,0),Vector2(1042,-160))
 check(layer.debug_snapshot().blur_pixels==0.0,"cargo within camera dead-zone does not smear scenery")
 layer.update_view(Vector2(1005,-152),Vector2(-24,-24),Vector2(1040,-162))
 check(layer.debug_snapshot().island_blur.x<0 and layer.debug_snapshot().island_blur.y<0,"reverse and vertical camera movement retain signed blur")
 layer.update_view(Vector2(1005,-152),Vector2.ZERO,Vector2(1040,-162),true)
 var frozen:Dictionary=layer.debug_snapshot()
 layer.update_view(Vector2(2000,-500),Vector2(999,999),Vector2(2000,-500),true)
 check(layer.debug_snapshot()==frozen and frozen.blur_pixels==0.0,"paused samples freeze position, phase offsets and blur")
 await process_frame;await process_frame
 check(layer.debug_snapshot()==frozen,"pause has no time-driven changes")
 layer.update_view(Vector2(1007,-150),Vector2(24,0),Vector2(1042,-160))
 layer.reduced_motion=true
 check(layer.debug_snapshot().blur_pixels==0 and layer.debug_snapshot().island_blur==Vector2.ZERO,"reduced motion clears all background blur immediately")
 layer.reduced_motion=false;layer.motion_blur_enabled=false
 check(layer.debug_snapshot().blur_pixels==0,"independent blur-off setting clears blur")
 layer.motion_blur_enabled=true
 layer.reset_camera_sample(Vector2(1010,-150),Vector2(1045,-160))
 layer.update_view(Vector2(1010,-150),Vector2(24,0),Vector2(1045,-160))
 check(layer.debug_snapshot().blur_pixels==0,"explicit camera sample reset stays stable on identical quantized frame")
 var snapshot:Dictionary=layer.debug_snapshot();snapshot.phase="corrupted";snapshot.destination_m=Vector2.ZERO
 check(layer.debug_snapshot().phase=="otherworld" and layer.debug_snapshot().destination_m==Vector2(1240,-150),"debug data is detached and read-only with respect to live state")
 var resources:Array=[]
 for node in layer.get_children():resources.append([node.texture,node.material])
 var original_props:Array=[sprite_at(0),sprite_at(1),sprite_at(2)]
 var resource_count:int=int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
 var bounded:bool=true
 for i in range(12000):
  var travel:float=float(i)*19313.718 if i%2==0 else -float(i)*11013.333
  layer.update_view(Vector2(travel,-travel),Vector2(24,-24),Vector2(travel,-travel))
  var state:Dictionary=layer.debug_snapshot()
  var far:Vector2=state.far_scroll;var near:Vector2=state.island_scroll
  bounded=bounded and far.is_finite() and near.is_finite() and far.x>=0 and far.x<1280 and absf(far.y)<=96 and near.x>=0 and near.x<1280 and near.y>=0 and near.y<640
  bounded=bounded and far/2==(far/2).round() and near/2==(near/2).round() and state.blur_pixels<=12
 check(bounded,"twelve thousand forward/reverse samples retain bounded two-pixel offsets and blur")
 var stable:bool=layer.get_child_count()==2 and world.get_child_count()==1 and world.get_child(0).get_child_count()==3
 for i in range(2):stable=stable and layer.get_child(i).texture==resources[i][0] and layer.get_child(i).material==resources[i][1]
 for i in range(3):stable=stable and sprite_at(i)==original_props[i]
 check(stable and int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))<=resource_count,"no node, texture, material or resource growth")
 layer.update_view(Vector2(1e30,-1e30),Vector2(24,0),Vector2(1e30,-1e30))
 check(layer.debug_snapshot().far_scroll.is_finite() and layer.debug_snapshot().island_scroll.is_finite(),"huge finite coordinates reduce before shader multiplication")
 var before:Dictionary=layer.debug_snapshot()
 layer.update_view(Vector2(NAN,0),Vector2.ZERO,Vector2.ZERO)
 layer.update_view(Vector2.ZERO,Vector2(INF,0),Vector2.ZERO)
 layer.update_view(Vector2.ZERO,Vector2.ZERO,Vector2(0,NAN))
 layer.sync_telemetry({"wormhole_phase":"unrecognized"})
 layer.sync_telemetry({"control_version":"pilot-v3","wormhole_phase":"ascent"})
 check(layer.debug_snapshot()==before,"invalid inputs and foreign telemetry cannot poison state")
 check(Presentation.ordinary_coordinate(1281,1280)==1 and Presentation.ordinary_coordinate(2559,1280)==1279,"ordinary wrap never reverses architecture")
 for period in [640.0,1280.0]:
  check(Presentation.wrapped_offset(-period-22.0,1.0,period)==Presentation.wrapped_offset(period-22.0,1.0,period),"reverse wrap has the same single-tile period "+str(period))
 layer.set_scene_visible(false)
 check(not layer.visible and not world.get_child(0).visible,"leaving visible flight hides both independent roots")
 layer.set_scene_visible(true)
 check(layer.visible and world.get_child(0).visible,"showing current phase restores both roots")
 var saved:Dictionary=route();saved.wormhole_portal.entry=[512.0,-130.0];saved.wormhole_portal.exit=[980.0,-170.0]
 saved.wormhole_portal.aperture_radius=11.0;saved.distance=1400.0;saved.destination_y=-140.0;saved.delivery_radius=7.0
 check(layer.configure_route(saved,world,Vector2(701,321),60),"saved nondefault geometry is supported")
 check(registered(sprite_at(0),Presentation.PORTAL_ANCHOR,Vector2(701,321)+Vector2(512,-130)*60),"saved nondefault entry is preserved")
 check(registered(sprite_at(1),Presentation.PORTAL_ANCHOR,Vector2(701,321)+Vector2(980,-170)*60),"saved nondefault exit is preserved")
 check(registered(sprite_at(2),Vector2(167,307),Vector2(701,321)+Vector2(1400,-140)*60),"saved nondefault destination is preserved")
 check(is_equal_approx(sprite_at(0).scale.y*Presentation.PORTAL_CONTENT_HALF_HEIGHT,11.0*60.0) and is_equal_approx(sprite_at(2).scale.x*59.0,7.0*60.0),"saved aperture and capture radii are used exactly")
 check(layer.sync_telemetry(telemetry("otherworld"),true),"resume picks otherworld on its first authoritative snapshot")
 check(layer.debug_snapshot().live_transitions==0 and layer.debug_snapshot().last_cut_restored and restored_signals==1,"resume suppresses live entry-effect semantics")
 layer.update_view(Vector2(1150,-160),Vector2(24,0),Vector2(1190,-165),true)
 var restored_view:Dictionary=layer.debug_snapshot()
 check(restored_view.blur_pixels==0 and restored_view.relative_camera_m==Vector2(210,5),"resume initializes exit-relative biome instantly without jump blur")
 check(not layer.sync_telemetry(telemetry("otherworld"),true),"repeated resume snapshot does not cut or replay effects")
 layer.configure_route(saved,world,Vector2(701,321),60)
 layer.sync_telemetry(telemetry("ascent"));layer.sync_telemetry(telemetry("otherworld"))
 layer.update_view(Vector2(1150,-160),Vector2(24,0),Vector2(1190,-165),true)
 check(layer.debug_snapshot().far_scroll==restored_view.far_scroll and layer.debug_snapshot().island_scroll==restored_view.island_scroll,"same authoritative location has same composition live and restored")
 var shader:String=FileAccess.get_file_as_string("res://assets/2d_v5/otherworld/otherworld_background.gdshader")
 check(not shader.contains("hint_screen_texture") and not shader.contains("TIME") and shader.contains("i <= 6") and shader.contains("mod(pixel.x"),"texture-local seven-tap shader uses no screen sampling, clock or mirror")
 var dimensions:bool=true
 for extent in [Vector2(1280,720),Vector2(1920,1080),Vector2(3840,2160)]:
  stage.scale=extent/Presentation.LOGICAL_SIZE
  for node in layer.get_children():dimensions=dimensions and node.get_global_transform().get_scale()*node.texture.get_size()==extent
 check(dimensions,"parent-only viewport scale keeps both full-frame planes aligned")
 # Physical circles, including saved nondefault/moving hardware, remain the
 # only source of cap geometry. The narrow energy sprite must not stretch caps.
 var hardware:Array=[
  {"position":Vector2(512,-145),"radius":3.5,"health":100.0,"wormhole_hardware":true},
  {"position":Vector2(512,-113),"radius":4.25,"health":100.0,"wormhole_hardware":true},
  {"position":Vector2(980,-187),"radius":4.0,"health":100.0,"wormhole_hardware":true},
  {"position":Vector2(980,-152),"radius":5.0,"health":100.0,"wormhole_hardware":true},
  {"position":Vector2(700,-150),"radius":8.0,"health":100.0,"wormhole_hardware":false}]
 var physical_copy:Array=hardware.duplicate(true)
 check(layer.configure_route(saved,world,Vector2(701,321),60,hardware),"saved cap geometry configures with exact actual hazards")
 check(hardware==physical_copy and layer.debug_snapshot().hardware_nodes==4 and layer.hardware_node(4)==null,"rendering cannot mutate circles or turn ordinary rocks into portal hardware")
 var cap_registration:bool=true
 for i in 4:
  var cap:Sprite2D=layer.hardware_node(i)
  cap_registration=cap_registration and cap.global_position.distance_to(Vector2(701,321)+hardware[i].position*60)<.03
  cap_registration=cap_registration and absf(cap.global_scale.x*Presentation.CAP_RADIUS-hardware[i].radius*60)<.03 and absf(cap.global_scale.x-cap.global_scale.y)<.001
 check(cap_registration,"nondefault caps retain uniform physical scale despite unequal aperture extents")
 var endpoints:Array=sprite_at(0).get_meta("content_endpoints_m")
 check(endpoints[0].distance_to(Vector2(512,-145+3.5*72/93))<.0001 and endpoints[1].distance_to(Vector2(512,-113-4.25*74/93))<.0001,"energy meets the measured inward emitters instead of entering the metal caps")
 hardware[0].position+=Vector2(.75,-2);hardware[0].radius=4.5;hardware[3].health=0.0
 physical_copy=hardware.duplicate(true);layer.update_hardware(hardware)
 check(layer.hardware_node(0).global_position.distance_to(Vector2(701,321)+hardware[0].position*60)<.03 and absf(layer.hardware_node(0).global_scale.x*93-hardware[0].radius*60)<.03,"live physical center and radius changes update existing cap without route reconstruction")
 check(not layer.hardware_node(3).visible and layer.hardware_node(0).visible and hardware==physical_copy,"destroyed hardware hides without a renderer-side collision or health mutation")
 endpoints=sprite_at(0).get_meta("content_endpoints_m")
 check(endpoints[0].x==512 and absf(endpoints[0].y-(-147+4.5*72/93))<.0001,"moving cap updates its endpoint while the real trigger plane remains fixed")
 layer.set_transit_strength(2.0)
 check(layer.debug_snapshot().transit_strength==1.0 and layer.hardware_node(0).modulate==Color.WHITE and layer.hardware_node(0).self_modulate==Color.WHITE,"bounded transit glow affects energy alone, never hardware opacity")
 layer.set_transit_strength(-1.0);check(layer.debug_snapshot().transit_strength==0.0,"negative transit strength clamps to zero")
 layer.set_transit_strength(NAN);check(layer.debug_snapshot().transit_strength==0.0,"invalid transit strength cannot poison canvas colors")
 var cap_refs:Array=[]
 for i in 4:cap_refs.append(weakref(layer.hardware_node(i)))
 var cap_resource_count:int=int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
 for i in 1200:layer.update_hardware(hardware);layer.set_transit_strength(float(i%19)/18.0)
 check(layer.debug_snapshot().hardware_nodes==4 and int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))<=cap_resource_count,"repeated cap updates and pulse changes allocate no persistent resources")
 var overfull:Array=[]
 for i in 48:overfull.append({"position":Vector2(512,-145-float(i)),"radius":3.5,"health":100.0,"wormhole_hardware":true})
 layer.configure_route(saved,world,Vector2(701,321),60,overfull)
 check(layer.debug_snapshot().hardware_nodes==Presentation.MAX_HARDWARE and layer.hardware_node(Presentation.MAX_HARDWARE)==null,"renderer caps authored hardware nodes independently of hazard count")
 var released:bool=true
 for ref in cap_refs:released=released and ref.get_ref()==null
 check(released,"retry releases every previous cap node and its parent")
 layer.leave_flight()
 check(not layer.route_enabled() and not layer.visible and world.get_child_count()==0 and layer.get_child_count()==2,"leave destroys only props and retains exact two-plane cache")
 check(layer.debug_snapshot().live_transitions==0 and layer.debug_snapshot().pending_sample_reset,"leave clears transition/sample state for retry")
 print("Otherworld presentation: ",passed," passed, ",failed," failed")
 canvas.free();world.free();quit(1 if failed else 0)
