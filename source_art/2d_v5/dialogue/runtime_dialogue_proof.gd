extends SceneTree
## Isolated rendered component fixture. Its open conversation is setup by script;
## every subsequent reveal/advance/mute/skip below is native XTest keyboard/pointer.
const Stories=preload("res://scripts/courier_stories.gd")
const DialoguePanel=preload("res://scripts/dialogue_panel.gd")
var panel
var elapsed:float=0.0
var phase:int=0
var underneath
class Probe extends Control:
 var leaked_keys:int=0
 var clicks:int=0
 func _unhandled_key_input(event:InputEvent) -> void:
  if event is InputEventKey and event.pressed:leaked_keys+=1
 func _gui_input(event:InputEvent) -> void:
  if event is InputEventMouseButton and event.pressed:clicks+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,720);root.title="Courier Dialogue Native Proof"
 underneath=Probe.new();underneath.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);underneath.mouse_filter=Control.MOUSE_FILTER_STOP;root.add_child(underneath)
 var art:=TextureRect.new();art.texture=load("res://assets/2d_v5/environment/far-city.png");art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);art.mouse_filter=Control.MOUSE_FILTER_IGNORE;underneath.add_child(art)
 var shop:=TextureRect.new();shop.texture=load("res://assets/2d_v5/environment/shop-shell.png");shop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;shop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shop.mouse_filter=Control.MOUSE_FILTER_IGNORE;underneath.add_child(shop)
 panel=DialoguePanel.new();root.add_child(panel);panel.finished.connect(_finished)
 var binding:=Stories.bind_contract({}, {"contract_id":"PROOF-A","status":"available"},1,0)
 panel.begin(Stories.conversation_for(binding.state,binding.contract,"accept"),binding.actor,{"reduced_motion":false})
 print("DIALOGUE_NATIVE_READY")
func _process(delta:float) -> bool:
 elapsed+=delta
 if elapsed>40:quit(2)
 return false
func _finished(id:String,skipped:bool) -> void:
 print("NATIVE_FINISHED ",id," skipped=",skipped," snapshot=",panel.debug_snapshot()," leaked_keys=",underneath.leaked_keys," underlying_clicks=",underneath.clicks)
 var file:=FileAccess.open("res://source_art/2d_v5/dialogue/native-result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"id":id,"skipped":skipped,"snapshot":panel.debug_snapshot(),"leaked_keys":underneath.leaked_keys,"underlying_clicks":underneath.clicks}));file.close()
 await create_timer(0.3).timeout
 quit(0)
