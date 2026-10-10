extends SceneTree
## Native QA entry only. Loads the unmodified main scene and records its actual
## Master mixer. F8 starts/stops the recording; all gameplay still uses OS input.
## No fixed FPS, injected dialogue, game-state edits or synthesized replacement mix.
class AudioTap extends Node:
 var output:String="res://docs/qa/v5/dialogue/integrated-audio.wav"
 var effect:AudioEffectRecord
 var effect_index:int=-1
 var started_usec:int=0
 var active:bool=false
 var recorded:bool=false
 func _ready() -> void:
  process_mode=Node.PROCESS_MODE_ALWAYS
  for arg in OS.get_cmdline_user_args():
   if arg.begins_with("--qa-audio-output="):output=arg.trim_prefix("--qa-audio-output=")
  print("QA_AUDIO_READY ",JSON.stringify({"key":"F8","output":output,"method":"Godot Master bus PCM, normal real-time execution"}))
 func _input(event:InputEvent) -> void:
  if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8:
   if active:finish()
   elif not recorded:start()
   get_viewport().set_input_as_handled()
 func start() -> void:
  if active or recorded:return
  effect=AudioEffectRecord.new();effect.format=AudioStreamWAV.FORMAT_16_BITS
  effect_index=AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,effect)
  started_usec=Time.get_ticks_usec();active=true;effect.set_recording_active(true)
  print("QA_AUDIO_START ",JSON.stringify({"unix_seconds":Time.get_unix_time_from_system(),"engine_usec":started_usec}))
 func finish() -> void:
  if not active:return
  active=false;recorded=true;effect.set_recording_active(false)
  var recording:AudioStreamWAV=effect.get_recording()
  var absolute:String=ProjectSettings.globalize_path(output)
  DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
  var result:int=recording.save_to_wav(absolute)
  print("QA_AUDIO_SAVED ",JSON.stringify({"unix_seconds":Time.get_unix_time_from_system(),"output":absolute,"error":result,"samples_bytes":recording.data.size(),"rate":recording.mix_rate,"stereo":recording.stereo,"elapsed_wall_seconds":(Time.get_ticks_usec()-started_usec)/1000000.0}))
  if effect_index>=0:AudioServer.remove_bus_effect(0,effect_index)
  effect_index=-1;effect=null
 func _process(_delta:float) -> void:
  if active and Time.get_ticks_usec()-started_usec>=90000000:finish()
 func _exit_tree() -> void:finish()
func _initialize() -> void:
 var tap=AudioTap.new();tap.name="NativeQAAudioTap";root.add_child.call_deferred(tap)
 var game=load("res://scenes/main.tscn").instantiate();root.add_child.call_deferred(game)
