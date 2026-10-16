extends RefCounted
## The title never calls Economy.load_state or save_state. This helper writes
## only after the player confirms New Game. Existing durable slots are never
## removed. A fresh primary replaces the old one at one atomic rename boundary.
const SLOT_NAMES:Array[String]=["savegame.json","savegame.backup.json"]
var save_root:String="user://"
var recovery_root:String="user://new-game-recovery"
var last_error:String=""

func _init(root_path:String="user://") -> void:
 save_root=root_path
 recovery_root=save_root.path_join("new-game-recovery")

func has_saved_progress() -> bool:
 for slot in SLOT_NAMES:
  var path:String=save_root.path_join(slot)
  if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):return true
 return false

func _fail(message:String) -> Dictionary:
 last_error=message
 return {"ok":false,"message":message}

func _read_bytes(path:String) -> Dictionary:
 if DirAccess.dir_exists_absolute(path):return _fail("存档路径无法读取，原记录未改变。请检查存档目录。")
 if not FileAccess.file_exists(path):return {"ok":true,"exists":false,"bytes":PackedByteArray()}
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null:return _fail("无法读取旧存档，未开始新游戏。原记录未改变。")
 var length:int=file.get_length()
 var bytes:PackedByteArray=file.get_buffer(length)
 var error:Error=file.get_error()
 file.close()
 if bytes.size()!=length or error!=OK:return _fail("旧存档读取不完整，未开始新游戏。原记录未改变。")
 return {"ok":true,"exists":true,"bytes":bytes}

func _write_verified(path:String,bytes:PackedByteArray) -> bool:
 var file:=FileAccess.open(path,FileAccess.WRITE)
 if file==null:return false
 var stored:bool=file.store_buffer(bytes)
 file.flush()
 var error:Error=file.get_error()
 file.close()
 if not stored or error!=OK:return false
 var read:Dictionary=_read_bytes(path)
 return bool(read.ok) and bool(read.get("exists",false)) and read.bytes==bytes

func prepare_new_game() -> Dictionary:
 last_error=""
 var slots:Dictionary={}
 var any_existing:bool=false
 for slot in SLOT_NAMES:
  var read:Dictionary=_read_bytes(save_root.path_join(slot))
  if not read.ok:return read
  slots[slot]=read
  any_existing=any_existing or bool(read.exists)
 var ticket:Dictionary={"ok":true,"slots":slots,"recovery_dir":"","used":false}
 if not any_existing:return ticket
 # This directory is intentionally retained, including for later failed starts.
 # It is separate from the rotating gameplay backup and contains the exact bytes
 # of corrupt or unsupported saves as well as valid saves.
 var archive:String=recovery_root.path_join("%d-%d"%[int(Time.get_unix_time_from_system()),Time.get_ticks_usec()])
 if DirAccess.dir_exists_absolute(archive) or FileAccess.file_exists(archive):return _fail("恢复备份目录重名，未开始新游戏。原记录未改变。")
 if DirAccess.make_dir_recursive_absolute(archive)!=OK:return _fail("无法创建恢复备份，未开始新游戏。原存档与备份未改变。")
 ticket.recovery_dir=archive
 var manifest:Dictionary={"format":"star-courier-new-game-recovery-v1","created_utc":Time.get_datetime_string_from_system(true),"files":{}}
 for slot in SLOT_NAMES:
  var record:Dictionary=slots[slot]
  manifest.files[slot]={"existed":record.exists,"length":record.bytes.size()}
  if not record.exists:continue
  var destination:String=archive.path_join(slot)
  if not _write_verified(destination,record.bytes):return _fail("恢复备份写入或校验失败，未开始新游戏。原存档与备份未改变。")
  manifest.files[slot].sha256=FileAccess.get_sha256(destination)
 var manifest_bytes:PackedByteArray=JSON.stringify(manifest,"  ").to_utf8_buffer()
 if not _write_verified(archive.path_join("manifest.json"),manifest_bytes):return _fail("恢复备份清单未能保存，未开始新游戏。原存档与备份未改变。")
 var checked:Dictionary=_verify_ticket(ticket)
 return ticket if checked.ok else checked

func _verify_ticket(ticket:Dictionary) -> Dictionary:
 if not ticket.get("ok",false) or ticket.get("used",true) or not ticket.get("slots") is Dictionary:return _fail("新游戏准备记录已失效，原存档未改变。请重试。")
 for slot in SLOT_NAMES:
  if not ticket.slots.has(slot):return _fail("新游戏准备记录不完整，原存档未改变。")
  var expected:Dictionary=ticket.slots[slot]
  var current:Dictionary=_read_bytes(save_root.path_join(slot))
  if not current.ok:return current
  if current.exists!=expected.exists or current.bytes!=expected.bytes:return _fail("存档在准备时发生变化，未开始新游戏。请重新选择。")
  if expected.exists:
   var archive:Dictionary=_read_bytes(str(ticket.recovery_dir).path_join(slot))
   if not archive.ok or not archive.get("exists",false) or archive.bytes!=expected.bytes:return _fail("恢复备份已失效，未开始新游戏。原存档与备份未改变。")
 return {"ok":true,"message":""}

func commit_new_game(ticket:Dictionary) -> Dictionary:
 # Economy invokes this only after writing, flushing and validating its normal
 # savegame.tmp. Keep the serializer/schema entirely owned by Economy.
 var checked:Dictionary=_verify_ticket(ticket)
 if not checked.ok:return checked
 var candidate:Dictionary=_read_bytes(save_root.path_join("savegame.tmp"))
 if not candidate.ok or not candidate.get("exists",false) or candidate.bytes.is_empty():return _fail("新存档暂存失败，未开始新游戏。原存档与备份未改变。")
 if DirAccess.rename_absolute(save_root.path_join("savegame.tmp"),save_root.path_join("savegame.json"))!=OK:return _fail("新存档提交失败，未开始新游戏。原存档与备份未改变。")
 # No fallible writes follow the commit point. The previous backup stays in
 # place; subsequent gameplay saves may rotate it, but never this archive.
 ticket.used=true
 return {"ok":true,"message":""}
