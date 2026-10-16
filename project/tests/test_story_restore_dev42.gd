extends SceneTree
const S=preload("res://scripts/courier_stories.gd")
var passed=0
var failed=0
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1;push_error(label)
func _initialize():
 for profile in [S.DELIVERY_CHAPTER_ROUTE_PROFILE,S.DELIVERY_ASCENT_ROUTE_PROFILE,S.DELIVERY_RIFT_ROUTE_PROFILE]:
  for actor in S.IDS:
   var order={"contract_id":"story-proof", "status":"accepted","appearance_id":actor,"control_version":"pilot-delivery-v8","cargo":"物理运输箱","route_profile":profile,"route_kind":"ground" if profile==S.DELIVERY_CHAPTER_ROUTE_PROFILE else ("ascent" if profile==S.DELIVERY_ASCENT_ROUTE_PROFILE else "rift"),"destination_id":"chapter-1-level-1" if profile==S.DELIVERY_CHAPTER_ROUTE_PROFILE else ("moon-proof" if profile==S.DELIVERY_ASCENT_ROUTE_PROFILE else "rift-greenhouse-receiver-v1"),"name":"已冻结路线","destination_name":"已冻结收件站","min_delivery_integrity":0.8}
   var state=S.bind_contract(S.initial_state(42),order,1).state
   var before=JSON.stringify(order)
   var accept=S.conversation_for(state,order,"accept")
   var original=old_lines(profile,actor,"accept",true)
   check(accept.lines.slice(1)==original,"original accept preserved "+actor+profile)
   check(str(accept.lines[0].text).contains("物理运输箱") and str(accept.lines[0].text).contains(S.PROFILES[actor].cargo),"cargo distinction")
   check(JSON.stringify(order)==before,"contract unchanged")
   var seen=S.mark_seen(state,"story-proof","story-proof/accept")
   check(S.conversation_for(seen,order,"accept").is_empty(),"seen not replayed")
   order.status="settled"
   for success in [true,false]:
    var committed=S.commit_settlement(state,order,{"contract_id":"story-proof","success":success}).state
    for beat in ["result","return"]:
     check(S.conversation_for(committed,order,beat).lines==old_lines(profile,actor,beat,success),"original receipt/return preserved")
 # Optional genuine campaign save, read-only original, isolated user directory.
 if not OS.get_environment("SC_NATIVE_D3").is_empty():
  var bytes=FileAccess.get_file_as_bytes(OS.get_environment("SC_NATIVE_D3"))
  var raw:Dictionary=JSON.parse_string(bytes.get_string_from_utf8())
  var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
  var e=load("res://scripts/economy.gd").new();e.load_state();e.enable_story_mode()
  check(not e.review_load_blocked,"genuine old campaign loads")
  check(e.close_day_and_save(raw.design,raw.launcher,raw.settings).ok and e.next_day_and_save(raw.design,raw.launcher,raw.settings).ok,"normal next day from old campaign")
  check(e.accept_contract_and_save("D4-A",raw.design,raw.launcher,raw.settings).ok,"normal next order accepted")
  var conv=e.story_conversation("D4-A","accept")
  check(conv.lines.size()>=3 and str(conv.lines).contains("月面窗边"),"old campaign next order original moon arc")
  print("OLD_CAMPAIGN_NEXT_ORDER ",JSON.stringify(conv))
 print("STORY_RESTORE_DEV42 passed=",passed," failed=",failed," original_helpers=true native=false")
 quit(1 if failed else 0)
func old_lines(profile:String,actor:String,beat:String,success:bool)->Array:
 if profile==S.DELIVERY_ASCENT_ROUTE_PROFILE:return S._moon_lines(actor,beat,success,0,"已冻结收件站")
 if profile==S.DELIVERY_RIFT_ROUTE_PROFILE:return S._otherworld_lines(actor,beat,success,0,"已冻结收件站")
 return S._ground_lines(actor,beat,success,0,"已冻结收件站")
