extends Node2D
## Native read-only presentation. Parent under WorldView.background_root.
## Physical rocks come directly from the live solver; this class never authors,
## steers, damages, teleports, accelerates or repositions a body.
const Content=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const Receipt=preload("res://scripts/lunar_outpost_receipt_v2.gd")
const RasterSkin=preload("res://scripts/demo_raster_skin.gd")
const OreFeedback=preload("res://scripts/lunar_ore_feedback_v2.gd")
const ROCK_RADII:Dictionary={"rock-1":97.13135436098891,"rock-2":92.01222744831254}
const MAX_NODES:int=14
var _route:Dictionary={}
var _panorama:Sprite2D
var _terrain:Sprite2D
var _props:FieldOverlay
var _receiver:Sprite2D
var _label:Label
var _label_card:PanelContainer
var _rocks:Array=[]
var _origin:Vector2=Vector2.ZERO
var _cell:float=72.0
var _enabled:bool=false
var _scene_visible:bool=false
var _weight:float=0.0
var _ore_feedback=OreFeedback.new()
var _ore_nodes:Dictionary={}

class FieldOverlay extends Node2D:
 var circles:Array=[]
 var capture_center:Vector2=Vector2.ZERO
 var capture_radius:float=1.0
 var zoom:float=1.0
 var received:bool=false
 func _draw() -> void:
  var color:Color=Color("78edcf") if received else Color("a7e7ff")
  draw_arc(capture_center,capture_radius,0.0,TAU,64,color,1.5/zoom,true)
  # Matching arrows explicitly indicate the real any-direction capture volume.
  for side in [-1.0,1.0]:
   var edge:Vector2=capture_center+Vector2(side*(capture_radius+11.0/zoom),0.0)
   var tip:Vector2=edge-Vector2(side*10.0/zoom,0.0)
   draw_line(edge,tip,color,2.0/zoom,true)
   draw_line(tip,tip+Vector2(side*5.0/zoom,-4.0/zoom),color,2.0/zoom,true)
   draw_line(tip,tip+Vector2(side*5.0/zoom,4.0/zoom),color,2.0/zoom,true)
  for item in circles:
   # The ring is the true CCD radius; irregular alpha art fits completely inside.
   draw_arc(item.position,item.radius,0.0,TAU,40,Color(1.0,.78,.44,.6),1.0/zoom,true)
   if item.velocity.length_squared()>0.0:
    var tip:Vector2=item.position+item.velocity.normalized()*(item.radius+12.0/zoom)
    var delta:Vector2=item.velocity.normalized()*12.0/zoom
    draw_line(tip-delta,tip,Color("ffd58e"),2.0/zoom,true)
    draw_line(tip,tip-delta.rotated(.60)*.55,Color("ffd58e"),2.0/zoom,true)
    draw_line(tip,tip-delta.rotated(-.60)*.55,Color("ffd58e"),2.0/zoom,true)

func _ready() -> void:
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_process(false)

func configure_route(route:Dictionary,world_parent:Node2D,origin:Vector2,cell:float=72.0) -> bool:
 leave_flight()
 if not Content.has_markers(route) or not Receipt.route_error(route).is_empty():return false
 _route=route.duplicate(true);_origin=origin;_cell=cell
 _panorama=_plane("SingleEarthLunarSky",Receipt.SKY,false)
 _terrain=_plane("DecorativeLunarRegolith",Receipt.REGOLITH,true)
 _panorama.modulate.a=0.0
 _terrain.modulate=Color(.82,.85,.95,0.0)
 _terrain.material.set_shader_parameter("saturation",.65)
 _props=FieldOverlay.new();_props.name="LunarPhysicalField";_props.z_index=-2
 world_parent.add_child(_props)
 var goal:Vector2=origin+Content.DESTINATION*cell
 _props.capture_center=goal;_props.capture_radius=Content.DELIVERY_RADIUS*cell
 _receiver=Sprite2D.new();_receiver.name="LunarReceiver"
 _receiver.texture=load("res://assets/2d_v5/flight/receiver.png")
 _receiver.centered=false;_receiver.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var spec:Dictionary=route.lunar_receiver
 _receiver.scale=Vector2.ONE*float(spec.art_width_m)*cell/279.0
 var deck:Vector2=goal+Vector2(0.0,(Content.DELIVERY_RADIUS+float(spec.deck_clearance_m))*cell)
 _receiver.position=deck-Vector2(139.5,149.0)*_receiver.scale
 _receiver.set_meta("capture_center",goal);_receiver.set_meta("deck_center",deck)
 _receiver.set_meta("lunar_registered_receiver",true);_props.add_child(_receiver)
 for index in range(route.hazards.size()):
  var h:Dictionary=route.hazards[index]
  var rock:Sprite2D=Sprite2D.new();rock.name="LunarRock"+str(index)
  rock.texture=load("res://assets/2d_v5/flight/"+str(h.lunar_art)+".png")
  rock.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  rock.scale=Vector2.ONE*float(h.radius)*cell/float(ROCK_RADII[h.lunar_art])
  _props.add_child(rock);_rocks.append(rock)
  if str(h.id) in OreFeedback.ORE_IDS:_create_ore_feedback(str(h.id),rock)
 _ore_feedback.configure(route)
 # Reuse the generated dark tag so the action remains legible over Earth.
 # It marks the real airborne capture circle, not the decorative deck below.
 _label_card=PanelContainer.new();_label_card.name="LunarReceiptAction"
 _label_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _label_card.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _label_card.add_theme_stylebox_override("panel",RasterSkin.style("normal",16.0,7.0))
 _label_card.custom_minimum_size=Vector2(196.0,40.0)
 _label_card.size=_label_card.custom_minimum_size
 _props.add_child(_label_card)
 _label=Label.new();_label.name="LunarReceiverLabel";_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 _label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
 _label.add_theme_font_override("font",load("res://assets/fonts/ChineseSans.otf"))
 _label.add_theme_font_size_override("font_size",22)
 _label.add_theme_color_override("font_color",Color("c6f4ff"))
 _label.add_theme_color_override("font_shadow_color",Color("111628"))
 _label.add_theme_constant_override("shadow_offset_x",2);_label.add_theme_constant_override("shadow_offset_y",2)
 _label_card.add_child(_label)
 _enabled=true;_scene_visible=true;_refresh_visibility()
 return true

func _create_ore_feedback(id:String,rock:Sprite2D) -> void:
 # Two fixed raster/label pairs. No particle emission or geometry stand-in.
 var burst:Sprite2D=Sprite2D.new();burst.name="OreBreakRaster"
 burst.texture=load("res://assets/2d_v5/flight/impact.png")
 burst.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;burst.z_index=8
 _props.add_child(burst);burst.hide()
 var label:Label=Label.new();label.name="OreBreakReceipt";label.text="矿石已破碎"
 label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.z_index=9
 label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 label.size=Vector2(180.0,34.0)
 label.add_theme_font_override("font",load("res://assets/fonts/ChineseSans.otf"))
 label.add_theme_font_size_override("font_size",22)
 label.add_theme_color_override("font_color",Color("ffe5a8"))
 label.add_theme_color_override("font_shadow_color",Color("111628"))
 label.add_theme_constant_override("shadow_offset_x",2);label.add_theme_constant_override("shadow_offset_y",2)
 _props.add_child(label);label.hide()
 _ore_nodes[id]={"rock":rock,"burst":burst,"label":label}

func _update_ore_feedback(sim,zoom:float) -> void:
 # Real free-flight Continue reconstructs its candidate before start_flight;
 # configure_route and the first sample therefore prime completed health only.
 # There is deliberately no paused gate: the last actual advancing step may
 # have broken ore immediately before the first paused draw.
 var elapsed:Variant=sim.get("elapsed")
 if elapsed is int or elapsed is float:
  _ore_feedback.observe(sim.get_instance_id(),float(elapsed),sim.obstacles)
 for nodes in _ore_nodes.values():
  nodes.rock.modulate=Color.WHITE;nodes.burst.hide();nodes.label.hide()
 for cue in _ore_feedback.frame():
  var nodes:Dictionary=_ore_nodes[cue.id]
  nodes.rock.modulate=Color.WHITE.lerp(Color(1.0,.76,.42),float(cue.hit_strength)*.55)
  var point:Vector2=_origin+cue.position*_cell
  nodes.burst.visible=float(cue.burst_alpha)>0.0
  nodes.burst.position=point;nodes.burst.modulate.a=float(cue.burst_alpha)
  nodes.burst.scale=Vector2.ONE*112.0/(float(nodes.burst.texture.get_width())*zoom)
  nodes.label.visible=float(cue.label_alpha)>0.0
  nodes.label.position=point+Vector2(-90.0,-65.0)/zoom
  nodes.label.scale=Vector2.ONE/zoom;nodes.label.modulate.a=float(cue.label_alpha)

func _plane(label:String,path:String,terrain:bool) -> Sprite2D:
 var node:Sprite2D=Sprite2D.new();node.name=label;node.texture=load(path);node.centered=false
 node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 node.scale=Vector2(1280.0,720.0)/Vector2(node.texture.get_size())
 var material:ShaderMaterial=ShaderMaterial.new();material.shader=load(Receipt.SHADER)
 material.set_shader_parameter("source_size_px",Vector2(node.texture.get_size()))
 material.set_shader_parameter("logical_size_px",Vector2(1280.0,720.0))
 material.set_shader_parameter("repeat_x",terrain);material.set_shader_parameter("terrain",terrain)
 material.set_shader_parameter("blur_delta_px",Vector2.ZERO)
 node.material=material;add_child(node);return node

func update_from_sim(sim,zoom:float=1.0,camera_m:Vector2=Vector2(INF,INF)) -> void:
 if not _enabled:return
 _weight=smoothstep(float(_route.lunar_backdrop_begin_x),float(_route.lunar_backdrop_full_x),sim.cargo_position().x)
 _panorama.modulate.a=_weight;_terrain.modulate.a=.88*_weight
 var camera:Vector2=camera_m if camera_m.is_finite() else sim.cargo_position()
 # One clamped Earth. Decorative terrain wraps in the same direction and
 # follows camera motion only; there is no new physical floor or world boundary.
 _panorama.material.set_shader_parameter("scroll_px",Vector2(clampf((camera.x-72.0)*.025,-16.0,16.0),clampf((camera.y+40.0)*.05,-8.0,8.0)))
 _terrain.material.set_shader_parameter("scroll_px",Vector2(fposmod(round(fposmod(camera.x,1280.0/2.4)*2.4/2.0)*2.0,1280.0),0.0))
 _terrain.material.set_shader_parameter("surface_y_px",640.0-clampf((camera.y+40.0)*.4,-26.0,26.0))
 var z:float=maxf(.01,zoom)
 _props.zoom=z;_props.received=sim.status=="success";_props.circles=[]
 for index in range(mini(_rocks.size(),sim.obstacles.size())):
  var hazard:Dictionary=sim.obstacles[index]
  var rock:Sprite2D=_rocks[index]
  rock.visible=float(hazard.health)>0.0
  rock.position=(_origin+hazard.position*_cell).round()
  if rock.visible:_props.circles.append({"position":_origin+hazard.position*_cell,"radius":float(hazard.radius)*_cell,"velocity":hazard.get("velocity",Vector2.ZERO)})
 _update_ore_feedback(sim,z)
 _label.text="货物已签收" if sim.status=="success" else "进入光圈交件"
 _label_card.scale=Vector2.ONE/z
 # Screen-sized tag stays inside the same receiver bounds as before. At a
 # forced ultra-wide fit the HUD keeps destination guidance, rather than
 # shrinking the text or allowing this tag to cover the whole capture circle.
 _label_card.visible=_props.capture_radius*z>=108.0
 _label_card.position=_props.capture_center+Vector2(-98.0/z,-_props.capture_radius+14.0/z)
 _props.queue_redraw();_refresh_visibility()

func set_scene_visible(value:bool) -> void:
 _scene_visible=value;_refresh_visibility()

func _refresh_visibility() -> void:
 visible=_enabled and _scene_visible
 if _props!=null:_props.visible=visible

func route_enabled() -> bool:return _enabled
func receiver_node() -> Sprite2D:return _receiver
func suppresses_hazard(index:int) -> bool:return _enabled and index>=0 and index<_rocks.size()

func leave_flight() -> void:
 _enabled=false;_scene_visible=false;_weight=0.0;_route.clear();_rocks.clear()
 _ore_feedback.clear();_ore_nodes.clear()
 if is_instance_valid(_props):_props.free()
 if is_instance_valid(_panorama):_panorama.free()
 if is_instance_valid(_terrain):_terrain.free()
 _props=null;_panorama=null;_terrain=null;_receiver=null;_label=null;_label_card=null;hide()

func debug_snapshot() -> Dictionary:
 return {"enabled":_enabled,"visible":visible,"weight":_weight,"rocks":_rocks.size(),"registered_receiver":is_instance_valid(_receiver),"node_budget":MAX_NODES,"ore_feedback":_ore_feedback.debug_snapshot(),"ore_node_pairs":_ore_nodes.size()}
