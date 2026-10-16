extends SceneTree
## Real Main/Economy/HUD/World, isolated save, explicit clocks and API intents.
## Preserves old empty-counter and immediate-accept counterexamples as asserts.
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
var game
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func frames(count:int=3) -> void:
 for unused in count:await process_frame
func step(seconds:float,stories:bool=true) -> void:
 for unused in ceili(seconds*120):
  if game.world._parcel_tween!=null:
   game.world._parcel_tween.pause();game.world._parcel_tween.custom_step(1.0/120.0)
  game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0)
  if stories:game._try_pending_story()
  game._sync_shop_action_availability()
func stop_owned_audio() -> Array:
 var refs:Array=[]
 for player in game.find_children("*","AudioStreamPlayer",true,false):
  AudioClock.watch_player(player,refs);player.stop();player.stream=null
 return refs
func dispose() -> void:
 if not is_instance_valid(game):game=null;return
 var refs:Array=stop_owned_audio()
 game.queue_free();game=null;await frames()
 var released:Dictionary=await AudioClock.wait_released(self,refs)
 print("DEV04_SHOP_AUDIO_RELEASE ",JSON.stringify(released,"",true,true))
 check(released.ok,"owned test audio players/playbacks release before next boot or quit")
func fresh(erase:bool=true) -> void:
 await dispose()
 if erase:
  for filename in ["savegame.json","savegame.backup.json","savegame.tmp"]:
   if FileAccess.file_exists("user://"+filename):DirAccess.remove_absolute("user://"+filename)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames()
func button_for_contract(cid:String) -> Button:
 for button in game.hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("shop_contract_id",""))==cid:return button
 return null
func exact_saved_differences(before:Variant,after:Variant,path:String="ledger") -> Array:
 var differences:Array=[]
 if before is Dictionary and after is Dictionary:
  for key in before:
   if not after.has(key):differences.append({"path":path+"/"+str(key),"kind":"missing_key"})
   else:differences.append_array(exact_saved_differences(before[key],after[key],path+"/"+str(key)))
  for key in after:
   if not before.has(key):differences.append({"path":path+"/"+str(key),"kind":"added_key"})
  return differences
 if before is Array and after is Array:
  if before.size()!=after.size():return [{"path":path,"kind":"array_size_changed","before":before.size(),"after":after.size()}]
  for index in before.size():differences.append_array(exact_saved_differences(before[index],after[index],path+"/"+str(index)))
  return differences
 if typeof(before)==typeof(after) and before==after:return differences
 # JSON has one numeric domain. Only allow a demonstrably lossless int/float
 # representation change. Existing floats must remain bit-value equal; there
 # is no tolerance, rounding, key omission, serialization canonicalizer or
 # acceptance of unsafe (>53-bit) integer coercion in this comparison.
 var numeric_pair:bool=(before is int and after is float) or (before is float and after is int)
 var lossless:bool=false
 if numeric_pair:
  var integer:int=before if before is int else after
  var floating:float=after if after is float else before
  lossless=integer>=-9007199254740991 and integer<=9007199254740991 and is_finite(floating) and floating==float(integer) and int(floating)==integer
 differences.append({"path":path,"kind":"lossless_int_float" if lossless else "value_or_type_changed","before_type":type_string(typeof(before)),"after_type":type_string(typeof(after)),"before":before,"after":after})
 return differences
func only_lossless_numeric_differences(differences:Array) -> bool:
 for difference in differences:
  if str(difference.kind)!="lossless_int_float":return false
 return true
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("ISOLATED XDG_DATA_HOME REQUIRED");quit(2);return
 root.size=Vector2i(1280,720)
 await fresh()
 var first:String=str(game.economy.contracts[0].contract_id)
 var second:String=str(game.economy.contracts[1].contract_id)
 var credits:int=game.economy.credits
 game._action("focus_counter",null);game._action("accept_contract",first)
 check(game.page=="hub" and game.economy.active_contract_id.is_empty() and not game.dialogue.is_open(),"first-frame counter/accept cannot address an NPC still offscreen")
 game.world.update_shop_state({"phase":"day","contracts":[],"active_contract_id":""})
 for unused in 4:game._action("focus_counter",null);game._action("accept_contract",first)
 check(game.page=="hub" and game.economy.active_contract_id.is_empty() and game.economy.credits==credits,"empty queue rejects repeated direct actions without mutation")
 game.render();step(2.0)
 check(game.world.has_counter_customer(first),"new customer physically reaches counter")
 game._action("focus_counter",null)
 check(game.page=="contracts" and button_for_contract(first)!=null and not button_for_contract(first).disabled,"arrived owner opens real counter UI")
 check(button_for_contract(second)!=null and button_for_contract(second).disabled,"queued contract remains visible but cannot be accepted as absent customer")
 game._action("accept_contract",second)
 check(game.economy.active_contract_id.is_empty(),"direct hidden-customer accept cannot bypass HUD ownership")
 game._action("accept_contract",first)
 check(game.economy.active_contract_id==first and game.dialogue.is_open(),"real owner acceptance opens its required story")
 check(game.save_game(),"unread accepted handoff saves")
 await fresh(false)
 check(game.economy.active_contract_id==first and not game.dialogue.is_open() and not game._pending_story.is_empty(),"restart preserves accepted handoff but waits for actual actor")
 step(2.0)
 check(game.dialogue.is_open() and game.world.has_counter_customer(first),"accepted restart resumes required dialogue on actual arrival")
 game.dialogue.skip_conversation();step(24.0);await frames()
 check(game.economy.is_cargo_loaded(first) and game.world.is_parcel_loaded(first),"accepted story completion naturally persists loading")
 game.economy.workshop_tier=2;game.render();game.world.restore_loaded(first)
 check(game.save_game(),"expanded loaded state saves for restart")
 await fresh(false)
 check(game.economy.is_cargo_loaded(first) and game.world.is_parcel_loaded(first) and not game.dialogue.is_open(),"loaded restart neither loses cargo nor replays acceptance")
 check(not game.is_shop_action_available("focus_counter"),"departed accepted NPC does not leave an enabled ghost counter")
 game.start_flight(false)
 check(game.page=="flight" and not game.economy.in_flight.is_empty(),"loaded accepted work can still dispatch despite no counter visitor")
 var parcel_id:int=game.world.parcel.get_instance_id()
 var root_before:Vector2=game.world.clerk.position
 step(.25,false)
 check(game.world.clerk.position.x<root_before.x and game.world.parcel.get_instance_id()==parcel_id,"clerk starts natural return during live delivery with one parcel")
 game.abort_flight()
 check(game.page=="report" and game.economy.in_flight.is_empty() and game.economy.settled_ids.has(first),"short flight settles durably before receipt")
 check(game.dialogue.is_open() and str(game._active_story.get("beat",""))=="result" and game.world._clerk_return_requested,"committed remote receipt opens immediately while residual walk continues")
 check(str(game._active_story.get("counter_contract_id",""))=="","remote receipt claims no nonexistent customer")
 var paid_credits:int=game.economy.credits;var settled:Dictionary=game.economy.settled_ids.duplicate(true)
 check(game.save_game(),"unread paid receipt saves")
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
 var before_to_disk:Array=exact_saved_differences(settled,saved.settled_ids)
 print("DEV04_LEDGER_BEFORE_TO_DISK ",JSON.stringify({"credits_before":paid_credits,"credits_disk":saved.credits,"differences":before_to_disk},"",true,true))
 check(float(saved.credits)==float(paid_credits) and only_lossless_numeric_differences(before_to_disk),"saving receipt changes no ledger value beyond lossless JSON numeric representation")
 await fresh(false)
 check(game.dialogue.is_open() and str(game._active_story.get("beat",""))=="result","paid receipt restores without waiting for a storefront actor")
 var after_restart:Array=exact_saved_differences(settled,game.economy.settled_ids)
 var disk_to_restart:Array=exact_saved_differences(saved.settled_ids,game.economy.settled_ids)
 print("DEV04_LEDGER_RESTART_DIAGNOSTIC ",JSON.stringify({"credits_before":paid_credits,"credits_after":game.economy.credits,"raw_dictionary_equal":game.economy.settled_ids==settled,"before_to_restart":after_restart,"disk_to_restart":disk_to_restart},"",true,true))
 check(game.economy.credits==paid_credits,"receipt restart preserves exact integer balance")
 check(only_lossless_numeric_differences(after_restart),"receipt restart preserves every ledger key and exact numeric value")
 check(disk_to_restart.is_empty(),"parsed on-disk receipt is structurally identical after restart")
 game.dialogue.skip_conversation();game.page="hub"
 game.world.update_shop_state({"phase":"day","contracts":[],"active_contract_id":""})
 game._restore_story_dialogue()
 check(not game.dialogue.is_open() and game._pending_story.is_empty() and not game.economy.pending_story_returns().is_empty(),"historical return waits for matching later real visit rather than ghost dialogue")
 await dispose()
 print("DEV04_SHOP_FLOW_MAIN_DIAGNOSTIC01 passed=%d failed=%d native_input=false"%[passed,failed]);quit(1 if failed else 0)
