extends SceneTree

const Controller = preload("res://scripts/xybots_character_controller.gd")

func _initialize() -> void:
 var game = Controller.new()
 var state = {"pistol_ammo": 0, "machine_gun_ammo": 0}
 game._start_pistol_reload(state)
 assert(state.reload_frame == 1 and state.reload_phase == "open")
 var expected = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
 for frame in expected:
  game._advance_pistol_reload(state, float(state.reload_timer) + 0.001)
  assert(state.reload_frame == frame, "Expected frame %d got %d" % [frame, state.reload_frame])
 game._advance_pistol_reload(state, 0.19)
 assert(state.reload_phase == "close" and state.pistol_ammo == 6)
 game._advance_pistol_reload(state, 0.23)
 assert(state.reload_phase == "")
 state = {"pistol_ammo": 3, "machine_gun_ammo": 0}
 game._start_pistol_reload(state)
 assert(state.reload_frame == 8)
 game._advance_pistol_reload(state, 0.201)
 assert(state.reload_frame == 9 and state.reload_phase == "turn")
 state = {"pistol_ammo": 0, "machine_gun_ammo": 12}
 game._start_pistol_reload(state)
 assert(not state.has("reload_phase"))
 # Firing removes a dot immediately and plays the two rotation frames backward.
 assert(game._ammo_display_frame(5, 0.12, 6) == 16)
 assert(game._ammo_display_frame(5, 0.05, 6) == 15)
 assert(game._ammo_display_frame(5, 0.0, 6) == 14)
 assert(game._ammo_display_frame(0, 0.12, 1) == 1)
 game.free()
 print("Reload sequence checks passed")
 quit()
