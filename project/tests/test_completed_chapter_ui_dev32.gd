extends Node
## Bounded read-only presentation checks. Synthetic malformed states are not
## gameplay evidence; Main uses a byte-copied, completed native dev31 save.
const UI=preload("res://scripts/delivery_ui_v3.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Main=preload("res://scripts/main.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for frame in 5:await get_tree().process_frame
func inside(control:Control,clip:Control)->bool:
 return control!=null and control.is_visible_in_tree() and clip.get_global_rect().encloses(control.get_global_rect())
func labels_with(root:Node,copy:String)->int:
 var count:int=0
 for label in root.find_children("*","Label",true,false):
  if label.text.contains(copy):count+=1
 return count
func offer(level:int,progression:bool=false,recovery:bool=false)->Dictionary:
 var order:Dictionary=Chapter.fresh_route(level,progression,recovery)
 order.contract_id="UI-L%d"%level;order.status="available"
 return order
func run()->void:
 if OS.get_environment("SC_COMPLETED_CHAPTER_UI_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 var status:Dictionary={"enabled":true,"complete":true,"unlocked_level":6,"level":5,"debt":0}
 check(UI.completed_chapter_copy({"delivery_chapter_status":status})=="五关已完成","explicit enabled completed five-level status shows completion")
 var source:PackedByteArray=var_to_bytes(status)
 for change in [{"enabled":false},{"enabled":1},{"complete":false},{"complete":1},{"unlocked_level":5},{"unlocked_level":7},{"unlocked_level":true},{"unlocked_level":"6"},{"unlocked_level":NAN}]:
  var bad:Dictionary=status.duplicate(true);bad.merge(change,true)
  check(UI.completed_chapter_copy({"delivery_chapter_status":bad}).is_empty(),"incomplete legacy or malformed progress cannot claim completion "+str(change))
 check(UI.completed_chapter_copy({}).is_empty() and UI.completed_chapter_copy({"delivery_chapter_status":[]}).is_empty(),"missing or malformed status stays unannotated")
 check(var_to_bytes(status)==source,"completion display preserves supplied status bytes")
 for level in range(1,6):
  var order:Dictionary=offer(level);var frozen:PackedByteArray=var_to_bytes(order)
  check(UI.repeat_copy(order)=="自选复送 · 不推进章节" and UI.route_copy(order).count("自选复送")==1,"level %d has exactly one frozen-intent repeat caption"%level)
  check(UI.repeat_copy(offer(level,true)).is_empty() and UI.repeat_copy(offer(level,false,true)).is_empty(),"level %d first-progressing and recovery quotes stay distinct"%level)
  check(var_to_bytes(order)==frozen,"level %d presentation preserves frozen quote"%level)
 var repeat:Dictionary=offer(4)
 for change in [{"chapter_progression":0},{"chapter_progression":"false"},{"recovery_offer":0},{"recovery_offer":"false"},{"chapter_level":0},{"chapter_level":6},{"chapter_level":2.5},{"chapter_level":"4"},{"chapter_level":true},{"chapter_level":NAN},{"control_version":"pilot-free-v2"}]:
  var bad:Dictionary=repeat.duplicate(true);bad.merge(change,true)
  check(UI.repeat_copy(bad).is_empty(),"bad frozen repeat identity never inferred "+str(change))
 for key in ["chapter_progression","recovery_offer","chapter_level"]:
  var bad:Dictionary=repeat.duplicate(true);bad.erase(key)
  check(UI.repeat_copy(bad).is_empty(),"missing frozen "+key+" is never guessed")
 var hud=HUD.new();add_child(hud);get_tree().root.size=Vector2i(1280,814);hud.set_art_frame(Rect2(0,47,1280,720))
 var data:Dictionary={"mode":"hub","control_version":"pilot-delivery-v3","activeorder":{},"contracts":[],"day":6,"credits":1799,"settings":{"reduced_motion":true},"delivery_chapter_status":status}
 hud.render(data);await settle()
 var completion:Label=hud.content.find_child("CompletedChapterStatus",true,false)
 check(completion!=null and completion.text.contains("五关已完成") and completion.text.contains("复送"),"existing storefront exposes completed chapter and continuing work")
 check(not completion.get_global_rect().intersects(hud.content.find_child("DayLedger",true,false).get_global_rect()) and not completion.get_global_rect().intersects(hud.content.find_child("CurrentWaybill",true,false).get_global_rect()),"completion line leaves ledger and current waybill unobstructed")
 data.delivery_chapter_status=status.duplicate(true);data.delivery_chapter_status.debt=40;hud.render(data);await settle()
 completion=hud.content.find_child("CompletedChapterStatus",true,false)
 check(completion.text.contains("五关已完成") and completion.text.contains("打烊后可接轻货偿债") and not completion.text.contains("复送"),"completed indebted shop names next-day recovery rather than optional repeats")
 data.delivery_chapter_status={"enabled":true,"complete":false,"unlocked_level":5};hud.render(data);await settle()
 check(hud.content.find_child("CompletedChapterStatus",true,false)==null,"returning to unfinished shop removes stale completion label")
 data.delivery_chapter_status=status
 for level in [2,3,4,5]:
  var order:Dictionary=offer(level);var frozen:PackedByteArray=var_to_bytes(order)
  data.mode="contracts";data.activeorder={};data.contracts=[order];data.counter_customer_id=order.contract_id;data.shop_action_availability={"accept_contract":true}
  hud.render(data);await settle()
  var card:Control=hud.content.find_child("Waybill1",true,false);var scroll:ScrollContainer=hud.content.find_child("ContractList",true,false);var accept:Button;var details:Button
  for button in card.find_children("*","Button",true,false):
   if button.get_meta("shop_contract_id","")==order.contract_id:accept=button
   if button.get_meta("view_key","")=="details:order:"+order.contract_id:details=button
  check(labels_with(card,"自选复送 · 不推进章节")==1,"level %d card shows repeat intent once outside details"%level)
  check(inside(accept,scroll) and inside(details,scroll) and not accept.disabled,"level %d full accept and details actions start in viewport"%level)
  print("REPEAT_CARD level=",level," card=",card.get_global_rect()," scroll=",scroll.get_global_rect()," accept=",accept.get_global_rect())
  details.pressed.emit();await settle();scroll.ensure_control_visible(accept);await settle()
  check(inside(accept,scroll),"level %d expanded details keep accept reachable"%level)
  data.mode="workshop";data.activeorder=order;data.has_accepted_contract=true;data.assembly_mode="craft";data.parts=[]
  hud.render(data);await settle()
  var panel:Control=hud.content.find_child("WorkshopRouteSketch",true,false)
  check(panel!=null and panel.size.y<=120 and labels_with(panel,"自选复送 · 不推进章节")==1,"level %d workbench repeat label fits existing compact header once"%level)
  var contents_inside:bool=true
  for node in panel.find_children("*","Control",true,false):
   if node is Label or node.name=="DeliveryRouteSketch":contents_inside=contents_inside and inside(node,panel)
  check(contents_inside and not panel.get_global_rect().intersects(hud.workshop_scene_rect()),"level %d workbench text and map stay in header without covering grid"%level)
  if level==5:
   var sketch:Control=panel.find_child("DeliveryRouteSketch",true,false)
   check(sketch!=null and sketch.snapshot()==UI.route_preview(order) and sketch.size.y>=70,"rift repeat preserves full dev31 map and frozen danger geometry")
  elif level==4:check(panel.find_child("DeliveryRouteSketch",true,false)==null,"moon repeat uses only short intent text without inventing a map")
  print("REPEAT_WORKSHOP level=",level," panel=",panel.get_global_rect())
  check(var_to_bytes(order)==frozen,"level %d card and workshop rendering leave contract bytes unchanged"%level)
 data.mode="contracts";data.contracts=[offer(1,false,true)];hud.render(data);await settle()
 check(labels_with(hud.content,"自选复送")==0,"completed shop does not relabel frozen basic recovery quote")
 data.contracts=[offer(5,true)];hud.render(data);await settle()
 check(labels_with(hud.content,"自选复送")==0,"current completion does not relabel earlier first-run fifth quote")
 data.mode="report";data.report={"trial":false,"success":true,"control_version":"pilot-rift-v8","delivery_integrity":1.0,"min_delivery_integrity":.8};data.activeorder={}
 hud.render(data);await settle()
 check(hud.content.find_child("CompletedChapterReceipt",true,false).text=="配送结果 · 五关已完成","existing settlement heading exposes actual completed chapter")
 data.delivery_chapter_status={"enabled":false,"complete":false};hud.render(data);await settle()
 check(hud.content.find_child("CompletedChapterReceipt",true,false)==null,"nonchapter receipt cannot inherit completed chapter label")
 hud.queue_free();await settle()
 await actual_main_status()
 print("COMPLETED_CHAPTER_UI_DEV32 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
func actual_main_status()->void:
 var main=Main.new();main.entry_require_existing_save=true;main.entry_defer_controls=true;main.clerk_pose_bootstrap_script=load("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");add_child(main);main.set_process(false)
 if main.economy.review_load_blocked:
  check(false,"Main loads copied native completed dev31 save");main.queue_free();await settle();return
 check(main.economy.day==6 and main.economy.credits==1799 and main.economy.delivery_chapter_state.unlocked_level==6,"Main input is real completed dev31 day6 balance1799 save")
 var before:PackedByteArray=var_to_bytes([main.economy.delivery_chapter_state,main.economy.contracts,main.economy.settled_ids,main.economy.inventory,main.economy.credits])
 main.page="hub";main.render();await settle()
 check(main.hud.state.delivery_chapter_status==main.economy.delivery_chapter_status() and main.hud.content.find_child("CompletedChapterStatus",true,false)!=null,"actual Main forwards read-only economic completion to storefront")
 check(before==var_to_bytes([main.economy.delivery_chapter_state,main.economy.contracts,main.economy.settled_ids,main.economy.inventory,main.economy.credits]),"Main presentation changes no progression contracts ledger inventory or balance")
 main.queue_free();await settle()
