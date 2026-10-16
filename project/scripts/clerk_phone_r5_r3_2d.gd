extends "res://scripts/clerk_tablet_r5_r3_2d.gd"
## Explicit review-phone presentation owner. Generic frozen contexts still use
## the inherited exact freeze. This owner never writes actor/root positions.
var _phone_owner:int=0
var _phone_phase:String="none"
var _phone_elapsed:float=0.0
var _phone_last_frame:float=-1.0
var _phone_completed_seconds:float=-1.0

func begin_review_phone(owner:int) -> bool:
 if owner==0 or not _rig_active or _model==null:return false
 _model.cancel_presentation_turn("phone_owner_acquired");_facing_right=_model.facing_right
 _phone_owner=owner;_phone_elapsed=0.0;_phone_last_frame=-1.0;_phone_completed_seconds=-1.0
 _phone_phase="raise" if _model.settled and _model.feet.far.planted and _model.feet.near.planted else "settle"
 _tablet_target=1.0 if _phone_phase=="raise" else 0.0
 return true

func end_review_phone(owner:int) -> void:
 if owner!=_phone_owner:return
 _model.cancel_presentation_turn("phone_owner_released")
 _phone_owner=0;_phone_phase="none";_phone_last_frame=-1.0
 # Matched presentation ownership ended. Publish its idle/lowering intent
 # even when same-clock observation deduplication or a frozen context prevents
 # another physical sample. No clock, model, contact or transform is advanced.
 _tablet_target=0.0;_pose="idle";_player_state="idle"
 var sprite:Sprite2D=_node()
 if is_instance_valid(sprite):sprite.set_meta("pose","idle")

func advance_review_phone(owner:int,elapsed:float,frame_clock:float) -> bool:
 if owner==0 or owner!=_phone_owner or not is_finite(elapsed) or elapsed<=0.0:return false
 if elapsed>0.25:
  _issue("phone_owned_interval_over250ms");return false
 if _review_phone_clock_duplicate(frame_clock):return true
 if not _rig_active or not is_instance_valid(_node()) or not _node().is_visible_in_tree():return false
 _phone_last_frame=frame_clock
 # Clear only this owner's freeze bookkeeping at the same pose clock. The
 # explicit finite settle below then consumes every accepted <=120 Hz slice.
 if _phone_phase=="settle":
  if not _model.update("stop",_rig_distance,_node().position,_facing_right,_observed_clock,0.0,true,_owner_reduced):return false
  var remaining:float=elapsed
  while remaining>0.000001 and _phone_phase=="settle":
   var dt:float=minf(OBSERVED_STEP,remaining);remaining-=dt
   _observed_clock+=dt;_phone_elapsed+=dt
   if not _model.update("stop",_rig_distance,_node().position,_facing_right,_observed_clock,_phone_elapsed,true,_owner_reduced):return false
   if _model.settled and not _model.settling and _model.feet.far.planted and _model.feet.near.planted:
    _phone_phase="raise";_phone_completed_seconds=_phone_elapsed;_tablet_target=1.0
   elif _phone_elapsed>0.5:
    _phone_phase="failed";_issue("phone_owned_settle_exceeded500ms");return false
  _render_rig()
 return _phone_phase!="failed"

func _review_phone_clock_duplicate(frame_clock:float) -> bool:
 return frame_clock==_phone_last_frame
