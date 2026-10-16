extends SceneTree
## Byte-for-byte retained native-run saves, not reconstructed success fixtures.
## Source paths and SHA-256 provenance are retained alongside these files.
const Econ=preload("res://scripts/economy.gd")
const Reviews=preload("res://scripts/customer_reviews.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func _initialize():
 var base:String="res://tests/fixtures/recovery_integrity/"
 var manifest:Array=JSON.parse_string(FileAccess.get_file_as_string(base+"provenance.json"))
 for fixture in manifest:
  var path:String=base+fixture.file;var bytes:String=FileAccess.get_file_as_string(path);var raw:Dictionary=JSON.parse_string(bytes)
  check(bytes.sha256_text()==fixture.sha256,"retained fixture hash: "+fixture.file)
  for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:DirAccess.remove_absolute("user://"+file)
  var writer=FileAccess.open("user://savegame.json",FileAccess.WRITE);writer.store_string(bytes);writer.close()
  var economy=Econ.new();check(economy._valid_save(raw),"saved economy validates actual native fixture: "+fixture.file)
  var loaded:Dictionary=economy.load_state()
  check(not loaded.is_empty() and not economy.review_load_blocked and economy.day==int(fixture.day),"load native saved day: "+fixture.file)
  check(economy.credits==int(raw.credits) and economy.settled_ids==raw.settled_ids,"load preserves real money and receipts: "+fixture.file)
  check(FileAccess.get_file_as_string("user://savegame.json")==bytes and not FileAccess.file_exists("user://savegame.tmp"),"load leaves retained bytes unchanged: "+fixture.file)
  if not raw.has("review_state"):
   check(economy.review_state.pending.is_empty() and economy.customer_reviews().is_empty(),"pre-review native receipt creates no retrospective reviews: "+fixture.file)
  else:
   var expected:Dictionary=Reviews.normalize_state(raw.review_state,int(raw.day)).state
   check(economy.review_state==expected,"old review-era facts retain established int/float normalization: "+fixture.file)
   for i in raw.review_state.published.size():check(economy.customer_reviews()[i].body==raw.review_state.published[i].body,"historical body stays byte-identical: "+fixture.file)
 print("RECOVERY_INTEGRITY_FIXTURES passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
