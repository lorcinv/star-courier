extends SceneTree
## UI-only fixture. Synthetic published records never enter the economy.
const Phone=preload("res://scripts/customer_review_phone.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=3) -> void:
 for unused in n:await process_frame
func records() -> Array:
 var rows:Array=[]
 for i in 30:
  rows.append({"client":"月面收件人 %d"%i,"rating":5-i%3,"body":"货物已经收到。包装保持完好，送达时间也符合约定。","delivery_day":30-i/2,"published_day":31-i/2})
 return rows
func entries(phone) -> Array:return phone._list.get_children().filter(func(child):return child.has_meta("phone_review"))
func run() -> void:
 var phone=Phone.new();root.add_child(phone);await settle()
 var theme:=Theme.new();theme.default_font=load("res://assets/fonts/ChineseSans.otf");theme.default_font_size=18;phone.set_existing_theme(theme)
 check(not phone.is_open() and phone._casing.texture.get_size()==Vector2(395,624),"imagegen casing is registered and startup stays closed")
 check(phone.open_from_player([],1),"empty feed opens explicitly")
 check(phone._list.get_child_count()==1 and phone._list.get_child(0).text=="还没有客户留言。","empty feed remains concise native text")
 check(root.gui_get_focus_owner()==phone._close and phone.focus_root()==phone._panel,"close remains safe default inside same focus root")
 phone.close_phone();await settle()
 var history:Array=records();var before:Array=history.duplicate(true)
 check(phone.open_from_player(history,31),"bounded thirty historical records open")
 await settle()
 var groups:Array=phone._list.get_children().filter(func(child):return child.has_meta("phone_date_group"))
 check(entries(phone).size()==30 and groups.size()==15,"adjacent same-day records share fifteen date headings")
 check(groups[0].text=="昨天 · 第 30 天配送" and groups[1].text=="第 29 天配送","yesterday and earlier dates derive only from published delivery dates")
 var index:int=0
 for entry in entries(phone):
  var lines:VBoxContainer=entry.get_child(0)
  check(lines.get_child(1).text==history[index].body and lines.get_child(1).get_theme_font_size("font_size")==18 and lines.get_child(0).text=="%s   %d / 5"%[history[index].client,history[index].rating],"entry %d preserves body, rating, identity and body font"%index)
  index+=1
 var bar:VScrollBar=phone._scroll.get_v_scroll_bar()
 check(bar.visible and bar.size.x>=12 and bar.get_theme_stylebox("grabber").get_minimum_size().y>=30,"long history exposes clear native track and bounded thumb")
 check(phone._scroll.follow_focus,"native focus follows a scrolled review")
 for size in [Vector2(1280,800),Vector2(1920,1080),Vector2(3840,2160)]:
  for right in [false,true]:
   var frame:=Rect2(Vector2(0,0),size);phone.set_art_frame(frame,Vector2(size.x*.8 if right else size.x*.2,size.y*.7));await settle()
   var scale:int=clampi(floori(size.y/720),1,3)
   check(phone._panel.size==Vector2(344,500) and phone._panel.get_global_rect().size==Vector2(344,500)*scale and frame.encloses(phone._device.get_global_rect()),"unchanged readable screen and integer shell at %s right=%s"%[size,right])
   check(phone._device.position.x==24*scale if right else phone._device.position.x==size.x-419*scale,"phone stays opposite clerk at %s right=%s"%[size,right])
 phone.scroll_to_edge(true);await settle();check(phone._scroll.scroll_vertical>1000,"native long history reaches tail")
 phone.scroll_to_edge(false);await settle();check(phone._scroll.scroll_vertical==0,"native long history returns to first group")
 check(history==before,"UI does not mutate caller records")
 phone.close_phone();await settle()
 var bad:Array=history.duplicate(true);bad[0].delivery_day=31
 check(not phone.open_from_player(bad,31),"same-day review defense remains closed")
 bad=history.duplicate(true);bad[0].published_day=32
 check(not phone.open_from_player(bad,31),"future publication defense remains closed")
 bad=history.duplicate(true);bad.append(history[0].duplicate(true))
 check(not phone.open_from_player(bad,31),"over thirty records defense remains closed")
 phone.open_from_player(history,31);phone.close_phone();await settle(5)
 var baseline:int=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
 for i in 40:
  check(phone.open_from_player(history,31),"repeat explicit opening %d"%i);phone.close_phone();phone.close_phone();await settle()
 check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))<=baseline+1,"forty grouped history rebuilds plateau native node count")
 check(history==before,"repeated open/close preserves caller data")
 phone.queue_free();await settle()
 print("CUSTOMER_REVIEW_PHONE_SKIN passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
