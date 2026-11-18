extends SceneTree
func _initialize():
	call_deferred("run_test")
func run_test():
	set_meta("grudge_public_build", true)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game._bind_player_context(0)
	game.clear_map_waiting_to_start = false
	game.wanted_tally_overlay.visible = false
	var mobile = load("res://scripts/mobile_controls.gd").new()
	mobile.game = game
	root.add_child(mobile)
	mobile.size = Vector2(960,720)
	game.mobile_controls = mobile
	var point = mobile._layout().roll
	var move = InputEventScreenTouch.new()
	move.index = 1
	move.position = Vector2(130,500)
	move.pressed = true
	mobile._input(move)
	var drag = InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(60,500)
	mobile._input(drag)
	var roll = InputEventScreenTouch.new()
	roll.index = 2
	roll.position = point
	roll.pressed = true
	mobile._input(roll)
	roll.pressed = false
	mobile._input(roll)
	assert(game._advance_dive_roll(0, 0.05, true))
	assert(game.player_states[0]["dive_active"])
	assert(mobile.stick.x < -0.9)
	assert(not mobile.take_roll())
	# Finish the existing stick drag, then double-tap and hold to crouch.
	move.pressed = false
	mobile._input(move)
	var tap = InputEventScreenTouch.new()
	tap.index = 3
	tap.position = Vector2(150, 500)
	tap.pressed = true
	mobile._input(tap)
	assert(not mobile.pressed("crouch"))
	tap.pressed = false
	mobile._input(tap)
	tap.pressed = true
	mobile._input(tap)
	assert(mobile.pressed("crouch"))
	var crouch_drag = InputEventScreenDrag.new()
	crouch_drag.index = 3
	crouch_drag.position = Vector2(150, 430)
	mobile._input(crouch_drag)
	assert(mobile.pressed("crouch") and mobile.stick.y < -0.9)
	tap.pressed = false
	mobile._input(tap)
	assert(not mobile.pressed("crouch"))
	assert("roll" in mobile.EDITABLE)
	print("Touch roll and hold-to-crouch gestures passed")
	game.mobile_controls = null
	mobile.queue_free()
	game.queue_free()
	quit()
