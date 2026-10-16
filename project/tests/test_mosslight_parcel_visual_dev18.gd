extends SceneTree
## Isolated headless renderer/lifecycle regression. D5 is a synthetic model
## setup; generation, acceptance and save/load use production APIs. No native
## player-input, completed delivery, or OS-visible image evidence is claimed.
const World=preload("res://scripts/world_view_2d.gd")
const Econ=preload("res://scripts/economy.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Caps=preload("res://scripts/recovery_presentation_caps.gd")
const SPOON_PATH:String="res://assets/2d_v5/mosslight/parcel-flowerpot-spoon.png"
const NEUTRAL_PATH:String="res://assets/2d_v5/npcs/shared/customer-parcel-neutral-pixel.png"
var passed:int=0
var failures:Array=[]
var phases:Dictionary={}
var completion_ids:Array=[]
var continuity_ok:bool=true
var watched_instance:int=0
var watched_texture:Texture2D
var watched_scale:Vector2
var watched_offset:Vector2
var watched_region:Rect2
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failures.append(label);push_error(label)
 return ok
func gate(route:Dictionary) -> String:
 var error:String=Econ.route_validation_error(route)
 return error if not error.is_empty() else Caps.route_error(route)
func fresh_model():
 var e=Econ.new();e.route_guard=gate;e.enable_force_mode()
 e.day=5;e.reputation=4;e.deliveries=4;e.credits=600
 e.story_state=Stories.initial_state(1801);e.enable_story_mode()
 e.starter_stock(Profile.starter_design(),Profile.starter_launcher())
 return e
func data_for(e,released:bool=false) -> Dictionary:
 return {"phase":e.phase,"day":e.day,"contracts":e.contracts.duplicate(true),"active_contract_id":e.active_contract_id,"handoff_released":released,"cargo_loaded":e.is_cargo_loaded()}
func new_world():
 var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 var w=World.new();viewport.add_child(w);w.set_process(false);w.assembly_feedback.set_process(false)
 w.show_design(Profile.starter_design());w.focus("hub",true)
 w.loading_complete.connect(func(cid:String):completion_ids.append(cid))
 return w
func dispose(w) -> void:
 var viewport=w.get_parent();w.free();viewport.free()
func cargo_sprite(w):
 for node in w.ship_root.get_children():
  if node is Sprite2D and bool(node.get_meta("is_cargo",false)):return node
 return null
func observe(w) -> void:
 var phase:String=w._parcel_phase
 if not phases.has(phase):phases[phase]={"texture":w.parcel.texture.resource_path if w.parcel.texture!=null else "","visible":w.parcel.visible,"position":str(w.parcel.position),"instance":w.parcel.get_instance_id()}
 continuity_ok=continuity_ok and w.parcel.get_instance_id()==watched_instance and w.parcel.texture==watched_texture and w.parcel.scale==watched_scale and w.parcel.offset==watched_offset and w.parcel.region_enabled and w.parcel.region_rect==watched_region
func step(w,seconds:float) -> void:
 for unused in ceili(seconds*120.0):
  var tween:Tween=w._parcel_tween
  if tween!=null and tween.is_valid() and w._focus_active and w.is_visible_in_tree():tween.pause();tween.custom_step(1.0/120.0)
  w._process(1.0/120.0);w.assembly_feedback._process(1.0/120.0)
  if w.parcel.get_instance_id()==watched_instance:observe(w)
func reach(w,phase:String) -> bool:
 for unused in 2400:
  if w._parcel_phase==phase:return true
  step(w,1.0/120.0)
 return check(false,"reached existing phase "+phase)
func watch(w) -> void:
 watched_instance=w.parcel.get_instance_id();watched_texture=w.parcel.texture;watched_scale=w.parcel.scale;watched_offset=w.parcel.offset;watched_region=w.parcel.region_rect
 phases={};continuity_ok=true;observe(w)
func save_model(e) -> bool:
 return e.save_state(Profile.starter_design(),Profile.starter_launcher(),{"volume":0.0,"reduced_motion":false})
func restored_model():
 var e=Econ.new();e.route_guard=gate;e.load_state(true);return e
func reject(w,order:Dictionary,label:String) -> void:
 var before:String=JSON.stringify(order);w._configure_parcel_presentation(order)
 check(Stories.parcel_presentation_id(order).is_empty() and w.parcel.texture!=null and w.parcel.texture.resource_path==NEUTRAL_PATH,label+" keeps neutral art")
 check(JSON.stringify(order)==before,label+" remains read-only")
func visible_bounds(image:Image) -> Rect2i:
 var low:=Vector2i(image.get_width(),image.get_height());var high:=Vector2i(-1,-1)
 for y in image.get_height():
  for x in image.get_width():
   if image.get_pixel(x,y).a<16.0/255.0:continue
   low.x=mini(low.x,x);low.y=mini(low.y,y);high.x=maxi(high.x,x);high.y=maxi(high.y,y)
 return Rect2i(low,high-low+Vector2i.ONE)
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json"):
  printerr("Use a fresh isolated HOME/XDG_DATA_HOME; this test never deletes existing saves.");quit(2);return
 var e=fresh_model();var order:Dictionary=e.contract_by_id("D5-A").duplicate(true)
 if not check(Stories.parcel_presentation_id(order)==Stories.MOSSLIGHT_SPOON_PARCEL,"production empty-batch authoring selects only new D5-A mosslight/human parcel"):
  finish();return
 var w=new_world();var neutral_scale:Vector2=w.parcel.scale;var neutral_texture:Texture2D=w.parcel.texture
 var cargo=cargo_sprite(w);var cargo_instance:int=cargo.get_instance_id();var cargo_texture:Texture2D=cargo.texture
 w._configure_parcel_presentation(order)
 if not check(w.parcel.texture!=null and w.parcel.texture.resource_path==SPOON_PATH,"validated authored marker selects actual spoon PNG"):
  dispose(w);finish();return
 check(w.parcel.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and is_equal_approx(w.parcel.scale.x,w.parcel.scale.y),"spoon uses nearest-filtered uniform scale")
 var spoon_image:Image=w.parcel.texture.get_image();var bounds:Rect2i=visible_bounds(spoon_image)
 var visible_center:Vector2=(Vector2(bounds.position)+Vector2(bounds.size)*.5-w.parcel.region_rect.get_center()+w.parcel.offset)*w.parcel.scale
 check(w.parcel.region_enabled and w.parcel.region_rect.encloses(Rect2(bounds)),"registered safe region encloses all visible tray pixels")
 check(visible_center.length()<=.75,"visible tray center stays at existing customer/clerk/robot grip anchor")
 check(absf(float(bounds.size.x)*w.parcel.scale.x-World.MOSSLIGHT_SPOON_PARCEL_WIDTH)<=1.0,"tray uses calibrated 52-pixel visible width")
 check(float(bounds.size.x)/float(maxi(1,bounds.size.y))>=2.5,"actual tray silhouette is narrower than old square box")
 var legacy:Dictionary=order.duplicate(true);legacy.erase("parcel_presentation_id");reject(w,legacy,"old unmarked mosslight order")
 check(w.parcel.texture==neutral_texture and w.parcel.scale==neutral_scale and w.parcel.offset==Vector2.ZERO and not w.parcel.region_enabled,"old box keeps exact original resource and geometry")
 for key in ["parcel_presentation_id","control_version","id","appearance_id","species","story_id","route_profile","route_kind","destination_id"]:
  var wrong:Dictionary=order.duplicate(true);wrong[key]="unsupported";reject(w,wrong,"wrong "+key)
 var missing:Dictionary=order.duplicate(true);missing.erase("story_id");reject(w,missing,"missing story")
 for pair in [["elf_archivist","elf"],["alien_botanist","alien"],["robot_machinist","robot"]]:
  var other:Dictionary=order.duplicate(true);other.appearance_id=pair[0];other.species=pair[1];reject(w,other,"nonhuman "+str(pair[0]))
 check(e.accept_contract("D5-A").ok,"production model accepts generated D5-A without injected marker")
 var data:Dictionary=data_for(e);var original:String=JSON.stringify(data)
 w.update_shop_state(data);step(w,3.0);watch(w)
 check(w.parcel.visible and not w.customers["D5-A"].node.pose_contains_parcel(),"accepted empty-hand human shows exactly one external spoon parcel")
 check(w.parcel.position.distance_to(w._customer_parcel_point("D5-A"))<.001,"accept uses existing registered customer anchor")
 check(w.begin_loading("D5-A"),"existing handoff/loading API accepts same parcel")
 if not reach(w,"robot_carry"):dispose(w);finish();return
 var generation:int=w._parcel_generation;var position:Vector2=w.parcel.position;var age:float=w._transport_age
 w.set_focus_active(false);step(w,.5)
 check(w.parcel.position==position and w._transport_age==age and w.parcel.texture==watched_texture,"focus pause preserves carried spoon without elapsed catch-up")
 w.hide();w.set_focus_active(true);step(w,.5)
 check(w.parcel.position==position and w._transport_age==age,"hidden scene preserves carried spoon")
 w.show();observe(w)
 check(w.parcel.texture==watched_texture and w.parcel.get_instance_id()==watched_instance,"resume keeps same parcel resource and instance")
 var refresh:Dictionary=data.duplicate(true);refresh.contracts[0].erase("parcel_presentation_id");w.update_shop_state(refresh)
 check(w.parcel.texture==watched_texture and w._parcel_generation==generation,"same-order refresh cannot swap a parcel during carry")
 check(e.mark_story_seen("D5-A","D5-A/accept") and save_model(e),"accepted unfinished real model snapshot saves through normal ledger")
 var reloaded=restored_model();var continued=new_world();continued.update_shop_state(data_for(reloaded,true))
 check(not reloaded.review_load_blocked and continued.parcel.texture==watched_texture and continued.is_loading(),"accepted save reload selects same spoon and resumes existing loading flow")
 continued.fastforward_loading("D5-A");check(continued.is_parcel_loaded() and not continued.parcel.visible,"continued skip settles single parcel at unchanged module boundary");dispose(continued)
 completion_ids.clear()
 if not reach(w,"loaded"):dispose(w);finish();return
 for phase in ["waiting_customer","customer_handoff","counter_transfer","clerk_handoff","robot_fetch","robot_pickup","robot_turn","clerk_round_counter","clerk_join","robot_carry","robot_insert","clerk_align","clerk_confirm","loaded"]:
  check(phases.has(phase),"same parcel traverses "+phase)
 check(continuity_ok,"all handoff/carry/insert samples preserve the same instance, texture, scale and anchor")
 check(not w.parcel.visible and cargo.visible and cargo.get_instance_id()==cargo_instance and cargo.texture==cargo_texture,"loaded spoon hides; original physical cargo module is revealed unchanged")
 check(completion_ids==["D5-A"],"normal completion emits exactly one current-order event")
 w.fastforward_loading("D5-A");w._complete_loading("D5-A",generation)
 check(completion_ids==["D5-A"] and JSON.stringify(data)==original,"repeated completion does not duplicate event or mutate caller contract")
 check(e.mark_cargo_loaded("D5-A").ok and save_model(e),"loaded accepted model saves normally")
 var loaded_model=restored_model();var loaded_world=new_world();loaded_world.update_shop_state(data_for(loaded_model,true))
 check(loaded_world.is_parcel_loaded() and not loaded_world.parcel.visible and loaded_world.parcel.texture==watched_texture,"loaded continue restores spoon identity without replaying handoff")
 check(cargo_sprite(loaded_world).texture==cargo_texture and cargo_sprite(loaded_world).visible,"loaded continue retains original physical cargo art");dispose(loaded_world)
 # Cancel during a fresh actual generated order's loading, then replace with
 # an old unmarked snapshot. All fixtures below remain synthetic source tests.
 var next_model=fresh_model();next_model.accept_contract("D5-A")
 var abort_world=new_world();abort_world.update_shop_state(data_for(next_model));step(abort_world,3.0);abort_world.begin_loading("D5-A")
 if not reach(abort_world,"robot_insert"):dispose(abort_world);dispose(w);finish();return
 var stale_generation:int=abort_world._parcel_generation;var stale_instance:int=abort_world.parcel.get_instance_id()
 check(next_model.cancel_accepted().ok,"production cancel ends accepted loading order")
 abort_world.update_shop_state(data_for(next_model));abort_world._complete_loading("D5-A",stale_generation);abort_world._receive_counter_parcel("D5-A",stale_generation)
 check(abort_world.active_id.is_empty() and not abort_world.parcel.visible and abort_world.parcel.texture==neutral_texture and abort_world.parcel.scale==neutral_scale and abort_world.parcel.offset==Vector2.ZERO and not abort_world.parcel.region_enabled,"cancel cleans marker/art/geometry; stale callbacks cannot revive spoon")
 legacy.contract_id="legacy-replacement";legacy.status="accepted"
 var replacement:Dictionary={"phase":"day","active_contract_id":legacy.contract_id,"handoff_released":false,"contracts":[legacy]}
 abort_world.update_shop_state(replacement)
 check(abort_world.parcel.get_instance_id()==stale_instance and abort_world.parcel.texture==neutral_texture and str(abort_world.parcel.get_meta("parcel_presentation_id","x")).is_empty(),"old replacement reuses one neutral parcel without inherited marker")
 check(abort_world.customers.size()==1 and not abort_world.customers.has("D5-A"),"replacement removes obsolete customer ownership")
 dispose(abort_world);dispose(w);finish()
func finish() -> void:
 var result:Dictionary={"passed":passed,"failures":failures,"phases":phases,"native_input":false,"completed_delivery":false,"scope":"Isolated headless source-level renderer/lifecycle regression; D5 prior state is a synthetic fixture. Real generation, acceptance and normal save/load APIs are exercised; not native visual acceptance."}
 var out=FileAccess.open("user://mosslight-parcel-visual-results.json",FileAccess.WRITE)
 if out!=null:out.store_string(JSON.stringify(result," "))
 print("MOSSLIGHT_PARCEL_VISUAL_DEV18 passed=",passed," failed=",failures.size()," native_input=false");quit(1 if not failures.is_empty() else 0)
