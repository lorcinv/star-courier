extends RefCounted
## Presentation only. Atlas pixels come from the image-generated UI design.
## This helper never owns input, gameplay state, save data, or phone lifecycle.
const DisplayMetrics=preload("res://scripts/demo_display_metrics.gd")
const ATLAS=preload("res://assets/ui/demo_skin_v1/atlas.png")
const REGIONS:Dictionary={
 "normal":Rect2(33,130,550,117),"selected":Rect2(33,248,550,115),
 "pressed":Rect2(33,365,550,116),"disabled":Rect2(33,481,550,120),
 "order":Rect2(599,130,643,441),"tray":Rect2(1248,150,895,193),
 "phone":Rect2(1264,382,454,186),"badge":Rect2(1739,408,360,130)
}
const INK=Color("101a30")
const CREAM=Color("fff3d7")
static var _secondary_panel_texture:Texture2D

static func texture(key:String) -> AtlasTexture:
 var result:=AtlasTexture.new();result.atlas=ATLAS;result.region=REGIONS[key];result.filter_clip=true
 return result

static func style(key:String,pad_x:float=18.0,pad_y:float=10.0) -> StyleBoxTexture:
 var result:=StyleBoxTexture.new();result.texture=texture(key)
 # Full-image stretch preserves the generated silhouette and does not invent
 # a procedural border. Component variants share practical target proportions.
 result.content_margin_left=pad_x;result.content_margin_right=pad_x
 result.content_margin_top=pad_y;result.content_margin_bottom=pad_y
 return result

static func panel_style() -> StyleBoxTexture:
 # This is source-pixel sampling, not new artwork: exact nearest half sample
 # of a measured 896x194 tray region. The raw generated PNG stays unchanged.
 if _secondary_panel_texture==null:
  var pixels:Image=ATLAS.get_image().get_region(Rect2i(1248,150,896,194))
  pixels.resize(448,97,Image.INTERPOLATE_NEAREST)
  _secondary_panel_texture=ImageTexture.create_from_image(pixels)
 var result:=StyleBoxTexture.new();result.texture=_secondary_panel_texture
 result.texture_margin_left=80;result.texture_margin_right=80
 result.texture_margin_top=46;result.texture_margin_bottom=24
 result.content_margin_left=22;result.content_margin_right=22
 result.content_margin_top=50;result.content_margin_bottom=28
 return result

static func button(button:Button,compact:bool=false) -> void:
 var pad_y:float=5.0 if compact else 10.0
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var key:String={"normal":"normal","hover":"selected","pressed":"pressed","hover_pressed":"pressed","disabled":"disabled"}[state]
  button.add_theme_stylebox_override(state,style(key,28,pad_y))
 # Focus is a transparent programmatic accessibility marker, not a second
 # opaque raster painted over pressed/hover_pressed feedback.
 var focus:=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=Color("ffca57")
 focus.set_border_width_all(2);focus.set_expand_margin_all(3);focus.anti_aliasing=false
 button.add_theme_stylebox_override("focus",focus)
 button.focus_entered.connect(func():DisplayMetrics.set_style_override(button,"normal",style("selected",28,pad_y)))
 button.focus_exited.connect(func():DisplayMetrics.set_style_override(button,"normal",style("normal",28,pad_y)))
 button.add_theme_color_override("font_color",CREAM)
 button.add_theme_color_override("font_hover_color",INK)
 button.add_theme_color_override("font_focus_color",INK)
 button.add_theme_color_override("font_pressed_color",INK)
 button.add_theme_color_override("font_hover_pressed_color",INK)
 button.add_theme_color_override("font_disabled_color",Color("c2d0df"))

static func apply_hud(content:Control) -> void:
 # Called after the existing HUD builds its real controls; change only paint.
 var ledger=content.get_node_or_null("DayLedger")
 if ledger is PanelContainer:ledger.add_theme_stylebox_override("panel",style("tray",12,8))
 var ticket=content.get_node_or_null("CurrentWaybill")
 if ticket is PanelContainer:_ticket(ticket)
 for child in content.get_children():
  if child is Button and child.has_meta("scene_action"):
   child.add_theme_stylebox_override("normal",style("normal",8,8))
   var hover:=style("normal",8,8);hover.modulate_color=Color(1.18,1.18,1.18)
   child.add_theme_stylebox_override("hover",hover)
   child.add_theme_stylebox_override("pressed",style("normal",8,8))
   child.add_theme_stylebox_override("disabled",style("disabled",8,8))
 var phone=content.get_node_or_null("PhoneLauncher")
 if phone is Button:
  # Keep the real phone image, hit area, caption, callback and owner intact.
  var badge:=TextureRect.new();badge.name="GeneratedPhoneBadge";badge.texture=texture("badge")
  badge.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;badge.position=Vector2(4,63);badge.size=Vector2(58,28)
  badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;phone.add_child(badge)
  for child in phone.get_children():
   if child is Label and child.text=="手机":phone.move_child(badge,child.get_index());break

static func _ticket(panel:PanelContainer) -> void:
 if panel.get_child_count()==0:return
 var body=panel.get_child(0)
 if not body is VBoxContainer:return
 var has_order:bool=body.get_child_count()>2
 panel.size.y=152.0 if has_order else 110.0
 var frame:=style("order",18,8);frame.content_margin_right=24;frame.content_margin_bottom=18
 panel.add_theme_stylebox_override("panel",frame)
 # Retain the original dynamic labels and cancel control. A fixed blank header
 # slice gives the compact receipt enough cream area at its existing width.
 var header:=TextureRect.new();header.name="GeneratedReceiptHeader"
 var crop:=AtlasTexture.new();crop.atlas=ATLAS;crop.region=Rect2(599,130,643,104);crop.filter_clip=true
 header.texture=crop;header.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 header.position=Vector2(-18,-8);header.size=Vector2(252,36);header.mouse_filter=Control.MOUSE_FILTER_IGNORE
 # Top-level decoration is intentionally outside container sizing/child layout.
 var decor:=Control.new();decor.mouse_filter=Control.MOUSE_FILTER_IGNORE
 panel.add_child(decor);panel.move_child(decor,0);decor.add_child(header)
 var gap:=Control.new();gap.custom_minimum_size.y=10;gap.mouse_filter=Control.MOUSE_FILTER_IGNORE
 body.add_child(gap);body.move_child(gap,1)
 for label in body.find_children("*","Label",true,false):
  if label.text.begins_with("ORDER /"):label.add_theme_color_override("font_color",INK)
  else:label.add_theme_color_override("font_color",CREAM)
  # Direct body labels fill the bounded VBox. Keep footer HBox labels natural
  # so their spacer cannot collapse them; only long body/name rows ellipsize.
  if label.get_parent()==body:
   label.clip_text=true;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
   label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
   if label.tooltip_text.is_empty():label.tooltip_text=label.text
 # A long name may have expanded the live PanelContainer before this paint
 # pass ran. Lowering Label minimum widths does not shrink its current size.
 # Restore the authored rectangle only after all text constraints are applied.
 panel.size=Vector2(252,152 if has_order else 110)
