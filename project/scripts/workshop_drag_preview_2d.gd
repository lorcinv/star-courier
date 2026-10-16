extends Node2D
## Presentation only. The real module and model never move until release commits.
## The ghost follows the latest input position directly; only the footprint snaps.
const CELL:float=72.0
const VALID:Color=Color("6fe6b1")
const INVALID:Color=Color("ff8078")
var ghost:Sprite2D
var source_part_id:int=-1
var _source:CanvasItem
var _source_modulate:Color=Color.WHITE
var _target:Vector2=Vector2.ZERO
var _valid:bool=false
var _has_target:bool=false
var _texture:Texture2D
var _updates:int=0
var _footprint_redraws:int=0

func _init() -> void:
 name="WorkshopDragPreview";z_index=40
 ghost=Sprite2D.new();ghost.name="PointerGhost";ghost.z_index=-1;ghost.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 add_child(ghost);hide()

func begin(part_id:int,source:CanvasItem,texture:Texture2D,quarter_turns:int) -> void:
 clear()
 source_part_id=part_id;_source=source
 if is_instance_valid(_source):
  _source_modulate=_source.self_modulate
  _source.self_modulate=Color(_source_modulate.r,_source_modulate.g,_source_modulate.b,_source_modulate.a*.22)
 _texture=texture;ghost.texture=texture;ghost.rotation=float(quarter_turns)*PI*.5
 if texture!=null:ghost.scale=Vector2.ONE*CELL*.98/Vector2(texture.get_size())

func present(pointer_center:Vector2,snapped_center:Vector2,valid_target:bool) -> void:
 if source_part_id<0 or not pointer_center.is_finite() or not snapped_center.is_finite():clear();return
 ghost.position=pointer_center
 ghost.modulate=Color(1,1,1,.88) if valid_target else Color(1,.72,.68,.82)
 if not _has_target or _target!=snapped_center or _valid!=valid_target:
  _target=snapped_center;_valid=valid_target;_has_target=true;_footprint_redraws+=1;queue_redraw()
 _updates+=1;show()

func clear() -> void:
 if is_instance_valid(_source):_source.self_modulate=_source_modulate
 _source=null;source_part_id=-1;_has_target=false;hide()

func _exit_tree() -> void:clear()

func _draw() -> void:
 if not _has_target:return
 var ink:Color=VALID if _valid else INVALID
 var rect:Rect2=Rect2(_target-Vector2.ONE*CELL*.5,Vector2.ONE*CELL)
 draw_rect(rect,Color(ink.r,ink.g,ink.b,.17),true)
 draw_rect(rect.grow(-1),ink,false,2.0)
 # A second shape keeps acceptance readable without relying on color alone.
 var at:Vector2=rect.position+Vector2(CELL-11,11)
 if _valid:
  draw_polyline(PackedVector2Array([at+Vector2(-5,0),at+Vector2(-1,4),at+Vector2(6,-5)]),ink,2.0)
 else:
  draw_line(at+Vector2(-4,-4),at+Vector2(4,4),ink,2.0)
  draw_line(at+Vector2(-4,4),at+Vector2(4,-4),ink,2.0)

func debug_snapshot() -> Dictionary:
 return {"visible":visible,"source_id":source_part_id,"ghost_center":ghost.position,"target_center":_target,"valid":_valid,"updates":_updates,"footprint_redraws":_footprint_redraws,"node_count":get_child_count()}
