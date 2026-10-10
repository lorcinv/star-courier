class_name WorkshopProfile
extends RefCounted
## Immutable tier definitions. Grid end coordinates are EXCLUSIVE (Rect2i).
## Expansion adds only right-hand columns and upper rows; all old cells survive.
## These are editor/presentation values, never a flight protocol or physics scale.
const MAX_TIER:int=2
const CELL:float=72.0
const FLOOR_Y:float=486.0
const TIER_BOUNDS:Array[Rect2i]=[
 Rect2i(-4,-2,9,5),
 Rect2i(-4,-4,13,7),
 Rect2i(-4,-6,17,9)
]
const TIER_COSTS:Array[int]=[0,180,420]
const ASSEMBLY_ORIGINS:Array[Vector2]=[Vector2(728,288),Vector2(2196,198),Vector2(2352,186)]
const BAY_TOP_LEFTS:Array[Vector2]=[Vector2.ZERO,Vector2(1040,-560),Vector2(1040,-802)]

static func is_valid_tier(tier:int) -> bool:return tier>=0 and tier<=MAX_TIER

static func bounds(tier:int) -> Rect2i:
 return TIER_BOUNDS[tier] if is_valid_tier(tier) else Rect2i()

static func contains_cell(tier:int,cell:Vector2i) -> bool:
 return is_valid_tier(tier) and bounds(tier).has_point(cell)

static func grid_size(tier:int) -> Vector2i:return bounds(tier).size

static func next_tier(current_tier:int) -> int:
 return current_tier+1 if is_valid_tier(current_tier) and current_tier<MAX_TIER else -1

static func purchase_cost(target_tier:int) -> int:
 return TIER_COSTS[target_tier] if is_valid_tier(target_tier) else -1

static func assembly_origin(tier:int) -> Vector2:
 return ASSEMBLY_ORIGINS[tier] if is_valid_tier(tier) else ASSEMBLY_ORIGINS[0]

static func bay_top_left(tier:int) -> Vector2:
 return BAY_TOP_LEFTS[tier] if is_valid_tier(tier) else Vector2.ZERO
