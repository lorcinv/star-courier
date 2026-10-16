extends "res://scripts/actor_motion_2d.gd"
## STAGED clerk-only presentation for the user's explicit single-speed states.
## Movement is one walk cycle, distance-driven. No clock/timer/position ownership.
const SINGLE_MANIFEST:String="res://assets/2d_v5/actors/single_walk_v1/single-walk-registration.json"
const PLAYER_STATES:Array[String]=["idle","start","move","inertial_stop","stop"]
const MOVING_STATES:Array[String]=["start","move","inertial_stop"]
var _neutral:Dictionary={}
var _dialogue:Dictionary={}
var _player_state:String="idle"
var _distance_baseline:float=NAN
var _single_phase:float=0.0
var _was_moving:bool=false
var _registration_ready:bool=false
var _distance_rebases:int=0

func _preload_motion_assets() -> void:
 # Base constructor dispatches here before loading any clerk walk/run textures.
 # Copy shared data so all four NPC records and other adapters remain untouched.
 _record=_record.duplicate(true)
 _record.run=[];_record.run_sequence=[];_record.run_phase_weights=[]
 if not FileAccess.file_exists(SINGLE_MANIFEST):_record.walk=[];_issue("missing_single_walk_manifest");return
 var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(SINGLE_MANIFEST))
 if not data is Dictionary or not data.get("walk") is Array or data.walk.size()!=32 or not data.get("neutral") is Dictionary or not data.get("dialogue") is Dictionary:
  _record.walk=[];_issue("invalid_single_walk_manifest");return
 _record.walk=data.walk;_record.walk_sequence=range(32);_record.walk_phase_weights=[]
 _record.walk_cycle_distance=float(data.get("walk_cycle_distance",135.38461538461536));_record.walk_reference_height=240.0
 if data.get("gestures") is Dictionary:_record.gestures=data.gestures
 _neutral=data.neutral;_dialogue=data.dialogue
 super._preload_motion_assets()
 if _valid_neutral(_neutral):_texture(str(_neutral.get("runtime","")));_registration_ready=true
 else:_issue("invalid_neutral_registration")
 for pose in ["idle","handoff"]:
  if _dialogue.get(pose) is Dictionary:_texture(str(_dialogue[pose].get("runtime","")))

func _valid_neutral(frame:Dictionary) -> bool:
 return frame.get("empty_hands",false)==true and frame.get("relaxed_arms",false)==true and frame.get("pose_semantic","")=="neutral" and not str(frame.get("head_reference","")).is_empty() and is_finite(_point(frame.get("foot_anchor")).x) and is_finite(_point(frame.get("hip_anchor")).x) and is_finite(_point(frame.get("neck_anchor")).x) and frame.get("head_bounds") is Array and frame.head_bounds.size()==4

func configure_neutral(frame:Dictionary) -> bool:
 if not _valid_neutral(frame) or _texture(str(frame.get("runtime","")))==null:return false
 _neutral=frame.duplicate(true);_registration_ready=true;return true

func apply_player_pose(state:String,distance_px:float,right:bool,enabled:bool=true) -> bool:
 var sprite:Sprite2D=_node()
 if not is_instance_valid(sprite) or not sprite.is_visible_in_tree():return false
 if state not in PLAYER_STATES or not is_finite(distance_px) or distance_px<0.0 or not _registration_ready:return false
 if not enabled:
  _distance_baseline=distance_px;_was_moving=false;_player_state="idle"
  return _apply_neutral(right,"idle")
 var moving:bool=state in MOVING_STATES
 var cycle:float=walk_cycle_distance()
 if not is_finite(cycle) or cycle<=0.0:return false
 var delta:float=0.0 if not is_finite(_distance_baseline) else distance_px-_distance_baseline
 var rebase:bool=delta<-.00001 or delta>cycle*.75
 if rebase:_distance_rebases+=1;delta=0.0;_was_moving=false
 if moving:
  if not _was_moving:_single_phase=_neutral_start_phase(cycle)
  _single_phase=fposmod(_single_phase+maxf(0.0,delta)/cycle,1.0)
  _distance_baseline=distance_px;_was_moving=true;_player_state=state
  return super.apply_walk(_single_phase*cycle,right)
 _distance_baseline=distance_px;_was_moving=false;_player_state=state
 return _apply_neutral(right,state)

func _neutral_start_phase(cycle:float) -> float:
 # Start on a matching planted neutral shoe when the authored record supplies
 # it. The next actual movement delta advances that same shoe backward locally.
 var feet:Variant=_neutral.get("support_feet",[])
 if feet is Array:
  for foot in feet:
   if foot is Dictionary and str(foot.get("id",""))=="near":
    var at:Vector2=_point(foot.get("point"));var origin:Vector2=_point(_neutral.get("foot_anchor"))
    var sole:float=(at.x-origin.x)*_height/float(_neutral.get("body_height",240.0))
    var phase:float=36.0/132.0-sole/cycle
    if is_finite(phase) and phase>=0.0 and phase<.625:return phase
 return 0.0

func _apply_neutral(right:bool,state:String="idle") -> bool:
 if not _registration_ready:_issue("missing_neutral_registration");return false
 return _apply_frame(_neutral,state,-1,right)

func apply_idle(facing_right:bool=true) -> bool:
 _was_moving=false;_distance_baseline=NAN;_player_state="idle"
 return _apply_neutral(facing_right)

func apply_walk(distance_px:float,facing_right:bool=true) -> bool:
 return apply_player_pose("move",distance_px,facing_right)

func apply_run(distance_px:float,facing_right:bool=true) -> bool:
 # Compatibility only: even a stale caller cannot select run artwork.
 return apply_walk(distance_px,facing_right)

func apply_gesture(pose_id:String,facing_right:bool=true) -> bool:
 _was_moving=false;_distance_baseline=NAN;_player_state="idle"
 return super.apply_gesture(pose_id,facing_right)

func apply_dialogue(handoff:bool=false,facing_right:bool=true) -> bool:
 var key:String="handoff" if handoff else "idle"
 if not _dialogue.get(key) is Dictionary:return false
 _was_moving=false;_distance_baseline=NAN;_player_state="idle"
 return _apply_frame(_dialogue[key],"handoff" if handoff else "dialogue",-1,facing_right)

func restore_original() -> void:
 # Quiet restoration is neutral. Only apply_dialogue explicitly permits the
 # raised/open-palmed communication art. Do not texture-swap after this call.
 _was_moving=false;_distance_baseline=NAN;_player_state="idle"
 _apply_neutral(_facing_right)

func pose_anchor_parent(anchor_name:String) -> Vector2:
 var sprite:Sprite2D=_node()
 var anchors:Variant=_frame.get("hand_and_parcel_anchors",{})
 if not is_instance_valid(sprite) or not anchors is Dictionary or not anchors.has(anchor_name):return Vector2(INF,INF)
 var point:Vector2=_point(anchors[anchor_name])
 return sprite.transform*anchor_local(point) if is_finite(point.x) else Vector2(INF,INF)

func dialogue_anchor_parent(anchor_name:String,facing_right:bool=false) -> Vector2:
 # Pure future-handoff query. Never consult the CURRENT texture, offset, flip,
 # frame or pose scale; parcel routing asks while the clerk is still neutral.
 var sprite:Sprite2D=_node()
 var frame:Variant=_dialogue.get("handoff",{})
 if not is_instance_valid(sprite) or not frame is Dictionary:return Vector2(INF,INF)
 var anchors:Variant=frame.get("hand_and_parcel_anchors",{})
 if not anchors is Dictionary or not anchors.has(anchor_name):return Vector2(INF,INF)
 var point:Vector2=_point(anchors[anchor_name]);var foot:Vector2=_point(frame.get("foot_anchor"))
 var body_height:float=float(frame.get("body_height",0.0))
 if not is_finite(point.x) or not is_finite(foot.x) or not is_finite(body_height) or body_height<=0:return Vector2(INF,INF)
 var local:Vector2=point-foot
 if facing_right!=(str(frame.get("facing",""))=="right"):local.x=-local.x
 var pose_transform:=Transform2D(sprite.rotation,Vector2.ONE*_height/body_height,sprite.skew,sprite.position)
 return pose_transform*local

func debug_snapshot() -> Dictionary:
 var snap:Dictionary=super.debug_snapshot();var sprite:Sprite2D=_node()
 snap.player_state=_player_state;snap.single_walk_phase=_single_phase;snap.distance_rebases=_distance_rebases;snap.neutral_ready=_registration_ready
 snap.head_reference=str(_frame.get("head_reference",""));snap.head_view=str(_frame.get("head_view","upright"))
 if is_instance_valid(sprite) and _active:
  var neck:Vector2=_point(_frame.get("neck_anchor"));var hip:Vector2=_point(_frame.get("hip_anchor"))
  if is_finite(neck.x):snap.neck_point=sprite.transform*anchor_local(neck)
  if is_finite(hip.x):snap.hip_point=sprite.transform*anchor_local(hip)
  var box:Variant=_frame.get("head_bounds",[])
  if box is Array and box.size()==4:
   var p0:Vector2=sprite.transform*anchor_local(Vector2(float(box[0]),float(box[1])))
   var p1:Vector2=sprite.transform*anchor_local(Vector2(float(box[2]),float(box[3])))
   snap.head_bounds_parent=Rect2(p0.min(p1),p0.max(p1)-p0.min(p1));snap.head_size_parent=(p1-p0).abs()
 return snap
