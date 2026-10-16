extends SceneTree
## A real formal economy commit and main next-day action drive the real view.
## Synthetic UI intents only; no physical delivery/controller claim.
var passed:int=0
var failed:int=0
var game
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=2) -> void:
 for unused in n:await process_frame
func run() -> void:
 for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await settle(4)
 game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 var id:String=str(game.economy.available_contracts()[0].contract_id);var old_day:int=game.economy.day
 check(game.economy.accept_contract(id).ok,"formal fixture accepts actual customer contract")
 game.economy.mark_story_seen(id,id+"/accept");game.economy.mark_cargo_loaded(id)
 check(game.economy.begin_dispatch(game.design,game.launcher).ok,"formal fixture enters real dispatched state")
 var result:Dictionary=game.economy.settle_contract_and_save(id,{"integrity":1.0,"energy_used":12.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},8.0,true,game.design,game.launcher,game.settings)
 check(result.ok and game.economy.review_state.pending.size()==1,"formal persisted settlement captures one fact-only pending record")
 var pending:Dictionary=game.economy.review_state.pending[id]
 check(not pending.has("rating") and not pending.has("body"),"same-day saved pending facts contain no future evaluation")
 game.economy.mark_story_seen(id,id+"/result");game.economy.mark_story_seen(id,id+"/return")
 game.render();await settle();check(not game._review_phone_is_open(),"settlement/render never opens a review popup")
 check(game._open_review_phone(),"same-day player may explicitly inspect phone")
 check(game.review_phone._list.get_child_count()==1 and game.review_phone._list.get_child(0) is Label and game.economy.customer_reviews().is_empty(),"same-day phone renders no future review or rating")
 game._close_review_phone();game.economy.close_day();game.save_game()
 var balance:int=game.economy.credits;var reputation:int=game.economy.reputation;var history:Array=game.economy.history.duplicate(true)
 DirAccess.make_dir_absolute("user://savegame.tmp")
 game._action("next_day",null);await settle()
 check(game.economy.day==old_day and game.economy.review_state.pending.size()==1 and game.economy.customer_reviews().is_empty(),"failed next-day save cannot leak a published evaluation")
 check(not game._review_phone_is_open(),"failed next-day transition never opens phone")
 DirAccess.remove_absolute("user://savegame.tmp");game._action("next_day",null);await settle(4)
 if game._dialogue_is_open():game.dialogue.skip_conversation();await settle(2)
 game._pending_story.clear();game._active_story.clear()
 check(game.economy.day==old_day+1 and game.economy.customer_reviews().size()==1 and game.economy.review_state.pending.is_empty(),"saved next morning publishes exactly previous-day formal review")
 check(not game._review_phone_is_open(),"successful next-day transition never opens phone")
 check(game._open_review_phone(),"player explicitly opens published review next morning")
 var records:Array=game.economy.customer_reviews()
 check(game.review_phone._list.get_child_count()==2 and game.review_phone._list.get_child(0).get_meta("phone_date_group")==old_day and game.review_phone._list.get_child(1) is PanelContainer,"phone shows one published customer record")
 var lines:VBoxContainer=game.review_phone._list.get_child(1).get_child(0)
 check(lines.get_child(1).text==records[0].body and lines.get_child(0).text.contains("5 / 5") and game.review_phone._list.get_child(0).text=="昨天 · 第 %d 天配送"%old_day,"phone uses exact published body, rating and actual delivery day")
 check(game.economy.credits==balance and game.economy.reputation==reputation and game.economy.history==history,"publication/view cannot replay settlement money or reputation")
 game._close_review_phone();game.save_game();game.queue_free();await settle(5)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await settle(4);game.world.set_process(false)
 if game._dialogue_is_open():game.dialogue.skip_conversation();await settle(2)
 check(not game._review_phone_is_open() and game.economy.customer_reviews()==records,"save restoration keeps feed identical and phone closed")
 game._pending_story.clear();check(game._open_review_phone(),"restored feed remains explicitly accessible")
 check(game.economy.credits==balance and game.economy.reputation==reputation and game.economy.customer_reviews().size()==1,"repeat open after reload cannot create reward or duplicate review")
 game.queue_free();await settle(4)
 print("CUSTOMER_REVIEW_PHONE_PUBLICATION passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
