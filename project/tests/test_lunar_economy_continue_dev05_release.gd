extends "res://tests/test_lunar_economy_continue_v2.gd"
## Exact parent journey and assertions, with completion-based test teardown.
## Three unpaced process frames are not proof the audio mixer released playback.
## No stop/flush behavior is added to production or to this observer.
const AudioClock=preload("res://tests/audio_clock_test_support.gd")
func finish() -> void:
 var refs:Array=[]
 if is_instance_valid(title):
  for player in title.find_children("*","AudioStreamPlayer",true,false):AudioClock.watch_player(player,refs)
  root.remove_child(title);title.free();title=null
 await frames()
 var after_three:Array=AudioClock.alive(refs)
 var released:Dictionary=await AudioClock.wait_released(self,refs)
 print("DEV05_AUDIO_RELEASE ",JSON.stringify({"after_three_frames":after_three,"completion":released}))
 check(bool(released.ok),"all observed player/playback refs actually release before test process exit")
 print("LUNAR_ECONOMY_CONTINUE_DEV05_RELEASE passed=",passed," failed=",failed)
 quit(1 if failed else 0)
