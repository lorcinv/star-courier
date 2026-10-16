extends CanvasLayer
## Modal presentation only. No settlement, rewards or global pause mutation.
## Parent must guard gameplay input with is_open() and queue dialogues outside flight.
signal finished(dialogue_id:String,skipped:bool)
signal modal_changed(open:bool)
signal audio_settings_changed(volume:float,muted:bool)
const DisplayMetrics=preload("res://scripts/demo_display_metrics.gd")
const BASE:=Vector2(1280,720)
const FONT=preload("res://assets/fonts/ChineseSans.otf")
const MAX_VOICES:int=3
const REVEAL_SECONDS:float=0.043
const BLEEPS_COOLDOWN:float=0.055
const CLERK_PORTRAIT_ROOT:String="res://assets/2d_v5/dialogue/clerk-"
const INK:=Color("101a30")
const CREAM:=Color("f7e9c7")
const TEAL:=Color("49cce5")
const YELLOW:=Color("ffca57")
const NAMEPLATE_SIZE:=Vector2(244,57)
const NAMEPLATE_Y:float=449.0 # Portrait footer, overlapping the textbox's top border.
var _root:Control
var _canvas:Control
var _left_portrait:TextureRect
var _right_portrait:TextureRect
var _name:Label
var _subtitle:Label
var _body:Label
var _counter:Label
var _hint:Label
var _continue:Button
var _mute:Button
var _volume:HSlider
var _voices:Array[AudioStreamPlayer]=[]
var _voice_streams:Dictionary={}
var _texture_cache:Dictionary={}
var _conversation:Dictionary={}
var _actor:Dictionary={}
var _settings:Dictionary={}
var _open:bool=false
var _line_index:int=0
var _visible_chars:int=0
var _reveal_accumulator:float=0.0
var _bleep_cooldown:float=0.0
var _bleeps_played:int=0
var _voice_cursor:int=0
var _generation:int=0
var _return_focus:WeakRef
var _entrance_tween:Tween
var _left_expression:String="neutral"
var _right_expression:String="neutral"
var _npc_speaking:bool=true
var audio_volume:float=0.55
var audio_muted:bool=false
var _master_volume:float=1.0
var _focus_active:bool=true
var _display_density:float=1.0
var _display_texture_cache:Dictionary={}

func _ready() -> void:
 layer=60
 process_mode=Node.PROCESS_MODE_ALWAYS
 _build()
 get_viewport().size_changed.connect(_layout)
 _layout()
 _root.hide()
 set_process(false)
 set_process_input(false)

func _build() -> void:
 _root=Control.new();_root.name="CourierDialogueModal";_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_root.mouse_filter=Control.MOUSE_FILTER_STOP;_root.mouse_force_pass_scroll_events=false;add_child(_root)
 _root.theme=Theme.new();_root.theme.default_font=FONT;_root.theme.default_font_size=22
 _root.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 var shade:=ColorRect.new();shade.color=Color(0.025,0.042,0.077,0.76);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(shade)
 _canvas=Control.new();_canvas.name="DialogueComposition";_canvas.size=BASE;_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(_canvas)
 _subtitle=_label(_canvas,Rect2(242,105,796,38),"柜台来信  /  晨星社区 → 星港中转站",22,CREAM);_subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 var left_frame:=Panel.new();left_frame.position=Vector2(83,182);left_frame.size=Vector2(340,348);left_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;left_frame.add_theme_stylebox_override("panel",_style(Color("17243a"),Color("375574"),2));_canvas.add_child(left_frame)
 var right_frame:=Panel.new();right_frame.position=Vector2(857,182);right_frame.size=Vector2(340,348);right_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;right_frame.add_theme_stylebox_override("panel",_style(Color("17243a"),Color("375574"),2));_canvas.add_child(right_frame)
 _left_portrait=_portrait(Rect2(54,140,404,404),"NPCPortraitLeft")
 _right_portrait=_portrait(Rect2(822,140,404,404),"ClerkPortraitRight")
 var paper:=Panel.new();paper.position=Vector2(79,485);paper.size=Vector2(1122,178);paper.mouse_filter=Control.MOUSE_FILTER_IGNORE;paper.add_theme_stylebox_override("panel",_style(CREAM,INK,4));_canvas.add_child(paper)
 var stripe:=ColorRect.new();stripe.position=Vector2(83,489);stripe.size=Vector2(1114,7);stripe.color=TEAL;stripe.mouse_filter=Control.MOUSE_FILTER_IGNORE;_canvas.add_child(stripe)
 _name=_label(_canvas,Rect2(Vector2.ZERO,NAMEPLATE_SIZE),"",26,INK);_name.name="ActiveSpeakerNameplate"
 _name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_name.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
 _name.clip_text=true;_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 _name.add_theme_stylebox_override("normal",_style(YELLOW,INK,3,9))
 _name.hide()
 _body=_label(_canvas,Rect2(112,516,1022,74),"",27,INK);_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 _counter=_label(_canvas,Rect2(564,451,152,30),"",18,CREAM);_counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 _hint=_label(_canvas,Rect2(112,615,635,28),"Enter / 空格：快显、继续    Esc：跳过",17,Color("52647c"))
 _continue=_button(Rect2(928,603,235,44),"继续  →",advance)
 _mute=_button(Rect2(90,675,145,34),"对话声：开",_toggle_mute)
 _volume=HSlider.new();_volume.position=Vector2(246,680);_volume.size=Vector2(154,22);_volume.min_value=0;_volume.max_value=1;_volume.step=0.05;_volume.value=audio_volume;_volume.mouse_filter=Control.MOUSE_FILTER_STOP;_canvas.add_child(_volume);_volume.value_changed.connect(_on_volume_changed)
 var skip:=_button(Rect2(1030,675,166,34),"跳过对话  Esc",skip_conversation);skip.name="SkipDialogue"
 for i in MAX_VOICES:
  var player:=AudioStreamPlayer.new();player.name="DialogueBleep%d"%i;player.process_mode=Node.PROCESS_MODE_ALWAYS;player.max_polyphony=1;add_child(player);_voices.append(player)
 for species in ["human","elf","alien","robot","clerk"]:_voice_streams[species]=_synthesize_bleep(species)

func _style(fill:Color,border:Color,width:int,padding:int=0) -> StyleBoxFlat:
 var style:=StyleBoxFlat.new();style.bg_color=fill;style.border_color=border;style.set_border_width_all(width);style.set_content_margin_all(padding);return style

func _label(parent:Control,rect:Rect2,text:String,size:int,color:Color) -> Label:
 var label:=Label.new();label.position=rect.position;label.size=rect.size;label.text=text;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(label);return label

func _button(rect:Rect2,text:String,callback:Callable) -> Button:
 var button:=Button.new();button.position=rect.position;button.size=rect.size;button.text=text;button.mouse_filter=Control.MOUSE_FILTER_STOP;button.add_theme_font_size_override("font_size",18)
 button.add_theme_color_override("font_color",CREAM);button.add_theme_color_override("font_hover_color",INK);button.add_theme_color_override("font_pressed_color",INK)
 button.add_theme_stylebox_override("normal",_style(INK,TEAL,2));button.add_theme_stylebox_override("hover",_style(TEAL,INK,2));button.add_theme_stylebox_override("pressed",_style(YELLOW,INK,3));button.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),YELLOW,3));_canvas.add_child(button);button.pressed.connect(callback);return button

func _portrait(rect:Rect2,title:String) -> TextureRect:
 var portrait:=TextureRect.new();portrait.name=title;portrait.position=rect.position;portrait.size=rect.size;portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;_canvas.add_child(portrait);return portrait

func _layout() -> void:
 if not is_instance_valid(_canvas):return
 var screen:Vector2=get_viewport().get_visible_rect().size
 _display_density=DisplayMetrics.factor(screen)
 var shown:Vector2=DisplayMetrics.point(BASE,_display_density)
 _canvas.scale=Vector2.ONE;_canvas.size=shown;_canvas.position=((screen-shown)*0.5).floor()
 DisplayMetrics.apply_theme(_root,_display_density)
 DisplayMetrics.apply_stage(_canvas,_display_density)
 _position_nameplate()

func _position_nameplate() -> void:
 if not is_instance_valid(_name):return
 var portrait:TextureRect=_left_portrait if _npc_speaking else _right_portrait
 # Both portraits share the textbox footer. Derive the horizontal attachment
 # from the speaking portrait so switching speaker and resizing cannot diverge.
 _name.size=DisplayMetrics.point(NAMEPLATE_SIZE,_display_density)
 _name.position=Vector2(roundf(portrait.get_rect().get_center().x-_name.size.x*0.5),roundf(NAMEPLATE_Y*_display_density))

func begin(conversation:Dictionary,actor_metadata:Dictionary={},settings:Dictionary={}) -> bool:
 if not is_node_ready():return false
 if not conversation.get("lines") is Array or conversation.lines.is_empty():return false
 for line in conversation.lines:
  if not line is Dictionary or not line.get("text") is String:return false
 # A newer conversation supersedes the old one without claiming it was completed.
 if not _open:
  var focus:Control=get_viewport().gui_get_focus_owner()
  _return_focus=weakref(focus) if is_instance_valid(focus) else null
 _stop_audio();_stop_entrance();_generation+=1
 _conversation=conversation.duplicate(true);_actor=actor_metadata.duplicate(true) if not actor_metadata.is_empty() else conversation.get("actor",{}).duplicate(true);_settings=settings.duplicate(true)
 _master_volume=clampf(float(settings.get("volume",1.0)),0.0,1.0)
 audio_volume=clampf(float(settings.get("dialogue_volume",0.55)),0.0,1.0);audio_muted=bool(settings.get("dialogue_muted",false))
 _volume.set_value_no_signal(audio_volume);_refresh_audio_button()
 _open=true;_line_index=0;_left_expression="neutral";_right_expression="neutral";_root.show();set_process(_focus_active);set_process_input(true);_layout();_show_line();_continue.grab_focus()
 _canvas.modulate.a=1.0
 if not bool(settings.get("reduced_motion",false)):
  _canvas.modulate.a=0.0;_entrance_tween=create_tween();_entrance_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS);_entrance_tween.tween_property(_canvas,"modulate:a",1.0,0.12)
  _entrance_tween.finished.connect(_on_entrance_finished.bind(_entrance_tween.get_instance_id()))
 modal_changed.emit(true)
 return true

func is_open() -> bool:return _open

func set_focus_active(active:bool) -> void:
 _focus_active=active;set_process(_open and active)
 _reveal_accumulator=0.0
 if not active:_stop_audio()

func advance() -> void:
 if not _open:return
 var full_text:String=str(_conversation.lines[_line_index].text)
 if _visible_chars<full_text.length():
  # Fast reveal is silent. There is no scheduled audio queue to drain.
  _visible_chars=full_text.length();_body.visible_characters=-1;_reveal_accumulator=0.0;_stop_audio();_continue.text="完成  →" if _line_index==_conversation.lines.size()-1 else "继续  →";return
 _stop_audio();_line_index+=1
 if _line_index>=_conversation.lines.size():_dismiss(false,true,true)
 else:_show_line()

func skip_conversation() -> void:_dismiss(true,true,true)
func close() -> void:_dismiss(true,true,true)
func cancel(emit_finished:bool=true) -> void:_dismiss(true,emit_finished,true)

func _dismiss(skipped:bool,emit_signal:bool,restore_focus:bool) -> void:
 if not _open:return
 var did:String=str(_conversation.get("dialogue_id",_conversation.get("id","")))
 _generation+=1;_open=false;_stop_audio();_stop_entrance();set_process(false);set_process_input(false);_root.hide();_conversation={};_actor={};_reveal_accumulator=0.0
 _name.text="";_name.hide();_npc_speaking=true;_position_nameplate()
 if restore_focus and _return_focus!=null:
  var focus:Control=_return_focus.get_ref() as Control
  if is_instance_valid(focus) and focus.is_inside_tree() and focus.is_visible_in_tree() and focus.focus_mode!=Control.FOCUS_NONE:focus.grab_focus()
 _return_focus=null
 modal_changed.emit(false)
 if emit_signal:finished.emit(did,skipped)

func _show_line() -> void:
 _stop_audio();_visible_chars=0;_reveal_accumulator=0.0
 var line:Dictionary=_conversation.lines[_line_index]
 var npc:bool=str(line.get("speaker","npc"))!="clerk"
 _npc_speaking=npc
 if npc:_left_expression=str(line.get("expression","neutral"))
 else:_right_expression=str(line.get("expression","neutral"))
 _left_portrait.texture=_portrait_grid(_npc_texture(_left_expression))
 _right_portrait.texture=_portrait_grid(_get_texture(CLERK_PORTRAIT_ROOT+_right_expression+".png",CLERK_PORTRAIT_ROOT+"neutral.png"))
 _left_portrait.modulate=Color.WHITE if npc else Color(0.48,0.53,0.61,1.0)
 _right_portrait.modulate=Color(0.48,0.53,0.61,1.0) if npc else Color.WHITE
 _name.text=str(_actor.get("name","来访者")) if npc else "店员 · 你"
 _position_nameplate();_name.show()
 _subtitle.text=str(_conversation.get("title","柜台来信"))+"  /  "+str(_conversation.get("route_hint","晨星社区 → 星港中转站"))
 _counter.text="%02d / %02d"%[_line_index+1,_conversation.lines.size()]
 _body.text=str(line.text);_body.visible_characters=0;_continue.text="快显  →"

func _portrait_grid(source:Texture2D) -> Texture2D:
 if source==null:return null
 var key:int=source.get_instance_id()
 if not _display_texture_cache.has(key):_display_texture_cache[key]=DisplayMetrics.integer_texture(source,Vector2i(202,202))
 return _display_texture_cache[key]

func _get_texture(path:String,fallback:String="") -> Texture2D:
 if _texture_cache.has(path):return _texture_cache[path]
 var chosen:String=path if ResourceLoader.exists(path) else fallback
 if not chosen.is_empty() and ResourceLoader.exists(chosen):
  var texture:=load(chosen) as Texture2D
  _texture_cache[path]=texture;return texture
 return null

func _npc_texture(expression:String) -> Texture2D:
 var portraits:Dictionary=_actor.get("portraits",{})
 var fallback:String=str(portraits.get("neutral","res://assets/2d_v5/dialogue/human_courier-neutral.png"))
 return _get_texture(str(portraits.get(expression,fallback)),fallback)

func set_input_device(gamepad:bool) -> void:
 if is_instance_valid(_hint):_hint.text="方向 选择  ·  A 确认  ·  B 跳过" if gamepad else "Enter / 空格：快显、继续    Esc：跳过"
 var skip:=_canvas.get_node_or_null("SkipDialogue")
 if skip!=null:skip.text="跳过对话  B" if gamepad else "跳过对话  Esc"

func _input(event:InputEvent) -> void:
 if not _open or not _focus_active:return
 if event is InputEventKey:
  get_viewport().set_input_as_handled()
  if not event.pressed or event.echo:return
  var code:int=event.keycode if event.keycode!=0 else event.physical_keycode
  if code==KEY_ESCAPE:skip_conversation()
  elif code in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:advance()
  elif code==KEY_M:_toggle_mute()
  elif code in [KEY_LEFT,KEY_RIGHT] and _volume.has_focus():
   _on_volume_changed(audio_volume+(-0.05 if code==KEY_LEFT else 0.05))
  elif code==KEY_TAB:
   # Modal keyboard focus never escapes to the underlying shop/flight controls.
   var current:Control=get_viewport().gui_get_focus_owner()
   var next:Control=current.find_prev_valid_focus() if event.shift_pressed and current!=null else (current.find_next_valid_focus() if current!=null else _continue)
   if next!=null and _root.is_ancestor_of(next):next.grab_focus()
   else:_continue.grab_focus()
 elif event is InputEventJoypadButton or event is InputEventJoypadMotion:get_viewport().set_input_as_handled()
 # Mouse is captured by the full-viewport STOP Control; child buttons stay usable.

func _process(delta:float) -> void:
 if not _open or not _focus_active:return
 _bleep_cooldown=maxf(0.0,_bleep_cooldown-delta)
 var text:String=str(_conversation.lines[_line_index].text)
 if _visible_chars>=text.length():return
 # Slow frames cannot cause a catch-up sound burst or unbounded work.
 _reveal_accumulator+=minf(delta,0.10)
 var voiced:bool=false
 var steps:int=0
 var expression:String=str(_conversation.lines[_line_index].get("expression","neutral"))
 while _visible_chars<text.length() and steps<3:
  var character:String=text.substr(_visible_chars,1)
  var interval:float=reveal_interval(character,expression)
  if _reveal_accumulator<interval:break
  voiced=voiced or is_voiced_character(character)
  _visible_chars+=1;steps+=1;_reveal_accumulator-=interval
 _body.visible_characters=_visible_chars
 if voiced and _bleep_cooldown<=0.0:_play_bleep()
 if _visible_chars>=text.length():_continue.text="完成  →" if _line_index==_conversation.lines.size()-1 else "继续  →"

static func expression_profile(expression:String) -> Dictionary:
 match expression:
  "warm_smile":return {"cadence":0.038,"pitch":1.04,"gain_db":-0.5}
  "pleased":return {"cadence":0.033,"pitch":1.10,"gain_db":0.0}
  "concerned":return {"cadence":0.055,"pitch":0.92,"gain_db":-1.5}
  "curious":return {"cadence":0.046,"pitch":1.05,"gain_db":-0.5}
  "surprised":return {"cadence":0.030,"pitch":1.16,"gain_db":0.0}
 return {"cadence":REVEAL_SECONDS,"pitch":1.0,"gain_db":0.0}

static func reveal_interval(character:String,expression:String) -> float:
 # Expression pacing and punctuation rests are deterministic, never queued audio.
 if character in ["。","！","？","!","?","…","."]:return 0.17
 if character in ["，","、","；","：",",",";",":"]:return 0.095
 if character in [" ","\t","\n"]:return 0.025
 return float(expression_profile(expression).cadence)

static func is_voiced_character(character:String) -> bool:
 if character.is_empty():return false
 var code:int=character.unicode_at(0)
 return (code>=48 and code<=57) or (code>=65 and code<=90) or (code>=97 and code<=122) or (code>=0x3400 and code<=0x9fff) or (code>=0x3041 and code<=0x3096) or (code>=0x30a1 and code<=0x30fa) or (code>=0xac00 and code<=0xd7a3)

func _play_bleep() -> void:
 if audio_muted or audio_volume<=0.0 or _master_volume<=0.0:return
 var line:Dictionary=_conversation.lines[_line_index]
 var is_clerk:bool=str(line.get("speaker","npc"))=="clerk"
 var species:String="clerk" if is_clerk else str(_actor.get("species","human"))
 var player:AudioStreamPlayer=_voices[_voice_cursor%MAX_VOICES];_voice_cursor+=1;player.stop()
 player.stream=_voice_streams.get(species,_voice_streams.human)
 var expression:Dictionary=expression_profile(str(line.get("expression","neutral")))
 var phrase_variation:float=[1.0,1.08,0.94,1.04,0.98][_visible_chars%5]
 player.pitch_scale=(1.1 if is_clerk else float(_actor.get("voice_pitch",1.0)))*phrase_variation*float(expression.pitch)
 player.volume_db=linear_to_db(maxf(0.001,audio_volume*_master_volume))-11.0+float(expression.gain_db);player.play();_bleeps_played+=1;_bleep_cooldown=BLEEPS_COOLDOWN

func _stop_audio() -> void:
 for voice in _voices:voice.stop()
 _bleep_cooldown=0.0

func set_audio(volume:float,muted:bool=false) -> void:
 audio_volume=clampf(volume,0.0,1.0);audio_muted=muted
 if is_instance_valid(_volume):_volume.set_value_no_signal(audio_volume)
 if muted or audio_volume<=0.0:_stop_audio()
 for voice in _voices:voice.volume_db=linear_to_db(maxf(0.001,audio_volume*_master_volume))-11.0
 _refresh_audio_button()

func _toggle_mute() -> void:
 set_audio(audio_volume,not audio_muted);audio_settings_changed.emit(audio_volume,audio_muted)

func _on_volume_changed(value:float) -> void:
 set_audio(value,audio_muted);audio_settings_changed.emit(audio_volume,audio_muted)

func _refresh_audio_button() -> void:
 if is_instance_valid(_mute):_mute.text="对话声：关" if audio_muted or audio_volume<=0.0 else "对话声：开"

func _stop_entrance() -> void:
 if _entrance_tween!=null and _entrance_tween.is_valid():_entrance_tween.kill()
 _entrance_tween=null

func _on_entrance_finished(instance_id:int) -> void:
 if _entrance_tween!=null and _entrance_tween.get_instance_id()==instance_id:_entrance_tween=null

func _exit_tree() -> void:
 _stop_audio();_stop_entrance();_open=false;_return_focus=null
 for voice in _voices:voice.stream=null
 _voices.clear();_voice_streams.clear();_texture_cache.clear();_display_texture_cache.clear()

func debug_snapshot() -> Dictionary:
 var playing:int=0
 for voice in _voices:
  if voice.playing:playing+=1
 return {"open":_open,"generation":_generation,"line_index":_line_index,"visible_characters":_visible_chars,"bleeps_played":_bleeps_played,"active_voices":playing,"voice_pool_size":_voices.size(),"queued_bleeps":0,"entrance_tween":_entrance_tween!=null,"left_expression":_left_expression,"right_expression":_right_expression,"audio_muted":audio_muted,"audio_volume":audio_volume}

static func _synthesize_bleep(species:String) -> AudioStreamWAV:
 # Tiny original nonverbal synth syllables. No samples, words, or voice imitation.
 var rate:int=22050;var duration:float=0.065
 var count:int=int(rate*duration);var data:=PackedByteArray();data.resize(count*2)
 var frequency:float=390.0 if species=="robot" else (610.0 if species=="alien" else (520.0 if species=="elf" else 460.0))
 var phase:float=0.0
 for i in count:
  var t:float=float(i)/rate;var unit:float=t/duration
  var envelope:float=minf(t/0.006,1.0)*pow(1.0-unit,1.7)
  phase+=TAU*frequency*(1.08-0.22*unit)/rate
  var sample:float=(sin(phase)+0.16*sin(phase*2.0))*envelope*0.42
  var value:int=clampi(int(sample*32767),-32768,32767)
  data.encode_s16(i*2,value)
 var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.stereo=false;stream.data=data
 return stream
