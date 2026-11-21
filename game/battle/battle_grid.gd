class_name GuildrunBattleGrid
extends RefCounted

## Neighbor-index order from HexGridUtils.GetCellNeighbor and its two offset tables.
const EVEN_ROW := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
const ODD_ROW := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const CELL_WIDTH := 2.598076105117798
const ROW_STEP := 2.25
const HEX_CELL_SIZE_Q16 := 0x18000

var size: Vector2i
var occupants: Dictionary[Vector2i, GuildrunBoardUnit] = {}


func _init(dimensions: Vector2i) -> void:
	size = dimensions


static func center(cell: Vector2i) -> Vector3:
	return Vector3(CELL_WIDTH * (cell.x + 0.5 * (cell.y & 1)), 0.0, -ROW_STEP * cell.y)


static func to_world_length_q16(length_q16: int) -> int:
	return ((length_q16 * HEX_CELL_SIZE_Q16 + 32768) >> 16) * 2


static func neighbor(cell: Vector2i, index: int) -> Vector2i:
	var offsets := EVEN_ROW if (cell.y & 1) == 0 else ODD_ROW
	return cell + offsets[index]


static func distance(first: Vector2i, second: Vector2i) -> int:
	var dx := (second.x - (second.y >> 1)) - (first.x - (first.y >> 1))
	var dy := second.y - first.y
	return maxi(maxi(absi(dx), absi(dy)), absi(dx + dy))


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func best_front_cell(origin_cell: Vector2i, toward: Vector2i) -> Vector2i:
	var origin := Vector2i(origin_cell.x - (origin_cell.y >> 1), origin_cell.y)
	var delta := Vector2i(toward.x - (toward.y >> 1), toward.y) - origin
	var directions := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
			Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
	var front := 0
	var best_score := -2147483648
	for i in 6:
		var direction: Vector2i = directions[i]
		var score := delta.x * direction.x + delta.y * direction.y
		if score > best_score:
			best_score = score
			front = i
	for radius in range(1, maxi(size.x, size.y) + 1):
		for step in range(radius + 1):
			for side: int in [-1, 1]:
				var axial: Vector2i = origin + directions[front] * (radius - step) + directions[posmod(front + side, 6)] * step
				var cell := Vector2i(axial.x + (axial.y >> 1), axial.y)
				if contains(cell) and not occupants.has(cell):
					return cell
	return origin_cell


func best_behind_cell(target: GuildrunBoardUnit, attacker: GuildrunBoardUnit) -> Vector2i:
	var rear := target.transform.basis.z.normalized()
	var origin := target.grid_cell
	for prefer_behind: bool in [true, false]:
		for radius in range(1, 5):
			var best := Vector2i(-1, -1)
			var best_dot := -INF
			var best_distance := 2147483647
			for dq in range(-radius, radius + 1):
				for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
					var y := origin.y + dr
					var cell := Vector2i(origin.x - (origin.y >> 1) + dq + (y >> 1), y)
					if not contains(cell) or distance(origin, cell) != radius:
						continue
					if occupants.has(cell) and occupants[cell] != attacker:
						continue
					var alignment := (center(cell) - center(origin)).normalized().dot(rear)
					if prefer_behind and alignment < 0.0:
						continue
					var travel := distance(attacker.grid_cell, cell)
					if alignment > best_dot + 655.0 / 65536.0 or (alignment > best_dot - 655.0 / 65536.0 and travel < best_distance):
						best = cell
						best_dot = alignment
						best_distance = travel
			if best.x >= 0:
				return best
	return attacker.grid_cell


## Each traversed edge costs one. As in MoveNext, a predecessor is replaced
## only if the new distance is strictly shorter. The starting cell may be occupied.
func find_path(start: Vector2i, goals: Array[Vector2i], reserved: Dictionary[Vector2i, GuildrunBoardUnit] = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not contains(start) or goals.is_empty() or start in goals:
		return result
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary[Vector2i, Vector2i] = {start: start}
	var cost: Dictionary[Vector2i, int] = {start: 0}
	while not frontier.is_empty():
		var cell := _pop_min(frontier, cost)
		if cell in goals:
			while cell != start:
				result.append(cell)
				cell = previous[cell]
			result.reverse()
			return result
		for i in 6:
			var next := neighbor(cell, i)
			if not contains(next) or occupants.has(next) or reserved.has(next) or cost.has(next):
				continue
			cost[next] = cost[cell] + 1
			previous[next] = cell
			_push_min(frontier, cost, next)
	return result


static func _push_min(heap: Array[Vector2i], cost: Dictionary[Vector2i, int], cell: Vector2i) -> void:
	var index := heap.size()
	heap.append(cell)
	while index > 0:
		var parent := (index - 1) >> 1
		# The native heap bubbles up equal priorities as well.
		if cost[heap[parent]] < cost[cell]:
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = cell


static func _pop_min(heap: Array[Vector2i], cost: Dictionary[Vector2i, int]) -> Vector2i:
	var first := heap[0]
	var last: Vector2i = heap.pop_back()
	if heap.is_empty():
		return first
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and cost[heap[child + 1]] <= cost[heap[child]]:
			child += 1
		if cost[last] < cost[heap[child]]:
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return first
