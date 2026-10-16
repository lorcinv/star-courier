extends SceneTree
## Real World -> PixelStage -> native HUD layout. Positions below are explicit
## presentation fixtures, not earned flight/settlement or a native-GUI claim.
const Content=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Simulation=preload("res://scripts/pilot_free_simulation_v2.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Stage=preload("res://scripts/pixel_stage.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Framing=preload("res://scripts/free_flight_framing_2d.gd")
var passed:int=0
var failed:int=0
var visible_cases:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle() -> void:
 for unused in 3:await process_frame
func solver_bytes(sim) -> PackedByteArray:
 return var_to_bytes([sim.route,sim.parts,sim.bodies,sim.obstacles,sim.telemetry,sim.elapsed,sim.status])
func physical_bytes(world) -> PackedByteArray:
 var presenter=world.mosslight_presentation
 var rocks:Array=[]
 for rock in presenter._rocks:rocks.append([rock.position,rock.scale,rock.visible])
 return var_to_bytes([world.flight_origin,world.target_center,world.target_zoom,world.smooth_center,world.smooth_zoom,world.camera.position,world.camera.zoom,world.get_viewport().get_canvas_transform(),presenter._props.capture_center,presenter._props.capture_radius,presenter.receiver_node().transform,rocks])
func world_rect(control:Control) -> Rect2:
 var transform:Transform2D=control.get_global_transform()
 var at:Vector2=transform*Vector2.ZERO
 return Rect2(at,transform*control.size-at)
func screen_rect(world,rect:Rect2) -> Rect2:
 var at:Vector2=world._screen_point(rect.position)
 return Rect2(at,world._screen_point(rect.end)-at)
func native_control_rect(control:Control) -> Rect2:
 var transform:Transform2D=control.get_global_transform_with_canvas()
 var at:Vector2=transform*Vector2.ZERO
 return Rect2(at,transform*control.size-at)
func safe_world(world) -> Rect2:
 var extent:Vector2=world.get_viewport_rect().size
 var scene:Vector2=extent*1280.0/extent.x
 var safe:Rect2=Framing.safe_rect(extent,world.screen_mapper)
 return Rect2(world.camera.position+(safe.position-scene*.5)/world.smooth_zoom,safe.size/world.smooth_zoom)
func verify_label(world,hud,label:String,required:bool=false) -> void:
 var presenter=world.mosslight_presentation
 var card:PanelContainer=presenter._label_card
 if required:check(card.is_visible_in_tree(),"safe full label remains available "+label)
 if not card.is_visible_in_tree():return
 visible_cases+=1
 var rect:Rect2=world_rect(card)
 var center:Vector2=presenter._props.capture_center
 var radius:float=presenter._props.capture_radius
 var inside:bool=true
 for point in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
  inside=inside and point.distance_to(center)<=radius-7.9/world.smooth_zoom
 check(inside,"entire card stays inside original transparent mouth "+label)
 check(safe_world(world).encloses(rect),"whole card within actual mapped safe viewport "+label)
 var clear:float=maxf(32.0/world.smooth_zoom,radius*.24)
 check(rect.end.y<=center.y-clear or rect.position.y>=center.y+clear,"capture center stays unobstructed "+label)
 var native:Rect2=screen_rect(world,rect)
 var clear_hud:bool=true
 # Read the actual native widget transforms independently of the world's
 # exclusion mapping; include all existing painted top-level HUD panels.
 for widget in hud.content.get_children():
  if widget is PanelContainer and widget.is_visible_in_tree():
   clear_hud=clear_hud and not native.intersects(native_control_rect(widget))
 check(clear_hud,"full native card avoids real HUD panels "+label)
 var text:Label=presenter._label
 var measure:Vector2=text.get_theme_font("font").get_string_size(text.text,HORIZONTAL_ALIGNMENT_LEFT,-1,text.get_theme_font_size("font_size"))
 check(text.size.x>=measure.x and text.size.y>=text.get_minimum_size().y and not text.clip_text,"all action text fits without clipping "+label)
 check(rect.grow(.01).encloses(world_rect(text)),"entire text rectangle stays in checked card "+label)
 check((presenter.receiver_node().position+Vector2(presenter.receiver_node().get_meta("registered_native_anchor"))*presenter.receiver_node().scale).distance_to(center)<.005,"receiver remains registered to original capture center "+label)
func flight_snapshot(sim) -> Dictionary:
 return {"elapsed":1.0,"control_version":"pilot-free-v2","free_flight":true,"paused":true,"speed":4.8,"cargo_y":sim.cargo_position().y,"energy_remaining":3000.0,"energy_capacity":6000.0,"energy_fraction":.5,"flight_status":sim.status,"events":[],"destination_navigation":{"status":sim.status,"distance_m":sim.cargo_position().distance_to(Content.DESTINATION)}}
func render_hud(hud,sim,route:Dictionary) -> void:
 hud.render({"mode":"flight","control_version":"pilot-free-v2","activeorder":route,"flight":flight_snapshot(sim),"settings":{"reduced_motion":true}})
func move_fixture(sim,at:Vector2,velocity:Vector2) -> void:
 var delta:Vector2=at-sim.cargo_position()
 for body in sim.bodies:body.position+=delta;body.velocity=velocity
func run() -> void:
 var stage=Stage.new();root.add_child(stage)
 var hud=HUD.new();root.add_child(hud)
 var world=World.new();world.catalog=Parts.catalog();world.screen_mapper=stage
 stage.viewport.add_child(world);world.set_process(false);world.protected_bird_hud_root=hud.root
 var route:Dictionary=Profile.route(Content.fresh_catalog());route.contract_id="label-layout-fixture"
 var sim=Simulation.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),route,27)
 # Exactly 17m from the destination at the observed 8.9m altitude.
 var low_approach:Vector2=Vector2(270.0-sqrt(17.0*17.0-9.1*9.1),-8.9)
 check(absf(low_approach.distance_to(Content.DESTINATION)-17.0)<.001,"low approach fixture is 17m from target at height 8.9m")
 var positions:Array=[low_approach,Content.DESTINATION+Vector2(-17,0),Content.DESTINATION+Vector2(17,0),Content.DESTINATION+Vector2(0,-17)]
 for density in ["auto","balanced","low"]:
  for native in [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
   root.size=native;stage.size=Vector2(native);stage.set_density_mode(density)
   hud.set_art_frame(stage.display_rect)
   for index in range(positions.size()):
    var label:String=density+" "+str(native)+" position="+str(index)
    sim.status="running";move_fixture(sim,positions[index],Vector2(-4.8,0) if index==2 else Vector2(4.8,0))
    render_hud(hud,sim,route);await settle()
    var before:PackedByteArray=solver_bytes(sim)
    world.start_flight(sim,true);world.settle_resumed_flight(sim)
    var first_card:PanelContainer=world.mosslight_presentation._label_card
    var first_text:Label=world.mosslight_presentation._label
    var measured:Vector2=first_text.get_combined_minimum_size()+first_card.get_theme_stylebox("panel").get_minimum_size()
    check(first_card.size.x>=measured.x and first_card.size.y>=measured.y,"first paused restore measures full text before container frame "+label)
    await settle();world._update_camera()
    verify_label(world,hud,label,index<=2)
    check(solver_bytes(sim)==before,"layout/restore leave solver bytes unchanged "+label)
    var camera_before:PackedByteArray=physical_bytes(world)
    var card_before:Rect2=world_rect(world.mosslight_presentation._label_card)
    var shown_before:bool=world.mosslight_presentation._label_card.visible
    var sample:Vector2=world.mosslight_presentation.debug_snapshot().sample_camera
    for repeat in 3:world.show_flight(sim,true);world._process(1.0/30.0)
    check(physical_bytes(world)==camera_before,"paused label updates cannot move camera/target/rocks "+label)
    check(world_rect(world.mosslight_presentation._label_card)==card_before and world.mosslight_presentation._label_card.visible==shown_before,"paused candidate stays stable "+label)
    check(world.mosslight_presentation.debug_snapshot().sample_camera==sample,"paused layout leaves background sample frozen "+label)
   # A real paused resize with the same live receiver, then repeated restore.
   move_fixture(sim,low_approach,Vector2(4.8,0));world.settle_resumed_flight(sim)
   var same_receiver:Sprite2D=world.mosslight_presentation.receiver_node()
   stage.size=Vector2(native)+Vector2(160,100);stage._resize_canvas();hud.set_art_frame(stage.display_rect)
   render_hud(hud,sim,route);await settle();world._update_camera()
   check(world.mosslight_presentation.receiver_node()==same_receiver,"paused resize keeps receiver identity "+density+str(native))
   verify_label(world,hud,"paused resize "+density+str(native),true)
   sim.status="success";world.show_flight(sim,true);await settle();world._update_camera()
   check(world.mosslight_presentation._label.text=="货物已签收","signed status retains full action text "+density+str(native))
   verify_label(world,hud,"signed "+density+str(native),true)
 # Focused fail-closed cases use real unchanged target geometry and current
 # camera. Only layout inputs are varied, never world target/camera positions.
 sim.status="running";move_fixture(sim,low_approach,Vector2(4.8,0))
 world.start_flight(sim,true);world.settle_resumed_flight(sim);await settle();world._update_camera()
 var presenter=world.mosslight_presentation
 var safe:Rect2=safe_world(world)
 var geometry:PackedByteArray=physical_bytes(world)
 var saved:PackedByteArray=solver_bytes(sim)
 presenter._layout_label(world.smooth_zoom,safe,[safe])
 check(not presenter._label_card.visible,"fully covered circle omits action rather than overlaps HUD")
 presenter._layout_label(world.smooth_zoom,Rect2(safe.position+Vector2(100000,0),safe.size),[])
 check(not presenter._label_card.visible,"offscreen target never receives a fake screen-edge label")
 presenter._layout_label(world.smooth_zoom,Rect2(),[])
 check(not presenter._label_card.visible,"unknown or collapsed viewport omits action safely")
 presenter._layout_label(.05,Rect2(presenter._props.capture_center-Vector2(100000,100000),Vector2(200000,200000)),[])
 check(not presenter._label_card.visible,"small real circle omits full text instead of shrinking or clipping it")
 presenter._layout_label(world.smooth_zoom,safe,world._protected_bird_hud_rects());await settle()
 verify_label(world,hud,"safe layout returns after offscreen/covered states",true)
 check(physical_bytes(world)==geometry and solver_bytes(sim)==saved,"all omission paths preserve camera/receiver/rocks/solver bytes")
 # Real added HUD occluder must be passed through the World wrapper even when
 # it is outside the usual reserved bands; dismissing it restores the label.
 var modal:PanelContainer=PanelContainer.new();var paint:StyleBoxFlat=StyleBoxFlat.new();paint.bg_color=Color("17243a")
 modal.add_theme_stylebox_override("panel",paint);hud.root.add_child(modal)
 modal.position=Vector2.ZERO;modal.size=hud.root.size;world._update_camera()
 check(not presenter._label_card.visible,"World forwards actual extra HUD occluder on paused update")
 modal.hide();world._update_camera();await settle()
 verify_label(world,hud,"HUD occluder dismissed",true)
 check(physical_bytes(world)==geometry,"HUD changes do not reframe real world target")
 check(visible_cases>=45,"matrix exercises visible labels rather than passing only by omission")
 world.leave_flight();check(not presenter.route_enabled(),"leaving flight clears action-label owner")
 world.free();stage.free();hud.free();await settle()
 print("MOSSLIGHT_LABEL_LAYOUT_DEV17 passed=",passed," failed=",failed," visible_cases=",visible_cases," native_gui=NOT_RUN")
 quit(1 if failed else 0)
