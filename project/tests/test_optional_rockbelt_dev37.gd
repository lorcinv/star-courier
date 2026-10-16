extends Node
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
const Layout=preload("res://scripts/delivery_route_layout_v1.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Econ=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle()->void:
 for frame in 5:await get_tree().process_frame
func inside(a:Control,b:Control)->bool:return a!=null and a.is_visible_in_tree() and b.get_global_rect().encloses(a.get_global_rect())
func run()->void:
 if OS.get_environment("SC_ROCKBELT_ISOLATED")!="1":get_tree().quit(2);return
 var route:Dictionary=Chapter.fresh_route(3,false,false,true)
 check(Chapter.route_error(route).is_empty() and route.hazards.size()==5,"new optional layout passes ordinary contract validators")
 check(route.reward==380 and route.min_delivery_integrity==.9 and not route.chapter_progression,"original fee/reward/integrity terms and nonprogression retained")
 check(Chapter.fresh_route(3).route_layout.id==Layout.FRAGILE_ID and Chapter.fresh_route(3,false).route_layout.id==Layout.FRAGILE_ID,"normal main and original repeat remain unchanged")
 check(Chapter.fresh_route(3,true,false,true).is_empty() and Chapter.fresh_route(3,false,true,true).is_empty(),"no progression or recovery rockbelt authoring")
 var snapshot:PackedByteArray=var_to_bytes(route)
 var preview:Dictionary=Layout.preview(route)
 check(preview.circles.size()==5 and preview.circles[2].position==Vector2(48,-10),"preview reads real five-rock order geometry")
 var hud=HUD.new();add_child(hud);get_tree().root.size=Vector2i(1280,814);hud.set_art_frame(Rect2(0,47,1280,720))
 route.contract_id="UI-BELT";route.status="available"
 var data:Dictionary={"mode":"contracts","control_version":route.control_version,"contracts":[route],"activeorder":{},"counter_customer_id":route.contract_id,"shop_action_availability":{"accept_contract":true},"settings":{"reduced_motion":true}}
 hud.render(data);await settle()
 var card:Control=hud.content.find_child("Waybill1",true,false);var scroll:Control=hud.content.find_child("ContractList",true,false);var heading:Label=card.find_child("RouteClearance",true,false);var accept:Button
 for b in card.find_children("*","Button",true,false):
  if b.get_meta("shop_contract_id","")==route.contract_id:accept=b
 check(inside(heading,scroll) and inside(accept,scroll),"actual choice explanation and accept visible before commitment")
 var sketch:Control=card.find_child("DeliveryRouteSketch",true,false)
 check(sketch.snapshot().circles.size()==5 and sketch.projected_geometry().paths.size()==3 and sketch.projected_geometry().paths[0].is_empty(),"diagram marks actual rocks and two bypasses, no promised safe straight corridor")
 data.mode="workshop";data.activeorder=route;data.parts=[];data.assembly_mode="craft";data.has_accepted_contract=true
 hud.render(data);await settle()
 var panel:Control=hud.content.find_child("WorkshopRouteSketch",true,false)
 var fit:bool=true
 for c in panel.find_children("*","Control",true,false):
  if c is Label or c.name=="DeliveryRouteSketch":fit=fit and inside(c,panel)
 check(fit and not panel.get_global_rect().intersects(hud.workshop_scene_rect()),"workshop rockbelt map/text fit above actual grid")
 print("BELT_UI panel=",panel.get_global_rect())
 hud.queue_free();await settle()
 # Unedited actual D3 native snapshot copied to isolated user dir. Normal
 # close/open boundaries author D4 then D5; this is Main economy, not a flight.
 var raw_bytes:PackedByteArray=FileAccess.get_file_as_bytes(OS.get_environment("SC_NATIVE_D3"));var raw:Dictionary=JSON.parse_string(raw_bytes.get_string_from_utf8())
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(raw_bytes);file.close()
 var e=Econ.new();e.load_state();e.enable_story_mode();check(not e.review_load_blocked,"actual native D3 save loads without migration")
 for day in [4,5]:
  check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"normal close/open day"+str(day))
 check(e.contracts[0].chapter_level==4 and e.contracts[0].chapter_progression and e.contracts[1].route_layout.id==Layout.ROCKBELT_ID,"level3 completion gates future D5B only; moon progression untouched")
 var shown:PackedByteArray=var_to_bytes(e.contracts);e.ensure_contracts();check(var_to_bytes(e.contracts)==shown,"shown batch cannot reroll")
 check(e.accept_contract_and_save("D5-B",raw.design,raw.launcher,raw.settings).ok,"optional quote accepted through ordinary save transaction")
 var accepted:String=JSON.stringify(e.active_contract(),"",true,true);var reopened=Econ.new();reopened.load_state();reopened.enable_story_mode()
 check(not reopened.review_load_blocked and JSON.parse_string(JSON.stringify(reopened.active_contract(),"",true,true))==JSON.parse_string(accepted),"accepted new layout reloads unchanged")
 check(FileAccess.get_file_as_bytes(OS.get_environment("SC_NATIVE_D3"))==raw_bytes,"original native save untouched")
 print("OPTIONAL_ROCKBELT_DEV37 passed=%d failed=%d model_economy_and_synthetic_ui=true native=NOT_RUN"%[passed,failed]);get_tree().quit(1 if failed else 0)
