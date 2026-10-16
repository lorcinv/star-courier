extends SceneTree
## Explicit successor for phone-home/app behavior. Real main/input/world synthetic events; not hardware validation.
## Retains all previous ledger, publication, ownership, modality, scroll and frame checks.
const Reviews=preload("res://scripts/customer_reviews.gd")
var passed:int=0
var failed:int=0
var game
var input
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
func step(n:int=30) -> void:
 for unused in n:input.tick(1.0/60.0);game.world._process(1.0/60.0);game._sync_shop_action_availability()
func open_phone() -> bool:
 game._action("customer_reviews",null);await settle();input.tick(0)
 if game._review_phone_is_open():
  check(not game.review_phone.is_reviews_app_open(),"entry opens phone home before reviews")
  var owner:int=game._review_phone_owner
  game.review_phone.open_reviews_app();await settle()
  check(game.review_phone.is_reviews_app_open() and game._review_phone_owner==owner and game.world.review_phone_owned_by(owner),"app navigation retains exact tablet owner")
 return game._review_phone_is_open()
func fake_history(count:int=30) -> void:
 var state:Dictionary=Reviews.initial_state(1)
 var names:Array=Reviews.ACTORS.keys()
 for day in range(1,count+1):
  var actor:String=str(names[(day-1)%names.size()])
  var facts:Dictionary={"settlement_id":"phone-proof-%d"%day,"delivery_day":day,"client":Reviews.ACTORS[actor],"appearance_id":actor,"route_name":"月面航线","destination_name":"月面收件站","success":true,"elapsed":8.0,"deadline":20.0,"integrity":100.0,"required":80.0}
  state.pending[facts.settlement_id]=facts
  var result:Dictionary=Reviews.publish_next_day(state,day,day+1)
  if not result.ok:push_error("history fixture "+str(result));return
  state=result.state
 game.economy.review_state=state;game.economy.day=count+1
func review_entries() -> Array:
 return game.review_phone._list.get_children().filter(func(child):return child.has_meta("phone_review"))
func ledger() -> Dictionary:
 return {"credits":game.economy.credits,"reputation":game.economy.reputation,"history":game.economy.history.duplicate(true),"reviews":game.economy.review_state.duplicate(true),"design":game.design.duplicate(true),"launcher":game.launcher.duplicate(true),"story":game.economy.story_state.duplicate(true)}
func clerk_registration() -> Dictionary:
 var sprite:Sprite2D=game.world.clerk;var motion=game.world._clerk_motion
 var snap:Dictionary=motion.debug_snapshot()
 var rigid:bool=bool(snap.get("rigid_active",false));var rig:Node2D=sprite.get_node_or_null("ClerkRigidCutouts") as Node2D
 var actual:Transform2D=sprite.transform
 var single:bool=false;var source_size:Vector2=Vector2.ZERO;var reference_height:float=0.0
 var source_path:String="";var exclusive_arms:bool=false
 if rigid and rig!=null:
  var head:Sprite2D=motion._parts.head
  actual=sprite.transform*rig.transform*head.transform
  source_size=head.texture.get_size();source_path=head.texture.resource_path
  reference_height=float(motion._rig_data.reference_height)
  single=sprite.texture==null and rig.visible and head.visible
  for key in motion._parts:
   if key not in ["near_arm","far_arm"]:single=single and motion._parts[key].visible
  exclusive_arms=true
  for side in ["near","far"]:
   var relaxed:bool=motion._parts[side+"_arm"].visible
   var upper:bool=motion._tablet_nodes[side+"_upper"].visible
   var fore:bool=motion._tablet_nodes[side+"_fore"].visible
   var hand:bool=motion._tablet_nodes[side+"_hand"].visible
   exclusive_arms=exclusive_arms and ((relaxed and not upper and not fore and not hand) or (not relaxed and upper and fore and hand))
  single=single and exclusive_arms
 var draw_scale:=Vector2(actual.x.length(),actual.y.length())
 var head_size:Vector2=snap.get("head_size_parent",Vector2.ZERO)
 var valid_head:bool=source_size==Vector2(104,91) and source_path in ["res://assets/2d_v5/actors/reconstructed_recovery_v1/head-level-pixel.png","res://assets/2d_v5/actors/motion_candidate_v1/head-closed-pixel.png"]
 var rendered_right:bool=actual.x.x>0 if rigid else not sprite.flip_h
 return {"draw_scale":[draw_scale.x,draw_scale.y],"body_height":draw_scale.y*reference_height,
  "head_size":[head_size.x,head_size.y],"head_source_size":[source_size.x,source_size.y],
  "head_registered":valid_head and head_size.is_equal_approx(source_size*draw_scale),"head_reference":str(snap.get("head_reference","")),
  "head_source_path":source_path,"exclusive_arms":exclusive_arms,
  "single_representation":single,"facing_right":bool(snap.facing_right),"rendered_facing_right":rendered_right,"rigid":rigid}
func check_close_easing(label:String) -> void:
 var motion=game.world._clerk_motion
 var root_at:Vector2=game.world.clerk.position
 var previous:float=motion._tablet_weight
 var valid:bool=motion._tablet_target==0.0
 # The registered 180ms lower is visible presentation after ownership release.
 # Check the actual transition at each 60Hz world sample, never demand a pop-off.
 for i in 12:
  step(1)
  var current:float=motion._tablet_weight
  valid=valid and current<=previous+0.000001 and current>=0.0 and game.world.clerk.position==root_at
  valid=valid and clerk_registration().single_representation
  previous=current
 check(valid,label+" keeps one arm representation and constant root through monotonic close easing")
 check(motion._tablet_weight==0.0 and not motion._tablet_nodes.tablet.visible and motion._parts.near_arm.visible and motion._parts.far_arm.visible,label+" finishes the declared180ms lower in empty-hand idle")
func run() -> void:
 for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
  if FileAccess.file_exists("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await settle(5)
 game.world.set_process(false);game.world.assembly_feedback.set_process(false);input=game.courier_input;input.tick(0)
 check(not game._review_phone_is_open() and not game.review_phone._root.visible,"startup never opens review phone")
 check(phone_button()!=null and phone_button().name=="PhoneLauncher" and phone_button().text.is_empty() and not phone_button().tooltip_text.is_empty(),"shop has accessible phone-shaped launcher instead of top text entry")
 game.navigate("workshop");await settle();check(phone_button()==null and not await open_phone(),"workshop has no phone action and rejects direct opening")
 game.navigate("hub");await settle();input.tick(0)
 var original:Dictionary=ledger();var position:Vector2=game.world.clerk.position;var registration:Dictionary=clerk_registration();var depth:int=game.world.clerk.z_index;var facing:bool=game.world._clerk_motion.debug_snapshot().facing_right
 check(await open_phone(),"explicit shop intent opens phone")
 check(input.context=="phone" and owned_focus(),"phone owns dedicated input context and native focus")
 check(game.review_phone._list.get_child_count()==1 and game.review_phone._list.get_child(0) is Label,"empty feed uses concise native label")
 check(game.world._clerk_motion.debug_snapshot().pose=="align","world owner reuses registered held-tablet gesture")
 var opened:Dictionary=clerk_registration()
 check(game.world.clerk.position==position and opened.draw_scale==registration.draw_scale and is_equal_approx(opened.body_height,210.0) and opened.head_registered and opened.single_representation and game.world.clerk.z_index==depth and opened.facing_right==facing and opened.rendered_facing_right==facing,"entry preserves root, actual source draw scale, registered head, depth, facing and one visible representation")
 check(not game.world._shop_control_available() and game.world.shop_interaction().is_empty(),"world denies direct movement and interaction while phone owns clerk")
 var owner:int=game._review_phone_owner;game.world.release_review_phone(owner+1)
 check(game.world.review_phone_owned_by(owner),"foreign owner cannot release phone pose")
 game._action("customer_reviews",null);check(game._review_phone_owner==owner,"repeated open intent keeps one owner")
 game._action("focus_workbench",null);game._action("accept_contract",str(game.economy.contracts[0].contract_id));game.rotate_part();game.remove_part();game.undo_assembly();game.start_flight(true)
 check(game.page=="hub" and ledger()==original,"phone rejects hidden actions, assembly and flight mutations")
 await key(KEY_D);await key(KEY_E);await button(JOY_BUTTON_DPAD_RIGHT);await axis(JOY_AXIS_LEFT_X,.95);step()
 check(game.world.clerk.position==position and game.world._clerk_motion.debug_snapshot().pose=="align" and game.world._shop_motion.velocity==0.0,"keyboard/pad/stick cannot move or overwrite tablet pose")
 await key(KEY_E,false);await button(JOY_BUTTON_DPAD_RIGHT,false)
 game.render();await settle();step()
 check(game._review_phone_is_open() and game.world._clerk_motion.debug_snapshot().pose=="align","ordinary render and idle updates preserve tablet owner")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open() and game._review_phone_owner==owner,"Escape leaves reviews for home without releasing tablet")
 await key(KEY_ESCAPE)
 check(not game._review_phone_is_open() and game.page=="hub" and not game.hud.settings_open,"Escape closes only phone")
 check(game.world._clerk_motion.debug_snapshot().pose=="idle" and game.world._review_phone_owner==0,"close releases matched owner into registered empty-hand idle")
 var closed:Dictionary=clerk_registration()
 check(game.world.clerk.position==position and closed.draw_scale==registration.draw_scale and is_equal_approx(closed.body_height,210.0) and closed.head_registered and closed.single_representation and game.world.clerk.z_index==depth and closed.facing_right==facing and closed.rendered_facing_right==facing,"exit restores one registered empty-hand representation with unchanged root, actual source scale, depth and facing")
 check_close_easing("first phone close")
 step();check(game.world.clerk.position==position and input.shop_axis()==0,"held keyboard and stick remain quarantined after close")
 await key(KEY_ESCAPE,false);await key(KEY_D,false);await axis(JOY_AXIS_LEFT_X,0);step(1);await key(KEY_D);step(12)
 check(game.world.clerk.position.x>position.x,"fresh released then pressed movement resumes normally")
 await key(KEY_D,false);step(30)
 # Open through the actual native button using controller confirm.
 await tap(JOY_BUTTON_START);var opener:Control=phone_button();opener.grab_focus();await button(JOY_BUTTON_A)
 check(game._review_phone_is_open() and input.context=="phone","native shop action opens via synthetic controller confirm")
 await button(JOY_BUTTON_A);check(game._review_phone_is_open(),"held opening confirm cannot immediately close phone")
 await button(JOY_BUTTON_A,false)
 var controller_owner:int=game._review_phone_owner
 await tap(JOY_BUTTON_A)
 check(game.review_phone.is_reviews_app_open() and game._review_phone_owner==controller_owner,"fresh controller confirm opens home app without reacquiring")
 await tap(JOY_BUTTON_B)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open() and game._review_phone_owner==controller_owner,"controller Back returns app to home with same owner")
 await button(JOY_BUTTON_B)
 check(not game._review_phone_is_open() and game.page=="hub","controller Back closes only phone")
 await button(JOY_BUTTON_B,false)
 # Fresh keyboard native focused-button opening cannot spill Enter into close.
 input._hub_ui=false;input.synchronize()
 var focused:Control=root.gui_get_focus_owner()
 if focused!=null:focused.release_focus()
 await key(KEY_TAB);await key(KEY_TAB,false)
 check(root.gui_get_focus_owner()!=null,"fresh Tab establishes native shop-menu focus from no selection")
 for unused in 12:
  if root.gui_get_focus_owner()==phone_button():break
  await key(KEY_TAB);await key(KEY_TAB,false)
 check(root.gui_get_focus_owner()==phone_button(),"native Tab reaches phone action without programmatic focus assignment")
 await key(KEY_ENTER);await key(KEY_ENTER,false)
 check(game._review_phone_is_open(),"native keyboard Enter explicitly opens phone")
 await key(KEY_ENTER,true,true);check(game._review_phone_is_open(),"held Enter echo cannot close freshly opened phone")
 await key(KEY_ENTER,false);await key(KEY_ENTER);await key(KEY_ENTER,false)
 check(game.review_phone.is_reviews_app_open(),"fresh keyboard Enter opens app from home focus")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
 check(game._review_phone_is_open() and not game.review_phone.is_reviews_app_open(),"keyboard back leaves app before closing device")
 await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
 # Reading after a completed cargo animation must not leave the device held.
 var old_clerk_state:String=game.world._clerk_state;var old_phase:String=game.world._parcel_phase
 game.world._clerk_state="ready";game.world._parcel_phase="loaded"
 check(await open_phone(),"completed loading permits explicit phone without stealing active transport")
 game._close_review_phone();step(3)
 check(game.world._clerk_motion.debug_snapshot().pose=="idle" and game.world._clerk_state=="free","closing after completed cargo keeps empty-hand neutral on later frames")
 game.world._clerk_state=old_clerk_state;game.world._parcel_phase=old_phase
 # A scrolling historical feed is built only from economy.customer_reviews().
 fake_history();original=ledger();check(await open_phone(),"published historical feed opens through main")
 check(review_entries().size()==30,"view shows bounded thirty published entries")
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
 await key(KEY_D);await axis(JOY_AXIS_LEFT_X,1.0);game._on_focus_exited();game._on_focus_entered();step()
 check(not game._review_phone_is_open() and game.world._review_phone_owner==0 and game.world.clerk.position==position,"focus interruption releases only phone and never restores held velocity")
 await key(KEY_D);await axis(JOY_AXIS_LEFT_X,1.0);step();check(game.world.clerk.position==position,"repeated held input after focus return still requires release")
 await key(KEY_D,false);await axis(JOY_AXIS_LEFT_X,0);step(1)
 # Layout uses the exact existing integer HUD scaling at all target sizes.
 check(await open_phone(),"phone opens for responsive layout proof")
 for size in [Vector2(1280,800),Vector2(1920,1080),Vector2(3840,2160)]:
  var frame:=Rect2(Vector2.ZERO,size);game.review_phone.set_art_frame(frame,Vector2(size.x*.2,size.y*.7));await settle()
  var rect:Rect2=game.review_phone._panel.get_global_rect();var expected:int=clampi(floori(size.y/720.0),1,3)
  check(frame.encloses(rect) and frame.encloses(game.review_phone._device.get_global_rect()) and game.review_phone._ui_scale==expected and rect.size==Vector2(344,500)*expected and game.review_phone._device.get_global_rect().size==Vector2(395,624)*expected,"compact readable phone stays framed at "+str(size))
 game.review_phone.set_art_frame(Rect2(0,0,1280,720),Vector2(1050,500));await settle()
 check(game.review_phone._device.position.x==24 and game.review_phone._panel.position==Vector2(25,56),"phone chooses opposite side from right-side clerk with registered screen")
 await key(KEY_D);game._on_art_frame_changed(game.view_container.display_rect);await settle();step()
 check(game._review_phone_is_open() and input.shop_axis()==0 and game.world.clerk.position==position,"resize retains owner and quarantines held input")
 game._close_review_phone();step();check(game.world.clerk.position==position,"resize/close never restores old movement")
 await key(KEY_D,false);await settle()
 # Repeated lifecycle is bounded after deferred native controls are released.
 await open_phone();game._close_review_phone();await settle(5)
 var nodes:int=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT));var objects:int=int(Performance.get_monitor(Performance.OBJECT_COUNT));var tweens:int=get_processed_tweens().size()
 for unused in 40:
  await open_phone();game._close_review_phone();game._close_review_phone();await settle(2)
 await settle(5)
 check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))<=nodes+1,"forty open/close cycles retain bounded native node count")
 check(int(Performance.get_monitor(Performance.OBJECT_COUNT))<=objects+8,"forty cycles retain bounded object count")
 check(get_processed_tweens().size()<=tweens,"phone lifecycle creates no accumulating tweens")
 check(ledger()==original,"navigation, resize and repeated phone use leave all business/story facts unchanged")
 check(await open_phone(),"phone opens before replacement");game.navigate("workshop");await settle()
 check(not game._review_phone_is_open() and game.world._review_phone_owner==0,"page replacement closes matched owner")
 game.navigate("hub");await settle();await open_phone();var world=game.world;game.remove_child(game.review_phone);game.review_phone.queue_free();await settle()
 check(game._review_phone_owner==0 and world._review_phone_owner==0,"panel teardown releases world ownership and input")
 game.queue_free();await settle(5)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);await settle(4)
 input=game.courier_input;input._hub_ui=true;input.controller_navigation=true;input.synchronize();game._open_review_phone()
 game.queue_free();await settle(5)
 check(not is_instance_valid(game),"root teardown with active controller phone releases children cleanly")
 for filename in ["savegame.json","savegame.backup.json"]:
  var damaged=FileAccess.open("user://"+filename,FileAccess.WRITE);damaged.store_string("{phone-recovery-corruption");damaged.close()
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game);await settle(3)
 check(game.economy.review_load_blocked and game.review_phone==null and game.world==null,"malformed primary and backup never create a phone or world")
 game._action("customer_reviews",null);game._close_review_phone()
 check(not game._open_review_phone() and game._review_phone_owner==0,"late explicit phone actions are null-safe and blocked in recovery-only mode")
 check(FileAccess.get_file_as_string("user://savegame.json")=="{phone-recovery-corruption" and FileAccess.get_file_as_string("user://savegame.backup.json")=="{phone-recovery-corruption","phone attempts preserve both damaged save files")
 game.queue_free();await settle(4)
 print("CUSTOMER_REVIEW_PHONE_INTEGRATION passed=%d failed=%d synthetic_InputEvent=true physical_controller=false native_OS_input=false"%[passed,failed]);quit(1 if failed else 0)
