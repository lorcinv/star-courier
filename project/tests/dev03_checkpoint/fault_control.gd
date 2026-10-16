extends RefCounted
## Test-only fault switches and counters, outside transactional script state.
static var mode:String=""
static var checkpoint_calls:int=0
static var coupled_calls:int=0
static var copy_calls:int=0
static var hits:int=0
static func reset(next:String="") -> void:
 mode=next;checkpoint_calls=0;coupled_calls=0;copy_calls=0;hits=0
