extends RefCounted

signal credit_added(source: int, rule: int, amount: int, preview_balance: int)

var _starting_balance: int
var _credits: int
var _settled: bool
var _rules: Array[Dictionary] = []
var _counts: Dictionary[Vector2i, int] = {}
var _tracking: Dictionary[Vector2i, int] = {}
var _last_event_id: int


func begin(balance: int, bindings: Array[Dictionary]) -> void:
	_starting_balance = balance
	_credits = 0
	_settled = false
	_rules.clear()
	_counts.clear()
	_tracking.clear()
	_last_event_id = -1
	for binding in bindings:
		if int(binding.threshold) <= 0 or int(binding.amount) <= 0:
			continue
		_rules.append(binding.duplicate(false))


func record(event_id: int, event: StringName, source: int = -1) -> int:
	if _settled or event_id <= _last_event_id:
		return 0
	_last_event_id = event_id
	var awarded := 0
	for binding in _rules:
		if binding.event != event or (binding.owner_only and int(binding.owner) != source):
			continue
		var key := Vector2i(int(binding.owner), int(binding.rule))
		var count := int(_counts.get(key, 0)) + 1
		if count < int(binding.threshold):
			_counts[key] = count
			continue
		_counts[key] = 0
		var credit := int(binding.amount)
		_credits += credit
		awarded += credit
		_tracking[key] = int(_tracking.get(key, 0)) + credit
		credit_added.emit(key.x, key.y, credit, preview_balance())
	return awarded


func preview_balance() -> int:
	return _starting_balance + _credits


func tracked(owner: int, rule: int) -> int:
	return int(_tracking.get(Vector2i(owner, rule), 0))


func take_delta() -> int:
	if _settled:
		return 0
	_settled = true
	return _credits

func tracking_totals() -> Dictionary:
	return _tracking.duplicate()
