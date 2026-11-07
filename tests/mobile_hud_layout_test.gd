extends SceneTree

func _initialize() -> void:
	set_meta("grudge_public_build", true)
	var game = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(game)
	await process_frame
	game.set_process(false)
	game._update_combat_hud()
	assert(game.combat_health_bars[0].columns == 0)
	assert(not game.mobile_hud_panels[0].visible)
	var mobile := Control.new()
	game.mobile_controls = mobile
	game.add_child(mobile)
	game.player_states[0]["health"] = 10
	game.player_states[0]["coins"] = 999
	game.player_states[0]["machine_gun_ammo"] = 12
	game._update_combat_hud()
	for screen_size in [Vector2(1280, 720), Vector2(1555, 720), Vector2(960, 720)]:
		game._layout_mobile_combat_hud(screen_size)
		var health: Node2D = game.combat_health_bars[0]
		var coin: Control = game.combat_coin_icons[0]
		var number: Control = game.combat_coin_labels[0]
		var first: Control = game.combat_ammo_icons[0]
		var second: Control = game.combat_ammo_second_icons[0]
		assert(health.columns == 5 and health.current_health == 10)
		assert(number.text == "999" and second.visible)
		assert(coin.scale.x > 1 and number.scale.x > 1 and first.scale.x > 1)
		assert(health.position.y >= 0 and coin.position.y >= 0 and number.position.y >= 0)
		var panels: Array[ColorRect] = game.mobile_hud_panels
		for i in range(panels.size()):
			assert(panels[i].visible)
			var r := Rect2(panels[i].position, panels[i].size)
			assert(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= screen_size.x and r.end.y <= screen_size.y)
			for j in range(i + 1, panels.size()):
				assert(not r.intersects(Rect2(panels[j].position, panels[j].size)))
	game.player_states[0]["health"] = 3
	game.player_states[0]["machine_gun_ammo"] = 0
	game._update_combat_hud()
	assert(game.combat_health_bars[0].current_health == 3)
	assert(not game.combat_ammo_second_icons[0].visible)
	print("Mobile HUD scales health, coins and single/dual ammo without panel overlap")
	game.queue_free()
	quit()
