@tool
extends Path2D

@onready var line: Line2D = $Line2D
const EDITOR_LINE_POINT_COUNT := 12


func _ready() -> void:
	if curve:
		if not curve.changed.is_connected(_update_line):
			curve.changed.connect(_update_line)

	call_deferred("_update_line")
	# The editor may keep this @tool scene alive while its Curve2D is edited.
	# Mirror it there each editor frame; a played game keeps the cheap signal path.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_update_line()


func _update_line() -> void:
	if curve == null or not is_instance_valid(line):
		return
	# Curve2D's baked list is a render tessellation (95 points here), not its
	# artist-facing Bézier controls. Deliberately keep a small, readable
	# polyline approximation for the Line2D child.
	var baked_points := curve.get_baked_points()
	line.clear_points()
	if baked_points.size() < 2:
		return
	var output_count := mini(EDITOR_LINE_POINT_COUNT, baked_points.size())
	for index in output_count:
		var sample_index := roundi(float(index) / float(output_count - 1) * float(baked_points.size() - 1))
		line.add_point(baked_points[sample_index])
