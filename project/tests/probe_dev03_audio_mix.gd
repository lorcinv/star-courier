extends SceneTree
const Main=preload("res://scripts/main.gd")
var capture:AudioEffectCapture
var app
func _initialize() -> void:run.call_deferred()
func stats(label:String) -> void:
 var frames:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
 var peak:float=0.0;var sum_squared:float=0.0
 for frame in frames:
  peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)));sum_squared+=frame.x*frame.x+frame.y*frame.y
 var rms:float=sqrt(sum_squared/maxi(1,frames.size()*2))
 print("AUDIO_MIX ",JSON.stringify({"label":label,"frames":frames.size(),"peak":peak,"rms":rms,"music_playing":app.music.playing,"music_paused":app.music.stream_paused,"music_process_mode":app.music.process_mode,"parent_process_mode":app.process_mode,"volume_db":app.music.volume_db,"driver":AudioServer.get_driver_name(),"display":DisplayServer.get_name()}))
 var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.stereo=true;wav.mix_rate=int(AudioServer.get_mix_rate())
 var pcm:=PackedByteArray();pcm.resize(frames.size()*4)
 for i in frames.size():pcm.encode_s16(i*4,clampi(roundi(frames[i].x*32767),-32768,32767));pcm.encode_s16(i*4+2,clampi(roundi(frames[i].y*32767),-32768,32767))
 wav.data=pcm;wav.save_to_wav("user://"+label+".wav")
func run() -> void:
 root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
 capture=AudioEffectCapture.new();capture.buffer_length=2.0;AudioServer.add_bus_effect(0,capture)
 app=Main.new();app.clerk_pose_bootstrap_script=preload("res://scripts/clerk_runtime_bootstrap_observed_v4.gd");app.process_mode=Node.PROCESS_MODE_DISABLED;app.entry_defer_controls=true
 root.add_child(app)
 if app.economy.review_load_blocked:push_error(app.economy.load_notice);quit(2);return
 await create_timer(.4).timeout;stats("title_deferred")
 app.finish_title_entry();app._pending_story.clear();if app._dialogue_is_open():app.dialogue.cancel(false)
 await create_timer(.4).timeout;stats("main_handoff")
 app.music.stop();capture.clear_buffer();app._sound("delivery_success")
 await create_timer(.4).timeout;stats("sfx")
 app.music.stop();app.sfx.stop();app.free();AudioServer.remove_bus_effect(0,0);quit()
