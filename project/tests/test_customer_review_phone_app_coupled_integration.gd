extends SceneTree
## Explicit successor of test_customer_review_phone_app_integration.gd.
## Real Main + bootstrap-before-ready + current coupled World/renderer.
## Scripted Godot UI events/signals only; no native OS, physical input, or visual approval.
## Assertion amendments are enumerated in ASSERTION-AMENDMENTS.md.
const Bootstrap=preload("res://scripts/clerk_runtime_bootstrap_observed_v4.gd")
const Reviews=preload("res://scripts/customer_reviews.gd")
var passed:int=0
var failed:int=0
var game
var input
var frame_budget_ok:bool=true
var identity:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(n:int=2) -> void:
 for unused in n:await process_frame
func key(code:int,pressed:bool=true,echo:bool=false,shift:bool=false) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.echo=echo;event.shift_pressed=shift;Input.parse_input_event(event);await settle(1)
func button(code:int,pressed:bool=true) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=code;event.pressed=pressed;Input.parse_input_event(event);await settle(1)
func axis(code:int,value:float) -> void:
 var event:=InputEventJoypadMotion.new();event.device=0;event.axis=code;event.axis_value=value;Input.parse_input_event(event);await settle(1)
func tap(code:int) -> void:await button(code);await button(code,false)
func phone_button() -> Control:
 for child in game.hud.content.find_children("*","Button",true,false):
  if str(child.get_meta("view_key",""))=="action:customer_reviews:null":return child
 return null
func owned_focus() -> bool:
 var owner:Control=root.gui_get_focus_owner()
 return owner!=null and game.review_phone.focus_root().is_ancestor_of(owner)
func cursor() -> float:return float(game.world._clerk_motion.coupled_renderer_snapshot().provider.accepted_time)
func controls() -> Dictionary:return game.world._clerk_motion.accepted_pose_snapshot().controls
func ids() -> Dictionary:
 var w=game.world;var m=w._clerk_motion
 return {"actor":w.clerk.get_instance_id(),"root_owner":w._shop_motion.get_instance_id(),"model":m._model.get_instance_id(),"motion":m.get_instance_id(),"rig":m._rig.get_instance_id(),"tablet":m._tablet_nodes.tablet.get_instance_id(),"parcel":w.parcel.get_instance_id()}
func step(n:int=30,block_input:bool=false) -> void:
 for unused in n:
  input.tick(1.0/60.0)
  if block_input:game.world.set_shop_input(0.0,false)
  var before:float=cursor()
  game.world._process(1.0/60.0);game.world.assembly_feedback._process(1.0/60.0);game._sync_shop_action_availability()
  frame_budget_ok=frame_budget_ok and cursor()-before<=1.0/60.0+1e-9
  await process_frame
func create_game() -> bool:
 game=load("res://scenes/main.tscn").instantiate()
 # This is the real Main factory hook, before Main/World._ready, not a live swap.
 game.clerk_pose_bootstrap_script=Bootstrap
 root.add_child(game);game.set_process(false)
 if game.world==null or game.courier_input==null:return false
 game.world.set_process(false);game.world.assembly_feedback.set_process(false)
 input=game.courier_input;await settle(5);input.tick(0)
 check(game.world._clerk_pose_setup_error.is_empty() and game.world._clerk_pose_consumer_enabled and game.world._clerk_motion.world_consumer_contract_version()>=2,"real bootstrap initializes coupled World before ready")
 identity=ids()
 return true
func open_phone() -> bool:
 game._action("customer_reviews",null);await settle();input.tick(0)
 if game._review_phone_is_open():
  check(not game.review_phone.is_reviews_app_open(),"entry opens phone home before reviews")
  var owner:int=game._review_phone_owner
  game.review_phone.open_reviews_app();await settle()
  check(game.review_phone.is_reviews_app_open() and game._review_phone_owner==owner and game.world.review_phone_owned_by(owner),"app navigation retains exact tablet owner")
 return game._review_phone_is_open()
func fake_history(count:int=30) -> bool:
 var state:Dictionary=Reviews.initial_state(1)
 var names:Array=Reviews.ACTORS.keys()
 for day in range(1,count+1):
  var actor:String=str(names[(day-1)%names.size()])
  var facts:Dictionary={"settlement_id":"phone-proof-%d"%day,"delivery_day":day,"client":Reviews.ACTORS[actor],"appearance_id":actor,"route_name":"月面航线","destination_name":"月面收件站","success":true,"elapsed":8.0,"deadline":20.0,"integrity":100.0,"required":80.0}
  state.pending[facts.settlement_id]=facts
  var result:Dictionary=Reviews.publish_next_day(state,day,day+1)
  if not result.ok:check(false,"history fixture publication failed: "+str(result));return false
  state=result.state
 # Current-day settlement facts must remain unpublished and invisible.
 var current_id:String="phone-proof-pending-current"
 state.pending[current_id]={"settlement_id":current_id,"delivery_day":count+1,"client":Reviews.ACTORS[str(names[0])],"appearance_id":str(names[0]),"route_name":"月面航线","destination_name":"月面收件站","success":true,"elapsed":8.0,"deadline":20.0,"integrity":100.0,"required":80.0}
 var normalized:Dictionary=Reviews.normalize_state(state,count+1)
 check(bool(normalized.ok),"historical plus current-day pending facts pass real review validator: "+str(normalized.get("reason","valid")))
 if not normalized.ok:return false
 check(normalized.state.published.size()==count and normalized.state.pending.size()==1,"validated fixture retains all published history and one current-day pending receipt")
 if normalized.state.published.size()!=count or normalized.state.pending.size()!=1:return false
 check(not normalized.state.pending[current_id].has("rating") and not normalized.state.pending[current_id].has("body"),"legitimate current-day receipt remains fact-only")
 game.economy.review_state=state;game.economy.day=count+1
 return true
func abort_fixture(label:String) -> void:
 # Critical setup/card failures must produce a terminal result, never an index
 # exception that abandons this coroutine and leaves a running SceneTree.
 check(false,label)
 if is_instance_valid(game):game.queue_free()
 await settle(4)
 print("CUSTOMER_REVIEW_PHONE_COUPLED_INTEGRATION_ABORT passed=%d failed=%d reason=%s"%[passed,failed,label])
 quit(1)
func review_entries() -> Array:
 return game.review_phone._list.get_children().filter(func(child):return child.has_meta("phone_review"))
func ledger() -> Dictionary:
 return {"credits":game.economy.credits,"reputation":game.economy.reputation,"history":game.economy.history.duplicate(true),"reviews":game.economy.review_state.duplicate(true),"design":game.design.duplicate(true),"launcher":game.launcher.duplicate(true),"story":game.economy.story_state.duplicate(true)}
func clerk_registration() -> Dictionary:
 var sprite:Sprite2D=game.world.clerk;var motion=game.world._clerk_motion
 var head:Sprite2D=motion._parts.head;var rig:Node2D=motion._rig
 var actual:Transform2D=sprite.transform*rig.transform*head.transform
 var draw_scale:=Vector2(actual.x.length(),actual.y.length())
 var draw:Dictionary=motion._bridge_last_draw
 var key:String=str(draw.get("placements",{}).get("head",{}).get("texture_key",""))
 var valid_head:bool=key in ["head_level","head_midpoint","head_reading"] and head.texture==motion._bridge_textures.get(key)
 if valid_head:
  var registration:Dictionary={}
  for view in motion._pose_head_views:
   if view.texture_key==key:registration=view
  var expected_root:Vector2=Vector2(registration.root[0],registration.root[1]) if registration.root is Array else registration.root
  var placement:Dictionary=draw.placements.head
  valid_head=head.transform*expected_root==placement.at or (head.transform*expected_root).distance_to(placement.at)<0.0001
 var single:bool=sprite.texture==null and sprite.get_child_count()==1 and rig.visible and head.visible
 for key_name in motion._bridge_nodes:
  single=single and motion._bridge_nodes[key_name].visible
 single=single and not motion._parts.near_arm.visible and not motion._parts.far_arm.visible and not motion._parts.pelvis.visible
 var layers:bool=true;var prior_layer:int=-999
 for child in rig.get_children():
  layers=layers and child.z_index==0 and child.z_as_relative and not child.top_level
  var layer:int=int(child.get_meta("rig_layer",0));layers=layers and layer>=prior_layer;prior_layer=layer
 return {"draw_scale":[draw_scale.x,draw_scale.y],"body_height":draw_scale.y*240.0,"head_registered":valid_head,"head_key":key,
  "single_representation":single and layers,"facing_right":motion._model.facing_right,"rendered_facing_right":actual.x.x>0.0}
func check_progressive_phone() -> void:
 var m=game.world._clerk_motion;var owner:int=game._review_phone_owner;var root_at:Vector2=game.world.clerk.position
 var start:Dictionary=controls();var previous:float=float(start.draw_progress)
 check(previous==0.0 and start.gesture=="align" and start.tap_state=="pending","UI app queues tap behind a real unraised take")
 var middle:bool=false;var tap_seen:bool=false;var head_middle:bool=false;var head_read:bool=false;var valid:bool=true
 var previous_prop:Vector2=m._tablet_nodes.tablet.position
 for i in 90:
  await step(1)
  var c:Dictionary=controls();var p:float=c.draw_progress;var row:Dictionary=clerk_registration()
  middle=middle or (p>0.0 and p<1.0);tap_seen=tap_seen or float(c.tap_blend)>0.0
  head_middle=head_middle or row.head_key=="head_midpoint";head_read=head_read or row.head_key=="head_reading"
  valid=valid and p>=previous-1e-9 and game._review_phone_owner==owner and game.world._review_phone_owner==owner and m._phone_owner==owner and ids()==identity
  valid=valid and row.head_registered and row.single_representation and game.world.clerk.position==root_at
  valid=valid and (float(c.tap_blend)==0.0 or p==1.0) and previous_prop.distance_to(m._tablet_nodes.tablet.position)<30.0
  previous=p;previous_prop=m._tablet_nodes.tablet.position
 check(valid and middle and head_middle and head_read,"actual take/read samples preserve one actor, owner, scale, registered head and bounded prop motion")
 check(tap_seen and controls().draw_progress==1.0 and controls().tap_state=="complete" and controls().tap_blend==0.0,"actual UI-triggered tap completes only after take reaches held endpoint")
 var before:PackedByteArray=var_to_bytes(controls());var at:float=cursor()
 game.review_phone.open_reviews_app();game._action("customer_reviews",null)
 check(var_to_bytes(controls())==before and cursor()==at and game._review_phone_owner==owner,"repeated app/open intent neither requeues tap nor consumes time")
 game.review_phone._close.pressed.emit()
 check(controls().gesture=="reach" and game._review_phone_owner==owner and game._review_phone_is_open(),"actual app Back changes only same-owner finger intent")
 game.review_phone._app.pressed.emit();await step(4)
 check(controls().gesture=="align" and controls().tap_blend>0.0,"fresh actual app button starts a fresh tap")
 game.review_phone._close.pressed.emit()
 check(controls().tap_state=="withdrawing" and controls().draw_progress==1.0,"Back during tap withdraws fingers without returning tablet")
 await step(10)
 check(controls().tap_blend==0.0 and controls().draw_progress==1.0 and game._review_phone_owner==owner,"home settles finger withdrawal while retaining held device and owner")
 game.review_phone._app.pressed.emit();await step(20)
 var before_bad:PackedByteArray=var_to_bytes(controls())
 check(not game.world.set_review_phone_page(owner+1,"reviews") and not game.world.set_review_phone_page(owner,"unknown") and var_to_bytes(controls())==before_bad,"foreign owner and unknown page cannot change presentation")
func check_close_easing(label:String) -> void:
 var m=game.world._clerk_motion;var owner:int=game.world._review_phone_owner;var root_at:Vector2=game.world.clerk.position
 var previous:float=controls().draw_progress;var initial:float=previous;var at:float=cursor();var landed_at_start:bool=m._model.settled
 check(owner!=0 and game.world._review_phone_closing and game._review_phone_owner==0,label+" dismisses UI while retaining exact presentation owner")
 check(not game.world.set_review_phone_page(owner,"reviews"),label+" closing owner rejects page intent")
 var valid:bool=true;var middle:bool=false
 for unused in 90:
  if game.world._review_phone_owner==0:break
  var readiness:Dictionary=m.coupled_finish_readiness("phone",owner)
  valid=valid and readiness.valid
  await step(1,true)
  var p:float=controls().draw_progress
  middle=middle or (p>0.0 and p<initial)
  valid=valid and p<=previous+1e-9 and p>=0.0 and game.world.clerk.position==root_at and ids()==identity and clerk_registration().single_representation
  if game.world._review_phone_owner!=0:valid=valid and game.world._review_phone_owner==owner and m._phone_owner==owner
  else:valid=valid and m._model.settled and not m._model.settling and not m._model.travelling and m._model.feet.near.planted and m._model.feet.far.planted
  previous=p
 check(valid and game.world._review_phone_owner==0 and previous==0.0 and (middle or initial==0.0),label+" lowers progressively and releases only at actual double support")
 if landed_at_start:check(absf(cursor()-at-initial*.30)<1e-8,label+" uses current exact 300ms accepted lower contract")
 var released:float=cursor();var body:PackedByteArray=var_to_bytes(m._model.snapshot())
 await step(12,true)
 check(m.coupled_renderer_snapshot().provider.mode=="walk" and absf(cursor()-released-.12)<1e-8 and var_to_bytes(m._model.snapshot())==body,label+" finishes finite 120ms provider release without stepping settled body")
 check(m._tablet_nodes.tablet.visible and m._bridge_last_draw.storage_owner=="hip_storage" and not m._parts.near_arm.visible and not m._parts.far_arm.visible,label+" returns the one prop to storage behind torso using continuous articulated arms")
 check(game.world._motion_failures.is_empty() and game.world._clerk_observation_rejections.is_empty(),label+" leaves no motion or observation rejection")
func check_natural_loaded_phone() -> void:
 # Real economy accepted order and actual World transport; no body/pose setters.
 var id:String=str(game.economy.available_contracts()[0].contract_id)
 check(game.economy.accept_contract(id).ok,"loaded scenario accepts a real economy contract")
 game.economy.mark_story_seen(id,id+"/accept");game.render();await settle()
 check(game.world.begin_loading(id),"loaded scenario starts real customer/counter/robot transport")
 for unused in 1800:
  if game.world.parcel_state=="loaded":break
  await step(1,true)
 await settle(3)
 check(game.world.parcel_state=="loaded" and game.world._clerk_state=="ready" and game.economy.is_cargo_loaded(id),"actual transport reaches durable loaded ready without forging settled state")
 game.navigate("hub");await settle()
 var before:Dictionary=ledger();var at:Vector2=game.world.clerk.position;var prop:int=game.world._clerk_motion._tablet_nodes.tablet.get_instance_id()
 check(await open_phone(),"naturally completed loading transfers same prop into explicit phone")
 check(controls().draw_progress==1.0 and game.world._clerk_motion._tablet_nodes.tablet.get_instance_id()==prop and ids()==identity,"ready-to-phone retains exact actual actor model and held prop")
 await step(30);game._close_review_phone();await check_close_easing("natural loaded phone")
 check(game.world._clerk_state=="free" and game.world.clerk.position==at and ledger()==before,"loaded phone returns naturally without moving root or changing durable business facts")

func run() -> void:
 for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 if not await create_game():check(false,"real Main construction succeeds");quit(2);return
 check(not game._review_phone_is_open() and not game.review_phone._root.visible,"startup never opens review phone")
 check(phone_button()!=null and phone_button().name=="PhoneLauncher" and phone_button().text.is_empty() and not phone_button().tooltip_text.is_empty(),"shop has accessible phone-shaped launcher instead of top text entry")
 game.navigate("workshop");await settle();check(phone_button()==null and not await open_phone(),"workshop has no phone action and rejects direct opening")
 game.navigate("hub");await settle();input.tick(0)
 var original:Dictionary=ledger();var position:Vector2=game.world.clerk.position;var registration:Dictionary=clerk_registration();var depth:int=game.world.clerk.z_index;var facing:bool=game.world._clerk_motion.debug_snapshot().facing_right
 check(await open_phone(),"explicit shop intent opens phone")
 check(input.context=="phone" and owned_focus(),"phone owns dedicated input context and native focus")
 check(game.review_phone._list.get_child_count()==1 and game.review_phone._list.get_child(0) is Label,"empty feed uses concise native label")
 await check_progressive_phone()
 var opened:Dictionary=clerk_registration()
 check(game.world.clerk.position==position and Vector2(opened.draw_scale[0],opened.draw_scale[1]).is_equal_approx(Vector2(registration.draw_scale[0],registration.draw_scale[1])) and is_equal_approx(opened.body_height,210.0) and opened.head_registered and opened.single_representation and game.world.clerk.z_index==depth and opened.facing_right==facing and opened.rendered_facing_right==facing,"entry preserves root, actual source draw scale, registered head, depth, facing and one visible representation")
 check(not game.world._shop_control_available() and game.world.shop_interaction().is_empty(),"world denies direct movement and interaction while phone owns clerk")
 var owner:int=game._review_phone_owner;game.world.release_review_phone(owner+1)
 check(game.world.review_phone_owned_by(owner),"foreign owner cannot release phone pose")
 game._action("customer_reviews",null);check(game._review_phone_owner==owner,"repeated open intent keeps one owner")
 game._action("focus_workbench",null);game._action("accept_contract",str(game.economy.contracts[0].contract_id));game.rotate_part();game.remove_part();game.undo_assembly();game.start_flight(true)
 check(game.page=="hub" and ledger()==original,"phone rejects hidden actions, assembly and flight mutations")
 await key(KEY_D);await key(KEY_E);await button(JOY_BUTTON_DPAD_RIGHT);await axis(JOY_AXIS_LEFT_X,.95);await step()
 check(game.world.clerk.position==position and controls().gesture=="align" and controls().draw_progress==1.0 and game.world._shop_motion.velocity==0.0,"keyboard/pad/stick cannot move or overwrite tablet pose")
 await key(KEY_E,false);await button(JOY_BUTTON_DPAD_RIGHT,false)
 game.render();await settle();await step()
 check(game._review_phone_is_open() and controls().gesture=="align" and controls().draw_progress==1.0,"ordinary render and idle updates preserve tablet owner")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open() and game._review_phone_owner==owner,"Escape leaves reviews for home without releasing tablet")
 await key(KEY_ESCAPE)
 check(not game._review_phone_is_open() and game.page=="hub" and not game.hud.settings_open,"Escape closes only phone")
 check(game.world._review_phone_owner==owner and game.world._review_phone_closing,"UI close retains matched owner until real return settles")
 var closed:Dictionary=clerk_registration()
 check(game.world.clerk.position==position and Vector2(closed.draw_scale[0],closed.draw_scale[1]).is_equal_approx(Vector2(registration.draw_scale[0],registration.draw_scale[1])) and is_equal_approx(closed.body_height,210.0) and closed.head_registered and closed.single_representation and game.world.clerk.z_index==depth and closed.facing_right==facing and closed.rendered_facing_right==facing,"UI dismissal preserves the registered representation, root, source scale, depth and facing before retained-owner return")
 await check_close_easing("first phone close")
 await step();check(game.world.clerk.position==position and input.shop_axis()==0,"held keyboard and stick remain quarantined after close")
 await key(KEY_ESCAPE,false);await key(KEY_D,false);await axis(JOY_AXIS_LEFT_X,0);await step(1);await key(KEY_D);await step(12)
 check(game.world.clerk.position.x>position.x,"fresh released then pressed movement resumes normally")
 await key(KEY_D,false);await step(30)
 # Open through the actual native button using controller confirm.
 await tap(JOY_BUTTON_START);var opener:Control=phone_button();opener.grab_focus();await button(JOY_BUTTON_A)
 check(game._review_phone_is_open() and input.context=="phone","Godot shop action opens via synthetic controller confirm")
 await button(JOY_BUTTON_A);check(game._review_phone_is_open(),"held opening confirm cannot immediately close phone")
 await button(JOY_BUTTON_A,false)
 var controller_owner:int=game._review_phone_owner
 await tap(JOY_BUTTON_A)
 check(game.review_phone.is_reviews_app_open() and game._review_phone_owner==controller_owner,"fresh controller confirm opens home app without reacquiring")
 await tap(JOY_BUTTON_B)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open() and game._review_phone_owner==controller_owner,"controller Back returns app to home with same owner")
 await button(JOY_BUTTON_B)
 check(not game._review_phone_is_open() and game.page=="hub","controller Back closes only phone")
 await button(JOY_BUTTON_B,false);await check_close_easing("controller phone close")
 # Fresh keyboard Godot focused-button opening cannot spill Enter into close.
 input._hub_ui=false;input.synchronize()
 var focused:Control=root.gui_get_focus_owner()
 if focused!=null:focused.release_focus()
 await key(KEY_TAB);await key(KEY_TAB,false)
 check(root.gui_get_focus_owner()!=null,"fresh Tab establishes Godot shop-menu focus from no selection")
 for unused in 12:
  if root.gui_get_focus_owner()==phone_button():break
  await key(KEY_TAB);await key(KEY_TAB,false)
 check(root.gui_get_focus_owner()==phone_button(),"scripted Tab reaches phone action without programmatic focus assignment")
 await key(KEY_ENTER);await key(KEY_ENTER,false)
 check(game._review_phone_is_open(),"scripted Godot keyboard Enter explicitly opens phone")
 await key(KEY_ENTER,true,true);check(game._review_phone_is_open(),"held Enter echo cannot close freshly opened phone")
 await key(KEY_ENTER,false);await key(KEY_ENTER);await key(KEY_ENTER,false)
 check(game.review_phone.is_reviews_app_open(),"fresh keyboard Enter opens app from home focus")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open(),"keyboard back leaves app before closing device")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false);await check_close_easing("keyboard phone close")
 # Natural completed-loading transfer is tested below in a fresh real Main.
 # A scrolling historical feed is built only from economy.customer_reviews().
 if not fake_history():await abort_fixture("legitimate history setup failed; remaining cases not run");return
 original=ledger();check(await open_phone(),"published historical feed opens through main")
 var cards:Array=review_entries();var visible:Array=game.economy.customer_reviews()
 check(cards.size()==30,"view shows bounded thirty published entries")
 check(visible.size()==30,"authoritative economy exposes all thirty validated historical records")
 if cards.size()!=30 or visible.size()!=30:
  await abort_fixture("historical cards/records missing; remaining cases not run");return
 var published_only:bool=not visible.is_empty()
 for record in visible:published_only=published_only and int(record.delivery_day)<game.economy.day and int(record.published_day)<=game.economy.day and record.settlement_id!="phone-proof-pending-current"
 check(published_only and game.economy.review_state.pending.has("phone-proof-pending-current"),"feed exposes previous-day-or-earlier published data and retains same-day facts unpublished")
 var first:Control=review_entries()[0];var close:Control=game.review_phone._close
 check(first.get_child(0).get_child(0).text.contains(str(game.economy.customer_reviews()[0].client)),"feed uses authoritative economy ordering and customer identity")
 await key(KEY_DOWN);await key(KEY_DOWN,false);check(root.gui_get_focus_owner()==first,"geometric keyboard down focuses first review")
 await key(KEY_TAB);await key(KEY_TAB,false);check(root.gui_get_focus_owner()==review_entries()[1],"Tab cycles only phone controls")
 await tap(JOY_BUTTON_DPAD_DOWN);input.tick(.02);check(owned_focus(),"controller navigation remains inside phone focus root")
 game.review_phone._scroll.scroll_vertical=0;await axis(JOY_AXIS_RIGHT_Y,1.0);input.tick(.1)
 check(game.review_phone._scroll.scroll_vertical>0,"right stick scrolls phone rather than hidden HUD")
 await axis(JOY_AXIS_RIGHT_Y,0);await key(KEY_END);await key(KEY_END,false)
 check(game.review_phone._scroll.scroll_vertical>1000,"keyboard End reaches long-feed tail")
 await key(KEY_HOME);await key(KEY_HOME,false);check(game.review_phone._scroll.scroll_vertical==0,"keyboard Home returns feed to top")
 for unused in 35:await key(KEY_TAB);await key(KEY_TAB,false)
 check(owned_focus(),"Tab wrap never escapes into shop HUD")
 close.grab_focus();await key(KEY_SPACE);await key(KEY_SPACE,false)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open(),"review header Back returns home")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
 check(not game._review_phone_is_open() and ledger()==original,"phone close via focused Space is read-only")
 await check_close_easing("feed close")
 # Modal/focus/scripted ownership denials.
 game.hud.settings_open=true;game.hud.render(game.hud.state);check(not await open_phone(),"settings modal blocks opening");game.hud.settings_open=false;game.hud.render(game.hud.state)
 game.hud.dispatch_confirmation_open=true;check(not await open_phone(),"dispatch confirmation blocks opening");game.hud.dispatch_confirmation_open=false
 game.hud._cancel_confirmation_id="guard";check(not await open_phone(),"cancel confirmation blocks opening");game.hud._cancel_confirmation_id=""
 game.dialogue.begin({"dialogue_id":"phone-block","lines":[{"speaker":"npc","text":"测试。"}]},{},game.settings)
 check(not await open_phone(),"dialogue blocks opening");game.dialogue.cancel(false)
 var prior_phase:String=game.world._parcel_phase;game.world._parcel_phase="robot_carry";game.world._loading_requested=true
 check(not await open_phone(),"active cargo transport blocks opening");game.world._parcel_phase=prior_phase;game.world._loading_requested=false
 game.world._clerk_return_requested=true;check(not await open_phone(),"scripted clerk return blocks opening");game.world._clerk_return_requested=false
 game.page="flight";check(not await open_phone(),"flight blocks opening");game.page="hub"
 game._pending_story={"contract_id":"guard","beat":"accept"};check(not await open_phone(),"pending scripted dialogue cannot be displaced");game._pending_story.clear()
 game._on_focus_exited();check(not await open_phone(),"inactive focus blocks opening");game._on_focus_entered()
 game.economy.review_load_blocked=true;check(not await open_phone(),"recovery-blocked ledger rejects phone input");game.economy.review_load_blocked=false
 # Focus loss closes and discards held input without reopening on focus return.
 check(await open_phone(),"phone reopens after guards clear");position=game.world.clerk.position
 await key(KEY_D);await axis(JOY_AXIS_LEFT_X,1.0);game._on_focus_exited()
 var frozen_cursor:float=cursor();var frozen_body:PackedByteArray=var_to_bytes(game.world._clerk_motion._model.snapshot())
 game.world._process(.9)
 check(cursor()==frozen_cursor and var_to_bytes(game.world._clerk_motion._model.snapshot())==frozen_body and game.world._review_phone_owner!=0,"focus loss closes UI but freezes retained presentation owner without elapsed catchup")
 game._on_focus_entered();await check_close_easing("focus interruption");await step()
 check(not game._review_phone_is_open() and game.world._review_phone_owner==0 and game.world.clerk.position==position,"focus interruption releases only phone and never restores held velocity")
 await key(KEY_D);await axis(JOY_AXIS_LEFT_X,1.0);await step();check(game.world.clerk.position==position,"repeated held input after focus return still requires release")
 await key(KEY_D,false);await axis(JOY_AXIS_LEFT_X,0);await step(1)
 # Layout uses the exact existing integer HUD scaling at all target sizes.
 check(await open_phone(),"phone opens for responsive layout proof")
 for size in [Vector2(1280,800),Vector2(1920,1080),Vector2(3840,2160)]:
  var frame:=Rect2(Vector2.ZERO,size);game.review_phone.set_art_frame(frame,Vector2(size.x*.2,size.y*.7));await settle()
  var rect:Rect2=game.review_phone._panel.get_global_rect();var expected:int=clampi(floori(size.y/720.0),1,3)
  check(frame.encloses(rect) and frame.encloses(game.review_phone._device.get_global_rect()) and game.review_phone._ui_scale==expected and rect.size==Vector2(344,500)*expected and game.review_phone._device.get_global_rect().size==Vector2(395,624)*expected,"compact readable phone stays framed at "+str(size))
 game.review_phone.set_art_frame(Rect2(0,0,1280,720),Vector2(1050,500));await settle()
 check(game.review_phone._device.position.x==24 and game.review_phone._panel.position==Vector2(25,56),"phone chooses opposite side from right-side clerk with registered screen")
 await key(KEY_D);game._on_art_frame_changed(game.view_container.display_rect);await settle();await step()
 check(game._review_phone_is_open() and input.shop_axis()==0 and game.world.clerk.position==position,"resize retains owner and quarantines held input")
 game._close_review_phone();await check_close_easing("resize close");await step();check(game.world.clerk.position==position,"resize/close never restores old movement")
 await key(KEY_D,false);await settle()
 # Repeated lifecycle is bounded after deferred native controls are released.
 await open_phone();game._close_review_phone();await check_close_easing("cycle baseline");await settle(5)
 var nodes:int=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT));var objects:int=int(Performance.get_monitor(Performance.OBJECT_COUNT));var tweens:int=get_processed_tweens().size()
 for unused in 40:
  await open_phone();game._close_review_phone();game._close_review_phone();await check_close_easing("repeat cycle "+str(unused));await settle(2)
 await settle(5)
 check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))<=nodes+1,"forty open/close cycles retain bounded native node count")
 check(int(Performance.get_monitor(Performance.OBJECT_COUNT))<=objects+8,"forty cycles retain bounded object count")
 check(get_processed_tweens().size()<=tweens,"phone lifecycle creates no accumulating tweens")
 check(ledger()==original,"navigation, resize and repeated phone use leave all business/story facts unchanged")
 check(await open_phone(),"phone opens before replacement");game.navigate("workshop");await settle();await check_close_easing("page replacement")
 check(not game._review_phone_is_open() and game.world._review_phone_owner==0,"page replacement closes matched owner")
 game.navigate("hub");await settle();await open_phone();var world=game.world;game.remove_child(game.review_phone);game.review_phone.queue_free();await settle();await check_close_easing("panel teardown")
 check(game._review_phone_owner==0 and world._review_phone_owner==0,"panel teardown releases world ownership and input")
 game.queue_free();await settle(5)
 if not await create_game():check(false,"second Main construction succeeds");quit(2);return
 await check_natural_loaded_phone()
 input=game.courier_input;input._hub_ui=true;input.controller_navigation=true;input.synchronize();game._open_review_phone()
 game.queue_free();await settle(5)
 check(not is_instance_valid(game),"root teardown with active controller phone releases children cleanly")
 for filename in ["savegame.json","savegame.backup.json"]:
  var damaged=FileAccess.open("user://"+filename,FileAccess.WRITE);damaged.store_string("{phone-recovery-corruption");damaged.close()
 game=load("res://scenes/main.tscn").instantiate();game.clerk_pose_bootstrap_script=Bootstrap;root.add_child(game);await settle(3)
 check(game.economy.review_load_blocked and game.review_phone==null and game.world==null,"malformed primary and backup never create a phone or world")
 game._action("customer_reviews",null);game._close_review_phone()
 check(not game._open_review_phone() and game._review_phone_owner==0,"late explicit phone actions are null-safe and blocked in recovery-only mode")
 check(FileAccess.get_file_as_string("user://savegame.json")=="{phone-recovery-corruption" and FileAccess.get_file_as_string("user://savegame.backup.json")=="{phone-recovery-corruption","phone attempts preserve both damaged save files")
 game.queue_free();await settle(4)
 check(frame_budget_ok,"all actual coupled World frames consume at most one accepted frame budget")
 print("CUSTOMER_REVIEW_PHONE_COUPLED_INTEGRATION passed=%d failed=%d synthetic_InputEvent=true physical_controller=false native_OS_input=false"%[passed,failed]);quit(1 if failed else 0)
