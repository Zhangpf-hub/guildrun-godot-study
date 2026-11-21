class_name GuildrunCombatRandom
extends RefCounted

const MASK_U32 := 0xffffffff
const SEED_STEP := -7046029254386353131
const PCG_MULTIPLIER := 0x5851f42d4c957f2d
const SEED_HASH_A := -4658895280553007687
const SEED_HASH_B := -7723592293110705685
const RESOLUTION_STATE := 3

var state: int
var _stream: int


# RunSessionService.CalculateCurrentSeed, before the seed is passed to BattleConfig.
static func battle_seed(run_seed: int, shards: int, shop_resets: int, floor: int) -> int:
	var battle_context := ((shards * 31 + shop_resets) * 31 + RESOLUTION_STATE) * 31 + floor
	return _signed_i32(0x1d02628f + battle_context * 31 + run_seed)


# Quantum RNGSession initializes PCG with two SplitMix64 values from a signed i32 seed.
func reseed(value: int) -> void:
	var initial := _signed_i32(value)
	state = _split_mix(initial + SEED_STEP)
	_stream = _split_mix(initial + 0x3c6ef372fe94f82a) | 1


# EvaluateProbability compares the upper 16 bits of the next PCG output.
func next_q16() -> int:
	return _next_u32() >> 16


# RNGSession.Next uses an exclusive upper bound and rejects the biased prefix.
func next_index(count: int) -> int:
	assert(count > 0)
	var threshold := (1 << 32) % count
	var value := _next_u32()
	while value < threshold:
		value = _next_u32()
	return value % count


func _next_u32() -> int:
	var previous := state
	state = previous * PCG_MULTIPLIER + _stream
	var rotation := (previous >> 59) & 31
	var mixed := (_unsigned_shift(previous, 45) ^ _unsigned_shift(previous, 27)) & MASK_U32
	return (mixed >> rotation) | ((mixed << ((-rotation) & 31)) & MASK_U32)


static func _split_mix(value: int) -> int:
	value = (value ^ _unsigned_shift(value, 30)) * SEED_HASH_A
	value = (value ^ _unsigned_shift(value, 27)) * SEED_HASH_B
	return value ^ _unsigned_shift(value, 31)


static func _unsigned_shift(value: int, bits: int) -> int:
	return (value >> bits) & ((1 << (64 - bits)) - 1)


static func _signed_i32(value: int) -> int:
	return ((value & MASK_U32) ^ 0x80000000) - 0x80000000
