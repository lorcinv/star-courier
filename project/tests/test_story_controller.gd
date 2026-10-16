extends SceneTree
## Real main-scene integration. Synthetic Godot input, not native OS evidence.
var game
var passed:int=0
var failed:int=0
var observed_tweens:Array=[]
var observed_ids:Dictionary={}
var setup_passed:int=0

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
# Successor fixture: use real Main/World clocks and shop navigation. Never set
# actor positions, story flags, cargo state or economy fields to satisfy a gate.
func require_setup(ok:bool,label:String) -> bool:
 if ok:setup_passed+=1;print("SETUP_PASS ",label)
 else:check(false,"fixture precondition: "+label)
 return ok
func step() -> void:
 var dt:float=1.0/120.0
 var tween:Tween=game.world._parcel_tween
 if tween!=null and game.world._focus_active and game.world.is_visible_in_tree():tween.pause();tween.custom_step(dt)
 game.world._process(dt);game.world.assembly_feedback._process(dt);game._process(dt)
func prepare_counter(id:String) -> bool:
 game.navigate("hub")
 for unused in 2400:
  if game.world.has_counter_customer(id):break
  step()
 if not require_setup(game.world.has_counter_customer(id),"matching customer physically arrives: "+id):return false
 game._action("focus_counter",null)
 for unused in 2400:
  if game.world.is_at_shop_counter():break
  step()
 return require_setup(game.world.is_at_shop_counter() and game.is_shop_action_available("accept_contract"),"real clerk navigation reaches an available counter: "+id)
func accept(id:String) -> bool:
 if not prepare_counter(id):return false
 game._action("accept_contract",id);await settle()
 return require_setup(game.economy.active_contract_id==id and game.dialogue.is_open() and str(game._active_story.get("dialogue_id",""))==id+"/accept" and not game.dialogue._actor.is_empty(),"accepted order owns a real open dialogue: "+id)
func finish_loading() -> bool:
 for unused in 3600:
  if game.economy.is_cargo_loaded() and game.world.is_parcel_loaded():break
  step()
 await settle()
 return require_setup(game.economy.is_cargo_loaded() and game.world.is_parcel_loaded() and not game._loading_scene_active(),"real loading completes before flight coverage")
func robot_portrait_matches() -> bool:
 var robot_path:String="res://assets/2d_v5/npcs/robot_machinist/portraits/neutral.png"
 var human_path:String="res://assets/2d_v5/dialogue/human_courier-neutral.png"
 var displayed:Texture2D=game.dialogue._left_portrait.texture
 var source:Texture2D=game.dialogue._npc_texture("neutral")
 var robot:Texture2D=load(robot_path)
 var human:Texture2D=load(human_path)
 if displayed==null or source==null or robot==null or human==null:return false
 if source!=robot or source.resource_path!=robot_path or Vector2i(displayed.get_size())!=Vector2i(202,202):return false
 var actual:Image=displayed.get_image()
 var expected:Image=robot.get_image().duplicate()
 var fallback:Image=human.get_image().duplicate()
 if actual==null or actual.is_empty() or expected.is_empty() or fallback.is_empty():return false
 expected.resize(202,202,Image.INTERPOLATE_NEAREST);fallback.resize(202,202,Image.INTERPOLATE_NEAREST)
 return actual.get_size()==Vector2i(202,202) and actual.get_format()==expected.get_format() and actual.get_data()==expected.get_data() and actual.get_data()!=fallback.get_data()
func finish() -> void:
 await dispose()
 print("STORY_CONTROLLER passed=%d failed=%d setup_passed=%d native_input=false"%[passed,failed,setup_passed])
 quit(1 if failed else 0)
func settle(frames:int=4) -> void:
 for i in frames:
  await process_frame
  if is_instance_valid(game) and is_instance_valid(game.dialogue) and game.dialogue._entrance_tween!=null:
   var tween:Tween=game.dialogue._entrance_tween
   if not observed_ids.has(tween.get_instance_id()):
    observed_ids[tween.get_instance_id()]=true;observed_tweens.append(weakref(tween))
 # Production now walks the clerk back to the counter before a queued portrait
 # conversation. This fixture disables main._process, so explicitly advance
 # that pending presentation rather than assuming an instantaneous teleport.
 if is_instance_valid(game) and not game._pending_story.is_empty() and not game.dialogue.is_open():
  for i in 1800:
   if game._pending_story.is_empty() or game.dialogue.is_open() or game._story_save_attempted:break
   step()
  if game.dialogue._entrance_tween!=null:
   var tween:Tween=game.dialogue._entrance_tween
   if not observed_ids.has(tween.get_instance_id()):observed_ids[tween.get_instance_id()]=true;observed_tweens.append(weakref(tween))
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await settle()
 game=null
func fresh(erase:bool=true) -> void:
 await dispose()
 if erase:
  for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
   if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false)
 game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await settle()
func key(code:int,ctrl:bool=false) -> void:
 var event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;event.ctrl_pressed=ctrl
 Input.parse_input_event(event);await settle(1)
 event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false;event.ctrl_pressed=ctrl
 Input.parse_input_event(event);await settle(1)
func skip() -> void:
 await key(KEY_ESCAPE)
 check(not game.dialogue.is_open(),"Escape finishes only the active dialogue")

func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():printerr("ISOLATED XDG_DATA_HOME REQUIRED");quit(2);return
 root.size=Vector2i(1280,800)
 await fresh()
 check(FileAccess.file_exists("user://savegame.json"),"fresh main persists its cosmetic seed before interaction")
 var initial:Dictionary=disk()
 check(initial.story_state.roster.size()==4 and initial.story_state.contract_bindings.size()==2,"fresh main persists four identities and two daily contract bindings")
 check(not game.dialogue.is_open() and game.page=="hub","fresh shop starts without unsolicited dialogue")
 var seed:int=int(initial.story_state.world_seed)
 if not await accept("D1-A"):await finish();return
 check(game.dialogue.is_open() and game._active_story.dialogue_id=="D1-A/accept","real accept action opens the contract-scoped acceptance dialogue")
 check(game.dialogue._actor.appearance_id=="human_courier" and game.dialogue._actor.name==game.economy.active_contract().client,"world contract and portrait share the same saved identity")
 check(game.dialogue._left_portrait.texture!=null and game.dialogue._right_portrait.texture!=null,"NPC-left and clerk-right fine portraits resolve in the main scene")
 check(disk().story_state.seen_dialogue_ids.is_empty(),"opening a dialogue does not claim it was read")
 var before:Dictionary=disk()
 var blueprint:Array=game.design.duplicate(true)
 game.selected_id=4
 for code in [KEY_R,KEY_DELETE]:await key(code)
 await key(KEY_Z,true);await key(KEY_W);await key(KEY_SHIFT)
 game._action("cancel_contract",null);game._action("focus_workbench",null);game._action("dispatch",null)
 game.start_flight(true)
 var click=InputEventMouseButton.new();click.pressed=true;click.button_index=MOUSE_BUTTON_LEFT;click.position=Vector2(480,400)
 game._viewport_input(click)
 check(game.design==blueprint and game.page=="hub" and game.sim==null,"dialogue captures editor keys, direct action routing, pointer assembly and launch")
 check(disk()==before and game.pilot_keys.is_empty(),"blocked dialogue input changes no ledger or held flight keys")
 game.dialogue.set_process(false);game.dialogue._process(.10)
 game._on_focus_exited()
 var revealed:int=game.dialogue._visible_chars
 game.dialogue._process(5.0)
 check(game.dialogue._visible_chars==revealed and game.dialogue.debug_snapshot().active_voices==0,"focus loss stops dialogue reveal and current bleeps")
 game._on_focus_entered();game.dialogue.set_process(false);game.dialogue._process(.10)
 check(game.dialogue._visible_chars>revealed,"focus return resumes without catch-up reveal")
 game.dialogue._on_volume_changed(.35);game.dialogue._toggle_mute()
 check(disk().settings.dialogue_volume==.35 and disk().settings.dialogue_muted,"dialogue volume and mute persist through real component signals")
 await fresh(false)
 check(game.dialogue.is_open() and game._active_story.dialogue_id=="D1-A/accept","closing before completion reopens the same unread acceptance")
 check(int(game.economy.story_state.world_seed)==seed and disk().story_state.roster==initial.story_state.roster,"reload never changes saved species or cosmetic seed")
 check(game.dialogue.audio_muted and is_equal_approx(game.dialogue.audio_volume,.35),"reopened dialogue restores its audio preferences")
 await skip()
 check(disk().story_state.seen_dialogue_ids["D1-A"].has("D1-A/accept"),"skipping persistently marks only that acceptance seen")
 check(game.economy.active_contract_id=="D1-A" and game.page=="hub","Escape dialogue does not cancel the order or navigate elsewhere")
 if not await finish_loading():await finish();return
 game.start_flight(true);game._step_flight();game.abort_flight();await settle()
 check(game.report.trial and not game.dialogue.is_open(),"free trial report never opens a paid-result conversation")
 check(game.economy.credits==260 and game.economy.story_state.committed_contract_ids.is_empty(),"free trial never changes money or story progression")
 game.start_flight(false);game._step_flight();game.abort_flight();await settle()
 check(game.page=="report" and game.dialogue.is_open() and game._active_story.dialogue_id=="D1-A/result","formal failure opens its saved result conversation over the report")
 check(game.dialogue._conversation.lines[0].expression=="concerned","failed delivery gets failure text rather than a success claim")
 var settled:Dictionary=disk();var money:int=game.economy.credits
 check(settled.settled_ids.has("D1-A") and settled.story_state.committed_contract_ids.has("D1-A") and settled.story_state.roster.human_courier.story_node==1,"one atomic save contains both unique settlement and story advancement")
 game.finish_flight();game.abort_flight()
 check(game.economy.credits==money and game.economy.jobs_today==1 and game.economy.story_state.roster.human_courier.story_node==1,"repeated terminal actions cannot award money or story progress twice")
 await fresh(false)
 check(game.dialogue.is_open() and game._active_story.dialogue_id=="D1-A/result" and game.economy.credits==money,"restart of an unread result restores dialogue without re-settlement")
 await skip()
 # The departed D1-A customer cannot speak through D1-B's elf. Keep the
 # same-day accounting assertion here; exercise its return on the next genuine
 # human visit below, after normal Main day transitions.
 game.navigate("hub");await settle()
 check(game.economy.credits==money and game.economy.jobs_today==1 and game.economy.settled_ids.size()==1,"accept/result dialogue restart/skip paths leave unique accounting intact")
 if not require_setup(not game.dialogue.is_open() and not game.economy.story_state.pending_returns.is_empty(),"departed human return waits while a different customer is assigned"):await finish();return
 if not await accept("D1-B"):await finish();return
 check(game.dialogue._actor.species=="elf" and game.dialogue._actor.appearance_id=="elf_archivist","the second day's-slot visitor uses the matching elf portrait identity")
 await skip();game._action("cancel_contract",null);await settle()
 check(game.economy.story_state.roster.elf_archivist.story_node==0 and not game.economy.story_state.committed_contract_ids.has("D1-B"),"cancelling accepted work advances no story node")
 game._action("close_day",null);game._action("next_day",null);await settle()
 if not await accept("D2-A"):await finish();return
 check(game.dialogue._actor.species=="alien" and game.dialogue._actor.appearance_id=="alien_botanist","next day exposes the recognizable alien identity")
 await skip();game._action("cancel_contract",null)
 if not await accept("D2-B"):await finish();return
 check(game.dialogue._actor.species=="robot" and game.dialogue._actor.appearance_id=="robot_machinist","next day also exposes the matching robot identity")
 check(robot_portrait_matches(),"robot conversation uses its own portrait art rather than a human fallback")
 await skip()
 for i in range(40):
  game._request_story("D2-B","accept")
  check(not game.dialogue.is_open(),"seen acceptance remains closed on repeated request %d"%i)
 check(game.dialogue.debug_snapshot().voice_pool_size==3 and game.dialogue.debug_snapshot().queued_bleeps==0,"main keeps a bounded three-voice pool and no deferred bleep queue")
 # Normal cancellation and next-day authoring bring the same saved human back
 # under D3-A; the historical return still belongs to settled D1-A.
 game._action("cancel_contract",null);game._action("close_day",null);game._action("next_day",null)
 var return_money:int=game.economy.credits;var return_jobs:int=game.economy.jobs_today
 var return_settled:Dictionary=game.economy.settled_ids.duplicate(true)
 await settle()
 if not require_setup(game.economy.day==3 and game.world.has_counter_customer("D3-A") and str(game.economy.story_actor("D3-A").get("appearance_id",""))=="human_courier","normal day rotation brings the same saved customer to the real counter"):await finish();return
 check(game.dialogue.is_open() and game._active_story.get("dialogue_id")=="D1-A/return","returning customer at the real counter presents the queued follow-up")
 if not require_setup(game.dialogue.is_open(),"return dialogue is open before restart"):await finish();return
 await fresh(false)
 check(game.dialogue.is_open() and game._active_story.get("dialogue_id")=="D1-A/return","unread return survives process lifetime without claiming completion")
 await skip();await fresh(false)
 check(not game.dialogue.is_open() and game.economy.story_state.pending_returns.is_empty(),"seen result and return do not repeat after another restart")
 if not require_setup(game.economy.credits==return_money and game.economy.jobs_today==return_jobs and game.economy.settled_ids==return_settled and game.economy.settled_ids.size()==1 and game.economy.story_state.roster.human_courier.story_node==1,"return restart/skip preserves the new day's exact accounting and the sole historical settlement"):await finish();return
 await dispose()
 var retained:int=0
 for ref in observed_tweens:
  if ref.get_ref()!=null:retained+=1
 check(not observed_tweens.is_empty() and retained==0,"controller teardown releases every observed live entrance Tween")
 if passed+failed!=81:check(false,"all 81 planned story-controller assertions ran")
 print("STORY_CONTROLLER passed=%d failed=%d setup_passed=%d native_input=false"%[passed,failed,setup_passed])
 quit(1 if failed else 0)
