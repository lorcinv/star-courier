extends CanvasLayer
## Explicit shop-only view. Main provides economy.customer_reviews(), never the
## saved review container or pending settlement facts. No economy mutation.
signal modal_changed(open:bool)
signal page_changed(page:String)
const DisplayMetrics=preload("res://scripts/demo_display_metrics.gd")
const MAX_REVIEWS:int=30
const CASING=preload("res://assets/2d_v5/reviews/customer-review-phone-ninepatch-source.png")
const DEVICE_SIZE:Vector2=Vector2(395,624)
const SCREEN_RECT:Rect2=Rect2(25,56,344,500)
const SCREEN_BLEED:float=6.0
var _device:Control
var _screen_clip:Control
var _casing:NinePatchRect
var _root:Control
var _panel:PanelContainer
var _list:VBoxContainer
var _date:Label
var _close:Button
var _scroll:ScrollContainer
var _open:bool=false
var _home:VBoxContainer
var _reviews:VBoxContainer
var _app:Button
var _home_date:Label
var _page:String="home"
var _art_frame:Rect2=Rect2()
var _clerk_screen:Vector2=Vector2.ZERO
var _ui_scale:float=1.0

func _ready() -> void:
 layer=24
 _root=Control.new();_root.name="CustomerReviewPhone";add_child(_root)
 _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _root.mouse_filter=Control.MOUSE_FILTER_STOP;_root.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 _device=Control.new();_device.name="PhoneDevice";_device.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(_device)
 _device.size=DEVICE_SIZE
 # Keep device-local screen coordinates, but cap paint below/right of the
 # aperture. This plain Control cannot grow to a page's minimum size.
 _screen_clip=Control.new();_screen_clip.name="PhoneScreenClip";_screen_clip.clip_contents=true
 _screen_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;_screen_clip.size=SCREEN_RECT.end+Vector2.ONE*SCREEN_BLEED;_device.add_child(_screen_clip)
 _panel=PanelContainer.new();_panel.name="ReviewPanel";_panel.set_meta("modal_panel",true);_screen_clip.add_child(_panel)
 # The imagegen raster is decoration only. Native controls retain their original
 # 344×500 screen, readable font sizes, focus ownership and lifecycle.
 var shell:=StyleBoxFlat.new();shell.bg_color=Color("17243a");shell.anti_aliasing=false
 # Extend background paint beneath the rounded raster trim, without changing
 # content size, margins or layout. This seals the transparent corner opening.
 shell.set_expand_margin_all(SCREEN_BLEED)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:shell.set_content_margin(side,16)
 _panel.add_theme_stylebox_override("panel",shell)
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);_panel.add_child(box);_reviews=box
 _home=VBoxContainer.new();_home.name="PhoneHome";_home.add_theme_constant_override("separation",16);_panel.add_child(_home)
 var home_header:=HBoxContainer.new();_home.add_child(home_header)
 var home_title:=_label("我的手机",22,Color("fff3d7"));home_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;home_header.add_child(home_title)
 var home_close:=Button.new();home_close.text="收起";home_close.custom_minimum_size=Vector2(64,38);home_close.tooltip_text="收起手机，返回店铺";home_header.add_child(home_close);home_close.pressed.connect(close_phone)
 _home_date=_label("",14,Color("a8b8cb"));_home.add_child(_home_date)
 var apps:=HBoxContainer.new();_home.add_child(apps)
 _app=Button.new();_app.name="CustomerReviewsApp";_app.text="客户留言";_app.icon=preload("res://assets/2d_v5/modules/cargo-pixel.png");_app.expand_icon=true;_app.add_theme_constant_override("icon_max_width",48);_app.custom_minimum_size=Vector2(144,88);_app.tooltip_text="打开客户留言，查看已发布的配送评价";_app.set_meta("safe_modal_default",true);apps.add_child(_app);_app.pressed.connect(open_reviews_app)
 var home_spacer:=Control.new();home_spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;_home.add_child(home_spacer)
 _home.add_child(_label("客户留言会在次日送达。",14,Color("a8b8cb")))
 var header:=HBoxContainer.new();header.add_theme_constant_override("separation",12);box.add_child(header)
 var title:=_label("客户留言",22,Color("fff3d7"));title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
 _close=Button.new();_close.text="返回";_close.custom_minimum_size=Vector2(64,38);_close.set_meta("safe_modal_default",true);header.add_child(_close);_close.pressed.connect(back)
 _date=_label("",14,Color("a8b8cb"));box.add_child(_date)
 _scroll=ScrollContainer.new();_scroll.name="ReviewScroll";_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;box.add_child(_scroll)
 _scroll.follow_focus=true
 var bar:VScrollBar=_scroll.get_v_scroll_bar();bar.focus_mode=Control.FOCUS_NONE
 bar.custom_minimum_size.x=12
 var track:=StyleBoxFlat.new();track.bg_color=Color("293e56");track.content_margin_left=6;track.content_margin_right=6
 bar.add_theme_stylebox_override("scroll",track)
 for state in ["grabber","grabber_highlight","grabber_pressed"]:
  var thumb:=StyleBoxFlat.new();thumb.bg_color=Color("edce73") if state=="grabber" else Color("fff3d7")
  thumb.content_margin_left=6;thumb.content_margin_right=6;thumb.content_margin_top=15;thumb.content_margin_bottom=15
  bar.add_theme_stylebox_override(state,thumb)
 _list=VBoxContainer.new();_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_list.add_theme_constant_override("separation",12);_scroll.add_child(_list)
 _casing=NinePatchRect.new();_casing.name="ImagegenPhoneCasing";_casing.texture=CASING;_casing.size=DEVICE_SIZE
 _casing.patch_margin_left=25;_casing.patch_margin_top=56;_casing.patch_margin_right=26;_casing.patch_margin_bottom=68
 _casing.draw_center=false
 _casing.axis_stretch_horizontal=NinePatchRect.AXIS_STRETCH_MODE_STRETCH
 _casing.axis_stretch_vertical=NinePatchRect.AXIS_STRETCH_MODE_STRETCH
 _casing.mouse_filter=Control.MOUSE_FILTER_IGNORE;_casing.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;_device.add_child(_casing)
 _root.hide();get_viewport().size_changed.connect(_layout);_layout()

func set_existing_theme(value:Theme) -> void:
 _panel.theme=value

func set_art_frame(rect:Rect2,clerk_screen:Vector2) -> void:
 _art_frame=rect;_clerk_screen=clerk_screen
 if is_instance_valid(_panel):_layout()

func _layout() -> void:
 var frame:Rect2=_art_frame if _art_frame.has_area() else get_viewport().get_visible_rect()
 _ui_scale=DisplayMetrics.factor(frame.size)
 # Enlarge native content and the nine-patch destination; its four source-pixel
 # corners stay 1x. The device itself never receives a fractional transform.
 var device_size:Vector2=DisplayMetrics.point(DEVICE_SIZE,_ui_scale)
 _device.scale=Vector2.ONE;_device.size=device_size
 _casing.size=device_size
 DisplayMetrics.apply_control(_panel,_ui_scale)
 # Fixed source-pixel trim determines the live aperture. Extra 1080p space is
 # content area, not stretched corners; retain the original 720p aperture.
 var screen:Rect2=Rect2(SCREEN_RECT.position,device_size-Vector2(51,124))
 _screen_clip.size=screen.end+Vector2.ONE*SCREEN_BLEED
 _panel.offset_left=screen.position.x;_panel.offset_top=screen.position.y
 _panel.offset_right=screen.end.x;_panel.offset_bottom=screen.end.y
 var left:bool=_clerk_screen.x>frame.get_center().x
 var margin:float=roundf(24.0*_ui_scale)
 var x:float=margin if left else frame.size.x-device_size.x-margin
 x=clampf(x,0.0,maxf(0.0,frame.size.x-device_size.x))
 _device.position=(frame.position+Vector2(x,(frame.size.y-device_size.y)*0.5)).round()

func _label(value:String,font_size:int,color:Color=Color("101a30")) -> Label:
 var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 return label

func open_from_player(records:Array,current_day:int) -> bool:
 if _open or not is_instance_valid(_root) or current_day<1 or records.size()>MAX_REVIEWS:return false
 # Defense in depth only. Publication and factual ratings remain economy's
 # responsibility; this view cannot publish, infer, or fill a missing review.
 for review in records:
  if not review is Dictionary or not review.has_all(["client","rating","body","delivery_day","published_day"]):return false
  if int(review.delivery_day)>=current_day or int(review.published_day)>current_day:return false
 for child in _list.get_children():_list.remove_child(child);child.queue_free()
 _date.text="第 %d 天"%current_day if records.is_empty() else "第 %d 天 · %d 条"%[current_day,records.size()]
 if records.is_empty():_list.add_child(_label("还没有客户留言。",18,Color("fff3d7")))
 var previous_delivery_day:int=-1
 for review in records:
  var delivery_day:int=int(review.delivery_day)
  if delivery_day!=previous_delivery_day:
   var group_text:String="昨天 · 第 %d 天配送"%delivery_day if delivery_day==current_day-1 else "第 %d 天配送"%delivery_day
   var group:=_label(group_text,14,Color("edce73"));group.name="ReviewDateGroup";group.set_meta("phone_date_group",delivery_day);_list.add_child(group)
   previous_delivery_day=delivery_day
  var entry:=PanelContainer.new();entry.set_meta("phone_review",true);entry.focus_mode=Control.FOCUS_ALL;entry.mouse_filter=Control.MOUSE_FILTER_PASS;_list.add_child(entry)
  var paper:=StyleBoxFlat.new();paper.bg_color=Color("f7e9c7");paper.content_margin_left=12;paper.content_margin_right=12;paper.content_margin_top=12;paper.content_margin_bottom=12;entry.add_theme_stylebox_override("panel",paper)
  entry.focus_entered.connect(_entry_focus.bind(entry,true));entry.focus_exited.connect(_entry_focus.bind(entry,false))
  var lines:=VBoxContainer.new();lines.add_theme_constant_override("separation",6);lines.mouse_filter=Control.MOUSE_FILTER_PASS;entry.add_child(lines)
  lines.add_child(_label("%s   %d / 5"%[str(review.client),int(review.rating)],18))
  lines.add_child(_label(str(review.body),18))
 _scroll.scroll_vertical=0
 _home_date.text="第 %d 天"%current_day
 _page="home";_reviews.hide();_home.show()
 _open=true;_root.show();_layout();modal_changed.emit(true);page_changed.emit("home");_app.grab_focus()
 return true

func open_reviews_app() -> void:
 if not _open or _page=="reviews":return
 _page="reviews";_home.hide();_reviews.show();_close.grab_focus();page_changed.emit("reviews")

func back() -> void:
 if not _open:return
 if _page=="reviews":
  _page="home";_reviews.hide();_home.show();_app.grab_focus();page_changed.emit("home")
 else:close_phone()

func is_reviews_app_open() -> bool:return _open and _page=="reviews"

func _entry_focus(entry:PanelContainer,active:bool) -> void:
 var paper:StyleBoxFlat=entry.get_theme_stylebox("panel") as StyleBoxFlat
 paper.border_color=Color("ee7863");paper.set_border_width_all(3 if active else 0)

func close_phone() -> void:
 if not _open:return
 var focused:Control=get_viewport().gui_get_focus_owner()
 if focused!=null and (_root==focused or _root.is_ancestor_of(focused)):focused.release_focus()
 _open=false;_root.hide();modal_changed.emit(false)

func scroll_by(amount:float) -> void:
 if is_reviews_app_open() and is_finite(amount):_scroll.scroll_vertical+=roundi(amount)
func scroll_to_edge(bottom:bool) -> void:
 if is_reviews_app_open():_scroll.scroll_vertical=int(_scroll.get_v_scroll_bar().max_value) if bottom else 0
func is_open() -> bool:return _open
func focus_root() -> Control:return _panel

func _exit_tree() -> void:
 if _open:_open=false;modal_changed.emit(false)
