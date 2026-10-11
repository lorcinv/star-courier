extends SceneTree
const Econ=preload("res://scripts/economy.gd")
const Reviews=preload("res://scripts/customer_reviews.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Offers=preload("res://scripts/seeded_offer_catalog.gd")
const Main=preload("res://scripts/main.gd")
const BeforeSeed=preload("res://tests/fixtures/economy_pre_seed_reviews_v5.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func exact(a:Variant,b:Variant) -> bool:
 # JSON parses whole-valued integers as floats. Compare exact serialized values
 # after the same round trip, without epsilon or rounding physical coordinates.
 return JSON.stringify(JSON.parse_string(JSON.stringify(a,"",true,true)),"",true,true)==JSON.stringify(JSON.parse_string(JSON.stringify(b,"",true,true)),"",true,true)
func clean() -> void:
 for name in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  var path:String="user://"+name
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
func save_raw(raw:Dictionary,path:String="user://savegame.json") -> void:
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(raw,"",true,true));file.close()
func read_raw(path:String="user://savegame.json") -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func new_shop(seed_value:int=9142):
 var e=Econ.new();e.enable_extreme_mode();e.story_state=Stories.initial_state(seed_value);e.enable_story_mode();e.starter_stock(Extreme.starter_design(),Extreme.starter_launcher())
 check(e.enable_seeded_offers(seed_value).ok,"explicit shop seed initialized")
 return e
func settle_one(e,slot:int=0) -> void:
 var id:String=e.contracts[slot].contract_id
 check(e.accept_contract(id).ok,"accept actual authored order "+id)
 check(e.mark_cargo_loaded(id).ok,"load actual order "+id)
 check(e.begin_dispatch(Extreme.starter_design(),Extreme.starter_launcher()).ok,"formal commitment "+id)
 check(e.settle_contract_and_save(id,{"integrity":1.0,"energy_used":120.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},20.0,true,Extreme.starter_design(),Extreme.starter_launcher(),{}).ok,"formal facts and ledger save together "+id)
func snapshot(e) -> Dictionary:
 var value:Dictionary={}
 for key in ["day","phase","jobs_today","credits","reputation","inventory","contracts","active_contract_id","settled_ids","last_trials","story_state","review_state","offer_generation_state","load_notice"]:
  var item:Variant=e.get(key);value[key]=item.duplicate(true) if item is Array or item is Dictionary else item
 return value
func run() -> void:
 clean();var e=new_shop();var original:Array=e.contracts.duplicate(true)
 check(not original[0].has("generation") and not original[1].has("generation"),"first-day teaching offers remain unchanged when seed is enabled")
 e.enable_seeded_offers(9999);e.ensure_contracts()
 check(exact(e.contracts,original) and int(e.offer_generation_state.world_seed)==9142,"enable/read cannot replace today or its saved seed")
 settle_one(e);check(e.customer_reviews().is_empty() and e.review_state.pending.size()==1,"same-day paid facts stay hidden before seeded next morning")
 e.close_day();e.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{})
 var night:Dictionary=snapshot(e);var file_before:String=FileAccess.get_file_as_string("user://savegame.json")
 DirAccess.make_dir_absolute("user://savegame.tmp")
 var failed_day:Dictionary=e.next_day_and_save(Extreme.starter_design(),Extreme.starter_launcher(),{})
 check(not failed_day.ok and exact(snapshot(e),night),"failed shared save restores date, offers, story, seed and pending/publication state")
 check(FileAccess.get_file_as_string("user://savegame.json")==file_before,"failed morning leaves actual prior-night disk bytes unchanged")
 DirAccess.remove_absolute("user://savegame.tmp")
 check(e.next_day_and_save(Extreme.starter_design(),Extreme.starter_launcher(),{}).ok,"successful next morning saves generated offers and prior-day review together")
 check(e.day==2 and e.customer_reviews().size()==1 and e.review_state.pending.is_empty(),"exactly one prior-day review publishes at day two")
 check(e.contracts.size()==2 and e.contracts[0].has("generation") and e.contracts[1].has("generation"),"new morning realizes both finite seeded offers")
 var morning:Dictionary=snapshot(e);check(not e.next_day_and_save([],[],{}).ok and exact(snapshot(e),morning),"repeated next-day request cannot regenerate offers or duplicate review")
 var loaded=Econ.new();loaded.load_state();loaded.enable_extreme_mode();loaded.enable_story_mode();loaded.enable_seeded_offers(123)
 save_raw({"before":{ "contracts":e.contracts,"review":e.review_state,"seed":e.offer_generation_state},"after":{"contracts":loaded.contracts,"review":loaded.review_state,"seed":loaded.offer_generation_state}},"user://restart-comparison.json")
 check(exact(loaded.contracts,e.contracts) and exact(loaded.review_state,e.review_state) and exact(loaded.offer_generation_state,e.offer_generation_state),"restart retains exact contracts, feed and world seed")
 check(loaded.customer_reviews()[0].delivery_day==1 and loaded.customer_reviews()[0].published_day==2,"publication date remains next day after restart")
 var id:String=loaded.contracts[0].contract_id;loaded.accept_contract(id)
 var order:Dictionary=loaded.active_contract().duplicate(true);var state_before:Dictionary=loaded.story_state.duplicate(true)
 var original_story:Dictionary=Stories.conversation_for(loaded.story_state,order,"accept")
 var conversation:Dictionary=loaded.story_conversation(id,"accept")
 check(conversation.lines.size()==original_story.lines.size()+1,"saved address variation adds one line without replacing recurring story beats")
 check(conversation.lines[0]==order.generation.dialogue.accept_lines[0],"dialogue consumes saved exact opening rather than rerolling")
 check(conversation.actor.appearance_id==order.generation.dialogue.appearance_id,"random opening retains the actual bound NPC identity")
 var tail:Array=conversation.lines.duplicate(true);tail.pop_front()
 check(exact(tail,original_story.lines) and exact(loaded.story_state,state_before),"reading generated dialogue preserves story progression and authored sequence")
 for i in 20:loaded.story_conversation(id,"accept")
 check(exact(loaded.story_state,state_before) and exact(order,loaded.active_contract()),"repeated dialogue reads change neither story nor committed order")
 loaded.save_state(Extreme.starter_design(),Extreme.starter_launcher(),{})
 var again=Econ.new();again.load_state();again.enable_story_mode()
 check(exact(again.story_conversation(id,"accept"),conversation),"saved prefix and existing beats survive a real file reload")
 # An unsupported authoring version may preserve current orders, but never
 # advance tomorrow or publish pending reviews while creating no valid offers.
 clean();var future=new_shop();settle_one(future);future.close_day();future.offer_generation_state.version="seeded-offers-v999";future.save_state([],[],{})
 var future_night:Dictionary=snapshot(future);var prior:String=FileAccess.get_file_as_string("user://savegame.json")
 var refused:Dictionary=future.next_day_and_save([],[],{})
 check(not refused.ok and exact(snapshot(future),future_night),"future generation version fails authoring with complete review/day rollback")
 check(future.customer_reviews().is_empty() and future.review_state.pending.size()==1,"failed future authoring reveals no next-day review")
 check(FileAccess.get_file_as_string("user://savegame.json")==prior,"failed future authoring leaves disk snapshot intact")
 # A pre-seed but review-aware writer retains the settings marker while dropping
 # the unknown root seed. Returning here must recover or block, never reseed.
 clean();e=new_shop(0);settle_one(e);e.close_day();e.next_day_and_save([],[],{})
 var full:Dictionary=read_raw();check(full.settings.offer_generation_schema==1 and int(full.offer_generation_state.world_seed)==0,"same-file marker preserves valid zero seed")
 var old=BeforeSeed.new();var old_loaded:Dictionary=old.load_state();check(not old_loaded.is_empty(),"captured pre-seed writer can read current safe ledger")
 check(old.save_state(old_loaded.design,old_loaded.launcher,old_loaded.settings),"captured pre-seed writer performs actual unknown-field-drop save")
 var lost:Dictionary=read_raw();check(not lost.has("offer_generation_state") and lost.settings.offer_generation_schema==1,"old writer retains marker but drops root seed as expected")
 var recovered=Econ.new();var recovered_data:Dictionary=recovered.load_state()
 check(not recovered_data.is_empty() and not recovered.review_load_blocked and int(recovered.offer_generation_state.world_seed)==0,"one old write recovers exact seeded backup")
 old.save_state(old_loaded.design,old_loaded.launcher,old_loaded.settings)
 var primary_before:String=FileAccess.get_file_as_string("user://savegame.json");var backup_before:String=FileAccess.get_file_as_string("user://savegame.backup.json")
 var blocked=Econ.new();check(blocked.load_state().is_empty() and blocked.review_load_blocked,"two old writes cannot become a newly seeded shop")
 check(not blocked.save_state([],[],{}) and FileAccess.get_file_as_string("user://savegame.json")==primary_before and FileAccess.get_file_as_string("user://savegame.backup.json")==backup_before,"blocked downgrade preserves both actual source files")
 var app=Main.new();root.add_child(app);await process_frame
 check(app.economy.review_load_blocked and app.world==null and not app.is_processing(),"real controller does not render or autosave a new shop for lost seed")
 app._action("next_day",null);app._on_focus_exited();app._on_focus_entered();app.render();app.start_flight(false)
 check(FileAccess.get_file_as_string("user://savegame.json")==primary_before and app.sim==null,"recovery controller actions cannot overwrite or launch")
 app.queue_free();await process_frame
 # Explicit corrupt roots are rejected even if their contracts are harmless.
 for damaged in [null,[],{"version":"seeded-offers-v1","world_seed":-1},{"version":"","world_seed":42}]:
  clean();var bad:Dictionary=full.duplicate(true);bad.offer_generation_state=damaged;save_raw(bad)
  var damaged_save:String=FileAccess.get_file_as_string("user://savegame.json")
  var b=Econ.new();check(b.load_state().is_empty() and b.review_load_blocked,"malformed root seed fails closed: "+str(damaged))
  check(not b.save_state([],[],{}) and FileAccess.get_file_as_string("user://savegame.json")==damaged_save,"malformed root remains preserved")
 clean();var missing:Dictionary=full.duplicate(true);missing.erase("offer_generation_state");missing.settings.erase("offer_generation_schema");save_raw(missing)
 var missing_seed=Econ.new();check(missing_seed.load_state().is_empty() and missing_seed.review_load_blocked,"realized generated offers without root cannot be treated as genuine legacy")
 clean();var mismatched:Dictionary=full.duplicate(true);mismatched.offer_generation_state.world_seed=1;save_raw(mismatched)
 var bad_seed=Econ.new();check(bad_seed.load_state().is_empty() and bad_seed.review_load_blocked,"known generated snapshots cannot silently belong to a different root seed")
 # Genuine pre-seed save with an unusable story seed cannot silently seed or
 # display an interactive new shop while claiming recovery mode.
 clean();var invalid_identity:Dictionary=full.duplicate(true);invalid_identity.erase("offer_generation_state");invalid_identity.settings.erase("offer_generation_schema");invalid_identity.contracts=[];invalid_identity.story_state.world_seed=-1
 save_raw(invalid_identity);var invalid_bytes:String=FileAccess.get_file_as_string("user://savegame.json")
 var unusable=Main.new();root.add_child(unusable);await process_frame
 check(unusable.economy.review_load_blocked and unusable.world==null and not unusable.is_processing(),"invalid legacy identity seed stays in recovery-only UI before world construction")
 unusable._action("next_day",null);unusable._on_focus_exited();unusable._on_focus_entered()
 check(FileAccess.get_file_as_string("user://savegame.json")==invalid_bytes,"initializer failure preserves actual legacy bytes without replacement seed")
 unusable.queue_free();await process_frame
 clean();print("SEEDED_REVIEW_TRANSACTIONS passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
