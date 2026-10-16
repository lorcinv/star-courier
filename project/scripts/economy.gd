class_name Economy
extends RefCounted
## A finite working day. Contracts, dispatch commitments and settlement IDs persist.
const SAVE_VERSION:int=5
const DeliveryChapter=preload("res://scripts/delivery_chapter_v3.gd")
const DeliveryProfile=preload("res://scripts/pilot_delivery_profile_v3.gd")
const DeliveryAscentProfile=preload("res://scripts/pilot_delivery_ascent_profile_v4.gd")
const DeliveryRiftProfile=preload("res://scripts/pilot_delivery_rift_profile_v5.gd")
const DeliveryTimeline=preload("res://scripts/pilot_free_timeline_v2.gd")
var delivery_chapter_state:Dictionary={}
var delivery_upgrade:Dictionary={}
const SeededOffers=preload("res://scripts/seeded_offer_catalog.gd")
const SeededGuard=preload("res://scripts/seeded_offer_guard.gd")
const AuthoringPolicy=preload("res://scripts/combined_offer_authoring_policy.gd")
const PirateOffer=preload("res://scripts/pirate_sidejob_offer_v1.gd")
const BirdOffer=preload("res://scripts/protected_bird_offer_v1.gd")
const BirdProfile=preload("res://scripts/pilot_protected_bird_profile.gd")
const BirdSettlement=preload("res://scripts/protected_bird_settlement_v1.gd")
const MeteorOffers=preload("res://scripts/orbital_meteor_offers.gd")
const ReadableGuard=preload("res://scripts/readable_offer_guard.gd")
const WorkshopProfile=preload("res://scripts/workshop_profile.gd")
const BasicParts=preload("res://scripts/parts_expanded.gd")
const WorkshopParts=preload("res://scripts/workshop_parts_v2.gd")
const PartsMigration=preload("res://scripts/parts_migration_v2.gd")
const DAY_BASIC_PART_KINDS:Array[String]=["solid_booster","heater","airbrake","beam","battery","thruster","armor","shield","drill","teleporter","splitter","spring","coupler","damper","accelerator"]
const PilotProfile=preload("res://scripts/pilot_profile.gd")
const AscentProfile=preload("res://scripts/pilot_ascent_profile.gd")
const ExtremeProfile=preload("res://scripts/pilot_extreme_profile.gd")
const FreeProfile=preload("res://scripts/pilot_free_profile_v1.gd")
const FreeTimeline=preload("res://scripts/pilot_free_timeline_v1.gd")
const FreeProtocols=preload("res://scripts/free_flight_protocols.gd")
const ForceProfile=preload("res://scripts/pilot_free_profile_v2.gd")
const LunarRoute=preload("res://scripts/pilot_free_lunar_route_v2.gd")
const MosslightRoute=preload("res://scripts/pilot_free_mosslight_route_v2.gd")
const FREE_ECONOMY_POLICY:String="free-flight-economy-v1"
const FREE_GROUND_REWARD:int=220
const FREE_RECOVERY_RESERVE:int=220
const FREE_SUCCESS_CHARGE_CAP:int=30
const FREE_FAILURE_CHARGE_CAP:int=25
const ECONOMIC_RECOVERY_SCHEMA:String="free-flight-debt-relief-v1"
var economic_recovery:Dictionary={}
const FREE_OFFER_UPGRADE_SCHEMA:String="available-free-offers-upgrade-v1"
var free_offer_upgrade:Dictionary={}
const FORCE_OFFER_UPGRADE_SCHEMA:String="available-force-offers-upgrade-v2"
var force_offer_upgrade:Dictionary={}
var parts_retirement:Dictionary={}
# Transient source digest, owned only by an explicit detached transition.
var _transition_source:Dictionary={}
const ACCEPTED_FREE_SWAP_SCHEMA:String="accepted-free-swap-v1"
var accepted_free_swaps:Dictionary={}
var _loaded_save_path:String=""
const GroundProfile=preload("res://scripts/pilot_ground_profile.gd")
const MoonProfile=preload("res://scripts/pilot_moon_profile.gd")
const WormholeProfile=preload("res://scripts/pilot_wormhole_profile.gd")
const PirateProfile=preload("res://scripts/pirate_encounter_profile_v1.gd")
const PirateProfileV2=preload("res://scripts/pirate_encounter_profile_v2.gd")
const PirateProtocols=preload("res://scripts/pirate_protocols.gd")
const PILOT_VERSIONS:Array=[DeliveryChapter.SHIELD_GROUND_VERSION,DeliveryChapter.SHIELD_ASCENT_VERSION,DeliveryChapter.SHIELD_RIFT_VERSION,DeliveryChapter.MATERIAL_GROUND_VERSION,DeliveryChapter.MATERIAL_ASCENT_VERSION,DeliveryChapter.MATERIAL_RIFT_VERSION,DeliveryChapter.CELL_GROUND_VERSION,DeliveryChapter.CELL_ASCENT_VERSION,DeliveryChapter.CELL_RIFT_VERSION,DeliveryRiftProfile.VERSION,DeliveryAscentProfile.VERSION,DeliveryProfile.VERSION,PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION,PirateProfile.VERSION,PirateProfileV2.VERSION,FreeProfile.CONTROL_VERSION,ForceProfile.CONTROL_VERSION]
const Stories=preload("res://scripts/courier_stories.gd")
const Reviews=preload("res://scripts/customer_reviews_v3.gd")
const DISPATCHES_PER_DAY:int=2
const WORMHOLE_ROUTE_ID:int=3
const WORMHOLE_REPUTATION:int=7
const MOON_ROUTE_ID:int=4
const MOON_REPUTATION:int=10
const MOON_FIRST_DAY:int=4
var credits:int=260
var reputation:int=0
var day:int=1
var phase:String="morning"
var jobs_today:int=0
var deliveries:int=0
var research:int=0
## Independent of battery research; bounds derive from this persisted tier.
var workshop_tier:int=0
var history:Array=[]
var designs:Dictionary={}
var inventory:Dictionary={}
var contracts:Array=[]
var active_contract_id:String=""
var settled_ids:Dictionary={}
var in_flight:Dictionary={}
var last_settlement:Dictionary={}
var last_trials:Dictionary={}
var save_error:String=""
var load_notice:String=""
## Presentation opts in explicitly. Legacy simulation fixtures remain unbound.
## Identity/progression shares the ledger's single atomic save, never a sidecar.
var story_mode:bool=false
var story_state:Dictionary={}
## Null only before new-shop/legacy initialization; saved states are validated.
var review_state:Variant=null
var review_load_blocked:bool=false
## Standalone legacy simulations/tests retain the old route catalog. The current
## game opts into pilot-v3 explicitly; saved older dispatches remain frozen.
var flight_mode:String="autonomous-v5"
## Versioned content authoring; existing offers remain immutable on enable/load.
var offer_generation_state:Dictionary={}
## Optional presentation gate. Empty by default so legacy model-only fixtures
## and full-game protocols keep their existing authoring behavior.
var route_guard:Callable=Callable()
## Shop wrappers and the bounded pirate adapter use staged backup rotation.
## The primary rename is the commit point; legacy persistence stays unchanged.
var _shop_save_in_progress:bool=false
# Only detached, saving authoring transactions may introduce the optional job.
var _pirate_authoring_in_progress:bool=false
var _shop_backup_warning:String=""
const SHOP_TRANSACTION_FIELDS:Array=["credits","reputation","day","phase","jobs_today","deliveries","research","workshop_tier","history","designs","inventory","contracts","active_contract_id","settled_ids","in_flight","last_settlement","last_trials","load_notice","story_mode","story_state","review_state","review_load_blocked","flight_mode","offer_generation_state","economic_recovery","free_offer_upgrade","accepted_free_swaps","force_offer_upgrade","parts_retirement","delivery_chapter_state","delivery_upgrade"]

func route_availability_error(route:Dictionary) -> String:
 if not route_guard.is_valid():return ""
 var result:Variant=route_guard.call(route)
 return result if result is String else "航线画面暂时无法读取，原进度已保留。"

func route_preflight_error(route:Dictionary) -> String:
 var unavailable:String=route_availability_error(route)
 return unavailable if not unavailable.is_empty() else route_validation_error(route)

func presentation_state_error(raw:Dictionary={}) -> String:
 if not route_guard.is_valid():return ""
 var offers:Variant=raw.get("contracts",contracts)
 if offers is Array:
  for order in offers:
   if order is Dictionary:
    var error:String=route_availability_error(order)
    if not error.is_empty():return error
 var snapshot:Variant=raw.get("in_flight",in_flight)
 if snapshot is Dictionary and snapshot.get("route") is Dictionary:
  return route_availability_error(snapshot.route)
 return ""

func enable_seeded_offers(explicit_seed:Variant) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var raw:Dictionary={}
 if not offer_generation_state.is_empty():raw.offer_generation_state=offer_generation_state
 var initialized:Dictionary=SeededOffers.initialize_save(raw,explicit_seed)
 if not initialized.ok:return initialized
 offer_generation_state=initialized.save.offer_generation_state
 # No ensure_contracts() here: existing offers, even available ones, stay exact.
 return {"ok":true,"changed":initialized.changed}

func author_readable_batch_and_save(explicit_seed:Variant,design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 return _shop_mutation_and_save(_author_readable_batch.bind(explicit_seed),design,launcher,settings,Callable())

func _author_readable_batch(explicit_seed:Variant) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if not contracts.is_empty() or not in_flight.is_empty():return _error("今日委托已安排，请先处理现有委托。")
 if phase!="morning" or jobs_today!=0 or not active_contract_id.is_empty() or not last_trials.is_empty():return _error("今日委托已安排，请先处理现有委托。")
 if not _new_batch_identity_error(day).is_empty():return _error("今日委托身份已使用，原进度已保留。")
 if offer_generation_state.get("introduced_day",0)==day or offer_generation_state.get("pirate_introduced_day",0)==day:return _error("今日委托已安排，请先处理现有委托。")
 if not flight_mode in ([ExtremeProfile.CONTROL_VERSION]+FreeProtocols.VERSIONS):return _error("暂时无法领取新委托，请重新载入进度。")
 var initialized:Dictionary=enable_seeded_offers(explicit_seed)
 if not initialized.ok:return _error("航线记录不完整，原进度已保留。")
 var transition:Dictionary=AuthoringPolicy.next_day_root(offer_generation_state,day)
 if not transition.ok:return _error("新委托未能整理，原进度已保留。")
 offer_generation_state=transition.state
 if story_state.is_empty():story_state=Stories.initial_state(int(offer_generation_state.world_seed))
 story_mode=true
 _pirate_authoring_in_progress=true
 ensure_contracts()
 _pirate_authoring_in_progress=false
 var error:String=_authored_batch_error()
 return {"ok":true} if error.is_empty() else _error(error)

func _new_batch_identity_error(new_day:int) -> String:
 # At authoring only, ANY prior use of either proposed ID is a collision.
 # Recursive keys cover every existing story/review namespace, including
 # seen dialogue IDs and route contexts, without changing those schemas.
 var namespaces:Array=[contracts,settled_ids,history,in_flight,last_settlement,last_trials,story_state,review_state,active_contract_id]
 for id in ["D%d-A"%new_day,"D%d-B"%new_day]:
  for value in namespaces:
   if _contains_contract_identity(value,id,0):return "contract_identity_already_used:"+id
 return ""

static func _contains_contract_identity(value:Variant,id:String,depth:int) -> bool:
 if depth>32:return true # Bound untrusted recursive authoring requests closed.
 if value is String:return value==id or value.begins_with(id+"/")
 if value is Dictionary:
  for key in value:
   if _contains_contract_identity(key,id,depth+1) or _contains_contract_identity(value[key],id,depth+1):return true
 elif value is Array:
  for child in value:
   if _contains_contract_identity(child,id,depth+1):return true
 return false

func _authored_batch_error() -> String:
 # Validate the final pair after optional replacements and initial binding.
 # This authoring-only gate never rejects/reinterprets an old opaque save.
 var invalid:String="这份航线记录不完整，暂时无法出发。"
 if contracts.size()!=DISPATCHES_PER_DAY or not AuthoringPolicy.supported_root(offer_generation_state):return invalid
 for slot in contracts.size():
  var order:Variant=contracts[slot]
  if not order is Dictionary:return invalid
  var error:String=route_validation_error(order)
  if not error.is_empty():return error
  if not ReadableGuard.same([order.get("contract_id"),order.get("accepted_day"),order.get("status")],["D%d-%s"%[day,"A" if slot==0 else "B"],day,"available"]):return invalid
  if order.has("generation"):
   if not AuthoringPolicy.known_route(order) or not ReadableGuard.same([order.generation.get("world_seed"),order.generation.get("day"),order.generation.get("slot")],[offer_generation_state.world_seed,day,slot]):return invalid
  if PirateOffer.has_markers(order) and (not AuthoringPolicy.is_pirate_root(offer_generation_state) or not ReadableGuard.same(offer_generation_state.pirate_introduced_day,day)):return invalid
  if BirdOffer.has_markers(order) and (not AuthoringPolicy.is_bird_root(offer_generation_state) or not ReadableGuard.same(offer_generation_state.introduced_day,day)):return invalid
 return ""

func _new_seeded_offer(catalog:Dictionary,slot:int) -> Dictionary:
 if offer_generation_state.is_empty():return {}
 var kind:String="ground" if int(catalog.id)==0 else "ascent"
 if not int(catalog.id) in [0,1,2]:return {} # Moon/wormhole are not rewritten.
 var actor_id:String=Stories.IDS[posmod((day-1)*2+slot,Stories.IDS.size())]
 var fresh:Dictionary=_autonomous_routes()[int(catalog.id)]
 return AuthoringPolicy.author(catalog,fresh,offer_generation_state,day,slot,kind,actor_id)

func enable_story_mode() -> void:
 if review_load_blocked:return
 if story_state.is_empty():
  # This is the explicit new-shop boundary, never a render or reload path.
  # A private generator must not consume the physics/global random sequence.
  var cosmetics=RandomNumberGenerator.new();cosmetics.randomize()
  story_state=Stories.initial_state(cosmetics.randi_range(1,2147483646))
 story_mode=true
 ensure_contracts()
 _bind_story_contracts()

func _bind_story_contracts(new_contracts:bool=false) -> void:
 if not story_mode or story_state.is_empty():return
 for slot in range(contracts.size()):
  var order:Dictionary=contracts[slot]
  # Even an existing binding may not rewrite a committed dispatch or receipt.
  if not str(order.get("status","")) in ["available","accepted"]:continue
  if not route_validation_error(order).is_empty():continue
  # Future content is an opaque committed snapshot, including its customer,
  # parcel and saved copy. Current story templates cannot rebind that identity.
  if _opaque_generated_offer(order):continue
  # A fully registered saved identity must never be rebound on later loads.
  if (ReadableGuard.recognized(order) or PirateOffer.has_markers(order)) and order.has("appearance_seed"):continue
  var bound:Dictionary=Stories.bind_contract(story_state,order,day,slot)
  story_state=bound.state;order=bound.contract
  if bound.actor.is_empty():continue
  if new_contracts:order=Stories.author_new_parcel_presentation(order)
  if str(order.get("variant",""))=="重货件":order.cargo="加急补货 · "+str(order.cargo)
  var teaser:Dictionary=Stories.conversation_for(story_state,order,"accept")
  if not teaser.is_empty():teaser=_with_saved_opening(order,teaser)
  if not teaser.is_empty() and not teaser.lines.is_empty():order.story=str(teaser.lines[0].text)
  contracts[slot]=order

static func _opaque_generated_offer(order:Dictionary) -> bool:
 var metadata:Variant=order.get("generation")
 return metadata is Dictionary and not AuthoringPolicy.known_route(order)

static func _review_order(order:Dictionary) -> Dictionary:
 # Review-only projection shared by new receipts and old saved validation.
 # Opaque generated identity stays untouched in the actual contract/ledger.
 if not _opaque_generated_offer(order):return order
 var projected:Dictionary=order.duplicate(true);projected.appearance_id=""
 return projected

func story_actor(contract_id:String) -> Dictionary:
 for order in contracts:
  if str(order.get("contract_id",""))==contract_id and _opaque_generated_offer(order):return {}
 var binding:Variant=story_state.get("contract_bindings",{}).get(contract_id)
 if not binding is Dictionary:return {}
 var actor:Dictionary=Stories.actor_metadata(binding)
 if not actor.is_empty():actor.contract_id=contract_id
 return actor

func story_conversation(contract_id:String,beat:String) -> Dictionary:
 var order:Dictionary={"contract_id":contract_id}
 for item in contracts:
  if str(item.get("contract_id",""))==contract_id:order=item;break
 if _opaque_generated_offer(order):return {} # No current arc is guessed for future identity.
 if beat=="accept" and str(order.get("status",""))!="accepted":return {}
 # The financial ledger, not a display flag or estimate, authorizes receipts.
 if beat in ["result","return"] and not settled_ids.has(contract_id):return {}
 var conversation:Dictionary=Stories.conversation_for(story_state,order,beat)
 if conversation.is_empty():return {}
 if beat=="accept":conversation=_with_saved_opening(order,conversation)
 var route_name:String=str(order.get("name",settled_ids.get(contract_id,{}).get("route","")))
 # New receipts retain their own destination after next_day clears contracts.
 # Old success-only receipts keep the original financial-ledger fallback.
 var saved_context:Dictionary=story_state.get("committed_contract_ids",{}).get(contract_id,{}).get("route_context",{})
 if (beat=="accept" or saved_context.is_empty()) and not route_name.is_empty():conversation.route_hint=route_name
 conversation.actor.contract_id=contract_id
 return conversation

func _with_saved_opening(order:Dictionary,conversation:Dictionary) -> Dictionary:
 # No reroll, template lookup or RNG at dialogue time. Unknown content versions
 # keep their existing story instead of being interpreted as this version.
 var metadata:Variant=order.get("generation")
 if not metadata is Dictionary or not AuthoringPolicy.known_route(order):return conversation
 if not route_validation_error(order).is_empty():return conversation
 var saved:Dictionary=metadata.dialogue
 if str(conversation.get("actor",{}).get("appearance_id",""))!=str(saved.appearance_id):return conversation
 var result:Dictionary=conversation.duplicate(true)
 result.lines.push_front(saved.accept_lines[0].duplicate(true))
 return result

func pending_story_returns() -> Array:
 var result:Array=[]
 for contract_id in story_state.get("pending_returns",[]):
  var conversation:Dictionary=story_conversation(str(contract_id),"return")
  if not conversation.is_empty():result.append(conversation)
 return result

func mark_story_seen(contract_id:String,dialogue_id:String) -> bool:
 if not dialogue_id in [contract_id+"/accept",contract_id+"/result",contract_id+"/return"]:return false
 var beat:String=dialogue_id.get_slice("/",1)
 if story_conversation(contract_id,beat).is_empty():return false
 story_state=Stories.mark_seen(story_state,contract_id,dialogue_id)
 return true

# Explicit first-chapter opt-in. Call only on a new shop, before starter_stock.
# Loading old saves never invokes this; their available/accepted quotes stay put.
func enable_delivery_mode() -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if flight_mode==DeliveryProfile.VERSION and not delivery_chapter_state.is_empty():return {"ok":true,"changed":false}
 if not _loaded_save_path.is_empty() or day!=1 or jobs_today!=0 or deliveries!=0 or not contracts.is_empty() or not settled_ids.is_empty() or not history.is_empty() or not in_flight.is_empty():return _error("已有进度需通过首章迁移入口更换规则，原委托已保留。")
 flight_mode=DeliveryProfile.VERSION;delivery_chapter_state=DeliveryChapter.initial_state()
 return {"ok":true,"changed":true}

func delivery_chapter_status() -> Dictionary:
 if delivery_chapter_state.is_empty():return {"enabled":false,"complete":false,"chapter_id":1,"level":1,"debt":maxi(0,-credits)}
 var level:int=mini(DeliveryChapter.LEVEL_COUNT,int(delivery_chapter_state.unlocked_level))
 return {"enabled":true,"chapter_id":DeliveryChapter.chapter_for_level(level),"level":level,"unlocked_level":int(delivery_chapter_state.unlocked_level),"first_chapter_complete":int(delivery_chapter_state.unlocked_level)>DeliveryChapter.FIRST_CHAPTER_LEVEL_COUNT,"moon_complete":int(delivery_chapter_state.unlocked_level)>DeliveryChapter.MOON_LEVEL,"rift_complete":int(delivery_chapter_state.unlocked_level)>DeliveryChapter.LEVEL_COUNT,"complete":int(delivery_chapter_state.unlocked_level)>DeliveryChapter.LEVEL_COUNT,"debt":maxi(0,-credits)}

func _ensure_delivery_contracts() -> void:
 if not contracts.is_empty() or not in_flight.is_empty():return
 if not DeliveryChapter.state_error(delivery_chapter_state,settled_ids).is_empty():load_notice="首章进度记录不完整，原进度已保留。";return
 if not _new_batch_identity_error(day).is_empty():load_notice="今日委托身份已使用，原进度已保留。";return
 var recovery:bool=credits<0
 var complete:bool=int(delivery_chapter_state.unlocked_level)>DeliveryChapter.LEVEL_COUNT
 var level:int=1 if recovery else mini(DeliveryChapter.LEVEL_COUNT,int(delivery_chapter_state.unlocked_level))
 # After all five receipt-backed completions, future A quotes alternate the
 # two advanced routes. Existing batches returned above keep their exact terms.
 if complete and not recovery:
  level=DeliveryChapter.MOON_LEVEL if posmod(day,2)==1 else DeliveryChapter.LEVEL_COUNT
 # Only one of the alternating post-campaign rift repeats uses the wider cold route.
 var cold_repeat:bool=complete and not recovery and level==5 and posmod(day,4)==2
 # Only future empty batches author the mainline cold layout; saved quotes remain frozen.
 var cold_mainline:bool=not complete and not recovery and level==5
 var first:Dictionary=DeliveryChapter.offer(level,day,0,not recovery and not complete,recovery,false,cold_repeat,cold_mainline)
 # Both offers are frozen together. Success unlocks a new task only at the next
 # normal business-day boundary, never by rewriting an already displayed quote.
 # B naturally rotates through completed light/heavy/fragile content via the
 # documented day-modulo policy. Debt always offers light. Existing old batches
 # return above before this factory and retain their original rotation/geometry.
 var repeat_level:int=DeliveryChapter.repeat_level(delivery_chapter_state,day,recovery)
 # Alternate future fragile repeats only after receipt-backed level3 completion.
 # Existing displayed/accepted batches already returned above; debt stays light.
 var rockbelt:bool=not recovery and repeat_level==3 and delivery_chapter_state.completed_levels.has("3") and posmod(day,6)==5
 var second:Dictionary=DeliveryChapter.offer(repeat_level,day,1,false,recovery,rockbelt)
 for order in [first,second]:
  if order.is_empty() or not route_preflight_error(order).is_empty():load_notice="首章委托暂时无法整理，原进度已保留。";return
 contracts=[first,second]
 _bind_story_contracts(true)

func _settle_delivery_and_require_review(id:String,telemetry:Dictionary,elapsed:float,success:bool) -> Dictionary:
 var result:Dictionary=settle_contract(id,telemetry,elapsed,success)
 if result.ok and not bool(result.get("review_pending",false)):return _error("结算记录不完整，请稍后重试。")
 return result

func can_upgrade_delivery_mode() -> bool:
 if review_load_blocked or not delivery_chapter_state.is_empty() or flight_mode==DeliveryProfile.VERSION or not in_flight.is_empty():return false
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return false
 for order in contracts:
  if not order is Dictionary or order.get("status")=="in_flight":return false
 return true

func _delivery_upgrade_plan(snapshot:Dictionary) -> Dictionary:
 if not can_upgrade_delivery_mode():return {"available":false,"deferred":not in_flight.is_empty()}
 var candidate:Dictionary=snapshot.duplicate(true);var changes:Array=[]
 candidate.flight_mode=DeliveryProfile.VERSION;candidate.delivery_chapter_state=DeliveryChapter.initial_state()
 candidate.settings.delivery_chapter_schema=DeliveryChapter.STATE_SCHEMA
 for index in candidate.contracts.size():
  var old:Dictionary=candidate.contracts[index]
  if old.get("status")!="available":continue
  if not route_validation_error(old).is_empty():return {"available":false,"reason":"old_order_invalid"}
  var fresh:Dictionary=DeliveryChapter.offer(1,day,index,index==0 and credits>=0,credits<0)
  # Retain the exact identity/actor of an explicitly replaced unaccepted quote.
  # Accepted contracts and every old receipt remain byte-for-byte unchanged.
  for key in ["contract_id","accepted_day","appearance_id","appearance_seed","species","accessory_id","story_id","story_node","client"]:
   if old.has(key):fresh[key]=old[key]
  if not route_preflight_error(fresh).is_empty():return {"available":false,"reason":"new_order_unavailable"}
  candidate.contracts[index]=fresh
  changes.append({"contract_id":str(old.contract_id),"original_order_sha256":_accepted_order_digest(old),"replacement_order_sha256":_accepted_order_digest(fresh)})
 var token:String=_accepted_order_digest({"schema":DeliveryChapter.UPGRADE_SCHEMA,"source":snapshot,"orders":changes})
 return {"available":true,"candidate":candidate,"orders":changes,"confirmation_token":token,"replaced_count":changes.size(),"message":"进入首章运输：未接订单改为首章轻货，已接订单按原规则完成。实际损失可形成负债，不清零余额、不赠送库存；原存档另行备份。"}

func delivery_upgrade_preview(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 if not can_upgrade_delivery_mode():return {"available":false,"deferred":not in_flight.is_empty()}
 var source:Dictionary=_durable_transition_source(design,launcher,settings)
 if not source.ok:return {"available":false,"reason":source.get("reason","")}
 var plan:Dictionary=_delivery_upgrade_plan(source.snapshot)
 plan.erase("candidate");plan.erase("orders")
 return plan

func upgrade_delivery_mode_and_save(confirmation_token:String,design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 if flight_mode==DeliveryProfile.VERSION and not delivery_chapter_state.is_empty():return {"ok":true,"changed":false,"duplicate":true}
 var source:Dictionary=_durable_transition_source(design,launcher,settings)
 if not source.ok:return _error("进度尚未保存或已经变化，请重新查看首章迁移预览。")
 var plan:Dictionary=_delivery_upgrade_plan(source.snapshot)
 if not bool(plan.get("available",false)) or confirmation_token.is_empty() or confirmation_token!=str(plan.get("confirmation_token","")):return _error("首章迁移预览已变化，原进度已保留。")
 _shop_save_in_progress=true;_transition_source=source;_shop_backup_warning="";save_error=""
 var backup:Dictionary=_archive_transition(source.snapshot,"user://delivery-chapter-upgrade-v3")
 if not backup.ok:
  _shop_save_in_progress=false;_transition_source={};return _error("无法备份首章迁移前的原档，这次操作未保存。")
 var candidate:Dictionary=plan.candidate
 candidate.delivery_upgrade={"schema":DeliveryChapter.UPGRADE_SCHEMA,"day":day,"source_sha256":str(backup.source_sha256),"confirmation_token":confirmation_token,"orders":plan.orders.duplicate(true)}
 candidate.settings.delivery_upgrade_schema=DeliveryChapter.UPGRADE_SCHEMA
 var saved:Dictionary=_persist_transition_snapshot(candidate)
 _shop_save_in_progress=false;_transition_source={}
 if not saved.ok:return _error("首章迁移未能保存，原订单、余额与库存未改变。")
 flight_mode=DeliveryProfile.VERSION;contracts=candidate.contracts.duplicate(true)
 delivery_chapter_state=candidate.delivery_chapter_state.duplicate(true);delivery_upgrade=candidate.delivery_upgrade.duplicate(true)
 return {"ok":true,"changed":true,"settings":candidate.settings.duplicate(true),"replaced_count":plan.replaced_count,"message":"已进入首章运输，旧已接订单和账单保持原规则，原档已备份。"+(" "+_shop_backup_warning if not _shop_backup_warning.is_empty() else "")}

func routes() -> Array:
 if flight_mode==DeliveryProfile.VERSION:return DeliveryChapter.catalog()
 var values:Array=_autonomous_routes()
 if flight_mode==PilotProfile.CONTROL_VERSION:
  for i in range(values.size()):values[i]=PilotProfile.route(values[i])
 elif flight_mode==AscentProfile.CONTROL_VERSION:
  for i in range(values.size()):values[i]=AscentProfile.route(values[i])
 elif flight_mode==ExtremeProfile.CONTROL_VERSION:
  for i in range(values.size()):values[i]=ExtremeProfile.route(values[i])
 elif FreeProtocols.is_version(flight_mode):
  for i in range(values.size()):
   if i==0:values[i]=_new_free_offer(GroundProfile.route(values[i]))
   elif i in [1,2]:values[i]=_new_free_offer(ExtremeProfile.route(values[i]))
   else:values[i]=ExtremeProfile.route(values[i])
  if flight_mode==ForceProfile.VERSION:
   var lunar:Dictionary=ForceProfile.route(LunarRoute.fresh_catalog())
   if not lunar.is_empty():
    lunar.economy_policy=FREE_ECONOMY_POLICY;values.append(lunar)
   var mosslight:Dictionary=ForceProfile.route(MosslightRoute.fresh_catalog())
   if not mosslight.is_empty():
    mosslight.economy_policy=FREE_ECONOMY_POLICY;values.append(mosslight)
 return values

func _new_free_offer(base:Dictionary) -> Dictionary:
 # Fresh catalog only. Generated/special/committed snapshots never enter here.
 var result:Dictionary=ForceProfile.route(base) if flight_mode==ForceProfile.VERSION else FreeProfile.route(base)
 result.economy_policy=FREE_ECONOMY_POLICY
 result.reward=FREE_GROUND_REWARD if int(base.id)==0 else (275 if int(base.id)==1 else 330)
 result.risk="自行选择飞行方向 · 安全抵达即可 · 电量耗尽则失败"
 return result

func needs_recovery_orders() -> bool:
 # Read-only authoring choice. It never changes a saved order or forgives debt.
 return deliveries<2 or credits<FREE_RECOVERY_RESERVE or (not last_settlement.is_empty() and last_settlement.get("success")==false)

func enable_force_mode() -> void:
 if review_load_blocked:return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):
  load_notice="存档的驾驶规则暂不受支持，原航线已保留。";return
 # New authoring only. Existing available/accepted/in-flight identities remain.
 flight_mode=ForceProfile.VERSION

func enable_free_mode() -> void:
 if review_load_blocked:return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):
  load_notice="存档的驾驶规则暂不受支持，原航线已保留。";return
 # All existing offers (even available), receipts, trials and dispatches stay
 # frozen. Only a subsequent genuinely empty authoring boundary uses this mode.
 flight_mode=FreeProfile.CONTROL_VERSION

static func route_validation_error(route:Dictionary) -> String:
 if DeliveryChapter.has_markers(route) or DeliveryProfile.has_markers(route):return DeliveryChapter.route_error(route)
 # New ID7/partial content markers must never fall through an older reader.
 if MosslightRoute.has_markers(route) and not ForceProfile.validation_error(route).is_empty():return "这份苔光自由飞行记录不完整，原进度已保留。"
 # Any new/free marker requires the exact new protocol; never downgrade it.
 if FreeProtocols.has_markers(route):
  if not FreeProtocols.route_error(route).is_empty():return "这份自由飞行记录不完整，原进度已保留。"
  if route.has("economy_policy"):
   if route.economy_policy!=FREE_ECONOMY_POLICY:return "这份自由飞行费用规则暂不受支持，原记录已保留。"
   if not Reviews._integer(route.get("reward"),FREE_GROUND_REWARD,10000000) or not SeededGuard.number_in(route.get("required"),0.001,100.0) or not SeededGuard.number_in(route.get("deadline"),0.001,10000000.0):return "这份自由飞行费用记录不完整，原记录已保留。"
  return ""
 # Dedicated commercial markers precede the broad physical protocol reader.
 if PirateOffer.has_markers(route):
  return "" if PirateOffer.validation_error(route).is_empty() else "这份自选委托记录不完整，原进度已保留。"
 # Explicit new protocol only; no inference or migration from older routes.
 if PirateProtocols.has_markers(route):
  return "" if PirateProtocols.route_error(route).is_empty() else "这份航线暂时无法出发，原记录已保留。"
 if BirdOffer.has_markers(route):
  return "" if BirdOffer.validation_error(route).is_empty() else "这份航线记录不完整，暂时无法出发。"
 var generated_error:String=ReadableGuard.validation_error(route) if ReadableGuard.has_markers(route) else (MeteorOffers.validation_error(route) if MeteorOffers.has_markers(route) else SeededGuard.saved_metadata_error(route))
 if not generated_error.is_empty():return "这份航线记录不完整，暂时无法出发。"
 # Inspect explicit identity only. Never reauthor or guess from names/geometry.
 for key in ["control_version","pilot_profile","mode","route_profile","route_kind","destination_id"]:
  if route.has(key) and not route[key] is String:return "航线记录不完整，暂时无法出发。"
 var version:String=str(route.get("control_version",""))
 if not version in ([""]+PILOT_VERSIONS):return "这份航线使用了暂不支持的驾驶规则。"
 if str(route.get("mode",""))=="pilot" and version.is_empty():return "航线缺少驾驶规则，暂时无法出发。"
 if route.has("pilot_profile") and str(route.pilot_profile)!=version:return "航线的驾驶规则不一致，暂时无法出发。"
 # New Moon identity is content, not a new solver. Any partial marker must
 # validate before the v4 branch so mixed Moon/portal saves cannot slip through.
 if MoonProfile.has_moon_markers(route):return MoonProfile.validation_error(route)
 # Older known protocols keep their established route and replay semantics.
 # Portal markers on an older protocol cannot silently become a paid v4 trip.
 if version==WormholeProfile.CONTROL_VERSION:return WormholeProfile.validation_error(route)
 if str(route.get("route_profile",""))==WormholeProfile.ROUTE_PROFILE or route.has("wormhole_portal") or route.has("wormhole_schema"):
  return "虫洞航线的驾驶规则不一致，暂时无法出发。"
 return ""

func _can_upgrade_available(order:Dictionary) -> bool:
 # Available old offers keep the established migration policy. Acceptance is
 # the route commitment boundary, including before a first formal launch.
 if str(order.get("status",""))!="available" or order.has("generation"):return false
 if not route_validation_error(order).is_empty():return false
 return not str(order.get("control_version","")) in ([WormholeProfile.CONTROL_VERSION]+FreeProtocols.VERSIONS+PirateProtocols.VERSIONS) and not MoonProfile.has_moon_markers(order)

func enable_extreme_mode() -> void:
 if review_load_blocked:return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):
  load_notice="存档的驾驶规则暂不受支持，原航线已保留。";return
 var migrating:bool=flight_mode!=ExtremeProfile.CONTROL_VERSION
 # v3 stays the workshop/default authoring mode; v4 belongs to its own routes.
 flight_mode=ExtremeProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if _can_upgrade_available(contracts[i]) and str(contracts[i].get("control_version",""))!=ExtremeProfile.CONTROL_VERSION:contracts[i]=ExtremeProfile.route(contracts[i])
 if migrating and not in_flight.is_empty():
  load_notice="在途配送保留原版规则；之后的新委托支持全功率推进、接触钻头与撞击护盾。"

func enable_ascent_mode() -> void:
 if review_load_blocked:return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return
 var migrating:bool=flight_mode!=AscentProfile.CONTROL_VERSION
 flight_mode=AscentProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if _can_upgrade_available(contracts[i]):contracts[i]=AscentProfile.route(contracts[i])
 if migrating and not in_flight.is_empty():
  load_notice="已保留在途配送的原版规则；后续新委托采用向上穿云的升空航线。"

func enable_pilot_mode() -> void:
 if review_load_blocked:return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return
 var migrating:bool=flight_mode!=PilotProfile.CONTROL_VERSION
 flight_mode=PilotProfile.CONTROL_VERSION
 for i in range(contracts.size()):
  if _can_upgrade_available(contracts[i]):contracts[i]=PilotProfile.route(contracts[i])
 if migrating and not in_flight.is_empty() and str(in_flight.get("control_version",""))!=PilotProfile.CONTROL_VERSION:
  load_notice="已保留进行中的自主版配送；本次仍按旧规则恢复。后续新配送使用可操控航线。"

func _autonomous_routes() -> Array:
 return [
  {"id":0,"name":"晨星社区","client":"林奶奶","cargo":"耐寒种子","distance":64.0,"weight":1.0,"deadline":14.0,"time_limit":42.0,"required":85.0,"reward":165,"rep":0,"risk":"碎石门 · 保持外形紧凑","story":"这一箱种子，是温室今年的第一场春天。帮我稳稳地送过去吧。","gravity":0.0,"wind":0.0,"max_delivery_speed":24.0,"delivery_radius":5.0,"hazards":[{"x":35.0,"y":-2.6,"radius":1.15,"type":"rock"},{"x":35.0,"y":2.6,"radius":1.15,"type":"rock"}]},
  {"id":1,"name":"碎石回廊","client":"阿堇","cargo":"精密轴承","distance":82.0,"weight":1.5,"deadline":16.0,"time_limit":45.0,"required":90.0,"reward":220,"rep":2,"risk":"窄缝 · 大轮廓更危险","story":"修好这颗轴承，驿站的发电机就能重新转起来。","gravity":0.0,"wind":0.0,"max_delivery_speed":25.0,"delivery_radius":5.0,"hazards":[{"x":30.0,"y":-2.0,"radius":1.2,"type":"rock"},{"x":43.0,"y":2.1,"radius":1.25,"type":"rock"},{"x":61.0,"y":-2.0,"radius":1.2,"type":"rock"}]},
  {"id":2,"name":"寂静灯塔","client":"守塔人","cargo":"信号放大器","distance":108.0,"weight":2.0,"deadline":20.0,"time_limit":52.0,"required":75.0,"reward":280,"rep":4,"risk":"信号追踪海盗 · 普通炮台","story":"灯亮起来，回家的船才看得见路。","gravity":0.0,"wind":0.0,"max_delivery_speed":26.0,"delivery_radius":5.0,"hazards":[{"x":36.0,"y":-3.2,"radius":1.0,"type":"tracker","damage":10.0},{"x":70.0,"y":3.2,"radius":1.0,"type":"turret","damage":10.0}]},
  {"id":3,"name":"引力果园","client":"米洛","cargo":"玻璃蜂巢","distance":112.0,"weight":2.4,"deadline":23.0,"time_limit":55.0,"required":90.0,"reward":340,"rep":7,"risk":"局部引力 · 高完整度要求","story":"蜜蜂睡着了。请让它们在果园醒来。","gravity":0.0,"wind":0.0,"max_delivery_speed":24.0,"delivery_radius":6.0,"hazards":[{"x":47.0,"y":3.3,"radius":2.0,"type":"gravity","strength":8.0},{"x":80.0,"y":-2.6,"radius":1.2,"type":"rock"}]},
  {"id":4,"name":"远岸邮局","client":"小满","cargo":"一百封手写信","distance":146.0,"weight":2.8,"deadline":28.0,"time_limit":65.0,"required":85.0,"reward":410,"rep":10,"risk":"长航程 · 混合危险","story":"有些话，值得有人亲手送到。","gravity":0.0,"wind":0.0,"max_delivery_speed":27.0,"delivery_radius":6.0,"hazards":[{"x":37.0,"y":-2.4,"radius":1.2,"type":"rock"},{"x":70.0,"y":3.0,"radius":1.0,"type":"tracker","damage":10.0},{"x":106.0,"y":-2.7,"radius":1.3,"type":"rock"}]}
 ]

func ensure_contracts() -> void:
 if review_load_blocked:return
 if flight_mode==DeliveryProfile.VERSION:
  _ensure_delivery_contracts();return
 if not contracts.is_empty() or not in_flight.is_empty():return
 if not flight_mode in (["autonomous-v5"]+PILOT_VERSIONS):return
 if not offer_generation_state.is_empty() and not AuthoringPolicy.supported_root(offer_generation_state):
  load_notice="今日航线暂时无法整理，原进度已保留。请使用对应版本继续。";return
 if AuthoringPolicy.is_pirate_root(offer_generation_state) and not _new_batch_identity_error(day).is_empty():
  load_notice="今日委托身份已使用，原进度已保留。";return
 var available:Array=[]
 for route in routes():
  if reputation>=int(route.rep):
   # Content authoring boundary only: no existing order/snapshot passes here.
   # Only newly authored rep-7 offers open the otherworld lane. Existing
   # available, accepted, in-flight and settled orders never pass this boundary.
   if flight_mode in ([ExtremeProfile.CONTROL_VERSION]+FreeProtocols.VERSIONS):
    if int(route.id)==0 and flight_mode==ExtremeProfile.CONTROL_VERSION:route=GroundProfile.route(route)
    elif int(route.id)==WORMHOLE_ROUTE_ID and reputation>=WORMHOLE_REPUTATION:route=WormholeProfile.route(route)
    elif int(route.id)==MOON_ROUTE_ID and day>=MOON_FIRST_DAY and reputation>=MOON_REPUTATION:route=MoonProfile.route(route)
   # Filter only uncommitted catalog candidates after their exact content
   # conversion. Saved snapshots never reach this boundary, and an unbound
   # full-game model retains its complete historical selection order.
   if route_availability_error(route).is_empty():available.append(route)
 # ID7 extends only a wholly ordinary current pool. Removing this fresh
 # candidate from a mixed/legacy pool preserves its historical back() choice.
 if flight_mode==ForceProfile.VERSION and not _ordinary_force_pool(available):
  available=available.filter(func(candidate):return not MosslightRoute.has_markers(candidate))
 if available.is_empty():
  load_notice="当前没有可用的委托航线，原进度已保留。";return
 var first:Dictionary=available[(day-1)%available.size()].duplicate(true)
 var second:Dictionary=available.back().duplicate(true)
 var recovery_batch:bool=FreeProtocols.is_version(flight_mode) and needs_recovery_orders()
 # Only a fresh, entirely ordinary v2 pool opts into balanced route pairing.
 # Existing snapshots return above; mixed/legacy catalogs keep their old pair.
 if flight_mode==ForceProfile.VERSION and not recovery_batch and _ordinary_force_pool(available):
  var offset:int=maxi(1,floori(float(available.size())/2.0))
  second=available[((day-1)%available.size()+offset)%available.size()].duplicate(true)
 if recovery_batch:
  for candidate in available:
   if int(candidate.id)==0 and FreeProtocols.is_version(candidate.get("control_version")):
    first=candidate.duplicate(true);second=candidate.duplicate(true);break
 # Generate only at this already-existing empty-contract authoring boundary.
 # The explicit seed and both realized snapshots must be atomically saved by
 # the normal controller before presentation. Enabling never rerolls today.
 var generated_first:Dictionary=_new_seeded_offer(first,0) if flight_mode==ExtremeProfile.CONTROL_VERSION else {}
 var generated_second:Dictionary=_new_seeded_offer(second,1) if flight_mode==ExtremeProfile.CONTROL_VERSION else {}
 for outcome in [generated_first,generated_second]:
  if not outcome.is_empty() and not outcome.ok:
   load_notice="今日航线暂时无法整理，原进度已保留。请使用对应版本继续。";return # no reroll or silent new seed
 first.contract_id="D%d-A"%day;first.status="available";first.accepted_day=day;first.variant="标准件"
 second.contract_id="D%d-B"%day;second.status="available";second.accepted_day=day
 second.weight=float(second.weight)*1.55;second.reward=int(second.reward)+55;second.deadline=float(second.deadline)+3.0
 # Canonicalize only new explicit v4/Moon cargo at its creation boundary.
 # Multiplication can carry a low ULP that JSON normalizes on reload. Existing
 # orders never pass here and retain their saved commercial numbers verbatim.
 if str(second.get("control_version",""))==WormholeProfile.CONTROL_VERSION or MoonProfile.is_moon_route(second):second.weight=float("%.2f"%float(second.weight))
 second.cargo="加急补货 · "+str(second.cargo);second.variant="重货件"
 second.story="还有一箱加急补货。更重一些，运费也会多一些。先看看装置扛不扛得住。"
 if recovery_batch:
  # The already-priced low-risk follow-up is a real delivery, not a cash grant.
  # No new inventory, waived bill, bonus or reroll is awarded on failure.
  second.weight=first.weight;second.reward=first.reward
  second.cargo=first.cargo;second.variant="轻件续单"
  second.story="这箱也是轻件，送到屋顶收件台就好。按你的节奏来，记得留意电量。"
  first.recovery_offer=true;second.recovery_offer=true
 if not generated_first.is_empty():first=generated_first.offer
 if not generated_second.is_empty():second=generated_second.offer
 var introduced_bird:bool=false
 if flight_mode==ExtremeProfile.CONTROL_VERSION and AuthoringPolicy.selects_bird(offer_generation_state,day,reputation,first):
  var bird:Dictionary=BirdOffer.create_new_offer(AuthoringPolicy.bird_root(offer_generation_state),day,Stories.IDS[posmod((day-1)*2,Stories.IDS.size())])
  if not bird.ok:load_notice="保护区委托记录不完整，原进度已保留。";return
  # An unavailable optional introduction remains pending. Do not claim its
  # once-only ledger, change its seed, or replace an existing saved offer.
  if route_availability_error(bird.offer).is_empty():first=bird.offer;introduced_bird=true
 var introduced_pirate:bool=false
 if _pirate_authoring_in_progress and route_guard.is_valid() and flight_mode==ExtremeProfile.CONTROL_VERSION and AuthoringPolicy.selects_pirate(offer_generation_state,day,reputation,deliveries,credits,first):
  var pirate:Dictionary=_new_pirate_offer()
  # A malformed factory result rolls back the complete candidate morning.
  if not bool(pirate.get("ok",false)) or not pirate.get("offer") is Dictionary or not PirateOffer.validation_error(pirate.offer).is_empty():
   load_notice="自选委托记录不完整，原进度已保留。";return
  # Capability-off leaves the once-only introduction pending and ordinary B exact.
  if route_availability_error(pirate.offer).is_empty():second=pirate.offer;introduced_pirate=true
 # Deterministic generation may add a meteor to an otherwise ordinary catalog.
 # Its frozen policy cannot be silently rerolled/relabelled if art is missing.
 # Reject the whole uncommitted pair; transactional callers restore the night.
 for order in [first,second]:
  var unavailable:String=route_availability_error(order)
  if not unavailable.is_empty():load_notice=unavailable;return
 if introduced_bird:
  offer_generation_state=offer_generation_state.duplicate(true);offer_generation_state.introduced_day=day
 if introduced_pirate:
  offer_generation_state=offer_generation_state.duplicate(true);offer_generation_state.pirate_introduced_day=day
 contracts=[first,second]
 _bind_story_contracts(true)

func _ordinary_force_pool(available:Array) -> bool:
 if available.is_empty() or available.size()>5:return false
 var seen:Dictionary={}
 for candidate in available:
  if not candidate is Dictionary:return false
  if not candidate.get("id") in [0,1,2,6,7] or candidate.get("control_version")!=ForceProfile.VERSION:return false
  if candidate.get("economy_policy")!=FREE_ECONOMY_POLICY or not ForceProfile.validation_error(candidate).is_empty():return false
  if seen.has(candidate.id):return false
  seen[candidate.id]=true
 return true

func _new_pirate_offer() -> Dictionary:
 return PirateOffer.create_new_offer(offer_generation_state,day,Stories.IDS[posmod((day-1)*2+1,Stories.IDS.size())])

func contract_by_id(id:String) -> Dictionary:
 ensure_contracts()
 for item in contracts:
  if str(item.contract_id)==id:return item
 return {}

func active_contract() -> Dictionary:
 return contract_by_id(active_contract_id) if not active_contract_id.is_empty() else {}

func available_contracts() -> Array:
 ensure_contracts()
 return contracts.filter(func(c):return str(c.status)=="available")

func accept_contract(id:String) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 ensure_contracts()
 if phase=="night":return _error("已经收工。明早再接新件。")
 if jobs_today>=DISPATCHES_PER_DAY:return _error("今天的发货席位已用完，先收工吧。")
 if not in_flight.is_empty():return _error("上一份委托仍在配送中。")
 var active=active_contract()
 if not active.is_empty() and active.status=="accepted" and str(active.contract_id)!=id:return _error("先处理柜台上已接下的那份委托。")
 var order=contract_by_id(id)
 if order.is_empty():return _error("这份委托已被处理，不能重复领取。")
 var route_error:String=route_preflight_error(order)
 if not route_error.is_empty():return _error(route_error)
 if str(order.get("status",""))!="available":return _error("这份委托已被处理，不能重复领取。")
 if reputation<int(order.rep):return _error("客户还没有开放这条航线。")
 order.status="accepted";order.cargo_loaded=false;active_contract_id=id;phase="day"
 return {"ok":true,"contract":order}

# Keep the unsaved methods as the legacy model API. These bounded wrappers
# cover implicit offer/story creation and review normalization as well as the
# visible purchase/decision. No UI callback sees a success before persistence.
func accept_contract_and_save(id:String,design:Array,launcher:Array,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(accept_contract.bind(id),design,launcher,settings,prepare)

func decline_available_and_save(id:String,design:Array,launcher:Array,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(decline_available.bind(id),design,launcher,settings,prepare)

func cancel_accepted_and_save(design:Array,launcher:Array,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(cancel_accepted,design,launcher,settings,prepare)

func close_day_and_save(design:Array,launcher:Array,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(close_day,design,launcher,settings,prepare)

func buy_part_and_save(type:String,spec:Dictionary,design:Array,launcher:Array,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(buy_part.bind(type,spec),design,launcher,settings,prepare)

func research_upgrade_and_save(design:Array,launcher:Array,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(research_upgrade,design,launcher,settings,prepare)

func _shop_mutation_and_save(mutation:Callable,design:Array,launcher:Array,settings:Dictionary,prepare:Callable) -> Dictionary:
 if _shop_save_in_progress:return _error("正在保存这次操作，请稍候。")
 # Own the whole candidate lifetime, including route/prepare callbacks. A
 # nested shop action must never commit against a partially mutated candidate.
 _shop_save_in_progress=true
 var previous:Dictionary={}
 for key in SHOP_TRANSACTION_FIELDS:
  var value:Variant=get(key)
  # Work on detached candidates: HUD/other holders of old dictionaries must
  # not observe an accepted order or stock change even through a stale alias.
  previous[key]=value
  if value is Array or value is Dictionary:set(key,value.duplicate(true))
 save_error="";_shop_backup_warning=""
 var result:Dictionary=mutation.call()
 if bool(result.get("ok",false)):
  # Main may check its replay guard and checkpoint here, but cannot substitute
  # for the real save below. Failure injection remains a test-only override.
  var prepared:bool=not prepare.is_valid() or bool(prepare.call())
  var saved:bool=prepared and save_state(design,launcher,settings)
  if saved:
   if not _shop_backup_warning.is_empty():
    result=result.duplicate(true)
    result.message=(str(result.get("message",""))+" " +_shop_backup_warning).strip_edges()
   _shop_save_in_progress=false
   return result
  result=_error(save_error if not save_error.is_empty() else "这次操作未能保存，原进度已保留。请重试。")
 for key in previous:set(key,previous[key])
 _shop_save_in_progress=false
 return result

func is_cargo_loaded(contract_id:String="") -> bool:
 var order:Dictionary=active_contract() if contract_id.is_empty() else contract_by_id(contract_id)
 var value:Variant=order.get("cargo_loaded",false)
 return value is bool and value

func mark_cargo_loaded(contract_id:String) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var order:Dictionary=active_contract()
 if order.is_empty() or str(order.get("contract_id",""))!=contract_id or str(order.get("status",""))!="accepted":return _error("这份货物已不在待装订单中。")
 var route_error:String=route_preflight_error(order)
 if not route_error.is_empty():return _error(route_error)
 var changed:bool=not is_cargo_loaded(contract_id)
 order.cargo_loaded=true
 return {"ok":true,"changed":changed}

func decline_available(id:String) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var order=contract_by_id(id)
 if phase=="night" or order.is_empty() or order.status!="available":return _error("这位客户已不在等待接单。")
 order.status="declined"
 return {"ok":true,"message":"已婉拒这份委托，客户会另作安排。"}

func cancel_accepted() -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var order=active_contract()
 if order.is_empty() or order.status!="accepted":return _error("没有可以退回的待发委托。")
 order.status="cancelled";active_contract_id="";reputation=maxi(0,reputation-1)
 return {"ok":true,"message":"货物退回客户，声望 -1。"}

func begin_dispatch(design:Array,launcher:Array,launch_settings:Dictionary={}) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var order=active_contract()
 if phase=="night" or order.is_empty() or order.status!="accepted":return _error("先在柜台确认一份待发委托。")
 var route_error:String=route_preflight_error(order)
 if not route_error.is_empty():return _error(route_error)
 if not in_flight.is_empty():return _error("不能重复发射同一份委托。")
 if jobs_today>=DISPATCHES_PER_DAY:return _error("今天的发货席位已用完。")
 if DeliveryChapter.is_version(order.get("control_version")):
  if launch_settings.is_empty():launch_settings={"angle_degrees":0.0,"power_fraction":1.0}
  var launch_error:String=DeliveryChapter.launch_settings_error(launch_settings)
  if not launch_error.is_empty():return _error(launch_error)
 if story_mode and not is_cargo_loaded(str(order.contract_id)):return _error("货物还没有装入飞船。请先让机器人完成装货。")
 order.status="in_flight";phase="day"
 var route=order.duplicate(true);route.variation=float(order.get("variation",1.0));route.battery_capacity_multiplier=1.0+0.15*research
 in_flight={"contract_id":order.contract_id,"design":design.duplicate(true),"launcher":launcher.duplicate(true),"route":route,"seed":day*100+int(order.id)*3+(1 if str(order.contract_id).ends_with("B") else 0),"elapsed":0.0}
 if BirdOffer.has_markers(route) or PirateOffer.has_markers(route):in_flight.seed=int(route.seed)
 if str(route.get("control_version","")) in PILOT_VERSIONS:
  in_flight.control_version=str(route.control_version);in_flight.input_commands=[{"tick":0,"axis_q":0,"boost":false,"active":false}];in_flight.ticks=0
  if DeliveryChapter.is_version(route.control_version):
   in_flight.input_schema=DeliveryTimeline.INPUT_SCHEMA
   in_flight.input_commands=DeliveryTimeline.new().snapshot()
   in_flight.launch_settings=launch_settings.duplicate(true)
   in_flight.launch_released=false;in_flight.launch_preparation={"age":0.0,"transfer_remaining":0.0}
  elif FreeProtocols.is_version(route.control_version):
   in_flight.input_schema=FreeProtocols.input_schema(route.control_version)
   in_flight.input_commands=FreeProtocols.initial_commands(route.control_version)
 else:in_flight.simulation_version="autonomous-v5"
 return {"ok":true,"snapshot":in_flight}

# The configured simulator remains Main-owned. This transaction freezes the
# exact trial route (including seed) rather than reinterpreting it after commit.
func begin_prepared_dispatch_and_save(craft:Array,pad:Array,prepared_route:Dictionary,settings:Dictionary,prepare:Callable=Callable()) -> Dictionary:
 return _shop_mutation_and_save(_begin_prepared_dispatch.bind(craft,pad,prepared_route),craft,pad,settings,prepare)

func _begin_prepared_dispatch(craft:Array,pad:Array,prepared_route:Dictionary) -> Dictionary:
 if not PirateProtocols.is_version(prepared_route.get("control_version")):return _error("这份航线暂时无法出发。")
 if var_to_bytes(trial_route())!=var_to_bytes(prepared_route):return _error("委托已变化，请重新试飞后出发。")
 var result:Dictionary=begin_dispatch(craft,pad)
 if not result.ok:return result
 # Status is business state on the order. The initial physics snapshot stays
 # byte-identical to the prepared/trial route, including accepted status.
 in_flight.route=prepared_route.duplicate(true);in_flight.seed=int(prepared_route.seed)
 if not _pirate_dispatch_coupling_error(in_flight).is_empty():return _error("配送身份记录不一致，原进度已保留。")
 return {"ok":true,"snapshot":in_flight}

func save_pirate_replay_and_save(snapshot:Dictionary,craft:Array,pad:Array,settings:Dictionary) -> Dictionary:
 return _shop_mutation_and_save(_replace_pirate_replay.bind(snapshot),craft,pad,settings,Callable())

func _replace_pirate_replay(snapshot:Dictionary) -> Dictionary:
 # This mutation commits a paid dispatch, unlike the contract-optional
 # stateless replay helper. Bind it to existing order state without authoring.
 if review_load_blocked or active_contract_id.is_empty() or settled_ids.has(active_contract_id):return _error("配送记录未能保存，原记录已保留。")
 if not _pirate_dispatch_coupling_error(snapshot).is_empty():return _error("配送身份记录不一致，原进度已保留。")
 for record in [in_flight,snapshot]:
  if not record.get("contract_id") is String or record.contract_id!=active_contract_id:return _error("配送记录未能保存，原记录已保留。")
 var committed_order:Dictionary={}
 for candidate in contracts:
  if not candidate is Dictionary or not candidate.get("contract_id") is String:continue
  if candidate.contract_id!=active_contract_id:continue
  if not committed_order.is_empty():return _error("配送记录未能保存，原记录已保留。")
  committed_order=candidate
 if committed_order.is_empty() or not committed_order.get("status") is String or committed_order.status!="in_flight":return _error("配送记录未能保存，原记录已保留。")
 if not route_validation_error(committed_order).is_empty():return _error("配送记录未能保存，原记录已保留。")
 if not PirateProtocols.is_version(snapshot.get("control_version")) or in_flight.is_empty() or not PirateProtocols.is_version(in_flight.get("control_version")) or snapshot.get("control_version")!=in_flight.get("control_version"): return _error("配送记录未能保存，原记录已保留。")
 if committed_order.control_version!=snapshot.control_version:return _error("配送记录未能保存，原记录已保留。")
 for key in ["contract_id","route","seed","design","launcher"]:
  if var_to_bytes(snapshot.get(key))!=var_to_bytes(in_flight.get(key)):return _error("配送记录已变化，原记录已保留。")
 if not replay_protocol_error(snapshot).is_empty():return _error("配送记录未能保存，原记录已保留。")
 in_flight=snapshot.duplicate(true)
 return {"ok":true}

func trial_route() -> Dictionary:
 if review_load_blocked:return {}
 var order=active_contract()
 if review_load_blocked or order.is_empty() or not route_preflight_error(order).is_empty():return {}
 var route=order.duplicate(true);route.variation=float(order.get("variation",1.0));route.battery_capacity_multiplier=1.0+0.15*research
 route.seed=int(order.seed) if BirdOffer.has_markers(order) or PirateOffer.has_markers(order) else day*100+int(order.id)*3+(1 if str(order.contract_id).ends_with("B") else 0)
 return route

static func energy_tariff(order:Dictionary) -> float:
 if DeliveryChapter.is_version(order.get("control_version")):return float(order.get("pilot_energy_tariff",0.025))
 return clampf(float(order.get("pilot_energy_tariff",AscentProfile.ENERGY_TARIFF)),.001,.18) if str(order.get("control_version","")) in ([AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION,WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION]+FreeProtocols.VERSIONS+PirateProtocols.VERSIONS) else .18

func estimate_delivery(order:Dictionary,telemetry:Dictionary,elapsed:float,success:bool) -> Dictionary:
 if DeliveryChapter.is_version(order.get("control_version")):return DeliveryChapter.quote(order,telemetry,success)
 var integrity:float=float(telemetry.get("integrity",0))
 if integrity<=1.0:integrity*=100.0
 var free_flight:bool=FreeProtocols.is_version(order.get("control_version")) and FreeProtocols.route_error(order).is_empty()
 var time_factor:float=1.0 if free_flight else clampf(float(order.deadline)/maxf(elapsed,float(order.deadline)),.35,1)
 var quality_factor:float=clampf(integrity/float(order.required),0,1)
 var insured:bool=free_flight and order.get("economy_policy")==FREE_ECONOMY_POLICY
 # The prospective contract pays half for delivery, half for condition.
 # This is an authored fee, never a retroactive minimum-profit grant.
 var income_factor:float=0.5+0.5*quality_factor if insured else quality_factor
 var income:int=int(int(order.reward)*time_factor*income_factor) if success else 0
 var tariff:float=energy_tariff(order)
 var energy:int=int(ceil(float(telemetry.get("energy_used",0))*tariff))
 var ammo:int=int(ceil(float(telemetry.get("ammo_cost",0))))
 var repairs:int=int(ceil(float(telemetry.get("repair_cost",0))))
 var lost:int=int(ceil(float(telemetry.get("lost_cost",0))))
 var quote:Dictionary={"income":income,"energy":energy,"energy_tariff":tariff,"ammo":ammo,"repairs":repairs,"lost":lost,"profit":income-energy-ammo-repairs-lost}
 if insured:
  var actual_costs:int=energy+ammo+repairs+lost
  var cap:int=FREE_SUCCESS_CHARGE_CAP if success else mini(FREE_FAILURE_CHARGE_CAP,maxi(0,credits))
  var charged_costs:int=mini(actual_costs,cap)
  quote.merge({"control_version":str(order.control_version),"economy_policy":FREE_ECONOMY_POLICY,"actual_costs":actual_costs,"charged_costs":charged_costs,"insurance_coverage":actual_costs-charged_costs,"charge_cap":cap,"profit":income-charged_costs},true)
 if str(order.get("control_version","")) in [WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION]:
  # The simulator already includes station draw in energy_used. These fields
  # explain that same bill; do not add or separately round a second charge.
  quote.energy_j=float(telemetry.get("energy_used",0.0))
  quote.wormhole_energy_j=float(telemetry.get("wormhole_energy_used",0.0))
  quote.wormhole_transits=int(telemetry.get("wormhole_transits",0))
  quote.wormhole_station_remaining=float(telemetry.get("wormhole_station_remaining",order.get("wormhole_portal",{}).get("station_energy_j",0.0)))
 return quote

func settle_contract(id:String,telemetry:Dictionary,elapsed:float,success:bool,completion:Dictionary={}) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if settled_ids.has(id):return {"ok":false,"duplicate":true,"message":"该委托已结算。","report":settled_ids[id]}
 var order=contract_by_id(id)
 if order.is_empty() or not order.get("status") is String or order.status!="in_flight":return _error("只有已正式发射的委托可以结算。")
 var route_error:String=route_preflight_error(order)
 if not route_error.is_empty():return _error(route_error)
 var chapter_flight:bool=DeliveryChapter.is_version(order.get("control_version"))
 var portal_evidence:Dictionary={}
 if chapter_flight:
  if active_contract_id!=id or in_flight.get("contract_id")!=id or not DeliveryChapter.snapshot_error(in_flight).is_empty():return _error("首章配送记录不一致，原进度已保留。")
  var committed:Dictionary=order.duplicate(true);var frozen:Dictionary=in_flight.route.duplicate(true)
  for key in ["status","variation","battery_capacity_multiplier","seed"]:committed.erase(key);frozen.erase(key)
  if not Shape_equal(committed,frozen):return _error("首章订单要求已变化，原记录已保留。")
  var telemetry_error:String=DeliveryChapter.telemetry_error(telemetry,elapsed)
  if not telemetry_error.is_empty():return _error(telemetry_error)
  if DeliveryChapter.is_cell_version(order.get("control_version")) and (not telemetry.get("control_version") is String or telemetry.control_version!=order.control_version):return _error("组合物理结果与已接订单版本不一致。")
  if telemetry.has("min_delivery_integrity") and (not SeededGuard.number_in(telemetry.min_delivery_integrity,0.0,1.0) or float(telemetry.min_delivery_integrity)!=float(order.min_delivery_integrity)):return _error("交付完整度要求与订单不一致。")
  if not DeliveryChapter.state_error(delivery_chapter_state,settled_ids).is_empty():return _error("首章进度记录不完整，原记录已保留。")
  if not bool(in_flight.launch_released):
   if success or DeliveryChapter.integrity_of(telemetry)!=1.0:return _error("发射准备尚未释放，无法记录飞行结果。")
   for key in ["energy_used","ammo_cost","repair_cost","lost_cost"]:
    if float(telemetry[key])!=0.0:return _error("发射准备尚未释放，不能扣取飞行损失。")
  if DeliveryChapter.is_rift_version(order.get("control_version")):
   var portal_capture:Dictionary=DeliveryChapter.capture_portal_evidence(order,in_flight,telemetry,success)
   if not portal_capture.ok:return _error("门户通行证据不完整，配送记录已保留。")
   portal_evidence=portal_capture.evidence
  success=success and DeliveryChapter.integrity_of(telemetry)>=float(order.min_delivery_integrity)
  if not SeededGuard.integer_in(credits,-DeliveryChapter.SAFE_INT,DeliveryChapter.SAFE_INT):return _error("余额记录无效，原记录已保留。")
 if PirateProtocols.is_version(order.get("control_version")):
  # Check the still-present committed identity BEFORE any evidence is cleared
  # or ledger, reputation, customer progression or review facts can change.
  if not _pirate_dispatch_coupling_error(in_flight).is_empty():return _error("配送身份记录不一致，原进度已保留。")
  # Validate untrusted values before comparing them with committed Strings.
  if not replay_protocol_error(in_flight).is_empty():return _error("这次配送暂时无法结算，记录已保留。")
  for value in [order.get("contract_id"),in_flight.get("contract_id"),in_flight.get("control_version")]:
   if not value is String:return _error("这次配送暂时无法结算，记录已保留。")
  if active_contract_id!=id or order.contract_id!=id or in_flight.contract_id!=id or in_flight.control_version!=order.control_version:return _error("这次配送暂时无法结算，记录已保留。")
  var pirate_error:String=_pirate_completion_error(telemetry,success,completion,str(order.control_version))
  if not pirate_error.is_empty():return _error(pirate_error)
 if not chapter_flight and FreeProtocols.is_version(order.get("control_version")):
  # Only finalization may change the account; invalid signed quantities cannot
  # mint money via a negative cost or a malformed replay identity.
  if active_contract_id!=id or in_flight.get("contract_id")!=id or not replay_protocol_error(in_flight).is_empty():return _error("自由飞行配送记录不一致，原进度已保留。")
  var expected_order:Dictionary=order.duplicate(true);var captured_order:Dictionary=in_flight.route.duplicate(true)
  for key in ["status","variation","battery_capacity_multiplier","seed"]:expected_order.erase(key);captured_order.erase(key)
  if not Shape_equal(expected_order,captured_order):return _error("自由飞行配送身份已变化，原进度已保留。")
  if not SeededGuard.number_in(elapsed,0.0,10000000.0):return _error("配送用时记录不完整，原进度已保留。")
  if not SeededGuard.number_in(telemetry.get("integrity"),0.0,100.0):return _error("货物状态记录不完整，原进度已保留。")
  for key in ["energy_used","ammo_cost","repair_cost","lost_cost"]:
   if not SeededGuard.number_in(telemetry.get(key,0.0),0.0,10000000.0):return _error("配送费用记录不完整，原进度已保留。")
 var bird_capture:Dictionary={}
 if BirdOffer.has_markers(order):
  bird_capture=BirdSettlement.capture(order,in_flight,telemetry,elapsed,success,completion)
  if not bird_capture.ok:
   var rejected:Dictionary=_error("这次配送暂时无法结算，记录已保留。")
   rejected.diagnostic_error=bird_capture.error
   return rejected
 var integrity:float=DeliveryChapter.integrity_of(telemetry)*100.0 if chapter_flight else float(telemetry.get("integrity",0.0))
 if not chapter_flight and integrity<=1.0:integrity*=100.0
 integrity=clampf(integrity,0.0,100.0)
 var quote=estimate_delivery(order,telemetry,elapsed,success)
 if chapter_flight and absf(float(credits)+float(quote.profit))>float(DeliveryChapter.SAFE_INT):return _error("结算金额超出有效范围，原记录已保留。")
 var base_income:int=int(order.reward)
 var income:int=int(quote.income);var energy:int=int(quote.energy);var ammo:int=int(quote.ammo);var repairs:int=int(quote.repairs);var lost:int=int(quote.lost);var profit:int=int(quote.profit)
 var free_flight:bool=chapter_flight or FreeProtocols.is_version(order.get("control_version"))
 var timely:bool=free_flight or elapsed<=float(order.deadline)
 var intact:bool=DeliveryChapter.integrity_of(telemetry)>=float(order.min_delivery_integrity) if chapter_flight else integrity>=float(order.required)
 var rep_change:int=(2 if timely and intact else 1) if success else -1
 var review:String
 if not success:review="没有等到货。下次发射前，咱们把问题找清楚吧。"
 elif not intact:review="货送到了，不过里面有破损。下次能不能更稳一些？"
 elif not timely:review="箱子完好。只是等得有些着急，下次早点到就更好了。"
 else:review="包装完整，谢谢你把这份心意送到了。" if free_flight else "准时，包装也完整。谢谢你把这份心意送到了。"
 last_settlement={"contract_id":id,"income":income,"base_income":base_income,"income_adjustment":income-base_income,"energy":energy,"ammo":ammo,"repairs":repairs,"lost":lost,"profit":profit,"success":success,"integrity":integrity,"required":order.required,"elapsed":elapsed,"deadline":order.deadline,"reputation":rep_change,"review":review,"route":order.name,"client":order.client,"day":day,"restored":true,"replenishment":"费用含自动补件与维修，装置已恢复为发射前方案。"}
 last_settlement.energy_tariff=quote.energy_tariff
 if free_flight:
  last_settlement.control_version=str(order.control_version)
  if order.get("economy_policy")==FREE_ECONOMY_POLICY:
   for key in ["economy_policy","actual_costs","charged_costs","insurance_coverage","charge_cap"]:last_settlement[key]=quote[key]
  last_settlement.delivery_policy=FreeProfile.MARKERS.delivery_policy
  last_settlement.energy_j=float(telemetry.get("energy_used",0.0))
  last_settlement.replenishment="发射前装置已恢复；驿站承担保障费用，无需另购丢失零件。"
 if chapter_flight:
  last_settlement.merge(quote,true)
  if not portal_evidence.is_empty():last_settlement.portal_delivery_evidence=portal_evidence
  last_settlement.credits_before=credits;last_settlement.credits_after=credits+profit
  last_settlement.debt=maxi(0,-int(last_settlement.credits_after))
  last_settlement.debt_added=maxi(0,int(last_settlement.debt)-maxi(0,-credits))
  last_settlement.level_completed=DeliveryChapter.advance(delivery_chapter_state,order,last_settlement)
  last_settlement.replenishment="按实际损失收费后恢复发射前装配；余额不足记入负债，不补贴或赠送库存。"
  last_settlement.review="完整度达到本单要求，客户已签收。" if success else ("货物完整度低于本单要求，未合格交付；实际损失已入账。" if not intact else "配送未完成，实际损失已入账。")
  last_settlement.route_context={"route_profile":order.route_profile,"route_kind":order.route_kind,"destination_id":order.destination_id,"route_name":order.name,"destination_name":order.destination_name}
 if str(order.get("control_version","")) in [WormholeProfile.CONTROL_VERSION,BirdProfile.CONTROL_VERSION]:
  for key in ["energy_j","wormhole_energy_j","wormhole_transits","wormhole_station_remaining"]:last_settlement[key]=quote[key]
  last_settlement.control_version=str(order.control_version)
  last_settlement.route_context={"route_profile":order.route_profile,"route_name":order.name,"destination_name":order.destination_name}
 if MoonProfile.is_moon_route(order):
  # Receipt copy identifies the actual destination after next_day removes offers.
  # Energy was already billed once by estimate_delivery; Moon adds no fee/reward.
  last_settlement.control_version=str(order.control_version)
  last_settlement.route_context={"route_profile":order.route_profile,"route_kind":order.route_kind,"destination_id":order.destination_id,"route_name":order.name,"destination_name":order.destination_name}
 if LunarRoute.has_markers(order) and LunarRoute.validation_error(order).is_empty():
  last_settlement.control_version=str(order.control_version)
  last_settlement.route_context={"route_profile":order.route_profile,"route_kind":order.route_kind,"destination_id":order.destination_id,"route_name":order.name,"destination_name":order.destination_name}
 if MosslightRoute.has_markers(order) and MosslightRoute.validation_error(order).is_empty():
  last_settlement.control_version=str(order.control_version)
  last_settlement.route_context={"route_profile":order.route_profile,"route_kind":order.route_kind,"destination_id":order.destination_id,"route_name":order.name,"destination_name":order.destination_name}
  if success and not Stories.parcel_presentation_id(order).is_empty():last_settlement.parcel_presentation_id=Stories.parcel_presentation_id(order)
 if PirateProtocols.is_version(order.get("control_version")):
  last_settlement.control_version=order.control_version
  last_settlement.energy_j=float(telemetry.get("energy_used",0.0))
  last_settlement.route_terminal=completion.terminal.duplicate(true)
  last_settlement.erase("review") # Pending facts publish through next_day only.
 if not bird_capture.is_empty():
  last_settlement.wildlife_evidence=bird_capture.evidence
  last_settlement.erase("review") # This version stores facts now; customer copy is authored next morning.
 credits+=profit;reputation=maxi(0,reputation+rep_change);jobs_today+=1
 if success:deliveries+=1
 order.status="settled";order.success=success
 # New receipts retain review-only destination/appearance evidence even after
 # contracts are cleared. This does not reinterpret older missing evidence.
 var review_order:Dictionary=_review_order(order)
 last_settlement.review_context={"version":Reviews.VERSION,"destination_name":review_order.get("destination_name",order.name),"appearance_id":review_order.get("appearance_id","")}
 settled_ids[id]=last_settlement.duplicate(true)
 history.push_front(last_settlement.duplicate(true))
 if history.size()>30:history.pop_back()
 var story_advanced:bool=false
 if not _opaque_generated_offer(order) and not story_state.is_empty() and story_state.get("contract_bindings",{}).has(id):
  # Accounting/status/unique-ID commit is complete before story advancement.
  # Success and failure both receive one receipt; neither story grants rewards.
  var committed:Dictionary=Stories.commit_settlement(story_state,order,last_settlement)
  story_state=committed.state;story_advanced=bool(committed.advanced)
 # Only the authoritative unique formal receipt can create pending facts.
 # Future content keeps its own client/parcel/appearance snapshot. Reviews
 # can still report the real outcome with generic wording, without pretending
 # an unknown identity belongs to one of our current recurring characters.
 var review_capture:Dictionary=Reviews.capture_settlement(review_state,review_order,settled_ids,day)
 if review_capture.ok:review_state=review_capture.state
 else:load_notice="这份客户留言未能记录，配送账单已保留。"
 in_flight={};active_contract_id=""
 # Direct, unsaved legacy callers retain accounting semantics but must inspect
 # this explicit outcome. The player-facing transactional API below is strict.
 return {"ok":true,"report":last_settlement,"story_advanced":story_advanced,"review_pending":bool(review_capture.ok),"review_error":str(review_capture.get("reason",""))}

static func _pirate_completion_error(telemetry:Dictionary,success:bool,completion:Dictionary,expected_version:String=PirateProfile.VERSION) -> String:
 var message:String="这次配送暂时无法结算，记录已保留。"
 if not telemetry.get("control_version") is String or not telemetry.get("chrono_error","") is String:return message
 if not completion.get("control_version") is String or not completion.get("status") is String:return message
 if not PirateProtocols.is_version(expected_version) or telemetry.control_version!=expected_version or not telemetry.get("chrono_error","").is_empty():return message
 if completion.control_version!=expected_version or completion.status!=("success" if success else "failed"):return message
 var terminal:Variant=completion.get("terminal")
 if not terminal is Dictionary or terminal.is_empty() or var_to_bytes(terminal)!=var_to_bytes(telemetry.get("route_terminal")):return message
 if not terminal.get("kind") is String:return message
 var kind:String=terminal.kind
 if success and not kind in ["receiver","delivered"]:return message
 if not success and not kind in ["abort","cargo_dead","receiver_speed","timeout","left","right","top","bottom"]:return message
 return ""

func _settle_pirate_and_require_review(id:String,telemetry:Dictionary,elapsed:float,success:bool,completion:Dictionary) -> Dictionary:
 if completion.has("checkpoint") and not settled_ids.has(id):
  if not completion.checkpoint is Dictionary:return _error("配送记录未能保存，原记录已保留。")
  var checked:Dictionary=_replace_pirate_replay(completion.checkpoint)
  if not checked.ok:return checked
 var result:Dictionary=settle_contract(id,telemetry,elapsed,success,completion)
 if result.ok and not bool(result.get("review_pending",false)):return _error("结算记录不完整，请稍后重试。")
 return result

func settle_contract_and_save(id:String,telemetry:Dictionary,elapsed:float,success:bool,design:Array,launcher:Array,settings:Dictionary,completion:Dictionary={}) -> Dictionary:
 if DeliveryChapter.is_version(contract_by_id(id).get("control_version")):
  return _shop_mutation_and_save(_settle_delivery_and_require_review.bind(id,telemetry,elapsed,success),design,launcher,settings,Callable())
 if PirateProtocols.is_version(contract_by_id(id).get("control_version")):
  return _shop_mutation_and_save(_settle_pirate_and_require_review.bind(id,telemetry,elapsed,success,completion),design,launcher,settings,Callable())
 var previous:Dictionary={}
 for key in ["credits","reputation","jobs_today","deliveries","contracts","settled_ids","history","last_settlement","story_state","review_state","in_flight","active_contract_id","load_notice"]:
  var value:Variant=get(key)
  previous[key]=value.duplicate(true) if value is Array or value is Dictionary else value
 var result:Dictionary=settle_contract(id,telemetry,elapsed,success,completion)
 if not result.ok:
  for key in previous:set(key,previous[key])
  return result
 if not bool(result.get("review_pending",false)):
  for key in previous:set(key,previous[key])
  return _error("结算记录不完整，本次尚未保存。请重试或重新载入存档。")
 if save_state(design,launcher,settings):return result
 for key in previous:set(key,previous[key])
 return _error(save_error)

func close_day() -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if not in_flight.is_empty():return _error("仍有货物在路上，暂时不能关店。")
 var active=active_contract()
 if not active.is_empty() and active.status=="accepted":return _error("柜台还有一份已接委托。先配送，或明确退回给客户。")
 phase="night"
 return {"ok":true,"message":"今天收工了，供应商送来了今晚的零件。"}

func next_day() -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if phase!="night":return _error("先收工，再开始下一天。")
 if not _new_batch_identity_error(day+1).is_empty():return _error("明日委托身份已使用，原进度已保留。")
 var previous:Dictionary={"day":day,"jobs_today":jobs_today,"phase":phase,"contracts":contracts.duplicate(true),"active_contract_id":active_contract_id,"last_trials":last_trials.duplicate(true),"story_state":story_state.duplicate(true),"offer_generation_state":offer_generation_state.duplicate(true),"review_state":review_state.duplicate(true) if review_state is Dictionary else review_state,"load_notice":load_notice}
 if not offer_generation_state.is_empty():
  var transition:Dictionary=AuthoringPolicy.next_day_root(offer_generation_state,day+1)
  if not transition.ok:return _error("今日航线使用了暂不支持的版本，原进度已保留。")
  offer_generation_state=transition.state
 day+=1;jobs_today=0;phase="morning";contracts=[];active_contract_id="";last_trials={};ensure_contracts()
 if contracts.size()!=DISPATCHES_PER_DAY or (not offer_generation_state.is_empty() and not _authored_batch_error().is_empty()):
  var message:String=load_notice if not load_notice.is_empty() else "今日航线暂时无法整理，原进度已保留。"
  for key in previous:set(key,previous[key])
  return _error(message)
 var unavailable:String=presentation_state_error()
 if not unavailable.is_empty():
  for key in previous:set(key,previous[key])
  return _error(unavailable)
 var publication:Dictionary=Reviews.publish_next_day(review_state,int(previous.day),day)
 if not publication.ok:
  for key in previous:set(key,previous[key])
  return _error("客户留言记录不完整，请重新载入有效存档。")
 # Publication follows successful offer authoring. The saved wrapper below
 # rolls both sides back if this candidate morning cannot be persisted.
 review_state=publication.state
 return {"ok":true,"published_reviews":publication.published_count}

func next_day_and_save(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 # Detached state and staged backup rotation include root, both offers, story,
 # review publication and the introduction stamp. Failure restores all aliases.
 return _shop_mutation_and_save(_author_next_day,design,launcher,settings,Callable())

func _author_next_day() -> Dictionary:
 _pirate_authoring_in_progress=true
 var result:Dictionary=next_day()
 _pirate_authoring_in_progress=false
 return result

func customer_reviews() -> Array:
 if review_load_blocked:return []
 return Reviews.visible_reviews(review_state,day)

# Read-only supply capability. Do not author a contract or initialize a shop.
func can_buy_basic_during_day() -> bool:
 return not review_load_blocked and (flight_mode==DeliveryProfile.VERSION or FreeProtocols.is_version(flight_mode)) and phase=="day" and in_flight.is_empty()

func day_basic_part_kinds() -> Array:
 return DAY_BASIC_PART_KINDS.duplicate()

func buy_part(type:String,spec:Dictionary) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if not WorkshopParts.is_core(type):return _error("这件旧零件不再出售。已有库存、装配和原控制仍会保留。")
 if flight_mode==DeliveryProfile.VERSION:
  var prices:Dictionary=BasicParts.catalog()
  if not prices.has(type) or not Reviews._integer(spec.get("price"),int(prices[type].price),int(prices[type].price)):return _error("零件价格已变化，请重新查看货架。")
  spec=prices[type]
 if phase!="night":
  if not can_buy_basic_during_day():
   return _error("供应商傍晚到店。今天先用手头的零件试一试。" if not FreeProtocols.is_version(flight_mode) else "现在暂时不能购买零件。请先回店处理待发委托，或收工后再来。")
  if not type in DAY_BASIC_PART_KINDS:return _error("白天只供应基础装配件，其他零件收工后再来看看。")
  var catalogue:Dictionary=BasicParts.catalog()
  if not catalogue.has(type):return _error("没有这件基础零件，原库存未改变。")
  var expected_price:int=int(catalogue[type].get("price",-1))
  if expected_price<=0 or not Reviews._integer(spec.get("price"),expected_price,expected_price):return _error("零件价格已变化，请重新查看货架。原资金与库存未改变。")
  # Charge the trusted registry value, never a free/discounted caller payload.
  spec=catalogue[type]
 var price:int=int(spec.get("price",0))
 if price<0 or credits<price:return _error("资金不足。先考虑最能解决问题的一件。")
 credits-=price;inventory[type]=int(inventory.get(type,0))+1
 return {"ok":true}

func workshop_upgrade_cost() -> int:
 # -1 means there is no further paid tier, never a zero-cost max-tier purchase.
 return WorkshopProfile.purchase_cost(WorkshopProfile.next_tier(workshop_tier))

func workshop_upgrade(target_tier:int) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 # The UI must submit the exact tier it displayed, not an unbound "upgrade".
 # A stale/double click for tier 1 can therefore never buy tier 2 accidentally.
 if phase!="night":return _error("车间扩建需要收工后进行。")
 if not in_flight.is_empty():return _error("仍有货物在路上，暂时不能扩建车间。")
 if not WorkshopProfile.is_valid_tier(target_tier):return _error("没有这个车间扩建等级。")
 if target_tier<=workshop_tier:
  return {"ok":false,"changed":false,"duplicate":true,"tier":workshop_tier,"message":"这一档车间已经开放，无需再次购买。"}
 if workshop_tier>=WorkshopProfile.MAX_TIER:return _error("车间已经完成全部扩建。")
 if target_tier!=workshop_tier+1:return _error("请先完成前一档车间扩建。")
 var cost:int=WorkshopProfile.purchase_cost(target_tier)
 if cost<0 or credits<cost:return _error("资金不足，先保留下一单需要的周转资金。")
 var previous_tier:int=workshop_tier;var previous_credits:int=credits
 credits-=cost;workshop_tier=target_tier
 var size:Vector2i=WorkshopProfile.grid_size(workshop_tier)
 # Caller saves once, and restores these two fields if that atomic save fails.
 # No inventory, blueprint, route, story or settlement field is touched here.
 return {"ok":true,"changed":true,"tier":workshop_tier,"cost":cost,"previous_tier":previous_tier,"previous_credits":previous_credits,"message":"车间已扩建为 %d × %d 格。现有零件与图纸保持原位。"%[size.x,size.y]}

func research_cost() -> int:return 140+research*100

func research_upgrade() -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if phase!="night":return _error("校准充电台需要收工后进行。")
 if research>=3:return _error("充电台已经完成全部校准。")
 var cost:int=research_cost()
 if credits<cost:return _error("资金不足，先保留下一单需要的周转资金。")
 credits-=cost;research+=1
 return {"ok":true,"message":"充电台已校准：可用储能提高 15%。实际消耗仍照常计费。"}

func starter_stock(_design:Array,_launcher:Array) -> void:
 if review_load_blocked:return
 if flight_mode==DeliveryProfile.VERSION and not inventory.is_empty():return
 # New-game stock only; old inventory is untouched until explicit retirement.
 # Four installed beams cover ship + two-beam pad; the old gate becomes a spare
 # equal-price beam. No retired logic item is granted to a new shop.
 inventory={"cargo":1,"beam":5,"battery":3,"thruster":2,"armor":1,"spring":1,"coupler":1}
 if flight_mode==DeliveryProfile.VERSION:
  var installed:Dictionary={}
  for part in _design+_launcher:installed[str(part.type)]=int(installed.get(str(part.type),0))+1
  for kind in installed:inventory[kind]=maxi(int(inventory.get(kind,0)),int(installed[kind]))
 ensure_contracts()

func missing_parts(design:Array,launcher:Array) -> Dictionary:
 var needed:Dictionary={};var missing:Dictionary={}
 for p in design+launcher:needed[str(p.type)]=int(needed.get(str(p.type),0))+1
 for type in needed:
  if int(needed[type])>int(inventory.get(type,0)):missing[type]=int(needed[type])-int(inventory.get(type,0))
 return missing

func _error(message:String) -> Dictionary:return {"ok":false,"message":message}

# Replay protocol identity is inspected before interpreting its payload. Unknown
# future records stay opaque; they are loaded only into recovery, never treated
# as corrupt legacy data in order to fall back to an older playable snapshot.
static func replay_protocol_error(snapshot:Dictionary) -> String:
 if snapshot.is_empty():return ""
 if not snapshot.get("route") is Dictionary:return "配送存档不完整，无法继续。原始记录已保留。"
 var route:Dictionary=snapshot.route
 if DeliveryChapter.is_version(snapshot.get("control_version")) or DeliveryChapter.has_markers(route) or DeliveryProfile.has_markers(route):return DeliveryChapter.snapshot_error(snapshot)
 if PirateOffer.has_markers(route) and not PirateOffer.validation_error(route).is_empty():return "自选委托配送记录不完整，原记录已保留。"
 for key in ["control_version","simulation_version"]:
  if snapshot.has(key) and not snapshot[key] is String:return "此配送存档暂时无法继续。原始记录已保留，请勿覆盖。"
 for key in ["control_version","mode"]:
  if route.has(key) and not route[key] is String:return "此配送存档暂时无法继续。原始记录已保留，请勿覆盖。"
 var control_version:String=snapshot.get("control_version",route.get("control_version",""))
 var route_version:String=route.get("control_version","")
 var simulation_version:String=snapshot.get("simulation_version","")
 if FreeProtocols.is_version(control_version) or FreeProtocols.has_markers(route) or snapshot.has("input_schema"):
  var free_error:String=FreeProtocols.snapshot_error(snapshot)
  if not free_error.is_empty():return free_error
 # Either side can declare pirate identity; a stripped nested route is never
 # legacy merely because its own markers disappeared.
 if PirateProtocols.is_version(control_version) or PirateProtocols.has_markers(route):
  if not PirateProtocols.route_error(route).is_empty() or control_version!=route_version:return "这份配送记录暂时无法继续，原记录已保留。"
  # Contract-free protocol helpers remain valid. Once either side carries a
  # contract, both must carry the same nonempty String. Paid settlement also
  # binds the wrapper to the active committed order before any ledger change.
  if snapshot.has("contract_id") or route.has("contract_id"):
   var contract_id:Variant=snapshot.get("contract_id")
   var route_contract_id:Variant=route.get("contract_id")
   if not contract_id is String or not route_contract_id is String:return "这份配送记录暂时无法继续，原记录已保留。"
   if contract_id.is_empty() or contract_id!=route_contract_id:return "这份配送记录暂时无法继续，原记录已保留。"
 if snapshot.has("terminal_intent") and (not (PirateProtocols.is_version(control_version) or FreeProtocols.is_version(control_version)) or not snapshot.terminal_intent is String or snapshot.terminal_intent!="abort"):
  return "这份配送记录暂时无法继续，原记录已保留。"
 if PirateProtocols.is_version(control_version):
  # Reuse the exact seed validator before comparing either untrusted value.
  # Pirate replay requires both explicit seeds; legacy absence stays separate.
  if not snapshot.has("seed") or not route.has("seed") or not replay_seed_error(snapshot).is_empty() or not replay_seed_error(route).is_empty():return "这份配送记录暂时无法继续，原记录已保留。"
  if route.seed!=snapshot.seed:return "这份配送记录暂时无法继续，原记录已保留。"
 var conflict:bool=(not route_version.is_empty() and snapshot.has("control_version") and route_version!=control_version) or (simulation_version=="autonomous-v5" and control_version in PILOT_VERSIONS) or (simulation_version in PILOT_VERSIONS and simulation_version!=control_version) or (route.get("mode","")=="pilot" and control_version.is_empty())
 if conflict or not control_version in ([""]+PILOT_VERSIONS) or not route_version in ([""]+PILOT_VERSIONS) or not simulation_version in (["","autonomous-v5"]+PILOT_VERSIONS):
  return "此配送存档暂时无法继续。原始记录已保留，请勿覆盖。"
 return ""

static func replay_seed_error(snapshot:Dictionary) -> String:
 # All supported legacy formats share the signed deterministic seed. Absence
 # retains the established day*100 default, but explicit null is not absence.
 # Keep the interoperable JSON-safe integer range +/- (2^53 - 1).
 # Convert integer bounds explicitly: decimal float literals lose a unit here.
 if not snapshot.has("seed"):return ""
 var seed_value:Variant=snapshot.seed
 if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or float(seed_value)!=floor(float(seed_value)) or float(seed_value)<float(-9007199254740991) or float(seed_value)>float(9007199254740991):
  return "配送存档损坏，无法继续。原始记录已保留。"
 return ""

func _valid_save(value:Variant,check_integrity:bool=true) -> bool:
 if not value is Dictionary:return false
 if not DeliveryChapter.saved_error(value).is_empty():return false
 if not _economic_recovery_error(value).is_empty() or not _free_offer_upgrade_error(value).is_empty() or not _free_ledger_error(value).is_empty() or not _accepted_free_swaps_error(value).is_empty() or not _force_offer_upgrade_error(value).is_empty() or not PartsMigration.receipt_error(value).is_empty():return false
 var raw_version:Variant=value.get("version")
 if not (raw_version is int or raw_version is float):return false
 if not is_finite(float(raw_version)) or float(raw_version)!=floor(float(raw_version)):return false
 if float(raw_version)<1.0 or float(raw_version)>float(SAVE_VERSION):return false
 if int(value.version)==SAVE_VERSION:
  # A corrupt v5 tier cannot silently shrink a paid grid or unlock free space.
  # Reject the primary and let the existing validated-backup path recover it.
  var tier:Variant=value.get("workshop_tier")
  if not (tier is int or tier is float):return false
  if not is_finite(float(tier)) or float(tier)!=floor(float(tier)):return false
  if not WorkshopProfile.is_valid_tier(int(tier)):return false
 if check_integrity and value.has("review_state"):
  if not Reviews._integer(value.get("day"),1,Reviews.MAX_DAY):return false
  if not value.review_state is Dictionary:return false
  var normalized:Dictionary=Reviews.normalize_state(value.review_state,int(value.get("day",0)))
  if not normalized.ok or not value.get("settled_ids",{}) is Dictionary or not value.get("contracts",[]) is Array:return false
  var review_contracts:Array=[]
  for saved_order in value.get("contracts",[]):
   review_contracts.append(_review_order(saved_order) if saved_order is Dictionary else saved_order)
  if not Reviews.ledger_validation_error(normalized.state,value.get("settled_ids",{}),review_contracts).is_empty():return false
 # Validate original identity bytes BEFORE normalize_state can substitute 0
 # or truncate a fractional seed. A valid backup must win over corrupt identity.
 # Entirely absent/empty pre-story state retains the deterministic legacy path.
 if value.get("story_state") is Dictionary and not value.story_state.is_empty():
  if not SeededGuard.integer_in(value.story_state.get("world_seed"),0,SeededOffers.MAX_SEED):return false
 if value.has("offer_generation_state") and not SeededGuard.seed_state_error(value.offer_generation_state).is_empty():return false
 if value.get("offer_generation_state") is Dictionary and AuthoringPolicy.known_root_version(value.offer_generation_state.get("version")):
  if not AuthoringPolicy.supported_root(value.offer_generation_state):return false
  if AuthoringPolicy.is_bird_root(value.offer_generation_state) and (not Reviews._integer(value.get("day"),1,1000000) or int(value.offer_generation_state.introduced_day)>int(value.day)):return false
 if AuthoringPolicy.future_root(value.get("offer_generation_state")):return false
 if not _pirate_saved_state_error(value).is_empty():return false
 var offer_settings:Variant=value.get("settings",{})
 if offer_settings is Dictionary and offer_settings.has("offer_generation_schema"):
  if not Reviews._integer(offer_settings.offer_generation_schema,1,1) or not value.has("offer_generation_state"):return false
 # An authored snapshot without its shop seed must never be silently enabled
 # with a replacement seed after an older writer dropped the root field.
 var saved_offers:Array=value.get("contracts",[]).duplicate() if value.get("contracts") is Array else []
 if value.get("in_flight") is Dictionary and value.in_flight.get("route") is Dictionary:saved_offers.append(value.in_flight.route)
 for saved in saved_offers:
  if not saved is Dictionary:continue
  if MeteorOffers.has_markers(saved) and not MeteorOffers.validation_error(saved).is_empty():return false
  if BirdOffer.has_markers(saved) and not BirdOffer.validation_error(saved).is_empty():return false
  if BirdOffer.has_markers(saved) and (not value.get("offer_generation_state") is Dictionary or not AuthoringPolicy.is_bird_root(value.offer_generation_state) or not Reviews._integer(value.offer_generation_state.get("introduced_day"),int(saved.accepted_day),int(saved.accepted_day))):return false
  if not saved.has("generation"):continue
  if not value.has("offer_generation_state"):return false
  var metadata:Variant=saved.generation
  if metadata is Dictionary and AuthoringPolicy.known_route(saved):
   if metadata.get("world_seed")!=value.offer_generation_state.world_seed:return false
 # A reviewed older writer can retain this setting while dropping/downgrading
 # the root. Detect that exact inconsistency in the existing save subsystem.
 if offer_settings is Dictionary and offer_settings.has("offer_authoring_policy"):
  if not offer_settings.offer_authoring_policy is String or not value.has("offer_generation_state") or offer_settings.offer_authoring_policy!=value.offer_generation_state.version:return false
 var review_settings:Variant=value.get("settings",{})
 if check_integrity and review_settings is Dictionary and review_settings.has("customer_reviews_schema"):
  if not value.has("review_state") or not Reviews._integer(review_settings.customer_reviews_schema,Reviews.schema_version(value.review_state),Reviews.schema_version(value.review_state)):return false
 for key in ["design","launcher"]:
  if not value.get(key,null) is Array:return false
 for key in ["inventory","designs","settings","settled_ids","in_flight","last_settlement","last_trials","story_state"]:
  if value.has(key) and not value[key] is Dictionary:return false
 for key in ["history","contracts"]:
  if value.has(key) and not value[key] is Array:return false
 if check_integrity:
  if not Reviews.opaque_error(AuthoringPolicy.review_inspection(value)).is_empty():return false
  if review_settings is Dictionary and review_settings.has("protected_bird_schema"):
   if not Reviews._integer(review_settings.protected_bird_schema,1,1) or not value.has("offer_generation_state") or not AuthoringPolicy.is_bird_root(value.offer_generation_state):return false
  for receipt in value.get("settled_ids",{}).values():
   if receipt is Dictionary and (receipt.has("wildlife_evidence") or receipt.get("control_version")==BirdProfile.CONTROL_VERSION):
    if not BirdSettlement.receipt_validation_error(receipt).is_empty():return false
    var identity:Dictionary=receipt.wildlife_evidence.dispatch_identity
    if not value.get("offer_generation_state") is Dictionary or not AuthoringPolicy.is_bird_root(value.offer_generation_state) or not Reviews._integer(value.offer_generation_state.get("introduced_day"),int(identity.delivery_day),int(identity.delivery_day)):return false
    if not BirdProfile.same_value(receipt.wildlife_evidence.seed,BirdOffer.derived_seed(int(value.offer_generation_state.world_seed),int(identity.delivery_day))):return false
 var snapshot:Dictionary=value.get("in_flight",{})
 if check_integrity and replay_protocol_error(snapshot).is_empty() and not replay_seed_error(snapshot).is_empty():return false
 return true

func _pirate_dispatch_coupling_error(snapshot:Dictionary) -> String:
 return _pirate_saved_state_error({"day":day,"research":research,"offer_generation_state":offer_generation_state,"contracts":contracts,"in_flight":snapshot,"active_contract_id":active_contract_id,"story_state":story_state})

static func _pirate_saved_state_error(value:Dictionary) -> String:
 var root:Variant=value.get("offer_generation_state")
 var settings:Variant=value.get("settings")
 var is_new_root:bool=root is Dictionary and Shape_equal(root.get("version"),PirateOffer.POLICY)
 # Key presence and the saved writer-policy setting retain the identity even
 # when its version is missing, null, numeric or downgraded. Never coerce it or
 # use corruption to select an older playable backup over this opaque primary.
 var root_marked:bool=root is Dictionary and root.has("pirate_introduced_day")
 var setting_marked:bool=settings is Dictionary and Shape_equal(settings.get("offer_authoring_policy"),PirateOffer.POLICY)
 if (root_marked or setting_marked) and not is_new_root:return "pirate_saved_root_remnant"
 if is_new_root:
  if not PirateOffer.root_error(root).is_empty() or not SeededGuard.integer_in(value.get("day"),1,1000000):return "pirate_saved_root"
  if int(root.pirate_introduced_day)>int(value.day) or int(root.introduced_day)>int(value.day):return "pirate_saved_future_introduction"
 var orders:Array=value.get("contracts",[]).duplicate() if value.get("contracts") is Array else []
 var ids:Dictionary={}
 var committed:Dictionary={}
 for order in orders:
  if order is Dictionary and order.get("contract_id") is String:
   if ids.has(order.contract_id) and (PirateOffer.has_markers(order) or ids[order.contract_id]):return "pirate_saved_duplicate_id"
   ids[order.contract_id]=PirateOffer.has_markers(order)
  if order is Dictionary and PirateOffer.has_markers(order) and Shape_equal(order.get("status"),"in_flight"):
   if not committed.is_empty():return "pirate_saved_multiple_paid_orders"
   committed=order
 var snapshot:Dictionary=value.get("in_flight",{}) if value.get("in_flight",{}) is Dictionary else {}
 var flight_route:Dictionary=snapshot.get("route",{}) if snapshot.get("route",{}) is Dictionary else {}
 if not flight_route.is_empty():orders.append(flight_route)
 for order in orders:
  if not order is Dictionary or not PirateOffer.has_markers(order):continue
  if not PirateOffer.validation_error(order).is_empty():return "pirate_saved_offer"
  if not is_new_root or not Shape_equal(root.pirate_introduced_day,order.accepted_day) or not Shape_equal(root.world_seed,order.generation.world_seed):return "pirate_saved_coupling"
  var story:Variant=value.get("story_state")
  if not story is Dictionary or not story.get("contract_bindings") is Dictionary:return "pirate_saved_story"
  var binding:Variant=story.contract_bindings.get(order.contract_id)
  if not binding is Dictionary:return "pirate_saved_binding"
  for key in ["appearance_id"]+PirateOffer.BINDING_KEYS:
   if not order.has(key) or not Shape_equal(order[key],binding.get(key)):return "pirate_saved_binding_identity"
 if not committed.is_empty() or PirateOffer.has_markers(flight_route):
  if committed.is_empty() or not PirateOffer.has_markers(flight_route):return "pirate_saved_paid_order_missing"
  if not Shape_equal([snapshot.get("contract_id"),value.get("active_contract_id"),snapshot.get("control_version"),snapshot.get("seed"),value.get("day")],[committed.contract_id,committed.contract_id,PirateProfileV2.VERSION,committed.seed,committed.accepted_day]):return "pirate_saved_paid_wrapper_identity"
  if not flight_route.get("status") is String or not flight_route.status in ["accepted","in_flight"]:return "pirate_saved_paid_route_status"
  # Paid-day research cannot change: upgrades require night, and closing
  # while in flight is forbidden. Anchor the captured value to that existing
  # saved field; no extra schema, new physics or epsilon comparison is needed.
  if not SeededGuard.integer_in(value.get("research"),0,3) or not Shape_equal(flight_route.get("battery_capacity_multiplier"),1.0+0.15*int(value.research)):return "pirate_saved_paid_research_capacity"
  # Preparation may snapshot accepted status and research capacity. Every
  # other field, including complete provenance/customer/physical payloads,
  # must still equal the committed order; no rounded JSON or epsilon repair.
  var expected:Dictionary=committed.duplicate(true);var actual:Dictionary=flight_route.duplicate(true)
  for key in ["status","battery_capacity_multiplier"]:expected.erase(key);actual.erase(key)
  if not Shape_equal(expected,actual):return "pirate_saved_paid_route_identity"
 return ""

static func Shape_equal(a:Variant,b:Variant) -> bool:return ReadableGuard.same(a,b)

func _read_save(path:String) -> Variant:
 var parser=JSON.new()
 if parser.parse(FileAccess.get_file_as_string(path))!=OK:return null
 return parser.data

# This explicit continuation transaction is never called by load/title preview.
# It preserves both old durable slots before granting only the exact old debt.
func recover_legacy_debt_and_save(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if flight_mode==DeliveryProfile.VERSION or not delivery_chapter_state.is_empty():return {"ok":true,"changed":false,"message":""}
 if not economic_recovery.is_empty():return {"ok":true,"changed":false,"duplicate":true,"message":""}
 if credits>=0:return {"ok":true,"changed":false,"message":""}
 # A committed old flight retains its exact accounting and replay. Recover only
 # after its ordinary result is safely committed; never relabel it mid-flight.
 if not in_flight.is_empty():return {"ok":true,"changed":false,"deferred":true,"message":""}
 var backup:Dictionary=_backup_before_economic_recovery()
 if not backup.ok:return backup
 return _shop_mutation_and_save(_recover_legacy_debt.bind(str(backup.source_sha256)),design,launcher,settings,Callable())

func _recover_legacy_debt(source_sha256:String) -> Dictionary:
 if flight_mode==DeliveryProfile.VERSION or not delivery_chapter_state.is_empty():return {"ok":true,"changed":false,"message":""}
 if not economic_recovery.is_empty() or credits>=0:return {"ok":true,"changed":false,"message":""}
 var prior:int=credits
 economic_recovery={"schema":ECONOMIC_RECOVERY_SCHEMA,"id":ECONOMIC_RECOVERY_SCHEMA,"prior_credits":prior,"grant":-prior,"resulting_credits":0,"source_sha256":source_sha256}
 credits=0
 return {"ok":true,"changed":true,"recovery_grant":-prior,"message":"旧版损失已补贴 ¥%d，余额恢复为 ¥0。原账单和发射前装置都已保留。"%(-prior)}

func _backup_before_economic_recovery() -> Dictionary:
 return _backup_legacy_transition()

func _backup_legacy_transition() -> Dictionary:
 var source:String=_loaded_save_path if not _loaded_save_path.is_empty() else "user://savegame.json"
 if not FileAccess.file_exists(source):return _error("无法读取补贴前存档，余额与原记录未改变。")
 var raw:Variant=_read_save(source)
 if not _valid_save(raw) or not Reviews._integer(raw.get("credits"),credits,credits):return _error("升级前存档已变化，余额与原记录未改变。请重新载入。")
 var source_sha256:String=FileAccess.get_sha256(source)
 if source_sha256.length()!=64:return _error("无法校验补贴前存档，余额与原记录未改变。")
 var folder:String="user://economy-recovery-v1/"+source_sha256
 if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder)!=OK:return _error("无法建立补贴前备份，余额与原记录未改变。")
 # Deterministic archive identity makes a retry safe after a failed final save.
 # Existing archive files are only compared, never overwritten or removed.
 for slot in ["savegame.json","savegame.backup.json"]:
  var path:String="user://"+slot
  if DirAccess.dir_exists_absolute(path):return _error("存档路径不可读取，补贴尚未应用。")
  if not FileAccess.file_exists(path):continue
  var file=FileAccess.open(path,FileAccess.READ)
  if file==null:return _error("无法读取补贴前备份，余额与原记录未改变。")
  var length:int=file.get_length();var bytes:PackedByteArray=file.get_buffer(length);var read_error:Error=file.get_error();file.close()
  if bytes.size()!=length or read_error!=OK:return _error("补贴前存档读取不完整，余额与原记录未改变。")
  var target:String=folder.path_join(slot)
  if FileAccess.file_exists(target):
   if FileAccess.get_file_as_bytes(target)!=bytes:return _error("补贴前备份与原存档不一致，余额未改变。")
   continue
  if DirAccess.dir_exists_absolute(target):return _error("补贴前备份无法保存，余额未改变。")
  var temporary:String=target+".tmp"
  var out=FileAccess.open(temporary,FileAccess.WRITE)
  if out==null:return _error("补贴前备份无法保存，余额未改变。")
  var stored:bool=out.store_buffer(bytes);out.flush();var write_error:Error=out.get_error();out.close()
  if not stored or write_error!=OK or FileAccess.get_file_as_bytes(temporary)!=bytes:return _error("补贴前备份校验失败，余额未改变。")
  if DirAccess.rename_absolute(temporary,target)!=OK or FileAccess.get_file_as_bytes(target)!=bytes:return _error("补贴前备份未能提交，余额未改变。")
 return {"ok":true,"source_sha256":source_sha256}

# All preview paths are read-only, including the title/load path. A confirmation
# is bound to the whole durable snapshot and its matching live projection.
func _durable_transition_source(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 if review_load_blocked or _shop_save_in_progress:return {"ok":false,"reason":"transition_unavailable"}
 var source:String=_loaded_save_path if not _loaded_save_path.is_empty() else "user://savegame.json"
 if not FileAccess.file_exists(source):return {"ok":false,"reason":"save_missing"}
 var raw:Variant=_read_save(source)
 if not _valid_save(raw):return {"ok":false,"reason":"save_invalid"}
 var reviews:Dictionary=Reviews.normalize_state(review_state,day)
 if not reviews.ok:return {"ok":false,"reason":"reviews_invalid"}
 var live:Dictionary=_snapshot_for_save(design,launcher,settings,reviews.state)
 # Preserve unknown, otherwise valid source fields. Every field this Economy
 # owns must agree; an unsaved edit can never be silently committed by upgrade.
 for key in live:
  if not raw.has(key) or _accepted_order_digest({"value":live[key]})!=_accepted_order_digest({"value":raw[key]}):return {"ok":false,"reason":"live_state_not_saved"}
 return {"ok":true,"snapshot":raw.duplicate(true),"path":source,"sha256":FileAccess.get_sha256(source),"slots":_transition_slot_digests()}

func _transition_slot_digests() -> Dictionary:
 var result:Dictionary={}
 for path in ["user://savegame.json","user://savegame.backup.json"]:
  result[path]="directory" if DirAccess.dir_exists_absolute(path) else FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
 return result

func _transition_source_unchanged() -> bool:
 return not _transition_source.is_empty() and FileAccess.file_exists(str(_transition_source.path)) and FileAccess.get_sha256(str(_transition_source.path))==str(_transition_source.sha256) and _transition_slot_digests()==_transition_source.slots

func _archive_transition(snapshot:Dictionary,archive_root:String) -> Dictionary:
 if not _transition_source_unchanged():return {"ok":false,"reason":"source_changed"}
 return PartsMigration.archive_raw_slots(snapshot,str(_transition_source.path),"user://savegame.json","user://savegame.backup.json",archive_root)

func _persist_transition_snapshot(candidate:Dictionary) -> Dictionary:
 # No live field/alias is replaced before the authoritative primary rename.
 # Recheck BOTH durable slots after raw archival and immediately before commit.
 if not _transition_source_unchanged() or not _valid_save(candidate):return {"ok":false,"reason":"source_or_candidate_changed"}
 if not presentation_state_error(candidate).is_empty():return {"ok":false,"reason":"presentation_unavailable"}
 var file=FileAccess.open("user://savegame.tmp",FileAccess.WRITE)
 if file==null:return {"ok":false,"reason":"temporary_open_failed"}
 var stored:bool=file.store_string(JSON.stringify(candidate,"",true,true));file.flush();var error:Error=file.get_error();file.close()
 if not stored or error!=OK or not _valid_save(_read_save("user://savegame.tmp")):return {"ok":false,"reason":"temporary_validation_failed"}
 if not _transition_source_unchanged():return {"ok":false,"reason":"source_changed_before_commit"}
 if not _commit_shop_save():return {"ok":false,"reason":"atomic_commit_failed"}
 return {"ok":true}

func parts_retirement_preview(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 var source:Dictionary=_durable_transition_source(design,launcher,settings)
 if not source.ok:return {"available":false,"reason":source.get("reason","")}
 var plan:Dictionary=PartsMigration.preview(source.snapshot)
 if not plan.ok:return {"available":false,"reason":plan.get("reason","")}
 if not bool(plan.get("changed",false)):return {"available":false,"deferred":plan.get("deferred",false),"reason":plan.get("reason","")}
 var converted_count:int=0
 for count in plan.converted_owned.values():converted_count+=int(count)
 return {"available":true,"confirmation_token":plan.confirmation_token,"converted_count":converted_count,"credit_delta":plan.credit_delta,"control_count":plan.controls.size(),"message":plan.message}

func retire_legacy_parts_and_save(confirmation_token:String,design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 var source:Dictionary=_durable_transition_source(design,launcher,settings)
 if not source.ok:return _error("进度尚未保存或已经变化，请重新查看整理预览。")
 _shop_save_in_progress=true;_transition_source=source;_shop_backup_warning="";save_error=""
 var result:Dictionary=PartsMigration.transaction(source.snapshot,confirmation_token,_archive_transition.bind("user://parts-retirement-v2"),_persist_transition_snapshot)
 _shop_save_in_progress=false;_transition_source={}
 if not bool(result.get("ok",false)):
  var failure:Dictionary=_error("整理未能保存，资金和原装配未改变。请重新查看后再试。")
  failure.reason=result.get("reason","");return failure
 if not bool(result.get("changed",false)):return result
 var candidate:Dictionary=result.candidate
 credits=int(candidate.credits);inventory=candidate.inventory.duplicate(true);designs=candidate.designs.duplicate(true);parts_retirement=candidate[PartsMigration.FIELD].duplicate(true)
 result.design=candidate.design.duplicate(true);result.launcher=candidate.launcher.duplicate(true);result.settings=candidate.settings.duplicate(true)
 result.erase("candidate")
 if not _shop_backup_warning.is_empty():result.message=str(result.message)+" "+_shop_backup_warning
 return result

func _force_offer_candidate(order:Dictionary) -> bool:
 return order.get("status")=="available" and order.get("contract_id") is String and not settled_ids.has(order.contract_id) and SeededGuard.integer_in(order.get("id"),0,2) and order.get("control_version")==FreeProfile.VERSION and FreeProfile.validation_error(order).is_empty() and route_validation_error(order).is_empty()

func _force_offer_plan(snapshot:Dictionary) -> Dictionary:
 if not force_offer_upgrade.is_empty() or not in_flight.is_empty() or phase=="night":return {"available":false}
 var candidate:Dictionary=snapshot.duplicate(true);var changes:Array=[];var ids:Array=[]
 for index in candidate.contracts.size():
  var old:Dictionary=candidate.contracts[index]
  if not _force_offer_candidate(old):continue
  var id:int=int(old.id);var base:Dictionary=_autonomous_routes()[id]
  base=GroundProfile.route(base) if id==0 else ExtremeProfile.route(base)
  var fresh:Dictionary=ForceProfile.route(base)
  if fresh.is_empty():return {"available":false,"reason":"fresh_route_invalid"}
  fresh.economy_policy=FREE_ECONOMY_POLICY
  # A fresh catalog route; original geometry lives only in the raw archive.
  # Keep the quoted commercial terms and customer, without inheriting any old
  # physics/input/generation marker into the new protocol.
  for key in ["contract_id","accepted_day","variant","client","cargo","appearance_id","appearance_seed","species","accessory_id","story_id","story_node","reward","required","deadline","rep","weight"]:
   if old.has(key):fresh[key]=old[key]
  fresh.status="available";fresh.risk="按住推进 · 松开滑行 · 主动刹车"
  fresh.story="这份委托改用新版操控：按住方向推进，松开继续滑行；靠近收件点时主动刹车。"
  if not route_preflight_error(fresh).is_empty():return {"available":false,"reason":"fresh_route_unavailable"}
  candidate.contracts[index]=fresh;ids.append(str(old.contract_id))
  changes.append({"contract_id":str(old.contract_id),"original_order_sha256":_accepted_order_digest(old),"replacement_order_sha256":_accepted_order_digest(fresh)})
 if changes.is_empty():return {"available":false}
 candidate.flight_mode=ForceProfile.VERSION
 return {"available":true,"candidate":candidate,"orders":changes,"contract_ids":ids,"count":ids.size(),"confirmation_token":_accepted_order_digest({"source":snapshot,"orders":changes}),"message":"免费更换未接的新版操控委托；已接和在途委托保持原样。"}

func force_offer_upgrade_preview(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 var source:Dictionary=_durable_transition_source(design,launcher,settings)
 if not source.ok:return {"available":false,"reason":source.get("reason","")}
 var plan:Dictionary=_force_offer_plan(source.snapshot)
 plan.erase("candidate");plan.erase("orders")
 return plan

func upgrade_available_force_offers_and_save(confirmation_token:String,design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 var source:Dictionary=_durable_transition_source(design,launcher,settings)
 if not source.ok:return _error("进度尚未保存或已经变化，请重新查看升级预览。")
 var plan:Dictionary=_force_offer_plan(source.snapshot)
 if not bool(plan.get("available",false)) or confirmation_token.is_empty() or confirmation_token!=str(plan.get("confirmation_token","")):return _error("委托状态已变化，原委托已保留。")
 _shop_save_in_progress=true;_transition_source=source;_shop_backup_warning="";save_error=""
 var backup:Dictionary=_archive_transition(source.snapshot,"user://force-offer-upgrade-v2")
 if not backup.ok:
  _shop_save_in_progress=false;_transition_source={};return _error("无法备份原委托，这次升级未保存。")
 var candidate:Dictionary=plan.candidate
 candidate.force_offer_upgrade={"schema":FORCE_OFFER_UPGRADE_SCHEMA,"day":day,"source_sha256":str(backup.source_sha256),"confirmation_token":confirmation_token,"orders":plan.orders.duplicate(true)}
 candidate.settings.force_offer_upgrade_schema=FORCE_OFFER_UPGRADE_SCHEMA
 var saved:Dictionary=_persist_transition_snapshot(candidate)
 _shop_save_in_progress=false;_transition_source={}
 if not saved.ok:return _error("升级未能保存，原委托、资金和装配未改变。")
 contracts=candidate.contracts.duplicate(true);flight_mode=ForceProfile.VERSION;force_offer_upgrade=candidate.force_offer_upgrade.duplicate(true)
 var message:String="未接委托已换成新版操控。原委托和旧账单已保留备份。"
 if not _shop_backup_warning.is_empty():message+=" "+_shop_backup_warning
 return {"ok":true,"changed":true,"contract_ids":plan.contract_ids,"message":message}

static func _force_offer_upgrade_error(value:Dictionary) -> String:
 var settings:Variant=value.get("settings",{})
 if not settings is Dictionary:return "invalid_force_upgrade_settings"
 var marked:bool=settings.has("force_offer_upgrade_schema")
 if marked and settings.force_offer_upgrade_schema!=FORCE_OFFER_UPGRADE_SCHEMA:return "unknown_force_offer_upgrade_marker"
 if not value.has("force_offer_upgrade"):return "missing_force_offer_upgrade_receipt" if marked else ""
 if not marked:return "missing_force_offer_upgrade_marker"
 var receipt:Variant=value.force_offer_upgrade
 if not receipt is Dictionary or not BirdProfile.exact_keys(receipt,["schema","day","source_sha256","confirmation_token","orders"]):return "invalid_force_offer_upgrade_receipt"
 if not Reviews._integer(value.get("day"),1,Reviews.MAX_DAY):return "invalid_force_offer_upgrade_day"
 if receipt.schema!=FORCE_OFFER_UPGRADE_SCHEMA or not Reviews._integer(receipt.day,1,int(value.day)):return "unknown_force_offer_upgrade_schema"
 if not receipt.orders is Array or receipt.orders.is_empty() or receipt.orders.size()>DISPATCHES_PER_DAY:return "invalid_force_offer_upgrade_orders"
 for key in ["source_sha256","confirmation_token"]:
  if not _transition_hash_valid(receipt[key]):return "invalid_force_offer_upgrade_hash"
 var seen:Dictionary={}
 for row in receipt.orders:
  if not row is Dictionary or not BirdProfile.exact_keys(row,["contract_id","original_order_sha256","replacement_order_sha256"]):return "invalid_force_offer_upgrade_order"
  if not row.contract_id is String or not row.contract_id in ["D%d-A"%int(receipt.day),"D%d-B"%int(receipt.day)] or seen.has(row.contract_id):return "invalid_force_offer_upgrade_identity"
  seen[row.contract_id]=true
  for key in ["original_order_sha256","replacement_order_sha256"]:
   if not _transition_hash_valid(row[key]):return "invalid_force_offer_upgrade_hash"
 return ""

static func _transition_hash_valid(value:Variant) -> bool:
 if not value is String or value.length()!=64:return false
 for character in value:
  if not character in "0123456789abcdef":return false
 return true

# UI calls this read-only preview before offering an explicit upgrade button.
# Merely loading, declining or closing that confirmation changes nothing.
func free_offer_upgrade_preview() -> Dictionary:
 var ids:Array=[]
 if review_load_blocked or not in_flight.is_empty() or phase=="night" or not free_offer_upgrade.is_empty():return {"available":false,"contract_ids":ids,"count":0}
 for order in contracts:
  if order is Dictionary and _upgradeable_old_ordinary(order):ids.append(order.contract_id)
 return {"available":not ids.is_empty(),"contract_ids":ids,"count":ids.size(),"message":"把未接下的旧委托换成自由飞行轻件？已接委托和旧账单会保留。"}

func _upgradeable_old_ordinary(order:Dictionary) -> bool:
 if order.get("status")!="available" or not order.get("contract_id") is String or settled_ids.has(order.contract_id):return false
 if not SeededGuard.integer_in(order.get("id"),0,2) or not route_validation_error(order).is_empty():return false
 if str(order.get("control_version","")) not in ["",PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION]:return false
 if MoonProfile.has_moon_markers(order) or PirateOffer.has_markers(order) or BirdOffer.has_markers(order):return false
 if order.has("generation") and not AuthoringPolicy.known_route(order):return false
 return true

func upgrade_available_free_offers_and_save(design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 if not in_flight.is_empty():return _error("先完成正在配送的旧委托，再更换未接委托。")
 var preview:Dictionary=free_offer_upgrade_preview()
 if not preview.available:return {"ok":true,"changed":false,"message":""}
 var backup:Dictionary=_backup_legacy_transition()
 if not backup.ok:return backup
 return _shop_mutation_and_save(_upgrade_available_free_offers.bind(str(backup.source_sha256)),design,launcher,settings,Callable())

func _upgrade_available_free_offers(source_sha256:String) -> Dictionary:
 if not in_flight.is_empty() or not free_offer_upgrade.is_empty():return _error("委托状态已变化，请重新查看。")
 var replaced:Array=[]
 for slot in contracts.size():
  var old:Dictionary=contracts[slot]
  if not _upgradeable_old_ordinary(old):continue
  var fresh:Dictionary=_new_free_offer(GroundProfile.route(_autonomous_routes()[0]))
  fresh.contract_id=old.contract_id;fresh.accepted_day=int(old.get("accepted_day",day));fresh.status="available";fresh.variant="轻件续单";fresh.recovery_offer=true
  # Retain only the same unaccepted customer's presentation identity. Old
  # geometry/provenance is archived, never relabelled as a new physics replay.
  for key in ["client","cargo","appearance_id","appearance_seed","species","accessory_id","story_id","story_node"]:
   if old.has(key):fresh[key]=old[key]
  fresh.story="把这箱轻件送到屋顶收件台就好。方向由你决定，记得留意电量。"
  var error:String=route_preflight_error(fresh)
  if not error.is_empty():return _error(error)
  contracts[slot]=fresh;replaced.append(str(old.contract_id))
 if replaced.is_empty():return {"ok":true,"changed":false,"message":""}
 free_offer_upgrade={"schema":FREE_OFFER_UPGRADE_SCHEMA,"id":FREE_OFFER_UPGRADE_SCHEMA,"day":day,"contract_ids":replaced,"source_sha256":source_sha256}
 if flight_mode!=ForceProfile.VERSION:flight_mode=FreeProfile.CONTROL_VERSION
 return {"ok":true,"changed":true,"contract_ids":replaced,"message":"未接的旧委托已换成自由飞行轻件。旧存档已备份。"}

static func _free_offer_upgrade_error(value:Dictionary) -> String:
 var settings:Variant=value.get("settings",{})
 var marked:bool=settings is Dictionary and settings.has("free_offer_upgrade_schema")
 if marked and settings.free_offer_upgrade_schema!=FREE_OFFER_UPGRADE_SCHEMA:return "unknown_free_offer_upgrade"
 if not value.has("free_offer_upgrade"):return "missing_free_offer_upgrade" if marked else ""
 var record:Variant=value.free_offer_upgrade
 if not record is Dictionary:return "invalid_free_offer_upgrade"
 if record.is_empty():return "missing_free_offer_upgrade" if marked else ""
 if not BirdProfile.exact_keys(record,["schema","id","day","contract_ids","source_sha256"]):return "invalid_free_offer_upgrade_keys"
 if record.get("schema")!=FREE_OFFER_UPGRADE_SCHEMA or record.get("id")!=FREE_OFFER_UPGRADE_SCHEMA:return "unknown_free_offer_upgrade"
 if not Reviews._integer(record.get("day"),1,int(value.get("day",0))):return "invalid_free_offer_upgrade_day"
 if not record.get("contract_ids") is Array or record.contract_ids.is_empty() or record.contract_ids.size()>DISPATCHES_PER_DAY:return "invalid_free_offer_upgrade_contracts"
 var seen:Dictionary={}
 for id in record.contract_ids:
  if not id is String or not id in ["D%d-A"%int(record.day),"D%d-B"%int(record.day)] or seen.has(id):return "invalid_free_offer_upgrade_identity"
  seen[id]=true
 if not record.get("source_sha256") is String or record.source_sha256.length()!=64:return "invalid_free_offer_upgrade_source"
 for character in record.source_sha256:
  if not character in "0123456789abcdef":return "invalid_free_offer_upgrade_source"
 return ""

# Separate explicit admission for the already-accepted but never-dispatched old
# ordinary order. The existing available-offer API keeps its original boundary.
func accepted_free_swap_preview() -> Dictionary:
 var unavailable:Dictionary={"available":false,"contract_id":"","order_sha256":"","cargo_loaded":false}
 if review_load_blocked or phase=="night" or not in_flight.is_empty() or active_contract_id.is_empty():return unavailable
 var candidate:Dictionary={}
 for order in contracts:
  if not order is Dictionary or order.get("contract_id")!=active_contract_id:continue
  if not candidate.is_empty():return unavailable # Ambiguous IDs fail closed.
  candidate=order
 if not _accepted_legacy_swap_candidate(candidate):return unavailable
 var loaded:bool=bool(candidate.get("cargo_loaded",false))
 return {"available":true,"contract_id":candidate.contract_id,"order_sha256":_accepted_order_digest(candidate),"cargo_loaded":loaded,"from_route":str(candidate.name),"to_route":"城市货站 → 屋顶收件台","reward":FREE_GROUND_REWARD,"message":"免费换成屋顶收件台的自由飞行轻件？还是同一位客户、同一箱货，不扣声望。"}

func _accepted_legacy_swap_candidate(order:Dictionary) -> bool:
 if order.is_empty() or order.get("status")!="accepted" or not order.get("contract_id") is String or order.contract_id!=active_contract_id or settled_ids.has(order.contract_id):return false
 if not SeededGuard.integer_in(order.get("id"),0,2) or not route_validation_error(order).is_empty():return false
 if str(order.get("control_version","")) not in ["",PilotProfile.CONTROL_VERSION,AscentProfile.CONTROL_VERSION,ExtremeProfile.CONTROL_VERSION]:return false
 if MoonProfile.has_moon_markers(order) or PirateOffer.has_markers(order) or BirdOffer.has_markers(order):return false
 if order.has("generation") and not AuthoringPolicy.known_route(order):return false
 if order.has("cargo_loaded") and not order.cargo_loaded is bool:return false
 if accepted_free_swaps.get("swaps",{}).has(order.contract_id):return false
 return true

func swap_accepted_legacy_for_free_and_save(expected_contract_id:String,expected_order_sha256:String,design:Array,launcher:Array,settings:Dictionary) -> Dictionary:
 if review_load_blocked:return _error(load_notice)
 var preview:Dictionary=accepted_free_swap_preview()
 if not preview.available or expected_contract_id!=preview.contract_id or expected_order_sha256!=preview.order_sha256:return _error("这份待发委托已变化，请重新查看换单选项。")
 if not _accepted_order_is_durable(expected_contract_id,expected_order_sha256):return _error("待发委托尚未保存或存档已变化，请重新载入后确认换单。")
 var backup:Dictionary=_backup_legacy_transition()
 if not backup.ok:return backup
 return _shop_mutation_and_save(_swap_accepted_legacy_for_free.bind(expected_contract_id,expected_order_sha256,str(backup.source_sha256)),design,launcher,settings,Callable())

static func _accepted_order_digest(order:Dictionary) -> String:
 # Godot JSON normalizes integer/float storage types on reload. Normalize once
 # before hashing so the confirmation binds exact numeric values, not a runtime
 # type distinction absent from the durable JSON representation.
 var canonical:Variant=JSON.parse_string(JSON.stringify(order,"",true,true))
 return JSON.stringify(canonical,"",true,true).sha256_text()

func _accepted_order_is_durable(id:String,digest:String) -> bool:
 var source:String=_loaded_save_path if not _loaded_save_path.is_empty() else "user://savegame.json"
 var raw:Variant=_read_save(source)
 if not _valid_save(raw) or not raw.get("contracts") is Array or raw.get("active_contract_id")!=id:return false
 var found:Dictionary={}
 for order in raw.contracts:
  if not order is Dictionary or order.get("contract_id")!=id:continue
  if not found.is_empty():return false
  found=order
 return not found.is_empty() and found.get("status")=="accepted" and _accepted_order_digest(found)==digest

func _swap_accepted_legacy_for_free(expected_contract_id:String,expected_order_sha256:String,source_sha256:String) -> Dictionary:
 # Recheck inside the same detached transaction that owns the final save.
 var preview:Dictionary=accepted_free_swap_preview()
 if not preview.available or expected_contract_id!=preview.contract_id or expected_order_sha256!=preview.order_sha256:return _error("这份待发委托已变化，原记录已保留。")
 var slot:int=-1
 for index in contracts.size():
  if contracts[index].get("contract_id")==expected_contract_id:slot=index;break
 if slot<0:return _error("待发委托未找到，原记录已保留。")
 var old:Dictionary=contracts[slot]
 var fresh:Dictionary=_new_free_offer(GroundProfile.route(_autonomous_routes()[0]))
 fresh.contract_id=old.contract_id;fresh.accepted_day=int(old.get("accepted_day",day));fresh.status="accepted";fresh.variant="轻件续单";fresh.recovery_offer=true
 fresh.cargo_loaded=preview.cargo_loaded
 for key in ["client","cargo","appearance_id","appearance_seed","species","accessory_id","story_id","story_node"]:
  if old.has(key):fresh[key]=old[key]
 fresh.story="还是这位客户托付的那箱货。这次送到屋顶收件台，方向由你决定。"
 var error:String=route_preflight_error(fresh)
 if not error.is_empty():return _error(error)
 contracts[slot]=fresh
 # A prediction from the old physics/price is not proof for the new contract.
 # No financial/review/story receipt is manufactured or consumed here.
 last_trials.erase(expected_contract_id)
 if accepted_free_swaps.is_empty():accepted_free_swaps={"schema":ACCEPTED_FREE_SWAP_SCHEMA,"swaps":{}}
 accepted_free_swaps.swaps[expected_contract_id]={"day":day,"original_order_sha256":expected_order_sha256,"source_sha256":source_sha256,"cargo_loaded":preview.cargo_loaded}
 if flight_mode!=ForceProfile.VERSION:flight_mode=FreeProfile.CONTROL_VERSION
 return {"ok":true,"changed":true,"contract_id":expected_contract_id,"cargo_loaded":preview.cargo_loaded,"message":"已免费换成自由飞行轻件。客户和货物不变，旧委托已备份。"}

static func _accepted_free_swaps_error(value:Dictionary) -> String:
 var settings:Variant=value.get("settings",{})
 var marked:bool=settings is Dictionary and settings.has("accepted_free_swap_schema")
 if marked and settings.accepted_free_swap_schema!=ACCEPTED_FREE_SWAP_SCHEMA:return "unknown_accepted_free_swap"
 if not value.has("accepted_free_swaps"):return "missing_accepted_free_swaps" if marked else ""
 var root:Variant=value.accepted_free_swaps
 if not root is Dictionary:return "invalid_accepted_free_swaps"
 if root.is_empty():return "missing_accepted_free_swaps" if marked else ""
 if not BirdProfile.exact_keys(root,["schema","swaps"]) or root.get("schema")!=ACCEPTED_FREE_SWAP_SCHEMA or not root.get("swaps") is Dictionary:return "unknown_accepted_free_swaps"
 # At the transition there are at most two old ordinary orders. A swap opts all
 # later authoring into free mode, so the retained transition ledger is bounded.
 if root.swaps.is_empty() or root.swaps.size()>DISPATCHES_PER_DAY:return "invalid_accepted_free_swap_count"
 for id in root.swaps:
  var record:Variant=root.swaps[id]
  if not id is String or not record is Dictionary or not BirdProfile.exact_keys(record,["day","original_order_sha256","source_sha256","cargo_loaded"]):return "invalid_accepted_free_swap_record"
  if not Reviews._integer(record.get("day"),1,int(value.get("day",0))) or not record.get("cargo_loaded") is bool:return "invalid_accepted_free_swap_state"
  if not id in ["D%d-A"%int(record.day),"D%d-B"%int(record.day)]:return "invalid_accepted_free_swap_identity"
  for key in ["original_order_sha256","source_sha256"]:
   if not record.get(key) is String or record[key].length()!=64:return "invalid_accepted_free_swap_source"
   for character in record[key]:
    if not character in "0123456789abcdef":return "invalid_accepted_free_swap_source"
 return ""

static func _free_ledger_error(value:Dictionary) -> String:
 var ledger:Variant=value.get("settled_ids",{})
 if not ledger is Dictionary:return "" # Existing structural validator owns it.
 for receipt in ledger.values():
  if not receipt is Dictionary or not receipt.has("economy_policy"):continue
  if receipt.economy_policy==DeliveryChapter.ECONOMY_POLICY:continue # Independently validated by DeliveryChapter.saved_error.
  if receipt.economy_policy!=FREE_ECONOMY_POLICY or not FreeProtocols.is_version(receipt.get("control_version")) or receipt.get("delivery_policy")!=FreeProfile.MARKERS.delivery_policy:return "unknown_free_receipt_policy"
  if not receipt.get("success") is bool:return "invalid_free_receipt_outcome"
  for key in ["income","base_income","energy","ammo","repairs","lost","actual_costs","charged_costs","insurance_coverage","charge_cap"]:
   if not Reviews._integer(receipt.get(key),0,40000000):return "invalid_free_receipt_amount"
  if not Reviews._integer(receipt.get("profit"),-FREE_FAILURE_CHARGE_CAP,40000000):return "invalid_free_receipt_profit"
  if int(receipt.actual_costs)!=int(receipt.energy)+int(receipt.ammo)+int(receipt.repairs)+int(receipt.lost):return "incoherent_free_actual_costs"
  if int(receipt.insurance_coverage)!=int(receipt.actual_costs)-int(receipt.charged_costs) or int(receipt.profit)!=int(receipt.income)-int(receipt.charged_costs):return "incoherent_free_coverage"
  var cap:int=FREE_SUCCESS_CHARGE_CAP if receipt.success else FREE_FAILURE_CHARGE_CAP
  if int(receipt.charge_cap)>cap or int(receipt.charged_costs)!=mini(int(receipt.actual_costs),int(receipt.charge_cap)):return "incoherent_free_charge_cap"
  if not receipt.success and int(receipt.income)!=0:return "failed_free_income"
 return ""

static func _economic_recovery_error(value:Dictionary) -> String:
 var settings:Variant=value.get("settings",{})
 var marked:bool=settings is Dictionary and settings.has("economic_recovery_schema")
 if marked and settings.economic_recovery_schema!=ECONOMIC_RECOVERY_SCHEMA:return "unknown_economic_recovery"
 if not value.has("economic_recovery"):return "missing_economic_recovery" if marked else ""
 var record:Variant=value.economic_recovery
 if not record is Dictionary:return "invalid_economic_recovery"
 if record.is_empty():return "missing_economic_recovery" if marked else ""
 if not BirdProfile.exact_keys(record,["schema","id","prior_credits","grant","resulting_credits","source_sha256"]):return "invalid_economic_recovery_keys"
 if record.get("schema")!=ECONOMIC_RECOVERY_SCHEMA or record.get("id")!=ECONOMIC_RECOVERY_SCHEMA:return "unknown_economic_recovery"
 if not Reviews._integer(record.get("prior_credits"),-9007199254740991,-1) or not Reviews._integer(record.get("grant"),1,9007199254740991) or not Reviews._integer(record.get("resulting_credits"),0,0):return "invalid_economic_recovery_amount"
 if int(record.grant)!=-int(record.prior_credits):return "incoherent_economic_recovery"
 if not record.get("source_sha256") is String or record.source_sha256.length()!=64:return "invalid_economic_recovery_source"
 for character in record.source_sha256:
  if not character in "0123456789abcdef":return "invalid_economic_recovery_source"
 return ""

# Only the explicit title New Game instance installs this one-shot callback.
# Existing save_state overrides and every gameplay transaction keep their API.
var new_game_commit_guard:Callable=Callable()

func save_state(design:Array,launcher:Array,settings:Dictionary) -> bool:
 save_error=""
 if review_load_blocked:save_error=load_notice;return false
 var unavailable:String=presentation_state_error()
 if not unavailable.is_empty():save_error=unavailable;return false
 var reviews:Dictionary=Reviews.normalize_state(review_state,day)
 if not reviews.ok:save_error="客户留言记录校验失败，原存档未改变。";return false
 review_state=reviews.state
 if not offer_generation_state.is_empty() and not SeededGuard.seed_state_error(offer_generation_state).is_empty():save_error="航线种子记录不完整，原存档未改变。";return false
 var data:Dictionary=_snapshot_for_save(design,launcher,settings,review_state)
 var file=FileAccess.open("user://savegame.tmp",FileAccess.WRITE)
 if file==null:save_error="无法创建临时存档，原存档未改变。";return false
 # Keep double-precision route/parameter values exact across deterministic
 # replay. Default JSON formatting rounds curved ascent gate coordinates.
 if not file.store_string(JSON.stringify(data,"",true,true)):file.close();save_error="写入存档失败，原存档未改变。";return false
 file.flush();var write_error:Error=file.get_error();file.close()
 if write_error!=OK:save_error="存档未能写入磁盘，原存档与备份未改变。";return false
 if not _valid_save(_read_save("user://savegame.tmp")):save_error="临时存档校验失败。";return false
 if _shop_save_in_progress:return _commit_shop_save()
 if new_game_commit_guard.is_valid():
  var commit:Callable=new_game_commit_guard;new_game_commit_guard=Callable()
  if not in_flight.is_empty():save_error="配送途中无法开始新游戏。原存档未改变。";return false
  var outcome:Dictionary=commit.call()
  save_error=str(outcome.get("message","新游戏保存失败，原存档未改变。"))
  if bool(outcome.get("ok",false)):_loaded_save_path="user://savegame.json"
  return bool(outcome.get("ok",false))
 # Autosave/manual save/exit use the same staged primary commit as shop
 # actions. A failed primary replacement must not rotate either durable slot.
 _shop_backup_warning=""
 return _commit_shop_save()

# Pure projection shared by ordinary saves and explicit transition previews.
func _snapshot_for_save(design:Array,launcher:Array,settings:Dictionary,normalized_reviews:Dictionary) -> Dictionary:
 # Older v5 main preserves unknown settings even when its economy drops new
 # top-level fields. This marker detects that known downgrade loss on return.
 var saved_settings:Dictionary=settings.duplicate(true);saved_settings.customer_reviews_schema=Reviews.schema_version(normalized_reviews)
 if not delivery_chapter_state.is_empty():saved_settings.delivery_chapter_schema=DeliveryChapter.STATE_SCHEMA
 if not delivery_upgrade.is_empty():saved_settings.delivery_upgrade_schema=DeliveryChapter.UPGRADE_SCHEMA
 if not economic_recovery.is_empty():saved_settings.economic_recovery_schema=ECONOMIC_RECOVERY_SCHEMA
 if not free_offer_upgrade.is_empty():saved_settings.free_offer_upgrade_schema=FREE_OFFER_UPGRADE_SCHEMA
 if not accepted_free_swaps.is_empty():saved_settings.accepted_free_swap_schema=ACCEPTED_FREE_SWAP_SCHEMA
 if not force_offer_upgrade.is_empty():saved_settings.force_offer_upgrade_schema=FORCE_OFFER_UPGRADE_SCHEMA
 # Preserve the receipt's actual policy version; never relabel historical v2.
 if not parts_retirement.is_empty():saved_settings[PartsMigration.MARKER]=parts_retirement.get("schema","")
 if AuthoringPolicy.is_bird_root(offer_generation_state):saved_settings.protected_bird_schema=1
 if not offer_generation_state.is_empty():
  saved_settings.offer_generation_schema=1
  if offer_generation_state.version in [AuthoringPolicy.VERSION,AuthoringPolicy.CURRENT_VERSION,AuthoringPolicy.PIRATE_VERSION,AuthoringPolicy.Legacy.VERSION,AuthoringPolicy.Ordinary.CURRENT_VERSION]:saved_settings.offer_authoring_policy=offer_generation_state.version
 var data={"version":SAVE_VERSION,"flight_mode":flight_mode,"credits":credits,"reputation":reputation,"day":day,"phase":phase,"jobs_today":jobs_today,"deliveries":deliveries,"research":research,"workshop_tier":workshop_tier,"history":history,"designs":designs,"inventory":inventory,"contracts":contracts,"active_contract_id":active_contract_id,"settled_ids":settled_ids,"in_flight":in_flight,"last_settlement":last_settlement,"last_trials":last_trials,"story_state":story_state,"review_state":normalized_reviews,"design":design,"launcher":launcher,"settings":saved_settings}
 if not offer_generation_state.is_empty():data.offer_generation_state=offer_generation_state.duplicate(true)
 if not economic_recovery.is_empty():data.economic_recovery=economic_recovery.duplicate(true)
 if not free_offer_upgrade.is_empty():data.free_offer_upgrade=free_offer_upgrade.duplicate(true)
 if not accepted_free_swaps.is_empty():data.accepted_free_swaps=accepted_free_swaps.duplicate(true)
 if not force_offer_upgrade.is_empty():data.force_offer_upgrade=force_offer_upgrade.duplicate(true)
 if not parts_retirement.is_empty():data[PartsMigration.FIELD]=parts_retirement.duplicate(true)
 if not delivery_chapter_state.is_empty():data.delivery_chapter_state=delivery_chapter_state.duplicate(true)
 if not delivery_upgrade.is_empty():data.delivery_upgrade=delivery_upgrade.duplicate(true)
 return data.duplicate(true)

func _commit_shop_save() -> bool:
 # Stage the previous primary without touching either durable slot. A failure
 # before the authoritative primary rename therefore preserves BOTH files.
 # This is not a two-file atomic transaction: a crash after primary rename can
 # leave the previous backup (or no first backup), but the new primary wins.
 var staged_backup:bool=false
 var stage:String="user://savegame.shop-backup.tmp"
 if FileAccess.file_exists("user://savegame.json") and _valid_save(_read_save("user://savegame.json")):
  var old_bytes:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
  var backup_file=FileAccess.open(stage,FileAccess.WRITE)
  if backup_file==null:
   save_error="无法暂存备份，这次操作未保存。原存档与备份未改变。";return false
  if not backup_file.store_buffer(old_bytes):
   backup_file.close();save_error="写入暂存备份失败，这次操作未保存。原存档与备份未改变。";return false
  backup_file.flush();var backup_error:Error=backup_file.get_error();backup_file.close()
  if backup_error!=OK or FileAccess.get_file_as_bytes(stage)!=old_bytes:
   save_error="暂存备份校验失败，这次操作未保存。原存档与备份未改变。";return false
  staged_backup=true
 if DirAccess.rename_absolute("user://savegame.tmp","user://savegame.json")!=OK:
  if staged_backup:DirAccess.remove_absolute(stage)
  save_error="替换存档失败，这次操作未保存。原存档与备份未改变。";return false
 _loaded_save_path="user://savegame.json"
 # Primary is now committed. A backup promotion failure cannot roll it back
 # in memory or report the purchase as failed, which would allow a retry charge.
 if staged_backup and DirAccess.rename_absolute(stage,"user://savegame.backup.json")!=OK:
  _shop_backup_warning="本次操作已保存，但备份未能更新。请检查存档目录。"
 return true

func load_state(defer_contract_authoring:bool=false) -> Dictionary:
 load_notice="";review_load_blocked=false;_loaded_save_path="";var parsed:Dictionary={};var blocked_integrity_save:Dictionary={};var existing_save:bool=false
 for path in ["user://savegame.json","user://savegame.backup.json"]:
  if not FileAccess.file_exists(path):continue
  existing_save=true
  var parser=JSON.new()
  if parser.parse(FileAccess.get_file_as_string(path))!=OK:continue
  var value=parser.data
  if value is Dictionary and not DeliveryChapter.saved_error(value).is_empty():
   parsed=value;review_load_blocked=true;load_notice="首章进度或真实赔付记录无法校验，原存档已保留。";break
  if value is Dictionary and (not PartsMigration.receipt_error(value).is_empty() or not _force_offer_upgrade_error(value).is_empty()):
   parsed=value;review_load_blocked=true;load_notice="升级记录暂时无法校验，原存档已保留。";break
  if value is Dictionary and (not _economic_recovery_error(value).is_empty() or not _free_offer_upgrade_error(value).is_empty() or not _free_ledger_error(value).is_empty() or not _accepted_free_swaps_error(value).is_empty()):
   parsed=value;review_load_blocked=true;load_notice="补贴记录暂时无法校验，原存档已保留。";break
  if value is Dictionary and AuthoringPolicy.future_root(value.get("offer_generation_state")):
   parsed=value;review_load_blocked=true;load_notice="此存档含暂不支持的委托编排规则。原始记录已保留，请勿覆盖。";break
  if value is Dictionary and not _pirate_saved_state_error(value).is_empty():
   parsed=value;review_load_blocked=true;load_notice="此存档的自选委托记录暂时无法读取。原始记录已保留，请勿覆盖。";break
  if value is Dictionary and not Reviews.opaque_error(AuthoringPolicy.review_inspection(value)).is_empty():
   parsed=value;review_load_blocked=true;load_notice="此存档含暂不支持的客户留言或保护鸟记录。原始记录已保留，请勿覆盖。";break
  # Protocol rejection outranks fallback: even damaged adjacent review fields
  # cannot authorize interpreting/downgrading an opaque future dispatch.
  if value is Dictionary and value.get("in_flight") is Dictionary:
   var identity_error:String=replay_protocol_error(value.in_flight)
   if not identity_error.is_empty():
    parsed=value;review_load_blocked=true;load_notice=identity_error;break
  if value is Dictionary:
   var unavailable:String=presentation_state_error(value)
   if not unavailable.is_empty():
    parsed=value;review_load_blocked=true;load_notice=unavailable;break
  if value is Dictionary and not _valid_save(value) and blocked_integrity_save.is_empty() and _valid_save(value,false):
   # Structural-only inspection retains the actual rejected record for a
   # read-only recovery screen; it is never a migration or a save candidate.
   blocked_integrity_save=value
  if _valid_save(value):
   parsed=value;_loaded_save_path=path
   if path.ends_with("backup.json"):load_notice="主存档损坏，已恢复上一份有效备份。"
   break
 if parsed.is_empty():
  if blocked_integrity_save.is_empty():
   if existing_save:review_load_blocked=true;load_notice="存档记录损坏，原文件已保留。请恢复有效备份后继续。"
   return {}
  # Keep the real ledger readable, but never replace the damaged source with a
  # fabricated new shop or reset its customer history. Existing valid backups
  # win above. No usable backup means explicit recovery is required.
  parsed=blocked_integrity_save;review_load_blocked=true
  load_notice="存档记录损坏，配送记录与原存档已保留。请恢复有效备份后继续。"

 # Recovery records remain opaque, including their ledger and in-flight copy.
 # Main shows its recovery-only screen before authoring contracts or actors.
 if review_load_blocked:
  if parsed.get("in_flight",{}) is Dictionary:in_flight=parsed.get("in_flight",{}).duplicate(true)
  if parsed.get("settled_ids",{}) is Dictionary:settled_ids=parsed.get("settled_ids",{}).duplicate(true)
  if Reviews._integer(parsed.get("credits"),-9007199254740991,9007199254740991):credits=int(parsed.credits)
  return parsed

 # Versions 1..4 predate paid expansion. Preserve their designs verbatim and
 # start at the original tier. Loading alone never rewrites the player's file.
 workshop_tier=int(parsed.workshop_tier) if int(parsed.version)==SAVE_VERSION else 0
 delivery_chapter_state=parsed.get("delivery_chapter_state",{}).duplicate(true)
 delivery_upgrade=parsed.get("delivery_upgrade",{}).duplicate(true)
 economic_recovery=parsed.get("economic_recovery",{}).duplicate(true)
 free_offer_upgrade=parsed.get("free_offer_upgrade",{}).duplicate(true)
 force_offer_upgrade=parsed.get("force_offer_upgrade",{}).duplicate(true)
 parts_retirement=parsed.get(PartsMigration.FIELD,{}).duplicate(true)
 accepted_free_swaps=parsed.get("accepted_free_swaps",{}).duplicate(true)
 offer_generation_state=parsed.get("offer_generation_state",{}).duplicate(true)
 story_mode=false
 if parsed.get("story_state",{}).is_empty():
  # v1-v3 (and story-disabled fixtures) get a reproducible migration seed.
  # Reloading the same old file cannot reroll appearances, award old receipts,
  # or rewrite its dispatch. Binding waits for explicit enable_story_mode().
  story_state=Stories.initial_state(Stories.stable_seed("legacy-shop/"+JSON.stringify(parsed,"",true,true)))
 else:story_state=Stories.normalize_state(parsed.story_state)
 flight_mode=str(parsed.get("flight_mode","autonomous-v5"))
 credits=int(parsed.get("credits",260));reputation=maxi(0,int(parsed.get("reputation",0)));day=maxi(1,int(parsed.get("day",1)));jobs_today=clampi(int(parsed.get("jobs_today",0)),0,DISPATCHES_PER_DAY);deliveries=maxi(0,int(parsed.get("deliveries",0)));research=clampi(int(parsed.get("research",0)),0,3)
 # Missing legacy field starts empty today, never from old financial receipts.
 review_state=Reviews.normalize_state(parsed.get("review_state"),day).state
 history=parsed.get("history",[]);designs=parsed.get("designs",{});inventory=parsed.get("inventory",{})
 if int(parsed.version)==1:
  phase="morning";contracts=[];jobs_today=0;load_notice="已保留原有方案与库存，可以开始新一天的营业。"
 else:
  phase=str(parsed.get("phase","morning"));contracts=parsed.get("contracts",[]);active_contract_id=str(parsed.get("active_contract_id",""));settled_ids=parsed.get("settled_ids",{});in_flight=parsed.get("in_flight",{});last_settlement=parsed.get("last_settlement",{});last_trials=parsed.get("last_trials",{})
  if not phase in ["morning","day","night"]:phase="morning"
 # Actual Continue may need an immutable old-state backup and debt recovery
 # before any new order is authored. Legacy/model callers keep their default.
 if not defer_contract_authoring:ensure_contracts()
 return parsed
