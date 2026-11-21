extends SceneTree

const LANDMARK := Vector3(4.0, 3.0, -8.0)
const NATIVE_PIXELS := {
	Vector2i(1024, 768): {
		"placement": Vector2(333.071, 320.833), "fight": Vector2(348.642, 291.018),
		"result": Vector2(354.134, 291.022), "crossroads": Vector2(356.520, 398.108),
	},
	Vector2i(1280, 720): {
		"placement": Vector2(419.380, 282.115), "fight": Vector2(436.165, 243.980),
		"result": Vector2(445.312, 245.335), "crossroads": Vector2(460.980, 376.244),
	},
	Vector2i(1728, 720): {
		"placement": Vector2(586.239, 261.943), "fight": Vector2(627.637, 225.465),
		"result": Vector2(618.745, 215.553), "crossroads": Vector2(675.502, 377.104),
	},
}
var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for dimensions: Vector2i in NATIVE_PIXELS:
		root.size = dimensions
		await process_frame
		var stage = load("res://battle/stage.tscn").instantiate()
		root.add_child(stage)
		var rig = stage.battle_camera
		rig.set_process(false)
		var camera := root.get_camera_3d()
		var fight: GuildrunEncounter = stage.encounter
		check(rig.state == "start" and rig.active_priority == 10, "Cut camera yields to preparation start")
		fight.select_hero(4)
		var start := camera.global_position
		var end: Vector3 = rig.target_transform("placement").origin
		rig.advance(1.0)
		check(camera.global_position.is_equal_approx(start.lerp(end, 0.15625)), "Native smooth 4-second placement blend")
		var resized := dimensions + Vector2i(96, 0)
		root.size = resized
		await process_frame
		check(is_equal_approx(rig._elapsed, 1.0), "Resize preserves the in-flight blend clock")
		check_lens(camera, resized)
		check(camera.global_position.is_equal_approx(start.lerp(rig.target_transform("placement").origin, 0.15625)),
				"Resize recomputes the target at the existing native blend fraction")
		root.size = dimensions
		await process_frame
		rig.advance(3.0)
		assert_projection(camera, dimensions, "placement")
		fight.start_fight()
		rig.advance(1.5)
		check(camera.global_position.distance_to(end) > 0.1, "Three-second fight blend advances")
		rig.advance(1.5)
		assert_projection(camera, dimensions, "fight")
		fight.phase = GuildrunEncounter.Phase.RESULT
		rig.advance(2.0)
		assert_projection(camera, dimensions, "result")
		if fight.first_shop == null:
			fight._create_party()
		fight.first_shop.prepare(4, stage.stage, 0)
		fight._show_crossroads()
		var road := fight.crossroads
		var world: Control = road.get_child(-1).get_node("WorldGateTargets")
		var gate: Button = world.get_child(0)
		gate.grab_focus()
		var original_position := gate.position
		rig.advance(1.0)
		check(world.get_child(0) == gate and gate.has_focus(), "Gate and focus survive camera movement")
		check(original_position.distance_to(gate.position) > 1.0, "Gate follows moving camera")
		check_gate_geometry(stage, gate)
		rig.advance(1.0)
		assert_projection(camera, dimensions, "crossroads")
		root.size = dimensions + Vector2i(96, 0)
		await process_frame
		check_lens(camera, dimensions + Vector2i(96, 0))
		var expected_bar := maxf(0.0, (root.size.x - root.size.y * (7.0 / 3.0)) / 2.0)
		check(absf(rig._left_bar.size.x - expected_bar) < 0.002
				and absf(rig._right_bar.position.x - (root.size.x - expected_bar)) < 0.002,
				"Ultrawide viewport uses symmetrical side bars")
		check(world.get_child(0) == gate and gate.has_focus(), "Gate and focus survive viewport resize")
		check_gate_geometry(stage, gate)
		var hit := InputEventMouseButton.new()
		hit.button_index = MOUSE_BUTTON_LEFT
		hit.position = stage.crossroads_gate_screen_rects()[0].get_center()
		hit.global_position = hit.position
		hit.pressed = true
		root.push_input(hit)
		hit.pressed = false
		root.push_input(hit)
		check(road.selected_event == road.offers[0] and rig.state == "crossroads_zoom", "Projected gate hit selects camera target")
		rig.advance(4.0)
		check(rig._elapsed == 4.0 and rig._duration == 8.0, "Native eight-second gate focus")
		road.claim()
		road.departed.emit()
		check(rig.state == "intro", "Leaving the event enters next-board intro camera")
		rig.advance(0.099)
		check(rig.state == "intro", "Placement waits for native intro delay")
		rig.advance(0.002)
		check(rig.state == "placement" and rig._duration == 2.0, "Intro blends to placement")
		stage.free()
	var preview = load("res://battle/stage.tscn").instantiate()
	preview.stage_id = 10706
	root.add_child(preview)
	check(preview.battle_camera == null and root.get_camera_3d().position == Vector3.ZERO
			and is_equal_approx(root.get_camera_3d().fov, 21.0),
			"Static board preview keeps authored CutVCam")
	preview.free()
	print("BATTLE_CAMERA three physical projections, in-flight resize, moving/ultrawide gate clicks, static preview")
	quit(1 if failed else 0)


func assert_projection(camera: Camera3D, dimensions: Vector2i, state: String) -> void:
	var point := camera.unproject_position(LANDMARK)
	var expected: Vector2 = NATIVE_PIXELS[dimensions][state]
	check(point.distance_to(expected) < 0.05, "%s %s projection expected %s, got %s" % [state, dimensions, expected, point])


func check_lens(camera: Camera3D, dimensions: Vector2i) -> void:
	var film_pixels := minf(dimensions.x, dimensions.y * (7.0 / 3.0))
	var focal_pixels := film_pixels * 43.169532775878906 / 21.945999145507812
	var observed := dimensions.y / (2.0 * tan(deg_to_rad(camera.fov) / 2.0))
	check(absf(focal_pixels - observed) < 0.01, "Focal distance is derived from the effective viewport width")


func check_gate_geometry(stage: Node, gate: Button) -> void:
	var pixel := gate.get_global_transform_with_canvas() * (gate.size / 2.0)
	check(pixel.distance_to(stage.crossroads_gate_screen_rects()[0].get_center()) < 0.1, "Gate hit aligns to camera projection")
	var title: Control = gate.get_child(0).get_node("Title")
	var title_center := title.get_global_transform_with_canvas() * (title.size / 2.0)
	check(title_center.distance_to(stage.crossroads_gate_label_rects()[0].get_center()) < 0.1,
			"Gate text aligns to camera projection")


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
