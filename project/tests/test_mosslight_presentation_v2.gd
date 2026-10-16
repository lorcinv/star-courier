extends SceneTree
## Bounded read-only presenter, actual alpha registration and lifecycle coverage.
## Source/import test only; this does not claim a rendered native-window pass.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Receipt=preload("res://scripts/mosslight_receipt_v2.gd")
const Presenter=preload("res://scripts/mosslight_presentation_2d.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
var passed:int=0
var failed:int=0
class VisualFixture extends RefCounted:
 var position:Vector2=Vector2.ZERO
 var status:String="running"
 var obstacles:Array=[]
 func cargo_position() -> Vector2:return position
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var host:Node2D=Node2D.new();root.add_child(host)
 var world:Node2D=Node2D.new();host.add_child(world)
 var presenter=Presenter.new();host.add_child(presenter)
 var route:Dictionary=Profile.route(Content.fresh_catalog())
 if route.is_empty():
  check(false,"mosslight authoring failed before presentation tests");host.free();quit(1);return
 var frozen:Dictionary=route.duplicate(true)
 check(not Caps.group_available("otherworld") and not Caps.group_available("wormhole"),"legacy otherworld and wormhole capabilities remain closed")
 check(Receipt.art_error(false).is_empty(),"actual new and reused raster bytes match pinned mosslight receipt")
 check(Receipt.art_error().is_empty(),"pinned mosslight textures import with registered dimensions")
 var missing:Dictionary=Receipt.ART.duplicate(true);missing.erase(Receipt.RECEIVER)
 check(not Receipt.registered_art_error(missing,false).is_empty(),"missing receiver receipt fails closed")
 var wrong_hash:Dictionary=Receipt.ART.duplicate(true);wrong_hash[Receipt.RECEIVER].sha="0".repeat(64)
 check(not Receipt.registered_art_error(wrong_hash,false).is_empty(),"unregistered replacement bytes fail closed")
 var wrong_size:Dictionary=Receipt.ART.duplicate(true);wrong_size[Receipt.RECEIVER].size=Vector2i(1,1)
 check(not Receipt.registered_art_error(wrong_size).is_empty(),"wrong import dimensions fail closed")
 check(Receipt.route_error({"control_version":"pilot-free-v2"}).is_empty(),"unmarked ordinary route does not inherit mosslight art gate")
 var origin:Vector2=Vector2(31.25,16.75)
 if not presenter.configure_route(route,world,origin,72.0):
  check(false,"complete mosslight receipt required for presenter activation");host.free();quit(1);return
 var model:VisualFixture=VisualFixture.new()
 for raw in route.hazards:
  var hazard:Dictionary=raw.duplicate(true);hazard.position=Vector2(hazard.x,hazard.y)
  hazard.velocity=Vector2.ZERO;model.obstacles.append(hazard)
 var obstacles_before:Array=model.obstacles.duplicate(true)
 model.position=Vector2(180.0,-18.0);presenter.update_from_sim(model,.52,model.position)
 check(presenter.debug_snapshot().weight==1.0,"actual cargo progress reveals the new environment")
 check(presenter.get_child_count()==2 and world.get_child_count()==1,"two backdrop planes and one bounded physical field")
 check(presenter.suppresses_hazard(0) and presenter.suppresses_hazard(2) and not presenter.suppresses_hazard(3),"three actual rocks have a single visual owner")
 var receiver:Sprite2D=presenter.receiver_node()
 var goal:Vector2=origin+Content.DESTINATION*72.0
 var anchor:Vector2=receiver.get_meta("registered_native_anchor")
 check((receiver.position+anchor*receiver.scale).distance_to(goal)<.005,"registered receiver mouth exactly matches capture center")
 check(is_equal_approx(receiver.scale.x*float(receiver.get_meta("registered_native_radius")),Content.DELIVERY_RADIUS*72.0),"source mouth radius exactly matches physical capture radius")
 check(receiver.get_meta("capture_center")==goal,"capture metadata uses solver coordinates")
 check(receiver.region_enabled and receiver.offset==Vector2(receiver.get_meta("painted_native_bounds").position),"runtime-transparent canvas is excluded from framing without moving visible source pixels")
 var receiver_image:Image=receiver.texture.get_image()
 var radius:float=float(receiver.get_meta("registered_native_radius"))
 var raw_nonzero_in_mouth:int=0
 var visible_in_mouth:int=0
 for y in range(maxi(0,int(floor(anchor.y-radius))),mini(receiver_image.get_height(),int(ceil(anchor.y+radius))+1)):
  for x in range(maxi(0,int(floor(anchor.x-radius))),mini(receiver_image.get_width(),int(ceil(anchor.x+radius))+1)):
   if Vector2(x+.5,y+.5).distance_to(anchor)<=radius:
    var alpha:float=receiver_image.get_pixel(x,y).a
    if alpha>0.0:raw_nonzero_in_mouth+=1
    if alpha>Receipt.RECEIVER_ALPHA_CUTOFF+.000001:visible_in_mouth+=1
 print("MOSSLIGHT_RAW_ALPHA_RECEIPT raw_nonzero_in_mouth=",raw_nonzero_in_mouth," visible_alpha_ge_2_in_mouth=",visible_in_mouth," raw_strict_zero=",raw_nonzero_in_mouth==0)
 check(visible_in_mouth==0,"actual receiver has no alpha >= 2/255 pixels in the full physical mouth")
 check(receiver.material.get_shader_parameter("registered_cutout")==true,"runtime material explicitly removes only alpha <= 1/255 tool residue")
 var visible_clipped:int=0
 for y in range(receiver_image.get_height()):
  for x in range(receiver_image.get_width()):
   if receiver_image.get_pixel(x,y).a>Receipt.RECEIVER_ALPHA_CUTOFF+.000001 and not Receipt.RECEIVER_VISIBLE_BOUNDS.has_point(Vector2i(x,y)):visible_clipped+=1
 check(visible_clipped==0,"registered region contains every source alpha >= 2/255 pixel")
 for index in range(3):
  var rock:Sprite2D=presenter._rocks[index]
  var image:Image=rock.texture.get_image();var source_radius:float=float(rock.get_meta("registered_native_radius"))
  var max_distance:float=0.0;var center:Vector2=Vector2(image.get_size())*.5
  for y in range(image.get_height()):
   for x in range(image.get_width()):
    if image.get_pixel(x,y).a>0.0:max_distance=maxf(max_distance,Vector2(x+.5,y+.5).distance_to(center))
  check(max_distance<=source_radius+.001,"rock raster "+str(index)+" fits the disclosed live physical circle")
  check(rock.position==origin+model.obstacles[index].position*72.0,"rock "+str(index)+" has no rendering position offset")
 check(route==frozen and model.obstacles==obstacles_before,"presenter does not mutate route or solver obstacles")
 var far:Sprite2D=presenter.get_child(0);var islands:Sprite2D=presenter.get_child(1)
 var far_phase:Variant=far.material.get_shader_parameter("scroll_px")
 var island_phase:Variant=islands.material.get_shader_parameter("scroll_px")
 presenter.update_from_sim(model,.52,model.position+Vector2(200,40),true)
 check(far.material.get_shader_parameter("scroll_px")==far_phase and islands.material.get_shader_parameter("scroll_px")==island_phase,"paused view has no autonomous or camera-smoothing parallax drift")
 presenter.update_from_sim(model,.52,model.position+Vector2(200,40),false)
 check(islands.material.get_shader_parameter("scroll_px")!=island_phase,"unpaused camera movement resumes parallax")
 presenter.update_from_sim(model,.52,model.position,false)
 check(islands.material.get_shader_parameter("scroll_px")==island_phase,"reverse camera returns to exact coordinate-derived raster phase")
 model.position=Vector2(20,-18);presenter.update_from_sim(model,.52,model.position)
 check(presenter.debug_snapshot().weight==0.0,"returning to departure reverses the environment blend without an entry replay")
 model.obstacles[0].position+=Vector2(.125,-.375);model.obstacles[0].radius=3.125
 model.obstacles[1].health=0.0;presenter.update_from_sim(model,.52,model.position)
 check(presenter._rocks[0].position==origin+model.obstacles[0].position*72.0,"physical rock presentation follows exact live displacement")
 check(is_equal_approx(presenter._rocks[0].scale.x*float(presenter._rocks[0].get_meta("registered_native_radius")),3.125*72.0),"physical circle and raster scale follow live radius")
 check(not presenter._rocks[1].visible and presenter._props.circles.size()==2,"destroyed rock removes both raster and collision disclosure")
 model.position=Content.DESTINATION;model.status="success";presenter.update_from_sim(model,.35,model.position)
 check(presenter.receiver_node()==receiver and presenter._props.received,"success keeps the same registered receiver without an entry effect")
 presenter.set_scene_visible(false);check(not world.get_child(0).visible,"hidden flight hides independently parented props")
 presenter.set_scene_visible(true);check(world.get_child(0).visible,"restoring scene visibility reuses registered props")
 presenter.leave_flight();check(world.get_child_count()==0 and presenter.get_child_count()==0 and not presenter.debug_snapshot().has_sample,"exit frees field and backgrounds and clears phase")
 for index in range(3):
  check(presenter.configure_route(route,world,origin,72.0) and world.get_child_count()==1 and presenter.get_child_count()==2,"repeat configure is bounded: "+str(index))
 model.position=Vector2(170,-22);presenter.update_from_sim(model,.52,model.position,true)
 check(presenter.debug_snapshot().sample_camera==model.position and presenter.debug_snapshot().weight==1.0,"first restored paused sample uses restored coordinates directly")
 var wrong:Dictionary=route.duplicate(true);wrong.mosslight_schema="future-v99"
 check(not presenter.configure_route(wrong,world,origin,72.0) and world.get_child_count()==0 and presenter.get_child_count()==0,"invalid snapshot clears new presentation without fallback art")
 var shader:String=FileAccess.get_file_as_string(Receipt.SHADER)
 check(not shader.contains("TIME") and not shader.contains("SCREEN_TEXTURE"),"background shader has no clock or screen feedback")
 host.free()
 print("MOSSLIGHT_PRESENTATION_V2_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
