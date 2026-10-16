extends Node3D
const PartsDB=preload("res://scripts/parts_expanded.gd")
const WorkshopParts=preload("res://scripts/workshop_parts_v2.gd")
const WorkshopPower=preload("res://scripts/workshop_power_status_v1.gd")
const Simulator=preload("res://scripts/simulation.gd")
const PilotSimulator=preload("res://scripts/pilot_simulation.gd")
const PilotProfile=preload("res://scripts/pilot_profile.gd")
const AscentSimulator=preload("res://scripts/pilot_ascent_simulation.gd")
const AscentProfile=preload("res://scripts/pilot_ascent_profile.gd")
const ExtremeSimulator=preload("res://scripts/pilot_extreme_simulation.gd")
const ExtremeProfile=preload("res://scripts/pilot_extreme_profile.gd")
const WormholeSimulator=preload("res://scripts/pilot_wormhole_simulation.gd")
const WormholeProfile=preload("res://scripts/pilot_wormhole_profile.gd")
const BirdSimulator=preload("res://scripts/pilot_protected_bird_simulation.gd")
const BirdProfile=preload("res://scripts/pilot_protected_bird_profile.gd")
const BirdOffer=preload("res://scripts/protected_bird_offer_v1.gd")
const BirdDesign=preload("res://scripts/protected_bird_design_v1.gd")
const BirdSettlement=preload("res://scripts/protected_bird_settlement_v1.gd")
const FlightReceipt=preload("res://scripts/flight_receipt.gd")
const PirateSimulator=preload("res://scripts/pilot_pirate_route_candidate_v1.gd")
const PirateProfile=preload("res://scripts/pirate_encounter_profile_v1.gd")
const PirateProfileV2=preload("res://scripts/pirate_encounter_profile_v2.gd")
const PirateSimulatorV2=preload("res://scripts/pilot_pirate_route_candidate_v2.gd")
const PirateOffer=preload("res://scripts/pirate_sidejob_offer_v1.gd")
const PiratePresentation=preload("res://scripts/pirate_world_presenter_2d.gd")
const PirateProtocols=preload("res://scripts/pirate_protocols.gd")
# Source staging only. No authored route or art/solver acceptance is implied.
const PIRATE_PLAYER_ROUTE_REGISTERED:bool=true
const PIRATE_PRODUCTION_ENCOUNTER_SCHEMA:String="pirate-ascent-encounter-v1"
const PIRATE_HOLD_MESSAGE:String="配送暂时停止，记录已保留。请重新打开游戏后再试。"
const PILOT_VERSIONS:Array=[PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION,PirateProfile.VERSION,PirateProfileV2.VERSION,"pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const ASCENT_VERSIONS:Array=[AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION,PirateProfile.VERSION,PirateProfileV2.VERSION,"pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const EXTREME_VERSIONS:Array=[ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION,PirateProfile.VERSION,PirateProfileV2.VERSION,"pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]
const PilotTimeline=preload("res://scripts/pilot_timeline.gd")
const FreeProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const FreeSimulator=preload("res://scripts/pilot_free_simulation_v1.gd")
const FreeTimeline=preload("res://scripts/pilot_free_timeline_v1.gd")
const FreeInput=preload("res://scripts/pilot_free_input_v1.gd")
const FreeProfileV2=preload("res://scripts/pilot_free_profile_v2.gd")
const DeliveryProfile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const DeliveryAscentProfile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const DeliveryAscentSimulator=preload("res://scripts/pilot_delivery_ascent_simulation_v4.gd")
const DeliveryRiftProfile=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const DeliveryRiftSimulator=preload("res://scripts/pilot_delivery_rift_simulation_v5.gd")
const RiftDeliveryPresenter=preload("res://scripts/rift_delivery_presenter_v5.gd")
const MoonAscentPresenter=preload("res://scripts/moon_ascent_presenter_v4.gd")
const DeliverySimulator=preload("res://scripts/pilot_delivery_simulation_v3.gd")
const CellRules=preload("res://scripts/cell_rules_profile_v6.gd")
const DeliveryProfileV6=preload("res://scripts/pilot_delivery_profile_v6.gd")
const DeliveryAscentProfileV6=preload("res://scripts/pilot_delivery_ascent_profile_v6.gd")
const DeliveryRiftProfileV6=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const DeliverySimulatorV6=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const DeliveryAscentSimulatorV6=preload("res://scripts/pilot_delivery_ascent_simulation_v6.gd")
const DeliveryRiftSimulatorV6=preload("res://scripts/pilot_delivery_rift_simulation_v6.gd")
const DeliveryProfileV8=preload("res://scripts/pilot_delivery_profile_v8.gd")
const DeliveryAscentProfileV8=preload("res://scripts/pilot_delivery_ascent_profile_v8.gd")
const DeliveryRiftProfileV8=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const DeliverySimulatorV8=preload("res://scripts/pilot_delivery_simulation_v8.gd")
const DeliveryAscentSimulatorV8=preload("res://scripts/pilot_delivery_ascent_simulation_v8.gd")
const DeliveryRiftSimulatorV8=preload("res://scripts/pilot_delivery_rift_simulation_v8.gd")
const DeliveryProfileV7=preload("res://scripts/pilot_delivery_profile_v7.gd")
const DeliveryAscentProfileV7=preload("res://scripts/pilot_delivery_ascent_profile_v7.gd")
const DeliveryRiftProfileV7=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const DeliverySimulatorV7=preload("res://scripts/pilot_delivery_simulation_v7.gd")
const DeliveryAscentSimulatorV7=preload("res://scripts/pilot_delivery_ascent_simulation_v7.gd")
const DeliveryRiftSimulatorV7=preload("res://scripts/pilot_delivery_rift_simulation_v7.gd")
const FreeProtocols=preload("res://scripts/free_flight_protocols.gd")
const LunarReceipt=preload("res://scripts/lunar_outpost_receipt_v2.gd")
const MosslightReceipt=preload("res://scripts/mosslight_receipt_v2.gd")
const FreeSimulatorV2=preload("res://scripts/pilot_free_simulation_v2.gd")
const FreeTimelineV2=preload("res://scripts/pilot_free_timeline_v2.gd")
const FreeInputV2=preload("res://scripts/pilot_free_input_v2.gd")
const SelectedDeviceView=preload("res://scripts/selected_device_presentation_v2.gd")
const EconomyDB=preload("res://scripts/economy.gd")
const RecoveryPresentationCaps=preload("res://scripts/recovery_presentation_caps.gd")
const WorldView=preload("res://scripts/world_view_2d.gd")
const GameHUD=preload("res://scripts/game_hud.gd")
const PixelStage=preload("res://scripts/pixel_stage.gd")
const DialoguePanel=preload("res://scripts/dialogue_panel.gd")
const LoadingSceneOverlay=preload("res://scripts/loading_scene_overlay.gd")
const CustomerReviewPhone=preload("res://scripts/customer_review_phone.gd")
const ShopInvestigation=preload("res://scripts/shop_investigation.gd")
const CourierInput=preload("res://scripts/courier_input.gd")
const WorkshopInput=preload("res://scripts/workshop_input_2d.gd")
const WorkshopProfile=preload("res://scripts/workshop_profile.gd")
var courier_input
var investigation
var review_phone
var _review_phone_owner:int=0
# Opt-in initializer injection, selected before World creates any clerk rig.
var clerk_pose_bootstrap_script:Script
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
var _delivery_launch_released:bool=false
var _flight_launch_settings:Dictionary={"angle_degrees":0.0,"power_fraction":1.0}
var _delivery_preview_key:String=""
var _delivery_preview_cache:Dictionary={}
var settings:Dictionary={"volume":0.55,"dialogue_volume":0.55,"dialogue_muted":false,"fullscreen":false,"reduced_motion":false,"motion_blur":true,"quality":"auto","pixel_density":"auto","controller_deadzone":.22,"launch_settings":{"angle_degrees":0.0,"power_fraction":1.0}}
var world
var hud
var view:SubViewport
var view_container:Control
# Explicit resource references make the exporter verify the audio dependencies.
const MUSIC_TRACKS:Dictionary={
 "workshop":preload("res://assets/audio/workshop_loop.ogg"),
 "flight":preload("res://assets/audio/flight_loop.ogg")
}
const SOUND_EFFECTS:Dictionary={
 "ui_select":preload("res://assets/audio/ui_select.wav"),
 "module_snap":preload("res://assets/audio/module_snap.wav"),
 "launch":preload("res://assets/audio/launch.wav"),
 "warning":preload("res://assets/audio/warning.wav"),
 "delivery_success":preload("res://assets/audio/delivery_success.wav")
}
const SaveExitDialog=preload("res://scripts/save_exit_dialog.gd")
var _abort_prompt:ConfirmationDialog
var _abort_prompt_pending:bool=false
var _abort_prompt_was_paused:bool=false
var _abort_prompt_sim
var _abort_prompt_contract_id:String=""
var _quit_prompt:ConfirmationDialog
var _quit_dialog:ConfirmationDialog
var _quit_exit_code:int=0
var _quit_prompt_was_paused:bool=false
var _quit_prompt_resume_after_modal:bool=false
var _quit_pause_after_disconnect:bool=false
var _quit_save_failed:bool=false
var _quit_prompt_pending:bool=false
var _quit_failure_pending:bool=false
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
var _selected_free_device_id:int=-1
var pilot_resume_blocked:bool=false
var _free_restore_active:bool=false
var _free_restore_token:int=0
var _free_restore_fraction:float=0.0
var _free_restore_error:String=""
var _free_abort_intent:bool=false
var _flight_modal_was_open:bool=false
var _paused_before_modal:bool=false
var dialogue
var loading_overlay
var _pending_story:Dictionary={}
var _active_story:Dictionary={}
var _story_save_attempted:bool=false
var _finalizing_cargo_for_launch:bool=false
var workshop_input=WorkshopInput.new()
var _pirate_diagnostic:Dictionary={}
# Transient feedback only; never written into the save schema.
var _last_save_error:String=""
# Title-owned, transient ingress only. No save schema fields are added.
var entry_new_game:bool=false
var entry_require_existing_save:bool=false
var entry_settings_overrides:Dictionary={}
var entry_defer_controls:bool=false
var entry_shop_walk:bool=false
var _entry_restore_prepared:bool=false
# Transient consent/notice only; Economy owns each durable transaction.
var _pending_free_order_upgrade:Dictionary={}
var _transition_previews:Dictionary={}
var _free_entry_notice:String=""
var _legacy_recovery_deferred:bool=false

func _ready() -> void:
 get_tree().auto_accept_quit=false
 get_window().title="星际快递"
 economy.route_guard=_recovery_route_error
 # Pixel stage uses actual window pixels, while Chinese UI stays readable.
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 get_window().content_scale_size=Vector2i.ZERO
 get_window().min_size=Vector2i(1280,720)
 get_window().focus_exited.connect(_on_focus_exited)
 get_window().focus_entered.connect(_on_focus_entered)
 get_window().close_requested.connect(_request_save_and_quit)
 catalog=PartsDB.catalog();catalog.cargo=PartsDB.cargo_spec();_starter()
 # An explicit new game must bring the one-shot protected commit callback.
 if entry_new_game and not economy.new_game_commit_guard.is_valid():
  economy.review_load_blocked=true;economy.load_notice="新游戏尚未准备完成，原存档未改变。"
  _show_save_recovery();return
 var loaded:Dictionary={} if entry_new_game else economy.load_state(true)
 if entry_require_existing_save and loaded.is_empty() and not economy.review_load_blocked:
  economy.review_load_blocked=true;economy.load_notice="存档已移走，无法继续。原记录未改变。"
 if economy.review_load_blocked:
  _show_save_recovery();return
 if not loaded.is_empty():
  design=loaded.get("design",design);launcher=loaded.get("launcher",launcher);settings.merge(loaded.get("settings",{}),true)
 if not _prepare_free_economy_entry(not loaded.is_empty()):
  _show_save_recovery();return
 settings.merge(entry_settings_overrides,true)
 settings.launch_settings=_launch_settings()
 economy.enable_story_mode()
 if not economy.review_load_blocked:
  var seeded:Dictionary=economy.enable_seeded_offers(economy.story_state.get("world_seed"))
  if not seeded.ok:
   economy.review_load_blocked=true;economy.load_notice="航线记录暂时无法读取，原进度已保留。"
   _show_save_recovery();return
 var unavailable:String=economy.presentation_state_error()
 if not unavailable.is_empty():
  economy.review_load_blocked=true;economy.load_notice=unavailable
  _show_save_recovery();return
 _validate_designs();_allocate_ids()
 # Startup can author a seed or fill a genuinely empty offer boundary. Commit
 # those bytes before any world, UI, input owner or dialogue exposes them.
 # Existing in-flight files must first pass the established resume checks;
 # never rotate their valid backup while an unsafe replay is still unvalidated.
 if economy.in_flight.is_empty() and not economy.review_load_blocked and not save_game():
  economy.review_load_blocked=true;economy.load_notice="进度暂时无法保存，原文件已保留。请检查存储空间后重新打开。"
  _show_save_recovery();return
 if bool(settings.fullscreen):DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 elif entry_settings_overrides.has("fullscreen") and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
 _build_ui()
 if economy.review_load_blocked:_show_save_recovery();return
 _apply_quality()
 _ensure_audio_players()
 render();_play_music(false)
 var load_message:String=economy.load_notice
 if not _free_entry_notice.is_empty():
  load_message+=("\n" if not load_message.is_empty() else "")+_free_entry_notice
  _free_entry_notice=""
 if _outside_workshop_count(design)+_outside_workshop_count(launcher)>0:
  load_message+=("\n" if not load_message.is_empty() else "")+"旧方案的超出工位部分已保留。可以移回开放格，或收工后扩建。"
 if not load_message.is_empty():notify(load_message)
 if economy.review_load_blocked:return
 if entry_defer_controls:
  # Title permits only the real World's presentation until actual arrival.
  # No deferred dialogue or replay may run twice across this ownership boundary.
  process_mode=Node.PROCESS_MODE_DISABLED
  hud.hide()
  return
 _dispatch_ready_restore()
 if "--smoke-test" in OS.get_cmdline_user_args():_smoke_test.call_deferred()
 if "--visual-test" in OS.get_cmdline_user_args():_visual_test.call_deferred()

func _prepare_free_economy_entry(has_loaded_save:bool) -> bool:
 # Only the real Main ingress invokes this, after Continue has loaded the save.
 # Title's read-only preview never constructs Main or calls this transaction.
 if has_loaded_save and not _delivery_version(economy.flight_mode):
  var recovery:Dictionary=economy.recover_legacy_debt_and_save(design,launcher,settings)
  if not bool(recovery.get("ok",false)):
   economy.review_load_blocked=true;economy.load_notice=str(recovery.get("message","旧存档暂时无法升级，原进度已保留。"));return false
  var loaded_route:Dictionary=economy.in_flight.get("route",{})
  var loaded_version:String=str(economy.in_flight.get("control_version",loaded_route.get("control_version","")))
  # Even a nonnegative old balance can become debt under that retained trip's
  # original settlement. Do not rerate the trip; check only after it commits.
  _legacy_recovery_deferred=bool(recovery.get("deferred",false)) or (not economy.in_flight.is_empty() and not _free_version(loaded_version) and economy.economic_recovery.is_empty())
  if bool(recovery.get("changed",false)):_free_entry_notice=str(recovery.get("message",""))
 if not has_loaded_save:
  var enabled:Dictionary=economy.enable_delivery_mode()
  if not bool(enabled.get("ok",false)):
   economy.review_load_blocked=true;economy.load_notice=str(enabled.get("message","首章运输尚未准备完成。"));return false
  design=DeliveryProfile.starter_design();launcher=DeliveryProfile.starter_launcher()
  economy.starter_stock(design,launcher)
 return true

func _finish_deferred_free_recovery() -> bool:
 if not _legacy_recovery_deferred:return true
 # The legacy receipt has already committed with its original arithmetic.
 var recovery:Dictionary=economy.recover_legacy_debt_and_save(design,launcher,settings)
 if not bool(recovery.get("ok",false)):
  economy.review_load_blocked=true;economy.load_notice=str(recovery.get("message","补贴暂时无法保存，原账单已保留。"))
  if is_instance_valid(hud):hud.hide()
  _show_save_recovery();return false
 _legacy_recovery_deferred=bool(recovery.get("deferred",false))
 if bool(recovery.get("changed",false)):_free_entry_notice=str(recovery.get("message",""))
 return true

func _title_shop_walk_allowed() -> bool:
 # Conservative: leave accepted/loading/result/return/in-flight restoration
 # exactly with the existing game. Never move those records into an empty shop.
 return entry_defer_controls and not economy.review_load_blocked and economy.in_flight.is_empty() and economy.active_contract_id.is_empty() and economy.last_settlement.is_empty() and economy.pending_story_returns().is_empty() and economy.phase!="night"

func prepare_title_restore() -> void:
 if not entry_defer_controls or _entry_restore_prepared:return
 if not economy.in_flight.is_empty():
  _entry_restore_prepared=true
  # Original safe replay validates and restores its original position while
  # player input is still disabled. It already resumes paused.
  _resume_dispatch()

func _dispatch_ready_restore() -> void:
 if _entry_restore_prepared:return
 _entry_restore_prepared=true
 if not economy.in_flight.is_empty():_resume_dispatch.call_deferred()
 else:_restore_story_dialogue.call_deferred()

func finish_title_entry() -> void:
 if not entry_defer_controls:return
 entry_defer_controls=false
 if is_instance_valid(world):world.process_mode=Node.PROCESS_MODE_INHERIT
 process_mode=Node.PROCESS_MODE_INHERIT
 _play_music(page=="flight")
 if is_instance_valid(hud):hud.show()
 if is_instance_valid(courier_input):courier_input.quarantine()
 _dispatch_ready_restore()

static func pirate_production_route_error(route:Dictionary,registered:bool=PIRATE_PLAYER_ROUTE_REGISTERED) -> String:
 # Registration alone never opens QA/v1/orbit routes. Dedicated complete
 # commercial identity, exact v2 ascent and the art receipt are all required.
 var unavailable:String="这份航线仍在准备中，原进度已保留。"
 if not registered or not PirateOffer.has_markers(route) or not PirateOffer.validation_error(route).is_empty():return unavailable
 if route.get("control_version")!=PirateProfileV2.VERSION or not PirateProfileV2.route_error(route).is_empty():return unavailable
 return PiratePresentation.route_error(route)

func _recovery_route_error(route:Dictionary) -> String:
 # Shield policy markers must never fall through to an older solver. The
 # corresponding private v7 copy reuses only already verified presentation.
 if DeliveryProfileV8.shield_markers(route):
  var shield_error:String=FreeProtocols.route_error(route)
  if not shield_error.is_empty():return shield_error
  var profile=DeliveryAscentProfileV8 if route.control_version==DeliveryAscentProfileV8.VERSION else (DeliveryRiftProfileV8 if route.control_version==DeliveryRiftProfileV8.VERSION else DeliveryProfileV8)
  return _recovery_route_error(profile.compatibility_route(route))
 # Validate new material markers first, including unknown/mixed identities.
 # Existing presentation permission is reused only via a private v6 copy.
 if DeliveryProfileV7.material_markers(route):
  var material_error:String=FreeProtocols.route_error(route)
  if not material_error.is_empty():return material_error
  var profile=DeliveryAscentProfileV7 if route.control_version==DeliveryAscentProfileV7.VERSION else (DeliveryRiftProfileV7 if route.control_version==DeliveryRiftProfileV7.VERSION else DeliveryProfileV7)
  return _recovery_route_error(profile.compatibility_route(route))
 # New identities are validated before broad legacy policy markers. Only the
 # exact environment earns its existing verified art, never the old caps.
 if CellRules.has_markers(route):
  var cell_error:String=CellRules.validation_error(route)
  if not cell_error.is_empty():return cell_error
  if route.cell_environment=="ascent":return MoonAscentPresenter.route_error(route)
  if route.cell_environment=="rift":return RiftDeliveryPresenter.route_error(route)
  var local:Dictionary=DeliveryProfileV6.compatibility_route(route)
  var ground_art_error:String=MosslightReceipt.route_error(local)
  return ground_art_error if not ground_art_error.is_empty() else LunarReceipt.route_error(local)
 # Only this exact new profile can use its verified pixel presentation.
 if DeliveryRiftProfile.has_markers(route):
  var rift_error:String=DeliveryRiftProfile.validation_error(route)
  return rift_error if not rift_error.is_empty() else RiftDeliveryPresenter.route_error(route)
 # Only the new exact altitude protocol earns its verified existing moon art.
 # Mixed markers fail closed; legacy moon/portal capability gates stay intact.
 if DeliveryAscentProfile.has_markers(route):
  var ascent_error:String=DeliveryAscentProfile.validation_error(route)
  return ascent_error if not ascent_error.is_empty() else MoonAscentPresenter.route_error(route)
 # The new environment must pass its own art receipt before free-v2 returns.
 var mosslight_error:String=MosslightReceipt.route_error(route)
 if not mosslight_error.is_empty():return mosslight_error
 var lunar_error:String=LunarReceipt.route_error(route)
 if not lunar_error.is_empty():return lunar_error
 if DeliveryProfile.has_markers(route):return DeliveryProfile.validation_error(route)
 if FreeProfileV2.has_markers(route):return FreeProfileV2.validation_error(route)
 if FreeProfile.has_markers(route):return FreeProfile.validation_error(route)
 if PirateOffer.has_markers(route) or PirateProtocols.has_markers(route):
  var pirate_error:String=pirate_production_route_error(route)
  if not pirate_error.is_empty():return pirate_error
 return RecoveryPresentationCaps.route_error(route)

func _show_save_recovery() -> void:
 var recovery:=Label.new();recovery.text=economy.load_notice;recovery.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;recovery.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;recovery.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 recovery.add_theme_font_override("font",preload("res://assets/fonts/ChineseSans.otf"));recovery.add_theme_font_size_override("font_size",22);add_child(recovery);recovery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 set_process(false);set_process_input(false);set_process_unhandled_input(false);set_process_unhandled_key_input(false)

func _starter() -> void:
 design=FreeProfileV2.starter_design();launcher=FreeProfileV2.starter_launcher()

func part(id:int,type:String,x:int,y:int) -> Dictionary:
 var order:Dictionary=economy.active_contract()
 var version:String=economy.flight_mode if order.is_empty() else str(order.get("control_version","autonomous-v5"))
 return WorkshopParts.new_part(id,type,x,y,active_design(),assembly_mode=="launcher",version in PILOT_VERSIONS,version)

func workshop_control_version() -> String:
 var order:Dictionary=economy.active_contract()
 return economy.flight_mode if order.is_empty() else str(order.get("control_version","autonomous-v5"))

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
 entry_shop_walk=_title_shop_walk_allowed()
 var world_factory:Script=load("res://scripts/title_entry_world_v1.gd") if entry_shop_walk else WorldView
 if world_factory==null:
  economy.review_load_blocked=true;economy.load_notice="店铺资源暂时无法读取。存档已保留。";return
 world=world_factory.new();world.catalog=catalog;world.screen_mapper=view_container
 if clerk_pose_bootstrap_script!=null:
  if not world.configure_clerk_pose_bootstrap(clerk_pose_bootstrap_script):
   economy.review_load_blocked=true;economy.load_notice="店铺暂时无法打开。存档已保留。";return
 if entry_shop_walk and not world.configure_title_shop_entry(Vector2(600,496),"focus_counter"):
  economy.review_load_blocked=true;economy.load_notice="店铺暂时无法打开。存档已保留。";return
 view.add_child(world)
 if not str(world.get("_clerk_pose_setup_error")).is_empty():
  economy.review_load_blocked=true;economy.load_notice="店铺暂时无法打开。存档已保留。";return
 world.loading_complete.connect(_on_cargo_loading_complete)
 if world.has_signal("shop_navigation_arrived"):world.shop_navigation_arrived.connect(_on_shop_navigation_arrived)
 view_container.display.gui_input.connect(_viewport_input)
 hud=GameHUD.new();add_child(hud);hud.action_requested.connect(_action)
 hud.accelerator_preview_changed.connect(world.present_accelerator_preview)
 hud.shield_preview_changed.connect(world.present_shield_preview)
 world.protected_bird_hud_root=hud.root
 dialogue=DialoguePanel.new();add_child(dialogue)
 dialogue.finished.connect(_on_dialogue_finished)
 dialogue.modal_changed.connect(_on_dialogue_modal_changed)
 dialogue.audio_settings_changed.connect(_on_dialogue_audio_settings)
 loading_overlay=LoadingSceneOverlay.new();add_child(loading_overlay)
 loading_overlay.skip_requested.connect(_skip_loading_scene)
 view_container.art_frame_changed.connect(_on_art_frame_changed)
 workshop_input.bind(self)
 _on_art_frame_changed(view_container.display_rect)
 review_phone=CustomerReviewPhone.new();add_child(review_phone)
 review_phone.set_existing_theme(hud.root.theme)
 review_phone.modal_changed.connect(_on_review_phone_modal_changed)
 review_phone.page_changed.connect(_on_review_phone_page_changed)
 _layout_review_phone()
 investigation=ShopInvestigation.new();add_child(investigation);investigation.bind(self)
 courier_input=CourierInput.new();add_child(courier_input);courier_input.bind(self)

func _on_art_frame_changed(rect:Rect2) -> void:
 if (_review_phone_is_open() or _investigation_is_open()) and is_instance_valid(courier_input):courier_input.quarantine()
 _layout_review_phone(rect)
 workshop_input.cancel()
 if is_instance_valid(loading_overlay):loading_overlay.set_art_frame(rect)
 if is_instance_valid(hud) and hud.has_method("set_art_frame"):
  hud.set_art_frame(rect)
  if not hud.state.is_empty():hud.render(hud.state)
 if workshop_input.host!=null:workshop_input.after_render()

func _investigation_is_open() -> bool:
 return is_instance_valid(investigation) and investigation.is_open()

func _close_investigation() -> void:
 if is_instance_valid(investigation):investigation.close()

func _review_phone_is_open() -> bool:
 return _review_phone_owner!=0 and is_instance_valid(review_phone) and review_phone.is_open()

func _can_open_review_phone() -> bool:
 return not _investigation_is_open() and not economy.review_load_blocked and not closing and page=="hub" and is_instance_valid(courier_input) and courier_input.focused and is_instance_valid(hud) and not hud.is_blocking_modal() and not _dialogue_is_open() and not _loading_scene_active() and _pending_story.is_empty() and is_instance_valid(world) and world.can_open_review_phone()

func _can_keep_review_phone() -> bool:
 return not _investigation_is_open() and not economy.review_load_blocked and not closing and page=="hub" and is_instance_valid(courier_input) and courier_input.focused and not hud.is_blocking_modal() and not _dialogue_is_open() and not _loading_scene_active() and _pending_story.is_empty() and world.review_phone_owned_by(_review_phone_owner)

func _layout_review_phone(rect:Rect2=Rect2()) -> void:
 if not is_instance_valid(review_phone) or not is_instance_valid(view_container):return
 var frame:Rect2=rect if rect.has_area() else view_container.display_rect
 var clerk_screen:Vector2=world._screen_point(world.clerk.position) if is_instance_valid(world) else frame.get_center()
 review_phone.set_art_frame(frame,clerk_screen)

func _open_review_phone() -> bool:
 if _review_phone_owner!=0 or not _can_open_review_phone():return false
 var owner:int=review_phone.get_instance_id()
 # Acquire the clerk before exposing any focusable phone control. No source
 # receipt, pending fact, or raw review-state dictionary reaches the view.
 if not world.acquire_review_phone(owner):return false
 _review_phone_owner=owner
 workshop_input.cancel();courier_input.quarantine();_clear_pilot_input()
 _layout_review_phone()
 if not review_phone.open_from_player(economy.customer_reviews(),economy.day):
  _release_review_phone();return false
 courier_input.synchronize()
 return true

func _back_review_phone() -> void:
 if is_instance_valid(review_phone) and review_phone.is_open():review_phone.back()

func _close_review_phone() -> void:
 if is_instance_valid(review_phone) and review_phone.is_open():review_phone.close_phone()
 else:_release_review_phone()

func _on_review_phone_page_changed(phone_page:String) -> void:
 if not _review_phone_is_open() or not is_instance_valid(world):return
 # Page navigation changes finger intent, never the existing phone owner.
 world.set_review_phone_page(_review_phone_owner,phone_page)

func _on_review_phone_modal_changed(open:bool) -> void:
 if not open:_release_review_phone()

func _release_review_phone() -> void:
 if _review_phone_owner==0:return
 var owner:int=_review_phone_owner;_review_phone_owner=0
 if is_instance_valid(world):world.release_review_phone(owner)
 workshop_input.cancel();_clear_pilot_input()
 if is_instance_valid(courier_input):
  courier_input.quarantine()
  if courier_input.is_inside_tree():courier_input.synchronize()

func active_design() -> Array:return design if assembly_mode=="craft" else launcher
func selected_part() -> Dictionary:
 for p in active_design():
  if int(p.id)==selected_id:return p
 return {}
func _installed_count(type:String) -> int:
 return (design+launcher).filter(func(p):return str(p.type)==type).size()

func _selected_part_presentation(specs:Dictionary,presentation_version:String) -> Dictionary:
 var capacity_scale:float=AscentProfile.BATTERY_MULTIPLIER if presentation_version in ASCENT_VERSIONS else 1.0
 var chosen=selected_part().duplicate(true)
 if not chosen.is_empty():
  chosen.spec=specs.get(chosen.type,catalog[chosen.type]);chosen.schema=PartsDB.parameter_schema(chosen.type);chosen.controls=PartsDB.controls(chosen.type);chosen.default_behavior=chosen.controls.default_behavior
  if chosen.type=="shield" and presentation_version in EXTREME_VERSIONS:chosen.default_behavior="未接线自动保护同一存活结构；撞击吸收需要实际余电，不会阻止翻转或结构过载。"
  if chosen.type=="shield" and presentation_version in FreeProtocols.SHIELD_VERSIONS:chosen.default_behavior="未接线自动启用；只保护同电路且格心在圈内的部件，需实际余电。撞击动量仍会传入结构。"
  if chosen.type=="battery" and capacity_scale>1:
   var capacity:float=float(catalog.battery.energy)*capacity_scale*(1.0+.15*economy.research)
   chosen.default_behavior="电芯容量 %.0f J；向同一结构供电。"%capacity
 return chosen

func refresh_workshop_selection() -> void:
 # Only the installed-part mouse press uses this path. The design and all
 # non-selection HUD data are unchanged; actual edits still use render().
 world.show_workshop_selection(selected_id)
 var data:Dictionary=hud.state.duplicate(true)
 data.selectedpart=_selected_part_presentation(data.catalog,str(data.control_version))
 # Preserve the existing inspector, palette-close and UI-focus behavior.
 hud.render(data)
 workshop_input.after_render()

func render() -> void:
 if economy.review_load_blocked and not is_instance_valid(world):return
 world.set_meta("assembly_context",assembly_mode)
 world.set_workshop_tier(economy.workshop_tier)
 world.reduced_motion=bool(settings.get("reduced_motion",false))
 world.motion_blur_enabled=bool(settings.get("motion_blur",true))
 var order=economy.active_contract().duplicate(true)
 if page=="flight":order=flight_order.duplicate(true)
 if not order.is_empty():order.accepted=order.get("status","")=="accepted"
 var presentation_version:String=str(order.get("control_version",economy.flight_mode))
 var specs:Dictionary={};var stock:Dictionary={}
 var capacity_scale:float=AscentProfile.BATTERY_MULTIPLIER if presentation_version in ASCENT_VERSIONS else 1.0
 for type in catalog:
  if type=="cargo":continue
  specs[type]=catalog[type].duplicate(true);specs[type].launcher_compatible=WorkshopParts.compatible(type,true,presentation_version)
  if type=="battery":specs[type].energy=float(specs[type].energy)*capacity_scale
  if type=="shield" and presentation_version in EXTREME_VERSIONS:specs[type].description="可防御攻击，也可吸收最多 65% 撞击损伤。每个护盾每步最多吸收 24 HP，每 HP 消耗 1.5 J；撞击动量仍会传入结构。"
  if type=="shield" and presentation_version in FreeProtocols.SHIELD_VERSIONS:specs[type].description="同电路受击格心在局部圈内才可吸收攻击或部分撞击。分裂后保护面积随材料减少；仍按实际吸收量付电，按受击格判定，不在圆边缘拦截射线。"
  stock[type]=int(economy.inventory.get(type,0))-_installed_count(type) if page=="workshop" else int(economy.inventory.get(type,0))
 var chosen:Dictionary=_selected_part_presentation(specs,presentation_version)
 var mass:float=0;var energy:float=0
 for p in active_design():
  mass+=float(catalog[p.type].get("mass",0))*(float(order.get("weight",1)) if p.type=="cargo" else 1.0)
  if p.type=="battery":energy+=float(catalog[p.type].get("energy",0))*capacity_scale*(1.0+.15*economy.research)
 var hint="去柜台接一单。"
 if not order.is_empty():hint="去工位准备出发，也可以先免费试飞。"
 if economy.phase=="night":hint="补好库存，准备明天。"
 if economy.jobs_today>0 and order.is_empty():hint="接下一单，或收工。"
 if page!="flight":
  world.leave_flight();world.focus(page);world.show_design(active_design() if page=="workshop" else design,selected_id if page=="workshop" else -1)
  world.update_shop_state({"phase":economy.phase,"day":economy.day,"contracts":economy.contracts,"active_contract_id":economy.active_contract_id,"research":economy.research,"inventory":economy.inventory,"installed":design+launcher,"cargo_loaded":economy.is_cargo_loaded(),"handoff_released":_cargo_handoff_released()})
 var data={"daily_reviews_enabled":true,"mode":page,"day":economy.day,"credits":economy.credits,"reputation":economy.reputation,"phase":economy.phase,"hint":hint,"activeorder":order,"contracts":economy.available_contracts(),"catalog":specs,"inventory":stock,"chosen_type":chosen_type,"assembly_mode":assembly_mode,"selectedpart":chosen,"parts":active_design(),"ship_stats":{"parts":active_design().size(),"mass":mass,"energy":energy},"settings":settings,"trial":trial,"report":report,"hotspots":world.hotspot_positions(),"cancel_warning":"退回已接委托会失去 1 点声望；这份委托今天不会重新出现。","upgrades":[{"id":"battery","name":"校准充电台 · 储能 +15%","cost":economy.research_cost(),"disabled":economy.research>=3 or economy.credits<economy.research_cost()}]}
 # Read-only progress from the economy owner, including post-settlement state.
 data.delivery_chapter_status=economy.delivery_chapter_status()
 # The finished frozen order remains presentation-only after active contract settlement.
 if page=="report":data.report_order=flight_order.duplicate(true)
 var next_tier:int=WorkshopProfile.next_tier(economy.workshop_tier)
 data.workshop={"tier":economy.workshop_tier,"size":WorkshopProfile.grid_size(economy.workshop_tier),"next_tier":next_tier,"next_size":WorkshopProfile.grid_size(next_tier),"cost":economy.workshop_upgrade_cost()}
 # Pure preflight presentation; never prevents a free assembly or launch.
 if page=="workshop" and assembly_mode=="craft":data.power_status=WorkshopPower.analyze(design)
 var outside:int=_outside_workshop_count(active_design())
 if outside>0:data.ship_stats.warning="已保留 %d 个旧方案格。移回开放区，或收工后扩建。"%outside
 data.save_exit_available=_flight_save_exit_available()
 data.control_version=presentation_version
 data.launch_settings=_flight_launch_settings.duplicate(true) if page=="flight" else _launch_settings()
 data.launch_preview=_delivery_launch_preview(order) if _delivery_version(presentation_version) and page=="workshop" else {}
 data.energy_tariff=economy.energy_tariff(order if not order.is_empty() else {"control_version":economy.flight_mode})
 data.wormhole_preflight=_wormhole_preflight(order)
 data.counter_customer_id=world.counter_customer_id()
 data.free_order_upgrade=_free_order_upgrade_state()
 data.shop_action_availability=_shop_action_availability()
 data.day_basic_supply=bool(economy.can_buy_basic_during_day()) if economy.has_method("can_buy_basic_during_day") else false
 hud.render(data)
 _sync_loading_scene_ui()
 workshop_input.after_render()

func _launch_settings(value:Variant=null) -> Dictionary:
 var source:Variant=settings.get("launch_settings",{}) if value==null else value
 if not source is Dictionary:source={}
 var angle:Variant=source.get("angle_degrees",0.0)
 var power:Variant=source.get("power_fraction",1.0)
 return {"angle_degrees":clampf(float(angle),0.0,90.0) if (angle is int or angle is float) and is_finite(float(angle)) else 0.0,"power_fraction":clampf(float(power),0.0,1.0) if (power is int or power is float) and is_finite(float(power)) else 1.0}

func _delivery_launch_preview(order:Dictionary) -> Dictionary:
 var route:Dictionary=order.duplicate(true) if not order.is_empty() else DeliveryProfile.route()
 if not _delivery_version(route.get("control_version")) or not FreeProtocols.route_error(route).is_empty():return {}
 var selected:Dictionary=_launch_settings()
 var key:String=JSON.stringify([design,launcher,route,selected],"",true,true)
 if key==_delivery_preview_key:return _delivery_preview_cache.duplicate(true)
 var preview_sim=_simulation_for_version(str(route.control_version))
 preview_sim.configure(design.duplicate(true),launcher.duplicate(true),route,int(route.get("seed",economy.day*100)))
 if not str(preview_sim.free_route_error).is_empty():return {}
 _delivery_preview_key=key
 _delivery_preview_cache=preview_sim.preview_launcher(float(selected.angle_degrees),float(selected.power_fraction))
 return _delivery_preview_cache.duplicate(true)

func _release_delivery_launcher() -> bool:
 if not _delivery_version(flight_order.get("control_version")) or _delivery_launch_released or sim.status!="running":return true
 var released:Dictionary=sim.release_launcher(float(_flight_launch_settings.angle_degrees),float(_flight_launch_settings.power_fraction))
 if not bool(sim.launch_released):
  pilot_resume_blocked=true;_set_paused(true);notify(str(released.get("warning","发射尚未完成，配送记录已保留。")));return false
 _delivery_launch_released=true
 return true

func _wormhole_preflight(route:Dictionary) -> Dictionary:
 var version:String=str(route.get("control_version",""))
 if not version in [WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION] or not economy.route_validation_error(route).is_empty():return {}
 if not _bird_design_error(route,design,launcher).is_empty():return {}
 if design.filter(func(p):return str(p.type)=="cargo").size()!=1:return {}
 # The launch graph joins orthogonally adjacent installed cells. Count that
 # exact starting graph; a later split can change the actual transit bill.
 var remaining:Dictionary={};var total_mass:float=0.0
 for p in design:
  var kind:String=str(p.type)
  var mass:float=float(catalog[kind].mass)*(maxf(.1,float(route.get("weight",1.0))) if kind=="cargo" else 1.0)
  remaining[Vector2i(int(p.x),int(p.y))]={"mass":mass,"type":kind};total_mass+=mass
 var bodies:int=0;var largest:float=0.0
 while not remaining.is_empty():
  var start:Vector2i=remaining.keys()[0];var queue:Array[Vector2i]=[start];var component:Dictionary={}
  component[start]=remaining[start];remaining.erase(start);bodies+=1
  while not queue.is_empty():
   var at:Vector2i=queue.pop_back()
   for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var neighbor:Vector2i=at+direction
    if remaining.has(neighbor):component[neighbor]=remaining[neighbor];remaining.erase(neighbor);queue.append(neighbor)
  var mass:float=0.0;var center:Vector2=Vector2.ZERO
  for cell in component:
   mass+=float(component[cell].mass);center+=Vector2(cell)*float(component[cell].mass)
  if mass>0.0:center/=mass
  for cell in component:largest=maxf(largest,Vector2(cell).distance_to(center)+(.48 if str(component[cell].type)=="drill" else .43))
 if bodies==0:return {}
 var quote:Dictionary=BirdProfile.transit_quote(BirdOffer.canonical_route(route),total_mass,bodies) if version==BirdProfile.CONTROL_VERSION else WormholeProfile.transit_quote(route,total_mass,bodies)
 if bool(quote.get("ok",false)):
  quote.starting_body_diameter_m=largest*2.0
  quote.fits_starting_outline=largest*2.0<=float(quote.max_centered_body_diameter_m)
 return quote

func _free_upgrade_context_available(kind:String="available") -> bool:
 if economy.review_load_blocked or closing or entry_defer_controls or pilot_resume_blocked or _free_restore_active:return false
 if page not in ["hub","contracts","workshop","report","supply"] or not economy.in_flight.is_empty():return false
 if kind!="parts" and (economy.phase=="night" or page=="supply"):return false
 if _review_phone_owner!=0 or _review_phone_is_open() or _investigation_is_open() or _dialogue_is_open() or _loading_scene_active():return false
 if not _pending_story.is_empty() or not _active_story.is_empty() or _finalizing_cargo_for_launch:return false
 if not is_instance_valid(hud) or hud.is_blocking_modal() or not is_instance_valid(world):return false
 if is_instance_valid(courier_input) and not courier_input.focused:return false
 # Project the existing world-owner guard across drawers without moving anyone.
 return world.can_request_shop_navigation("focus_workbench" if kind=="parts" else "focus_counter",page!="hub")

func _free_order_upgrade_preview(kind:String) -> Dictionary:
 if kind=="delivery":
  var transition:Dictionary=economy.delivery_upgrade_preview(design,launcher,settings).duplicate(true)
  transition.kind=kind;return transition
 if kind in ["parts","force"]:
  var transition:Dictionary=economy.parts_retirement_preview(design,launcher,settings) if kind=="parts" else economy.force_offer_upgrade_preview(design,launcher,settings)
  transition.kind=kind;return transition
 if kind=="accepted":
  var accepted:Dictionary=economy.accepted_free_swap_preview().duplicate(true)
  accepted.kind=kind;return accepted
 if kind!="available":return {}
 var preview:Dictionary=economy.free_offer_upgrade_preview().duplicate(true)
 var originals:Array=[]
 for order in economy.contracts:
  if str(order.get("contract_id","")) in preview.get("contract_ids",[]):originals.append(order.duplicate(true))
 preview.kind=kind
 preview.order_sha256=JSON.stringify(originals,"",true,true).sha256_text()
 return preview

func _free_order_upgrade_state() -> Dictionary:
 _transition_previews={}
 for kind in ["available","accepted","force","parts","delivery"]:
  if _free_upgrade_context_available(kind):_transition_previews[kind]=_free_order_upgrade_preview(kind)
 return _transition_previews.duplicate(true)

func _request_free_order_upgrade(kind:String) -> void:
 if not _free_upgrade_context_available(kind):return
 var preview:Dictionary=_free_order_upgrade_preview(kind)
 if not bool(preview.get("available",false)):return
 workshop_input.cancel()
 _pending_free_order_upgrade=preview.duplicate(true)
 if not hud.open_free_order_upgrade(preview):_pending_free_order_upgrade.clear();return
 if is_instance_valid(courier_input):courier_input.quarantine()

func _confirm_free_order_upgrade(payload:Variant) -> void:
 var pending:Dictionary=_pending_free_order_upgrade.duplicate(true)
 _pending_free_order_upgrade.clear()
 if pending.is_empty() or not payload is Dictionary or payload!=pending:return
 if not _free_upgrade_context_available(str(pending.get("kind",""))):notify("现在暂时不能升级，请稍后再试。");return
 var current:Dictionary=_free_order_upgrade_preview(str(pending.get("kind","")))
 if not bool(current.get("available",false)) or current!=pending:
  notify("委托状态已变化，请重新查看。");return
 var kind:String=str(pending.kind)
 var accepted:bool=kind=="accepted"
 var result:Dictionary={}
 if kind=="delivery":result=economy.upgrade_delivery_mode_and_save(str(pending.confirmation_token),design,launcher,settings)
 elif kind=="parts":result=economy.retire_legacy_parts_and_save(str(pending.confirmation_token),design,launcher,settings)
 elif kind=="force":result=economy.upgrade_available_force_offers_and_save(str(pending.confirmation_token),design,launcher,settings)
 elif accepted:result=economy.swap_accepted_legacy_for_free_and_save(str(pending.contract_id),str(pending.order_sha256),design,launcher,settings)
 else:result=economy.upgrade_available_free_offers_and_save(design,launcher,settings)
 if not bool(result.get("ok",false)):notify(str(result.get("message","换单未完成，原委托已保留。")));return
 if not bool(result.get("changed",false)):return
 if kind=="parts":
  # Economy committed the detached candidate. Only now replace editor aliases;
  # old undo entries must not resurrect retired stock or signal wiring.
  design=result.design;launcher=result.launcher;settings=result.settings
  undo_history.clear();workshop_input.cancel();workshop_input.controller_cancel()
  selected_id=-1;chosen_type="beam";_allocate_ids()
  sim=null;trial=false;report.clear();_clear_pilot_input()
  hud.reset_free_order_view()
 if accepted:
  # Clear only transient previews AFTER the atomic save. Do not accept again,
  # restore/repack cargo, replay dialogue, touch receipts or restart handoff.
  _clear_pilot_input();sim=null;trial=false;report.clear();flight_order.clear()
  pilot_timeline=PilotTimeline.new();pilot_completed_ticks=0
  frame_accum=0.0;checkpoint=0.0;launch_countdown=0.0;completion_countdown=-1.0
  launch_age=0.0;launch_transfer_remaining=0.0;launch_sfx_played=false
  paused=false;speed=1.0;slow_simulation=false;_flight_modal_was_open=false;_paused_before_modal=false
  hud.reset_free_order_view()
  var fresh:Dictionary=economy.active_contract()
  if str(fresh.get("contract_id",""))==str(result.get("contract_id","")):page="workshop"
 render()
 notify(str(result.get("message","委托已更换。")))
 if is_instance_valid(courier_input):courier_input.quarantine()

func is_shop_action_available(action:String) -> bool:
 # Only actions with a real clerk/proximity guard participate. Workbench,
 # supplies, help, settings and loading skip keep their independent rules.
 if action=="customer_reviews":return _can_open_review_phone()
 if action in ["upgrade_force_offers","retire_legacy_parts","upgrade_delivery_offers"]:
  var kind:String="parts" if action=="retire_legacy_parts" else "delivery" if action=="upgrade_delivery_offers" else "force"
  # Per-frame proximity refresh never reads files or rebuilds migration plans.
  return _free_upgrade_context_available(kind) and bool(_transition_previews.get(kind,{}).get("available",false))
 if action in ["upgrade_free_offers","swap_accepted_free"]:
  return _free_upgrade_context_available() and bool(_free_order_upgrade_preview("accepted" if action=="swap_accepted_free" else "available").get("available",false))
 if action not in ["focus_counter","next_contract","accept_contract"]:return true
 if economy.review_load_blocked or closing or page=="flight" or not is_instance_valid(world):return false
 if _review_phone_is_open() or _investigation_is_open() or _dialogue_is_open() or _loading_scene_active():return false
 if is_instance_valid(hud) and hud.is_blocking_modal():return false
 if action=="accept_contract":return world.is_at_shop_counter() and not world.counter_customer_id().is_empty()
 return world.can_request_shop_navigation("focus_counter",page!="hub")

func _shop_action_availability() -> Dictionary:
 var result:Dictionary={}
 for action in ["focus_counter","next_contract","accept_contract","customer_reviews","upgrade_free_offers","swap_accepted_free","upgrade_force_offers","retire_legacy_parts","upgrade_delivery_offers"]:
  result[action]=is_shop_action_available(action)
 return result

func _sync_shop_action_availability() -> void:
 if is_instance_valid(hud) and is_instance_valid(world):hud.update_shop_action_availability(_shop_action_availability(),world.counter_customer_id())

func _action(action:String,payload:Variant) -> void:
 if closing:return
 if action=="save_and_quit":
  if page=="flight" and not _flight_save_exit_available():return
  _request_save_and_quit();return
 if action=="save_progress":
  if save_game():notify("进度已保存。")
  elif not _last_save_error.is_empty():notify(_last_save_error)
  return
 if action=="test_sound":_test_sound();return
 if action=="cancel_free_upgrade":_pending_free_order_upgrade.clear();return
 if action=="confirm_free_upgrade":_confirm_free_order_upgrade(payload);return
 if action in ["upgrade_free_offers","swap_accepted_free","upgrade_force_offers","retire_legacy_parts","upgrade_delivery_offers"]:
  _request_free_order_upgrade({"upgrade_free_offers":"available","swap_accepted_free":"accepted","upgrade_force_offers":"force","retire_legacy_parts":"parts","upgrade_delivery_offers":"delivery"}[action]);return
 if is_instance_valid(hud) and hud.free_order_upgrade_open():return
 if _review_phone_is_open() or _investigation_is_open():return
 if action==ShopInvestigation.ACTION:
  if is_instance_valid(investigation):investigation.begin()
  return
 if action=="customer_reviews":_open_review_phone();return
 if economy.review_load_blocked:notify(economy.load_notice);return
 if action=="accept_contract":
  for order in economy.contracts:
   if str(order.get("contract_id",""))==str(payload):
    var unavailable:String=economy.route_preflight_error(order)
    if not unavailable.is_empty():notify(unavailable);return
 workshop_input.cancel()
 if _dialogue_is_open():return
 if action=="skip_loading_scene":_skip_loading_scene();return
 if _loading_scene_active() and not action in ["cancel_contract","settings"]:return
 if action in ["focus_counter","next_contract","accept_contract"] and not is_shop_action_available(action):return
 if action=="accept_contract" and not world.has_counter_customer(str(payload)):return
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
  "focus_launch":navigate("workshop");notify("准备好即可配送；试飞可选。")
  "close_drawer":navigate("hub")
  "help":navigate("help")
  "accept_contract":
   var result=economy.accept_contract_and_save(str(payload),design,launcher,settings,_prepare_shop_save)
   if _shop_result_ok(result):
    navigate("hub");_request_story(str(payload),"accept");_show_shop_result(result)
  "decline_contract":
   var result:Dictionary=economy.decline_available_and_save(str(payload),design,launcher,settings,_prepare_shop_save)
   if _shop_result_ok(result):render();_show_shop_result(result)
  "cancel_contract":
   var result:Dictionary=economy.cancel_accepted_and_save(design,launcher,settings,_prepare_shop_save)
   if _shop_result_ok(result):navigate("hub");_show_shop_result(result)
  "select_catalog":chosen_type=str(payload);selected_id=-1;render()
  "assembly_mode":assembly_mode=str(payload);selected_id=-1;render()
  "fit_workshop":workshop_input.fit()
  "undo":undo_assembly()
  "rotate_part":rotate_part()
  "remove_part":remove_part()
  "set_launch_settings":
   if page!="workshop" or not _delivery_version(workshop_control_version()) or not payload is Dictionary:return
   var previous:Dictionary=_launch_settings()
   settings.launch_settings=_launch_settings(payload)
   if not save_game():settings.launch_settings=previous
   render()
  "set_param":
   var p=selected_part()
   if not p.is_empty() and int(p.id)==int(payload.get("id",-1)):_remember_assembly();p.param=PartsDB.sanitize_parameter(p.type,float(payload.value));save_game();world.committed_edit("tune",p);hud.sync_workshop_preview(active_design(),p)
  "set_input":
   var p=selected_part()
   if not p.is_empty() and int(p.id)==int(payload.get("id",-1)) and str(payload.get("key","")) in ["input_a","input_b","target"]:_remember_assembly();p[str(payload.key)]=int(payload.source);world.set_meta("assembly_context",assembly_mode);world.show_design(active_design(),selected_id);save_game();world.committed_edit("tune",p);hud.sync_workshop_preview(active_design(),p)
  "save_blueprint":save_blueprint()
  "load_blueprint":load_blueprint()
  "trial","trial_retry":start_flight(true)
  "dispatch":start_flight(false)
  "pause":_set_paused(not paused)
  "set_speed":speed=1.0 if _is_pilot_flight() else clampf(float(payload),1,4)
  "abort":_request_abort_flight()
  "close_day","finish_day":
   var result:Dictionary=economy.close_day_and_save(design,launcher,settings,_prepare_shop_save)
   if _shop_result_ok(result):navigate("supply");_show_shop_result(result)
  "next_day":
   if _result_ok(economy.next_day_and_save(design,launcher,settings)):navigate("hub")
  "buy":
   if catalog.has(str(payload)):
    var result:Dictionary=economy.buy_part_and_save(str(payload),catalog[str(payload)],design,launcher,settings,_prepare_shop_save)
    if _shop_result_ok(result):render();_show_shop_result(result,"零件已放到货架上。")
  "upgrade":
   var result:Dictionary=economy.research_upgrade_and_save(design,launcher,settings,_prepare_shop_save)
   if _shop_result_ok(result):render();_show_shop_result(result)
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
   elif payload.has("volume"):settings.volume=clampf(float(payload.volume),0.0,1.0);_apply_audio_volume();save_game()

func _on_shop_navigation_arrived(action_id:String) -> void:
 if entry_defer_controls:return
 if page!="hub" or _dialogue_is_open() or _loading_scene_active() or hud.is_blocking_modal():return
 _shop_navigation_arriving=true;_action(action_id,null);_shop_navigation_arriving=false

func _shop_result_ok(result:Dictionary) -> bool:
 # Report rollback errors immediately; successful shop messages must wait
 # until navigation/story setup/render has finished clearing the old HUD mode.
 if bool(result.get("ok",false)):return true
 return _result_ok(result)

func _show_shop_result(result:Dictionary,fallback:String="") -> void:
 var message:String=str(result.get("message",fallback))
 if not message.is_empty():notify(message)

func _result_ok(result:Dictionary) -> bool:
 if result.has("message"):notify(str(result.message))
 return bool(result.get("ok",false))
func notify(message:String) -> void:if is_instance_valid(hud):hud.toast(message)
func navigate(target:String) -> void:
 _close_investigation()
 _close_review_phone()
 if economy.review_load_blocked:return
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
  loading_overlay.update_state(world.loading_ui_state())
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
 if _review_phone_is_open() or _pending_story.is_empty() or _dialogue_is_open() or _loading_scene_active() or page=="flight" or pilot_resume_blocked or closing:return
 if is_instance_valid(hud) and hud.is_blocking_modal():return
 var cid:String=str(_pending_story.contract_id);var beat:String=str(_pending_story.beat)
 if beat=="accept" and (economy.active_contract_id!=cid or str(economy.active_contract().get("status",""))!="accepted"):
  _pending_story.clear();return
 var conversation:Dictionary=economy.story_conversation(cid,beat)
 if conversation.is_empty():_pending_story.clear();return
 var counter_id:String=cid if beat=="accept" else str(_pending_story.get("counter_contract_id",""))
 if beat=="return" and world.counter_customer_id(false)!=counter_id:
  _pending_story.clear();return
 if beat!="result":
  # A remote paid receipt needs no imaginary visitor. In-person beats require
  # the matching real customer to arrive before claiming the clerk or saving.
  if not world.has_counter_customer(counter_id):return
  if not world.prepare_counter_interaction():return
 # A story is presented only after the matching identity and paid result are
 # durable. A failed disk write is attempted once, not every rendered frame.
 if _story_save_attempted:return
 _story_save_attempted=true
 if not save_game():return
 _clear_pilot_input()
 _active_story={"contract_id":cid,"counter_contract_id":counter_id if beat!="result" else "","dialogue_id":str(conversation.dialogue_id),"beat":beat}
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
  var present_id:String=world.counter_customer_id(false)
  if present_id.is_empty():return
  var present_actor:Dictionary=economy.story_actor(present_id)
  for conversation in pending:
   # Old paid story identity may revisit under a new order ID. Never attach
   # it to an absent/departed actor or to the next unrelated queue member.
   if str(conversation.get("actor",{}).get("appearance_id",""))!=str(present_actor.get("appearance_id","")):continue
   _pending_story={"contract_id":str(conversation.contract_id),"beat":"return","counter_contract_id":present_id};_story_save_attempted=false
   _try_pending_story();return

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
 if open:_close_investigation();_close_review_phone()
 if is_instance_valid(world):world.set_dialogue_active(open,str(_active_story.get("counter_contract_id","")))
 if open:_clear_pilot_input();workshop_input.cancel()

func _on_dialogue_audio_settings(volume:float,muted:bool) -> void:
 settings.dialogue_volume=clampf(volume,0.0,1.0);settings.dialogue_muted=muted;save_game()

func _viewport_input(event:InputEvent) -> void:
 if _review_phone_is_open() or _investigation_is_open():return
 workshop_input.handle(event)
func rotate_part() -> void:
 if _review_phone_is_open() or _investigation_is_open():return
 workshop_input.cancel()
 if _loading_scene_active():return
 var p=selected_part()
 if not p.is_empty():_remember_assembly();p.rot=(int(p.rot)+1)%4;render();save_game();world.committed_edit("rotate",p)
func remove_part() -> void:
 if _review_phone_is_open() or _investigation_is_open():return
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
 economy.designs["workbench"]={"design":design.duplicate(true),"launcher":launcher.duplicate(true)}
 if save_game():notify("图纸已保存在工位。")
 else:notify(_last_save_error if not _last_save_error.is_empty() else "图纸未能保存，请重试保存。")
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

func _bird_design_error(route:Dictionary,craft:Array,pad:Array) -> String:
 if str(route.get("control_version",""))==BirdProfile.CONTROL_VERSION and not BirdDesign.validation_error(craft,pad).is_empty():
  return "这份装配记录不完整，暂时无法出发。"
 return ""

func start_flight(is_trial:bool) -> void:
 if _review_phone_is_open() or _investigation_is_open():return
 if economy.review_load_blocked:return
 if _dialogue_is_open():return
 if pilot_resume_blocked:notify("此配送记录无法安全恢复，原记录已保留。");return
 if page=="flight":return
 if economy.active_contract().is_empty():notify("先去柜台确认一份委托。试飞也会使用这份货物的重量。 ");return
 var route_error:String=economy.route_preflight_error(economy.active_contract())
 if not route_error.is_empty():notify(route_error);return
 var design_error:String=_bird_design_error(economy.active_contract(),design,launcher)
 if not design_error.is_empty():notify(design_error);return
 # Pirate preflight validates the complete typed assembly before the legacy
 # helpers access p.type. Malformed entries must be a clean launch rejection.
 if PirateProtocols.is_version(economy.active_contract().get("control_version")):
  _start_pirate_flight(is_trial);return
 if design.filter(func(p):return str(p.type)=="cargo").size()!=1:notify("飞行器必须带上这一件客户货物。");return
 if not economy.missing_parts(design,launcher).is_empty():notify("方案超过了实际库存，请先调整。");return
 if not _ensure_cargo_loaded_for_launch():return
 var route=economy.trial_route()
 if not is_trial:
  var result=economy.begin_dispatch(design,launcher,_launch_settings())
  if not _result_ok(result):return
  if not save_game():
   economy.active_contract().status="accepted";economy.in_flight={};return
  route=economy.in_flight.route.duplicate(true);route.seed=economy.in_flight.seed
 _flight_launch_settings=_launch_settings() if is_trial else _launch_settings(economy.in_flight.get("launch_settings",{}))
 _configure_flight(is_trial,design,launcher,route)

func _prepare_pirate_flight(craft:Array,pad:Array,route:Dictionary) -> Dictionary:
 # Direct callers pass the same typed adapter boundary as replay/preflight.
 var route_error:String=PirateProtocols.route_error(route)
 if not route_error.is_empty():return {"ok":false,"error":route_error}
 # An explicit deterministic seed is part of the prepared dispatch identity.
 if not route.has("seed") or not EconomyDB.replay_seed_error({"seed":route.get("seed")}).is_empty():return {"ok":false,"error":"invalid_pirate_seed"}
 match route.get("control_version"):
  PirateProfile.VERSION:return PirateSimulator.prepare_flight(craft,pad,route,int(route.seed))
  PirateProfileV2.VERSION:return PirateSimulatorV2.prepare_flight(craft,pad,route,int(route.seed))
 return {"ok":false,"error":"unsupported_pirate_control_version"}

func _start_pirate_flight(is_trial:bool) -> void:
 # Loading is a prior visible/durable action. A rejected launch must not
 # fast-forward a scene or save cargo/story state as a side effect.
 if economy.story_mode and not economy.is_cargo_loaded():notify("请先完成装货，再出发。");return
 var craft:Array=design.duplicate(true);var pad:Array=launcher.duplicate(true)
 var route:Dictionary=economy.trial_route().duplicate(true)
 if route.is_empty():notify("这份航线暂时无法出发。");return
 var prepared:Dictionary=_prepare_pirate_flight(craft,pad,route)
 if not bool(prepared.get("ok",false)):
  _pirate_diagnostic=prepared.duplicate(true)
  notify("装置或发射净空不符合这条航线，请检查后重试。");return
 if not economy.missing_parts(craft,pad).is_empty():notify("方案超过了实际库存，请先调整。");return
 var committed:Dictionary={"ok":true}
 if not is_trial:
  committed=economy.begin_prepared_dispatch_and_save(craft,pad,route,settings.duplicate(true),_prepare_shop_save)
  if not _result_ok(committed):return
 # The exact configured object crosses the commit point. No second configure,
 # seed choice, route authoring or physics preparation occurs after payment.
 _present_prepared_flight(is_trial,pad,route,prepared.simulation,false)
 if not str(committed.get("message","")).is_empty():notify(str(committed.message))

func _configure_flight(is_trial:bool,craft:Array,pad:Array,route:Dictionary,resuming:bool=false) -> void:
 var route_error:String=economy.route_preflight_error(route)
 if not route_error.is_empty():
  if resuming:pilot_resume_blocked=true
  notify(route_error);return
 var design_error:String=_bird_design_error(route,craft,pad)
 if not design_error.is_empty():
  if resuming:pilot_resume_blocked=true
  notify(design_error);return
 var version:String=str(route.get("control_version",""))
 if _delivery_version(version) and not resuming:
  _flight_launch_settings=_launch_settings() if is_trial else _launch_settings(economy.in_flight.get("launch_settings",settings.get("launch_settings",{})))
 var next_sim=_simulation_for_version(version)
 if next_sim==null:
  if resuming:pilot_resume_blocked=true
  notify("此配送记录暂时无法继续，原记录已保留。");return
 var physics_route:Dictionary=BirdOffer.canonical_route(route) if version==BirdProfile.CONTROL_VERSION else route
 if PirateProtocols.is_version(version):
  var prepared:Dictionary=_prepare_pirate_flight(craft,pad,route)
  if not bool(prepared.get("ok",false)):
   if resuming:pilot_resume_blocked=true
   _pirate_diagnostic=prepared.duplicate(true);notify("配送暂时无法恢复，原记录已保留。");return
  next_sim=prepared.simulation
 else:next_sim.configure(craft.duplicate(true),pad.duplicate(true),physics_route,int(route.get("seed",economy.day*100)))
 _present_prepared_flight(is_trial,pad,route,next_sim,resuming)

func _present_prepared_flight(is_trial:bool,pad:Array,route:Dictionary,next_sim,resuming:bool) -> void:
 world.set_workshop_tier(economy.workshop_tier)
 trial=is_trial;flight_order=route.duplicate(true);_free_abort_intent=false;pilot_timeline=_timeline_for_route(route);pilot_timeline.reset();pilot_completed_ticks=0;pilot_resume_blocked=false;_clear_pilot_input()
 sim=next_sim
 _delivery_launch_released=resuming if _delivery_version(route.get("control_version")) else false
 _selected_free_device_id=-1
 if _force_input_version(route.get("control_version")):
  var available:Array=sim.selectable_device_ids()
  # Fresh dispatch chooses first tool once. Resume retains the concrete saved
  # id, even when destroyed/detached; never silently select a different tool.
  _selected_free_device_id=int(sim.pilot_device_id) if resuming else (int(available[0]) if not available.is_empty() else -1)
  if not resuming:
   sim.set_free_flight_input(0,0,false,false,_selected_free_device_id,false)
   pilot_timeline.record(0,FreeInputV2.state({},null,_selected_free_device_id))
   sim._refresh_telemetry()
 world.route_distance=float(route.distance);world.route_radius=float(route.get("delivery_radius",5));world.launcher_design=pad.duplicate(true);world.start_flight(sim,resuming);launch_transfer_remaining=0.0 if resuming else world.launch_transfer_duration();page="flight";paused=false;speed=1;frame_accum=0;checkpoint=sim.elapsed if resuming else 0.0;launch_countdown=0 if resuming else launch_transfer_remaining+(.95 if _delivery_version(route.get("control_version")) else .7);launch_age=1.35 if resuming else 0;launch_sfx_played=resuming;slow_simulation=false;completion_countdown=-1;render();_play_music(true)

func _simulation_for_version(version:String):
 match version:
  DeliveryRiftProfileV8.VERSION:return DeliveryRiftSimulatorV8.new()
  DeliveryAscentProfileV8.VERSION:return DeliveryAscentSimulatorV8.new()
  DeliveryProfileV8.VERSION:return DeliverySimulatorV8.new()
  DeliveryRiftProfileV7.VERSION:return DeliveryRiftSimulatorV7.new()
  DeliveryAscentProfileV7.VERSION:return DeliveryAscentSimulatorV7.new()
  DeliveryProfileV7.VERSION:return DeliverySimulatorV7.new()
  DeliveryRiftProfileV6.VERSION:return DeliveryRiftSimulatorV6.new()
  DeliveryAscentProfileV6.VERSION:return DeliveryAscentSimulatorV6.new()
  DeliveryProfileV6.VERSION:return DeliverySimulatorV6.new()
  DeliveryRiftProfile.VERSION:return DeliveryRiftSimulator.new()
  DeliveryAscentProfile.VERSION:return DeliveryAscentSimulator.new()
  DeliveryProfile.VERSION:return DeliverySimulator.new()
  FreeProfileV2.VERSION:return FreeSimulatorV2.new()
  FreeProfile.VERSION:return FreeSimulator.new()
  PirateProfile.VERSION:return PirateSimulator.new()
  PirateProfileV2.VERSION:return PirateSimulatorV2.new()
  BirdProfile.CONTROL_VERSION:return BirdSimulator.new()
  WormholeProfile.CONTROL_VERSION:return WormholeSimulator.new()
  ExtremeProfile.CONTROL_VERSION:return ExtremeSimulator.new()
  AscentProfile.CONTROL_VERSION:return AscentSimulator.new()
  PilotProfile.CONTROL_VERSION:return PilotSimulator.new()
  "":return Simulator.new()
 return null

func _resume_dispatch() -> void:
 if economy.review_load_blocked:return
 var snapshot=economy.in_flight.duplicate(true)
 if not snapshot.get("route") is Dictionary or not snapshot.get("design") is Array or not snapshot.get("launcher") is Array:
  pilot_resume_blocked=true;notify("配送存档不完整，无法继续。原始记录已保留。");return
 # Check protocol before touching seed/time payloads; future versions are opaque.
 var protocol_error:String=economy.replay_protocol_error(snapshot)
 if not protocol_error.is_empty():pilot_resume_blocked=true;notify(protocol_error);return
 var unavailable:String=economy.route_preflight_error(snapshot.route)
 if not unavailable.is_empty():pilot_resume_blocked=true;notify(unavailable);return
 var seed_error:String=economy.replay_seed_error(snapshot)
 if not seed_error.is_empty():pilot_resume_blocked=true;notify(seed_error);return
 var replay_max_ticks:int=FreeTimeline.MAX_TICKS if _free_version(snapshot.route.get("control_version")) else PilotTimeline.MAX_TICKS
 var raw_ticks:Variant=snapshot.get("ticks")
 if not snapshot.has("ticks"):
  var raw_elapsed:Variant=snapshot.get("elapsed",0)
  if not (raw_elapsed is int or raw_elapsed is float) or not is_finite(float(raw_elapsed)) or float(raw_elapsed)<0 or float(raw_elapsed)>float(replay_max_ticks)/60.0:
   pilot_resume_blocked=true;notify("配送存档损坏，无法继续。原始记录已保留。");return
  raw_ticks=roundi(float(raw_elapsed)*60.0)
 if not (raw_ticks is int or raw_ticks is float) or not is_finite(float(raw_ticks)) or float(raw_ticks)!=floor(float(raw_ticks)) or float(raw_ticks)<0 or float(raw_ticks)>replay_max_ticks:
  pilot_resume_blocked=true;notify("配送存档损坏，无法继续。原始记录已保留。");return
 var route:Dictionary=snapshot.route;route.seed=int(snapshot.get("seed",economy.day*100))
 var control_version:String=snapshot.get("control_version",route.get("control_version",""))
 if control_version in PILOT_VERSIONS:route.control_version=control_version
 var route_error:String=economy.route_preflight_error(route)
 if not route_error.is_empty():pilot_resume_blocked=true;notify(route_error+" 原始记录已保留。");return
 if PirateProtocols.is_version(control_version):
  _resume_pirate_dispatch(snapshot,route,int(raw_ticks));return
 if _free_version(control_version):
  _resume_free_dispatch(snapshot,route,int(raw_ticks));return
 _configure_flight(false,snapshot.design,snapshot.launcher,route,true)
 if pilot_resume_blocked or sim==null:return
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

func _resume_pirate_dispatch(snapshot:Dictionary,route:Dictionary,ticks:int) -> void:
 # Also guard direct recovery callers before allocating or replaying any owner.
 if not economy.replay_protocol_error(snapshot).is_empty() or not PirateProtocols.route_error(route).is_empty() or route.get("control_version")!=snapshot.get("control_version",snapshot.get("route",{}).get("control_version")):
  pilot_resume_blocked=true;notify("配送规则不一致，原记录已保留。");return
 var timeline=PilotTimeline.new()
 if not timeline.restore(snapshot.get("input_commands"),ticks):
  pilot_resume_blocked=true;notify("驾驶记录暂时无法恢复，原记录已保留。");return
 var prepared:Dictionary=_prepare_pirate_flight(snapshot.design,snapshot.launcher,route)
 if not bool(prepared.get("ok",false)):
  _pirate_diagnostic=prepared.duplicate(true);pilot_resume_blocked=true;notify("配送暂时无法恢复，原记录已保留。");return
 var candidate=prepared.simulation
 var completed:int=0
 for tick in range(ticks):
  if candidate.status!="running":break
  var command:Dictionary=timeline.state_at(tick)
  candidate.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active))
  candidate.step(1.0/60.0);completed+=1
 if candidate.status=="held" or not str(candidate.chrono_error).is_empty() or completed!=ticks:
  _pirate_diagnostic={"error":candidate.chrono_error,"completed_ticks":completed,"expected_ticks":ticks}
  pilot_resume_blocked=true;notify(PIRATE_HOLD_MESSAGE);return
 if snapshot.get("terminal_intent","")=="abort":
  if not candidate.abort_flight().ok:pilot_resume_blocked=true;notify(PIRATE_HOLD_MESSAGE);return
 _present_prepared_flight(false,snapshot.launcher,route,candidate,true)
 pilot_timeline=timeline;pilot_completed_ticks=completed
 world.settle_resumed_flight(sim);_set_paused(true)
 notify("配送已恢复。按 P 或 Esc 继续，重新按下方向键驾驶。")

func _is_pirate_flight() -> bool:
 return sim!=null and PirateProtocols.is_version(flight_order.get("control_version"))

func _pirate_is_held() -> bool:
 return _is_pirate_flight() and (sim.status=="held" or not str(sim.chrono_error).is_empty())

func _hold_pirate_flight() -> void:
 if not _pirate_is_held() or pilot_resume_blocked:return
 _pirate_diagnostic={"error":str(sim.chrono_error),"terminal":sim.route_terminal.duplicate(true),"completed_ticks":pilot_completed_ticks}
 completion_countdown=-1.0;pilot_resume_blocked=true;_set_paused(true)
 notify(PIRATE_HOLD_MESSAGE)

func _request_abort_flight() -> void:
 if closing or entry_defer_controls or page!="flight" or sim==null:return
 if pilot_resume_blocked or economy.review_load_blocked or _free_restore_active or _pirate_is_held():return
 if trial:
  abort_flight();return
 if str(sim.status)!="running":return
 if economy.in_flight.is_empty():return
 _abort_prompt_was_paused=paused;_abort_prompt_sim=sim
 _abort_prompt_contract_id=str(economy.in_flight.get("contract_id",""))
 _abort_prompt_pending=true;_quit_pause_after_disconnect=false;closing=true
 _set_paused(true)
 if is_instance_valid(world):world.set_focus_active(false)
 if not is_instance_valid(_abort_prompt):
  _abort_prompt=SaveExitDialog.new();_abort_prompt.name="PaidAbortConfirmation";_abort_prompt.title="中止正式配送？"
  _abort_prompt.process_mode=Node.PROCESS_MODE_ALWAYS;_abort_prompt.exclusive=true;_abort_prompt.unresizable=true
  _abort_prompt.dialog_text="中止后按失败结算，这份委托不能再次正式配送。\n消耗、损坏与货损按本单规则计费，余额不足可能形成债务。"
  _abort_prompt.get_ok_button().text="确认中止并结算";_abort_prompt.get_cancel_button().text="继续配送"
  add_child(_abort_prompt)
  _abort_prompt.confirmed.connect(_confirm_abort_prompt)
  _abort_prompt.canceled.connect(_cancel_abort_prompt)
 _abort_prompt.popup_centered(Vector2i(540,210))
 _abort_prompt.get_cancel_button().grab_focus()

func _close_abort_prompt() -> void:
 _abort_prompt_pending=false
 if is_instance_valid(_abort_prompt):_abort_prompt.hide()
 closing=false
 var focused:bool=get_window().has_focus()
 if is_instance_valid(world):world.set_focus_active(focused)
 if is_instance_valid(courier_input):courier_input.set_focus_active(focused)
 _abort_prompt_sim=null;_abort_prompt_contract_id=""

func _cancel_abort_prompt() -> void:
 if not _abort_prompt_pending:return
 var same_flight:bool=page=="flight" and sim==_abort_prompt_sim
 _close_abort_prompt()
 if same_flight:_set_paused(true if _quit_pause_after_disconnect else _abort_prompt_was_paused)

func _confirm_abort_prompt() -> void:
 if not _abort_prompt_pending:return
 var current:bool=page=="flight" and not trial and sim!=null and sim==_abort_prompt_sim and str(sim.status)=="running" and not pilot_resume_blocked and str(economy.in_flight.get("contract_id",""))==_abort_prompt_contract_id
 _close_abort_prompt()
 if current:abort_flight()
 # If the flight identity changed, the old dialog has no authority to settle it.

func abort_flight() -> void:
 if sim==null or page!="flight":return
 if _pirate_is_held():_hold_pirate_flight();return
 if pilot_resume_blocked:notify("此配送记录无法安全恢复，暂不结算；原记录已保留。");return
 _clear_pilot_input()
 if _free_version(flight_order.get("control_version")):
  if sim.status!="running":finish_flight();return
  _free_abort_intent=true
 if _is_pirate_flight():
  if sim.status=="running" and not sim.abort_flight().ok:return
  if sim.status not in ["success","failed"]:return
 else:sim.status="failed";sim.events.append("操作员中止本次航行。")
 finish_flight()

func finish_flight() -> void:
 if _pirate_is_held():_hold_pirate_flight();return
 if _is_pirate_flight() and sim.status not in ["success","failed"]:return
 if sim==null or page!="flight" or pilot_resume_blocked:return
 _clear_pilot_input()
 sim.finalize_settlement()
 var integrity:float=float(sim.telemetry.get("delivery_integrity",sim.telemetry.get("integrity",0)))*100
 report={"contract_id":str(flight_order.get("contract_id","")),"success":sim.status=="success","trial":trial,"elapsed":sim.elapsed,"integrity":integrity,"events":_flight_report_events(),"cause":_diagnosis(),"energy":float(sim.telemetry.get("energy_used",0))}
 if _delivery_version(flight_order.get("control_version")):
  report.delivery_integrity=float(sim.telemetry.delivery_integrity);report.min_delivery_integrity=float(flight_order.min_delivery_integrity)
  report.delivery_qualified=bool(sim.telemetry.get("delivery_qualified",false));report.control_version=str(flight_order.control_version)
 # Cold damage is observed HP loss, not a new fee or inferred total loss.
 # Missing/invalid legacy telemetry must remain absent rather than look like zero.
 if flight_order.get("control_version","") in [DeliveryRiftProfile.VERSION,DeliveryRiftProfileV6.VERSION,DeliveryRiftProfileV7.VERSION,DeliveryRiftProfileV8.VERSION]:
  var cold_damage:Variant=sim.telemetry.get("biological_damage")
  if (cold_damage is int or cold_damage is float) and is_finite(float(cold_damage)) and float(cold_damage)>=0.0:
   report.biological_damage=float(cold_damage)
 # Preserve actual inherited paid-impact counters for the ordinary receipt.
 # These are observations only; no extra simulation step, energy or RNG use.
 if _force_input_version(flight_order.get("control_version")):report.merge(FlightReceipt.shield_totals(sim.telemetry),true)
 if _force_input_version(flight_order.get("control_version")) and sim.telemetry.get("free_failure","")=="usable_energy_empty":
  report.free_failure="usable_energy_empty";report.power_failure=WorkshopPower.runtime_failure(sim)
 if not sim.incidents.is_empty():report.incident_id=int(sim.incidents[0].id)
 if trial:
  var stored:Dictionary=economy.last_trials.get(str(flight_order.contract_id),{})
  var previous:Dictionary=stored.get("latest",stored)
  var quote:Dictionary=economy.estimate_delivery(flight_order,sim.telemetry,float(sim.elapsed),sim.status=="success")
  report.energy_j=report.energy;report.estimated_profit=quote.profit;report.control_version=str(flight_order.get("control_version",""))
  for key in ["wormhole_energy_j","wormhole_transits","wormhole_station_remaining"]:
   if quote.has(key):report[key]=quote[key]
  report.design_snapshot=design.duplicate(true);report.launcher_snapshot=launcher.duplicate(true)
  if not previous.is_empty():
   report.comparison={"航时":"%+.2f 秒"%(sim.elapsed-float(previous.elapsed)),"耗能":"%+.1f J"%(snappedf(report.energy_j-float(previous.get("energy_j",previous.energy)),.01)),"完整度":"%+.1f%%"%(integrity-float(previous.integrity)),"预计净收益":"¥ %+d"%(int(report.estimated_profit)-int(previous.get("estimated_profit",0))),"本次改动":_design_changes(previous)}
  economy.last_trials[str(flight_order.contract_id)]={"latest":report.duplicate(true),"previous":previous.duplicate(true)}
 else:
  # Bind evidence to the completed live command boundary, including a terminal
  # first substep and a zero-tick abort. This checkpoint does no I/O or replay.
  if not _is_pirate_flight():_checkpoint_flight()
  var completion:Dictionary=BirdSettlement.from_simulator(sim,economy.in_flight) if str(flight_order.get("control_version",""))==BirdProfile.CONTROL_VERSION else {}
  if _is_pirate_flight():completion={"control_version":flight_order.control_version,"status":sim.status,"terminal":sim.route_terminal.duplicate(true),"checkpoint":_pirate_replay_checkpoint()}
  var result=economy.settle_contract_and_save(str(flight_order.contract_id),sim.telemetry,float(sim.elapsed),sim.status=="success",design,launcher,settings,completion)
  if result.get("ok",false):report.merge(result.report,true)
  else:
   # The ledger and pending review were rolled back together. Stay on the
   # finished flight, then retry after a delay; never show an unpaid receipt.
   _set_paused(true);completion_countdown=3.0;notify(str(result.get("message","结算未完成。")));return
 var persisted:bool=save_game() if trial else true
 if not trial and not _finish_deferred_free_recovery():return
 page="report";render();_play_music(false);_sound("delivery_success" if sim.status=="success" else "warning")
 if not _free_entry_notice.is_empty():notify(_free_entry_notice);_free_entry_notice=""
 if not trial and persisted:_request_story(str(flight_order.contract_id),"result")

func _design_changes(previous:Dictionary) -> String:
 var old:Array=previous.get("design_snapshot",[])+previous.get("launcher_snapshot",[])
 var changes:Array[String]=[]
 for p in design+launcher:
  var matches:Array=old.filter(func(q):return int(q.id)==int(p.id))
  if matches.is_empty():changes.append("新增 #"+str(p.id)+" "+str(catalog[p.type].name));continue
  var before:Dictionary=matches[0]
  if int(before.x)!=int(p.x) or int(before.y)!=int(p.y):changes.append(str(catalog[p.type].name)+"换了位置")
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
 if _review_phone_is_open() or _investigation_is_open():return
 workshop_input.cancel()
 if _loading_scene_active():return
 if page!="workshop" or undo_history.is_empty():return
 var previous:Dictionary=undo_history.pop_back();design=previous.design;launcher=previous.launcher;selected_id=int(previous.selected);_allocate_ids()
 var persisted:bool=save_game();render()
 if persisted:notify("已撤销上一步装配修改。")
 else:
  var detail:String=("\n"+_last_save_error) if not _last_save_error.is_empty() else ""
  notify("已撤销，但进度未保存。请重试保存。"+detail)

func _flight_report_events() -> Array:
 var result:Array=sim.events.duplicate()
 if str(flight_order.get("control_version",""))==BirdProfile.CONTROL_VERSION:
  for i in result.size():result[i]=FlightReceipt.player_event(str(result[i]),BirdProfile.CONTROL_VERSION)
 return result

func _diagnosis() -> String:
 if sim.status=="success":return "货物已签收。"
 # The actual terminal event explains failure; a first collision or later
 # repair/rescue receipt must not replace it with engineering diagnostics.
 if str(flight_order.get("control_version",""))==BirdProfile.CONTROL_VERSION:
  for event in sim.events:
   if FlightReceipt.player_event(str(event),BirdProfile.CONTROL_VERSION)!=str(event):return FlightReceipt.BIRD_FAILURE_COPY
 if is_instance_valid(hud):
  var receipt:Dictionary={"events":sim.events,"free_failure":sim.telemetry.get("free_failure","")}
  if _force_input_version(flight_order.get("control_version")) and receipt.free_failure=="usable_energy_empty":receipt.power_failure=WorkshopPower.runtime_failure(sim)
  return hud._report_failure_copy(receipt)
 return "这趟没能送达。"

static func _free_version(version:Variant) -> bool:
 return version is String and version in [FreeProfile.VERSION,FreeProfileV2.VERSION,DeliveryProfile.VERSION,DeliveryAscentProfile.VERSION,DeliveryRiftProfile.VERSION,DeliveryProfileV6.VERSION,DeliveryAscentProfileV6.VERSION,DeliveryRiftProfileV6.VERSION,DeliveryProfileV7.VERSION,DeliveryAscentProfileV7.VERSION,DeliveryRiftProfileV7.VERSION,DeliveryProfileV8.VERSION,DeliveryAscentProfileV8.VERSION,DeliveryRiftProfileV8.VERSION]

static func _delivery_version(version:Variant) -> bool:
 return version is String and version in [DeliveryProfile.VERSION,DeliveryAscentProfile.VERSION,DeliveryRiftProfile.VERSION,DeliveryProfileV6.VERSION,DeliveryAscentProfileV6.VERSION,DeliveryRiftProfileV6.VERSION,DeliveryProfileV7.VERSION,DeliveryAscentProfileV7.VERSION,DeliveryRiftProfileV7.VERSION,DeliveryProfileV8.VERSION,DeliveryAscentProfileV8.VERSION,DeliveryRiftProfileV8.VERSION]

static func _force_input_version(version:Variant) -> bool:
 return version is String and version in [FreeProfileV2.VERSION,DeliveryProfile.VERSION,DeliveryAscentProfile.VERSION,DeliveryRiftProfile.VERSION,DeliveryProfileV6.VERSION,DeliveryAscentProfileV6.VERSION,DeliveryRiftProfileV6.VERSION,DeliveryProfileV7.VERSION,DeliveryAscentProfileV7.VERSION,DeliveryRiftProfileV7.VERSION,DeliveryProfileV8.VERSION,DeliveryAscentProfileV8.VERSION,DeliveryRiftProfileV8.VERSION]

func _timeline_for_route(route:Dictionary):
 if _force_input_version(route.get("control_version")):return FreeTimelineV2.new()
 return FreeTimeline.new() if route.get("control_version")==FreeProfile.VERSION else PilotTimeline.new()

func _apply_pilot_command(command:Dictionary) -> void:
 if _force_input_version(flight_order.get("control_version")):
  sim.set_free_flight_input(int(command.axis_x_q),int(command.axis_q),bool(command.boost),bool(command.active),int(command.device_id),bool(command.brake))
 elif flight_order.get("control_version")==FreeProfile.VERSION:
  sim.set_free_flight_input(int(command.axis_x_q),int(command.axis_q),bool(command.boost),bool(command.active))
 else:sim.set_pilot_input(int(command.axis_q),bool(command.boost),bool(command.active))

func title_restore_pending() -> bool:return _free_restore_active
func title_restore_progress() -> float:return _free_restore_fraction
func title_restore_failure() -> String:return _free_restore_error
func cancel_title_restore() -> void:
 _free_restore_token+=1;_free_restore_active=false;pilot_resume_blocked=true

func _free_restore_hold(message:String) -> void:
 _free_restore_active=false;_free_restore_error=message;pilot_resume_blocked=true;paused=true
 if is_instance_valid(hud):notify(message)

func _resume_free_dispatch(snapshot:Dictionary,route:Dictionary,ticks:int) -> void:
 if not FreeProtocols.snapshot_error(snapshot).is_empty():_free_restore_hold("配送记录不完整，原存档已保留。");return
 # New long-lived input schema replays in bounded batches. The saved snapshot
 # remains untouched until the exact recorded state has been reconstructed.
 _free_restore_token+=1
 var token:int=_free_restore_token
 _free_restore_active=true;_free_restore_error="";_free_restore_fraction=0.0
 pilot_resume_blocked=true;paused=true
 var timeline=_timeline_for_route(route)
 if not timeline.restore(snapshot.get("input_commands"),ticks):
  _free_restore_hold("驾驶记录无法恢复，原存档已保留。");return
 var candidate=_simulation_for_version(str(route.get("control_version","")))
 candidate.configure(snapshot.design.duplicate(true),snapshot.launcher.duplicate(true),route,int(snapshot.get("seed",economy.day*100)))
 if not candidate.free_route_error.is_empty():_free_restore_hold("配送规则无法恢复，原存档已保留。");return
 var delivery_preparing:bool=_delivery_version(route.get("control_version")) and not bool(snapshot.launch_released)
 if _delivery_version(route.get("control_version")):
  _flight_launch_settings=snapshot.launch_settings.duplicate(true)
  # Reconstruct a paid release once from original pad charge. Preparation saves
  # retain zero ticks and zero cost, including a paused pre-release abort.
  if not delivery_preparing:
   candidate.release_launcher(float(_flight_launch_settings.angle_degrees),float(_flight_launch_settings.power_fraction))
   if not bool(candidate.launch_released):_free_restore_hold("发射记录无法恢复，原存档已保留。");return
 var completed:int=0
 for tick in range(ticks):
  if candidate.status!="running":_free_restore_hold("配送记录不完整，原存档已保留。");return
  var command:Dictionary=timeline.state_at(tick)
  if _force_input_version(route.get("control_version")):
   candidate.set_free_flight_input(int(command.axis_x_q),int(command.axis_q),bool(command.boost),bool(command.active),int(command.device_id),bool(command.brake))
  else:candidate.set_free_flight_input(int(command.axis_x_q),int(command.axis_q),bool(command.boost),bool(command.active))
  candidate.step(1.0/60.0);completed+=1
  if completed%120==0:
   _free_restore_fraction=float(completed)/maxf(1.0,float(ticks))
   await get_tree().process_frame
   if not is_inside_tree() or token!=_free_restore_token:return
 if token!=_free_restore_token:return
 var abort_intent:bool=snapshot.get("terminal_intent","")=="abort"
 if abort_intent:
  if candidate.status!="running":_free_restore_hold("中止记录与航行状态不一致，原存档已保留。");return
  candidate.status="failed";candidate.events.append("操作员中止本次航行。")
 _present_prepared_flight(false,snapshot.launcher,route,candidate,not delivery_preparing)
 if delivery_preparing:
  launch_age=float(snapshot.launch_preparation.age);launch_transfer_remaining=float(snapshot.launch_preparation.transfer_remaining)
  launch_countdown=launch_transfer_remaining+maxf(0.0,.95-launch_age)
  world.launch_age=launch_age;world.launch_transfer_progress=1.0 if world.launch_transfer_duration()<=0.0 else clampf(1.0-launch_transfer_remaining/world.launch_transfer_duration(),0.0,1.0)
 if _force_input_version(route.get("control_version")):
  _selected_free_device_id=int(timeline.state_at(ticks).device_id)
 _free_abort_intent=abort_intent
 pilot_timeline=timeline;pilot_completed_ticks=completed
 if not delivery_preparing:world.settle_resumed_flight(sim)
 else:world.show_flight(sim,true)
 _free_restore_fraction=1.0;_free_restore_active=false;pilot_resume_blocked=false
 _set_paused(true);notify("配送已恢复。按 P 继续。")

func _is_pilot_flight() -> bool:
 return sim!=null and sim.has_method("set_pilot_input") and str(flight_order.get("control_version","")) in PILOT_VERSIONS

func _clear_pilot_input() -> void:
 pilot_keys.clear()
 if _is_pilot_flight():
  sim.set_pilot_input(0,false,false)
  sim.telemetry.pilot_axis_q=0;sim.telemetry.pilot_boost=false;sim.telemetry.pilot_active=false
  if sim.telemetry.has("pilot_axis_x_q"):sim.telemetry.pilot_axis_x_q=0
  if sim.telemetry.has("overdrive"):sim.telemetry.overdrive=false
  if sim.telemetry.has("pilot_brake"):sim.telemetry.pilot_brake=false
  if sim.telemetry.has("free_control_mode"):sim.telemetry.free_control_mode="coast"

func _pilot_input_state() -> Dictionary:
 if _force_input_version(flight_order.get("control_version")):return FreeInputV2.state(pilot_keys,courier_input,_selected_free_device_id)
 if flight_order.get("control_version")==FreeProfile.VERSION:return FreeInput.state(pilot_keys,courier_input)
 var up:bool=pilot_keys.has(KEY_W) or pilot_keys.has(KEY_UP)
 var down:bool=pilot_keys.has(KEY_S) or pilot_keys.has(KEY_DOWN)
 var pad:Dictionary=courier_input.pilot_state() if is_instance_valid(courier_input) else {"axis_q":0,"boost":false,"active":false}
 return {"axis_q":(int(down)-int(up))*1000 if up or down else int(pad.axis_q),"boost":pilot_keys.has(KEY_SHIFT) or bool(pad.boost),"active":pilot_keys.has(KEY_SPACE) or bool(pad.active)}

func cycle_free_device() -> void:
 if page!="flight" or paused or pilot_resume_blocked or sim==null or not _force_input_version(flight_order.get("control_version")):return
 if is_instance_valid(courier_input) and (not courier_input.focused or courier_input.context!="flight"):return
 var available:Array=sim.selectable_device_ids()
 if available.is_empty():_selected_free_device_id=-1;return
 var index:int=available.find(_selected_free_device_id)
 _selected_free_device_id=int(available[(index+1)%available.size()])
 # This only selects an input target. The next recorded command owns any
 # physical activation. No assembly, inventory or economic mutation occurs.

func _flight_save_exit_available() -> bool:
 return page=="flight" and paused and sim!=null and str(sim.status)=="running" and not closing and not entry_defer_controls and not pilot_resume_blocked and not _free_restore_active and not economy.review_load_blocked and not _pirate_is_held()

func _set_paused(value:bool) -> void:
 if pilot_resume_blocked and not value:return
 paused=value
 if _is_pirate_flight():sim.set_paused(value)
 if is_instance_valid(hud) and hud.has_method("update_flight_exit_state"):hud.update_flight_exit_state(paused,_flight_save_exit_available())
 _clear_pilot_input()
 if is_instance_valid(courier_input):courier_input.synchronize()

func _on_focus_exited() -> void:
 if closing:return
 _close_investigation()
 _close_review_phone()
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
 if closing:return
 if is_instance_valid(courier_input):courier_input.set_focus_active(true)
 if is_instance_valid(loading_overlay):loading_overlay.set_focus_active(true)
 if is_instance_valid(dialogue):dialogue.set_focus_active(true)
 if is_instance_valid(world):world.set_focus_active(true)

func _pirate_replay_checkpoint() -> Dictionary:
 var snapshot:Dictionary=economy.in_flight.duplicate(true)
 if snapshot.is_empty() or _pirate_is_held():return snapshot
 snapshot.elapsed=sim.elapsed;snapshot.ticks=pilot_completed_ticks
 snapshot.control_version=flight_order.control_version;snapshot.input_commands=pilot_timeline.snapshot()
 if sim.route_terminal.get("kind")=="abort":snapshot.terminal_intent="abort"
 return snapshot

func _checkpoint_flight() -> void:
 # Pirate checkpoints are detached and saved through the same transaction as
 # dispatch/settlement. A standalone checkpoint must not mutate live aliases.
 if _is_pirate_flight():return
 if page!="flight" or trial or sim==null or pilot_resume_blocked or economy.in_flight.is_empty():return
 if str(economy.in_flight.get("contract_id",""))!=str(flight_order.get("contract_id","")):return
 economy.in_flight.elapsed=sim.elapsed
 economy.in_flight.ticks=pilot_completed_ticks if _is_pilot_flight() else roundi(sim.elapsed*60.0)
 if _is_pilot_flight():economy.in_flight.control_version=str(flight_order.control_version);economy.in_flight.input_commands=pilot_timeline.snapshot()
 if _delivery_version(flight_order.get("control_version")):
  economy.in_flight.launch_released=bool(sim.launch_released)
  if sim.launch_released:economy.in_flight.erase("launch_preparation")
  else:economy.in_flight.launch_preparation={"age":clampf(launch_age,0.0,.95),"transfer_remaining":maxf(0.0,launch_transfer_remaining)}
 if _free_version(flight_order.get("control_version")):
  economy.in_flight.input_schema=FreeProtocols.input_schema(str(flight_order.get("control_version")))
  if _free_abort_intent:economy.in_flight.terminal_intent="abort"
  else:economy.in_flight.erase("terminal_intent")

func _step_flight() -> void:
 if _pirate_is_held():_hold_pirate_flight();return
 if _is_pilot_flight():
  var command:Dictionary=_pilot_input_state()
  if not pilot_timeline.record(pilot_completed_ticks,command):
   _set_paused(true);notify(pilot_timeline.error);return
  _apply_pilot_command(command)
 sim.step(1.0/60.0);pilot_completed_ticks+=1
 if _pirate_is_held():_hold_pirate_flight()

func _process(delta:float) -> void:
 if closing:return
 if _investigation_is_open() and not investigation._available():_close_investigation()
 if _review_phone_is_open() and not _can_keep_review_phone():_close_review_phone()
 if is_instance_valid(courier_input):courier_input.tick(delta)
 workshop_input.tick()
 _sync_loading_scene_ui()
 if not _pending_story.is_empty():_try_pending_story()
 _sync_shop_action_availability()
 if is_instance_valid(hud) and is_instance_valid(world) and page=="hub":hud.update_hotspots(world.hotspot_positions())
 if page!="flight" or sim==null:return
 if _pirate_is_held():_hold_pirate_flight();return
 if pilot_resume_blocked:return
 var modal_open:bool=is_instance_valid(hud) and hud.is_blocking_modal()
 if modal_open and not _flight_modal_was_open:_paused_before_modal=paused;_set_paused(true)
 elif not modal_open and _flight_modal_was_open:_set_paused(_paused_before_modal)
 _flight_modal_was_open=modal_open
 var active_delta:float=0.0
 var release_age:float=.95 if _delivery_version(flight_order.get("control_version")) else .7
 # A positive charge age can only occur after the transfer (also used by
 # deterministic fixtures and historical resume adapters).
 if launch_age>0.0 or world.launch_transfer_duration()<=0.0:launch_transfer_remaining=0.0
 if not paused:
  var remaining_delta:float=maxf(0.0,delta)
  if launch_transfer_remaining>0.0:
   var used:float=minf(remaining_delta,launch_transfer_remaining)
   launch_transfer_remaining=maxf(0.0,launch_transfer_remaining-used);remaining_delta-=used
  active_delta=maxf(0.0,remaining_delta-maxf(0.0,release_age-launch_age))
  launch_age+=remaining_delta
 world.launch_transfer_progress=1.0 if world.launch_transfer_duration()<=0.0 else 1.0-launch_transfer_remaining/world.launch_transfer_duration()
 launch_countdown=launch_transfer_remaining+maxf(0,release_age-launch_age);world.launch_age=launch_age
 if launch_countdown<=0.0 and not paused and not _release_delivery_launcher():return
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
 if _pirate_is_held():_hold_pirate_flight();return
 world.show_flight(sim,paused)
 var flight_data:Dictionary=sim.telemetry.duplicate(true)
 # Observe live cargo supply even before the first physics tick. This only
 # augments the HUD copy; free launch and the solver failure protocol stay intact.
 if _force_input_version(flight_order.get("control_version")):
  if str(sim.status)=="running":flight_data.power_status=WorkshopPower.runtime_status(sim)
  elif sim.telemetry.get("free_failure","")=="usable_energy_empty":flight_data.power_failure=WorkshopPower.runtime_failure(sim)
 flight_data.merge({"elapsed":sim.elapsed,"distance":sim.cargo_position().x,"total_distance":world.route_distance,"integrity":sim.telemetry.get("integrity",1),"energy_used":sim.telemetry.get("energy_used",0),"events":[] if launch_countdown>0 else sim.events,"charging":launch_countdown>0,"paused":paused,"simulation_rate":speed,"phase":("收件确认" if sim.status=="success" else "航行结束") if sim.status!="running" else (("移送到地面发射位" if launch_transfer_remaining>0.0 else "发射台蓄能中") if launch_countdown>0 else ("运行较慢" if slow_simulation else ("手动驾驶" if _is_pilot_flight() else "自动航行")))},true)
 if not _is_pilot_flight():flight_data.speed=speed
 # Presentation-only, already tick-sampled by world.show_flight above.
 if flight_order.get("control_version","")==BirdProfile.CONTROL_VERSION and world.flight_nodes.has("protected_bird"):
  flight_data.protected_bird_advice=world.flight_nodes.protected_bird.advisory_state()
 flight_data.destination_navigation=world.delivery_navigation_snapshot(sim)
 flight_data.save_exit_available=_flight_save_exit_available()
 if _force_input_version(flight_order.get("control_version")):flight_data.selected_tool=SelectedDeviceView.state(sim)
 hud.update_flight(flight_data)
 # Paused handoff has no new simulation to save; preserve both recovered slots.
 if not trial and not paused and sim.elapsed-checkpoint>=1.0:checkpoint=sim.elapsed;_checkpoint_flight();save_game()
 # Pirate holds returned above; preserve the exact legacy terminal predicate.
 if sim.status!="running":
  if completion_countdown<0:completion_countdown=1.05
  else:completion_countdown-=delta
  if completion_countdown<=0:finish_flight()
func _input(event:InputEvent) -> void:
 if closing:return
 if _review_phone_is_open() or _investigation_is_open():return
 workshop_input.observe(event)
 # Releases must be observed even when a focused UI control consumes key presses.
 if event is InputEventKey and not event.pressed:
  pilot_keys.erase(event.keycode);pilot_keys.erase(event.physical_keycode)

func _unhandled_key_input(event:InputEvent) -> void:
 if closing:return
 if _review_phone_is_open() or _investigation_is_open():return
 if economy.review_load_blocked:return
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
  elif code==KEY_Q and _force_input_version(flight_order.get("control_version")):
   cycle_free_device();get_viewport().set_input_as_handled()
  elif not paused and not pilot_resume_blocked and (code in [KEY_W,KEY_S,KEY_UP,KEY_DOWN,KEY_SHIFT,KEY_SPACE] or (_free_version(flight_order.get("control_version")) and code in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]) or (_force_input_version(flight_order.get("control_version")) and code==KEY_CTRL)):pilot_keys[code]=true;get_viewport().set_input_as_handled()
 elif page=="flight" and event.keycode in [KEY_SPACE,KEY_ESCAPE]:_set_paused(not paused)
 elif event.keycode==KEY_ESCAPE:navigate("hub")
func _prepare_shop_save() -> bool:
 # Preserve save_game's replay/presentation guards and checkpoint ordering.
 # The wrapper owns error feedback after rollback, so no success UI leaks out.
 if pilot_resume_blocked or economy.review_load_blocked:
  economy.save_error=economy.load_notice if not economy.load_notice.is_empty() else "配送记录尚未恢复，这次操作未保存。"
  return false
 var unavailable:String=economy.presentation_state_error()
 if not unavailable.is_empty():economy.save_error=unavailable;return false
 _checkpoint_flight()
 return true

func save_game() -> bool:
 _last_save_error=""
 if _pirate_is_held():_last_save_error=PIRATE_HOLD_MESSAGE;_hold_pirate_flight();return false
 if pilot_resume_blocked or economy.review_load_blocked:
  _last_save_error=economy.load_notice if not economy.load_notice.is_empty() else "配送记录尚未恢复，这次操作未保存。"
  return false
 var unavailable:String=economy.presentation_state_error()
 if not unavailable.is_empty():_last_save_error=unavailable;notify(unavailable);return false
 if _is_pirate_flight() and not trial and page=="flight":
  var result:Dictionary=economy.save_pirate_replay_and_save(_pirate_replay_checkpoint(),design,launcher,settings)
  if not bool(result.get("ok",false)):_last_save_error=str(result.get("message","配送记录未能保存。"));notify(_last_save_error);return false
  if not str(result.get("message","")).is_empty():notify(str(result.message))
  return true
 _checkpoint_flight()
 var ok=economy.save_state(design,launcher,settings)
 if not ok:_last_save_error=economy.save_error;notify(economy.save_error)
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
func _ensure_audio_players() -> void:
 if not is_instance_valid(music):
  music=AudioStreamPlayer.new();music.name="Music";music.process_mode=Node.PROCESS_MODE_ALWAYS;music.bus="Master";add_child(music)
 if not is_instance_valid(sfx):
  sfx=AudioStreamPlayer.new();sfx.name="SoundEffects";sfx.process_mode=Node.PROCESS_MODE_ALWAYS;sfx.bus="Master";add_child(sfx)
 _apply_audio_volume()

func _master_volume() -> float:
 var value:Variant=settings.get("volume",.55)
 if not (value is int or value is float) or not is_finite(float(value)):return .55
 return clampf(float(value),0.0,1.0)

func _apply_audio_volume() -> void:
 var volume:float=_master_volume()
 # Source music already peaks below -9 dBFS. Avoid the former extra -5 dB
 # attenuation; retain the user's saved volume, including intentional mute.
 var gain_db:float=linear_to_db(volume) if volume>0.0 else -80.0
 if is_instance_valid(music):
  music.volume_db=gain_db
  music.stream_paused=volume<=0.0 or entry_defer_controls
 if is_instance_valid(sfx):
  sfx.volume_db=gain_db
  if volume<=0.0:sfx.stop()

func _play_music(flying:bool) -> void:
 if not is_instance_valid(music):return
 var track:AudioStream=MUSIC_TRACKS["flight" if flying else "workshop"]
 if music.stream!=track:
  music.stop();music.stream=track
  if music.stream is AudioStreamOggVorbis:music.stream.loop=true
 # Main is constructed disabled during the title entrance. Start only after
 # the title releases it; do not depend on inherited process-mode side effects.
 if not entry_defer_controls and not music.playing:music.play()
 _apply_audio_volume()

func _test_sound() -> void:
 if _master_volume()<=0.0:notify("当前音量为 0，请调高后试听。");return
 _sound("delivery_success")
 if AudioServer.get_driver_name()=="Dummy":notify("当前没有实际声音输出（Dummy 驱动）。");return
 notify("已触发试听，音量 %d%%。输出：%s。若听不到，请检查系统音量与输出设备。"%[roundi(_master_volume()*100),AudioServer.get_output_device()])

func _sound(name:String) -> void:
 if not is_instance_valid(sfx) or not SOUND_EFFECTS.has(name) or _master_volume()<=0.0:return
 sfx.stream=SOUND_EFFECTS[name];sfx.stream_paused=false;sfx.volume_db=linear_to_db(_master_volume());sfx.play()

func _notification(what:int) -> void:
 if what==NOTIFICATION_WM_CLOSE_REQUEST:_request_save_and_quit.call_deferred()

func _request_save_and_quit() -> void:
 # Title owns window-close until it explicitly hands over input and state.
 # A paused restore candidate must never start a second quit coroutine.
 if entry_defer_controls or closing:return
 if economy.review_load_blocked or pilot_resume_blocked:_quit_cleanly();return
 _quit_prompt_was_paused=paused;_quit_prompt_resume_after_modal=_paused_before_modal;_quit_save_failed=false;_quit_pause_after_disconnect=false
 closing=true;_quit_prompt_pending=true
 if page=="flight":_set_paused(true)
 workshop_input.cancel()
 if is_instance_valid(courier_input):courier_input.synchronize()
 if is_instance_valid(world):world.set_focus_active(false)
 if not is_instance_valid(_quit_prompt):
  _quit_prompt=SaveExitDialog.new();_quit_prompt.name="SaveExitConfirmation";_quit_prompt.title="保存并退出";_quit_prompt.process_mode=Node.PROCESS_MODE_ALWAYS
  _quit_prompt.exclusive=true;_quit_prompt.unresizable=true
  _quit_prompt.dialog_text="保存当前进度后退出游戏？"
  _quit_prompt.get_ok_button().text="保存并退出";_quit_prompt.get_cancel_button().text="继续游戏"
  add_child(_quit_prompt)
  _quit_prompt.confirmed.connect(_confirm_quit_prompt)
  _quit_prompt.canceled.connect(_cancel_quit_prompt)
 _quit_prompt.popup_centered(Vector2i(480,170))
 _quit_prompt.get_cancel_button().grab_focus()

func _confirm_quit_prompt() -> void:
 if not _quit_prompt_pending:return
 _quit_prompt_pending=false;_quit_prompt.hide();closing=false;_quit_cleanly()

func _quit_cleanly(exit_code:int=0) -> void:
 if closing:return
 closing=true;_quit_exit_code=exit_code
 if page=="flight":_set_paused(true)
 workshop_input.cancel()
 if is_instance_valid(courier_input):courier_input.synchronize()
 if is_instance_valid(world):world.set_focus_active(false)
 # Read-only recovery has no live changes to save. Its existing corrupt or
 # unsupported bytes must survive, and must not trap the player in the app.
 if economy.review_load_blocked or pilot_resume_blocked:
  _finish_quit(exit_code);return
 # Do not destroy dialogue/loading/phone ownership until the commit succeeds.
 if not save_game():
  _show_quit_save_failure();return
 _finish_quit(exit_code)

func _show_quit_save_failure() -> void:
 _quit_save_failed=true;_quit_failure_pending=true
 if not is_instance_valid(_quit_dialog):
  _quit_dialog=SaveExitDialog.new();_quit_dialog.name="SaveExitFailure";_quit_dialog.title="尚未保存";_quit_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
  _quit_dialog.exclusive=true;_quit_dialog.unresizable=true
  _quit_dialog.get_ok_button().text="重试保存并退出";_quit_dialog.get_cancel_button().text="返回游戏"
  _quit_dialog.add_button("放弃本次更改并退出",true,"discard")
  add_child(_quit_dialog)
  _quit_dialog.confirmed.connect(_retry_quit_save)
  _quit_dialog.canceled.connect(_cancel_quit_failure)
  _quit_dialog.custom_action.connect(func(action:String):
   if action=="discard" and _quit_failure_pending:
    _quit_failure_pending=false;_quit_dialog.hide();_finish_quit(_quit_exit_code))
 var detail:String=_last_save_error if not _last_save_error.is_empty() else "无法写入存档，请检查磁盘空间与文件权限。"
 _quit_dialog.dialog_text="保存失败，游戏还没有退出。上次成功保存的进度仍在。\n\n"+detail
 _quit_dialog.popup_centered(Vector2i(650,240))
 _quit_dialog.get_cancel_button().grab_focus()

func _retry_quit_save() -> void:
 if not _quit_failure_pending:return
 _quit_failure_pending=false
 if is_instance_valid(_quit_dialog):_quit_dialog.hide()
 closing=false
 _quit_cleanly(_quit_exit_code)

func _hold_quit_resume_for_disconnect() -> void:
 if closing:_quit_pause_after_disconnect=true

func _cancel_quit_prompt() -> void:
 # An old hidden prompt cannot cancel a newer save-failure dialog.
 if not _quit_prompt_pending:return
 _cancel_quit()

func _cancel_quit_failure() -> void:
 if not _quit_failure_pending:return
 _cancel_quit()

func _cancel_quit() -> void:
 if not _quit_prompt_pending and not _quit_failure_pending:return
 _quit_prompt_pending=false;_quit_failure_pending=false
 if is_instance_valid(_quit_prompt):_quit_prompt.hide()
 if is_instance_valid(_quit_dialog):_quit_dialog.hide()
 closing=false
 var focused:bool=get_window().has_focus()
 if is_instance_valid(world):world.set_focus_active(focused)
 if is_instance_valid(courier_input):courier_input.set_focus_active(focused)
 # Canceling the initial prompt restores its prior pause state without saving.
 # After an actual write failure, flight stays paused for an explicit resume.
 if page=="flight":
  if _quit_save_failed or _quit_pause_after_disconnect:
   _paused_before_modal=true;_set_paused(true)
  else:
   _paused_before_modal=_quit_prompt_resume_after_modal;_set_paused(_quit_prompt_was_paused)

func _finish_quit(exit_code:int) -> void:
 _close_investigation()
 _close_review_phone()
 if is_instance_valid(world) and world.has_method("teardown_review_phone"):world.teardown_review_phone(world._review_phone_owner)
 if is_instance_valid(world) and world.has_method("teardown_clerk_departure"):world.teardown_clerk_departure()
 if is_instance_valid(dialogue):dialogue.cancel(false)
 if is_instance_valid(loading_overlay):loading_overlay.close()
 _active_story.clear();_pending_story.clear()
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

func _exit_tree() -> void:
 _close_investigation()
 _close_review_phone()
 if is_instance_valid(world) and world.has_method("teardown_review_phone"):world.teardown_review_phone(world._review_phone_owner)
 if is_instance_valid(world) and world.has_method("teardown_clerk_departure"):world.teardown_clerk_departure()
