extends RefCounted

# Photon FPMath.Ln in build 26551710, for every distinct growth factor in EnemyScalingSheetHolder.
const LOG_Q16 := {98304: 26572, 104858: 30802, 108134: 32818, 114688: 36675, 121242: 40317, 131072: 45426}
const EXP_Q16 := [
	65536, 178145, 484249, 1316325, 3578144, 9726404, 26439109, 71868950,
	195360062, 531043708, 1443526462, 3923911751, 10666298010, 28994004058,
	78813874367, 214238322522, 582360139072, 1583018983658, 4303091737384,
	11697016075923, 31795786246376,
]
const STAT_CAP := 500000000


@warning_ignore("integer_division")
static func scaled_stat(base: int, factor_q16: int, cycle: int) -> int:
	if cycle <= 0 or base == 0:
		return base
	# EnemyData..ctor uses (0.43092 + 0.07815 * cycle) * cycle.
	var exponent := (28241 + 5122 * cycle) * cycle
	var x := (int(LOG_Q16[factor_q16]) * exponent + 32768) >> 16
	var integral := (x + 32768) >> 16
	if integral >= EXP_Q16.size():
		return STAT_CAP
	var fraction := x - (integral << 16)
	var square := fraction * fraction
	var cube := square * fraction
	var correction := 65536 + fraction + (square >> 17) + ((cube / 6) >> 32) + ((square * square / 24) >> 48)
	var multiplier := (int(EXP_Q16[integral]) * correction) >> 16
	return mini(STAT_CAP, (base * multiplier) >> 16)
