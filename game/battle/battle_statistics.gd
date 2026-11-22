class_name GuildrunBattleStatistics
extends RefCounted

enum Origin { ATTACK, ABILITY, ITEM, STATUS, OTHER }
enum Mode { DEALT, TAKEN, SUPPORT }
enum StatusKind { NONE, BURN, FROST, POISON }

const ORIGIN_FIELDS := ["attack", "ability", "item", "status", "other"]
const DISPLAY_FIELDS := [
	["ability", "attack", "item", "status", "other"],
	["health_damage", "shield_damage", "mitigated"],
	["healing", "shielding"],
]
const DISPLAY_COLORS := [
	[Color("#923491"), Color("#b8a85f"), Color("#9eb2e3"), Color("#c65b4f"), Color("#a0a198")],
	[Color("#198e57"), Color("#c4ae78"), Color("#787e74")],
	[Color("#5aa977"), Color("#8b8acf")],
]

var units: Dictionary[int, Dictionary] = {}
var relics: Dictionary[int, Dictionary] = {}
var _status_totals: Dictionary[int, Dictionary] = {}


func register(id: int, label: String, portrait: String, ally: bool) -> void:
	if not units.has(id):
		units[id] = {
			"label": label, "portrait": portrait, "ally": ally,
			"attack": 0, "ability": 0, "item": 0, "status": 0, "other": 0,
			"health_damage": 0, "shield_damage": 0, "mitigated": 0,
			"healing": 0, "shielding": 0,
		}


func damage(source: int, target: int, origin: Origin, logged_damage: int, shield: int, mitigated: int, relic := 0) -> void:
	if units.has(target):
		var receiver: Dictionary = units[target]
		receiver.health_damage += logged_damage
		receiver.shield_damage += shield
		receiver.mitigated += mitigated
	if relic != 0:
		var entry := _relic(relic)
		entry.damage += logged_damage
	elif units.has(source):
		var attacker: Dictionary = units[source]
		attacker[ORIGIN_FIELDS[origin]] += logged_damage


func record_status_applied(source: int, kind: StatusKind, stacks: int) -> void:
	if not units.has(source) or not units[source].ally or stacks <= 0:
		return
	var totals := _status_totals_for(kind)
	var applied: Dictionary = totals.applied
	applied[source] = int(applied.get(source, 0)) + stacks
	totals.player_stacks += stacks
	totals.dirty = true


func record_status_damage(kind: StatusKind, logged_damage: int) -> void:
	if logged_damage <= 0:
		return
	var totals := _status_totals_for(kind)
	totals.damage += logged_damage
	totals.dirty = true


func _status_totals_for(kind: StatusKind) -> Dictionary:
	if not _status_totals.has(kind):
		_status_totals[kind] = {"applied": {}, "shares": {}, "player_stacks": 0, "damage": 0, "dirty": false}
	return _status_totals[kind]


@warning_ignore("integer_division")
func settle_status_damage() -> void:
	# BattleStats calculates separate cumulative Q16 shares for burn and poison at frame end.
	for totals: Dictionary in _status_totals.values():
		if not totals.dirty:
			continue
		totals.dirty = false
		var applied: Dictionary = totals.applied
		var shares: Dictionary = totals.shares
		var player_stacks := int(totals.player_stacks)
		for source: int in applied:
			var fraction_q16 := (int(applied[source]) << 16) / player_stacks
			var share := (int(totals.damage) * fraction_q16) >> 16
			var unit: Dictionary = units[source]
			unit.status += share - int(shares.get(source, 0))
			shares[source] = share


func support(source: int, healing: int, shielding: int, relic := 0) -> void:
	var entry := _relic(relic) if relic != 0 else units.get(source, {}) as Dictionary
	if not entry.is_empty():
		entry.healing += healing
		entry.shielding += shielding


func _relic(id: int) -> Dictionary:
	if not relics.has(id):
		relics[id] = {"damage": 0, "healing": 0, "shielding": 0}
	return relics[id]


func snapshot(elapsed_q16: int, victory: bool) -> Dictionary:
	settle_status_damage()
	return {
		"elapsed_q16": elapsed_q16, "victory": victory,
		"units": units.duplicate(true), "relics": relics.duplicate(true),
	}


static func total(entry: Dictionary, mode: Mode) -> int:
	match mode:
		Mode.DEALT:
			return entry.attack + entry.ability + entry.item + entry.status + entry.other
		Mode.TAKEN:
			return entry.health_damage + entry.shield_damage + entry.mitigated
		Mode.SUPPORT:
			return entry.healing + entry.shielding
	return 0
