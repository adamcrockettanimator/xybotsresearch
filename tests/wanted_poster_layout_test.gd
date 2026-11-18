extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	set_meta("grudge_public_build", true)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for round_number in range(1, 17):
		game.clear_map_round = round_number
		game.clear_map_waiting_to_start = true
		game._apply_session_roster()
		for terminal in [false, true]:
			game._begin_wanted_tally(terminal)
			await process_frame
			var instruction: Control = game.wanted_tally_overlay.get_node("RoundInstruction")
			var button: Control = game.wanted_tally_overlay.get_node("BeginButton")
			var instruction_bottom: float = instruction.get_global_rect().end.y
			var button_top: float = button.get_global_rect().position.y
			var bounds: Array[Rect2] = []
			for index in game.wanted_tally_posters:
				var card: Control = game.wanted_tally_posters[index].card
				var transform := card.get_global_transform_with_canvas()
				var rect := Rect2(transform * Vector2.ZERO, (transform * Vector2(87.0, 164.0)) - (transform * Vector2.ZERO))
				assert(rect.position.y >= instruction_bottom, "Round %d poster overlaps instruction: %s" % [round_number, rect])
				assert(rect.end.y <= button_top, "Round %d poster overlaps buttons: %s" % [round_number, rect])
				for other in bounds:
					assert(not rect.intersects(other), "Round %d poster cards overlap" % round_number)
				bounds.append(rect)
	print("Poster boards fit around interface for rounds 1 through 16")
	game.queue_free()
	quit()
