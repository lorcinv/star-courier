extends SceneTree
class TitleProbe extends "res://scripts/demo_title.gd":
 var launch_requests:Array=[]
 func _launch_game(new_game:bool) -> void:launch_requests.append(new_game)
var capture:AudioEffectCapture
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func peak() -> float:
 var amount:float=0.0
 for frame in capture.get_buffer(capture.get_frames_available()):amount=maxf(amount,maxf(absf(frame.x),absf(frame.y)))
 return amount
func music_count(title) -> int:
 var count:int=0
 for child in title.get_children():
  if child is AudioStreamPlayer and child.name=="TitleMusic" and not child.is_queued_for_deletion():count+=1
 return count
func make_title():
 var title=TitleProbe.new();title.clerk_pose_bootstrap_script=preload("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");root.add_child(title);title._focus_entered();return title
func wait_mix() -> void:await create_timer(.55).timeout
func run() -> void:
 root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
 capture=AudioEffectCapture.new();capture.buffer_length=2.0;AudioServer.add_bus_effect(0,capture)
 var title=make_title();await wait_mix()
 check(title._preview_ready and title.screen=="menu","real title preview opens with injected approved actor factory")
 check(music_count(title)==1 and title._music_index==title.MENU_MUSIC_INDEX and title._prologue_music.stream==title.MENU_MUSIC,"menu owns one original workshop music stream")
 check(title._prologue_music.playing and peak()>0.001,"default-volume title emits nonzero mixer output")
 var player_id:int=title._prologue_music.get_instance_id()
 title._show_settings();await wait_mix()
 check(title._prologue_music.get_instance_id()==player_id and not title._prologue_music.stream_paused,"menu settings retains same active music owner")
 title._set_setting("volume",0.0);title._test_title_sound();await create_timer(.1).timeout;capture.clear_buffer();await wait_mix()
 check(title.settings.volume==0.0 and title._prologue_music.stream_paused and peak()==0.0 and "0" in title._audio_test_status,"mute stays exactly silent and sound test explains zero volume")
 title._set_setting("volume",.55);await wait_mix();check(peak()>0.001,"unmuting title resumes same loop")
 title._test_title_sound();check("Dummy" in title._audio_test_status,"headless test identifies Dummy output instead of claiming audible sound")
 title._return_from_settings();title._request_new_game();await wait_mix()
 check(title.screen=="prologue" and music_count(title)==1 and title._music_index==0 and title._prologue_music.get_instance_id()==player_id,"menu-to-prologue switches one player through silence")
 title._advance_prologue();await wait_mix();check(music_count(title)==1 and title._music_index==1 and title._prologue_music.get_instance_id()==player_id,"prologue beat transition cannot overlap music players")
 title._show_settings();await create_timer(.1).timeout;capture.clear_buffer();await wait_mix()
 check(title._prologue_music.stream_paused and peak()==0.0,"prologue settings keeps its story cue paused")
 title._return_from_settings();await wait_mix();check(not title._prologue_music.stream_paused and title._music_index==1,"return from settings resumes same prologue beat")
 title._cancel_prologue();await wait_mix();check(title.screen=="menu" and music_count(title)==1 and title._music_index==title.MENU_MUSIC_INDEX,"cancel prologue restores one menu loop")
 title._focus_exited();await create_timer(.1).timeout;capture.clear_buffer();await wait_mix();check(peak()==0.0 and title._prologue_music.stream_paused,"title focus loss pauses output")
 title._focus_entered();await wait_mix();check(peak()>0.001,"title focus return resumes output")
 title._prologue_accepted=true;title._begin_game(false);await wait_mix()
 check(title.launch_requests==[false] and title._prologue_music==null and title._title_test_sound==null and music_count(title)==0,"title releases music and test sound before game construction")
 title.free();await create_timer(.15).timeout
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string('{"settings":{"volume":0.0}}');file.close()
 var before:PackedByteArray=FileAccess.get_file_as_bytes("user://savegame.json")
 title=make_title();await create_timer(.1).timeout;capture.clear_buffer();await wait_mix()
 check(title.settings.volume==0.0 and peak()==0.0 and FileAccess.get_file_as_bytes("user://savegame.json")==before,"old saved zero volume is honored without any title write")
 title.free();AudioServer.remove_bus_effect(0,0);capture=null;await create_timer(.15).timeout
 print("DEV03_TITLE_AUDIO_DELTA passed=%d failed=%d driver=%s mixer_only=true"%[passed,failed,AudioServer.get_driver_name()]);quit(1 if failed else 0)
