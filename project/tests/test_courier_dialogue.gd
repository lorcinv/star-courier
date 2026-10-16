extends SceneTree
## Pure-state + synthetic-input component tests, isolated from actual player saves.
const Stories=preload("res://scripts/courier_stories.gd")
const DialoguePanel=preload("res://scripts/dialogue_panel.gd")
var passed:int=0
var failed:int=0
var completed:Array=[]
var modal_events:Array=[]
var underlying_keys:int=0
var panel
var focus:Button
class InputProbe extends Node:
 var key_count:int=0
 func _unhandled_key_input(event:InputEvent) -> void:
  if event is InputEventKey:key_count+=1
func _initialize() -> void:run.call_deferred()
func check(condition:bool,message:String) -> void:
 if condition:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func settle(frames:int=3) -> void:
 for i in frames:await process_frame
func _finish(id:String,skipped:bool) -> void:completed.append([id,skipped])
func _modal(open:bool) -> void:modal_events.append(open)
func convo(id:String="test",text:String="快递今天到了。 Hello!") -> Dictionary:
 return {"id":id,"lines":[{"speaker":"npc","text":text,"expression":"neutral"},{"speaker":"clerk","text":"收到，谢谢！","expression":"pleased"}]}
func retained(refs:Array) -> int:
 var count:int=0
 for item in refs:
  if item.get_ref()!=null:count+=1
 return count
func test_state() -> void:
 var state:=Stories.initial_state();var before:=JSON.stringify(state)
 check(state.roster.size()==4,"four fixed recurring identities")
 var seeded:=Stories.initial_state(7421)
 check(seeded.world_seed==7421 and seeded.roster==Stories.initial_state(7421).roster,"one explicit cosmetic shop seed repeats exactly")
 check(seeded.roster.elf_archivist.appearance_seed!=Stories.initial_state(7422).roster.elf_archivist.appearance_seed,"different new-shop seeds vary compatible cosmetic choices")
 check(Stories.normalize_state(JSON.parse_string(JSON.stringify(seeded))).roster==seeded.roster,"cosmetic seed and appearance survive normalized JSON reload")
 for id in Stories.IDS:
  var actor:Dictionary=state.roster[id]
  check(actor.species==Stories.PROFILES[id].species,"species stays bound to "+id)
  check(actor.accessory_id in Stories.PROFILES[id].accessories,"accessory compatibility for "+id)
 var names:Array=[]
 for day in [1,2]:
  for slot in [0,1]:
   var result:=Stories.bind_contract(state,{"contract_id":"D%d-%s"%[day,"A" if slot==0 else "B"],"status":"available"},day,slot)
   names.append(result.contract.appearance_id)
 check(names==Stories.IDS,"first two days deterministically cover all four species")
 check(JSON.stringify(state)==before,"binding helper never mutates caller-owned state")
 var bound:=Stories.bind_contract(state,{"contract_id":"D1-A","status":"available"},1,0)
 state=bound.state
 var saved:Dictionary=JSON.parse_string(JSON.stringify(state))
 seed(11937)
 for i in 40:randi()
 var rebound:=Stories.bind_contract(saved,bound.contract,99,1)
 check(rebound.contract.appearance_id==bound.contract.appearance_id,"saved contract identity wins over later day/slot")
 check(int(rebound.contract.appearance_seed)==int(bound.contract.appearance_seed),"appearance seed survives JSON numbers and random calls")
 check(rebound.contract.accessory_id==bound.contract.accessory_id,"accessory survives JSON save/reload")
 check(rebound.contract.client=="小禾","display client matches portrait identity")
 var legacy:=Stories.bind_contract(state,{"contract_id":"legacy","status":"in_flight","client":"原客户"},1,0)
 check(not legacy.contract.has("appearance_id") and legacy.contract.client=="原客户","unbound legacy in-flight identity remains untouched")
 var invalid:=Stories.bind_contract(state,{"status":"available"},1,0)
 check(invalid.actor.is_empty(),"missing contract ID cannot produce a story identity")
 var accept:=Stories.conversation_for(state,bound.contract,"accept")
 check(accept.lines.size()==3 and accept.id=="D1-A/accept","acceptance story has unique contract-scoped dialogue ID")
 check(Stories.conversation_for(state,bound.contract,"result").is_empty(),"uncommitted result cannot be shown")
 var seen:=Stories.mark_seen(state,"D1-A","D1-A/accept")
 check(Stories.conversation_for(seen,bound.contract,"accept").is_empty(),"seen acceptance does not replay")
 check(not Stories.conversation_for(state,bound.contract,"accept").is_empty(),"mark_seen works on a copy")
 check(Stories.mark_seen(state,"D1-A","other/accept").seen_dialogue_ids.is_empty(),"foreign dialogue IDs cannot hide story")
 var report:Dictionary={"contract_id":"D1-A","success":true,"income":9999}
 var trial:=Stories.commit_settlement(state,bound.contract,report,true)
 check(not trial.advanced and trial.state.committed_contract_ids.is_empty(),"trial never advances story")
 var estimate:=Stories.commit_settlement(state,bound.contract,report)
 check(not estimate.advanced,"non-settled estimate never advances story")
 var settled:Dictionary=bound.contract.duplicate(true);settled.status="settled"
 var mismatch:=Stories.commit_settlement(state,settled,{"contract_id":"other","success":true})
 check(not mismatch.advanced,"mismatched report cannot advance contract")
 var result:=Stories.commit_settlement(state,settled,report)
 check(result.advanced and result.state.roster.human_courier.story_node==1,"only committed unique settlement advances a story")
 check(result.conversation.id=="D1-A/result","settlement produces contract-scoped result conversation")
 check(not result.state.has("credits") and not result.state.has("income"),"story stores no reward or financial mutation")
 var duplicate:=Stories.commit_settlement(result.state,settled,report)
 check(not duplicate.advanced and duplicate.state.roster.human_courier.story_node==1,"duplicate settlement cannot double advance")
 var returns:=Stories.pending_return_conversations(result.state)
 check(returns.size()==1 and returns[0].id=="D1-A/return","return dialogue is queued after settlement")
 var returned:=Stories.mark_seen(result.state,"D1-A","D1-A/return")
 check(returned.pending_returns.is_empty() and returned.roster.human_courier.story_node==1,"reading return removes queue entry without advancing settlement")
 var failed_report:=Stories.commit_settlement(state,settled,{"contract_id":"D1-A","success":false})
 check(failed_report.conversation.lines[0].expression=="concerned","failed delivery never claims the parcel arrived")
 var many:Dictionary=state
 for i in range(24):
  var extra:=Stories.bind_contract(many,{"contract_id":"extra%d"%i,"status":"available"},1,i%4)
  extra.contract.status="settled"
  many=Stories.commit_settlement(extra.state,extra.contract,{"contract_id":"extra%d"%i,"success":true}).state
 check(many.pending_returns.size()==Stories.MAX_PENDING_RETURNS,"pending-return queue is bounded")
 check(many.roster.human_courier.story_node<=3,"story progression remains bounded")
 var corrupted:=Stories.normalize_state({"roster":{"elf_archivist":{"accessory_id":"power_cell","appearance_seed":12}},"pending_returns":["A","A",12]})
 check(corrupted.roster.elf_archivist.accessory_id in ["book_pouch","map_case"],"incompatible saved accessory repaired without species mixing")
 check(corrupted.pending_returns.is_empty(),"queue normalization rejects malformed, duplicate and dangling IDs")
 var malformed:Dictionary=JSON.parse_string('{"roster":{"human_courier":{"appearance_seed":{},"story_node":[]}},"contract_bindings":{"bad1":true,"bad2":[],"bad3":{"appearance_id":"unknown"},"good":{"appearance_id":"human_courier","appearance_seed":42,"story_node":1}},"seen_dialogue_ids":{"good":{"good/accept":true,"other/result":true,"good/result":"true"},"bad1":7},"committed_contract_ids":{"good":{"success":true},"bad1":false},"pending_returns":["good","good","bad1",12]}')
 var cleaned:=Stories.normalize_state(malformed)
 check(cleaned.contract_bindings.size()==1 and cleaned.contract_bindings.good.appearance_seed==42,"malformed bindings filtered while valid identity preserved")
 check(cleaned.seen_dialogue_ids.good=={"good/accept":true},"malformed seen flags and foreign IDs filtered")
 check(cleaned.committed_contract_ids=={"good":{"success":true}} and cleaned.pending_returns==["good"],"malformed settlement entries filtered and valid return deduplicated")
 check(Stories.bind_contract(cleaned,{"contract_id":"good","status":"available"},3,0).contract.appearance_seed==42,"cleaned save remains usable for binding")
 check(not Stories.conversation_for(cleaned,{"contract_id":"good"},"return").is_empty(),"cleaned save remains usable for conversation")
 var scalar_maps:=Stories.normalize_state({"roster":1,"contract_bindings":[1],"seen_dialogue_ids":"wrong","committed_contract_ids":true,"pending_returns":{}})
 check(scalar_maps.roster.size()==4 and scalar_maps.contract_bindings.is_empty(),"malformed top-level maps normalize safely")
 var scalar_report:=Stories.commit_settlement(state,settled,{"contract_id":"D1-A","success":"false"})
 check(not scalar_report.advanced,"non-boolean settlement outcome cannot advance story")
func test_characters() -> void:
 for char in [" ","\n","\t","。","，","！","？","：","；","…","—",",",".","!","?","(",")","·","→"]:
  check(not DialoguePanel.is_voiced_character(char),"punctuation/space is silent: "+char)
 for char in ["你","好","A","z","4","あ","カ"]:check(DialoguePanel.is_voiced_character(char),"spoken glyph eligible: "+char)
func test_expression() -> void:
 check(DialoguePanel.reveal_interval("A","pleased")<DialoguePanel.reveal_interval("A","concerned"),"pleased cadence is quicker than concerned")
 check(DialoguePanel.expression_profile("surprised").pitch>DialoguePanel.expression_profile("concerned").pitch,"surprised and concerned use distinct expression pitches")
 check(DialoguePanel.reveal_interval("。","pleased")>DialoguePanel.reveal_interval("A","pleased"),"sentence punctuation inserts a silent rest")
 check(DialoguePanel.reveal_interval("，","neutral")>DialoguePanel.reveal_interval("A","neutral"),"comma punctuation inserts a silent rest")
 check(DialoguePanel.expression_profile("unknown")==DialoguePanel.expression_profile("neutral"),"unknown expressions use safe neutral voice profile")
func test_modal() -> void:
 check(panel._root.mouse_filter==Control.MOUSE_FILTER_STOP,"full viewport modal captures pointers")
 check(panel.process_mode==Node.PROCESS_MODE_ALWAYS,"dialogue remains controllable under preexisting pause")
 check(not panel.begin({"lines":[]}),"empty dialogue rejected without taking focus")
 check(not panel.begin({"lines":[{}]}),"malformed dialogue rejected")
 focus.grab_focus();await settle()
 check(panel.begin(convo(),{}, {"reduced_motion":true}),"valid dialogue opens")
 panel.set_process(false)
 check(panel.is_open() and panel._continue.has_focus(),"dialogue owns keyboard focus")
 check(panel._entrance_tween==null and panel._canvas.modulate.a==1.0,"reduced motion has no entrance Tween")
 check(not paused,"opening does not silently pause the game tree")
 panel._process(0.06)
 check(panel._visible_chars==1,"typewriter reveals one glyph on ordinary frame")
 var start:int=panel._bleeps_played
 panel.advance()
 check(panel._body.visible_characters==-1 and panel._visible_chars==str(convo().lines[0].text).length(),"first advance reveals full current line")
 check(panel.debug_snapshot().active_voices==0 and panel._bleeps_played==start,"fast reveal cancels audio without burst")
 panel._process(8.0)
 check(panel._bleeps_played==start,"revealed line has no delayed bleeps")
 panel.advance();check(panel._line_index==1 and panel._right_expression=="pleased","next advance changes speaker and expression")
 check(panel._left_portrait.modulate.r<panel._right_portrait.modulate.r,"inactive portrait is muted")
 panel.advance();panel.advance()
 check(not panel.is_open() and completed.back()==["test",false],"final line ends conversation exactly once")
 check(focus.has_focus(),"safe original focus restored")
 var count:int=completed.size();panel.close();panel.cancel();panel.advance()
 check(completed.size()==count,"repeated close/cancel cannot emit duplicate completion")
 panel.begin(convo("old"));panel.set_process(false);panel._process(0.10)
 var old_tween:WeakRef=weakref(panel._entrance_tween)
 panel.begin(convo("new"),{}, {"reduced_motion":true});panel.set_process(false)
 check(panel._conversation.id=="new" and panel._line_index==0 and panel.debug_snapshot().active_voices==0,"newer begin replaces text and stops old sounds")
 check(completed.size()==count,"replacing dialogue does not falsely mark old dialogue seen")
 await settle();check(old_tween.get_ref()==null,"interrupted entrance Tween is released")
 panel.skip_conversation()
 check(completed.back()==["new",true] and not panel.is_open(),"Esc-style skip reports new ID and stops presentation")
 panel.begin(convo("silent"," 。 ，！ ? …\n"),{}, {"reduced_motion":true});panel.set_process(false);start=panel._bleeps_played
 for i in 40:panel._process(0.06)
 check(panel._bleeps_played==start,"punctuation-only line emits no sounds")
 panel.cancel(false);check(completed.back()==["new",true],"silent cancel emits no false finish")
 panel.begin(convo("pool","声音测试声音测试声音测试声音测试声音测试声音测试"),{}, {"reduced_motion":true});panel.set_process(false)
 start=panel._bleeps_played;panel._process(100.0)
 check(panel._bleeps_played-start<=1 and panel._visible_chars<=3,"stalled frame cannot generate catch-up audio burst")
 for i in 100:panel._play_bleep()
 check(panel._voices.size()==3 and panel.debug_snapshot().active_voices<=3,"voice pool stays bounded after rapid audio calls")
 panel.set_audio(0.55,true);check(panel.debug_snapshot().active_voices==0,"muting cancels active syllables immediately")
 start=panel._bleeps_played;panel._play_bleep();check(panel._bleeps_played==start,"muted audio cannot restart")
 panel.set_audio(0.0,false);panel._play_bleep();check(panel._bleeps_played==start,"zero volume is fully silent")
 panel.set_audio(1.5,false);check(panel.audio_volume==1.0,"volume clamps safely")
 panel.skip_conversation();check(panel.debug_snapshot().queued_bleeps==0 and panel.debug_snapshot().active_voices==0,"skip cancels all audio with zero scheduled queue")
 paused=true;panel.begin(convo("paused"),{}, {"reduced_motion":true});panel.set_process(false);check(paused,"opening retains existing pause")
 panel.close();check(paused,"closing retains existing pause");paused=false
 focus.queue_free();await settle();panel.begin(convo("missingfocus"),{}, {"reduced_motion":true});panel.close()
 check(not panel.is_open(),"removed previous focus is handled safely")
func test_input() -> void:
 var probe:=InputProbe.new();root.add_child(probe)
 panel.begin(convo("keys"),{}, {"reduced_motion":true});panel.set_process(false)
 for key in [KEY_W,KEY_LEFT,KEY_P,KEY_SHIFT]:
  var event:=InputEventKey.new();event.keycode=key;event.pressed=true;Input.parse_input_event(event);await settle(1)
 check(probe.key_count==0,"modal consumes gameplay keys before unhandled gameplay handlers")
 var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;Input.parse_input_event(enter);await settle()
 check(panel._body.visible_characters==-1,"synthetic Enter reveals line")
 enter.echo=true;Input.parse_input_event(enter);await settle()
 check(panel._line_index==0,"keyboard repeat does not fast-forward multiple lines")
 var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;Input.parse_input_event(escape);await settle()
 check(not panel.is_open() and probe.key_count==0,"synthetic Escape closes without leaking pause input")
 probe.queue_free()
func test_portraits() -> void:
 var state:=Stories.initial_state()
 for id in Stories.IDS:
  var actor:=Stories.actor_metadata(state.roster[id])
  panel.begin(convo("portrait_"+id),actor,{"reduced_motion":true});panel.set_process(false)
  for expression in ["neutral","pleased","concerned"]:
   var texture:Texture2D=panel._npc_texture(expression)
   check(texture!=null and texture.resource_path==actor.portraits[expression],"actual portrait loaded without fallback: "+id+"/"+expression)
   check(texture!=null and texture.get_size()==Vector2(512,512),"registered 512px portrait canvas: "+id+"/"+expression)
 panel.cancel(false)
func check_nameplate(npc:bool,context:String) -> void:
 var portrait:TextureRect=panel._left_portrait if npc else panel._right_portrait
 var label_rect:Rect2=panel._name.get_global_rect()
 var portrait_rect:Rect2=portrait.get_global_rect()
 check(panel._name.is_visible_in_tree() and panel._npc_speaking==npc,"visible nameplate matches active speaker: "+context)
 check(is_equal_approx(label_rect.get_center().x,portrait_rect.get_center().x),"nameplate is centered beneath its own portrait: "+context)
 check(label_rect.position.x>=portrait_rect.position.x and label_rect.end.x<=portrait_rect.end.x,"nameplate stays inside speaking portrait column: "+context)
 check(root.get_visible_rect().encloses(label_rect),"nameplate stays inside viewport: "+context)
 check(not label_rect.intersects(panel._body.get_global_rect()) and not label_rect.intersects(panel._counter.get_global_rect()) and not label_rect.intersects(panel._continue.get_global_rect()),"nameplate avoids dialogue, count and button: "+context)
 check(panel._name.size.x>=panel._name.get_minimum_size().x and panel._name.size.y>=panel._name.get_minimum_size().y,"nameplate text fits its fixed footer: "+context)
 check(panel._name.text==("小禾" if npc else "店员 · 你"),"nameplate never retains the previous speaker's name: "+context)
func test_nameplates() -> void:
 var actor:=Stories.actor_metadata(Stories.initial_state().roster.human_courier)
 var original_size:Vector2i=root.size
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 for extent in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
  root.size=extent;await settle()
  var context:String=str(extent)
  panel.begin(convo("nameplate"),actor,{"reduced_motion":true});panel.set_process(false)
  check_nameplate(true,"NPC begin "+context)
  var npc_rect:Rect2=panel._name.get_global_rect();panel.advance()
  check(panel._name.get_global_rect()==npc_rect and panel._name.text=="小禾","fast reveal keeps NPC nameplate attached: "+context)
  panel.advance();check_nameplate(false,"clerk next "+context)
  var clerk_rect:Rect2=panel._name.get_global_rect();panel.advance()
  check(panel._name.get_global_rect()==clerk_rect and panel._name.text=="店员 · 你","fast reveal keeps clerk nameplate attached: "+context)
  root.size=Vector2i(1600,900);await settle();check_nameplate(false,"clerk live resize from "+context)
  root.size=extent;await settle();check_nameplate(false,"clerk resize back "+context)
  panel.skip_conversation()
  check(not panel._name.visible and panel._name.text.is_empty(),"skip clears the previous speaker label: "+context)
  var clerk_first:Dictionary=convo("clerk_first");clerk_first.lines.reverse()
  panel.begin(clerk_first,actor,{"reduced_motion":true});panel.set_process(false)
  check_nameplate(false,"clerk-first restart "+context)
  panel.begin(convo("replacement"),actor,{"reduced_motion":true});panel.set_process(false)
  check_nameplate(true,"NPC replacement begin "+context)
  panel.cancel(false)
 # A future longer display name cannot grow into the counter or dialogue text.
 actor.name="晨星社区快递服务站的来访者"
 panel.begin(convo("long_name","今天这份包裹需要先送到晨星社区，再转交星港中转站。请按原来的路线飞行，途中记得查看货物完整度，平安回来。"),actor,{"reduced_motion":true});panel.set_process(false);panel.advance();await settle()
 check(panel._name.size==DialoguePanel.NAMEPLATE_SIZE and panel._name.clip_text,"long names stay bounded within the portrait footer")
 check(panel._body.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART and panel._body.get_line_count()>1,"long dialogue still wraps across the full textbox")
 check(not panel._name.get_global_rect().intersects(panel._body.get_global_rect()) and not panel._body.get_global_rect().intersects(panel._continue.get_global_rect()),"wrapped dialogue remains clear of nameplate and continue control")
 panel.cancel(false);root.size=original_size;await settle()
func test_tweens() -> void:
 var refs:Array=[]
 for i in 96:
  panel.begin(convo("replace%d"%i));refs.append(weakref(panel._entrance_tween))
 panel.cancel(false);await settle()
 check(retained(refs)==0,"96 rapidly replaced entrance Tweens are all released")
 refs.clear()
 for i in 96:
  panel.begin(convo("finish%d"%i));refs.append(weakref(panel._entrance_tween));panel._entrance_tween.custom_step(0.2)
 panel.cancel(false);await settle()
 check(retained(refs)==0,"96 naturally completed entrance Tweens are all released")
func run() -> void:
 test_state();test_characters();test_expression()
 focus=Button.new();focus.text="Underlying focus";focus.position=Vector2(0,0);focus.size=Vector2(240,60);root.add_child(focus)
 panel=DialoguePanel.new();root.add_child(panel);panel.finished.connect(_finish);panel.modal_changed.connect(_modal)
 await settle();await test_modal();await test_input();test_portraits();await test_nameplates();await test_tweens()
 panel.begin(convo("free"));panel._process(0.1)
 var ref:WeakRef=weakref(panel);panel.queue_free();await settle(5)
 check(ref.get_ref()==null,"freeing an open speaking panel releases the node")
 await create_timer(0.15).timeout # Allow the audio mix thread to release stopped playback references.
 print("COURIER_DIALOGUE_TESTS ",passed," passed, ",failed," failed")
 quit(1 if failed>0 else 0)
