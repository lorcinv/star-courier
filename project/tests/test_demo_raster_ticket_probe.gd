extends SceneTree
const RasterSkin=preload("res://scripts/demo_raster_skin.gd")
const Title=preload("res://scripts/demo_title.gd")
const HUD=preload("res://scripts/game_hud.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func settle() -> void:
 for unused in 4:await process_frame
func ticket_probe(node:Node,depth:int=0) -> void:
 if node is Control:
  var detail:Dictionary={"depth":depth,"name":str(node.name),"class":node.get_class(),"position":str(node.position),"size":str(node.size),"minimum":str(node.get_minimum_size()),"combined_minimum":str(node.get_combined_minimum_size()),"custom_minimum":str(node.custom_minimum_size),"hflags":node.size_flags_horizontal,"vflags":node.size_flags_vertical}
  if node is Label:detail.merge({"text":node.text,"clip_text":node.clip_text,"overrun":node.text_overrun_behavior,"font_size":node.get_theme_font_size("font_size")})
  if node is PanelContainer:
   var box:StyleBox=node.get_theme_stylebox("panel")
   detail["style_minimum"]=str(box.get_minimum_size());detail["content_margins"]=[box.get_content_margin(SIDE_LEFT),box.get_content_margin(SIDE_TOP),box.get_content_margin(SIDE_RIGHT),box.get_content_margin(SIDE_BOTTOM)]
  print("TICKET_GEOMETRY_PROBE ",JSON.stringify(detail))
 for child in node.get_children():ticket_probe(child,depth+1)
func run() -> void:
 if OS.get_environment("STAR_COURIER_UI_TEST")!="1" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):
  printerr("Requires STAR_COURIER_UI_TEST=1 and fresh /tmp XDG_DATA_HOME");quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refuse existing profile");quit(2);return
 var frame:StyleBoxTexture=RasterSkin.panel_style()
 check(frame.texture.get_size()==Vector2(448,97),"secondary frame uses exact half-size source sample")
 check(frame.texture_margin_left==80 and frame.texture_margin_right==80 and frame.texture_margin_top==46 and frame.texture_margin_bottom==24,"secondary frame has measured fixed nine-slice corners")
 check(frame.content_margin_left==22 and frame.content_margin_right==22 and frame.content_margin_top==50 and frame.content_margin_bottom==28,"secondary content lies below the fixed top rail")
 var button:=Button.new();button.text="设置";button.size=Vector2(380,54);RasterSkin.button(button);root.add_child(button);button.grab_focus();await settle()
 var focus=button.get_theme_stylebox("focus")
 check(focus is StyleBoxFlat and focus.bg_color.a==0,"focus overlay is transparent and cannot cover pressed pixels")
 check((button.get_theme_stylebox("normal") as StyleBoxTexture).texture.region==RasterSkin.REGIONS.selected,"keyboard focus selects the raster base without an opaque overlay")
 check((button.get_theme_stylebox("pressed") as StyleBoxTexture).texture.region==RasterSkin.REGIONS.pressed and (button.get_theme_stylebox("hover_pressed") as StyleBoxTexture).texture.region==RasterSkin.REGIONS.pressed,"pressed and hover-pressed retain the cyan raster")
 button.release_focus();await settle()
 check((button.get_theme_stylebox("normal") as StyleBoxTexture).texture.region==RasterSkin.REGIONS.normal,"focus exit restores the normal raster")
 button.free()
 var title=Title.new();root.add_child(title);await settle();title._show_settings();await settle()
 check(title.panel.size.y<=600.0 and title.panel.size.x<=430.0,"real title settings fit the authored 430 by 600 panel")
 check(title.menu.position.y>=50.0 and title.menu.position.x>=22.0,"real title content uses measured nine-slice insets")
 var settings_fit:bool=true
 var bounds:Rect2=title.panel.get_global_rect()
 for child in title.menu.get_children():
  if child is Control:
   var rect:Rect2=child.get_global_rect()
   settings_fit=settings_fit and rect.end.y<=bounds.end.y-28.0+.1 and rect.position.x>=bounds.position.x+22.0-.1
 check(settings_fit,"all real settings controls remain above the bottom frame rail")
 check(title.game==null,"geometry inspection creates no gameplay Main")
 title.free();await settle()
 var hud=HUD.new();root.add_child(hud);hud.set_art_frame(Rect2(0,0,1280,720));await settle()
 var long_name:String="今天的托付".repeat(12)
 hud.render({"mode":"hub","day":1,"credits":260,"reputation":1,"phase":"morning","contracts":[],"has_accepted_contract":true,"activeorder":{"name":long_name,"distance":2400,"cargo":"花种","required":95,"deadline":80,"accepted":true},"settings":{"reduced_motion":true}})
 await settle()
 var ticket:PanelContainer=hud.content.get_node("CurrentWaybill")
 ticket_probe(ticket)
 check(ticket.size.x<=252.1 and ticket.size.y<=152.1,"long accepted order cannot expand the bounded ticket")
 var receipt:StyleBoxTexture=ticket.get_theme_stylebox("panel") as StyleBoxTexture
 check(receipt.content_margin_left==18 and receipt.content_margin_right==24,"ticket body stays inside the measured dark right rail")
 var long_label:Label
 var deadline:Label
 for label in ticket.find_children("*","Label",true,false):
  if label.text==long_name:long_label=label
  if label.text.begins_with("时限"):deadline=label
 check(is_instance_valid(long_label) and long_label.clip_text and long_label.text_overrun_behavior==TextServer.OVERRUN_TRIM_ELLIPSIS and long_label.tooltip_text==long_name,"long order name is bounded with a full-text tooltip")
 check(is_instance_valid(deadline) and deadline.get_global_rect().end.x<=ticket.get_global_rect().end.x-24.0+.1,"right-aligned deadline stays clear of the cream edge")
 hud.free();await settle()
 check(not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.backup.json"),"raster geometry tests write no save slots")
 print("DEMO_RASTER_GEOMETRY passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
