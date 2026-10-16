extends RefCounted
## Pure accepted-slice state. No clock, model, root, feet, nodes or callbacks.
const DRAW_SECONDS:float=0.30
const READY_SECONDS:float=0.12
var draw_progress:float=0.0
var draw_target:float=0.0
var gesture:String="reach"
var gesture_age:float=0.0
var ready_blend:float=0.0
var ready_pending:bool=false
var _ready_from:float=0.0
var _ready_target:float=0.0
var _ready_age:float=0.0
var accepted_seconds:float=0.0
var tap_state:String="complete"
var tap_age:float=0.0
var tap_blend:float=0.0
var _tap_withdraw_from:float=0.0
var _tap_withdraw_age:float=0.0
var _tap_fresh_after_withdraw:bool=false
const TAP_APPROACH:float=0.08
const TAP_DWELL_END:float=0.16
const TAP_END:float=0.28
const TAP_WITHDRAW:float=0.12

func begin_owner(value:String) -> void:
 # A new authority receives a fresh temporal session, but no spatial jump.
 gesture=value;gesture_age=0.0;accepted_seconds=0.0
 _ready_from=ready_blend;_ready_target=1.0 if value=="ready" else 0.0;_ready_age=0.0
 ready_pending=value=="ready" and draw_progress<1.0
 _cancel_tap();tap_age=0.0
 if value=="align":_queue_fresh_tap()

func complete_ready_endpoint() -> void:
 # Only the inherited explicit skip/restore relocation boundary calls this.
 begin_owner("ready")
 draw_progress=1.0;draw_target=1.0;ready_blend=1.0
 _ready_from=1.0;_ready_target=1.0;_ready_age=READY_SECONDS;ready_pending=false
 tap_state="complete";tap_age=0.0;tap_blend=0.0;_tap_fresh_after_withdraw=false

func intent(value:String) -> bool:
 if value not in ["reach","align","ready"]:return false
 if value==gesture:return true
 gesture=value;gesture_age=0.0
 _ready_from=ready_blend;_ready_target=1.0 if value=="ready" else 0.0;_ready_age=0.0
 ready_pending=value=="ready" and draw_progress<1.0
 _cancel_tap()
 if value=="align":_queue_fresh_tap()
 return true

func consume(elapsed:float,draw_elapsed:float) -> bool:
 if not is_finite(elapsed) or elapsed<=0.0 or elapsed>0.25:return false
 if not is_finite(draw_elapsed) or draw_elapsed<0.0 or draw_elapsed>elapsed+0.000001:return false
 # draw_elapsed is the accepted post-settle suffix, never a borrowed clock.
 var held_at:float=INF
 if draw_target==1.0 and draw_elapsed>0.0:
  var raise_left:float=(1.0-draw_progress)*DRAW_SECONDS
  if raise_left<=draw_elapsed+0.000000001:held_at=elapsed-draw_elapsed+raise_left
 accepted_seconds+=elapsed;gesture_age+=elapsed
 # Compare the actual remaining duration before dividing by DRAW_SECONDS.
 # An exactly funded endpoint must not retain a division-rounding residue.
 # No epsilon, extra elapsed, or early completion is introduced.
 var draw_left:float=absf(draw_target-draw_progress)*DRAW_SECONDS
 draw_progress=draw_target if draw_elapsed>=draw_left else move_toward(draw_progress,draw_target,draw_elapsed/DRAW_SECONDS)
 var ready_elapsed:float=elapsed
 if ready_pending:
  ready_elapsed=0.0
  if is_finite(held_at):
   ready_pending=false;ready_elapsed=maxf(0.0,elapsed-held_at)
 _ready_age=minf(READY_SECONDS,_ready_age+ready_elapsed)
 var u:float=_ready_age/READY_SECONDS
 ready_blend=lerpf(_ready_from,_ready_target,u*u*(3.0-2.0*u))
 _consume_tap(elapsed,held_at)
 return true

func request_lower() -> void:
 draw_target=0.0
 if ready_pending:
  ready_pending=false;_ready_from=ready_blend;_ready_target=ready_blend;_ready_age=READY_SECONDS
 _cancel_tap()

func _ease_tap(u:float) -> float:
 u=clampf(u,0.0,1.0)
 return u*u*(3.0-2.0*u)

func _cancel_tap() -> void:
 _tap_fresh_after_withdraw=false
 if tap_state=="withdrawing":return
 if tap_blend>0.0:
  tap_state="withdrawing";_tap_withdraw_from=tap_blend;_tap_withdraw_age=0.0
 else:
  tap_state="complete";tap_age=0.0;tap_blend=0.0

func _queue_fresh_tap() -> void:
 # Only an actual new align intention may queue; repeated intent returns early.
 tap_age=0.0
 if tap_state=="withdrawing":_tap_fresh_after_withdraw=true
 else:tap_state="pending";tap_blend=0.0

func _consume_tap(elapsed:float,held_at:float) -> void:
 var used:float=0.0
 if tap_state=="withdrawing":
  var dt:float=minf(elapsed,maxf(0.0,TAP_WITHDRAW-_tap_withdraw_age))
  _tap_withdraw_age+=dt;used+=dt
  tap_blend=_tap_withdraw_from*(1.0-_ease_tap(_tap_withdraw_age/TAP_WITHDRAW))
  if _tap_withdraw_age>=TAP_WITHDRAW-0.000000001:
   tap_blend=0.0
   tap_state="pending" if _tap_fresh_after_withdraw else "complete"
   _tap_fresh_after_withdraw=false
 if tap_state=="pending":
  if not is_finite(held_at):return
  used=maxf(used,held_at)
  if used>elapsed+0.000000001:return
  tap_state="running";tap_age=0.0
 if tap_state=="running":
  tap_age=minf(TAP_END,tap_age+maxf(0.0,elapsed-used))
  if tap_age<TAP_APPROACH:tap_blend=_ease_tap(tap_age/TAP_APPROACH)
  elif tap_age<TAP_DWELL_END:tap_blend=1.0
  elif tap_age<TAP_END:tap_blend=1.0-_ease_tap((tap_age-TAP_DWELL_END)/TAP_WITHDRAW)
  else:tap_state="complete";tap_blend=0.0

func snapshot() -> Dictionary:
 return {"draw_progress":draw_progress,"draw_target":draw_target,"gesture":gesture,
  "gesture_age":gesture_age,"ready_blend":ready_blend,"ready_pending":ready_pending,"accepted_seconds":accepted_seconds,
  "ready_from":_ready_from,"ready_target":_ready_target,"ready_age":_ready_age,
  "tap_state":tap_state,"tap_age":tap_age,"tap_blend":tap_blend,
  "tap_withdraw_from":_tap_withdraw_from,"tap_withdraw_age":_tap_withdraw_age,
  "tap_fresh_after_withdraw":_tap_fresh_after_withdraw}
