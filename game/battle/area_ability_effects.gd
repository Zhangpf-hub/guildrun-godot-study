extends RefCounted


static func read_pulse(effect_refs: Array, references: Dictionary) -> Array[Dictionary]:
	var pulse: Array[Dictionary] = []
	for effect_ref: Dictionary in effect_refs:
		var effect: Dictionary = references[effect_ref.rid].data
		var actions: Array[Dictionary] = []
		for action_ref: Dictionary in effect._actions:
			var action: Dictionary = references[action_ref.rid]
			actions.append({"kind": action.type["class"], "data": action.data})
		pulse.append({"team": int(effect.TargetType), "actions": actions})
	return pulse


static func auto_position(source: GuildrunBoardUnit, target: GuildrunBoardUnit, units: Array[GuildrunBoardUnit], radius: float) -> Vector3:
	var points: Array[Vector2] = []
	var weights: Array[float] = []
	var origin := Vector2(target.position.x, target.position.z)
	for unit in units:
		if not unit.defeated:
			points.append(Vector2(unit.position.x, unit.position.z))
			weights.append(1.01 if unit == source else 1.0)
	var candidates := points.duplicate()
	candidates.append(origin)
	for i in points.size():
		for j in range(i + 1, points.size()):
			var delta := points[j] - points[i]
			var midpoint := (points[i] + points[j]) * 0.5
			var height_squared := radius * radius - delta.length_squared() * 0.25
			if height_squared >= 0.0 and not delta.is_zero_approx():
				var edge := delta.orthogonal().normalized() * sqrt(height_squared)
				candidates.append(midpoint + edge)
				candidates.append(midpoint - edge)
	var selected: Array[Vector2] = []
	var best_score := -1.0
	var best_distance := INF
	for candidate: Vector2 in candidates:
		var score := 0.0
		var covered: Array[Vector2] = []
		for i in points.size():
			if candidate.distance_squared_to(points[i]) <= radius * radius + 0.0001:
				score += weights[i]
				covered.append(points[i])
		var distance := candidate.distance_squared_to(origin)
		if score > best_score or (is_equal_approx(score, best_score) and distance < best_distance):
			best_score = score
			best_distance = distance
			selected = covered
	var center := _enclosing_center(selected, origin)
	return Vector3(center.x, target.position.y, center.y)


static func _enclosing_center(points: Array[Vector2], fallback: Vector2) -> Vector2:
	var candidates := points.duplicate()
	for i in points.size():
		for j in range(i + 1, points.size()):
			candidates.append((points[i] + points[j]) * 0.5)
			for k in range(j + 1, points.size()):
				var a := points[j] - points[i]
				var b := points[k] - points[i]
				var divisor := 2.0 * a.cross(b)
				if not is_zero_approx(divisor):
					var offset := Vector2(a.length_squared() * b.y - b.length_squared() * a.y,
							a.x * b.length_squared() - b.x * a.length_squared()) / divisor
					candidates.append(points[i] + offset)
	var center := fallback
	var best_radius := INF
	for candidate: Vector2 in candidates:
		var radius := 0.0
		for point in points:
			radius = maxf(radius, candidate.distance_squared_to(point))
		if radius < best_radius:
			best_radius = radius
			center = candidate
	return center
