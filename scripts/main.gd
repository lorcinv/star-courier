extends Node3D
const PartsDB=preload("res://scripts/parts_expanded.gd")
const Simulator=preload("res://scripts/simulation.gd")
const PilotSimulator=preload("res://scripts/pilot_simulation.gd")
const PilotProfile=preload("res://scripts/pilot_profile.gd")
const AscentSimulator=preload("res://scripts/pilot_ascent_simulation.gd")
const AscentProfile=preload("res://scripts/pilot_ascent_profile.gd")
const ExtremeSimulator=preload("res://scripts/pilot_extreme_simulation.gd")
const ExtremeProfile=preload("res://scripts/pilot_extreme_profile.gd")
const PILOT_VERSIONS:Array=[PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION]
const ASCENT_VERSIONS:Array=[AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION]
const PilotTimeline=preload("res://scripts/pilot_timeline.gd")
const EconomyDB=preload("res://scripts/economy.gd")
const WorldView=preload("res://scripts/world_view_2d.gd")
const GameHUD=preload("res://scripts/game_hud.gd")
const PixelStage=preload("res://scripts/pixel_stage.gd")
const DialoguePanel=preload("res://scripts/dialogue_panel.gd")
const LoadingSceneOverlay=preload("res://scripts/loading_scene_overlay.gd")
const CourierInput=preload("res://scripts/courier_input.gd")
const WorkshopInput=preload("res://scripts/workshop_input_2d.gd")
const WorkshopProfile=preload("res://scripts/workshop_profile.gd")
var courier_input
var _shop_navigation_arriving:bool=false
var economy=EconomyDB.new()
var catalog:Dictionary={}
var design:Array=[]
var launcher:Array=[]
var chosen_type:String="beam"
var selected_id:int=-1
var next_id:int=20
var page:String="hub"
var assembly_mode:String="craft"
var sim=null
var trial:bool=false
var speed:float=1.0
var paused:bool=false
var frame_accum:float=0.0
var checkpoint:float=0.0
var launch_countdown:float=0.0
var completion_countdown:float=-1.0
var launch_age:float=0.0
var launch_transfer_remaining:float=0.0
var slow_simulation:bool=false
var launch_sfx_played:bool=false
var settings:Dictionary={"volume":0.55,"dialogue_volume":0.55,"dialogue_muted":false,"fullscreen":false,"reduced_motion":false,"motion_blur":true,"quality":"auto","pixel_density":"auto","controller_deadzone":.22}
var world
var hud
var view:SubViewport
var view_container:Control
var music:AudioStreamPlayer
var sfx:AudioStreamPlayer
var undo_history:Array=[]
var report:Dictionary={}
var flight_order:Dictionary={}
var closing:bool=false
var quality_profile:String="standard"
var software_renderer:bool=false
var pilot_timeline=PilotTimeline.new()
var pilot_completed_ticks:int=0
var pilot_keys:Dictionary={}
var pilot_resume_blocked:bool=false
var _flight_modal_was_open:bool=false
var _paused_before_modal:bool=false
var dialogue
var loading_overlay
var _pending_story:Dictionary={}
var _active_story:Dictionary={}
var _story_save_attempted:bool=false
var _finalizing_cargo_for_launch:bool=false
var workshop_input=WorkshopInput.new()

func _ready() -> void:
 get_tree().auto_accept_quit=false
 # Pixel stage uses actual window pixels, while Chinese UI stays readable.
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 get_window().content_scale_size=Vector2i.ZERO
 get_window().min_size=Vector2i(1280,720)
 get_window().focus_exited.connect(_on_focus_exited)
 get_window().focus_entered.connect(_on_focus_entered)
 get_window().close_requested.connect(_quit_cleanly)
 catalog=PartsDB.catalog();catalog.cargo=PartsDB.cargo_spec();_starter()
 var loaded=economy.load_state()
 if not loaded.is_empty():
  design=loaded.get("design",design);launcher=loaded.get("launcher",launcher);settings.merge(loaded.get("settings",{}),true)
 else:economy.enable_extreme_mode();economy.starter_stock(design,launcher)
 economy.enable_extreme_mode()
 economy.enable_story_mode()
 _validate_designs();_allocate_ids()
 if bool(settings.fullscreen):DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 _build_ui();_apply_quality()
 music=AudioStreamPlayer.new();add_child(music);sfx=AudioStreamPlayer.new();add_child(sfx)
 render();_play_music(false)
 var load_message:String=economy.load_notice
 if _outside_workshop_count(design)+_outside_workshop_count(launcher)>0:
  load_message+=("\n" if not load_message.is_empty() else "")+"旧方案的超出工位部分已保留。可以移回开放格，或收工后扩建。"
 if not load_message.is_empty():notify(load_message)
 if not economy.in_flight.is_empty():_resume_dispatch.call_deferred()
 elif save_game():_restore_story_dialogue.call_deferred()
 if "--smoke-test" in OS.get_cmdline_user_args():_smoke_test.call_deferred()
 if "--visual-test" in OS.get_cmdline_user_args():_visual_test.call_deferred()

func _starter() -> void:
 design=ExtremeProfile.starter_design();launcher=ExtremeProfile.starter_launcher()

func part(id:int,type:String,x:int,y:int) -> Dictionary:
 return {"id":id,"type":type,"x":x,"y":y,"rot":0,"param":PartsDB.defaults(type),"input_a":-1,"input_b":-1,"target":-1}

func _allocate_ids() -> void:
 for p in design+launcher:next_id=maxi(next_id,int(p.id)+1)

func _validate_designs() -> void:
 var ids:Dictionary={}
 for items in [design,launcher]:
  var occupied:Dictionary={}
  for i in range(items.size()-1,-1,-1):
   var p=items[i]
   if not p is Dictionary or not catalog.has(str(p.get("type",""))):items.remove_at(i);continue
   var cell=Vector2i(int(p.get("x",0)),int(p.get("y",0)))
   # Paid-tier bounds govern NEW targets. Never silently crop a retained design
   # while loading a legacy save or blueprint into a smaller workshop.
   if occupied.has(cell):items.remove_at(i);continue
   occupied[cell]=true
   var id=int(p.get("id",-1))
   if id<0 or ids.has(id):id=next_id;next_id+=1
   p.id=id;ids[id]=true;p.x=cell.x;p.y=cell.y;p.rot=posmod(int(p.get("rot",0)),4);p.param=PartsDB.sanitize_parameter(str(p.type),float(p.get("param",0)))
  var local_ids:Array=items.map(func(p):return int(p.id))
  for p in items:
   for key in ["input_a","input_b","target"]:
    if key!="target" and int(p.get(key,-1))==PilotProfile.COCKPIT_SIGNAL and economy.flight_mode in PILOT_VERSIONS:continue
    if not int(p.get(key,-1)) in local_ids:p[key]=-1

func _outside_workshop_count(items:Array) -> int:
 var count:int=0
 for p in items:
  if not WorkshopProfile.contains_cell(economy.workshop_tier,Vector2i(int(p.x),int(p.y))):count+=1
 return count

func _build_ui() -> void:
 var layer=CanvasLayer.new();layer.layer=0;add_child(layer)
 view_container=PixelStage.new();layer.add_child(view_container);view_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 view=view_container.viewport
 world=WorldView.new();world.catalog=catalog;world.screen_mapper=view_container;view.add_child(world)
 world.loading_complete.connect(_on_cargo_loading_complete)
 if world.has_signal("shop_navigation_arrived"):world.shop_navigation_arrived.connect(_on_shop_navigation_arrived)
 view_container.display.gui_input.connect(_viewport_input)
 hud=GameHUD.new();add_child(hud);hud.action_requested.connect(_action)
 dialogue=DialoguePanel.new();add_child(dialogue)
 dialogue.finished.connect(_on_dialogue_finished)
 dialogue.modal_changed.connect(_on_dialogue_modal_changed)
 dialogue.audio_settings_changed.connect(_on_dialogue_audio_settings)
 loading_overlay=LoadingSceneOverlay.new();add_child(loading_overlay)
 loading_overlay.skip_requested.connect(_skip_loading_scene)
 view_container.art_frame_changed.connect(_on_art_frame_changed)
 workshop_input.bind(self)
 _on_art_frame_changed(view_container.display_rect)
 courier_input=CourierInput.new();add_child(courier_input);courier_input.bind(self)

func _on_art_frame_changed(rect:Rect2) -> void:
 workshop_input.cancel()
 if is_instance_valid(loading_overlay):loading_overlay.set_art_frame(rect)
 if is_instance_valid(hud) and hud.has_method("set_art_frame"):
  hud.set_art_frame(rect)
  if not hud.state.is_empty():hud.render(hud.state)
 if workshop_input.host!=null:workshop_input.after_render()

func active_design() -> Array:return design if assembly_mode=="craft" else launcher
func selected_part() -> Dictionary:
 for p in active_design():
  if int(p.id)==selected_id:return p
 return {}
func _installed_count(type:String) -> int:
 return (design+launcher).filter(func(p):return str(p.type)==type).size()

func render() -> void:
 world.set_workshop_tier(economy.workshop_tier)
 world.reduced_motion=bool(settings.get("reduced_motion",false))
 world.motion_blur_enabled=bool(settings.get("motion_blur",true))
 var order=economy.active_contract().duplicate(true)
 if page=="flight":order=flight_order.duplicate(true)
 if not order.is_empty():order.accepted=order.get("status","")=="accepted"
 var specs:Dictionary={};var stock:Dictionary={}
 var capacity_scale:float=AscentProfile.BATTERY_MULTIPLIER if economy.flight_mode in ASCENT_VERSIONS else 1.0
 for type in catalog:
  if type=="cargo":continue
  specs[type]=catalog[type].duplicate(true);specs[type].launcher_compatible=type in PartsDB.launcher_types()
  if type=="battery":specs[type].energy=float(specs[type].energy)*capacity_scale
  if type=="shield" and economy.flight_mode==ExtremeProfile.CONTROL_VERSION:specs[type].description="可防御攻击，也可吸收最多 65% 撞击损伤。每个护盾每步最多吸收 24 HP，每 HP 消耗 1.5 J；撞击动量仍会传入结构。"
  stock[type]=int(economy.inventory.get(type,0))-_installed_count(type) if page=="workshop" else int(economy.inventory.get(type,0))
 var chosen=selected_part().duplicate(true)
 if not chosen.is_empty():
  chosen.spec=specs.get(chosen.type,catalog[chosen.type]);chosen.schema=PartsDB.parameter_schema(chosen.type);chosen.controls=PartsDB.controls(chosen.type);chosen.default_behavior=chosen.controls.default_behavior
  if chosen.type=="shield" and economy.flight_mode==ExtremeProfile.CONTROL_VERSION:chosen.default_behavior="未接线自动保护同一存活结构；撞击吸收需要实际余电，不会阻止翻转或结构过载。"
  if chosen.type=="battery" and capacity_scale>1:
   var capacity:float=float(catalog.battery.energy)*capacity_scale*(1.0+.15*economy.research)
   chosen.default_behavior="电芯容量 %.0f J；向同一结构供电。"%capacity
 var mass:float=0;var energy:float=0
 for p in active_design():
  mass+=float(catalog[p.type].get("mass",0))*(float(order.get("weight",1)) if p.type=="cargo" else 1.0)
  if p.type=="battery":energy+=float(catalog[p.type].get("energy",0))*capacity_scale*(1.0+.15*economy.research)
 var hint="柜台前有客人。先听听他们要寄什么，再接下适合今天的一单。"
 if not order.is_empty():hint="委托已确认。去工位装好货，免费试飞之后再正式配送。"
 if economy.phase=="night":hint="收工了。用今天的回信和试飞记录，决定明天最需要哪件零件。"
 if economy.jobs_today>0 and order.is_empty():hint="回信已经到了。还可以接下一位客人，或者收工准备明天。"
 if page!="flight":
  world.leave_flight();world.focus(page);world.show_design(active_design() if page=="workshop" else design,selected_id if page=="workshop" else -1)
  world.update_shop_state({"phase":economy.phase,"day":economy.day,"contracts":economy.contracts,"active_contract_id":economy.active_contract_id,"research":economy.research,"inventory":economy.inventory,"installed":design+launcher,"cargo_loaded":economy.is_cargo_loaded(),"handoff_released":_cargo_handoff_released()})
 var data={"mode":page,"day":economy.day,"credits":economy.credits,"reputation":economy.reputation,"phase":economy.phase,"hint":hint,"activeorder":order,"contracts":economy.available_contracts(),"catalog":specs,"inventory":stock,"chosen_type":chosen_type,"assembly_mode":assembly_mode,"selectedpart":chosen,"parts":active_design(),"ship_stats":{"parts":active_design().size(),"mass":mass,"energy":energy},"settings":settings,"trial":trial,"report":report,"hotspots":world.hotspot_positions(),"cancel_warning":"退回已接委托会失去 1 点声望；这份委托今天不会重新出现。","upgrades":[{"id":"battery","name":"校准充电台 · 储能 +15%","cost":economy.research_cost(),"disabled":economy.research>=3 or economy.credits<economy.research_cost()}]}
 var next_tier:int=WorkshopProfile.next_tier(economy.workshop_tier)
 data.workshop={"tier":economy.workshop_tier,"size":WorkshopProfile.grid_size(economy.workshop_tier),"next_tier":next_tier,"next_size":WorkshopProfile.grid_size(next_tier),"cost":economy.workshop_upgrade_cost()}
 var outside:int=_outside_workshop_count(active_design())
 if outside>0:data.ship_stats.warning="已保留 %d 个旧方案格。移回开放区，或收工后扩建。"%outside
 data.control_version=str(flight_order.get("control_version","")) if page=="flight" else economy.flight_mode
 data.energy_tariff=economy.energy_tariff(order if not order.is_empty() else {"control_version":economy.flight_mode})
 hud.render(data)
 _sync_loading_scene_ui()
 workshop_input.after_render()

func _action(action:String,payload:Variant) -> void:
 workshop_input.cancel()
 if _dialogue_is_open():return
 if action=="skip_loading_scene":_skip_loading_scene();return
 if _loading_scene_active() and not action in ["cancel_contract","settings"]:return
 if action in ["focus_counter","next_contract"] and not _shop_navigation_arriving and world.has_method("request_shop_navigation"):
  if page!="hub":navigate("hub")
  if is_instance_valid(courier_input):courier_input._hub_ui=false;courier_input.synchronize()
  if not world.request_shop_navigation("focus_counter"):return
 if action=="accept_contract" and world.has_method("is_at_shop_counter"):
  if not world.is_at_shop_counter():navigate("hub");world.request_shop_navigation("focus_counter");return
 _sound("ui_select")
 match action:
  "focus_counter","next_contract":navigate("contracts")
  "focus_workbench":
   if page=="report" and report.has("incident_id"):selected_id=int(report.incident_id);assembly_mode="craft"
   navigate("workshop")
   if _cargo_handoff_released():world.pack_parcel()
  "focus_supply":navigate("supply")
  "focus_launch":navigate("workshop");notify("先试飞检查，再点击正式配送。")
  "close_drawer":navigate("hub")
  "help":navigate("help")
  "accept_contract":
   var result=economy.accept_contract(str(payload))
   if _result_ok(result):
    save_game();navigate("hub");_request_story(str(payload),"accept")
  "decline_contract":
   if _result_ok(economy.decline_available(str(payload))):save_game();render()
  "cancel_contract":
   if _result_ok(economy.cancel_accepted()):save_game();navigate("hub")
  "select_catalog":chosen_type=str(payload);selected_id=-1;render()
  "assembly_mode":assembly_mode=str(payload);selected_id=-1;render()
  "fit_workshop":workshop_input.fit()
  "undo":undo_assembly()
  "rotate_part":rotate_part()
  "remove_part":remove_part()
  "set_param":
   var p=selected_part()
   if not p.is_empty():_remember_assembly();p.param=PartsDB.sanitize_parameter(p.type,float(payload.value));save_game();world.committed_edit("tune",p)
  "set_input":
   var p=selected_part()
   if not p.is_empty():_remember_assembly();p[str(payload.key)]=int(payload.source);world.show_design(active_design(),selected_id);save_game();world.committed_edit("tune",p)
  "save_blueprint":save_blueprint()
  "load_blueprint":load_blueprint()
  "trial","trial_retry":start_flight(true)
  "dispatch":start_flight(false)
  "pause":_set_paused(not paused)
  "set_speed":speed=1.0 if _is_pilot_flight() else clampf(float(payload),1,4)
  "abort":abort_flight()
  "close_day","finish_day":
   if _result_ok(economy.close_day()):save_game();navigate("supply")
  "next_day":
   if _result_ok(economy.next_day()):save_game();navigate("hub")
  "buy":
   if catalog.has(str(payload)) and _result_ok(economy.buy_part(str(payload),catalog[str(payload)])):save_game();render();notify("零件已放到货架上。")
  "upgrade":
   if _result_ok(economy.research_upgrade()):save_game();render()
  "workshop_upgrade":
   var result:Dictionary=economy.workshop_upgrade(int(payload))
   if not bool(result.get("ok",false)):notify(str(result.get("message","扩建未完成。")));return
   # The paid tier becomes visible only after its atomic save succeeds. A stale
   # click carries the exact quoted target, so it cannot buy the following tier.
   if not save_game():
    economy.workshop_tier=int(result.previous_tier);economy.credits=int(result.previous_credits);render();return
   render();notify(str(result.message))
  "settings":
   if payload.get("toggle_fullscreen",false):toggle_fullscreen()
   elif payload.has("quality"):settings.quality=str(payload.quality);_apply_quality();save_game()
   elif payload.has("pixel_density"):settings.pixel_density=str(payload.pixel_density);_apply_quality();save_game()
   elif payload.has("reduced_motion"):settings.reduced_motion=bool(payload.reduced_motion);world.reduced_motion=settings.reduced_motion;save_game()
   elif payload.has("motion_blur"):settings.motion_blur=bool(payload.motion_blur);world.motion_blur_enabled=settings.motion_blur;save_game()
   elif payload.has("controller_deadzone"):settings.controller_deadzone=clampf(float(payload.controller_deadzone),.10,.45);save_game()
   elif payload.has("volume"):settings.volume=payload.volume;music.volume_db=linear_to_db(maxf(float(settings.volume),.001))-5;save_game()

func _on_shop_navigation_arrived(action_id:String) -> void:
 if page!="hub" or _dialogue_is_open() or _loading_scene_active() or hud.is_blocking_modal():return
 _shop_navigation_arriving=true;_action(action_id,null);_shop_navigation_arriving=false

func _result_ok(result:Dictionary) -> bool:
 if result.has("message"):notify(str(result.message))
 return bool(result.get("ok",false))
func notify(message:String) -> void:if is_instance_valid(hud):hud.toast(message)
func navigate(target:String) -> void:
 workshop_input.cancel()
 if world.has_method("cancel_shop_navigation"):world.cancel_shop_navigation()
 if page=="flight":return
 page=target;render()
 if target=="hub":_restore_story_dialogue.call_deferred()

func _dialogue_is_open() -> bool:
 return is_instance_valid(dialogue) and dialogue.is_open()

func _loading_scene_active() -> bool:
 if closing or page=="flight" or _dialogue_is_open() or not is_instance_valid(world):return false
 if world.has_method("is_loading_scene"):return bool(world.is_loading_scene())
 return bool(world.is_loading()) if world.has_method("is_loading") else false

func _sync_loading_scene_ui() -> void:
 if not is_instance_valid(loading_overlay):return
 var active:bool=_loading_scene_active()
 if active:
  workshop_input.cancel()
  loading_overlay.update_state(world.loading_snapshot())
 else:loading_overlay.close()
 if is_instance_valid(hud):hud.visible=not active

func _skip_loading_scene(order_id:String="") -> void:
 if not _loading_scene_active() or not world._focus_active:return
 var current:String=economy.active_contract_id
 if current.is_empty() or (not order_id.is_empty() and order_id!=current):return
 world.fastforward_loading(current)
 _sync_loading_scene_ui()

func _finish_loading_scene(order_id:String,message:String="") -> void:
 # Deferred because reduced-motion completion can happen inside render().
 # A stale completion cannot navigate a new customer's scene or a live flight.
 if closing or page=="flight" or economy.active_contract_id!=order_id:return
 if not world.is_parcel_loaded(order_id):return
 _sync_loading_scene_ui()
 assembly_mode="craft";navigate("workshop")
 if not message.is_empty():notify(message)

func _request_story(contract_id:String,beat:String) -> void:
 if contract_id.is_empty() or economy.story_conversation(contract_id,beat).is_empty():return
 _pending_story={"contract_id":contract_id,"beat":beat};_story_save_attempted=false
 _try_pending_story()

func _try_pending_story() -> void:
 if _pending_story.is_empty() or _dialogue_is_open() or _loading_scene_active() or page=="flight" or pilot_resume_blocked or closing:return
 if is_instance_valid(hud) and hud.is_blocking_modal():return
 var cid:String=str(_pending_story.contract_id);var beat:String=str(_pending_story.beat)
 if beat=="accept" and (economy.active_contract_id!=cid or str(economy.active_contract().get("status",""))!="accepted"):
  _pending_story.clear();return
 var conversation:Dictionary=economy.story_conversation(cid,beat)
 if conversation.is_empty():_pending_story.clear();return
 if world.has_method("prepare_counter_interaction") and not world.prepare_counter_interaction():return
 # A story is presented only after the matching identity and paid result are
 # durable. A failed disk write is attempted once, not every rendered frame.
 if _story_save_attempted:return
 _story_save_attempted=true
 if not save_game():return
 _clear_pilot_input()
 _active_story={"contract_id":cid,"dialogue_id":str(conversation.dialogue_id),"beat":beat}
 if dialogue.begin(conversation,economy.story_actor(cid),settings):_pending_story.clear()
 else:_active_story.clear()

func _restore_story_dialogue() -> void:
 if page=="flight" or _dialogue_is_open() or pilot_resume_blocked or closing:return
 var active:Dictionary=economy.active_contract()
 if str(active.get("status",""))=="accepted":
  var cid:String=str(active.contract_id)
  if not economy.story_conversation(cid,"accept").is_empty():_request_story(cid,"accept");return
 var settled_id:String=str(economy.last_settlement.get("contract_id",""))
 if not settled_id.is_empty() and not economy.story_conversation(settled_id,"result").is_empty():
  _request_story(settled_id,"result");return
 if page=="hub":
  var pending:Array=economy.pending_story_returns()
  if not pending.is_empty():_request_story(str(pending[0].contract_id),"return")

func _on_dialogue_finished(dialogue_id:String,_skipped:bool) -> void:
 if _active_story.is_empty() or str(_active_story.dialogue_id)!=dialogue_id:return
 var completed:Dictionary=_active_story.duplicate(true);_active_story.clear()
 var previous:Dictionary=economy.story_state.duplicate(true)
 if economy.mark_story_seen(str(completed.contract_id),dialogue_id) and not save_game():
  economy.story_state=previous;return
 if str(completed.beat)=="accept" and economy.active_contract_id==str(completed.contract_id):
  render()

func _cargo_handoff_released() -> bool:
 var order:Dictionary=economy.active_contract()
 if order.is_empty() or str(order.get("status",""))!="accepted":return false
 return not economy.story_mode or economy.story_conversation(str(order.contract_id),"accept").is_empty()

func _commit_cargo_loading(contract_id:String) -> bool:
 var order:Dictionary=economy.active_contract()
 if order.is_empty() or str(order.get("contract_id",""))!=contract_id or str(order.get("status",""))!="accepted":return false
 if economy.is_cargo_loaded(contract_id):return true
 if not economy.mark_cargo_loaded(contract_id).get("ok",false):return false
 if save_game():return true
 # The renderer may already be visually settled. Keep the durable model false
 # so another explicit launch can retry saving, never dispatch on a failed save.
 order.cargo_loaded=false
 return false

func _on_cargo_loading_complete(contract_id:String) -> void:
 if _finalizing_cargo_for_launch or closing or not _cargo_handoff_released():return
 if economy.is_cargo_loaded(contract_id):return
 if world.active_id!=contract_id or not world.is_parcel_loaded(contract_id):return
 var message:String="货物已装入货舱。"
 if not _commit_cargo_loading(contract_id):message=economy.save_error+" 请重试保存后再发射。"
 _finish_loading_scene.call_deferred(contract_id,message)

func _ensure_cargo_loaded_for_launch() -> bool:
 if not economy.story_mode:return true
 var order:Dictionary=economy.active_contract();var cid:String=str(order.get("contract_id",""))
 if not _cargo_handoff_released():
  _request_story(cid,"accept");return false
 if world.active_id!=cid:render()
 _finalizing_cargo_for_launch=true
 world.fastforward_loading(cid)
 _finalizing_cargo_for_launch=false
 if not world.is_parcel_loaded(cid):return false
 return _commit_cargo_loading(cid)

func _on_dialogue_modal_changed(open:bool) -> void:
 if open:_clear_pilot_input();workshop_input.cancel()

func _on_dialogue_audio_settings(volume:float,muted:bool) -> void:
 settings.dialogue_volume=clampf(volume,0.0,1.0);settings.dialogue_muted=muted;save_game()

func _viewport_input(event:InputEvent) -> void:
 workshop_input.handle(event)
func rotate_part() -> void:
 workshop_input.cancel()
 if _loading_scene_active():return
 var p=selected_part()
 if not p.is_empty():_remember_assembly();p.rot=(int(p.rot)+1)%4;render();save_game();world.committed_edit("rotate",p)
func remove_part() -> void:
 workshop_input.cancel()
 if _loading_scene_active():return
 var p=selected_part()
 if p.is_empty():return
 if p.type=="cargo":notify("这是客户的货物，不能拆掉。可以调整周围装置。");return
 _remember_assembly();active_design().erase(p)
 for item in active_design():
  for key in ["input_a","input_b","target"]:
   if int(item.get(key,-1))==selected_id:item[key]=-1
 selected_id=-1;render();save_game();world.committed_edit("remove",p)
func save_blueprint() -> void:
 if _loading_scene_active():return
 economy.designs["workbench"]={"design":design.duplicate(true),"launcher":launcher.duplicate(true)};save_game();notify("图纸已保存在工位。")
func load_blueprint() -> void:
 workshop_input.cancel()
 if _loading_scene_active():return
 var blueprint:Dictionary=economy.designs.get("workbench",{})
 if blueprint.is_empty():notify("工位还没有保存图纸。");return
 var missing=economy.missing_parts(blueprint.design,blueprint.launcher)
 if not missing.is_empty():
  var names:Array[String]=[]
  for type in missing:names.append("%s ×%d"%[str(catalog.get(type,{}).get("name",type)),int(missing[type])])
  notify("缺少零件："+"、".join(names));return
 _remember_assembly();design=blueprint.design.duplicate(true);launcher=blueprint.launcher.duplicate(true);_validate_designs();_allocate_ids();selected_id=-1;save_game();render()

func start_flight(is_trial:bool) -> void:
 if _dialogue_is_open():return
 if pilot_resume_blocked:notify("此配送记录无法安全恢复，原记录已保留。");return
 if page=="flight":return
 if economy.active_contract().is_empty():notify("先去柜台确认一份委托。试飞也会使用这份货物的重量。 ");return
 if design.filter(func(p):return str(p.type)=="cargo").size()!=1:notify("飞行器必须带上这一件客户货物。");return
 if not economy.missing_parts(design,launcher).is_empty():notify("方案超过了实际库存，请先调整。");return
 if not _ensure_cargo_loaded_for_launch():return
 var route=economy.trial_route()
 if not is_trial:
  var result=economy.begin_dispatch(design,launcher)
  if not _result_ok(result):return
  if not save_game():
   economy.active_contract().status="accepted";economy.in_flight={};return
  route=economy.in_flight.route.duplicate(true);route.seed=economy.in_flight.seed
 _configure_flight(is_trial,design,launcher,route)

func _configure_flight(is_trial:bool,craft:Array,pad:Array,route:Dictionary,resuming:bool=false) -> void:
 world.set_workshop_tier(economy.workshop_tier)
 trial=is_trial;flight_order=route.duplicate(true);pilot_timeline.reset();pilot_completed_ticks=0;pilot_resume_blocked=false;_clear_pilot_input()
 var version:String=str(route.get("control_version",""))
 sim=_simulation_for_version(version)
 sim.configure(craft.duplicate(true),pad.duplicate(true),route,int(route.get("seed",economy.day*100)))
 world.route_distance=float(route.distance);world.route_radius=float(route.get("delivery_radius",5));world.launcher_design=pad.duplicate(true);world.start_flight(sim,resuming);launch_transfer_remaining=0.0 if resuming else world.launch_transfer_duration();page="flight";paused=false;speed=1;frame_accum=0;checkpoint=0;launch_countdown=0 if resuming else launch_transfer_remaining+.7;launch_age=1.35 if resuming else 0;launch_sfx_played=resuming;slow_simulation=false;completion_countdown=-1;render();_play_music(true)

func _simulation_for_version(version:String):
 match version:
  ExtremeProfile.CONTROL_VERSION:return ExtremeSimulator.new()
  AscentProfile.CONTROL_VERSION:return AscentSimulator.new()
  PilotProfile.CONTROL_VERSION:return PilotSimulator.new()
 return Simulator.new()

func _resume_dispatch() -> void:
 var snapshot=economy.in_flight.duplicate(true)
 if not snapshot.get("route") is Dictionary or not snapshot.get("design") is Array or not snapshot.get("launcher") is Array:
  pilot_resume_blocked=true;notify("配送存档不完整，无法继续。原始记录已保留。");return
 var raw_ticks:Variant=snapshot.get("ticks",roundi(float(snapshot.get("elapsed",0))*60.0))
 if not (raw_ticks is int or raw_ticks is float) or not is_finite(float(raw_ticks)) or float(raw_ticks)!=float(int(raw_ticks)) or int(raw_ticks)<0 or int(raw_ticks)>PilotTimeline.MAX_TICKS:
  pilot_resume_blocked=true;notify("配送存档损坏，无法继续。原始记录已保留。");return
 var route:Dictionary=snapshot.route;route.seed=int(snapshot.get("seed",economy.day*100))
 var control_version:String=str(snapshot.get("control_version",route.get("control_version","")))
 var route_version:String=str(route.get("control_version",""))
 var simulation_version:String=str(snapshot.get("simulation_version",""))
 var versions_conflict:bool=(not route_version.is_empty() and snapshot.has("control_version") and route_version!=control_version) or (simulation_version=="autonomous-v5" and control_version in PILOT_VERSIONS) or (simulation_version in PILOT_VERSIONS and simulation_version!=control_version) or (str(route.get("mode",""))=="pilot" and control_version.is_empty())
 if versions_conflict or not control_version in ([""]+PILOT_VERSIONS) or not route_version in ([""]+PILOT_VERSIONS) or not simulation_version in (["","autonomous-v5"]+PILOT_VERSIONS):
  notify("此配送存档暂时无法继续。原始记录已保留，请勿覆盖。");pilot_resume_blocked=true;return
 if control_version in PILOT_VERSIONS:route.control_version=control_version
 _configure_flight(false,snapshot.design,snapshot.launcher,route,true)
 var elapsed:float=float(snapshot.get("elapsed",0))
 var ticks:int=int(raw_ticks)
 if _is_pilot_flight() and not pilot_timeline.restore(snapshot.get("input_commands",null),ticks):
  pilot_resume_blocked=true;_set_paused(true);notify(pilot_timeline.error);return
 for tick in range(ticks):
  if sim.status!="running":break
  if _is_pilot_flight():
   var command:Dictionary=pilot_timeline.state_at(tick);sim.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active))
  sim.step(1.0/60.0)
  pilot_completed_ticks+=1
 _clear_pilot_input()
 world.settle_resumed_flight(sim)
 if _is_pilot_flight():_set_paused(true);notify("配送已恢复。按 P 或 Esc 继续，重新按下方向键驾驶。")
 else:notify("配送已恢复。")

func abort_flight() -> void:
 if sim==null:return
 if pilot_resume_blocked:notify("此配送记录无法安全恢复，暂不结算；原记录已保留。");return
 _clear_pilot_input()
 sim.status="failed";sim.events.append("操作员中止本次航行。");finish_flight()

func finish_flight() -> void:
 if sim==null or page!="flight" or pilot_resume_blocked:return
 _clear_pilot_input()
 sim.finalize_settlement()
 var integrity:float=float(sim.telemetry.get("integrity",0))*100
 report={"success":sim.status=="success","trial":trial,"elapsed":sim.elapsed,"integrity":integrity,"events":sim.events.duplicate(),"cause":_diagnosis(),"energy":float(sim.telemetry.get("energy_used",0))}
 if not sim.incidents.is_empty():report.incident_id=int(sim.incidents[0].id)
 if trial:
  var stored:Dictionary=economy.last_trials.get(str(flight_order.contract_id),{})
  var previous:Dictionary=stored.get("latest",stored)
  report.energy_j=report.energy;report.estimated_profit=economy.estimate_delivery(flight_order,sim.telemetry,float(sim.elapsed),sim.status=="success").profit
  report.design_snapshot=design.duplicate(true);report.launcher_snapshot=launcher.duplicate(true)
  if not previous.is_empty():
   report.comparison={"航时":"%+.2f 秒"%(sim.elapsed-float(previous.elapsed)),"耗能":"%+.1f J"%(snappedf(report.energy_j-float(previous.get("energy_j",previous.energy)),.01)),"完整度":"%+.1f%%"%(integrity-float(previous.integrity)),"预计净收益":"¥ %+d"%(int(report.estimated_profit)-int(previous.get("estimated_profit",0))),"本次改动":_design_changes(previous)}
  economy.last_trials[str(flight_order.contract_id)]={"latest":report.duplicate(true),"previous":previous.duplicate(true)}
 else:
  var result=economy.settle_contract(str(flight_order.contract_id),sim.telemetry,float(sim.elapsed),sim.status=="success")
  if result.get("ok",false):report.merge(result.report,true)
  else:notify(str(result.get("message","结算未完成。")))
 var persisted:bool=save_game()
 page="report";render();_play_music(false);_sound("delivery_success" if sim.status=="success" else "warning")
 if not trial and persisted:_request_story(str(flight_order.contract_id),"result")

func _design_changes(previous:Dictionary) -> String:
 var old:Array=previous.get("design_snapshot",[])+previous.get("launcher_snapshot",[])
 var changes:Array[String]=[]
 for p in design+launcher:
  var matches:Array=old.filter(func(q):return int(q.id)==int(p.id))
  if matches.is_empty():changes.append("新增 #"+str(p.id)+" "+str(catalog[p.type].name));continue
  var before:Dictionary=matches[0]
  if int(before.rot)!=int(p.rot):changes.append("#%d 朝向 %s → %s"%[p.id,["右","下","左","上"][int(before.rot)],["右","下","左","上"][int(p.rot)]])
  if not is_equal_approx(float(before.param),float(p.param)):changes.append("#%d %s → %s %s"%[p.id,str(before.param),str(p.param),str(PartsDB.parameter_schema(p.type).get("unit",""))])
  for key in ["input_a","input_b","target"]:
   if int(before.get(key,-1))!=int(p.get(key,-1)):changes.append("#%d 调整%s"%[p.id,{"input_a":"信号 A","input_b":"信号 B","target":"作用目标"}[key]])
 for p in old:
  if (design+launcher).filter(func(q):return int(q.id)==int(p.id)).is_empty():changes.append("拆下 #"+str(p.id))
 return "；".join(changes) if not changes.is_empty() else "装置未改动。"

func _remember_assembly() -> void:
 undo_history.append({"design":design.duplicate(true),"launcher":launcher.duplicate(true),"selected":selected_id})
 if undo_history.size()>32:undo_history.pop_front()
func undo_assembly() -> void:
 workshop_input.cancel()
 if _loading_scene_active():return
 if page!="workshop" or undo_history.is_empty():return
 var previous:Dictionary=undo_history.pop_back();design=previous.design;launcher=previous.launcher;selected_id=int(previous.selected);_allocate_ids();save_game();render();notify("已撤销上一步装配修改。")

func _diagnosis() -> String:
 if not sim.incidents.is_empty():
  var hit:Dictionary=sim.incidents[0]
  var cause:String={"collision":"碰撞","stress":"结构过载","attack":"外部攻击"}.get(str(hit.source),str(hit.source))
  var advice:String={"collision":"检查外廓与通过碎石门的净空。","stress":"降低瞬间推力，或重新布置承载与缓冲。","attack":"检查受击位置的防护和供能。"}.get(str(hit.source),"检查该模块与邻件。")
  return "首次受损：%.2f 秒，#%d %s受到%s，损伤 %.2f HP。%s"%[float(hit.elapsed),int(hit.id),catalog.get(str(hit.type),{}).get("name",str(hit.type)),cause,float(hit.amount),advice]
 if sim.status=="success":return "货物已签收。"
 for event in sim.events:
  var message=str(event)
  if "碰撞" in message or "断裂" in message or "损毁" in message or "耗尽" in message:return message+"。回工位检查相关零件的位置、连接或供能。"
 if sim.cargo_position().x<0:return "货物飞向了起点后方。检查喷口朝向；朝后的推力会抵消发射冲量。"
 if float(sim.telemetry.get("energy_remaining",0))<1:return "储能已耗尽，仍未送达。可减轻装置、降低无效耗能，或增加连接到动力组件的电芯。"
 return str(sim.events.back()) if not sim.events.is_empty() else "未进入收件区。检查推进方向、货舱连接和收件速度要求。"

func _is_pilot_flight() -> bool:
 return sim!=null and sim.has_method("set_pilot_input") and str(flight_order.get("control_version","")) in PILOT_VERSIONS

func _clear_pilot_input() -> void:
 pilot_keys.clear()
 if _is_pilot_flight():
  sim.set_pilot_input(0,false,false)
  sim.telemetry.pilot_axis_q=0;sim.telemetry.pilot_boost=false;sim.telemetry.pilot_active=false
  if sim.telemetry.has("overdrive"):sim.telemetry.overdrive=false

func _pilot_input_state() -> Dictionary:
 var up:bool=pilot_keys.has(KEY_W) or pilot_keys.has(KEY_UP)
 var down:bool=pilot_keys.has(KEY_S) or pilot_keys.has(KEY_DOWN)
 var pad:Dictionary=courier_input.pilot_state() if is_instance_valid(courier_input) else {"axis_q":0,"boost":false,"active":false}
 return {"axis_q":(int(down)-int(up))*1000 if up or down else int(pad.axis_q),"boost":pilot_keys.has(KEY_SHIFT) or bool(pad.boost),"active":pilot_keys.has(KEY_SPACE) or bool(pad.active)}

func _set_paused(value:bool) -> void:
 if pilot_resume_blocked and not value:return
 paused=value;_clear_pilot_input()
 if is_instance_valid(courier_input):courier_input.synchronize()

func _on_focus_exited() -> void:
 if is_instance_valid(courier_input):courier_input.set_focus_active(false)
 workshop_input.cancel()
 if is_instance_valid(loading_overlay):loading_overlay.set_focus_active(false)
 if is_instance_valid(dialogue):dialogue.set_focus_active(false)
 if is_instance_valid(world):world.set_focus_active(false)
 if page=="flight":
  if _flight_modal_was_open or (is_instance_valid(hud) and hud.is_blocking_modal()):_paused_before_modal=true
  _set_paused(true);_checkpoint_flight();save_game()
 else:_clear_pilot_input()

func _on_focus_entered() -> void:
 if is_instance_valid(courier_input):courier_input.set_focus_active(true)
 if is_instance_valid(loading_overlay):loading_overlay.set_focus_active(true)
 if is_instance_valid(dialogue):dialogue.set_focus_active(true)
 if is_instance_valid(world):world.set_focus_active(true)

func _checkpoint_flight() -> void:
 if page!="flight" or trial or sim==null or pilot_resume_blocked or economy.in_flight.is_empty():return
 if str(economy.in_flight.get("contract_id",""))!=str(flight_order.get("contract_id","")):return
 economy.in_flight.elapsed=sim.elapsed
 economy.in_flight.ticks=pilot_completed_ticks if _is_pilot_flight() else roundi(sim.elapsed*60.0)
 if _is_pilot_flight():economy.in_flight.control_version=str(flight_order.control_version);economy.in_flight.input_commands=pilot_timeline.snapshot()

func _step_flight() -> void:
 if _is_pilot_flight():
  var command:Dictionary=_pilot_input_state()
  if not pilot_timeline.record(pilot_completed_ticks,command):
   _set_paused(true);notify(pilot_timeline.error);return
  sim.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active))
 sim.step(1.0/60.0);pilot_completed_ticks+=1

func _process(delta:float) -> void:
 if is_instance_valid(courier_input):courier_input.tick(delta)
 workshop_input.tick()
 _sync_loading_scene_ui()
 if not _pending_story.is_empty():_try_pending_story()
 if is_instance_valid(hud) and is_instance_valid(world) and page=="hub":hud.update_hotspots(world.hotspot_positions())
 if page!="flight" or sim==null:return
 if pilot_resume_blocked:return
 var modal_open:bool=is_instance_valid(hud) and hud.is_blocking_modal()
 if modal_open and not _flight_modal_was_open:_paused_before_modal=paused;_set_paused(true)
 elif not modal_open and _flight_modal_was_open:_set_paused(_paused_before_modal)
 _flight_modal_was_open=modal_open
 var active_delta:float=0.0
 # A positive charge age can only occur after the transfer (also used by
 # deterministic fixtures and historical resume adapters).
 if launch_age>0.0 or world.launch_transfer_duration()<=0.0:launch_transfer_remaining=0.0
 if not paused:
  var remaining_delta:float=maxf(0.0,delta)
  if launch_transfer_remaining>0.0:
   var used:float=minf(remaining_delta,launch_transfer_remaining)
   launch_transfer_remaining=maxf(0.0,launch_transfer_remaining-used);remaining_delta-=used
  active_delta=maxf(0.0,remaining_delta-maxf(0.0,.7-launch_age))
  launch_age+=remaining_delta
 world.launch_transfer_progress=1.0 if world.launch_transfer_duration()<=0.0 else 1.0-launch_transfer_remaining/world.launch_transfer_duration()
 launch_countdown=launch_transfer_remaining+maxf(0,.7-launch_age);world.launch_age=launch_age
 if launch_countdown<=0.0 and not launch_sfx_played:launch_sfx_played=true;_sound("launch")
 var launch_phase:String="move" if launch_transfer_remaining>0.0 else ("charge" if launch_age<.7 else ("ignition" if launch_age<.95 else ("release" if launch_age<1.35 else "done")))
 var launch_progress:float=world.launch_transfer_progress if launch_phase=="move" else (launch_age/.7 if launch_phase=="charge" else ((launch_age-.7)/.25 if launch_phase=="ignition" else (launch_age-.95)/.4))
 if hud.has_method("update_launch"):hud.update_launch(clampf(launch_progress,0,1),launch_phase)
 slow_simulation=false
 if launch_countdown<=0 and not paused:
  frame_accum=minf(.25,frame_accum+minf(active_delta,.1)*speed)
  var started:int=Time.get_ticks_usec();var steps:int=0
  while frame_accum>=1.0/60.0 and sim.status=="running":
   _step_flight();frame_accum-=1.0/60.0;steps+=1
   if steps>=8 or Time.get_ticks_usec()-started>=8000:
    slow_simulation=frame_accum>=1.0/60.0;break
 world.show_flight(sim,paused)
 var flight_data:Dictionary=sim.telemetry.duplicate(true)
 flight_data.merge({"elapsed":sim.elapsed,"distance":sim.cargo_position().x,"total_distance":world.route_distance,"integrity":sim.telemetry.get("integrity",1),"energy_used":sim.telemetry.get("energy_used",0),"events":[] if launch_countdown>0 else sim.events,"charging":launch_countdown>0,"paused":paused,"simulation_rate":speed,"phase":("收件确认" if sim.status=="success" else "航行结束") if sim.status!="running" else (("移送到地面发射位" if launch_transfer_remaining>0.0 else "发射台蓄能中") if launch_countdown>0 else ("运行较慢" if slow_simulation else ("手动驾驶" if _is_pilot_flight() else "自动航行")))},true)
 if not _is_pilot_flight():flight_data.speed=speed
 hud.update_flight(flight_data)
 if not trial and sim.elapsed-checkpoint>=1.0:checkpoint=sim.elapsed;_checkpoint_flight();save_game()
 if sim.status!="running":
  if completion_countdown<0:completion_countdown=1.05
  else:completion_countdown-=delta
  if completion_countdown<=0:finish_flight()
func _input(event:InputEvent) -> void:
 workshop_input.observe(event)
 # Releases must be observed even when a focused UI control consumes key presses.
 if event is InputEventKey and not event.pressed:
  pilot_keys.erase(event.keycode);pilot_keys.erase(event.physical_keycode)

func _unhandled_key_input(event:InputEvent) -> void:
 if is_instance_valid(courier_input) and not courier_input.focused:return
 if not event is InputEventKey or not event.pressed or event.echo:return
 if _dialogue_is_open():return
 if event.keycode==KEY_F11:toggle_fullscreen();return
 if _loading_scene_active():return
 if is_instance_valid(hud) and hud.is_blocking_modal():return
 if page=="workshop":
  if event.keycode==KEY_F:workshop_input.fit();get_viewport().set_input_as_handled()
  if event.keycode==KEY_Z and event.ctrl_pressed:undo_assembly()
  if event.keycode==KEY_R:rotate_part()
  if event.keycode==KEY_DELETE:remove_part()
 if page=="flight" and _is_pilot_flight():
  var code:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
  if code in [KEY_P,KEY_ESCAPE]:_set_paused(not paused);get_viewport().set_input_as_handled()
  elif not paused and not pilot_resume_blocked and code in [KEY_W,KEY_S,KEY_UP,KEY_DOWN,KEY_SHIFT,KEY_SPACE]:pilot_keys[code]=true;get_viewport().set_input_as_handled()
 elif page=="flight" and event.keycode in [KEY_SPACE,KEY_ESCAPE]:_set_paused(not paused)
 elif event.keycode==KEY_ESCAPE:navigate("hub")
func save_game() -> bool:
 if pilot_resume_blocked:return false
 _checkpoint_flight()
 var ok=economy.save_state(design,launcher,settings)
 if not ok:notify(economy.save_error)
 return ok
func _apply_quality() -> void:
 var adapter=RenderingServer.get_video_adapter_name().to_lower() if DisplayServer.get_name()!="headless" else ""
 software_renderer="llvmpipe" in adapter or "softpipe" in adapter or "swiftshader" in adapter or "software" in adapter
 var selected_quality:String=str(settings.get("quality","auto"))
 if not selected_quality in ["auto","low","standard","high"]:selected_quality="auto";settings.quality="auto"
 quality_profile=("low" if software_renderer else "standard") if selected_quality=="auto" else selected_quality
 var density:String=str(settings.get("pixel_density","auto"))
 if not density in ["auto","balanced","low"]:density="auto";settings.pixel_density="auto"
 if is_instance_valid(view_container) and view_container.has_method("set_density_mode"):view_container.set_density_mode(density)
 # Retain old quality values for save compatibility. The pure 2D renderer has
 # no adjustable 3D shadows; actual displayed resolution follows pixel density.
 view.scaling_3d_scale=1.0;view.msaa_3d=Viewport.MSAA_DISABLED
 if world.has_method("apply_quality"):world.apply_quality(quality_profile)

func toggle_fullscreen() -> void:
 settings.fullscreen=not bool(settings.fullscreen);DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED);save_game()
func _play_music(flying:bool) -> void:
 if DisplayServer.get_name()=="headless" or not is_instance_valid(music):return
 var path="res://assets/audio/flight_loop.ogg" if flying else "res://assets/audio/workshop_loop.ogg"
 var track=load(path)
 if music.stream==track and music.playing:return
 music.stream=track
 if music.stream is AudioStreamOggVorbis:music.stream.loop=true
 music.volume_db=linear_to_db(maxf(float(settings.volume),.001))-5;music.play()
func _sound(name:String) -> void:
 if DisplayServer.get_name()=="headless" or not is_instance_valid(sfx):return
 var path="res://assets/audio/"+name+".wav"
 if ResourceLoader.exists(path):sfx.stream=load(path);sfx.volume_db=linear_to_db(maxf(float(settings.volume),.001));sfx.play()
func _notification(what:int) -> void:
 if what==NOTIFICATION_WM_CLOSE_REQUEST:_quit_cleanly.call_deferred()
func _quit_cleanly(exit_code:int=0) -> void:
 if closing:return
 closing=true
 if is_instance_valid(dialogue):dialogue.cancel(false)
 if is_instance_valid(loading_overlay):loading_overlay.close()
 _active_story.clear();_pending_story.clear()
 _checkpoint_flight()
 save_game()
 if is_instance_valid(music):music.stop();music.stream=null
 if is_instance_valid(sfx):sfx.stop();sfx.stream=null
 await get_tree().create_timer(.25).timeout
 get_tree().quit(exit_code)
func _smoke_test() -> void:
 _action("accept_contract",str(economy.available_contracts()[0].contract_id))
 if _dialogue_is_open():dialogue.skip_conversation()
 start_flight(true)
 var test_tick:int=0;var test_axis:int=0
 while sim.status=="running":
  # Test-only binary pilot commands. No such guidance runs in a normal game.
  if test_tick%12==0:test_axis=_smoke_guidance_axis()
  pilot_keys.clear()
  if test_axis!=0:pilot_keys[KEY_S if test_axis>0 else KEY_W]=true
  _step_flight();test_tick+=1
 print("SMOKE_FLIGHT ",sim.status," ",sim.elapsed," ",sim.telemetry);finish_flight();print("SMOKE_UI_COMPLETE");await _quit_cleanly(0 if sim.status=="success" else 1)

func _smoke_guidance_axis() -> int:
 # QA-only observer, called solely by smoke/proof scripts. Normal _process
 # reads real key state and never calls this helper.
 var at:Vector2=sim.cargo_position()
 if str(sim.route.get("control_version","")) in ASCENT_VERSIONS:
  var offset:float=0
  for gate in sim.route.get("pilot_gates",[]):
   if at.x<float(gate.x)+6.5:offset=float(gate.lane_offset);break
  var normal:Vector2=AscentProfile.path_tangent(at.x,sim.route).orthogonal()*-1.0
  var velocity:Vector2=sim._cargo_body().get("velocity",Vector2.ZERO)
  var error:float=AscentProfile.path_y(at.x,sim.route)+offset-at.y-velocity.dot(normal)*.9
  return int(signf(error))*1000 if absf(error)>.9 else 0
 var goal:float=0
 for gate in sim.route.get("pilot_gates",[]):
  if at.x<float(gate.x)+4:goal=float(gate.y);break
 var error:float=goal-at.y-float(sim.telemetry.get("vertical_speed",0))*.85
 return int(signf(error))*1000 if absf(error)>.32 else 0
func _capture(name:String) -> void:
 await get_tree().process_frame;await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://docs/qa/"+name+".png");print("CAPTURE ",name)
func _visual_test() -> void:
 await get_tree().create_timer(2).timeout;await _capture("v2-01-shop")
 navigate("contracts");await get_tree().create_timer(1).timeout;await _capture("v2-02-counter")
 _action("accept_contract",str(economy.available_contracts()[0].contract_id));await get_tree().create_timer(2).timeout;await _capture("v2-03-accepted")
 _action("focus_workbench",null);selected_id=4;render();await get_tree().create_timer(2).timeout;await _capture("v2-04-workbench")
 start_flight(true);await get_tree().create_timer(5.2).timeout;paused=true;await _capture("v2-05-flight")
 while sim.status=="running":sim.step(1.0/60.0)
 finish_flight();await get_tree().create_timer(1).timeout;await _capture("v2-06-trial")
 design[3].param=3;start_flight(true)
 while sim.status=="running":sim.step(1.0/60.0)
 finish_flight();await get_tree().create_timer(1).timeout;await _capture("v2-06b-comparison")
 start_flight(false)
 while sim.status=="running":sim.step(1.0/60.0)
 finish_flight();await get_tree().create_timer(1).timeout;await _capture("v2-07-return")
 _action("close_day",null);await get_tree().create_timer(1).timeout;await _capture("v2-08-night")
 print("VISUAL_TEST_COMPLETE");await _quit_cleanly()
