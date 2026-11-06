extends SceneTree

class FakeGame extends Node:
	var match_paused := false
	var options_overlay: Control = null
	var combat_round_complete := false
	var clear_map_waiting_to_start := false
	var player_states := [{"continuous_camera_yaw": 0.0}]

func _initialize() -> void:
	var game := FakeGame.new()
	root.add_child.call_deferred(game)
	var controls = load("res://scripts/mobile_controls.gd").new()
	controls.game = game
	root.add_child.call_deferred(controls)
	await process_frame
	controls.size = Vector2(960, 720)
	var points: Dictionary = controls._layout()
	var corner: Vector2 = controls.size - Vector2(45, 45)
	assert(is_equal_approx(corner.distance_to(points.crouch), corner.distance_to(points.fire)))
	assert(is_equal_approx(corner.distance_to(points.fire), corner.distance_to(points.reload)))
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(154, 547)
	touch.pressed = true
	controls._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(154, 477)
	controls._input(drag)
	assert(controls.stick.y < -0.9)
	var look := InputEventScreenTouch.new()
	look.index = 1
	look.position = Vector2(600, 350)
	look.pressed = true
	controls._input(look)
	assert(not controls.take_fire())
	var look_drag := InputEventScreenDrag.new()
	look_drag.index = 1
	look_drag.position = Vector2(620, 350)
	look_drag.relative = Vector2(500, 0) # Web may mix another finger's delta.
	controls._input(look_drag)
	assert(is_equal_approx(float(game.player_states[0]["continuous_camera_yaw"]), 0.12))
	drag.position = Vector2(180, 480)
	controls._input(drag)
	look_drag.position = Vector2(625, 350)
	look_drag.relative = Vector2(-440, 0)
	controls._input(look_drag)
	assert(is_equal_approx(float(game.player_states[0]["continuous_camera_yaw"]), 0.15))
	assert(not controls.take_fire())
	look.pressed = false
	controls._input(look)
	var fire := InputEventScreenTouch.new()
	fire.index = 2
	fire.position = points.fire
	fire.pressed = true
	controls._input(fire)
	assert(controls.take_fire() and controls.take_fire()) # Held fire repeats.
	var fire_drag := InputEventScreenDrag.new()
	fire_drag.index = 2
	fire_drag.position = points.fire + Vector2(10, 0)
	fire_drag.relative = Vector2(-500, 0)
	controls._input(fire_drag)
	assert(is_equal_approx(float(game.player_states[0]["continuous_camera_yaw"]), 0.21))
	fire.pressed = false
	controls._input(fire)
	assert(not controls.take_fire())
	fire.pressed = true
	controls._input(fire)
	fire.pressed = false
	controls._input(fire)
	assert(controls.take_fire() and not controls.take_fire())
	var duck := InputEventScreenTouch.new()
	duck.index = 4
	duck.position = points.crouch
	duck.pressed = true
	controls._input(duck)
	duck.pressed = false
	controls._input(duck)
	assert(controls.pressed("crouch"))
	duck.pressed = true
	controls._input(duck)
	duck.pressed = false
	controls._input(duck)
	assert(not controls.pressed("crouch"))
	game.clear_map_waiting_to_start = true
	var begin := InputEventScreenTouch.new()
	begin.index = 3
	begin.position = Vector2(500, 300)
	begin.pressed = true
	controls._input(begin)
	begin.pressed = false
	controls._input(begin)
	assert(controls.take_continue())
	assert(not controls.take_continue())
	game.clear_map_waiting_to_start = false
	game.combat_round_complete = true
	begin.pressed = true
	controls._input(begin)
	assert(controls.take_continue())
	game.combat_round_complete = false
	game.match_paused = true
	controls.layout_path = "user://mobile_control_layout_test.cfg"
	var layout_tap := InputEventScreenTouch.new()
	layout_tap.index = 7
	layout_tap.position = controls._layout().layout
	layout_tap.pressed = true
	controls._input(layout_tap)
	assert(controls.editing)
	var edit_touch := InputEventScreenTouch.new()
	edit_touch.index = 8
	edit_touch.position = controls._layout().fire
	edit_touch.pressed = true
	controls._input(edit_touch)
	var edit_drag := InputEventScreenDrag.new()
	edit_drag.index = 8
	edit_drag.position = Vector2(650, 420)
	controls._input(edit_drag)
	edit_touch.pressed = false
	controls._input(edit_touch)
	assert(controls._layout().fire.distance_to(Vector2(650, 420)) < 0.1)
	assert(not controls.take_fire())
	var save_touch := InputEventScreenTouch.new()
	save_touch.index = 9
	save_touch.position = controls._layout().done
	save_touch.pressed = true
	controls._input(save_touch)
	assert(not controls.editing)
	var restored = load("res://scripts/mobile_controls.gd").new()
	restored.layout_path = controls.layout_path
	restored.size = Vector2(960, 720)
	restored._load_layout()
	assert(restored._layout().fire.distance_to(Vector2(650, 420)) < 0.1)
	restored.size = Vector2(480, 360)
	assert(restored._layout().fire.distance_to(Vector2(325, 210)) < 0.1)
	restored.free()
	controls._start_editing()
	var reset_touch := InputEventScreenTouch.new()
	reset_touch.index = 10
	reset_touch.position = controls._layout().reset
	reset_touch.pressed = true
	controls._input(reset_touch)
	assert(controls.saved_positions.is_empty())
	assert(controls._layout().fire.distance_to(points.fire) < 0.1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(controls.layout_path))
	print("Mobile controls, multitouch, layout editing and persistence passed")
	controls.queue_free()
	game.queue_free()
	quit()

