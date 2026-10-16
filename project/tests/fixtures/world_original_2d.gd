extends Node2D
signal loading_complete(order_id:String)
signal shop_navigation_arrived(action_id:String)
## Pure2D presentation. Every painted scene object comes from imagegen raster art.
## Economy and deterministic simulation remain the controller's source of truth.
const ART_ROOT:String="res://assets/2d_v5/"
const SCENE_SIZE:Vector2=Vector2(1280,720)
const CELL:float=72.0
const MAX_VISIBLE_EFFECTS:int=32
const MAX_VISIBLE_RINGS:int=24
const MAX_VISIBLE_JOINTS:int=384
const PILOT_VERTICAL_DEADZONE:float=120.0
const LAUNCH_TRANSFER_DURATION:float=.62
const SHOP_FLOOR_Y:float=486.0
const CRADLE_CONTACT_Y:float=428.0
const WorkshopProfile=preload("res://scripts/workshop_profile.gd")
const WorkshopSupport=preload("res://scripts/workshop_support_presenter_2d.gd")
const MAX_DEPARTURE_TILES:int=24
const MAX_LAUNCH_DECK_STRIPS:int=32
const AssemblyFeedback=preload("res://scripts/assembly_2d.gd")
const FlightBackdrop=preload("res://scripts/flight_backdrop_2d.gd")
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
# Pixel anchor on the top of the generated kiosk deck (279 x 220 source).
const GROUND_RECEIVER_DECK:Vector2=Vector2(139.5,149)
const GROUND_RECEIVER_CLEARANCE:float=32.0
const AscentBackdrop=preload("res://scripts/ascent_backdrop_2d.gd")
const ReadableCorridor=preload("res://scripts/readable_corridor_framing_2d.gd")
const CorridorFraming=preload("res://scripts/corridor_framing_2d.gd")
const PresentationCaps=preload("res://scripts/recovery_presentation_caps.gd")
const BirdProfile=preload("res://scripts/pilot_protected_bird_profile.gd")
const FlightCues=preload("res://scripts/flight_cues_2d.gd")
const MeteorOffers=preload("res://scripts/orbital_meteor_offers.gd")
const MeteorPresentation=preload("res://scripts/orbital_meteor_presentation.gd")
const NpcSprite2D=preload("res://scripts/npc_sprite_2d.gd")
const ActorMotion2D=preload("res://scripts/actor_motion_2d.gd")
const ClerkSingleWalk2D=preload("res://scripts/clerk_recovery_motion_2d.gd")
const ShopLocomotion2D=preload("res://scripts/shop_locomotion_2d.gd")
const ShopInvestigation=preload("res://scripts/shop_investigation.gd")
const ShopSign2D=preload("res://scripts/shop_sign_2d.gd")
const CUSTOMER_HANDOFF_DURATION:float=.12
const COUNTER_TRANSFER_DURATION:float=.40
const CLERK_HANDOFF_DURATION:float=.12
const ROBOT_PICKUP_DURATION:float=.45
const ROBOT_REACH_FRACTION:float=.43
const ROBOT_TURN_DURATION:float=.22
const ROBOT_INSERT_DURATION:float=.60
const CUSTOMER_FAREWELL_DURATION:float=.42
const CUSTOMER_EXIT_X:float=-180.0
const CUSTOMER_WALK_SPEED:float=160.0
const CLERK_HOME_X:float=276.0
const COUNTER_EDGE_X:float=452.0
const ROBOT_COUNTER_CLEAR_X:float=COUNTER_EDGE_X+60.0
const ROBOT_BEHIND_COUNTER_Z:int=4
const ROBOT_AISLE_Z:int=9
const CLERK_ESCORT_GAP:float=132.0
const CLERK_RIGHT_AISLE_GAP:float=180.0
const COOPERATIVE_WALK_SPEED:float=180.0
const CLERK_ALIGN_DURATION:float=.40
const CLERK_CONFIRM_DURATION:float=.40
const MAX_LOADING_PHASE_BOUNDARIES:int=12
var catalog:Dictionary={}
var screen_mapper:Control
var camera:Camera2D
var mode:String="hub"
var night:bool=false
var reduced_motion:bool=false:
 set(value):
  if reduced_motion==value:return
  reduced_motion=value
  if assembly_feedback!=null:assembly_feedback.reduced_motion=value
  if value and is_instance_valid(parcel):_settle_parcel_motion()
var motion_blur_enabled:bool=true
var visual_time:float=0
var launch_age:float=0
var launch_transfer_progress:float=1.0
var _launch_from_offset:Vector2=Vector2.ZERO
var _launch_camera_from:Vector2=SCENE_SIZE*.5
var _launch_zoom_from:float=1.0
var _launch_camera_to:Vector2=Vector2(1115,330)
var _launch_bounds:Rect2
var _launch_center_x:float=1115.0
var _launch_view_zoom:float=1.0
var _backdrop_cargo:Vector2=Vector2.ZERO
var _backdrop_velocity:Vector2=Vector2.ZERO
var _backdrop_progress:float=0.0
var shop_cradle:Sprite2D
var departure_deck:Node2D
var workshop_support:Node2D
var _support_transfer_duration:float=LAUNCH_TRANSFER_DURATION
var workshop_bay:Sprite2D
var expanded_cradle:Node2D
var workshop_tier:int=0
var _workshop_tier_configured:bool=false
var _preview_pad_width:float=-1.0
var _preview_pad_center:float=0.0
var _departure_right_edge:float=-1.0
var route_distance:float=64
var route_radius:float=5
var launcher_design:Array=[]
var assembly_origin:Vector2=Vector2(728,288)
var flight_origin:Vector2=Vector2(660,345)
var target_center:Vector2=SCENE_SIZE*.5
var smooth_center:Vector2=SCENE_SIZE*.5
var target_zoom:float=1.0
var smooth_zoom:float=1.0
var _workshop_view_saved:bool=false
var _workshop_center:Vector2=Vector2(708,315)
var _workshop_zoom:float=1.12
var last_integrity:float=1
var terminal_age:float=-1
var shake:float=0
var selected:int=-1
var active_id:String=""
var parcel_state:String="empty"
var phase:String="day"
var cache:Dictionary={}
var missing_assets:Dictionary={}
var materials:Array=[]
var customers:Dictionary={}
var flight_nodes:Dictionary={}
var trails:Array=[]
var visible_effect_count:int=0
var visible_ring_count:int=0
var background_root:Node2D
var workshop_root:Node2D
var actors_root:Node2D
var foreground_root:Node2D
var ship_root:Node2D
var flight_root:Node2D
var fx_root:Node2D
var effect_node:Node2D
var clerk:Sprite2D
var parcel:Sprite2D
var sky:Sprite2D
var sky_tiles:Array[Sprite2D]=[]
var shell:Sprite2D
var shop_sign:Sprite2D
var backdrop_canvas:CanvasLayer
var _live_design:Array=[]
var _flight_center:Vector2=Vector2.ZERO
var _last_sim=null
var _ascent_view_zoom:float=.35
var _corridor_frame:Dictionary={}
var _corridor_zoom:float=.35
var _effect_pool:Array[Sprite2D]=[]
var assembly_feedback:Node2D
var _parcel_tween:Tween
var _parcel_generation:int=0
var _parcel_phase:String="empty"
var _counter_transfer_start:Vector2=Vector2.ZERO
var _actor_manifest:Dictionary={}
var flight_backdrop:Node2D
var ascent_backdrop:Node2D
var moon_presentation:Node2D
var otherworld_presentation:Node2D
var _restoring_flight_visual:bool=false
var _bird_paused_visual:bool=false
var protected_bird_hud_root:Control
var _wormhole_cue_started:float=-1.0
var _flight_camera_departure:Vector2=Vector2.ZERO
var _loading_requested:bool=false
var _loaded_notified:bool=false
var _transport_age:float=0.0
var _transport_from:Vector2=Vector2.ZERO
var _transport_x:float=516.0
var _transport_leg_from_x:float=516.0
var _transport_leg_to_x:float=444.0
var _transport_leg_duration:float=.5
var _transport_reach_from:Vector2=Vector2.ZERO
var _transport_cargo_snapshot:Vector2=Vector2.ZERO
var _cargo_destination:Vector2=Vector2(728,288)
var _cargo_rotation:float=0.0
var _parcel_base_scale:Vector2=Vector2.ONE
var _scene_paused:bool=false
var _focus_active:bool=true
var _clerk_motion:RefCounted
var _investigation_owner:int=0
var _review_phone_owner:int=0
var _review_phone_facing:bool=false
var _clerk_state:String="counter"
var _clerk_walk_distance:float=0.0
var _clerk_leg_from_x:float=CLERK_HOME_X
var _clerk_leg_to_x:float=CLERK_HOME_X
var _clerk_leg_duration:float=.25
var _clerk_return_requested:bool=false
var _clerk_return_age:float=0.0
var _robot_return_pending:bool=false
var _motion_failures:Dictionary={}
var _shop_motion:RefCounted=ShopLocomotion2D.new()
var _shop_owns_clerk:bool=false
var _shop_input_enabled:bool=false
var _shop_navigation:String=""
var _shop_idle_facing:int=0
var _dialogue_active:bool=false
var _dialogue_order_id:String=""


class DrillPowerCue extends Node2D:
 # A functional motor meter at the real cutter head. The generated housing
 # never spins/deforms; this quiet arc reports paid motor output, not damage.
 var power:float=0.0
 func set_power(value:float) -> void:
  var next:float=clampf(value,0,1) if is_finite(value) else 0.0
  visible=next>.001
  if is_equal_approx(power,next):return
  power=next;queue_redraw()
 func _draw() -> void:
  if power>.001:draw_arc(Vector2(21.6,0),14,-PI*.5,-PI*.5+TAU*power,28,Color("70e9eb"),2,false)

class AssemblyGuide extends Node2D:
 var selected_cell:Vector2=Vector2(INF,INF)
 var cell:float=72
 var bounds:Rect2i=Rect2i(-4,-2,9,5)
 func _draw() -> void:
  # Functional editing overlay, not generated world artwork.
  for x in range(bounds.position.x,bounds.end.x):
   for y in range(bounds.position.y,bounds.end.y):
    var at=Vector2(x,y)*cell
    draw_line(at-Vector2(3,0),at+Vector2(3,0),Color(0.28,.82,.85,.45),1,false)
    draw_line(at-Vector2(0,3),at+Vector2(0,3),Color(0.28,.82,.85,.45),1,false)
  if is_finite(selected_cell.x):draw_rect(Rect2(selected_cell*cell-Vector2.ONE*cell*.49,Vector2.ONE*cell*.98),Color("fff4d2"),false,2,false)
var grid:AssemblyGuide

func _group(label:String,parent:Node=self) -> Node2D:
 var node=Node2D.new();node.name=label;parent.add_child(node);return node

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 get_viewport().disable_3d=true
 var manifest_path:String=ART_ROOT+"actors/actor-manifest.json"
 if FileAccess.file_exists(manifest_path):
  var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
  if manifest is Dictionary:_actor_manifest=manifest.get("actors",{})
 backdrop_canvas=CanvasLayer.new();backdrop_canvas.layer=-10;add_child(backdrop_canvas)
 background_root=_group("GeneratedCityLayer",backdrop_canvas)
 for i in range(3):sky_tiles.append(_sprite("environment/far-city",background_root,Vector2(1280,720)))
 sky=sky_tiles[1];sky.position=SCENE_SIZE*.5
 flight_backdrop=FlightBackdrop.new();background_root.add_child(flight_backdrop);flight_backdrop.hide()
 ascent_backdrop=AscentBackdrop.new();background_root.add_child(ascent_backdrop);ascent_backdrop.configure_route({"background_route":"city"})
 # Missing special-route groups are rejected by Main before saving/dispatch.
 # Do not eagerly load their absent art or create an ordinary receiver stand-in.
 if PresentationCaps.group_available("otherworld"):
  otherworld_presentation=load("res://scripts/otherworld_presentation_2d.gd").new();otherworld_presentation.name="RegisteredOtherworldPresentation";background_root.add_child(otherworld_presentation)
 if PresentationCaps.group_available("moon"):
  moon_presentation=load("res://scripts/moon_presentation_2d.gd").new();moon_presentation.name="MoonPresentation";background_root.add_child(moon_presentation)
 workshop_root=_group("GeneratedShopLayer")
 shell=_sprite("environment/shop-shell",workshop_root,SCENE_SIZE);shell.position=SCENE_SIZE*.5
 shop_sign=ShopSign2D.new();workshop_root.add_child(shop_sign)
 workshop_bay=Sprite2D.new();workshop_bay.name="GeneratedRightWorkshopBay";workshop_bay.centered=false;workshop_bay.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;workshop_bay.hide();workshop_root.add_child(workshop_bay)
 actors_root=_group("GeneratedActors");actors_root.z_index=3
 ship_root=_group("EditableModuleSprites");ship_root.z_index=5
 assembly_feedback=AssemblyFeedback.new();assembly_feedback.name="CourierRobotAssembly";add_child(assembly_feedback)
 assembly_feedback.configure(assembly_origin,CELL);assembly_feedback.bind_part_root(ship_root)
 foreground_root=_group("GeneratedForeground");foreground_root.z_index=8
 _placed_prop("props/counter-pixel","props/counter",Vector2(222,486),410,foreground_root)
 var marble:=_placed_prop(ShopInvestigation.ART_ID,ShopInvestigation.ART_ID,ShopInvestigation.PROP_BOTTOM,ShopInvestigation.PROP_WIDTH,foreground_root);marble.name="StoredBlackMarble"
 shop_cradle=_placed_prop("props/launch-cradle-pixel","props/launch-cradle",Vector2(1115,486),300,foreground_root)
 expanded_cradle=_group("ExpandedWorkshopDepartureCradle",foreground_root);expanded_cradle.hide()
 departure_deck=_group("GroundedDepartureDeck",workshop_root)
 workshop_support=WorkshopSupport.new();workshop_support.name="GroundedWorkshopSupports";workshop_root.add_child(workshop_support)
 _extend_departure_deck(1280.0)
 clerk=_actor("clerk",actors_root,210);clerk.position=Vector2(CLERK_HOME_X,SHOP_FLOOR_Y)
 _clerk_motion=ClerkSingleWalk2D.new(clerk,"clerk",210)
 _clerk_motion.apply_idle(false)
 parcel=_sprite("npcs/shared/customer-parcel-neutral-pixel",actors_root,Vector2(49,49.0*45.0/66.0));parcel.position=Vector2(222,385);parcel.z_index=10;parcel.hide();_parcel_base_scale=parcel.scale
 flight_root=_group("LiveSimulationSprites");flight_root.z_index=5;flight_root.hide()
 fx_root=_group("GeneratedFlightEffects");fx_root.z_index=6
 effect_node=_group("BoundedSpriteEffects",fx_root);effect_node.hide()
 for i in range(MAX_VISIBLE_EFFECTS):
  var effect=_sprite("flight/impact",effect_node,Vector2(48,48));effect.hide();_effect_pool.append(effect)
 grid=AssemblyGuide.new();grid.cell=CELL;grid.z_index=20;grid.position=assembly_origin;add_child(grid);grid.hide()
 camera=Camera2D.new();camera.name="PixelCamera2D";camera.position_smoothing_enabled=false;camera.rotation_smoothing_enabled=false;camera.position=smooth_center;add_child(camera);camera.make_current()
 visibility_changed.connect(_on_world_visibility_changed)
 get_viewport().size_changed.connect(_update_camera)
 set_workshop_tier(workshop_tier)
 _update_camera()

func _texture(id:String) -> Texture2D:
 var resolved:String=id
 if id=="modules/joint":resolved="modules/cohesion/joint-collar-pixel"
 elif id=="modules/coupler":resolved="modules/cohesion/coupler-latch-pixel"
 elif id.begins_with("modules/") and ResourceLoader.exists(ART_ROOT+id+"-pixel.png"):resolved=id+"-pixel"
 elif id.begins_with("actors/"):
  if ResourceLoader.exists(ART_ROOT+id+"-pixel.png"):resolved=id+"-pixel"
  elif ResourceLoader.exists(ART_ROOT+id+"-native.png"):resolved=id+"-native"
 var path:String=ART_ROOT+resolved+".png"
 if cache.has(path):return cache[path]
 if ResourceLoader.exists(path):
  var texture=load(path) as Texture2D
  if texture!=null:cache[path]=texture;missing_assets.erase(path);return texture
 missing_assets[path]=true
 if not cache.has("missing:"+path):push_warning("Missing generated2D sprite: "+path);cache["missing:"+path]=true
 return null

func _sprite(id:String,parent:Node,size:Vector2=Vector2.ZERO,height:float=0) -> Sprite2D:
 var node=Sprite2D.new();node.texture=_texture(id);node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;node.set_meta("art_id",id);parent.add_child(node)
 if node.texture!=null:
  if height>0:node.scale=Vector2.ONE*height/float(node.texture.get_height())
  elif size!=Vector2.ZERO:node.scale=size/Vector2(node.texture.get_size())
 return node

func _actor(id:String,parent:Node,height:float) -> Sprite2D:
 var node=_sprite("actors/"+id+"-idle",parent)
 var anchor:Array=_actor_manifest.get(id,{}).get("foot_anchor",[86,248] if id=="clerk" else [73,248])
 node.centered=false;node.offset=-Vector2(float(anchor[0]),float(anchor[1]))
 node.scale=Vector2.ONE*height/240.0;node.set_meta("actor_id",id);return node

func _actor_parcel_point(node:Sprite2D,id:String) -> Vector2:
 if id=="clerk" and _clerk_motion!=null and _clerk_motion.has_method("dialogue_anchor_parent"):
  var registered:Vector2=_clerk_motion.dialogue_anchor_parent("parcel",false)
  if registered.is_finite():return registered
 var values:Array=_actor_manifest.get(id,{}).get("poses",{}).get("handoff",{}).get("hand_and_parcel_anchors",{}).get("parcel",[80,138])
 return node.transform*(Vector2(float(values[0]),float(values[1]))+node.offset)

func _actor_pose(node:Sprite2D,id:String,handoff:bool) -> void:
 if id=="clerk":handoff=handoff or _clerk_supports_counter_parcel()
 if id=="clerk" and (_review_phone_owner!=0 or _investigation_owner!=0):return
 if id=="clerk" and _clerk_motion!=null and _clerk_motion.has_method("apply_dialogue"):
  if handoff or _dialogue_active:_record_motion_result(_clerk_motion.apply_dialogue(handoff,false),"clerk_dialogue" if not handoff else "clerk_handoff",clerk)
  else:_record_motion_result(_clerk_motion.apply_idle(false),"clerk_idle",clerk)
  return
 var pose:String="handoff" if handoff else "idle"
 if str(node.get_meta("pose",""))==pose:return
 var art=_texture("actors/"+id+"-"+pose)
 if art!=null:node.texture=art;node.set_meta("pose",pose)

func _placed_prop(id:String,fallback:String,bottom:Vector2,width:float,parent:Node) -> Sprite2D:
 var use_id:String=id if ResourceLoader.exists(ART_ROOT+id+".png") else fallback
 var prop=_sprite(use_id,parent)
 if prop.texture!=null:
  prop.scale=Vector2.ONE*width/float(prop.texture.get_width());prop.position=bottom-Vector2(0,prop.texture.get_height()*prop.scale.y*.5)
 return prop

func _clear(node:Node) -> void:
 for child in node.get_children():node.remove_child(child);child.queue_free()

func workshop_grid_rect() -> Rect2:
 var bounds:Rect2i=WorkshopProfile.bounds(workshop_tier)
 return Rect2(assembly_origin+(Vector2(bounds.position)-Vector2.ONE*.5)*CELL,Vector2(bounds.size)*CELL)

func workshop_exit_x() -> float:
 if workshop_tier==0 or workshop_bay==null or workshop_bay.texture==null:return 1280.0
 return workshop_bay.position.x+float(workshop_bay.texture.get_width())

func set_workshop_tier(tier:int) -> bool:
 if not WorkshopProfile.is_valid_tier(tier):return false
 if tier==workshop_tier and _workshop_tier_configured:return false
 workshop_tier=tier;assembly_origin=WorkshopProfile.assembly_origin(tier)
 # Support setup before tree entry without touching unconstructed scene nodes.
 if workshop_bay==null:return true
 _workshop_tier_configured=true;_workshop_view_saved=false
 _preview_pad_width=-1.0;_departure_right_edge=-1.0
 workshop_bay.visible=tier>0
 if tier>0:
  workshop_bay.texture=_texture("workshop-support/right-bay-tier%d-floor-reconstructed"%tier)
  workshop_bay.position=WorkshopProfile.bay_top_left(tier);workshop_bay.scale=Vector2.ONE
 else:workshop_bay.texture=null
 grid.bounds=WorkshopProfile.bounds(tier);grid.position=assembly_origin;grid.queue_redraw()
 assembly_feedback.configure(assembly_origin,CELL)
 show_design(_live_design,selected)
 focus(mode)
 return true

func _configure_transport_extent() -> void:
 var bounds:Rect2i=WorkshopProfile.bounds(workshop_tier)
 var far_cell_x:float=assembly_origin.x+float(bounds.end.x-1)*CELL-88.0
 # Preserve the original route for its usual cargo cells while allowing every
 # paid cell (and a retained legacy cargo location) to be reached physically.
 var right:float=maxf(AssemblyFeedback.MAX_X,maxf(far_cell_x,_cargo_destination.x-88.0))
 var left:float=minf(AssemblyFeedback.MIN_X,_cargo_destination.x-88.0)
 assembly_feedback.configure_transport_bounds(left,right,SHOP_FLOOR_Y,AssemblyFeedback.ROBOT_SPEED,AssemblyFeedback.MAX_TRAVEL_SECONDS)

func _expanded_pad_center(craft_width:float) -> float:
 # Leave a real approach apron for the unchanged simulation's rear launcher.
 return workshop_exit_x()+240.0+craft_width*.5

func _sync_expanded_cradle() -> void:
 if expanded_cradle==null:return
 shop_cradle.visible=workshop_tier==0 and mode!="flight"
 expanded_cradle.visible=workshop_tier>0 and mode!="flight"
 if workshop_tier==0:
  _clear(expanded_cradle);_extend_departure_deck(1280.0);return
 var left:float=INF;var right:float=-INF
 for part in _live_design:
  left=minf(left,(float(part.x)-.49)*CELL);right=maxf(right,(float(part.x)+.49)*CELL)
 var craft_width:float=right-left if is_finite(left) else CELL*.98
 var width:float=maxf(300.0,craft_width+60.0)
 var center:float=_expanded_pad_center(craft_width)
 if is_equal_approx(width,_preview_pad_width) and is_equal_approx(center,_preview_pad_center):return
 _preview_pad_width=width;_preview_pad_center=center
 _clear(expanded_cradle);_build_cradle_deck(expanded_cradle,center,width)
 _extend_departure_deck(center+width*.5+12.0)

func _hub_frame() -> Rect2:
 var frame:Rect2=Rect2(Vector2.ZERO,SCENE_SIZE)
 if workshop_tier>0 and workshop_bay.texture!=null:
  frame=frame.merge(Rect2(workshop_bay.position,Vector2(workshop_bay.texture.get_size())))
  frame=frame.expand(Vector2(maxf(workshop_exit_x(),_departure_right_edge),SHOP_FLOOR_Y))
 return frame

func focus(target:String,instant:bool=false) -> void:
 if target=="flight":set_shop_input(0.0,false)
 if target=="flight" and is_loading():fastforward_loading()
 mode=target
 var airborne:bool=mode=="flight"
 var ascent:bool=airborne and _last_sim!=null and str(_last_sim.route.get("control_version","")) in ["pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird"]
 var in_otherworld:bool=otherworld_presentation!=null and otherworld_presentation.otherworld_active()
 if flight_backdrop!=null:flight_backdrop.visible=airborne and not ascent
 if ascent_backdrop!=null:ascent_backdrop.visible=not airborne or (ascent and not in_otherworld)
 if otherworld_presentation!=null:otherworld_presentation.set_scene_visible(airborne)
 if moon_presentation!=null:moon_presentation.set_scene_visible(airborne)
 for tile in sky_tiles:tile.hide()
 # The physical shop is left behind by the camera, never replaced with sky at
 # dispatch. Keep the same counter, floor, robot and launch architecture alive.
 if assembly_feedback!=null:assembly_feedback.set_scene_visible(true)
 workshop_root.show();actors_root.show();foreground_root.show();ship_root.visible=not airborne;flight_root.visible=airborne
 if shop_cradle!=null:shop_cradle.visible=not airborne and workshop_tier==0
 if expanded_cradle!=null:expanded_cradle.visible=not airborne and workshop_tier>0
 grid.visible=mode=="workshop"
 if target=="contracts":target_center=Vector2(464,345);target_zoom=1.38
 elif target=="workshop":
  var area:Rect2=workshop_grid_rect()
  var default_center:Vector2=Vector2(708,315) if workshop_tier==0 else area.get_center()
  var default_zoom:float=1.12 if workshop_tier==0 else minf(900.0/area.size.x,470.0/area.size.y)
  target_center=_workshop_center if _workshop_view_saved else default_center
  target_zoom=_workshop_zoom if _workshop_view_saved else default_zoom
 elif target=="supply":target_center=Vector2(604,346);target_zoom=1.06
 elif not airborne:
  if workshop_tier==0:target_center=SCENE_SIZE*.5;target_zoom=1.0
  else:
   var frame:Rect2=_hub_frame();target_center=frame.get_center()
   target_zoom=minf(SCENE_SIZE.x/(frame.size.x+96.0),SCENE_SIZE.y/(frame.size.y+96.0))
 if is_loading_scene():_frame_loading_action()
 if instant:smooth_center=target_center;smooth_zoom=target_zoom;_update_camera()

func show_design(design:Array,chosen:int=-1) -> void:
 if assembly_feedback!=null:assembly_feedback.bind_part_root(ship_root)
 _live_design=design.duplicate(true);selected=chosen;_clear(ship_root);ship_root.position=assembly_origin
 grid.selected_cell=Vector2(INF,INF)
 for part in design:
  var node=_module(part,ship_root);node.position=Vector2(part.x,part.y)*CELL;node.rotation=float(part.get("rot",0))*PI*.5
  if str(part.type)=="cargo":
   _cargo_destination=assembly_origin+Vector2(part.x,part.y)*CELL
   _cargo_rotation=float(part.get("rot",0))*PI*.5
   node.set_meta("is_cargo",true)
  if int(part.id)==chosen:grid.selected_cell=Vector2(part.x,part.y)
 _design_joints(design,ship_root)
 if workshop_support!=null:workshop_support.sync_assembly(_workshop_support_nodes(ship_root),_workshop_support_edges(ship_root))
 _configure_transport_extent();_sync_expanded_cradle();_configure_shop_route()
 if parcel_state=="loaded":parcel.position=_cargo_destination
 if mode=="hub" and workshop_tier>0:focus("hub")
 _sync_cargo_visibility()
 grid.queue_redraw()

func _module(part:Dictionary,parent:Node) -> Sprite2D:
 var sprite=_sprite("modules/"+str(part.type),parent,Vector2.ONE*CELL*.98)
 sprite.name="Part"+str(part.id);sprite.set_meta("part_id",int(part.id))
 if str(part.type)=="thruster":
  var plume=_sprite("flight/exhaust",sprite,Vector2(95,49));plume.name="Exhaust";plume.flip_h=true;plume.position=Vector2(-77,0);plume.z_index=-1;plume.hide()
 if str(part.type)=="drill":
  var motor=DrillPowerCue.new();motor.name="PoweredDrillCue";motor.hide();sprite.add_child(motor)
 return sprite

func _design_joints(parts:Array,parent:Node) -> void:
 var count:int=0
 for i in range(parts.size()):
  for j in range(i+1,parts.size()):
   var a:Dictionary=parts[i];var b:Dictionary=parts[j]
   if absi(int(a.x)-int(b.x))+absi(int(a.y)-int(b.y))!=1:continue
   var sleeve=_sprite("modules/joint",parent,Vector2(26,23));sleeve.position=(Vector2(a.x,a.y)+Vector2(b.x,b.y))*.5*CELL;sleeve.rotation=(Vector2(b.x,b.y)-Vector2(a.x,a.y)).angle();sleeve.z_index=-1
   sleeve.set_meta("structural_edge",[int(a.id),int(b.id)]);count+=1
   if count>=MAX_VISIBLE_JOINTS:return

func apply_workshop_camera(center_value:Vector2,zoom_value:float) -> void:
 if not center_value.is_finite() or not is_finite(zoom_value) or zoom_value<=0:return
 _workshop_view_saved=true;_workshop_center=center_value;_workshop_zoom=zoom_value
 if mode!="workshop":return
 target_center=center_value;smooth_center=center_value;target_zoom=zoom_value;smooth_zoom=zoom_value
 _update_camera()

func cell_at(pixel:Vector2) -> Vector2i:
 var point:Vector2=get_viewport().get_canvas_transform().affine_inverse()*pixel
 return Vector2i(((point-assembly_origin)/CELL).round())

func update_shop_state(data:Dictionary) -> void:
 phase=str(data.get("phase","day"));night=phase=="night"
 workshop_root.modulate=Color("677394") if night else Color.WHITE
 actors_root.modulate=workshop_root.modulate;foreground_root.modulate=workshop_root.modulate;ship_root.modulate=workshop_root.modulate
 if assembly_feedback!=null:assembly_feedback.modulate=workshop_root.modulate
 var seen:Array=[];var contracts:Array=data.get("contracts",[])
 for i in range(contracts.size()):
  var contract:Dictionary=contracts[i];var id:String=str(contract.contract_id);seen.append(id)
  var binding:Dictionary=_customer_binding(contract)
  if not customers.has(id):
   var actor=NpcSprite2D.new();actors_root.add_child(actor);actor.configure(binding,215)
   actor.counter_pose_resumed.connect(_sync_customer_parcel)
   # Customer stands on the near side of the counter; the clerk stays behind it.
   actor.z_index=10;actor.position=Vector2(-100-float(i)*110,488)
   customers[id]={"node":actor,"target":actor.position,"phase":str(contract.status),"binding":binding,"departure":"present","departure_age":0.0,"walk_distance":0.0}
  var customer:Dictionary=customers[id];customer.phase=str(contract.status)
  if customer.binding!=binding:
   customer.node.configure(binding,215);customer.binding=binding
   customer.node.set_pose(id==active_id and _parcel_phase in ["customer_handoff","waiting_customer"])
  customer.node.set_conversation(_dialogue_active and (_dialogue_order_id.is_empty() or id==_dialogue_order_id))
  customer.node.set_meta("contract_id",id)
  customer.node.set_meta("story_id",str(contract.get("story_id","")))
  customer.node.set_meta("story_node",int(contract.get("story_node",0)))
  var hidden:bool=night or str(contract.status) in ["declined","cancelled","settled"] or (i>0 and str(contracts[0].status) in ["available","accepted"])
  if str(customer.departure)=="departed":
   customer.target=Vector2(CUSTOMER_EXIT_X,488);customer.node.hide()
  elif str(customer.departure) in ["farewell","exiting"]:pass
  else:customer.target=Vector2(-110-float(i)*105,488) if hidden else Vector2(148,488)
 for id in customers.keys():
  if not id in seen:
   actors_root.remove_child(customers[id].node);customers[id].node.queue_free();customers.erase(id)
 var current:String=str(data.get("active_contract_id",""))
 var current_contract:Dictionary={}
 for contract in contracts:
  if str(contract.get("contract_id",""))==current:current_contract=contract;break
 if str(current_contract.get("status","")) in ["cancelled","declined","settled","failed"]:current=""
 var released:Variant=data.get("handoff_released",current_contract.get("handoff_released",null))
 var already_loaded:bool=bool(data.get("cargo_loaded",current_contract.get("cargo_loaded",false)))
 if current!=active_id:
  _cancel_parcel_transfer();active_id=current
  _loading_requested=false;_loaded_notified=false
  parcel.scale=_parcel_base_scale;parcel.rotation=0.0
  if current.is_empty():parcel.hide();parcel_state="empty";_parcel_phase="empty";_set_counter_poses();prepare_counter_interaction()
  elif already_loaded:restore_loaded(current)
  elif released!=null:
   parcel_state="accepted";_parcel_phase="waiting_customer"
   _set_counter_poses(active_id);_sync_customer_parcel()
  else:
   if prepare_counter_interaction():_start_counter_handoff()
   else:parcel_state="accepted";_parcel_phase="waiting_clerk";_set_counter_poses(active_id);_sync_customer_parcel()
 if not active_id.is_empty():
  if already_loaded and parcel_state!="loaded":restore_loaded(active_id)
  elif released!=null and bool(released) and parcel_state!="loaded":begin_loading(active_id)
 if assembly_feedback!=null:
  assembly_feedback.on_order_changed(active_id,"loaded" if parcel_state=="loaded" else ("loading" if _loading_requested else ("accepted" if not active_id.is_empty() else "empty")))
 _sync_customer_parcel();_sync_cargo_visibility()

func _customer_binding(contract:Dictionary) -> Dictionary:
 # Copy only identity inputs; status/story updates must not reset a live pose or
 # reroll an accessory. Empty legacy contracts use the adapter's human fallback.
 var binding:Dictionary={}
 for key in ["appearance_id","appearance_seed","species","accessory_id"]:
  if contract.has(key):binding[key]=contract[key]
 return binding.duplicate(true)

func _customer_parcel_point(order_id:String) -> Vector2:
 if customers.has(order_id):return customers[order_id].node.parcel_point()
 return Vector2(202,367)

func _sync_customer_parcel() -> void:
 if not _parcel_phase in ["waiting_customer","waiting_clerk","customer_handoff"]:return
 parcel.position=_customer_parcel_point(active_id)
 var actor=customers.get(active_id,{}).get("node")
 parcel.visible=is_instance_valid(actor) and not actor.pose_contains_parcel()

func _clerk_supports_counter_parcel() -> bool:
 # One presentation authority, derived from the existing order/phase/contact.
 # No additional timer, transferable item, or independent ownership state.
 if active_id.is_empty() or not is_instance_valid(parcel) or not parcel.visible:return false
 if parcel_state=="counter":return _parcel_phase in ["counter_transfer","clerk_handoff","counter"]
 if parcel_state!="loading":return false
 if _parcel_phase=="robot_fetch":return true
 return _parcel_phase=="robot_pickup" and _transport_age/ROBOT_PICKUP_DURATION<ROBOT_REACH_FRACTION

func _sync_clerk_counter_support() -> void:
 if _clerk_supports_counter_parcel() and _clerk_state=="counter" and str(clerk.get_meta("pose",""))!="handoff":
  _actor_pose(clerk,"clerk",true)

func set_dialogue_active(active:bool,order_id:String="") -> void:
 _dialogue_active=active;_dialogue_order_id=order_id if active else ""
 for id in customers:
  customers[id].node.set_conversation(active and (order_id.is_empty() or str(id)==order_id))
 if _review_phone_owner==0 and _investigation_owner==0 and is_instance_valid(clerk) and _clerk_state=="counter":_actor_pose(clerk,"clerk",false)

func _set_counter_poses(customer_id:String="",clerk_handoff:bool=false) -> void:
 for id in customers:
  var customer:Dictionary=customers[id]
  customer.node.rotation=0.0
  if str(customer.departure)=="departed":customer.node.hide();continue
  if str(customer.departure) in ["farewell","exiting"]:continue
  customer.node.set_pose(not customer_id.is_empty() and id==customer_id)
 if is_instance_valid(clerk) and _clerk_state=="counter":
  clerk.rotation=0.0;_clerk_motion.restore_original();_actor_pose(clerk,"clerk",clerk_handoff)

func _begin_customer_departure() -> void:
 if not customers.has(active_id):return
 var customer:Dictionary=customers[active_id]
 if str(customer.departure)!="present":return
 customer.departure="farewell";customer.departure_age=0.0
 customer.target=customer.node.position;customer.node.rotation=0.0
 _record_motion_result(customer.node.set_gesture("farewell",true),"customer_farewell",customer.node)

func _settle_customer_departure() -> void:
 if not customers.has(active_id):return
 var customer:Dictionary=customers[active_id]
 customer.departure="departed";customer.departure_age=0.0
 customer.target=Vector2(CUSTOMER_EXIT_X,488);customer.node.position=customer.target
 customer.node.set_pose(false);customer.node.rotation=0.0;customer.node.hide()

func _step_customers(delta:float) -> void:
 for id in customers:
  var customer:Dictionary=customers[id];var node:Sprite2D=customer.node
  node.set_visual_context(visual_time,true,reduced_motion)
  if str(customer.departure)=="departed":node.hide();continue
  var remaining:float=delta
  if str(customer.departure)=="farewell":
   var consumed:float=minf(remaining,maxf(0.0,CUSTOMER_FAREWELL_DURATION-float(customer.departure_age)))
   customer.departure_age+=consumed;remaining-=consumed
   node.rotation=0.0;_record_motion_result(node.set_gesture("farewell",true),"customer_farewell",node)
   if float(customer.departure_age)<CUSTOMER_FAREWELL_DURATION:continue
   customer.departure="exiting";customer.target=Vector2(CUSTOMER_EXIT_X,488)
  var before:Vector2=node.position
  if customer.get("walk_target",Vector2(INF,INF))!=customer.target:
   customer.walk_from=node.position;customer.walk_target=customer.target;customer.walk_age=0.0
   customer.walk_duration=maxf(.25,node.position.distance_to(customer.target)/CUSTOMER_WALK_SPEED+.2)
  customer.walk_age=minf(float(customer.walk_age)+remaining,float(customer.walk_duration))
  node.position=Vector2(customer.walk_from).lerp(customer.target,_customer_walk_progress(float(customer.walk_age),float(customer.walk_duration)))
  var travelled:float=node.position.distance_to(before)
  if travelled>.00001:
   customer.walk_distance+=travelled;node.rotation=0.0
   customer.rig_stop_age=0.0;customer.rig_facing=node.position.x>before.x
   if node.supports_state_locomotion():
    var ramp:float=minf(.2,float(customer.walk_duration)*.35)
    var motion_state:String="start" if float(customer.walk_age)<ramp else ("inertial_stop" if float(customer.walk_age)>float(customer.walk_duration)-ramp else "move")
    _record_motion_result(node.set_locomotion(motion_state,float(customer.walk_distance),bool(customer.rig_facing),visual_time),"customer_"+motion_state,node)
   else:_record_motion_result(node.set_walk(float(customer.walk_distance),node.position.x>before.x),"customer_walk",node)
  elif str(customer.departure)=="exiting" and float(customer.walk_age)>=float(customer.walk_duration):
   customer.departure="departed";node.set_pose(false);node.hide()
  elif id==active_id and (_parcel_phase in ["waiting_customer","waiting_clerk","customer_handoff"] or (_parcel_phase=="counter_transfer" and node.supports_counter_transfer_pose())):
   node.set_pose(true);node.rotation=0.0
  elif node.supports_state_locomotion():
   customer.rig_stop_age=float(customer.get("rig_stop_age",0.0))+remaining
   var motion_state:String="stop" if float(customer.rig_stop_age)<.30 else "idle"
   _record_motion_result(node.set_locomotion(motion_state,float(customer.walk_distance),bool(customer.get("rig_facing",true)),visual_time,float(customer.rig_stop_age)),"customer_"+motion_state,node)
   node.rotation=0.0
  else:
   node.set_pose(false)
   var seed_phase:float=float(posmod(int(node.appearance_seed),101))*.061
   node.rotation=sin(visual_time*1.35+seed_phase)*.004 if not reduced_motion else 0.0

func _customer_walk_progress(age:float,duration:float) -> float:
 # Integral of a short eased velocity ramp: an NPC starts and stops on the
 # floor, without adding idle bob or a frame-rate-dependent spring overshoot.
 if duration<=0:return 1.0
 var t:float=clampf(age,0.0,duration)
 var ramp:float=minf(.2,duration*.35)
 if t>=duration:return 1.0
 if t>duration-ramp:return 1.0-_customer_walk_progress(duration-t,duration)
 if t>=ramp:return (t-ramp*.5)/(duration-ramp)
 var u:float=t/ramp
 return ramp*(u*u*u-.5*u*u*u*u)/(duration-ramp)

func _set_clerk_walk_x(at_x:float) -> void:
 var distance:float=absf(at_x-clerk.position.x)
 var right:bool=at_x>=clerk.position.x
 clerk.position=Vector2(at_x,SHOP_FLOOR_Y);clerk.rotation=0.0
 if distance>.00001:
  _clerk_walk_distance+=distance;_record_motion_result(_clerk_motion.apply_walk(_clerk_walk_distance,right),"clerk_walk",clerk)

func _set_clerk_leg(destination_x:float) -> void:
 _clerk_leg_from_x=clerk.position.x;_clerk_leg_to_x=destination_x
 _clerk_leg_duration=maxf(.25,absf(destination_x-clerk.position.x)/COOPERATIVE_WALK_SPEED+AssemblyFeedback.MOTION_RAMP_SECONDS)

func _set_clerk_gesture(pose:String) -> void:
 clerk.rotation=0.0;_record_motion_result(_clerk_motion.apply_gesture(pose,_cargo_destination.x>=clerk.position.x),"clerk_"+pose,clerk)

func _record_motion_result(ok:bool,beat:String,node:CanvasItem) -> void:
 if not ok and node.is_visible_in_tree() and _motion_failures.size()<8:_motion_failures[beat]=true

func _clerk_loaded_x() -> float:
 var dock_x:float=assembly_feedback.transport_dock_x(_cargo_destination)
 # Keep the helper out of the parcel/craft vertical column. A leftmost cargo
 # uses the safe right aisle instead of sending the clerk through the counter.
 return dock_x-CLERK_ESCORT_GAP if dock_x-CLERK_ESCORT_GAP>=COUNTER_EDGE_X else maxf(COUNTER_EDGE_X,dock_x+CLERK_RIGHT_AISLE_GAP)

func prepare_counter_interaction() -> bool:
 if _review_phone_owner!=0 or _investigation_owner!=0:return false
 if _shop_owns_clerk:
  if is_loading_scene():return false
  if not _clerk_return_requested:
   _shop_navigation="";_shop_motion.navigate_to(CLERK_HOME_X-ShopLocomotion2D.COUNTER_MIN_X)
   _clerk_return_requested=true;_clerk_state="return_shop"
  return false
 # The controller may poll this before opening dialogue. Repeated requests do
 # not restart a route; the clerk returns through the same counter right edge.
 if _clerk_state=="counter" and is_equal_approx(clerk.position.x,CLERK_HOME_X):return true
 if is_loading_scene():return false
 if not _clerk_return_requested:
  _clerk_return_requested=true;_clerk_return_age=0.0
  _clerk_state="return_aisle" if clerk.z_index>0 else "return_behind"
  _set_clerk_leg(COUNTER_EDGE_X if _clerk_state=="return_aisle" else CLERK_HOME_X)
 return false

func _step_clerk_return(delta:float) -> void:
 if not _clerk_return_requested:return
 if _clerk_state=="return_shop":
  _shop_motion.set_blockers([assembly_feedback.robot_root.position]);_shop_motion.step(delta);_apply_shop_motion()
  if _shop_motion.arrived():
   _shop_owns_clerk=false;_shop_motion.clear_input();_clerk_return_requested=false;_clerk_state="counter";clerk.z_index=0
   _clerk_motion.restore_original();_actor_pose(clerk,"clerk",false)
   if _parcel_phase=="waiting_clerk" and not active_id.is_empty():
    if _loading_requested:_start_counter_handoff()
    else:_parcel_phase="waiting_customer";_set_counter_poses(active_id);_sync_customer_parcel()
  return
 var remaining:float=delta
 for boundary in 2:
  var used:float=minf(remaining,maxf(0.0,_clerk_leg_duration-_clerk_return_age))
  _clerk_return_age+=used;remaining-=used
  _set_clerk_walk_x(assembly_feedback.sample_transport_x(_clerk_leg_from_x,_clerk_leg_to_x,_clerk_return_age,_clerk_leg_duration))
  if _clerk_return_age<_clerk_leg_duration:return
  if _clerk_state=="return_aisle":
   clerk.z_index=0;_clerk_state="return_behind";_clerk_return_age=0.0;_set_clerk_leg(CLERK_HOME_X)
  else:
   _clerk_return_requested=false;_clerk_state="counter";clerk.z_index=0
   _clerk_motion.restore_original();_actor_pose(clerk,"clerk",false)
   if _parcel_phase=="waiting_clerk" and not active_id.is_empty():
    if _loading_requested:_start_counter_handoff()
    else:_parcel_phase="waiting_customer";_set_counter_poses(active_id);_sync_customer_parcel()
   return
  if remaining<=0:return

func _step_robot_return() -> void:
 if not _robot_return_pending or is_loading_scene():return
 # Both actors share one foreground aisle. Keep the robot planted until the
 # clerk is back behind the counter rather than driving through her feet.
 if _clerk_return_requested or _clerk_state!="counter":return
 _robot_return_pending=false
 if not is_equal_approx(assembly_feedback.transport_current_x(),AssemblyFeedback.DOCK_X):
  assembly_feedback.release_transport()

func _sync_robot_counter_depth() -> void:
 # Resolve both inbound and outbound travel from geometry, not a prior order's
 # last phase. The separate claw remains above the counter during pickup.
 assembly_feedback.z_index=ROBOT_BEHIND_COUNTER_Z if assembly_feedback.transport_current_x()<ROBOT_COUNTER_CLEAR_X else ROBOT_AISLE_Z

func _parcel_transition_valid(order_id:String,generation:int,state:String) -> bool:
 return active_id==order_id and _parcel_generation==generation and parcel_state==state

func _start_counter_handoff() -> void:
 parcel_state="counter";parcel.position=_customer_parcel_point(active_id);parcel.scale=_parcel_base_scale;parcel.rotation=0.0
 if reduced_motion:_settle_parcel_motion();return
 # Three nonhuman handoff sprites contain parcels; human and clerk have empty
 # hands. Explicit asset semantics choose the single visible representation.
 _parcel_phase="customer_handoff";_set_counter_poses(active_id);_sync_customer_parcel()
 var generation:int=_parcel_generation;var order_id:String=active_id
 _parcel_tween=create_tween()
 _parcel_tween.tween_interval(CUSTOMER_HANDOFF_DURATION)
 _parcel_tween.tween_callback(_begin_counter_transfer.bind(order_id,generation))
 _parcel_tween.tween_method(_move_counter_parcel.bind(order_id,generation),0.0,1.0,COUNTER_TRANSFER_DURATION)
 _parcel_tween.tween_callback(_receive_counter_parcel.bind(order_id,generation))
 _parcel_tween.tween_interval(CLERK_HANDOFF_DURATION)
 _parcel_tween.tween_callback(_finish_counter_handoff.bind(order_id,generation))
 _sync_parcel_clock()

func _begin_counter_transfer(order_id:String,generation:int) -> void:
 if not _parcel_transition_valid(order_id,generation,"counter"):return
 _counter_transfer_start=_customer_parcel_point(order_id)
 # Receiver is visibly ready before the first parcel travel sample. Human
 # empty giving hands remain raised through contact; baked nonhuman boxes
 # retain their existing single-representation switch.
 var giver:String=order_id if customers.has(order_id) and customers[order_id].node.supports_counter_transfer_pose() else ""
 _set_counter_poses(giver,true);_parcel_phase="counter_transfer"
 parcel.position=_counter_transfer_start;parcel.show()

func _move_counter_parcel(progress:float,order_id:String,generation:int) -> void:
 if not _parcel_transition_valid(order_id,generation,"counter") or _parcel_phase!="counter_transfer":return
 parcel.position=_counter_transfer_start.lerp(_actor_parcel_point(clerk,"clerk"),progress)

func _receive_counter_parcel(order_id:String,generation:int) -> void:
 if not _parcel_transition_valid(order_id,generation,"counter"):return
 parcel.position=_actor_parcel_point(clerk,"clerk");parcel.show()
 _set_counter_poses("",true);_parcel_phase="clerk_handoff"

func _finish_counter_handoff(order_id:String,generation:int) -> void:
 if not _parcel_transition_valid(order_id,generation,"counter"):return
 _parcel_phase="counter";_set_counter_poses()
 parcel.position=_actor_parcel_point(clerk,"clerk");parcel.show();_parcel_tween=null
 if _loading_requested:_start_robot_fetch()

func _cancel_parcel_transfer() -> void:
 _parcel_generation+=1
 if _parcel_tween!=null and _parcel_tween.is_valid():_parcel_tween.kill()
 _parcel_tween=null
 if assembly_feedback!=null:
  assembly_feedback.hold_transport_position()
  _robot_return_pending=true
  _sync_robot_counter_depth()
 _parcel_phase=parcel_state;_set_counter_poses()
 _transport_age=0.0

func _settle_parcel_motion() -> void:
 if _loading_requested and not active_id.is_empty():
  fastforward_loading();return
 var waiting:bool=_parcel_phase in ["waiting_customer","waiting_clerk"]
 _cancel_parcel_transfer()
 if waiting:
  _parcel_phase="waiting_customer";_set_counter_poses(active_id);_sync_customer_parcel()
 elif parcel_state=="counter":parcel.position=_actor_parcel_point(clerk,"clerk");parcel.show()
 else:
  if parcel_state=="loaded":parcel.position=_cargo_destination
  parcel.hide()
 _sync_clerk_counter_support();_sync_cargo_visibility()

func begin_loading(order_id:String="") -> bool:
 if _review_phone_owner!=0 or _investigation_owner!=0:return false
 cancel_shop_navigation()
 if active_id.is_empty() or (not order_id.is_empty() and order_id!=active_id):return false
 if parcel_state=="loaded" or _loading_requested:return true
 _loading_requested=true
 if reduced_motion:fastforward_loading();return true
 if _parcel_phase in ["waiting_customer","waiting_clerk"] or parcel_state=="accepted":
  # Request the return before claiming loading input ownership.
  if _clerk_state!="counter":
   _loading_requested=false;prepare_counter_interaction();_loading_requested=true
   _parcel_phase="waiting_clerk";_set_counter_poses(active_id);_sync_customer_parcel()
  else:_start_counter_handoff()
 elif _parcel_phase=="counter":_start_robot_fetch()
 return true

func pack_parcel() -> void:
 begin_loading()

func is_loading() -> bool:
 return _loading_requested and parcel_state!="loaded" and not active_id.is_empty()

func is_loading_scene() -> bool:
 return is_loading()

func is_parcel_loaded(order_id:String="") -> bool:
 return not active_id.is_empty() and parcel_state=="loaded" and (order_id.is_empty() or active_id==order_id)

func restore_loaded(order_id:String) -> void:
 if order_id.is_empty() or order_id!=active_id:return
 _cancel_parcel_transfer();_loading_requested=false;_loaded_notified=true
 parcel_state="loaded";_parcel_phase="loaded";parcel.position=_cargo_destination
 parcel.scale=_parcel_base_scale;parcel.rotation=0.0;parcel.hide()
 _settle_loaded_actors();_sync_cargo_visibility()
 if assembly_feedback!=null:assembly_feedback.on_order_changed(order_id,"loaded")

func fastforward_loading(order_id:String="") -> bool:
 if active_id.is_empty() or (not order_id.is_empty() and order_id!=active_id):return false
 if parcel_state=="loaded":return true
 _cancel_parcel_transfer();_loading_requested=true
 _complete_loading(active_id,_parcel_generation)
 return true

func _start_robot_fetch() -> void:
 if not _loading_requested or active_id.is_empty() or parcel_state=="loaded":return
 _parcel_generation+=1
 parcel_state="loading";_parcel_phase="robot_fetch";_transport_age=0.0
 _robot_return_pending=false
 _transport_x=assembly_feedback.transport_current_x()
 _begin_customer_departure()
 assembly_feedback.acquire_transport(active_id)
 assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,false,"carry-empty")
 _sync_robot_counter_depth()
 _set_transport_leg(AssemblyFeedback.COUNTER_X)
 _sync_clerk_counter_support();_sync_cargo_visibility()

func _set_transport_leg(destination_x:float) -> void:
 _transport_leg_from_x=_transport_x;_transport_leg_to_x=destination_x
 _transport_leg_duration=maxf(.25,absf(_transport_x-destination_x)/COOPERATIVE_WALK_SPEED+AssemblyFeedback.MOTION_RAMP_SECONDS)

func _begin_transport_phase(next_phase:String) -> void:
 _parcel_phase=next_phase;_transport_age=0.0;_transport_from=parcel.position
 if next_phase=="robot_pickup":_transport_reach_from=assembly_feedback.transport_hand_point()
 elif next_phase=="clerk_round_counter":
  _clerk_state="round_counter";clerk.z_index=0;_set_clerk_leg(COUNTER_EDGE_X)
  var dock_x:float=assembly_feedback.transport_dock_x(_cargo_destination)
  var left_side:bool=_clerk_loaded_x()<dock_x
  _set_transport_leg(COUNTER_EDGE_X+CLERK_ESCORT_GAP if left_side else dock_x)
 elif next_phase=="clerk_join":
  _clerk_state="join";clerk.z_index=8;_sync_robot_counter_depth()
  var left_side:bool=_clerk_loaded_x()<assembly_feedback.transport_dock_x(_cargo_destination)
  _set_clerk_leg(_transport_x-CLERK_ESCORT_GAP if left_side else maxf(COUNTER_EDGE_X,_transport_x+CLERK_RIGHT_AISLE_GAP))
  # Waiting at the counter edge is not a loading confirmation. Keep empty
  # hands here; the tablet first appears after the escort reaches the cargo.
  if is_equal_approx(_clerk_leg_from_x,_clerk_leg_to_x):
   clerk.rotation=0.0
   _record_motion_result(_clerk_motion.apply_idle(_cargo_destination.x>=clerk.position.x),"clerk_join_wait",clerk)
 elif next_phase=="robot_carry":
  _clerk_state="escort";_transport_cargo_snapshot=_cargo_destination
  _set_transport_leg(assembly_feedback.transport_dock_x(_cargo_destination));_set_clerk_leg(_clerk_loaded_x())
 elif next_phase=="robot_insert":_clerk_state="reach";_set_clerk_gesture("reach")
 elif next_phase=="clerk_align":_clerk_state="align";_set_clerk_gesture("align")
 elif next_phase=="clerk_confirm":_clerk_state="ready";_set_clerk_gesture("ready")

func _step_parcel_transport(delta:float,boundaries:int=0) -> void:
 if not is_loading() or parcel_state!="loading" or _scene_paused or not _focus_active or not is_visible_in_tree() or mode=="flight":return
 if not is_finite(delta) or delta<=0 or boundaries>=MAX_LOADING_PHASE_BOUNDARIES:return
 if str(assembly_feedback.debug_snapshot().transport_owner)!=active_id:assembly_feedback.acquire_transport(active_id)
 # Edits during insertion/alignment invalidate only the presentation leg, never
 # the order generation or parcel identity. Return to the latest real cargo.
 if _parcel_phase in ["robot_carry","robot_insert","clerk_align","clerk_confirm"] and _transport_cargo_snapshot!=_cargo_destination:
  _begin_transport_phase("robot_carry")
 var clerk_supported_before:bool=_clerk_supports_counter_parcel()
 _transport_age+=delta
 var grip:Vector2=parcel.position
 var show_grip:bool=false
 var carryover:float=0.0
 match _parcel_phase:
  "robot_fetch":
   _transport_x=assembly_feedback.sample_transport_x(_transport_leg_from_x,_transport_leg_to_x,_transport_age,_transport_leg_duration)
   var velocity:float=assembly_feedback.sample_transport_velocity(_transport_leg_from_x,_transport_leg_to_x,_transport_age,_transport_leg_duration)
   assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,false,"carry-empty",velocity)
   if _transport_age>=_transport_leg_duration:
    carryover=_transport_age-_transport_leg_duration;_begin_transport_phase("robot_pickup")
  "robot_pickup":
   assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,false,"carry-empty")
   var t:float=clampf(_transport_age/ROBOT_PICKUP_DURATION,0.0,1.0)
   show_grip=true
   if t<ROBOT_REACH_FRACTION:
    parcel.position=_transport_from
    grip=_transport_reach_from.lerp(_transport_from,smoothstep(0.0,1.0,t/ROBOT_REACH_FRACTION))
   else:
    var lift:float=smoothstep(0.0,1.0,(t-ROBOT_REACH_FRACTION)/(1.0-ROBOT_REACH_FRACTION))
    parcel.position=_transport_from.lerp(assembly_feedback.transport_hand_point(),lift);grip=parcel.position
   if t>=1.0:
    carryover=_transport_age-ROBOT_PICKUP_DURATION;_begin_transport_phase("robot_turn")
  "robot_turn":
   var t:float=clampf(_transport_age/ROBOT_TURN_DURATION,0.0,1.0)
   assembly_feedback.drive_transport_turn(active_id,_transport_x,t)
   parcel.position=assembly_feedback.transport_hand_point()+Vector2(0,10.0*sin(t*PI)*sin(t*PI))
   grip=parcel.position;show_grip=true
   if t>=1.0:
    carryover=_transport_age-ROBOT_TURN_DURATION;_begin_transport_phase("clerk_round_counter")
  "clerk_round_counter","clerk_join":
   var duration:float=_clerk_leg_duration
   var velocity:float=0.0
   if _parcel_phase=="clerk_round_counter":
    # The robot clears the opening first while the clerk is still behind the
    # counter. They meet with a real body-width gap instead of crossing feet.
    duration=maxf(duration,_transport_leg_duration)
    _transport_x=assembly_feedback.sample_transport_x(_transport_leg_from_x,_transport_leg_to_x,_transport_age,_transport_leg_duration)
    velocity=assembly_feedback.sample_transport_velocity(_transport_leg_from_x,_transport_leg_to_x,_transport_age,_transport_leg_duration)
   assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,true,"carry-empty",velocity)
   parcel.position=assembly_feedback.transport_hand_point();grip=parcel.position;show_grip=true
   _set_clerk_walk_x(assembly_feedback.sample_transport_x(_clerk_leg_from_x,_clerk_leg_to_x,_transport_age,_clerk_leg_duration))
   if _transport_age>=duration:
    carryover=_transport_age-duration
    _begin_transport_phase("clerk_join" if _parcel_phase=="clerk_round_counter" else "robot_carry")
  "robot_carry":
   _transport_x=assembly_feedback.sample_transport_x(_transport_leg_from_x,_transport_leg_to_x,_transport_age,_transport_leg_duration)
   var velocity:float=assembly_feedback.sample_transport_velocity(_transport_leg_from_x,_transport_leg_to_x,_transport_age,_transport_leg_duration)
   assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,true,"carry-empty",velocity)
   _set_clerk_walk_x(assembly_feedback.sample_transport_x(_clerk_leg_from_x,_clerk_leg_to_x,_transport_age,_transport_leg_duration))
   parcel.position=assembly_feedback.transport_hand_point();grip=parcel.position;show_grip=true
   if _transport_age>=_transport_leg_duration:
    carryover=_transport_age-_transport_leg_duration;_begin_transport_phase("robot_insert")
  "robot_insert":
   assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,true,"carry-empty")
   var t:float=clampf(_transport_age/ROBOT_INSERT_DURATION,0.0,1.0)
   parcel.position=_transport_from.lerp(_cargo_destination,smoothstep(0.0,1.0,t))
   parcel.scale=_parcel_base_scale;parcel.rotation=lerpf(0.0,_cargo_rotation,smoothstep(0.0,1.0,t))
   grip=parcel.position;show_grip=true
   if t>=1.0:
    carryover=_transport_age-ROBOT_INSERT_DURATION;_begin_transport_phase("clerk_align")
  "clerk_align","clerk_confirm":
   assembly_feedback.drive_transport(active_id,_parcel_phase,_transport_x,true,"carry-empty")
   parcel.position=_cargo_destination;grip=parcel.position;show_grip=true
   var duration:float=CLERK_ALIGN_DURATION if _parcel_phase=="clerk_align" else CLERK_CONFIRM_DURATION
   if _transport_age>=duration:
    carryover=_transport_age-duration
    if _parcel_phase=="clerk_align":_begin_transport_phase("clerk_confirm")
    else:_complete_loading(active_id,_parcel_generation)
 _sync_robot_counter_depth()
 if is_loading() and show_grip:assembly_feedback.grip_transport_parcel(active_id,grip)
 # Release only after the same frame has put the real gripper on the parcel.
 # Before ROBOT_REACH_FRACTION, all neutral/dialogue calls preserve the clerk.
 if clerk_supported_before and not _clerk_supports_counter_parcel() and _clerk_state=="counter":
  _actor_pose(clerk,"clerk",false)
 _sync_clerk_counter_support()
 # At most twelve positive-duration boundaries can be consumed per active
 # frame; no wall clock is consulted and paused time is never caught up.
 if is_loading() and carryover>0:_step_parcel_transport(carryover,boundaries+1)

func _settle_loaded_actors() -> void:
 _release_shop_control()
 _settle_customer_departure();_clerk_return_requested=false;_clerk_return_age=0.0;_robot_return_pending=false
 _clerk_state="ready";clerk.position=Vector2(_clerk_loaded_x(),SHOP_FLOOR_Y);clerk.z_index=8
 _set_clerk_gesture("ready")
 _transport_x=assembly_feedback.transport_dock_x(_cargo_destination)
 assembly_feedback.release_transport_at_workbench(active_id,_transport_x)
 _sync_robot_counter_depth()

func _complete_loading(order_id:String,generation:int) -> void:
 if active_id!=order_id or _parcel_generation!=generation or parcel_state=="loaded":return
 parcel.position=_cargo_destination;parcel.hide();parcel.scale=_parcel_base_scale;parcel.rotation=0.0
 parcel_state="loaded";_parcel_phase="loaded";_loading_requested=false;_parcel_tween=null
 _settle_loaded_actors();_sync_cargo_visibility()
 assembly_feedback.on_order_changed(order_id,"loaded")
 if not _loaded_notified:
  _loaded_notified=true;loading_complete.emit(order_id)

func _frame_loading_action() -> void:
 if not is_loading_scene() or mode=="flight":return
 var center_x:float=(clerk.position.x+_transport_x)*.5
 if _parcel_phase in ["waiting_clerk","customer_handoff","counter_transfer","clerk_handoff","robot_fetch","robot_pickup","robot_turn"]:center_x=366.0
 var top:float=minf(270.0,parcel.position.y-55.0)
 target_center=Vector2(center_x,(top+SHOP_FLOOR_Y)*.5-12.0)
 target_zoom=minf(1.28,530.0/maxf(300.0,SHOP_FLOOR_Y-top+80.0))
 # Keep the painted shop left edge outside the visible viewport throughout.
 target_center.x=maxf(target_center.x,SCENE_SIZE.x/(2.0*target_zoom))

func _finish_parcel_transfer(order_id:String,generation:int) -> void:
 # Kept as a stale-callback compatibility guard for the prior packing adapter.
 if _parcel_transition_valid(order_id,generation,"loading"):_complete_loading(order_id,generation)

func _sync_cargo_visibility() -> void:
 if not is_instance_valid(ship_root):return
 for node in ship_root.get_children():
  if node is Sprite2D and bool(node.get_meta("is_cargo",false)):
   node.visible=active_id.is_empty() or parcel_state=="loaded"

func _on_world_visibility_changed() -> void:
 _scene_paused=not is_visible_in_tree()
 if _scene_paused:set_shop_input(0.0,false)
 if not _scene_paused and _clerk_state=="ready":_set_clerk_gesture("ready")
 _sync_parcel_clock()

func set_focus_active(active:bool) -> void:
 _focus_active=active
 if not active:set_shop_input(0.0,false)
 if assembly_feedback!=null:assembly_feedback.set_focus_active(active)
 _sync_parcel_clock()

func _sync_parcel_clock() -> void:
 if _parcel_tween!=null and _parcel_tween.is_valid():
  if _scene_paused or not _focus_active:_parcel_tween.pause()
  else:_parcel_tween.play()

func loading_snapshot() -> Dictionary:
 var customer:Dictionary=customers.get(active_id,{})
 var actor=customer.get("node")
 return {"order_id":active_id,"state":parcel_state,"phase":_parcel_phase,"loading":is_loading(),
  "parcel_instance":parcel.get_instance_id(),"parcel_visible":parcel.visible,"parcel_position":parcel.position,
  "cargo_destination":_cargo_destination,"notified":_loaded_notified,"generation":_parcel_generation,
  "clerk_state":_clerk_state,"clerk_position":clerk.position,"clerk_z":clerk.z_index,"clerk_returning":_clerk_return_requested,
  "clerk_motion":_clerk_motion.debug_snapshot(),"clerk_walk_distance":_clerk_walk_distance,
  "clerk_supports_parcel":_clerk_supports_counter_parcel(),"robot_pickup_progress":_transport_age/ROBOT_PICKUP_DURATION if _parcel_phase=="robot_pickup" else -1.0,"robot_grip_point":assembly_feedback.transport_grip_point(),
  "customer_departure":str(customer.get("departure","absent")),"customer_position":actor.position if is_instance_valid(actor) else Vector2.ZERO,
  "customer_motion":actor.debug_snapshot() if is_instance_valid(actor) else {},
  "robot":assembly_feedback.debug_snapshot(),"robot_return_pending":_robot_return_pending,"scene_paused":_scene_paused or not _focus_active,
  "camera_center":target_center,"camera_zoom":target_zoom,"motion_failures":_motion_failures.duplicate()}

func _configure_shop_route() -> void:
 # The original launch cradle starts at x965. Expanded launch machinery lives
 # beyond the bay exit; neither is part of the player's walking floor.
 # Reserve a full extended shoe, not only the registered hip/foot origin.
 var right:float=864.0 if workshop_tier==0 else workshop_exit_x()-96.0
 _shop_motion.configure(right)

func can_open_investigation() -> bool:
 return _shop_control_available() and not _dialogue_active and _clerk_state in ["counter","free"] and _parcel_phase in ["empty","counter","loaded"] and str(shop_interaction().get("id",""))==ShopInvestigation.ACTION

func investigation_owned_by(owner:int) -> bool:
 return owner!=0 and _investigation_owner==owner and _review_phone_owner==0 and _focus_active and not _scene_paused and is_visible_in_tree() and mode=="hub" and not is_loading_scene() and not _dialogue_active and not _clerk_return_requested

func acquire_investigation(owner:int) -> bool:
 if owner==0 or not can_open_investigation():return false
 _investigation_owner=owner
 cancel_shop_navigation();_shop_input_enabled=false;_shop_motion.clear_input()
 # Freeze the existing registered cutout pose. This object owns no gesture,
 # tablet, waving pose, animation clock, root relocation, or duplicated body.
 if _clerk_motion.has_method("set_visual_context"):_clerk_motion.set_visual_context(visual_time,false,reduced_motion)
 return true

func release_investigation(owner:int) -> void:
 if owner==0 or _investigation_owner!=owner:return
 _investigation_owner=0
 cancel_shop_navigation();_shop_input_enabled=false;_shop_motion.clear_input()
 if _clerk_motion.has_method("set_visual_context"):_clerk_motion.set_visual_context(visual_time,false,reduced_motion)

func can_open_review_phone() -> bool:
 return _review_phone_owner==0 and _investigation_owner==0 and _shop_control_available() and not _dialogue_active and _clerk_state in ["counter","free","ready"] and _parcel_phase in ["empty","counter","loaded"]

func review_phone_owned_by(owner:int) -> bool:
 return owner!=0 and _review_phone_owner==owner and _focus_active and not _scene_paused and is_visible_in_tree() and mode=="hub" and not is_loading_scene() and not _dialogue_active and not _clerk_return_requested

func acquire_review_phone(owner:int) -> bool:
 if owner==0 or not can_open_review_phone():return false
 _review_phone_facing=bool(_clerk_motion.debug_snapshot().get("facing_right",false))
 _review_phone_owner=owner
 cancel_shop_navigation();_shop_input_enabled=false;_shop_motion.clear_input()
 # Only the adapter changes presentation. The world root, depth, direction,
 # and source registration stay fixed; this never invokes the cargo gesture.
 if not _clerk_motion.apply_gesture("align",_review_phone_facing):
  release_review_phone(owner);return false
 return true

func release_review_phone(owner:int) -> void:
 if owner==0 or _review_phone_owner!=owner:return
 _review_phone_owner=0
 # A completed cargo pose is no longer an active script owner. Phone dismissal
 # leaves empty hands until a fresh walk or another explicit story action.
 if _clerk_state=="ready":_clerk_state="free"
 cancel_shop_navigation();_shop_input_enabled=false;_shop_motion.clear_input()
 if is_instance_valid(clerk):_record_motion_result(_clerk_motion.apply_idle(_review_phone_facing),"clerk_phone_close",clerk)

func _shop_control_available(from_drawer:bool=false) -> bool:
 return _review_phone_owner==0 and _investigation_owner==0 and (mode=="hub" or (from_drawer and mode in ["contracts","workshop","supply","report","help"])) and _focus_active and not _scene_paused and is_visible_in_tree() and not is_loading_scene() and not _clerk_return_requested and not _clerk_supports_counter_parcel() and _parcel_phase not in ["customer_handoff","counter_transfer","clerk_handoff"]

func _adopt_shop_clerk() -> void:
 _configure_shop_route();_shop_motion.adopt_position(clerk.position)
 _shop_motion.distance=_clerk_walk_distance;_shop_owns_clerk=true;_clerk_state="free"

func set_shop_input(axis:float,enabled:bool=true) -> void:
 # The host owns modal/page input. This second gate also protects direct calls,
 # focus loss and a newly starting cutscene; neither can retain movement input.
 var allowed:bool=enabled and _shop_control_available()
 _shop_input_enabled=allowed
 if not allowed:
  if not _clerk_return_requested:cancel_shop_navigation()
  var returning:bool=_clerk_return_requested and _clerk_state=="return_shop" and mode=="hub" and _focus_active and not _scene_paused and is_visible_in_tree()
  _shop_motion.set_input(0.0,false,returning)
  if _shop_owns_clerk and not _clerk_return_requested:_apply_shop_motion()
  return
 if not _shop_owns_clerk and is_finite(axis) and absf(axis)>=ShopLocomotion2D.INPUT_EPSILON and not bool(_shop_motion.snapshot().needs_neutral):
  _adopt_shop_clerk();_shop_motion.set_input(0.0,true)
 _shop_motion.set_input(axis,true)
 if absf(axis)>=ShopLocomotion2D.INPUT_EPSILON and not _shop_motion.is_navigating():_shop_navigation=""

func _shop_stations() -> Array:
 return [
  {"id":"focus_counter","label":"接待客户","coordinate":CLERK_HOME_X-ShopLocomotion2D.COUNTER_MIN_X,"radius":64.0,"enabled":not night},
  {"id":ShopInvestigation.ACTION,"label":"查看黑色弹珠","coordinate":_shop_motion.coordinate_for_front_x(ShopInvestigation.STATION_X),"radius":ShopInvestigation.STATION_RADIUS,"enabled":true},
  {"id":"focus_workbench","label":"工位","coordinate":_shop_motion.coordinate_for_front_x(assembly_origin.x),"radius":100.0,"enabled":true},
  {"id":"focus_supply","label":"夜间补给","coordinate":_shop_motion.coordinate_for_front_x(490.0),"radius":52.0,"enabled":night}]

func is_at_shop_counter() -> bool:
 return is_instance_valid(clerk) and clerk.position.distance_to(Vector2(CLERK_HOME_X,SHOP_FLOOR_Y))<=.1 and not is_loading_scene() and not _clerk_return_requested and _focus_active and not _scene_paused

func shop_interaction() -> Dictionary:
 if _review_phone_owner!=0 or _investigation_owner!=0:return {}
 if mode!="hub" or is_loading_scene() or _clerk_return_requested or not _focus_active or _scene_paused:return {}
 var nearest:Dictionary={};var best:float=INF
 for station in _shop_stations():
  var at:Vector2=_shop_motion.point_at(float(station.coordinate))
  var gap:float=_shop_motion.distance_to(float(station.coordinate)) if _shop_owns_clerk else clerk.position.distance_to(at)
  if gap<=float(station.radius) and gap<best:
   best=gap;nearest=station.duplicate();nearest.distance=gap;nearest.position=_screen_point(at-Vector2(0,216))
 return nearest

func can_request_shop_navigation(action_id:String,from_drawer:bool=false) -> bool:
 # Read-only projection for HUD actions that first close a shop drawer. This
 # does not move the clerk or grant an input owner permission to navigate.
 if not _shop_control_available(from_drawer):return false
 for station in _shop_stations():
  if str(station.id)==action_id:return bool(station.enabled)
 return false

func request_shop_navigation(action_id:String) -> bool:
 if not can_request_shop_navigation(action_id):return false
 for station in _shop_stations():
  if str(station.id)!=action_id or not bool(station.enabled):continue
  var at:Vector2=_shop_motion.point_at(float(station.coordinate))
  # Counter UI requires the registered home position so parcel handoffs cannot
  # begin from a remote clerk. Other panels use their meaningful nearby range.
  var tolerance:float=.1 if action_id=="focus_counter" else float(station.radius)
  if clerk.position.distance_to(at)<=tolerance and not _clerk_return_requested:
   if action_id=="focus_counter":_release_shop_control();_clerk_state="counter";clerk.z_index=0;_clerk_motion.restore_original();_actor_pose(clerk,"clerk",false)
   return true
  if not _shop_owns_clerk:_adopt_shop_clerk()
  _shop_motion.navigate_to(float(station.coordinate));_shop_navigation=action_id
  return false
 return false

func cancel_shop_navigation() -> void:
 _shop_navigation=""
 if not _clerk_return_requested:_shop_motion.cancel_navigation()

func _release_shop_control() -> void:
 _shop_owns_clerk=false;_shop_input_enabled=false;_shop_navigation="";_shop_idle_facing=0
 _shop_motion.clear_input();_shop_motion.cancel_navigation()

func _apply_shop_motion() -> void:
 if _clerk_supports_counter_parcel():_sync_clerk_counter_support();return
 if _review_phone_owner!=0 or _investigation_owner!=0:return
 var previous:Vector2=clerk.position
 clerk.position=_shop_motion.position;clerk.rotation=0.0
 clerk.z_index=0 if _shop_motion.rear_lane() else 11
 _clerk_walk_distance=_shop_motion.distance
 if not clerk.is_visible_in_tree():return
 if _clerk_motion.has_method("apply_player_pose"):
  _record_motion_result(_clerk_motion.apply_player_pose(_shop_motion.state,_clerk_walk_distance,_shop_motion.facing_right,_focus_active and not _scene_paused and (_shop_input_enabled or _clerk_return_requested),visual_time,_shop_motion.stop_age),"clerk_"+_shop_motion.state,clerk)
  return
 # Legacy adapter remains usable in isolated historical fixtures. The live
 # single-walk adapter above never selects a run or an open-hand idle.
 if _shop_motion.state in ["idle","stop"]:
  _record_motion_result(_clerk_motion.apply_idle(_shop_motion.facing_right),"clerk_idle",clerk)
 elif clerk.position.distance_to(previous)>.000001:
  _record_motion_result(_clerk_motion.apply_walk(_clerk_walk_distance,_shop_motion.facing_right),"clerk_"+_shop_motion.state,clerk)

func _step_shop_locomotion(delta:float) -> void:
 if _shop_owns_clerk and not _clerk_return_requested and _shop_control_available():
  _shop_motion.set_blockers([assembly_feedback.robot_root.position]);_shop_motion.step(delta);_apply_shop_motion()
  if not _shop_navigation.is_empty() and _shop_motion.arrived():
   var arrived:String=_shop_navigation;_shop_navigation=""
   if arrived=="focus_counter":
    _release_shop_control();_clerk_state="counter";clerk.z_index=0;_clerk_motion.restore_original();_actor_pose(clerk,"clerk",false)
   shop_navigation_arrived.emit(arrived)
 if (_shop_input_enabled or (_shop_owns_clerk and _clerk_return_requested)) and mode=="hub" and not is_loading_scene():
  # At large tiers the free-roam camera follows the actual clerk at readable
  # scale; the separate workbench editor retains its saved pan and zoom.
  target_zoom=1.0
  target_center=Vector2(clampf(clerk.position.x+110.0,SCENE_SIZE.x*.5,maxf(SCENE_SIZE.x*.5,_shop_motion.right_bound-SCENE_SIZE.x*.42)),SCENE_SIZE.y*.5)

func shop_locomotion_snapshot() -> Dictionary:
 var result:Dictionary=_shop_motion.snapshot()
 result.owns_clerk=_shop_owns_clerk;result.input_enabled=_shop_input_enabled;result.navigation=_shop_navigation
 result.clerk_position=clerk.position;result.clerk_state=_clerk_state;result.clerk_z=clerk.z_index
 result.interaction=shop_interaction();result.motion=_clerk_motion.debug_snapshot()
 return result

func committed_edit(kind:String,part:Dictionary) -> void:
 if assembly_feedback!=null:
  assembly_feedback.on_committed_edit(kind,part)
  # Module latch feedback still plays, but an unrelated edit cannot send the
  # empty robot across a clerk who is currently returning through the aisle.
  if _robot_return_pending or _clerk_return_requested:assembly_feedback.hold_transport_position()

func _screen_point(point:Vector2) -> Vector2:
 var pixel:Vector2=get_viewport().get_canvas_transform()*point
 return screen_mapper.pixel_to_screen(pixel) if screen_mapper!=null else pixel

func hotspot_positions() -> Array:
 if mode=="flight":return []
 return [{"id":"focus_counter","label":"柜台 · 接待客户","position":_screen_point(Vector2(265,345))},{"id":"focus_workbench","label":"工位 · 拼装装置","position":_screen_point(assembly_origin+Vector2(3,28))},{"id":"focus_supply","label":"夜间补给" if night else "供应商傍晚到店","position":_screen_point(Vector2(480,450))}]

func _extend_departure_deck(right_edge:float) -> void:
 # Reuse native generated floor regions only. The old shop remains untouched;
 # the new bay supplies its own continuation, with the same y486 foot anchor.
 if departure_deck==null or is_equal_approx(right_edge,_departure_right_edge):return
 _departure_right_edge=right_edge;_clear(departure_deck)
 var floor_texture:Texture2D=_texture("environment/shop-shell") if workshop_tier==0 else workshop_bay.texture
 if floor_texture==null:return
 var left:float=1280.0 if workshop_tier==0 else workshop_exit_x()
 var source:Rect2=Rect2(1024,480,256,240)
 var top:float=480.0
 if workshop_tier>0:
  var anchor_y:float=SHOP_FLOOR_Y-workshop_bay.position.y
  # Omit the distant rear rail beyond the hangar. The walking plane stays
  # registered while the craft's y428 underside clears this y430 apron.
  source=Rect2(float(floor_texture.get_width())-512.0,anchor_y-56.0,512.0,float(floor_texture.get_height())-(anchor_y-56.0))
  top=SHOP_FLOOR_Y-56.0
 while left<right_edge and departure_deck.get_child_count()<MAX_DEPARTURE_TILES:
  var tile=Sprite2D.new();tile.texture=floor_texture;tile.centered=false;tile.region_enabled=true
  tile.region_rect=Rect2(source.position,Vector2(minf(source.size.x,right_edge-left),source.size.y))
  tile.position=Vector2(left,top);tile.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  departure_deck.add_child(tile);left+=tile.region_rect.size.x
 if workshop_support!=null:workshop_support.configure_stage(SHOP_FLOOR_Y,Vector2(workshop_grid_rect().position.x,right_edge))

func workshop_support_fit_rect() -> Rect2:
 var area:Rect2=workshop_grid_rect()
 # Preserve the whole paid editing grid and its grounded support feet, without
 # pulling the distant departure-pad architecture into every assembly F-fit.
 return Rect2(area.position,Vector2(area.size.x,maxf(area.end.y,SHOP_FLOOR_Y+16.0)-area.position.y))

func _workshop_support_nodes(parent:Node) -> Dictionary:
 var result:Dictionary={}
 for node in parent.get_children():
  if node is Sprite2D and node.has_meta("part_id"):result[int(node.get_meta("part_id"))]=node
 return result

func _workshop_support_edges(parent:Node) -> Array:
 var result:Array=[]
 for node in parent.get_children():
  if node.has_meta("structural_edge"):result.append(node.get_meta("structural_edge"))
 return result

func _prepare_launch_registration(sim) -> void:
 var centre:Vector2=Vector2.ZERO;var mass:float=0.0
 var low:Vector2=Vector2(INF,INF);var high:Vector2=Vector2(-INF,-INF)
 for p in sim.parts.values():
  var cell:Vector2=Vector2(p.x,p.y);var weight:float=float(p.mass)
  centre+=cell*weight;mass+=weight
  low=low.min(cell-Vector2.ONE*.49);high=high.max(cell+Vector2.ONE*.49)
 if mass>0:centre/=mass
 if not low.is_finite():low=Vector2(-.49,-.49);high=-low
 _launch_bounds=Rect2((low-centre)*CELL,(high-low)*CELL)
 _launch_center_x=maxf(1115.0,970.0+_launch_bounds.size.x*.5)
 if workshop_tier>0:
  _launch_center_x=_expanded_pad_center(_launch_bounds.size.x)
  var support_left:float=_launch_bounds.position.x
  for p in sim.launcher_parts:support_left=minf(support_left,p.world_pos.x*CELL-maxf(CELL*.49,32.0))
  _launch_center_x=maxf(_launch_center_x,workshop_exit_x()+24.0+_launch_bounds.get_center().x-support_left)
 flight_origin=Vector2(_launch_center_x-_launch_bounds.get_center().x,CRADLE_CONTACT_Y-_launch_bounds.end.y)
 _launch_from_offset=assembly_origin+centre*CELL-flight_origin
 _support_transfer_duration=clampf(absf(_launch_from_offset.x)/650.0+.16,LAUNCH_TRANSFER_DURATION,2.8)
 _launch_view_zoom=minf(1.0,minf(214.6/maxf(1.0,_launch_bounds.size.y),900.0/maxf(1.0,_launch_bounds.size.x)))
 _launch_camera_to=Vector2(_launch_center_x,CRADLE_CONTACT_Y-_launch_bounds.size.y*.5-12.0/_launch_view_zoom)
 _extend_departure_deck(_launch_center_x+maxf(300.0,_launch_bounds.size.x+60.0)*.5+12.0)

func launch_transfer_duration() -> float:
 return 0.0 if reduced_motion else _support_transfer_duration

func start_flight(sim=null,resuming:bool=false) -> void:
 if sim!=null:
  var unavailable:String=PresentationCaps.route_error(sim.route)
  if not unavailable.is_empty():
   push_error(unavailable);return
 if flight_nodes.has("protected_bird"):flight_nodes.protected_bird.leave_flight()
 _bird_paused_visual=resuming
 _launch_camera_from=smooth_center;_launch_zoom_from=smooth_zoom
 _corridor_frame.clear();_corridor_zoom=.35
 _restoring_flight_visual=resuming
 _wormhole_cue_started=-1.0
 if otherworld_presentation!=null:otherworld_presentation.leave_flight()
 if moon_presentation!=null:moon_presentation.leave_flight()
 _clear(flight_root);flight_nodes={};trails=[];last_integrity=1;terminal_age=-1;launch_age=1.35 if resuming else 0.0;_ascent_view_zoom=.35;_last_sim=sim
 launch_transfer_progress=1.0 if resuming or reduced_motion else 0.0
 _backdrop_cargo=Vector2.ZERO;_backdrop_velocity=Vector2.ZERO;_backdrop_progress=0.0
 if sim!=null:
  _prepare_launch_registration(sim)
  flight_backdrop.configure_route(sim.route);ascent_backdrop.configure_route(sim.route)
  if otherworld_presentation!=null:otherworld_presentation.configure_route(sim.route,flight_root,flight_origin,CELL,sim.obstacles)
  if moon_presentation!=null:moon_presentation.configure_route(sim.route,flight_root,flight_origin,CELL,sim.obstacles)
  if otherworld_presentation!=null:otherworld_presentation.reduced_motion=reduced_motion;otherworld_presentation.motion_blur_enabled=motion_blur_enabled
  var cues=FlightCues.new();cues.name="FlightCollisionAndReceiptCues";cues.z_index=2;flight_root.add_child(cues);flight_nodes.cues=cues
  if str(sim.route.get("control_version",""))==BirdProfile.CONTROL_VERSION and BirdProfile.validation_error(sim.route).is_empty():
   var bird=load("res://scripts/protected_bird_presentation_2d.gd").new();bird.name="ProtectedBirdEncounter";bird.z_index=8
   flight_root.add_child(bird);bird.reduced_motion=reduced_motion
   if bird.configure(sim,flight_origin,CELL,resuming):flight_nodes.protected_bird=bird
   else:flight_root.remove_child(bird);bird.queue_free()
  if MeteorOffers.has_markers(sim.route) and MeteorOffers.validation_error(sim.route).is_empty():
   var meteor=MeteorPresentation.new();meteor.name="BoundedOrbitalMeteor";meteor.z_index=10
   flight_root.add_child(meteor);meteor.configure(sim.route,sim,flight_origin,CELL);flight_nodes.meteor=meteor
  _build_launch_pad(sim)
 var burst=_sprite("flight/ignition",flight_root,Vector2(230,180));burst.z_index=-1;burst.hide();flight_nodes.launch_burst=burst
 _flight_camera_departure=SCENE_SIZE*.5
 focus("flight")
 # Construct the live sprites before the old workshop sprites are hidden. With
 # a mass-weighted registration offset every module starts on its exact cell.
 if sim!=null:
  show_flight(sim,true)
  if workshop_support!=null:
   workshop_support.bind_transfer(_workshop_support_nodes(flight_root))
   workshop_support.present("airborne" if resuming else "unclamp",1.0 if resuming else 0.0)

func _cradle_strip(parent:Node,x:float,width:float,source:Rect2) -> void:
 var sprite=_sprite("props/launch-cradle-pixel",parent)
 sprite.centered=false;sprite.region_enabled=true;sprite.region_rect=Rect2(source.position,Vector2(width,source.size.y));sprite.position=Vector2(x,SHOP_FLOOR_Y-115.0);sprite.z_index=-2

func _launcher_pedestal(parent:Node,at:Vector2) -> void:
 # Original generated support split into registered, overlapping mechanical
 # pieces. Only the straight steel shaft extends; feet and saddle never stretch.
 var support=_group("GroundedModulePedestal",parent);support.z_index=-1
 var contact_y:float=at.y+CELL*.45
 var base=_sprite("launch-support/support-base-pixel",support);base.centered=false;base.position=Vector2(at.x-32.0,SHOP_FLOOR_Y-56.0)
 var saddle=_sprite("launch-support/support-saddle-pixel",support);saddle.centered=false;saddle.position=Vector2(at.x-23.0,contact_y-10.0)
 var tube=_sprite("launch-support/support-shaft-pixel",support);tube.centered=false;tube.position=Vector2(at.x-6.0,contact_y+12.0)
 tube.scale.y=maxf(1.0,SHOP_FLOOR_Y-52.0-tube.position.y)/24.0
 support.set_meta("floor_anchor",Vector2(at.x,SHOP_FLOOR_Y));support.set_meta("load_contact",Vector2(at.x,contact_y))

func _build_cradle_deck(pad:Node2D,center:float,width:float) -> void:
 var left:float=center-width*.5
 # Clamp caps and feet retain their size. Only existing plain deck art repeats.
 _cradle_strip(pad,left,78.0,Rect2(0,0,78,115))
 var x:float=left+78.0;var strips:int=0
 while x<left+width-72.0 and strips<MAX_LAUNCH_DECK_STRIPS:
  var span:float=minf(150.0,left+width-72.0-x)
  _cradle_strip(pad,x,span,Rect2(78,0,150,115));x+=span;strips+=1
 _cradle_strip(pad,left+width-72.0,72.0,Rect2(228,0,72,115))

func _launch_transfer_offset(transfer:float) -> Vector2:
 # Rear arms release before the same supported craft starts traveling.
 transfer=clampf((transfer-.12)/.88,0.0,1.0)
 if workshop_tier==0:return _launch_from_offset*(1.0-transfer)
 # A high/wide build exits through the empty right corridor before being
 # lowered onto the same grounded apron. Its sprites never cross bay artwork.
 var horizontal:float=clampf(transfer/.78,0.0,1.0)
 var vertical:float=smoothstep(0.0,1.0,clampf((transfer-.78)/.22,0.0,1.0))
 return Vector2(_launch_from_offset.x*(1.0-horizontal),_launch_from_offset.y*(1.0-vertical))

func _build_launch_pad(sim) -> void:
 var pad=_group("AnchoredLauncher",flight_root);flight_nodes.launch_pad=pad
 var width:float=maxf(300.0,_launch_bounds.size.x+60.0)
 _build_cradle_deck(pad,_launch_center_x,width)
 for p in sim.launcher_parts:
  var node=_module(p,pad);node.position=flight_origin+p.world_pos*CELL;node.rotation=float(p.local_angle);node.name=("Spring" if p.type=="spring" else "Pad")+str(p.id)
  node.set_meta("fixed_launcher_position",node.position)
  _launcher_pedestal(pad,node.position)
 pad.set_meta("floor_y",SHOP_FLOOR_Y);pad.set_meta("contact_y",CRADLE_CONTACT_Y);pad.set_meta("craft_bounds",_launch_bounds)

func show_flight(sim,paused_visual:bool=false) -> void:
 if mode!="flight":start_flight(sim)
 _bird_paused_visual=paused_visual
 _last_sim=sim
 var wormhole_cut:bool=otherworld_presentation.sync_telemetry(sim.telemetry,_restoring_flight_visual) if otherworld_presentation!=null else false
 var in_otherworld:bool=otherworld_presentation!=null and otherworld_presentation.otherworld_active()
 if wormhole_cut:_wormhole_cue_started=sim.elapsed if in_otherworld and not _restoring_flight_visual else -1.0
 if otherworld_presentation!=null:otherworld_presentation.set_transit_strength(clampf(1.0-(sim.elapsed-_wormhole_cue_started)/.18,0.0,1.0) if _wormhole_cue_started>=0.0 else 0.0)
 if otherworld_presentation!=null:otherworld_presentation.update_hardware(sim.obstacles)
 if moon_presentation!=null:moon_presentation.update_hardware(sim.obstacles)
 if launch_age>0.0:launch_transfer_progress=1.0
 var transfer:float=smoothstep(0.0,1.0,clampf(launch_transfer_progress,0.0,1.0))
 var craft_offset:Vector2=_launch_transfer_offset(transfer)
 var cargo:Vector2=sim.cargo_position();var at:Vector2=flight_origin+cargo*CELL+craft_offset;_flight_center=cargo*CELL
 var ascent:bool=str(sim.route.get("control_version","")) in ["pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird"]
 var pilot:bool=str(sim.route.get("control_version","")) in ["pilot-v1","pilot-v2","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird"]
 if otherworld_presentation!=null:otherworld_presentation.set_scene_visible(mode=="flight")
 if mode=="flight":
  ascent_backdrop.visible=ascent and not in_otherworld;flight_backdrop.visible=not ascent
 var cruise_zoom:float=_ascent_cruise_zoom(sim.telemetry) if ascent else (.68 if pilot else 1.0)
 if ascent and not CorridorFraming.applies(sim.route):
  _ascent_view_zoom=minf(_ascent_view_zoom,_ascent_craft_fit_zoom(sim));cruise_zoom=_ascent_view_zoom
 var lead:float=maxf(220,float(sim.telemetry.get("lookahead_m",22))*CELL-SCENE_SIZE.x*.5/cruise_zoom) if pilot else 220
 if ascent:lead=SCENE_SIZE.x*.34/cruise_zoom
 var cruise_center:Vector2=_ascent_cruise_center(at,lead,float(sim.telemetry.get("lane_y",cargo.y)),float(sim.telemetry.get("route_heading",0))) if ascent else (_pilot_cruise_center(at,lead) if pilot else at+Vector2(lead,-35))
 target_center=cruise_center;target_zoom=cruise_zoom
 var velocity:Vector2=Vector2.ZERO
 for body in sim.bodies:
  if body.parts.any(func(p):return p.type=="cargo" and p.alive):velocity=body.velocity;break
 if (moon_presentation!=null and moon_presentation.route_enabled()):
  var frame:Dictionary=moon_presentation.camera_target(sim,get_viewport_rect().size,screen_mapper)
  cruise_center=frame.center;cruise_zoom=frame.zoom
  target_center=cruise_center;target_zoom=cruise_zoom
 elif ReadableCorridor.applies(sim.route):
  _corridor_frame=ReadableCorridor.compose(sim,flight_origin,CELL,get_viewport_rect().size,screen_mapper,_corridor_frame)
  cruise_center=_corridor_frame.center;cruise_zoom=_corridor_frame.zoom
  target_center=cruise_center;target_zoom=cruise_zoom
 elif CorridorFraming.applies(sim.route):
  _corridor_frame=CorridorFraming.compose(sim,flight_origin,CELL,get_viewport_rect().size,screen_mapper,minf(_ascent_view_zoom,_corridor_zoom),_corridor_frame)
  _corridor_zoom=_corridor_frame.zoom
  cruise_center=_corridor_frame.center;cruise_zoom=_corridor_frame.zoom
  target_center=cruise_center;target_zoom=cruise_zoom
 if paused_visual:velocity=Vector2.ZERO
 if ascent:
  ascent_backdrop.reduced_motion=reduced_motion;ascent_backdrop.motion_blur_enabled=motion_blur_enabled
  _backdrop_cargo=cargo;_backdrop_velocity=velocity if launch_transfer_progress>=1.0 and launch_age>=.7 else Vector2.ZERO;_backdrop_progress=clampf(cargo.x/maxf(1,route_distance),0,1)
 else:
  flight_backdrop.reduced_motion=reduced_motion;flight_backdrop.motion_blur_enabled=motion_blur_enabled
  flight_backdrop.update_flight(cargo,velocity,clampf(cargo.x/maxf(1,route_distance),0,1))
 var recoil:float=0
 if launch_transfer_progress<1.0:
  target_center=_launch_camera_from.lerp(_launch_camera_to,transfer);target_zoom=lerpf(_launch_zoom_from,_launch_view_zoom,transfer)
 elif launch_age<1.35:
  if launch_age<.7:recoil=0.0 if reduced_motion else -5*clampf(launch_age/.7,0,1);target_zoom=_launch_view_zoom if reduced_motion else lerpf(_launch_view_zoom,_launch_view_zoom*1.04,launch_age/.7);target_center=_launch_camera_to
  elif launch_age<.95:target_zoom=_launch_view_zoom if reduced_motion else lerpf(_launch_view_zoom*1.04,_launch_view_zoom,(launch_age-.7)/.25);target_center=_launch_camera_to+Vector2(maxf(0.0,at.x-_launch_center_x)*.5,0)
  else:
   var release:float=smoothstep(0.0,1.0,(launch_age-.95)/.4)
   if ReadableCorridor.applies(sim.route):
    var launch_center:Vector2=_launch_camera_to+Vector2(maxf(0.0,at.x-_launch_center_x)*.5,0)
    var release_frame:Dictionary=ReadableCorridor.release_frame(_corridor_frame.craft,launch_center,_launch_view_zoom,cruise_center,cruise_zoom,_corridor_frame.scene_size,_corridor_frame.craft_safe,release)
    target_center=release_frame.center;target_zoom=release_frame.zoom
   else:
    target_center=(_launch_camera_to+Vector2(maxf(0.0,at.x-_launch_center_x)*.5,0)).lerp(cruise_center,release);target_zoom=lerpf(_launch_view_zoom,cruise_zoom,release)
 for p in sim.parts.values():
  var key:String="p"+str(p.id)
  if not flight_nodes.has(key):flight_nodes[key]=_module(p,flight_root)
  var sprite:Sprite2D=flight_nodes[key];sprite.visible=bool(p.get("alive",false)) and (not bool(p.get("delivered",false)) or sim.status=="success")
  sprite.position=(flight_origin+sim.part_world_position(int(p.id))*CELL+craft_offset+Vector2(recoil,0)).round()
  # world_angle is a detached/rebuild snapshot in the deterministic simulator.
  # Attached art must use the live body's angle, just as its world position does.
  var live_body:Dictionary=sim.body_for_part(int(p.id))
  sprite.rotation=float(live_body.angle)+float(p.local_angle) if not live_body.is_empty() else float(p.get("world_angle",0))
  if sprite.texture!=null:sprite.scale=Vector2.ONE*CELL*.98/Vector2(sprite.texture.get_size())*float(p.get("scale",1))
  var plume=sprite.get_node_or_null("Exhaust")
  if plume!=null:
   # Pilot nozzle state is already paid, per circuit. Unknown pilot telemetry
   # cannot borrow energy from some other island or fabricate exhaust.
   var fallback:float=0.0 if pilot else (1.0 if bool(p.get("active",false)) and sim.total_energy()>0 else 0.0)
   var throttle:float=float(p.get("pilot_throttle",fallback))
   if not is_finite(throttle):throttle=0.0
   plume.visible=throttle>.001 and sim.status=="running" and launch_age>=.7
   var plume_length:float=95*clampf(throttle,.2,1.3)
   plume.rotation=float(p.get("gimbal_angle",0));plume.position=Vector2(-(CELL*.34+plume_length*.5),0).rotated(plume.rotation)
   if plume.texture!=null:plume.scale=Vector2(plume_length,49)/Vector2(plume.texture.get_size())
  var motor=sprite.get_node_or_null("PoweredDrillCue")
  if motor!=null:motor.set_power(float(p.get("drill_power_ratio",0.0)) if sim.status=="running" else 0.0)
 _update_flight_joints(sim,recoil,craft_offset)
 if workshop_support!=null:
  var support_phase:String="unclamp" if transfer<.12 else ("move" if transfer<1.0 else ("retract" if launch_age<.7 else "airborne"))
  var support_progress:float=clampf(transfer/.12,0.0,1.0) if support_phase=="unclamp" else clampf(launch_age/.5,0.0,1.0)
  workshop_support.present(support_phase,support_progress,paused_visual)
 var pad:Node2D=flight_nodes.launch_pad;pad.show()
 for object in pad.get_children():
  if str(object.name).begins_with("Spring") and object is Sprite2D and object.texture!=null:
   var baseline:float=CELL*.98/float(object.texture.get_width());object.scale.x=baseline*(1-.34*clampf(launch_age/.7,0,1)) if launch_age<.7 else baseline
 var burst:Sprite2D=flight_nodes.launch_burst;burst.position=at-Vector2(115,0);burst.visible=launch_transfer_progress>=1.0 and not reduced_motion and launch_age>=.7 and launch_age<1.12
 for i in range(sim.obstacles.size()):
  var h:Dictionary=sim.obstacles[i];var key:String="h"+str(i)
  if moon_presentation!=null and moon_presentation.suppresses_hazard(i):continue
  if flight_nodes.has("meteor") and flight_nodes.meteor.suppresses_hazard(i):continue
  var portal_cap:Sprite2D=otherworld_presentation.hardware_node(i) if otherworld_presentation!=null else null
  if portal_cap!=null:
   flight_nodes[key]=portal_cap
   continue
  if not flight_nodes.has(key):
   var art:String={"turret":"modules/accelerator","tracker":"modules/decoy","mine":"modules/bomb","gravity":"modules/shrink"}.get(str(h.type),"flight/rock-"+str(i%2+1))
   flight_nodes[key]=_sprite(art,flight_root,Vector2.ONE*CELL*2*float(h.radius));flight_nodes[key].set_meta("hazard_type",str(h.type))
  var obstacle:Sprite2D=flight_nodes[key];obstacle.position=(flight_origin+h.position*CELL).round();obstacle.visible=float(h.health)>0
  if str(h.type) in ["turret","tracker"]:obstacle.flip_h=true
 if not flight_nodes.has("destination"):
  var goal:Vector2=flight_origin+Vector2(route_distance,float(sim.route.get("destination_y",0)))*CELL
  if (moon_presentation!=null and moon_presentation.route_enabled()):
   flight_nodes.destination=moon_presentation.receiver_node()
  elif (otherworld_presentation!=null and otherworld_presentation.route_enabled()):
   flight_nodes.destination=otherworld_presentation.receiver_node()
  elif GroundProfile.is_ground_route(sim.route):
   flight_nodes.destination=_ground_receiver(goal,route_radius*CELL)
  elif pilot:
   var dock=_sprite("space/orbital-mail-dock",flight_root);dock.centered=false;dock.offset=-Vector2(318,213);dock.position=goal;dock.scale=Vector2.ONE*1.65;dock.z_index=-3;flight_nodes.destination=dock
  else:flight_nodes.destination=_placed_prop("flight/receiver","flight/receiver",goal+Vector2(0,route_radius*CELL+80),230,flight_root)
  var label=Label.new();label.text=str(sim.route.get("destination_name","收件台")) if GroundProfile.is_ground_route(sim.route) or (otherworld_presentation!=null and otherworld_presentation.route_enabled()) or (moon_presentation!=null and moon_presentation.route_enabled()) else ("牵引收件区" if pilot else "收件区");label.add_theme_font_override("font",load("res://assets/fonts/ChineseSans.otf"));label.add_theme_font_size_override("font_size",24);label.add_theme_color_override("font_color",Color("c5f5df"));label.position=goal-Vector2(66,route_radius*CELL+35);flight_root.add_child(label);flight_nodes.receipt_label=label
 flight_nodes.receipt_label.visible=not (moon_presentation!=null and moon_presentation.route_enabled()) and (not (otherworld_presentation!=null and otherworld_presentation.route_enabled()) or in_otherworld)
 flight_nodes.cues.update_state(sim,flight_origin,CELL)
 if sim.status=="success":flight_nodes.receipt_label.text="货物已签收"
 if sim.status!="running":
  if terminal_age<0:terminal_age=0
  target_center=at+Vector2(100,-40);target_zoom=_launch_view_zoom
  if in_otherworld and sim.status=="success":
   # Keep the actual registered receiving mouth and its roof/deck in the
   # receipt shot. The old ship-only close-up cropped this larger dock away.
   var capture_radius:float=route_radius*CELL
   var receipt_goal:Vector2=flight_origin+Vector2(route_distance,float(sim.route.destination_y))*CELL
   target_center=receipt_goal+Vector2(capture_radius*.65,-capture_radius*.14)
   target_zoom=minf(_launch_view_zoom,minf(.40,SCENE_SIZE.y*.75/maxf(1.0,capture_radius*2.8)))
  if (moon_presentation!=null and moon_presentation.route_enabled()) and sim.status=="success":
   var receipt_frame:Dictionary=moon_presentation.camera_target(sim,get_viewport_rect().size,screen_mapper)
   target_center=receipt_frame.center;target_zoom=receipt_frame.zoom
 _draw_flight_effects(sim,at)
 if launch_transfer_progress<1.0 or launch_age<1.35:smooth_center=target_center;smooth_zoom=target_zoom
 if wormhole_cut:
  # The simulation has already crossed the portal. Do not sweep the camera
  # through the skipped space or blur the previous biome across the new one.
  smooth_center=target_center;smooth_zoom=target_zoom;camera.reset_physics_interpolation()
 _update_camera()

func _ground_receiver(goal:Vector2,radius:float) -> Sprite2D:
 # The real capture aperture remains at goal. Register the generated deck
 # below its lower edge, rather than centering a kiosk on the collision target.
 var kiosk:Sprite2D=_sprite("flight/receiver",flight_root)
 kiosk.centered=false;kiosk.z_index=-3
 var width:float=maxf(230.0,radius*2.0+120.0)
 kiosk.scale=Vector2.ONE*width/float(kiosk.texture.get_width())
 kiosk.position=goal+Vector2(0,radius+GROUND_RECEIVER_CLEARANCE)-GROUND_RECEIVER_DECK*kiosk.scale
 kiosk.set_meta("capture_center",goal)
 kiosk.set_meta("deck_center",goal+Vector2(0,radius+GROUND_RECEIVER_CLEARANCE))
 return kiosk

func settle_resumed_flight(sim) -> void:
 _corridor_frame.clear()
 # The controller has just reconstructed history without visual updates.
 # Establish health at that completed tick before observing new destruction.
 if flight_nodes.has("meteor"):flight_nodes.meteor.configure(sim.route,sim,flight_origin,CELL)
 if flight_nodes.has("protected_bird"):flight_nodes.protected_bird.configure(sim,flight_origin,CELL,true)
 launch_transfer_progress=1.0;launch_age=1.35
 show_flight(sim,true)
 smooth_center=target_center;smooth_zoom=target_zoom;_update_camera()
 _restoring_flight_visual=false
 _wormhole_cue_started=-1.0
 if otherworld_presentation!=null:otherworld_presentation.set_transit_strength(0.0)

func _pilot_cruise_center(at:Vector2,lead:float) -> Vector2:
 # Ordinary steering moves the ship through the frame. Follow only outside the
 # safe central band, without moving simulation coordinates or collision gates.
 var y:float=at.y-clampf(at.y-flight_origin.y,-PILOT_VERTICAL_DEADZONE,PILOT_VERTICAL_DEADZONE)
 return Vector2(at.x+lead,y-35)

func _ascent_cruise_center(at:Vector2,lead:float,lane_y:float,_heading:float) -> Vector2:
 # The native 1280px HUD occupies the left top and lower-left. Keep the craft
 # in the deliberate clear band between them instead of sending it under a
 # resource card while steering. The camera still follows a real lane, and the
 # lateral lead/zoom budget that exposes upcoming obstacles is unchanged.
 var baseline:float=flight_origin.y+lane_y*CELL
 var y:float=at.y-clampf(at.y-baseline,-180.0,180.0)
 return Vector2(at.x+lead,y-88.0/maxf(.01,_ascent_view_zoom))

func _ascent_craft_fit_zoom(sim) -> float:
 # Bound the real connected cargo body's projected height. Wide/tall extreme
 # builds may rotate; detached debris must not shrink the player's entire view.
 var body:Dictionary={}
 for p in sim.parts.values():
  if p.type=="cargo" and p.alive:body=sim.body_for_part(int(p.id));break
 if body.is_empty():return 1.0
 var top:float=INF;var bottom:float=-INF
 for p in body.parts:
  if not p.alive:continue
  var angle:float=float(body.angle)+float(p.local_angle)
  var radius:float=CELL*.49*float(p.get("scale",1))*(absf(sin(angle))+absf(cos(angle)))
  var center:float=sim.part_world_position(int(p.id)).y*CELL
  top=minf(top,center-radius);bottom=maxf(bottom,center+radius)
 return minf(1.0,120.0/maxf(1.0,bottom-top))

func _ascent_cruise_zoom(telemetry:Dictionary) -> float:
 # Keep real corridor silhouettes ahead, not only a predictive HUD arrow.
 # Four bounded pullbacks preserve readable pixels and never hunt around a
 # speed threshold. Once widened, the view stays wide until receipt/retry.
 var forward:float=maxf(0.0,float(telemetry.get("forward_speed",0)))
 var wanted:float=.35
 if forward>=14.0:wanted=.30
 if forward>=18.0:wanted=.27
 if forward>=20.5 or bool(telemetry.get("pilot_boost",false)):wanted=.24
 _ascent_view_zoom=minf(_ascent_view_zoom,wanted)
 return _ascent_view_zoom

func _update_flight_joints(sim,recoil:float=0,craft_offset:Vector2=Vector2.ZERO) -> void:
 var node:Node2D=flight_nodes.get("joints")
 if node==null:node=_group("LiveStructuralJoints",flight_root);node.z_index=-1;flight_nodes.joints=node
 var edges:Array=[];var index:int=0
 for link in sim.links:
  if not sim.parts.has(link.a) or not sim.parts.has(link.b):continue
  var a:Dictionary=sim.parts[link.a];var b:Dictionary=sim.parts[link.b]
  if not a.alive or not b.alive or a.body_id!=b.body_id:continue
  if index>=MAX_VISIBLE_JOINTS:break
  var joint:Sprite2D
  if index<node.get_child_count():joint=node.get_child(index)
  else:joint=_sprite("modules/joint",node,Vector2(26,23))
  var pa:Vector2=sim.part_world_position(link.a);var pb:Vector2=sim.part_world_position(link.b)
  joint.position=(flight_origin+(pa+pb)*.5*CELL+craft_offset+Vector2(recoil,0)).round();joint.rotation=(pb-pa).angle();joint.show();edges.append([int(link.a),int(link.b)]);index+=1
 for i in range(index,node.get_child_count()):node.get_child(i).hide()
 node.set_meta("structural_edges",edges)

func _draw_flight_effects(sim,_at:Vector2) -> void:
 visible_effect_count=0;visible_ring_count=0;effect_node.show()
 for effect in sim.effects:
  if visible_effect_count>=MAX_VISIBLE_EFFECTS:break
  var node:Sprite2D=_effect_pool[visible_effect_count]
  var position_value:Vector2=effect.get("position",effect.get("from",Vector2.ZERO))
  var kind:String=str(effect.get("type",""))
  if kind in ["lance","arc","enemy"]:position_value=effect.get("to",position_value)
  node.position=(flight_origin+position_value*CELL).round()
  node.modulate=Color("ffd37b") if kind=="drill" else Color("b5a4f0") if kind=="arc" else Color("f57f73") if kind=="enemy" else Color.WHITE
  # One existing generated particle per bounded, genuinely funded contact.
  # Reduced motion retains the contact information without a bright burst.
  if kind=="drill":node.modulate.a=.55 if reduced_motion else .9
  node.set_meta("effect_type",kind)
  if node.texture!=null:node.scale=Vector2.ONE*(80 if kind=="explosion" else 32 if kind=="drill" and reduced_motion else 44 if kind=="drill" else 28)/float(node.texture.get_width())
  node.visible=kind not in ["teleport","wormhole"];visible_effect_count+=1
  if kind=="teleport":visible_ring_count=mini(MAX_VISIBLE_RINGS,visible_ring_count+2)
 for i in range(visible_effect_count,_effect_pool.size()):_effect_pool[i].hide()

func leave_flight() -> void:
 if flight_nodes.has("protected_bird"):flight_nodes.protected_bird.leave_flight()
 _bird_paused_visual=false
 if otherworld_presentation!=null:otherworld_presentation.leave_flight()
 if moon_presentation!=null:moon_presentation.leave_flight()
 _restoring_flight_visual=false
 _wormhole_cue_started=-1.0
 _clear(flight_root);flight_nodes={};_last_sim=null;_flight_center=Vector2.ZERO;trails=[]
 effect_node.hide();visible_effect_count=0;visible_ring_count=0;launch_transfer_progress=1.0
 _backdrop_cargo=Vector2.ZERO;_backdrop_velocity=Vector2.ZERO;_backdrop_progress=0.0
 ascent_backdrop.configure_route({"background_route":"city"});focus("hub")
 if workshop_support!=null:workshop_support.sync_assembly(_workshop_support_nodes(ship_root),_workshop_support_edges(ship_root))

func _protected_bird_hud_rects() -> Array:
 # Main binds the existing HUD root. Read visible native widget rectangles;
 # never infer an empty screen from the simulator or mutate HUD layout here.
 var result:Array=[]
 if not is_instance_valid(protected_bird_hud_root):return result
 var pending:Array=[protected_bird_hud_root]
 var visits:int=0
 var inverse:Transform2D=get_viewport().get_canvas_transform().affine_inverse()
 while not pending.is_empty() and visits<96 and result.size()<32:
  var node= pending.pop_back();visits+=1
  if not node is Control or not node.is_visible_in_tree() or node.modulate.a<=0.0 or node.self_modulate.a<=0.0:continue
  var painted:bool=node is PanelContainer or node is BaseButton or node is Label or node is RichTextLabel or node is ProgressBar
  if node is Label and node.text.is_empty():painted=false
  if node is PanelContainer:
   var style=node.get_theme_stylebox("panel")
   if style is StyleBoxEmpty:painted=false
   elif style is StyleBoxFlat and style.bg_color.a<=0.0:
    var border:bool=style.border_color.a>0.0 and (style.border_width_left>0 or style.border_width_top>0 or style.border_width_right>0 or style.border_width_bottom>0)
    if not border:painted=false
  if painted and node.size.x>0.0 and node.size.y>0.0:
   var transform:Transform2D=node.get_global_transform_with_canvas()
   var a:Vector2=transform*Vector2.ZERO;var b:Vector2=transform*node.size
   if screen_mapper!=null:a=screen_mapper.screen_to_pixel(a);b=screen_mapper.screen_to_pixel(b)
   var from:Vector2=inverse*a;var to:Vector2=inverse*b
   result.append(Rect2(from,to-from).abs())
  else:
   for child in node.get_children():
    if child is Control:pending.append(child)
 return result

func apply_quality(_profile:String) -> void:pass

func _update_camera() -> void:
 if camera==null:return
 var extent:Vector2=get_viewport_rect().size
 if mode=="flight" and (moon_presentation!=null and moon_presentation.route_enabled()) and launch_transfer_progress>=1.0 and launch_age>=1.35:
  var fit:Dictionary=moon_presentation.constrain_camera(smooth_center,smooth_zoom,extent,screen_mapper)
  smooth_center=fit.center;smooth_zoom=fit.zoom
 elif mode=="flight" and not _corridor_frame.is_empty() and _last_sim!=null and CorridorFraming.applies(_last_sim.route) and launch_transfer_progress>=1.0 and launch_age>=1.35:
  if _corridor_frame.viewport_extent!=extent or _corridor_frame.art_extent!=(screen_mapper.display_rect.size if screen_mapper!=null else extent):
   if ReadableCorridor.applies(_last_sim.route):_corridor_frame=ReadableCorridor.compose(_last_sim,flight_origin,CELL,extent,screen_mapper,{})
   else:_corridor_frame=CorridorFraming.compose(_last_sim,flight_origin,CELL,extent,screen_mapper,minf(_ascent_view_zoom,_corridor_zoom),{})
   smooth_center=_corridor_frame.center;smooth_zoom=_corridor_frame.zoom
   target_center=smooth_center;target_zoom=smooth_zoom;_corridor_zoom=minf(_corridor_zoom,smooth_zoom)
  if ReadableCorridor.applies(_last_sim.route):smooth_center.x=_corridor_frame.center.x;smooth_zoom=_corridor_frame.zoom
  var fit:Dictionary=CorridorFraming.Shared.constrain(smooth_center,smooth_zoom,_corridor_frame.craft,_corridor_frame.craft_safe,_corridor_frame.scene_size)
  smooth_center=fit.center;smooth_zoom=fit.zoom
 var zoom_value:float=extent.x/SCENE_SIZE.x*smooth_zoom
 camera.zoom=Vector2.ONE*zoom_value
 camera.position=(smooth_center*zoom_value).round()/zoom_value
 camera.force_update_scroll()
 if mode=="flight" and _last_sim!=null and flight_nodes.has("protected_bird"):
  # Exclude the existing top/bottom HUD bands from visibility accounting.
  # Cargo may already be delivered and absent from bodies; only read wildlife.
  var bird_scene:Vector2=extent*SCENE_SIZE.x/maxf(1.0,extent.x)
  var bird_safe:Rect2=CorridorFraming.safe_rect(extent,screen_mapper)
  var bird_view:Rect2=Rect2(camera.position+(bird_safe.position-bird_scene*.5)/smooth_zoom,bird_safe.size/smooth_zoom)
  flight_nodes.protected_bird.reduced_motion=reduced_motion
  flight_nodes.protected_bird.update_from_sim(_last_sim,bird_view,smooth_zoom,_bird_paused_visual or _scene_paused or not _focus_active,_protected_bird_hud_rects())
  if flight_nodes.has("cues"):flight_nodes.cues.set_protected_bird_cue(flight_nodes.protected_bird.cue_state())
 if mode=="flight" and _last_sim!=null and flight_nodes.has("meteor"):
  var span:Vector2=SCENE_SIZE/maxf(.01,smooth_zoom)/CELL
  var center:Vector2=(camera.position-flight_origin)/CELL
  flight_nodes.meteor.update_from_sim(_last_sim,Rect2(center-span*.5,span),smooth_zoom)
 if (moon_presentation!=null and moon_presentation.route_enabled()) and mode=="flight":
  moon_presentation.reduced_motion=reduced_motion;moon_presentation.motion_blur_enabled=motion_blur_enabled
  moon_presentation.update_view(_backdrop_cargo,_backdrop_velocity,(camera.position-flight_origin)/CELL,smooth_zoom,_scene_paused)
  moon_presentation.update_boundary_cues(camera.position,smooth_zoom,launch_transfer_progress>=1.0 and launch_age>=1.35)
  ascent_backdrop.modulate.a=1.0-moon_presentation.moon_weight()
  ascent_backdrop.visible=moon_presentation.moon_weight()<1.0
 elif ascent_backdrop!=null:ascent_backdrop.modulate.a=1.0
 # One ordinary-wrap backdrop and camera reference serve shop and departure.
 # Switching dispatch state never reflects a building or resets parallax phase.
 background_root.scale=extent/SCENE_SIZE
 if ascent_backdrop!=null and ascent_backdrop.visible:
  ascent_backdrop.reduced_motion=reduced_motion;ascent_backdrop.motion_blur_enabled=motion_blur_enabled
  ascent_backdrop.update_flight(_backdrop_cargo,_backdrop_velocity,_backdrop_progress,(camera.position-SCENE_SIZE*.5)/CELL)
 if otherworld_presentation!=null and otherworld_presentation.otherworld_active() and mode=="flight":
  otherworld_presentation.reduced_motion=reduced_motion;otherworld_presentation.motion_blur_enabled=motion_blur_enabled
  otherworld_presentation.update_view(_backdrop_cargo,_backdrop_velocity,(camera.position-flight_origin)/CELL,_scene_paused)

func _process(delta:float) -> void:
 if not is_finite(delta) or delta<=0 or _scene_paused or not _focus_active or not is_visible_in_tree():return
 if assembly_feedback!=null:assembly_feedback.reduced_motion=reduced_motion
 visual_time+=delta
 if _clerk_motion.has_method("set_visual_context"):_clerk_motion.set_visual_context(visual_time,_review_phone_owner==0 and _investigation_owner==0 and (not _shop_owns_clerk or _shop_input_enabled or _clerk_return_requested),reduced_motion)
 if _review_phone_owner==0 and _investigation_owner==0 and _clerk_state=="ready" and str(_clerk_motion.debug_snapshot().pose)!="ready":_set_clerk_gesture("ready")
 _step_customers(delta)
 if mode!="flight":
  _step_clerk_return(delta);_step_robot_return();_step_shop_locomotion(delta)
  if _robot_return_pending or assembly_feedback.robot_state in ["return_turn","return"]:_sync_robot_counter_depth()
 if _review_phone_owner==0 and _investigation_owner==0 and clerk!=null and _clerk_motion.has_method("advance_visual"):
  clerk.rotation=0.0
  _clerk_motion.advance_visual(visual_time,_review_phone_owner==0 and _investigation_owner==0 and (not _shop_owns_clerk or _shop_input_enabled or _clerk_return_requested),reduced_motion)
 elif _review_phone_owner==0 and _investigation_owner==0 and clerk!=null and _clerk_state=="counter":
  clerk.rotation=sin(visual_time*1.2+.8)*.0035 if not reduced_motion and str(clerk.get_meta("pose","idle"))=="idle" else 0.0
 _sync_customer_parcel();_step_parcel_transport(delta);_sync_clerk_counter_support();_frame_loading_action()
 var weight:float=1-exp(-delta*8)
 smooth_center=smooth_center.lerp(target_center,weight);smooth_zoom=lerpf(smooth_zoom,target_zoom,weight)
 if smooth_center.distance_to(target_center)<.05:smooth_center=target_center
 if absf(smooth_zoom-target_zoom)<.0001:smooth_zoom=target_zoom
 _update_camera()

func _exit_tree() -> void:
 release_investigation(_investigation_owner)
 release_review_phone(_review_phone_owner)
 # Node-bound tweens are auto-freed, but explicitly invalidate callbacks too.
 _cancel_parcel_transfer()
