extends Node
## Headless presentation checks against frozen routes and actual Control bounds.
## These do not stand in for native playthrough or complete-flight physics tests.
const UI=preload("res://scripts/delivery_ui_v3.gd")
const Risk=preload("res://scripts/delivery_rift_risk_ui_v1.gd")
const Preview=preload("res://scripts/delivery_route_preview_v1.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for frame in 5:await get_tree().process_frame
func visible_inside(control:Control,clip:Control)->bool:
 return control!=null and control.is_visible_in_tree() and clip.get_global_rect().encloses(control.get_global_rect())
func offer()->Dictionary:
 var order:Dictionary=Chapter.fresh_route(5)
 order.contract_id="D8-A";order.status="available";order.client="小禾";order.cargo="活体苔光幼苗";order.destination_name="裂隙苔光温室"
 return order
func run()->void:
 if OS.get_environment("SC_RIFT_RISK_UI_ISOLATED")!="1":get_tree().quit(2);return
 var order:Dictionary=offer();var original:PackedByteArray=var_to_bytes(order)
 check(order.control_version=="pilot-rift-v8" and not Risk.preview(order).is_empty(),"current normal chapter route activates frozen-risk view")
 var sketch=Preview.new();sketch.size=Vector2(376,80);add_child(sketch);sketch.present(order)
 var snapshot:Dictionary=sketch.snapshot();var view:Dictionary=sketch.projected_geometry()
 check(snapshot.entry==Vector2(28,0) and snapshot.exit==Vector2(100,0) and snapshot.aperture_radius==5 and snapshot.margin==.25,"preview reads actual gate planes aperture and conservative margin")
 check(snapshot.cold_bounds==Rect2(130,-10,40,20) and snapshot.turbulence_bounds==Rect2(132,-10,35,20),"cold and turbulence are distinct actual frozen rectangles")
 check(snapshot.grace_seconds==2.5 and snapshot.damage_hp_per_second==3.0 and snapshot.period_seconds==7.0 and snapshot.active_seconds==3.0,"preview carries actual grace damage rate and field timing")
 check(view.paths.is_empty() and view.circles.is_empty(),"risk map invents neither guaranteed flight path nor full-ship wall")
 check(is_equal_approx(view.cold_bounds.size.x,40*view.scale) and is_equal_approx(view.turbulence_bounds.size.x,35*view.scale) and is_equal_approx(view.aperture_radius,5*view.scale),"gate and both field projections share metric scale")
 check(is_equal_approx(view.exit.x-view.entry.x,72*view.scale) and view.cold_bounds.position.y>0 and view.cold_bounds.end.y<sketch.size.y,"entry exit spacing and warm space beyond cold edges remain visible")
 check(UI.route_preview(order)==snapshot and UI.route_copy(order).contains("10 m") and UI.route_copy(order).contains("2.5 s") and UI.route_copy(order).contains("3 HP/s"),"shared caption exposes actual opening grace and damage without manual defaults")
 check(Risk.guidance(order).contains("货物中心") and Risk.guidance(order).contains("刚体重心") and Risk.guidance(order).contains("保守包络") and Risk.guidance(order).contains("旋转不保证"),"guidance distinguishes all three real sampling rules")
 check(sketch.tooltip_text.contains("护盾不保温") and sketch.tooltip_text.contains("不保证无海盗") and snapshot.pirate_position==Vector2(154,-20),"preview never promises shield insulation or risk-free warm detour")
 check(var_to_bytes(order)==original,"all read-only helpers preserve frozen current order bytes")
 for profile in [Risk.V5,Risk.V6,Risk.V7,Risk.V8]:
  var old:Dictionary=profile.route();old.contract_id="old-"+str(profile.VERSION)
  old.rift_portal.entry=[31.0,1.0];old.rift_portal.exit=[103.0,2.0];old.rift_portal.aperture_radius=6.0;old.rift_portal.margin=.3
  old.rift_biology.cold_bounds=[140.0,-15.0,30.0,12.0];old.rift_biology.grace_seconds=4.25;old.rift_biology.damage_hp_per_second=1.75
  old.rift_turbulence.bounds=[136.0,-12.0,25.0,18.0];old.rift_turbulence.period_seconds=9.0;old.rift_turbulence.active_seconds=2.0
  var frozen:PackedByteArray=var_to_bytes(old);sketch.present(old);var own:Dictionary=sketch.snapshot()
  check(not own.is_empty() and own.entry==Vector2(31,1) and own.exit==Vector2(103,2) and own.cold_bounds==Rect2(140,-15,30,12) and own.turbulence_bounds==Rect2(136,-12,25,18),"old "+profile.VERSION+" draws its own geometry")
  check(UI.route_copy(old).contains("12 m") and UI.route_copy(old).contains("4.25 s") and UI.route_copy(old).contains("1.75 HP/s") and var_to_bytes(old)==frozen,"old "+profile.VERSION+" retains its own rates without mutation")
 for change in [{"rift_biology":{}},{"rift_portal":{}},{"control_version":"pilot-free-v2"}]:
  var invalid:Dictionary=order.duplicate(true);invalid.merge(change,true);sketch.present(invalid)
  check(not sketch.visible and UI.route_copy(invalid).is_empty(),"missing or unsupported frozen data cannot create risk guidance "+str(change.keys()))
 var bad:Dictionary=order.duplicate(true);bad.rift_biology.grace_seconds=NAN
 check(Risk.preview(bad).is_empty(),"nonfinite frozen damage settings do not render fabricated numbers")
 var flight:Dictionary={"portal_crossing_tick":20,"region":"greenhouse","biological_exposure_seconds":9.5,"biological_temperature_c":-12.0,"delivery_integrity":.79,"flight_status":"running","speed":5.0,"height":0.0,"energy_remaining":1000.0}
 var before:PackedByteArray=var_to_bytes(flight)
 check(Risk.biology(flight,order).text.contains("9.5/2.5 s") and Risk.biology(flight,order).note.contains("正受冷损"),"79 percent cargo retains actual harmful exposure and rate")
 var warm:Dictionary=flight.duplicate(true);warm.biological_temperature_c=18.0;warm.biological_exposure_seconds=0.0
 check(not Risk.biology(warm,order).cold and Risk.biology(warm,order).text.contains("当前不增冷损") and Risk.biology(warm,order).note.contains("不会自动修复"),"warm exit stops new cold damage without implying healing")
 var grace:Dictionary=flight.duplicate(true);grace.biological_exposure_seconds=2.0
 check(not Risk.biology(grace,order).note.contains("正受冷损"),"within-grace exposure does not claim cold damage already occurs")
 for change in [{"portal_crossing_tick":-1},{"region":"departure"},{"biological_exposure_seconds":"9.5"},{"biological_temperature_c":NAN}]:
  var invalid:Dictionary=flight.duplicate(true);invalid.merge(change,true)
  check(Risk.biology(invalid,order).is_empty(),"unknown or preportal biological state is withheld "+str(change.keys()))
 check(var_to_bytes(flight)==before,"status helper never alters measured flight telemetry")
 var report:Dictionary={"contract_id":order.contract_id,"control_version":order.control_version,"success":false,"trial":true,"delivery_integrity":.79,"min_delivery_integrity":.8,"biological_damage":21.0,"events":["操作员中止本次航行。"]}
 check(Risk.report_copy(report,order).contains("21 HP") and not Risk.report_copy(report,order).contains("21%"),"receipt explains recorded cold HP without claiming percent or all damage")
 var zero:Dictionary=report.duplicate(true);zero.biological_damage=0.0
 check(Risk.report_copy(zero,order).contains("0 HP"),"explicit measured zero is distinguishable from missing evidence")
 var missing:Dictionary=report.duplicate(true);missing.erase("biological_damage")
 check(Risk.report_copy(missing,order).is_empty(),"missing historical cold counter never turns into zero")
 for change in [{"contract_id":"other"},{"control_version":"pilot-free-v2"},{"biological_damage":-1},{"biological_damage":NAN},{"biological_damage":"21"}]:
  var invalid:Dictionary=report.duplicate(true);invalid.merge(change,true)
  check(Risk.report_copy(invalid,order).is_empty(),"receipt guards identity and measured counter "+str(change.keys()))
 var hud=HUD.new();add_child(hud);get_tree().root.size=Vector2i(1280,814);hud.set_art_frame(Rect2(0,47,1280,720))
 var data:Dictionary={"mode":"contracts","control_version":"pilot-delivery-v8","contracts":[order],"activeorder":{},"counter_customer_id":order.contract_id,"shop_action_availability":{"accept_contract":true},"settings":{"reduced_motion":true},"day":8,"credits":1000,"trial":true}
 hud.render(data);await settle()
 var card:Control=hud.content.find_child("Waybill1",true,false);var scroll:ScrollContainer=hud.content.find_child("ContractList",true,false);var accept:Button;var details:Button
 for button in card.find_children("*","Button",true,false):
  if button.get_meta("shop_contract_id","")==order.contract_id:accept=button
  if button.get_meta("view_key","")=="details:order:"+order.contract_id:details=button
 var route:Control=card.find_child("DeliveryRouteSketch",true,false);var guidance:Label=card.find_child("RiftRoutePreparation",true,false)
 check(route.snapshot()==snapshot and guidance.text==Risk.guidance(order) and visible_inside(route,scroll) and visible_inside(guidance,scroll),"preacceptance card shows actual diagram and concise sampling rules")
 print("RIFT_CLOSED card=",card.get_global_rect()," scroll=",scroll.get_global_rect()," accept=",accept.get_global_rect())
 check(accept!=null and not accept.disabled and visible_inside(accept,scroll) and visible_inside(details,scroll) and card.get_global_rect().size.y<=scroll.get_global_rect().size.y,"single fifth-level card retains first-screen full accept and detail buttons")
 var ink:Color=guidance.get_theme_color("font_color");var paper:Color=(card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
 check((paper.srgb_to_linear().get_luminance()+.05)/(ink.srgb_to_linear().get_luminance()+.05)>=4.5,"risk guidance stays readable on the light contract card")
 details.pressed.emit();await settle();scroll.ensure_control_visible(accept);await settle()
 check(visible_inside(accept,scroll) and card.find_child("OptionalDetails",true,false).is_visible_in_tree(),"expanded fifth-level details scroll to full accept action")
 var intents:Array=[];hud.action_requested.connect(func(action:String,payload:Variant):intents.append([action,payload]));accept.pressed.emit()
 check(intents==[["accept_contract",order.contract_id]],"visible accept emits only the matching frozen contract action")
 data.activeorder=order;data.mode="workshop";data.assembly_mode="craft";data.parts=Risk.V8.starter_design();data.has_accepted_contract=true
 hud.render(data);await settle()
 var panel:Control=hud.content.find_child("WorkshopRouteSketch",true,false);route=panel.find_child("DeliveryRouteSketch",true,false);guidance=panel.find_child("RiftRoutePreparation",true,false);var heading:Control=panel.find_child("RouteClearance",true,false)
 print("RIFT_WORKSHOP panel=",panel.get_global_rect()," diagram=",route.get_global_rect()," guidance=",guidance.get_global_rect())
 check(route.snapshot()==snapshot and guidance.text==Risk.guidance(order),"workshop and acceptance read identical frozen risk geometry")
 check(panel.size.y<=120 and visible_inside(route,panel) and visible_inside(guidance,panel) and visible_inside(heading,panel),"map and risk text fit existing 120 px workshop header")
 check(not panel.get_global_rect().intersects(hud.workshop_scene_rect()) and hud.content.find_child("DispatchActions",true,false)!=null,"risk view preserves usable grid and trial dispatch controls")
 data.mode="flight";data.flight=flight;hud.render(data);await settle()
 var bio:Control=hud.content.find_child("RiftBiologyPanel",true,false);var integrity:Control=hud.content.find_child("CargoIntegrityPanel",true,false)
 check(hud.flight_labels.integrity.text=="79%" and hud.flight_labels.integrity_status.text.contains("不合格") and hud.flight_labels.integrity_minimum.text=="最低 80%","79 percent and explicit rejection remain visible alongside biology")
 check(bio.is_visible_in_tree() and hud.flight_labels.biology.text.contains("9.5/2.5 s") and hud.flight_labels.biology_note.text.contains("正受冷损"),"unqualified flight no longer hides biological exposure")
 check(visible_inside(hud.flight_labels.biology,bio) and visible_inside(hud.flight_labels.biology_note,bio) and not bio.get_global_rect().intersects(integrity.get_global_rect()),"persistent biology lines fit separate compact panel without clipping health")
 var legend:Control=hud.content.find_child("RouteBoundaryLegend",true,false)
 check(legend.get_child(0).text.contains("货物中心") and legend.get_child(0).text.contains("刚体重心") and not legend.get_global_rect().intersects(bio.get_global_rect()),"flight legend distinguishes actual field sampling instead of describing rock walls")
 hud._update_free_flight(warm);await settle()
 check(hud.flight_labels.integrity.text=="79%" and hud.flight_labels.integrity_status.text.contains("不合格") and hud.flight_labels.biology.text.contains("当前不增冷损") and hud.flight_labels.biology_note.text.contains("不会自动修复"),"warm update preserves rejected HP and displays no new cold damage")
 data.mode="report";data.report=report;data.report_order=order;data.activeorder={};hud.render(data);await settle()
 var receipt:Label=hud.content.find_child("BiologicalDamageReceipt",true,false)
 check(receipt!=null and receipt.is_visible_in_tree() and receipt.text==Risk.report_copy(report,order) and hud._report_failure_copy(report)=="你结束了本次飞行。","trial report exposes measured cold damage without replacing actual terminal cause")
 report.trial=false;report.compensation=110;report.profit=-110;data.report=report;data.trial=false;hud.render(data);await settle()
 check(hud.content.find_child("BiologicalDamageReceipt",true,false).text.contains("21 HP"),"formal receipt uses same recorded cold HP")
 data.report=missing;hud.render(data);await settle()
 check(hud.content.find_child("BiologicalDamageReceipt",true,false)==null,"historical report without cold evidence stays unannotated")
 sketch.queue_free();hud.queue_free();await settle()
 print("RIFT_RISK_UI_DEV31 passed=%d failed=%d native_visual=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
