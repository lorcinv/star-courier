extends SceneTree
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
class AudioController extends "res://scripts/main.gd":
 func _ready() -> void:pass
 func _process(_delta:float) -> void:pass
var capture:AudioEffectCapture
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func sample() -> Dictionary:
 var frames:PackedVector2Array=capture.get_buffer(capture.get_frames_available());var peak:float=0.0
 for frame in frames:peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
 return {"frames":frames.size(),"peak":peak}
func wait_audio(seconds:float,label:String) -> void:
 var result:Dictionary=await AudioClock.wait_frames(self,capture,seconds)
 print("AUDIO_CLOCK_V2 ",label," ",JSON.stringify(result))
 if not result.ok:failed+=1;push_error("FAIL bounded audio-frame wait: "+label)

func run() -> void:
 capture=AudioEffectCapture.new();capture.buffer_length=2.0;AudioServer.add_bus_effect(0,capture)
 var app=AudioController.new();app.process_mode=Node.PROCESS_MODE_DISABLED;app.entry_defer_controls=true;root.add_child(app);app._ensure_audio_players();app._play_music(false)
 await wait_audio(.25,"quarter_second_capture")
 var mix:Dictionary=sample()
 check(mix.frames>0 and mix.peak==0.0 and not app.music.playing,"no gameplay music before title handoff")
 app.entry_defer_controls=false;app.process_mode=Node.PROCESS_MODE_INHERIT;app._play_music(false)
 await wait_audio(.25,"quarter_second_capture");mix=sample()
 check(app.music.playing and not app.music.stream_paused and mix.peak>0.001,"workshop loop mixes nonzero at saved default volume")
 check(app.music.process_mode==Node.PROCESS_MODE_ALWAYS and app.sfx.process_mode==Node.PROCESS_MODE_ALWAYS,"audio ownership independent of disabled gameplay owner")
 app._play_music(true);capture.clear_buffer();await wait_audio(.25,"quarter_second_capture");mix=sample()
 check(app.music.stream==app.MUSIC_TRACKS.flight and mix.peak>0.001,"flight loop switch mixes nonzero")
 check(app.music.stream.loop,"music loops continuously")
 app.music.stop()
 for name in app.SOUND_EFFECTS:
  app.sfx.stop();await wait_audio(.08,"previous_sfx_stop");capture.clear_buffer();app._sound(name);await wait_audio(.2,"sfx_or_mute_capture");mix=sample()
  check(mix.frames>0 and mix.peak>0.001,"nonzero SFX: "+str(name))
 app.settings.volume=0.0;app._apply_audio_volume();app._play_music(false);app._sound("delivery_success")
 await wait_audio(.1,"mute_stop_drain");capture.clear_buffer();await wait_audio(.2,"sfx_or_mute_capture");mix=sample()
 check(mix.frames>0 and mix.peak==0.0 and not app.sfx.playing,"volume zero produces exactly silent mix and no SFX playback")
 app.settings.volume=.55;app._apply_audio_volume();app._play_music(false);capture.clear_buffer();await wait_audio(.25,"quarter_second_capture");mix=sample()
 check(mix.peak>0.001 and not app.music.stream_paused,"unmuting restores workshop music")
 app.settings.volume="invalid";check(app._master_volume()==.55,"invalid legacy volume has safe default")
 var releases:Array=[];AudioClock.watch_player(app.music,releases);AudioClock.watch_player(app.sfx,releases)
 app.music.stop();app.sfx.stop();app.free();AudioServer.remove_bus_effect(0,0);capture=null
 var released:Dictionary=await AudioClock.wait_released(self,releases)
 print("AUDIO_RELEASE_V2 ",JSON.stringify(released))
 check(released.ok,"audio players and their playback references release before test quit")
 print("DEV03_AUDIO_PLAYBACK passed=%d failed=%d driver=%s display=%s mixer_only=true"%[passed,failed,AudioServer.get_driver_name(),DisplayServer.get_name()]);quit(1 if failed else 0)
