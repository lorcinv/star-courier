extends SceneTree
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
## Synthetic, presentation-only probe. Run only in a NEW fictional /tmp profile.
## No Main is constructed: the original test_demo_title_lifecycle.gd remains
## required separately for real guarded save/Continue and clerk-entry behavior.
class TitleProbe extends "res://scripts/demo_title.gd":
 var launch_requests:Array[bool]=[]
 var release_watch:Array=[]
 func _launch_game(new_game:bool) -> void:
  launch_requests.append(new_game)
 func _dispose_prologue_music(generation:int,after:Callable) -> void:
  AudioClock.watch_player(_prologue_music,release_watch)
  super._dispose_prologue_music(generation,after)

const FACTORY:String="res://scripts/clerk_runtime_bootstrap_observed_v4.gd"
var title:TitleProbe
var passed:int=0
var failed:int=0

func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func settle(count:int=3) -> void:
 for unused in count:await process_frame
func bytes() -> Array:
 var result:Array=[]
 for slot in ["savegame.json","savegame.backup.json"]:
  result.append(FileAccess.get_file_as_bytes("user://"+slot) if FileAccess.file_exists("user://"+slot) else null)
 return result
func live_music_count() -> int:
 var count:int=0
 for child in title.get_children():
  if child is AudioStreamPlayer and child.name=="TitleMusic" and not child.is_queued_for_deletion():count+=1
 return count
func open_title() -> void:
 title=TitleProbe.new();title.clerk_pose_bootstrap_script=load(FACTORY)
 root.add_child(title);await settle();title._focus_entered();await settle()
func close_title() -> void:
 # Only ephemeral owned objects must disappear. The static preloaded menu
 # AudioStream remains valid while its script/constant is loaded.
 AudioClock.watch_player(title._prologue_music,title.release_watch)
 AudioClock.watch_streams(title._prologue_streams,title.release_watch)
 var releases:Array=title.release_watch.duplicate()
 root.remove_child(title);title.free();await settle()
 var released:Dictionary=await AudioClock.wait_released(self,releases)
 print("PROLOGUE_RELEASE_V2 ",JSON.stringify(released))
 check(released.ok,"title players, dynamic prologue streams and stopped playbacks release before next phase")

func run() -> void:
 if OS.get_environment("STAR_COURIER_TITLE_TEST")!="1" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/"):
  printerr("Requires STAR_COURIER_TITLE_TEST=1 and a NEW /tmp XDG_DATA_HOME");quit(2);return
 if FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refuse non-empty profile. Supply a NEW fictional profile.");quit(2);return
 await open_title()
 check(title._preview_ready,"approved live title preview is configured")
 check(title._presentation_error.is_empty(),"all real title, prologue and audio assets resolve")
 check(title._prologue_textures.size()==3 and title._prologue_streams.size()==3,"exactly three illustrated/music beats load")
 if not title._preview_ready or not title._presentation_error.is_empty():
  await close_title();finish();return
 check(title.game==null and bytes()==[null,null],"presentation asset loading constructs no Main and writes no save")
 check(title._prologue_music!=null and live_music_count()==1 and not title._prologue_layer.visible,"title menu owns one music player and hides the prologue")
 var logo:TextureRect=title.title_stage.get_node("StarCourierPixelLogo")
 var chinese:TextureRect=title.title_stage.get_node("XingjiKuaidiPixelLogo")
 check(logo.texture.get_size()==Vector2(288,160) and chinese.texture.get_size()==Vector2(208,80),"both title wordmarks use delivered native raster sizes")
 check(title.get_window().title=="星际快递" and title.title_stage.get_node("DemoMark").text=="DEMO","only small DEMO mark remains; window title has no development phrase")
 root.size=Vector2i(1920,1080);await settle();title._layout();await settle()
 check(title.title_stage.scale==Vector2.ONE and title.title_stage.size==Vector2(1920,1080) and title.title_stage.position==Vector2.ZERO,"1080 title fills frame with native unscaled Control canvas")
 check(logo.size==Vector2(864,480) and chinese.size==Vector2(624,240),"wordmarks are exact3x at1080")
 title._set_setting("reduced_motion",true)
 title._request_new_game();await create_timer(.55).timeout
 check(title.screen=="prologue" and title.game==null and bytes()==[null,null],"new game starts presentation before any Main/reset")
 check(title._prologue_image.texture==title._prologue_textures[0] and title._prologue_image.modulate.a==1.0 and title._prologue_transition==null,"reduced motion commits scene immediately without an animation")
 check(title._prologue_image.size==Vector2(1920,1080) and not logo.visible and not chinese.visible,"full-frame640x360 art renders3x without title wordmarks over the scene")
 check(title.menu is HBoxContainer and title.menu.get_child_count()==4,"four accessible horizontal story controls include settings")
 check(live_music_count()==1 and title._prologue_music.stream==title._prologue_streams[0],"one owned player starts scene1 music")
 var player_id:int=title._prologue_music.get_instance_id()
 title._show_prologue(false);await settle()
 check(live_music_count()==1 and title._prologue_music.get_instance_id()==player_id,"rebuilding current scene reuses music player")
 title._advance_prologue();await create_timer(.55).timeout
 check(title._prologue_index==1 and title._prologue_image.texture==title._prologue_textures[1],"scene advance replaces art with beat2")
 check(live_music_count()==1 and title._prologue_music.get_instance_id()==player_id and title._prologue_music.stream==title._prologue_streams[1],"section change fades through one reusable player")
 title._show_settings();await settle()
 check(title.screen=="settings" and title._prologue_music.stream_paused,"story settings pauses music without losing its player")
 title._set_setting("volume",0.0);title._return_from_settings();await settle()
 check(title.screen=="prologue" and title._prologue_index==1 and title._prologue_music.stream_paused and title._prologue_music.volume_db<=-79.0,"return keeps beat2 and respects muted global volume")
 title._set_setting("volume",.25);title._set_music_gain(1.0)
 check(is_equal_approx(db_to_linear(title._prologue_music.volume_db),.25*.708),"global volume and cue safety gain apply to owned audio")
 title._focus_exited();await settle()
 check(title._prologue_music.stream_paused,"focus loss pauses story audio")
 title._focus_entered();await settle()
 check(not title._prologue_music.stream_paused and title._prologue_index==1,"focus return resumes same story beat")
 title._cancel_prologue();await create_timer(.55).timeout
 check(title.screen=="menu" and title._prologue_music!=null and title._music_index==title.MENU_MUSIC_INDEX and live_music_count()==1 and bytes()==[null,null],"cancel returns to one menu loop and preserves empty profile")
 title._request_new_game();await settle();title._finish_prologue();title._finish_prologue();await settle()
 check(title.launch_requests==[true] and title._prologue_music==null,"repeated skip requests launch once after audio cleanup")
 check(bytes()==[null,null] and title.game==null,"probe intercepts launch and never writes game state")
 await close_title()
 # Only this NEW fictional profile gets an explicit corrupt save marker.
 var file:=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string("{fictional presentation probe");file.close()
 var before:Array=bytes();await open_title();title._continue_game();await settle()
 check(title.launch_requests==[false] and title.screen!="prologue" and title._prologue_music==null,"Continue takes existing-save launch route without prologue/audio")
 check(bytes()==before,"Continue presentation route leaves fixture bytes unchanged")
 await close_title();finish()

func finish() -> void:
 print("DEMO_PROLOGUE_PRESENTATION_V2 passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
