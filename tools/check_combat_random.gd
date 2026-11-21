extends SceneTree


func _initialize() -> void:
	var random: RefCounted = load("res://battle/combat_random.gd").new()
	# Normal floors and an event fight recorded by Steam build 26551710.
	var seeds := [[15, 0, 0, 500813409], [15, 0, 1, 500813440], [39, 0, 2, 522977975],
			[32, 2, 3, 516572941], [7, 6, 3, 493604080]]
	for record: Array in seeds:
		if random.battle_seed(262144, record[0], record[1], record[2]) != record[3]:
			push_error("BattleConfig seed differs from the source log")
			quit(1)
			return
	var samples := {
		500813409: [52909, 39668, 39296, 57967, 54888, 48808, 22111, 29428, 432, 63745, 46053, 63431, 24756],
		0: [16673, 416, 41841, 65439, 43714, 46230],
		-1: [45712, 26787, 15895, 16926, 25459, 16377],
		2147483647: [45395, 27104, 18911, 38944, 28193, 19344],
		-2147483648: [5546, 61456, 42406, 58982, 10308, 9429],
	}
	for seed_value: int in samples:
		random.reseed(seed_value)
		for value: int in samples[seed_value]:
			if random.next_q16() != value:
				push_error("Quantum RNGSession draw differs for seed %d" % seed_value)
				quit(1)
				return
	random.reseed(500813409)
	if random.next_index(1) != 0 or random.next_index(7) != 3 or random.next_index(9) != 1 or random.next_q16() != 57967:
		push_error("Target selection must consume draws from the same stream as critical hits")
		quit(1)
		return
	print("Combat random source seeds, signed i32 initialization, Q16 draws and target selection verified")
	quit()
