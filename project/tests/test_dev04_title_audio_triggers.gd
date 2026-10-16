extends SceneTree
## Real default title scene, real input pipeline, real Main/save handoff.
## Fresh fictional profile only. Dummy mixer/synthetic events are not audible
## Windows/device or physical-keyboard/gamepad acceptance.
const TitleScene=preload("res://scenes/demo_title.tscn")
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
var title
var clock_capture:AudioEffectCapture
var music_capture:AudioEffectCapture
var ui_capture:AudioEffectCapture
var passed:int=0
var failed:int=0
var music_bus:String="Dev04TitleMusicProbe"
var ui_bus:String="Dev04TitleUIProbe"

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func settle(count:int=3) -> void:
 for unused in count:await process_frame
func add_capture(bus:String) -> AudioEffectCapture:
 var index:int=0
 if bus!="Master":
  index=AudioServer.bus_count;AudioServer.add_bus();AudioServer.set_bus_name(index,bus);AudioServer.set_bus_send(index,"Master")
 var effect:=AudioEffectCapture.new();effect.buffer_length=2.0;AudioServer.add_bus_effect(index,effect)
 return effect
func sample(capture:AudioEffectCapture,label:String) -> Dictionary:
 var frames:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
 var peak:float=0.0
 for frame in frames:peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
 var result:Dictionary={"label":label,"frames":frames.size(),"peak":peak,"driver":AudioServer.get_driver_name(),"display":DisplayServer.get_name(),"mixer_only":true}
 print("DEV04_AUDIO_SAMPLE ",JSON.stringify(result));return result
func wait_audio(seconds:float,label:String) -> void:
 # This Master capture is a frame clock, not the measured music/UI buffer.
 # Clerk entry can fill it while no observer is waiting. Release that backlog
 # before waiting for NEW pushed frames; a full ring records only discards.
 print("DEV04_AUDIO_CLOCK_BACKLOG ",label," ",JSON.stringify({"available_frames":clock_capture.get_frames_available(),"pushed_frames":clock_capture.get_pushed_frames(),"discarded_frames":clock_capture.get_discarded_frames()}))
 clock_capture.clear_buffer()
 var result:Dictionary=await AudioClock.wait_frames(self,clock_capture,seconds)
 print("DEV04_AUDIO_CLOCK ",label," ",JSON.stringify(result))
 check(result.ok,"audio-frame observation completes: "+label)
 clock_capture.clear_buffer()
func route_title_player(child:Node) -> void:
 if child is AudioStreamPlayer:
  if child.name=="TitleMusic":child.bus=music_bus
  elif child.name in ["TitleUISound","TitleSoundTest"]:child.bus=ui_bus
func music_count() -> int:
 var count:int=0
 for child in title.get_children():
  if child is AudioStreamPlayer and child.name=="TitleMusic" and not child.is_queued_for_deletion():count+=1
 return count
func ui_count() -> int:
 var count:int=0
 for child in title.get_children():
  if child is AudioStreamPlayer and child.name in ["TitleUISound","TitleSoundTest"] and not child.is_queued_for_deletion():count+=1
 return count
func open_title() -> void:
 title=TitleScene.instantiate();title.child_entered_tree.connect(route_title_player)
 root.add_child(title);await settle()
 # Headless cannot have hardware window focus. This explicitly supplies the
 # same callback, without pretending a desktop window received focus.
 if DisplayServer.get_name()=="headless":title._focus_entered()
 await settle()
 check(title._preview_ready and title._presentation_error.is_empty(),"actual configured title scene resolves live preview and all presentation assets")
func watch_players() -> Array:
 var refs:Array=[]
 for player in title.find_children("*","AudioStreamPlayer",true,false):AudioClock.watch_player(player,refs)
 AudioClock.watch_streams(title._prologue_streams,refs)
 return refs
func close_title() -> void:
 var refs:Array=watch_players();root.remove_child(title);title.free();title=null
 var released:Dictionary=await AudioClock.wait_released(self,refs)
 print("DEV04_AUDIO_RELEASE ",JSON.stringify(released))
 check(released.ok,"all dynamic title/Main audio players and playback references release")
func emit_key(code:int,pressed:bool) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
 Input.parse_input_event(event)
func key(code:int,pressed:bool) -> void:emit_key(code,pressed);await settle(2)
func tap(code:int) -> void:await key(code,true);await key(code,false)
func joy(index:int,pressed:bool) -> void:
 var event:=InputEventJoypadButton.new();event.device=0;event.button_index=index;event.pressed=pressed
 Input.parse_input_event(event);await settle(2)
func mouse_button(id:String,pressed:bool) -> void:
 var point:Vector2=title.menu.get_node(id).get_global_rect().get_center()
 var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
 Input.parse_input_event(event);await settle(2)
func activate(id:String) -> void:
 title._focus_control(title.menu.get_node(id),title.screen);await settle()
 await tap(KEY_ENTER)
func wait_music(index:int,label:String) -> void:
 var deadline:int=Time.get_ticks_msec()+3000
 while (not is_instance_valid(title._prologue_music) or title._music_index!=index or title._music_gain<.999) and Time.get_ticks_msec()<deadline:await process_frame
 check(is_instance_valid(title._prologue_music) and title._music_index==index and title._music_gain>=.999,"music transition completes: "+label)
 await wait_audio(.08,label+" drain");music_capture.clear_buffer()
 await wait_audio(.22,label+" capture")
 var mixed:Dictionary=sample(music_capture,label)
 check(music_count()==1 and title._prologue_music.playing and not title._prologue_music.stream_paused and mixed.peak>.001,"one active nonzero music owner: "+label)
 print("DEV04_TITLE_STATE ",JSON.stringify({"screen":title.screen,"beat":title._prologue_index,"music_index":title._music_index,"focused":title._window_focused,"volume":title.settings.volume,"gain":title._music_gain,"stream":title._prologue_music.stream.resource_path}))
func silent_music(label:String) -> void:
 await wait_audio(.08,label+" drain");music_capture.clear_buffer()
 await wait_audio(.22,label+" capture")
 var mixed:Dictionary=sample(music_capture,label)
 check(title._prologue_music.stream_paused and mixed.peak==0.0,label+" is exactly silent")
func wait_main(label:String) -> bool:
 var deadline:int=Time.get_ticks_msec()+15000
 while title.screen!="game" and not title._opening_failed and Time.get_ticks_msec()<deadline:await process_frame
 var ready:bool=title.screen=="game" and is_instance_valid(title.game)
 check(ready,"real Main handoff completes: "+label)
 if not ready:return false
 check(title._prologue_music==null and title._title_ui_sound==null and title._title_test_sound==null and music_count()==0 and ui_count()==0,"title audio owners are gone before active Main: "+label)
 check(not title.game.entry_defer_controls and title.game.music.playing,"Main starts its own music after control handoff: "+label)
 title.game.music.bus=music_bus
 await wait_audio(.08,label+" drain");music_capture.clear_buffer();await wait_audio(.22,label+" capture")
 check(sample(music_capture,label).peak>.001,"Main music mixes nonzero after "+label)
 return true
func run() -> void:
 if OS.get_environment("STAR_COURIER_TITLE_TEST")!="1" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):
  printerr("Requires STAR_COURIER_TITLE_TEST=1 and a NEW /tmp XDG_DATA_HOME");quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refuse non-empty profile");quit(2);return
 root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
 clock_capture=add_capture("Master");music_capture=add_capture(music_bus);ui_capture=add_capture(ui_bus)
 await open_title();await wait_music(title.MENU_MUSIC_INDEX,"default menu")
 check(title._title_ui_sound==null,"initial programmatic focus does not sound")
 await tap(KEY_DOWN)
 check(root.gui_get_focus_owner()==title.settings_button and is_instance_valid(title._title_ui_sound),"native keyboard navigation skips disabled Continue and creates UI feedback")
 if not is_instance_valid(title._title_ui_sound):await close_title();finish();return
 var ui_id:int=title._title_ui_sound.get_instance_id()
 check(title._title_ui_sound.stream==title.TITLE_UI_SOUND and title._title_ui_sound.pitch_scale<1.0,"navigation uses the preloaded short selection cue")
 await wait_audio(.2,"navigation capture")
 check(sample(ui_capture,"keyboard navigation").peak>.001,"keyboard navigation mixes nonzero UI sound")
 ui_capture.clear_buffer();await joy(JOY_BUTTON_DPAD_UP,true);await joy(JOY_BUTTON_DPAD_UP,false)
 check(root.gui_get_focus_owner()==title.new_button,"native controller D-pad navigates real title focus")
 await wait_audio(.2,"controller capture")
 check(sample(ui_capture,"controller navigation").peak>.001 and title._title_ui_sound.get_instance_id()==ui_id and ui_count()==1,"controller feedback reuses one UI player")
 await tap(KEY_DOWN);await wait_audio(.2,"old cue drain");ui_capture.clear_buffer()
 await key(KEY_ENTER,true)
 check(is_instance_valid(title._title_ui_sound) and title._title_ui_sound.pitch_scale==1.0,"native accept button-down triggers confirmation cue before action")
 await wait_audio(.18,"button capture")
 check(sample(ui_capture,"button activation").peak>.001,"button activation mixes nonzero UI sound")
 await key(KEY_ENTER,false);check(title.screen=="settings","native accept executes actual Settings action")
 ui_capture.clear_buffer();await mouse_button("MotionBlur",true);await wait_audio(.18,"mouse button capture")
 check(sample(ui_capture,"mouse button").peak>.001,"native mouse button-down mixes selection cue")
 await mouse_button("MotionBlur",false)
 check(not title.settings.motion_blur,"native mouse release executes actual setting toggle")
 await activate("MotionBlur") # Restore default before the real prologue route.
 await activate("TestSound")
 check(title._title_ui_sound==null and is_instance_valid(title._title_test_sound) and ui_count()==1,"Test Sound replaces UI feedback without stacking SFX players")
 await tap(KEY_DOWN)
 check(title._title_test_sound==null and is_instance_valid(title._title_ui_sound) and ui_count()==1,"next navigation retires Test Sound and owns a single short-SFX player")
 title._set_setting("volume",0.0);await wait_audio(.08,"mute drain");ui_capture.clear_buffer()
 await activate("ReducedMotion");await wait_audio(.22,"muted button capture")
 check(sample(ui_capture,"muted button").peak==0.0 and not title._title_ui_sound.playing,"mute stops existing UI sound and suppresses native button playback")
 title._set_setting("reduced_motion",false)
 title._focus_exited();check(title._title_ui_sound==null,"focus loss disposes short UI audio")
 title._play_title_ui_sound();check(title._title_ui_sound==null,"unfocused zero-volume request cannot allocate UI audio")
 title._set_setting("volume",.55);title._play_title_ui_sound();check(title._title_ui_sound==null,"unfocused nonzero-volume request cannot allocate UI audio")
 title._focus_entered();await settle();check(title._title_ui_sound==null,"focus recovery stays quiet")
 await activate("SettingsBack");await wait_music(title.MENU_MUSIC_INDEX,"settings return")
 check(not FileAccess.file_exists("user://savegame.json"),"menu/settings interaction writes no fictional save")
 await activate("NewGame");await wait_music(0,"prologue beat 1")
 var music_id:int=title._prologue_music.get_instance_id()
 check(title.screen=="prologue" and title.game==null,"real New Game enters prologue before constructing Main")
 await activate("PrologueNext");await wait_music(1,"prologue beat 2")
 await activate("PrologueSettings");await silent_music("prologue settings")
 title._set_setting("volume",0.0);await activate("SettingsBack");await silent_music("muted prologue return")
 check(title._prologue_index==1,"settings return preserves current prologue beat")
 title._set_setting("volume",.55);await wait_music(1,"unmuted prologue beat 2")
 title._focus_exited();await silent_music("prologue focus loss")
 title._focus_entered();await wait_music(1,"prologue focus regain")
 await activate("PrologueNext");await wait_music(2,"prologue beat 3")
 check(title._prologue_music.get_instance_id()==music_id,"all prologue beats and interruptions reuse one music owner")
 var skip:bool="--skip-route" in OS.get_cmdline_user_args()
 await activate("PrologueSkip" if skip else "PrologueNext")
 if not await wait_main("skip" if skip else "final continue"):
  await close_title();finish();return
 check(FileAccess.file_exists("user://savegame.json"),"new-game normal Main commit creates fictional save")
 await close_title();await open_title();await wait_music(title.MENU_MUSIC_INDEX,"saved title")
 check(not title.continue_button.disabled,"normal saved title enables Continue")
 await activate("Continue")
 check(title.screen!="prologue","Continue bypasses prologue")
 await wait_main("saved Continue");await close_title();finish()
func finish() -> void:
 AudioServer.remove_bus(AudioServer.get_bus_index(ui_bus));AudioServer.remove_bus(AudioServer.get_bus_index(music_bus))
 AudioServer.remove_bus_effect(0,0)
 print("DEV04_TITLE_AUDIO_TRIGGERS passed=%d failed=%d driver=%s display=%s mixer_only=true synthetic_input=true windows_audibility_verified=false"%[passed,failed,AudioServer.get_driver_name(),DisplayServer.get_name()])
 quit(1 if failed else 0)
