extends SceneTree

const SEMANTIC_BARREL_SPRITE := preload("res://scripts/semantic_barrel_sprite.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	for size in [32, 18, 9, 4]:
		var texture := SEMANTIC_BARREL_SPRITE.texture_for(size, 3)
		var image := texture.get_image()
		var opaque_pixels := 0
		var colors: Dictionary = {}
		for y in range(size):
			for x in range(size):
				var color := image.get_pixel(x, y)
				if color.a > 0.0:
					opaque_pixels += 1
					colors[color.to_html(true)] = true
		if opaque_pixels == 0:
			failures.append("Semantic barrel %dpx has no visible silhouette" % size)
		if size >= 15 and colors.size() < 4:
			failures.append("Semantic barrel %dpx lost its named material reads" % size)
		if size <= 9 and opaque_pixels >= size * size:
			failures.append("Semantic barrel %dpx lost its transparent silhouette" % size)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Semantic barrel sprite test passed")
	quit(0)
