extends SceneTree
## Minimal extraction from the newest earned ordinary Main harness.
## API-only. Original check/equal/shop choreography/accept/guide/command bodies
## are unchanged. Genesis, economy injection, fault helpers and route splice absent.
const Main=preload("res://scenes/main.tscn")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
var game
var passed:int=0
var failed:int=0
var failures:Array=[]
var stage:String="bootstrap"

func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;failures.append(stage+": "+label);push_error("FAIL "+label)
 return ok
func equal(a:Variant,b:Variant) -> bool:
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for k in a:
   if not b.has(k) or not equal(a[k],b[k]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not equal(a[i],b[i]):return false
  return true
 return a==b
func frames(n:int=3) -> void:
 for unused in n:await process_frame
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func bytes() -> PackedByteArray:return FileAccess.get_file_as_bytes("user://savegame.json")
func ledger() -> Dictionary:
 var e=game.economy
 return {"credits":e.credits,"reputation":e.reputation,"jobs":e.jobs_today,"deliveries":e.deliveries,"stock":e.inventory.duplicate(true),"history":e.history.duplicate(true),"settled":e.settled_ids.duplicate(true),"reviews":e.review_state.duplicate(true),"tier":e.workshop_tier,"research":e.research}
func dispose() -> void:
 if is_instance_valid(game):game.queue_free();await frames(4)
 game=null
func shop_step(seconds:float) -> void:
 for unused in ceili(seconds*120.0):
  var tween:Tween=game.world._parcel_tween
  if tween!=null and game.world._focus_active and game.world.is_visible_in_tree():tween.pause();tween.custom_step(1.0/120.0)
  game.world._process(1.0/120.0);game.world.assembly_feedback._process(1.0/120.0);game._process(1.0/120.0)
func drain_stories() -> void:
 game.navigate("hub")
 for unused in 3600:
  if game._dialogue_is_open():game.dialogue.skip_conversation()
  game._restore_story_dialogue();shop_step(1.0/120.0)
  if not game._dialogue_is_open() and game._pending_story.is_empty() and game.economy.pending_story_returns().is_empty():break
 await frames()
 check(not game._dialogue_is_open() and game._pending_story.is_empty(),"story completion releases controller ownership")
func accept(id:String,interrupted:bool=false,natural:bool=false) -> bool:
 game.navigate("hub");game.world.request_shop_navigation("focus_counter")
 for unused in 3600:
  if game.world.is_at_shop_counter():break
  shop_step(1.0/120.0)
 game._action("accept_contract",id)
 for unused in 3600:
  if game._dialogue_is_open():break
  shop_step(1.0/120.0)
 if not check(game.economy.active_contract_id==id and game._dialogue_is_open(),id+" accepts through Main and opens the real customer dialogue"):return false
 var before:Dictionary=ledger()
 game.start_flight(false)
 check(game.page!="flight" and game.economy.in_flight.is_empty(),id+" unread acceptance blocks dispatch")
 game.dialogue.skip_conversation();game._sync_loading_scene_ui()
 check(game._loading_scene_active() and not game.economy.is_cargo_loaded(),id+" starts loading without prematurely claiming durable cargo")
 if interrupted:
  shop_step(.25);game._on_focus_exited()
  var frozen:Dictionary=game.world.loading_snapshot();shop_step(.5);game._skip_loading_scene(id)
  check(equal(game.world.loading_snapshot(),frozen) and not game.economy.is_cargo_loaded(),id+" focus loss freezes loading and rejects skip")
  game._on_focus_entered();check(game.save_game(),id+" interrupted loading saves accepted-unloaded state")
  check(not bool(disk().contracts[0].cargo_loaded),id+" incomplete loading remains false on disk")
  if not await boot():return false
  check(game.world.is_loading() and not game._dialogue_is_open() and not game.economy.is_cargo_loaded(),id+" restart resumes loading without repeating read acceptance")
 if natural:
  shop_step(24.0)
 else:
  game._skip_loading_scene("foreign")
  check(not game.economy.is_cargo_loaded(),id+" foreign skip cannot install this parcel")
  game._action("skip_loading_scene",null)
 await frames()
 if not check(game.economy.is_cargo_loaded(id) and game.world.is_parcel_loaded(id) and game.page=="workshop",id+" reaches the real durable loaded workshop"):return false
 check(equal(ledger(),before),id+" loading changes no money, parts, quota, receipt or review")
 var durable:PackedByteArray=bytes()
 for unused in 4:game._on_cargo_loading_complete(id);game._skip_loading_scene(id)
 check(bytes()==durable and equal(ledger(),before),id+" repeated completion/skip is financially and durably idempotent")
 return true

func guide() -> int:
 ## Offline test pilot from the existing ground/seeded reference tests. Commands
 ## only. Never write position, velocity, resources, route, outcome or solver.
 var s=game.sim;var at:Vector2=s.cargo_position();var offset:float=0.0
 for gate in s.route.get("pilot_gates",[]):
  if at.x<float(gate.x)+6.5:offset=float(gate.lane_offset);break
 var normal:Vector2=Ascent.path_tangent(at.x,s.route).orthogonal()*-1.0
 var body:Dictionary=s._cargo_body();var velocity:Vector2=body.get("velocity",Vector2.ZERO)
 var lateral:float=velocity.dot(normal)
 var acceleration:float=float(s.route.pilot_net_force_limit)/maxf(1.0,float(body.get("mass",10.2)))
 var preview:float=lateral*(.45+absf(lateral)/(2.0*acceleration*.9))
 var error:float=Ascent.path_y(at.x,s.route)+offset-at.y-preview
 return int(signf(error))*1000 if absf(error)>.9 else 0
func command(axis:int) -> void:
 game.pilot_keys.clear()
 if axis!=0:game.pilot_keys[KEY_S if axis>0 else KEY_W]=true
func boot() -> bool:
 await dispose()
 game=Main.instantiate()
 root.add_child(game);game.set_process(false)
 if is_instance_valid(game.world):
  game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 await frames(4)
 return check(not game.economy.review_load_blocked and not game.pilot_resume_blocked and is_instance_valid(game.world),"actual Main boots the private earned-save shop without recovery hold")

