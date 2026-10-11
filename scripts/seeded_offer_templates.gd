extends RefCounted
## Frozen authored content and integer PRNG definitions for seeded-offers-v1.
const VERSION = "seeded-offers-v1"
const LAYOUTS = {
	"ground": [
		{"id":"roof-zigzag", "distance":360.0, "altitude":8.0, "climb_end":165.0, "xs":[85.0,185.0,275.0], "offsets":[-6.0,5.0,-5.0]},
		{"id":"roof-long-approach", "distance":380.0, "altitude":10.0, "climb_end":175.0, "xs":[90.0,190.0,285.0], "offsets":[-5.0,6.0,-4.0]},
		{"id":"roof-shallow", "distance":370.0, "altitude":6.0, "climb_end":170.0, "xs":[90.0,185.0,280.0], "offsets":[-6.0,4.0,-5.0]}],
	"ascent": [
		{"id":"orbit-zigzag", "distance":520.0, "altitude":150.0, "climb_end":410.0, "xs":[105.0,220.0,330.0,465.0], "offsets":[-8.0,6.0,-6.0,0.0]},
		{"id":"orbit-wide-turn", "distance":540.0, "altitude":144.0, "climb_end":420.0, "xs":[110.0,230.0,345.0,480.0], "offsets":[-7.0,6.0,-5.0,0.0]},
		{"id":"orbit-early-level", "distance":530.0, "altitude":138.0, "climb_end":400.0, "xs":[105.0,220.0,335.0,475.0], "offsets":[-8.0,5.0,-6.0,0.0]}]
}
const OPENINGS = {
	"human_courier": ["小勺送到%s，外面那层布也一起留给他。", "还是那把小勺，地址写的是%s。我把勺柄也包好了。"],
	"elf_archivist": ["书签送到%s。借书条放在外袋，别和它一起夹进去。", "%s在等这枚书签。我另外夹了张纸，写着它该放在哪本书里。"],
	"alien_botanist": ["这盆幼苗去%s。垫在花盆下面的布，到了也先别抽走。", "送到%s就好。幼苗还在睡，箱盖上留了透气孔。"],
	"robot_machinist": ["旧哨片送到%s。旁边那颗螺丝是配套的，别弄丢。", "%s要这片旧水壶哨片。我用纸包住了边，拆的时候慢一点。"]
}

class LocalStream:
	extends RefCounted
	var state: int
	func _init(initial: int): state = initial
	func take(count: int) -> int:
		# Park–Miller arithmetic is exact in signed 64-bit integers. No engine RNG.
		state = (state * 48271) % 2147483647
		return state % count

static func stable_seed(text: String) -> int:
	var value: int = 5381
	for byte in text.to_utf8_buffer(): value = (value * 33 + int(byte)) % 2147483647
	return maxi(1, value)

static func derived_seed(world_seed: int, day: int, slot: int, kind: String, domain: String) -> int:
	return stable_seed("star-courier/%s/%d/%d/%d/%s/%s" % [VERSION, world_seed, day, slot, kind, domain])

