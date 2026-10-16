extends RefCounted
## Explicit, value-conserving retirement. Pure preview; detached transaction.
## Inventory is TOTAL owned, including installed modules (Main._installed_count).
## Blueprint copies describe arrangements; they are never extra property.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Values=preload("res://scripts/pilot_protected_bird_profile.gd")
# Historical receipts retain their original, exact control rewrite semantics.
const LEGACY_SCHEMA:String="mechanical-parts-retirement-v2"
const SCHEMA:String="mechanical-parts-retirement-v3"
const FIELD:String="parts_retirement"
const MARKER:String="parts_retirement_schema"
const SAFE_INT:int=9007199254740991
const MANUAL:Array[String]=["teleporter","splitter","coupler","accelerator"]

static func preview(snapshot:Dictionary) -> Dictionary:
 var error:String=receipt_error(snapshot)
 if not error.is_empty():return _error(error)
 if snapshot.has(FIELD):return {"ok":true,"changed":false,"duplicate":true}
 if not snapshot.get("in_flight",{}) is Dictionary:return _error("invalid_in_flight")
 if not snapshot.get("in_flight",{}).is_empty():return {"ok":true,"changed":false,"deferred":true,"reason":"in_flight"}
 if not snapshot.get("contracts",[]) is Array:return _error("invalid_contracts")
 if not snapshot.get("active_contract_id","") is String:return _error("invalid_active_contract_id")
 var active:String=snapshot.get("active_contract_id","")
 var contract_ids:Dictionary={};var active_found:bool=active.is_empty();var defer_legacy:bool=false
 for order in snapshot.get("contracts",[]):
  if not order is Dictionary or not order.get("contract_id") is String or str(order.contract_id).is_empty() or not order.get("status") is String:return _error("invalid_contract")
  if order.status not in ["available","accepted","in_flight","settled","declined","cancelled"]:return _error("invalid_contract_status")
  if order.has("control_version") and not order.control_version is String:return _error("invalid_contract_version")
  if contract_ids.has(order.contract_id):return _error("duplicate_contract_id")
  contract_ids[order.contract_id]=true
  # Nonempty snapshots were deferred above without touching replay bytes.
  # A contract cannot still be flying when that authoritative wrapper is empty.
  if order.status=="in_flight":return _error("in_flight_contract_missing_snapshot")
  if order.status=="accepted" and order.contract_id!=active:return _error("accepted_contract_not_active")
  if order.contract_id==active:
   active_found=true
   if order.status!="accepted":return _error("active_contract_not_accepted")
   if order.get("control_version")!="pilot-free-v2":defer_legacy=true
 if not active_found:return _error("active_contract_missing")
 if defer_legacy:return {"ok":true,"changed":false,"deferred":true,"reason":"accepted_legacy_order"}
 if not _integer(snapshot.get("credits"),-SAFE_INT,SAFE_INT):return _error("invalid_credits")
 for key in ["inventory","designs","settings"]:
  if not snapshot.get(key,{}) is Dictionary:return _error("invalid_"+key)
 for key in ["design","launcher"]:
  if not snapshot.get(key) is Array:return _error("invalid_"+key)
 var catalog:Dictionary=Parts.catalog();var inventory:Dictionary=snapshot.get("inventory",{})
 var before:Dictionary=_asset_ledger(inventory,int(snapshot.credits))
 if not before.ok:return before
 var current_ids:Dictionary={};var installed:Dictionary={}
 for key in ["design","launcher"]:
  var design_error:String=_design_error(snapshot[key],current_ids)
  if not design_error.is_empty():return _error(design_error)
  for p in snapshot[key]:
   if p.type!="cargo":installed[p.type]=int(installed.get(p.type,0))+1
 for kind in installed:
  if int(installed[kind])>int(inventory.get(kind,0)):return _error("installed_exceeds_total_owned:"+kind)
 var candidate:Dictionary=snapshot.duplicate(true)
 var after_inventory:Dictionary=inventory.duplicate(true)
 var converted:Dictionary={};var changes:Array=[];var controls:Array=[]
 # Retire the owned total ONCE, including installed pieces. Designs below only
 # change references, never refund a second time for an installed/blueprint copy.
 for kind in inventory:
  if kind=="cargo" or Policy.is_core(str(kind)):continue
  var count:int=int(inventory[kind])
  if count>0:converted[kind]=count
  after_inventory.erase(kind)
 var blueprint_error:String=""
 for key in ["design","launcher"]:
  _convert_design(candidate[key],key=="launcher",key,changes,controls,converted,true)
 for name in candidate.get("designs",{}):
  if not name is String or name.is_empty():return _error("invalid_blueprint_name")
  var blueprint:Variant=candidate.designs[name]
  if not blueprint is Dictionary:return _error("invalid_blueprint:"+str(name))
  var blueprint_ids:Dictionary={}
  for key in ["design","launcher"]:
   if not blueprint.get(key) is Array:return _error("invalid_blueprint_"+key+":"+str(name))
   blueprint_error=_design_error(blueprint[key],blueprint_ids)
   if not blueprint_error.is_empty():return _error(blueprint_error)
   _convert_design(blueprint[key],key=="launcher","blueprint:"+str(name)+":"+key,changes,controls,{},false)
 var delta:int=0;var new_beams:int=0
 for kind in converted:
  var count:int=int(converted[kind]);var unit_price:int=int(catalog[kind].price)
  if Policy.is_core(str(kind)):
   if count>int(after_inventory.get(kind,0)):return _error("context_conversion_exceeds_total_owned:"+kind)
   after_inventory[kind]=int(after_inventory[kind])-count
   if int(after_inventory[kind])==0:after_inventory.erase(kind)
  delta+=count*(unit_price-int(catalog.beam.price));new_beams+=count
 if int(snapshot.credits)>SAFE_INT-delta:return _error("credit_overflow")
 if new_beams>0:after_inventory["beam"]=int(after_inventory.get("beam",0))+new_beams
 candidate.inventory=after_inventory;candidate.credits=int(snapshot.credits)+delta
 var after:Dictionary=_asset_ledger(after_inventory,int(candidate.credits))
 if not after.ok:return after
 if before.total_value!=after.total_value:return _error("asset_value_mismatch")
 var changed:bool=not changes.is_empty() or not controls.is_empty() or not Values.same_value(inventory,after_inventory)
 var plan:Dictionary={"ok":true,"changed":changed,"before":before,"after":after,"credit_delta":delta,"converted_owned":converted,"placements":changes,"controls":controls,"candidate":candidate}
 plan.confirmation_token=_hash({"schema":SCHEMA,"source":snapshot,"converted_owned":converted,"placements":changes,"controls":controls,"after":after})
 plan.message="整理 %d 件旧零件为结构梁，补回差价 ¥%d。现有位置和编号保留；旧信号改为直接控制，原存档另行备份。"%[new_beams,delta]
 return plan

static func _convert_design(items:Array,launcher:bool,path:String,changes:Array,controls:Array,converted:Dictionary,count_owned:bool) -> void:
 for p in items:
  var kind:String=str(p.type)
  if kind=="cargo" or Policy.compatible(kind,launcher):continue
  # Retired global inventory already counted above. Context-only conversions
  # (for example spring installed on a ship) use the owned active count only.
  if count_owned and Policy.is_core(kind):converted[kind]=int(converted.get(kind,0))+1
  var prior:Dictionary=p.duplicate(true)
  p.type="beam";p.param=Parts.defaults("beam");p.input_a=-1;p.input_b=-1;p.target=-1
  changes.append({"path":path,"id":int(p.id),"before":prior,"after":p.duplicate(true)})
 for p in items:
  if p.type=="cargo":continue
  var prior:Dictionary=p.duplicate(true)
  # New workshop has no signal wiring panel. Retire the old wiring explicitly,
  # including surviving mechanical chains, without changing frozen snapshots.
  p.input_b=-1
  p.input_a=_retired_input_a(p,launcher,SCHEMA)
  if p.type=="damper":p.target=-1 # New passive spin damper cannot tether remote bodies.
  if launcher and p.type in ["spring","accelerator"]:p.target=-1
  if not Values.same_value(p,prior):controls.append({"path":path,"id":int(p.id),"before":prior,"after":p.duplicate(true)})

## v3 preserves an explicitly held craft drill. Automatic remains automatic;
## old external wiring still retires to automatic. v2 receipts must continue
## validating the historical forced-auto result, even for a held source drill.
static func _retired_input_a(part:Dictionary,launcher:bool,schema:String) -> int:
 if schema==SCHEMA and not launcher and part.type=="drill" and int(part.input_a)==-2:return -2
 return -2 if not launcher and str(part.type) in MANUAL else -1

## Persist callback must atomically save the complete candidate, using Economy's
## existing staged primary commit. It must report success only after commit and
## must not mutate live aliases on failure. Main swaps aliases only on ok=true.
static func transaction(snapshot:Dictionary,confirmation_token:String,backup:Callable,persist:Callable) -> Dictionary:
 var plan:Dictionary=preview(snapshot)
 if not plan.ok or not bool(plan.get("changed",false)):return plan
 if confirmation_token.is_empty() or confirmation_token!=str(plan.confirmation_token):return _error("confirmation_stale_or_missing")
 if not backup.is_valid() or not persist.is_valid():return _error("transaction_callbacks_missing")
 var backed:Variant=backup.call(snapshot.duplicate(true))
 if not backed is Dictionary or not bool(backed.get("ok",false)):return _error("raw_backup_failed")
 var source_sha:String=str(backed.get("source_sha256",""))
 if not _sha(source_sha):return _error("raw_backup_hash_missing")
 var candidate:Dictionary=plan.candidate.duplicate(true)
 var receipt:Dictionary={"schema":SCHEMA,"source_sha256":source_sha,"confirmation_token":confirmation_token,"credit_delta":plan.credit_delta,"before":plan.before,"after":plan.after,"converted_owned":plan.converted_owned.duplicate(true),"placements":plan.placements.duplicate(true),"controls":plan.controls.duplicate(true)}
 candidate[FIELD]=receipt
 if not candidate.has("settings"):candidate.settings={}
 candidate.settings[MARKER]=SCHEMA
 var error:String=receipt_error(candidate)
 if not error.is_empty():return _error(error)
 var saved:Variant=persist.call(candidate.duplicate(true))
 if not saved is Dictionary or not bool(saved.get("ok",false)):return _error("atomic_save_failed")
 return {"ok":true,"changed":true,"candidate":candidate,"receipt":receipt,"before":plan.before,"after":plan.after,"message":plan.message}

## Production backup seam. Only call inside the explicitly confirmed transaction.
## Archive includes byte-for-byte original primary and previous backup. Retry
## verifies existing bytes; never overwrites an earlier archive.
static func archive_raw_slots(snapshot:Dictionary,source_path:String,primary_path:String,backup_path:String,archive_root:String) -> Dictionary:
 var source:Dictionary=_read_bytes(source_path)
 if not source.ok:return source
 var parsed:Variant=JSON.parse_string(source.bytes.get_string_from_utf8())
 if not parsed is Dictionary or _hash(parsed)!=_hash(snapshot):return _error("source_changed_reload_required")
 # Receipt identity is the actual file SHA256, not a reserialized document.
 var source_sha:String=FileAccess.get_sha256(source_path)
 var hasher=HashingContext.new();hasher.start(HashingContext.HASH_SHA256);hasher.update(source.bytes)
 if not _sha(source_sha) or hasher.finish().hex_encode()!=source_sha:return _error("source_changed_reload_required")
 var folder:String=archive_root.path_join(source_sha)
 if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder)!=OK:return _error("archive_directory_failed")
 for row in [["source.json",source_path],["savegame.json",primary_path],["savegame.backup.json",backup_path]]:
  var path:String=str(row[1])
  if not FileAccess.file_exists(path):
   if DirAccess.dir_exists_absolute(path):return _error("archive_input_is_directory")
   continue
  var original:Dictionary=_read_bytes(path)
  if not original.ok:return original
  var target:String=folder.path_join(str(row[0]))
  if FileAccess.file_exists(target):
   var existing:Dictionary=_read_bytes(target)
   if not existing.ok or existing.bytes!=original.bytes:return _error("archive_conflict")
   continue
  if DirAccess.dir_exists_absolute(target):return _error("archive_target_is_directory")
  var temporary:String=target+".tmp"
  var file=FileAccess.open(temporary,FileAccess.WRITE)
  if file==null:return _error("archive_open_failed")
  var stored:bool=file.store_buffer(original.bytes);file.flush();var write_error:Error=file.get_error();file.close()
  var checked:Dictionary=_read_bytes(temporary)
  if not stored or write_error!=OK or not checked.ok or checked.bytes!=original.bytes:return _error("archive_verification_failed")
  if DirAccess.rename_absolute(temporary,target)!=OK:return _error("archive_commit_failed")
  checked=_read_bytes(target)
  if not checked.ok or checked.bytes!=original.bytes:return _error("archive_commit_verification_failed")
 var rechecked:Dictionary=_read_bytes(source_path)
 var archived_source:Dictionary=_read_bytes(folder.path_join("source.json"))
 if not rechecked.ok or rechecked.bytes!=source.bytes or not archived_source.ok or archived_source.bytes!=source.bytes:return _error("source_changed_reload_required")
 return {"ok":true,"source_sha256":source_sha,"archive_path":folder}

static func receipt_error(snapshot:Dictionary) -> String:
 var settings:Variant=snapshot.get("settings",{})
 if not settings is Dictionary:return "invalid_settings"
 var marked:bool=settings.has(MARKER)
 if marked and settings[MARKER] not in [LEGACY_SCHEMA,SCHEMA]:return "unknown_parts_retirement_marker"
 if not snapshot.has(FIELD):return "parts_retirement_receipt_missing" if marked else ""
 if not marked:return "parts_retirement_marker_missing"
 var receipt:Variant=snapshot[FIELD]
 if not receipt is Dictionary:return "invalid_parts_retirement_receipt"
 if receipt.size()!=9 or receipt.get("schema") not in [LEGACY_SCHEMA,SCHEMA]:return "invalid_parts_retirement_schema"
 if settings[MARKER]!=receipt.schema:return "parts_retirement_schema_mismatch"
 for key in ["source_sha256","confirmation_token"]:
  if not _sha(str(receipt.get(key,""))):return "invalid_parts_retirement_hash"
 if not _integer(receipt.get("credit_delta"),0,SAFE_INT):return "invalid_parts_retirement_delta"
 for key in ["before","after","converted_owned"]:
  if not receipt.get(key) is Dictionary:return "invalid_parts_retirement_ledger"
 for key in ["placements","controls"]:
  if not receipt.get(key) is Array:return "invalid_parts_retirement_changes"
 for key in ["before","after"]:
  var ledger:Dictionary=receipt[key]
  if not ledger.get("inventory") is Dictionary or not _integer(ledger.get("credits"),-SAFE_INT,SAFE_INT):return "invalid_parts_retirement_ledger"
  var expected:Dictionary=_asset_ledger(ledger.inventory,int(ledger.credits))
  if not expected.ok or not Values.same_value(expected,ledger):return "incoherent_parts_retirement_ledger"
 if receipt.before.total_value!=receipt.after.total_value:return "parts_retirement_value_lost"
 if int(receipt.after.credits)-int(receipt.before.credits)!=int(receipt.credit_delta):return "parts_retirement_credit_mismatch"
 var expected_inventory:Dictionary=receipt.before.inventory.duplicate(true)
 var delta:int=0;var count:int=0
 for kind in receipt.converted_owned:
  if not Parts.catalog().has(kind) or not _integer(receipt.converted_owned[kind],1,SAFE_INT):return "invalid_parts_retirement_conversion"
  var amount:int=int(receipt.converted_owned[kind])
  if amount>int(expected_inventory.get(kind,0)):return "parts_retirement_double_refund"
  expected_inventory[kind]=int(expected_inventory[kind])-amount
  if int(expected_inventory[kind])==0:expected_inventory.erase(kind)
  delta+=amount*(int(Parts.catalog()[kind].price)-int(Parts.catalog().beam.price));count+=amount
 # Legacy zero-count keys are also removed without a conversion/payment.
 for kind in expected_inventory.keys():
  if kind!="cargo" and not Policy.is_core(str(kind)) and int(expected_inventory[kind])==0:expected_inventory.erase(kind)
 if count>0:expected_inventory["beam"]=int(expected_inventory.get("beam",0))+count
 if delta!=int(receipt.credit_delta) or not Values.same_value(expected_inventory,receipt.after.inventory):return "parts_retirement_conversion_mismatch"
 for kind in receipt.after.inventory:
  if kind!="cargo" and not Policy.is_core(str(kind)):return "parts_retirement_legacy_inventory_remains"
 var changed_rows:Dictionary={};var active_converted:Dictionary={}
 for key in ["placements","controls"]:
  for row in receipt[key]:
   if not row is Dictionary or row.size()!=4 or not row.get("path") is String or not _integer(row.get("id"),0,SAFE_INT):return "invalid_parts_retirement_change"
   if not row.get("before") is Dictionary or not row.get("after") is Dictionary:return "invalid_parts_retirement_change"
   if not _design_error([row.before],{}).is_empty() or not _design_error([row.after],{}).is_empty():return "invalid_parts_retirement_change"
   if int(row.before.id)!=int(row.id) or int(row.after.id)!=int(row.id):return "parts_retirement_id_changed"
   for coordinate in ["x","y","rot"]:
    if row.before.get(coordinate)!=row.after.get(coordinate):return "parts_retirement_placement_changed"
   var context:Dictionary=_path_context(str(row.path))
   if context.is_empty():return "invalid_parts_retirement_path"
   var launcher:bool=bool(context.launcher)
   var identity:String=row.path+":"+str(row.id)
   if changed_rows.has(identity):return "duplicate_parts_retirement_change"
   changed_rows[identity]=true
   var expected:Dictionary=row.before.duplicate(true)
   if key=="placements":
    if row.before.type=="cargo" or Policy.compatible(str(row.before.type),launcher):return "unexpected_parts_retirement_conversion"
    if not bool(context.blueprint):active_converted[row.before.type]=int(active_converted.get(row.before.type,0))+1
    expected.type="beam";expected.param=Parts.defaults("beam");expected.input_a=-1;expected.input_b=-1;expected.target=-1
   else:
    if row.before.type!=row.after.type or row.before.type=="cargo" or not Policy.compatible(str(row.before.type),launcher):return "parts_retirement_control_type_changed"
    expected.input_a=_retired_input_a(expected,launcher,str(receipt.schema))
    expected.input_b=-1
    if expected.type=="damper" or (launcher and expected.type in ["spring","accelerator"]):expected.target=-1
   if not Values.same_value(expected,row.after) or Values.same_value(row.before,row.after):return "incoherent_parts_retirement_change"
 for kind in receipt.converted_owned:
  var owned_count:int=int(receipt.converted_owned[kind]);var installed_count:int=int(active_converted.get(kind,0))
  if Policy.is_core(str(kind)) and owned_count!=installed_count:return "parts_retirement_context_count_mismatch"
  if not Policy.is_core(str(kind)) and owned_count!=int(receipt.before.inventory.get(kind,0)):return "parts_retirement_retired_total_mismatch"
  if installed_count>owned_count:return "parts_retirement_installed_double_count"
 for kind in active_converted:
  if not receipt.converted_owned.has(kind):return "parts_retirement_owned_conversion_missing"
 return ""

static func _path_context(path:String) -> Dictionary:
 if path in ["design","launcher"]:return {"launcher":path=="launcher","blueprint":false}
 if not path.begins_with("blueprint:"):return {}
 for suffix in [":design",":launcher"]:
  if path.ends_with(suffix) and path.length()>"blueprint:".length()+suffix.length():return {"launcher":suffix==":launcher","blueprint":true}
 return {}

static func _design_error(items:Array,ids:Dictionary) -> String:
 var cells:Dictionary={}
 for p in items:
  if not p is Dictionary or p.size()!=9 or not p.get("type") is String or not _integer(p.get("id"),0,SAFE_INT):return "invalid_installed_part"
  for key in ["id","type","x","y","rot","param","input_a","input_b","target"]:
   if not p.has(key):return "invalid_installed_part_fields"
  if p.type!="cargo" and not Parts.catalog().has(p.type):return "unknown_part_preserved"
  if ids.has(int(p.id)):return "duplicate_installed_id"
  ids[int(p.id)]=true
  for axis in ["x","y"]:
   if not _integer(p.get(axis),-SAFE_INT,SAFE_INT):return "invalid_installed_coordinate"
  var cell:String=str(int(p.x))+":"+str(int(p.y))
  if cells.has(cell):return "duplicate_installed_cell"
  cells[cell]=true
  if not _integer(p.rot,0,3):return "invalid_installed_rotation"
  if not (p.param is int or p.param is float) or not is_finite(float(p.param)):return "invalid_installed_parameter"
  if Parts.sanitize_parameter(str(p.type),p.param)!=float(p.param):return "out_of_range_installed_parameter"
  for wire in ["input_a","input_b"]:
   if not _integer(p[wire],-2,SAFE_INT):return "invalid_installed_input"
  if not _integer(p.target,-1,SAFE_INT):return "invalid_installed_target"
 return ""
static func _asset_ledger(inventory:Dictionary,credits:int) -> Dictionary:
 var value:int=0;var catalog:Dictionary=Parts.catalog()
 for kind in inventory:
  if not kind is String or not _integer(inventory[kind],0,1000000):
   var failure:Dictionary=_error("invalid_inventory_quantity")
   failure.key=str(kind);failure.key_type=type_string(typeof(kind));failure.quantity_type=type_string(typeof(inventory[kind]));failure.quantity=inventory[kind]
   return failure
  if kind=="cargo":continue
  if not catalog.has(kind):return _error("unknown_inventory_preserved")
  value+=int(inventory[kind])*int(catalog[kind].price)
 if credits>SAFE_INT-value:return _error("asset_value_overflow")
 return {"ok":true,"credits":credits,"inventory":inventory.duplicate(true),"parts_value":value,"total_value":credits+value}
static func _read_bytes(path:String) -> Dictionary:
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:return _error("raw_read_failed")
 var size:int=file.get_length();var bytes:PackedByteArray=file.get_buffer(size);var error:Error=file.get_error();file.close()
 if error!=OK or bytes.size()!=size:return _error("raw_read_incomplete")
 return {"ok":true,"bytes":bytes}
static func _integer(value:Variant,minimum:int,maximum:int) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=minimum and float(value)<=maximum
static func _sha(value:String) -> bool:
 if value.length()!=64:return false
 for character in value:
  if not character in "0123456789abcdef":return false
 return true
static func _hash(value:Variant) -> String:return JSON.stringify(value,"",true,true).sha256_text()
static func _error(reason:String) -> Dictionary:return {"ok":false,"changed":false,"reason":reason}
