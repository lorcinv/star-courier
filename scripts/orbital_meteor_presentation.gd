extends Node2D
## Isolated native Node2D adapter. All painted art is generated raster; the
## contact boundary and directional warning are functional geometry only.
const Observer=preload("res://scripts/orbital_meteor_observer.gd")
const ART_ROOT="res://assets/2d_v5/events/meteor/"
const MAX_NODES=5 # this node, one meteor, two fragments, one Label
var _observer=Observer.new()
var _origin=Vector2.ZERO
var _cell=72.0
var _route:Dictionary={}
var _records:Dictionary={}
var _sprites:Dictionary={}
var _label:Label
var _view=Rect2()
var _frame:Dictionary={}
var _sim_time=0.0
var _meteor_position=Vector2.ZERO
var _meteor_radius=0.8
var _meteor_alive=false
var _cue_point=Vector2.ZERO
var _cue_velocity=Vector2.ZERO
var _active_cue=false
var _zoom=0.27
var warning_scene_rect:Rect2=Rect2()

func configure(route:Dictionary,sim,origin:Vector2,cell:float=72.0,checkpoint:Dictionary={}) -> void:
 for child in get_children():remove_child(child);child.free()
 _route=route.duplicate(true);_origin=origin;_cell=cell;_sprites.clear();_records.clear()
 var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ART_ROOT+"manifest.json"))
 for record in manifest.assets:_records[record.name]=record
 for name in ["meteor","fragment-a","fragment-b"]:
  var sprite=Sprite2D.new();sprite.name=name;sprite.texture=load(ART_ROOT+name+".png")
  sprite.centered=false;sprite.offset=-Vector2(_records[name].anchor_px[0],_records[name].anchor_px[1])
  sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;sprite.visible=false
  add_child(sprite);_sprites[name]=sprite
 _label=Label.new();_label.name="MeteorWarning";_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _label.add_theme_font_override("font",load("res://assets/fonts/ChineseSans.otf"))
 _label.add_theme_color_override("font_shadow_color",Color("121b30"));_label.add_theme_constant_override("shadow_offset_x",2);_label.add_theme_constant_override("shadow_offset_y",2)
 _label.add_theme_font_size_override("font_size",20);_label.add_theme_color_override("font_color",Color("ffd88f"))
 add_child(_label);_observer.configure(route,sim,checkpoint);_label.hide()

func suppresses_hazard(index:int) -> bool:
 for event in _route.get("orbital_event",{}).get("events",[]):
  if int(event.hazard_index)==index:return true
 return false

func update_from_sim(sim,physical_view_rect:Rect2,zoom:float) -> void:
 _view=physical_view_rect;_sim_time=sim.elapsed;_zoom=maxf(.1,zoom);_frame=_observer.update(sim)
 if _frame.get("error","")!="":return
 var e:Dictionary=_route.orbital_event.events[0];var h:Dictionary=sim.obstacles[int(e.hazard_index)]
 _meteor_position=h.position;_meteor_radius=h.radius;_meteor_alive=h.health>0.0
 var rock:Sprite2D=_sprites.meteor;rock.visible=_meteor_alive
 rock.position=(_origin+_meteor_position*_cell).round()
 rock.scale=Vector2.ONE*_cell*_meteor_radius/float(_records.meteor.occupied_circumradius_px)
 for name in ["fragment-a","fragment-b"]:_sprites[name].visible=false
 for fragment in _frame.fragments:
  var sprite:Sprite2D=_sprites[fragment.sprite];sprite.visible=true
  var age:float=_sim_time-float(fragment.born)
  sprite.position=(_origin+(fragment.position+fragment.velocity*age)*_cell).round()
  sprite.scale=Vector2.ONE*_cell*0.28/float(_records[fragment.sprite].occupied_circumradius_px)
  sprite.modulate.a=clampf((float(fragment.expires)-_sim_time)/0.65,0.0,1.0)
 _active_cue=not _frame.cues.is_empty();_label.visible=_active_cue
 if _active_cue:
  var cue:Dictionary=_frame.cues[0]
  _cue_velocity=cue.velocity
  _label.text="流星运动方向：向下" if cue.velocity.y>0.0 else "流星运动方向：向上"
  # The warning lives in the center/right band below the 96px top HUD.
  # Coordinates are logical 1280x720 stage units at every pixel density.
  # Keep it clear of the actual whole craft, not just its cargo center.
  var ship:Rect2=Rect2();var first:bool=true
  for part in sim.parts.values():
   if not bool(part.get("alive",false)):continue
   var at:Vector2=(sim.part_world_position(int(part.id))-_view.position)*_cell*_zoom
   var bounds:Rect2=Rect2(at-Vector2.ONE*52.0*_zoom*float(part.get("scale",1.0)),Vector2.ONE*104.0*_zoom*float(part.get("scale",1.0)))
   ship=bounds if first else ship.merge(bounds);first=false
  var candidates:Array=[Rect2(340,116,340,32),Rect2(900,116,340,32),Rect2(840,480,340,32)]
  var chosen:Rect2=candidates[0]
  for candidate in candidates:
   if first or not candidate.grow(30.0).intersects(ship):chosen=candidate;break
  # Put the direction arrow in the same HUD-clear band; an offscreen-edge
  # arrow could otherwise cover the normal altitude/resources panels.
  _cue_point=_view.position+(chosen.position+Vector2(-20.0,12.0))/(_cell*_zoom)
  warning_scene_rect=chosen
  _label.position=_origin+_view.position*_cell+chosen.position/_zoom
  _label.scale=Vector2.ONE/_zoom
 queue_redraw()

func _draw() -> void:
 if _meteor_alive:
  draw_arc(_origin+_meteor_position*_cell,_meteor_radius*_cell,0,TAU,40,Color(1.0,0.78,0.42,0.8),1.25/_zoom,true)
 if _active_cue:
  var at=_origin+_cue_point*_cell;var d=_cue_velocity.normalized()*16.0/_zoom
  draw_line(at-d,at+d,Color("ffd88f"),2.0/_zoom,true)
  draw_line(at+d,at+d-d.rotated(.65)*.5,Color("ffd88f"),2.0/_zoom,true)
  draw_line(at+d,at+d-d.rotated(-.65)*.5,Color("ffd88f"),2.0/_zoom,true)

func observer_checkpoint() -> Dictionary:return _observer.snapshot()
func bounded_node_count() -> int:return 1+get_child_count()
