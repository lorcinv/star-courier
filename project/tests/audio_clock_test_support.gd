extends RefCounted
## Test-only completion conditions. Wall clock is a timeout, not audio evidence.
static func wait_frames(tree:SceneTree,capture:AudioEffectCapture,seconds:float,bound_seconds:float=2.0) -> Dictionary:
 var rate:float=AudioServer.get_mix_rate()
 var target:int=maxi(1,ceili(seconds*rate))
 var initial:int=capture.get_pushed_frames()
 var started:int=Time.get_ticks_usec()
 var deadline:int=started+int(bound_seconds*1000000.0)
 while capture.get_pushed_frames()-initial<target and Time.get_ticks_usec()<deadline:
  await tree.process_frame
 var observed:int=capture.get_pushed_frames()-initial
 return {"ok":observed>=target,"target_frames":target,"observed_frames":observed,"available_frames":capture.get_frames_available(),"discarded_frames":capture.get_discarded_frames(),"wall_usec":Time.get_ticks_usec()-started,"mix_rate":rate,"bound_seconds":bound_seconds}

static func alive(refs:Array) -> Array:
 var result:Array=[]
 for reference:WeakRef in refs:
  var value:Variant=reference.get_ref()
  if is_instance_valid(value):result.append({"id":value.get_instance_id(),"class":value.get_class(),"resource_path":value.resource_path if value is Resource else ""})
 return result

static func wait_released(tree:SceneTree,refs:Array,bound_seconds:float=2.0) -> Dictionary:
 var started:int=Time.get_ticks_usec()
 var deadline:int=started+int(bound_seconds*1000000.0)
 var remaining:Array=alive(refs)
 while not remaining.is_empty() and Time.get_ticks_usec()<deadline:
  await tree.process_frame
  remaining=alive(refs)
 return {"ok":remaining.is_empty(),"remaining":remaining,"wall_usec":Time.get_ticks_usec()-started,"tracked_refs":refs.size(),"bound_seconds":bound_seconds}

static func watch_player(player:AudioStreamPlayer,refs:Array) -> void:
 if not is_instance_valid(player):return
 refs.append(weakref(player))
 if player.has_stream_playback():refs.append(weakref(player.get_stream_playback()))

static func watch_streams(streams:Array,refs:Array) -> void:
 # Keep temporary strong stream references inside this non-awaiting helper.
 for stream:AudioStream in streams:refs.append(weakref(stream))
