# Entry scene for the coordinate-frame experiment.  It instantiates the
# untouched original game scene, then adds the reversible runtime wall layer.
extends Node2D

const ORIGINAL_GAME := preload("res://main.tscn")
const RUNTIME_RENDERER := preload("res://scripts/coordinate_frame_runtime_renderer.gd")

func _ready() -> void:
	var game := ORIGINAL_GAME.instantiate()
	game.name = "CoordinateFrameGame"
	add_child(game)
	var renderer := RUNTIME_RENDERER.new()
	renderer.name = "CoordinateFrameRuntimeRenderer"
	game.add_child(renderer)
