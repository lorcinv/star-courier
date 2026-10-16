extends "res://tests/test_parts_retirement_economy_v2.gd"
## Diagnostic successor; original fixture/assertions are unchanged.
class Diagnostic extends "res://scripts/economy.gd":
 func _persist_transition_snapshot(candidate:Dictionary) -> Dictionary:
  var roundtrip:Dictionary=JSON.parse_string(JSON.stringify(candidate,"",true,true))
  print("PARTS_PERSIST_DIAGNOSTIC ",JSON.stringify({"source_unchanged":_transition_source_unchanged(),"candidate_valid":_valid_save(candidate),"candidate_structural":_valid_save(candidate,false),"candidate_parts_error":PartsMigration.receipt_error(candidate),"roundtrip_valid":_valid_save(roundtrip),"roundtrip_parts_error":PartsMigration.receipt_error(roundtrip),"presentation_error":presentation_state_error(candidate)},"",true,true))
  var result:Dictionary=super._persist_transition_snapshot(candidate)
  print("PARTS_PERSIST_RESULT ",JSON.stringify({"result":result,"save_error":save_error,"temp_exists":FileAccess.file_exists("user://savegame.tmp"),"temp_parts_error":PartsMigration.receipt_error(_read_save("user://savegame.tmp")) if FileAccess.file_exists("user://savegame.tmp") else "absent"},"",true,true))
  return result
func _initialize() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 var e=fixture();var result:Dictionary=confirm(e,preview(e));print("PARTS_TRANSACTION_RESULT ",JSON.stringify(result,"",true,true));quit(0)
func fixture():
 clean();craft=Old.starter_design();pad=Old.starter_launcher()
 craft.append({"id":901,"type":"probe","x":4,"y":2,"rot":1,"param":Parts.defaults("probe"),"input_a":-1,"input_b":-1,"target":-1})
 var e=Diagnostic.new();e.enable_free_mode();e.starter_stock(craft,pad)
 e.inventory["probe"]=2;e.inventory["not_gate"]=3
 e.designs={"copy":{"design":craft.duplicate(true),"launcher":pad.duplicate(true)}}
 check(e.save_state(craft,pad,{}),"diagnostic durable primary")
 e.credits+=1;check(e.save_state(craft,pad,{}),"diagnostic durable previous backup")
 return e
