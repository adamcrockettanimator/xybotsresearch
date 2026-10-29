## Captures the playable semantic-prop calibration scene after its first frames.
##
## This is visual QA support for renderer work: it does not alter the scene,
## gameplay data, or project entrypoint. Run it with Godot's --script option.
extends Node2D


const CALIBRATION_SCENE := preload("res://tests/calibration/semantic_crate_authoring.tscn")
const OUTPUT_PATH := "user://semantic_projected_barrel_capture.png"
var frames_waited := 0


func _ready() -> void:
	var calibration := CALIBRATION_SCENE.instantiate()
	add_child(calibration)


func _process(_delta: float) -> void:
	# Let the gallery wrapper create the game, bind its camera, and repaint the
	# semantic-prop comparison row before reading back the completed viewport.
	frames_waited += 1
	if frames_waited < 12:
		return
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(absolute_path)
	print("SEMANTIC_BARREL_CAPTURE=%s error=%d" % [absolute_path, error])
	get_tree().quit(error)
