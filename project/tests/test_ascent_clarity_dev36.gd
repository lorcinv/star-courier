extends Node
# Synthetic frozen-order display checks, not flight or novice evidence.
const UI=preload("res://scripts/delivery_ui_v3.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for frame in 5:await get_tree().process_frame
func inside(c:Control,p:Control)->bool:
 return c!=null and c.is_visible_in_tree() and p.get_global_rect().encloses(c.get_global_rect())
func run()->void:
 if OS.get_environment("SC_ASCENT_CLARITY_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 var order:Dictionary=Chapter.fresh_route(4,true,false);order.contract_id="UI-MOON";order.status="available"
 var frozen:PackedByteArray=var_to_bytes(order)
 check(UI.ascent_geometry_copy(order)=="水平间距 40 m · 目标离地 560 m","moon shows actual horizontal separation and altitude")
 var custom:Dictionary=order.duplicate(true);custom.distance=-75.0;custom.destination_y=-700.0;custom.background_ground_y_m=20.0
 check(UI.ascent_geometry_copy(custom)=="水平间距 75 m · 目标离地 720 m","geometry comes from frozen order, not chapter defaults or Euclidean length")
 for key in ["distance","destination_y","background_ground_y_m"]:
  var missing:Dictionary=order.duplicate(true);missing.erase(key)
  check(UI.ascent_geometry_copy(missing).is_empty(),"missing "+key+" is not invented")
  var bad:Dictionary=order.duplicate(true);bad[key]=NAN
  check(UI.ascent_geometry_copy(bad).is_empty(),"invalid "+key+" is not displayed")
 var legacy:Dictionary={"distance":40.0,"control_version":"pilot-free-v2"}
 check(UI.order_distance_copy(legacy)=="路程 40.0 m" and UI.ascent_geometry_copy(legacy).is_empty(),"historical non-ascent copy remains unchanged")
 var hud=HUD.new();add_child(hud);get_tree().root.size=Vector2i(1280,814);hud.set_art_frame(Rect2(0,47,1280,720))
 for progression in [true,false]:
  var route:Dictionary=Chapter.fresh_route(4,progression,false);route.contract_id="UI-MOON";route.status="available"
  var data:Dictionary={"mode":"contracts","control_version":route.control_version,"activeorder":{},"contracts":[route],"counter_customer_id":route.contract_id,"shop_action_availability":{"accept_contract":true},"settings":{"reduced_motion":true}}
  hud.render(data);await settle()
  var card:Control=hud.content.find_child("Waybill1",true,false)
  var scroll:Control=hud.content.find_child("ContractList",true,false)
  var heading:Label=card.find_child("RouteClearance",true,false);var accept:Button
  for button in card.find_children("*","Button",true,false):
   if button.get_meta("shop_contract_id","")==route.contract_id:accept=button
  check(heading!=null and heading.text.contains("目标离地 560 m") and heading.text.contains("持续推进"),"moon teaching visible before accepting, progression="+str(progression))
  check(inside(heading,scroll) and inside(accept,scroll) and not accept.disabled,"teaching and accept fully inside initial drawer")
  data.mode="workshop";data.activeorder=route;data.has_accepted_contract=true;data.assembly_mode="craft";data.parts=[]
  hud.render(data);await settle()
  var panel:Control=hud.content.find_child("WorkshopRouteSketch",true,false);heading=panel.find_child("RouteClearance",true,false)
  check(inside(heading,panel) and heading.text.contains("560 m"),"workshop includes full moon preparation")
  check(not panel.get_global_rect().intersects(hud.workshop_scene_rect()),"moon preparation does not cover assembly grid")
  print("MOON_UI progression=",progression," heading=",heading.get_global_rect()," panel=",panel.get_global_rect()," grid=",hud.workshop_scene_rect())
 check(var_to_bytes(order)==frozen,"presentation never mutates frozen contract")
 hud.queue_free();await settle()
 print("ASCENT_CLARITY_DEV36 passed=%d failed=%d synthetic_ui=true physics=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
