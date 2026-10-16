extends Node
## Only the new route's shared preview, preparation/retry advice and guarded
## debt copy. Headless presentation checks; no GUI interaction or save writes.
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Layout=preload("res://scripts/delivery_route_layout_v1.gd")
const Preview=preload("res://scripts/delivery_route_preview_v1.gd")
const UI=preload("res://scripts/delivery_ui_v3.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v8.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for tick in 5:await get_tree().process_frame
func visible_inside(control:Control,clip:Control)->bool:
 return control.is_visible_in_tree() and clip.get_global_rect().encloses(control.get_global_rect())
func native_contract_bounds()->void:
 # Match the real 1280x814 window's centered 720px native-density art frame.
 # This is the contract list Main supplies after A is declined, not activeorder.
 get_tree().root.size=Vector2i(1280,814)
 var hud=HUD.new();add_child(hud);hud.set_art_frame(Rect2(0,47,1280,720))
 var heavy:Dictionary=Chapter.fresh_route(2,false)
 heavy.contract_id="D7-B";heavy.status="available";heavy.client="叶笺";heavy.cargo="货站蓄能芯";heavy.destination_name="高架货站"
 heavy.story="这箱货站蓄能芯送往高架货站，最低交付完整度 75%。"
 var declined:Dictionary=Chapter.fresh_route(4);declined.contract_id="D7-A";declined.status="declined"
 var store:Array=[declined,heavy]
 var data:Dictionary={"mode":"contracts","control_version":Profile.VERSION,"activeorder":{},"contracts":store.filter(func(c):return c.status=="available"),"counter_customer_id":"D7-B","shop_action_availability":{"accept_contract":true},"settings":{"reduced_motion":true},"day":7,"credits":1460}
 hud.render(data);await settle()
 var drawer:Control=hud.content.find_child("SceneDrawer",true,false)
 var scroll:ScrollContainer=hud.content.find_child("ContractList",true,false)
 var card:Control=hud.content.find_child("Waybill1",true,false)
 var accept:Button
 var details:Button
 for button in card.find_children("*","Button",true,false):
  if button.get_meta("shop_contract_id","")=="D7-B":accept=button
  if button.get_meta("view_key","")=="details:order:D7-B":details=button
 check(data.contracts.size()==1 and data.activeorder.is_empty() and hud._ui_scale==1.0 and hud.root.get_global_rect()==Rect2(0,47,1280,720),"native fixture has declined A available B matching counter and 720px art frame")
 check(accept!=null and not accept.disabled and details!=null,"native single heavy offer has enabled accept and real detail controls")
 print("NATIVE_HEAVY_CLOSED drawer=",drawer.get_global_rect()," scroll=",scroll.get_global_rect()," card=",card.get_global_rect()," details=",details.get_global_rect()," accept=",accept.get_global_rect())
 check(visible_inside(accept,scroll) and visible_inside(details,scroll) and visible_inside(drawer,hud.root),"single heavy details and accept are wholly visible on the initial native screen")
 check(scroll.get_global_rect().size.y>=card.get_global_rect().size.y and card.get_global_rect().encloses(accept.get_global_rect()),"closed single heavy card fits the contract viewport instead of losing its footer")
 var guidance:Label=card.find_child("HeavyRoutePreparation",true,false)
 var ink:Color=guidance.get_theme_color("font_color");var paper:Color=(card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
 var contrast:float=(paper.srgb_to_linear().get_luminance()+.05)/(ink.srgb_to_linear().get_luminance()+.05)
 check(contrast>=4.5,"heavy preparation uses readable dark text on the light order card")
 details.pressed.emit();await settle()
 var detail_body:Control=card.find_child("OptionalDetails",true,false)
 scroll.ensure_control_visible(accept);await settle()
 print("NATIVE_HEAVY_OPEN scroll=",scroll.get_global_rect()," content=",card.get_global_rect()," accept=",accept.get_global_rect()," offset=",scroll.scroll_vertical," max=",scroll.get_v_scroll_bar().max_value," page=",scroll.get_v_scroll_bar().page)
 check(detail_body.is_visible_in_tree() and scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page and scroll.scroll_vertical>0,"expanded real details stay in a scrollable contract body")
 check(visible_inside(accept,scroll) and visible_inside(accept,hud.root) and card.get_global_rect().encloses(accept.get_global_rect()),"expanded heavy details can scroll all the way to the complete accept button")
 var intents:Array=[]
 hud.action_requested.connect(func(action:String,payload:Variant):intents.append([action,payload]))
 accept.pressed.emit()
 check(intents==[["accept_contract","D7-B"]],"visible accept emits only the matching B contract action")
 # An existing two-offer drawer still permits reaching B; it must not grow
 # beyond the native frame merely because a new route preview is present.
 var available_a:Dictionary=declined.duplicate(true);available_a.status="available"
 data.contracts=[available_a,heavy];hud.render(data);await settle()
 drawer=hud.content.find_child("SceneDrawer",true,false);scroll=hud.content.find_child("ContractList",true,false);card=hud.content.find_child("Waybill2",true,false)
 for button in card.find_children("*","Button",true,false):
  if button.get_meta("shop_contract_id","")=="D7-B":accept=button
 scroll.ensure_control_visible(accept);await settle()
 check(visible_inside(drawer,hud.root) and visible_inside(accept,scroll) and not accept.disabled,"two available offers retain bounded scrolling to the matching heavy B action")
 hud.queue_free();await settle()

func run()->void:
 if OS.get_environment("SC_HEAVY_UI_ISOLATED")!="1":get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,720)
 var order:Dictionary=Chapter.fresh_route(2);order.contract_id="ui-heavy-new"
 check(Layout.validation_error(order).is_empty() and UI.heavy_route(order),"only valid new heavy identity enables new presentation")
 var before:PackedByteArray=var_to_bytes(order)
 var sketch=Preview.new();sketch.size=Vector2(160,52);add_child(sketch);sketch.present(order)
 var snapshot:Dictionary=sketch.snapshot();var geometry:Dictionary=sketch.projected_geometry()
 check(snapshot.receiver==Vector2(110,-72) and snapshot.altitude_m==72.0 and snapshot.cargo_mass_kg==12.0 and snapshot.min_delivery_integrity==.75,"shared preview reads actual height cargo mass and integrity")
 check(geometry.circles.size()==1 and geometry.paths.is_empty(),"single rock view makes no safe-path or trajectory promise")
 check(snapshot.circles[0].position==Vector2(62,-64) and snapshot.circles[0].radius==9.0 and is_equal_approx(geometry.circles[0].radius,snapshot.circles[0].radius*geometry.scale),"rock position radius and projection are metric-consistent")
 check(geometry.receiver.y<geometry.launch.y and geometry.receiver.x>geometry.launch.x,"elevated receiver remains above and ahead of launch")
 check(UI.route_copy(order).contains("72 m") and UI.route_copy(order).contains("12.0 kg") and UI.route_copy(order).contains("75%"),"caption makes actual load and delivery requirements readable")
 check(UI.route_guidance(order).contains("默认台") and UI.route_guidance(order).contains("裸重货") and UI.route_guidance(order).contains("动力件与支撑") and UI.route_guidance(order).contains("船上推进"),"preparation cue explains two build directions without locking a part")
 check(var_to_bytes(order)==before,"preview and preparation helpers never mutate the accepted route")
 var old:Dictionary=order.duplicate(true);old.erase("route_layout");old.destination_y=-18.0;old.hazards=[]
 sketch.present(old)
 check(not sketch.visible and UI.route_copy(old).is_empty() and UI.route_guidance(old).is_empty(),"old heavy offers do not inherit new slope or preparation claims")
 var invalid:Dictionary=order.duplicate(true);invalid.hazards[0].radius=8.0;sketch.present(invalid)
 check(not sketch.visible and not UI.heavy_route(invalid) and UI.route_guidance(invalid).is_empty(),"invalid frozen geometry cannot create misleading heavy advice")
 var fragile:Dictionary=Chapter.fresh_route(3);sketch.present(fragile)
 check(sketch.projected_geometry().paths.size()==3 and sketch.snapshot().circles.size()==2 and UI.route_copy(fragile)=="窄道 2.4 m · 可从上 / 下方绕行" and UI.route_guidance(fragile).is_empty(),"fragile corridor geometry caption and original choices remain intact")
 var near:Dictionary={"destination_distance":20.0,"speed":11.0,"flight_status":"running","charging":false}
 check(UI.receipt_speed(near,order).get("text")=="收件 ≤ 10.0 m/s" and UI.receipt_speed(near,order).get("overspeed")==true,"new heavy approach displays actual unchanged receiving limit")
 check(UI.receipt_speed(near,old).is_empty(),"old ground-order speed presentation remains unchanged")
 var hud=HUD.new();add_child(hud)
 var data:Dictionary={"mode":"contracts","control_version":Profile.VERSION,"activeorder":order,"contracts":[order],"assembly_mode":"craft","parts":Profile.starter_design(),"selectedpart":{},"settings":{"reduced_motion":true},"has_accepted_contract":false,"credits":100,"trial":false}
 hud.render(data);await settle()
 var card:Node=hud.content.find_child("Waybill1",true,false)
 check(card.find_child("DeliveryRouteSketch",true,false).snapshot()==snapshot and card.find_child("RouteClearance",true,false).text==UI.route_copy(order),"preacceptance card exposes shared heavy route and requirements")
 var prep:Label=card.find_child("HeavyRoutePreparation",true,false)
 check(prep!=null and prep.is_visible_in_tree() and prep.text==UI.route_guidance(order),"preparation suggestion is visible before acceptance without opening details")
 var repeat_order:Dictionary=Chapter.fresh_route(2,false);repeat_order.contract_id="ui-heavy-repeat";repeat_order.name="剧情名称";repeat_order.story="剧情覆盖"
 check(UI.route_copy(repeat_order).begins_with("自选复送 · 不推进章节\n"),"optional heavy repeat remains explicit despite story name changes")
 data.contracts=[repeat_order];data.activeorder=repeat_order;data.mode="workshop";data.has_accepted_contract=true
 hud.render(data);await settle()
 var panel:Control=hud.content.find_child("WorkshopRouteSketch",true,false)
 var route_sketch:Control=panel.find_child("DeliveryRouteSketch",true,false)
 var heading:Label=panel.find_child("RouteClearance",true,false)
 prep=panel.find_child("HeavyRoutePreparation",true,false)
 check(heading.is_visible_in_tree() and heading.text==UI.route_copy(repeat_order) and prep.text==UI.route_guidance(repeat_order) and route_sketch.snapshot()==snapshot,"workshop exposes same frozen requirements repeat flag and practical build cue")
 check(panel.size.y<=120.0 and panel.get_global_rect().encloses(heading.get_global_rect()) and panel.get_global_rect().encloses(prep.get_global_rect()) and panel.get_global_rect().encloses(route_sketch.get_global_rect()),"heavy repeat and guidance fit existing 120 px workshop header")
 check(not panel.get_global_rect().intersects(hud.workshop_scene_rect()) and hud.content.find_child("DispatchActions",true,false)!=null and hud.content.find_child("WorkshopTools",true,false)!=null,"new guidance preserves build area and trial dispatch controls")
 data.activeorder=old;hud.render(data);await settle()
 check(hud.content.find_child("WorkshopRouteSketch",true,false)==null and hud.content.find_child("HeavyRoutePreparation",true,false)==null,"returning to old contract removes new heavy UI")
 var report:Dictionary={"contract_id":order.contract_id,"control_version":order.control_version,"success":false,"trial":false,"delivery_integrity":1.0,"min_delivery_integrity":.75,"restored":true,"credits_after":-50,"debt":50,"debt_added":50,"events":["操作员中止本次航行。"]}
 var rbefore:PackedByteArray=var_to_bytes(report)
 check(not UI.heavy_retry_copy(report,order).is_empty() and not UI.heavy_retry_copy(report,order).contains("能量不足"),"new heavy failure offers a next step without inventing energy diagnosis")
 var wrong:Dictionary=order.duplicate(true);wrong.contract_id="other"
 check(UI.heavy_retry_copy(report,wrong).is_empty() and UI.heavy_retry_copy(report,old).is_empty() and UI.heavy_retry_copy(report,{}).is_empty(),"failure advice requires matching nonempty identity and validated heavy geometry")
 var without_id:Dictionary=report.duplicate(true);without_id.erase("contract_id")
 check(UI.heavy_retry_copy(without_id,order).is_empty(),"unbound report never guesses heavy identity")
 var succeeded:Dictionary=report.duplicate(true);succeeded.success=true
 check(UI.heavy_retry_copy(succeeded,order).is_empty(),"successful heavy delivery receives no failure advice")
 data.mode="report";data.activeorder={};data.report_order=order;data.report=report;data.credits=-50
 hud.render(data);await settle()
 check(hud._report_failure_copy(report)=="你结束了本次飞行。" and hud.content.find_child("HeavyRouteRetryGuidance",true,false)!=null,"terminal reason stays exact while formal report reads owner supplied route after activeorder clears")
 var debt_hint:Label=hud.content.find_child("DebtRecoveryGuidance",true,false)
 check(debt_hint!=null and debt_hint.is_visible_in_tree() and debt_hint.text.contains("原装配已恢复") and debt_hint.text.contains("打烊后可接轻货赚运费"),"verified restored chapter debt gets visible recovery guidance")
 check(var_to_bytes(report)==rbefore,"failure and debt presentation do not change report or economy")
 for change in [{"restored":false},{"restored":1},{"trial":true},{"trial":"false"},{"debt":0},{"control_version":"pilot-free-v2"}]:
  var denied:Dictionary=report.duplicate(true);denied.merge(change,true)
  check(UI.debt_recovery_copy(denied,data).is_empty(),"debt recovery advice withheld for report "+str(change))
 for change in [{"credits":0},{"credits":100},{"credits":"-50"},{"control_version":"pilot-free-v2"}]:
  var denied:Dictionary=data.duplicate(true);denied.merge(change,true)
  check(UI.debt_recovery_copy(report,denied).is_empty(),"debt recovery advice withheld for current state "+str(change))
 var trial_report:Dictionary=report.duplicate(true);trial_report.trial=true;trial_report.erase("restored");trial_report.erase("debt")
 data.report=trial_report;data.activeorder=order;data.credits=100;hud.render(data);await settle()
 check(hud.content.find_child("HeavyRouteRetryGuidance",true,false)!=null and hud.content.find_child("DebtRecoveryGuidance",true,false)==null,"free retry receives route advice without debt or restoration promise")
 data.report=report;data.report_order=wrong;data.credits=-50;hud.render(data);await settle()
 check(hud.content.find_child("HeavyRouteRetryGuidance",true,false)==null,"unrelated current order cannot annotate another receipt")
 sketch.queue_free();hud.queue_free();await settle()
 await native_contract_bounds()
 print("HEAVY_ROUTE_UI_V1 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
