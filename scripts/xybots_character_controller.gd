# Xybots character and environment prototype controller.
# This script owns the cropped 160x120 playfield prototype: it loads captured Xybots wall/floor/player art,
# tracks the player cell and facing on a thin-wall grid, lets the character move inside a tile,
# plays captured transition frames for turns and tile crossings, and renders stable views from transparent wall sprites.
# The straight-wall renderer is intentionally table-driven so the wall-number mapping can be corrected as the art is cleaned up.

extends Node2D                                                                              # Use Node2D as the root script type for the prototype scene.

const DIR_N := "N"                                                                          # Name the north-facing animation/map direction.
const DIR_E := "E"                                                                          # Name the east-facing animation/map direction.
const DIR_S := "S"                                                                          # Name the south-facing animation/map direction.
const DIR_W := "W"                                                                          # Name the west-facing animation/map direction.

const VIEWPORT_SIZE := Vector2(160.0, 120.0)                                                # Set the cropped Xybots playfield size used by the prototype.
const SIDE_BY_SIDE_GUTTER := 8.0                                                            # Set the unscaled pixel gap between the 2D and 3D diagnostic panels.
const PHASE_SECONDS := 0.10                                                                 # Set how long each captured transition frame is displayed.
const MOVE_UNITS_PER_SECOND := 0.85                                                         # Set how quickly the character moves within the current tile.
const HOME_LOCAL_FLOOR_POSITION := Vector2(0.5, 0.68)                                       # Set the resting local position inside a tile.
const FORWARD_TRIGGER_Y := 0.56                                                             # Set the forward threshold where crossing into the next tile begins.
const BACKWARD_TRIGGER_Y := 0.84                                                            # Set the backward threshold where crossing into the previous tile begins.
const STRAFE_LEFT_WALL_CONTACT_X := -0.08                                                   # Set the closest blocked-wall contact position on the viewer's left.
const STRAFE_RIGHT_WALL_CONTACT_X := 1.08                                                   # Set the closest blocked-wall contact position on the viewer's right.
const FORWARD_WALL_CONTACT_Y := 0.56                                                        # Set the closest blocked-wall contact position in front of the viewer.
const BACKWARD_WALL_CONTACT_Y := 0.84                                                       # Set the closest blocked-wall contact position behind the viewer.
const HALLWAY_LENGTH := 4                                                                   # Set the number of cells in the current test hallway.

const PHASE_ROOT := "res://assets/reference_xybots_local/playfield_phases"                  # Point to captured full-frame movement and turn phase assets.
const STABLE_VIEW_ROOT := "res://assets/reference_xybots_local/stable_views"                # Point to old full-frame stable-view fallback assets.
const SLOT_ROOT := "res://assets/reference_xybots_local/environment_slots"                  # Point to old coarse slot fallback assets.
const WALLS_STRAIGHT_ROOT := "res://assets/Environment/WallsStraight"                       # Point to the 28 transparent straight-wall overlay sprites.
const FLOOR_TURN_TEXTURE := "res://assets/Environment/Floor_Turn.png"                       # Point to the floor strip whose first frame is used as the straight-view base.
const PLAYER_FRAMES := "res://assets/frames/renamed_trimmed_sequence/capture_frames.tres"   # Point to the baked player animation SpriteFrames resource.
const PLAYER_IDLE_TEXTURE := "res://assets/frames/IdleN_AimN/IdleN_AimN.png"                # Point to the user-provided first-player idle sprite.

const FAR_FLOOR_Y := 0.30                                                                   # Define a fixed value used by the movement, rendering, or asset-loading system.
const NEAR_FLOOR_Y := 0.93                                                                  # Define a fixed value used by the movement, rendering, or asset-loading system.
const FAR_FLOOR_HALF_WIDTH := 0.16                                                          # Define a fixed value used by the movement, rendering, or asset-loading system.
const NEAR_FLOOR_HALF_WIDTH := 0.48                                                         # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_N := 0                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_E := 1                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_S := 2                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_W := 3                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const VIEW_FRONT := "front"                                                                 # Define a fixed value used by the movement, rendering, or asset-loading system.
const VIEW_LEFT := "left"                                                                   # Define a fixed value used by the movement, rendering, or asset-loading system.
const VIEW_RIGHT := "right"                                                                 # Define a fixed value used by the movement, rendering, or asset-loading system.
const DEBUG_MAP_CELL_SIZE := 24.0                                                           # Set the top-down debug map cell size inside the 160x120 diagnostic panel.
const DEBUG_MAP_PANEL_GRID_ORIGIN := Vector2(68.0, 12.0)                                    # Center the one-cell-wide four-cell hallway inside the debug panel.
const DEBUG_WALL_LABELS_ENABLED := true                                                     # Enable numeric debug labels on visible wall overlay sprites.
const DIAGNOSTIC_3D_WALL_HEIGHT := 1.2                                                       # Set the generated 3D wall height in world units.
const DIAGNOSTIC_3D_WALL_THICKNESS := 0.06                                                   # Set the generated 3D thin-wall thickness in world units.
const DIAGNOSTIC_3D_CELL_WIDTH := 1.35                                                       # Widen the diagnostic cell volume so the 3D hallway better matches the 2D projection.
const DIAGNOSTIC_3D_LOCAL_SIDE_HALF_EXTENT := 0.56                                           # Convert normalized side offsets into widened 3D cell units.
const DIAGNOSTIC_3D_LOCAL_DEPTH_HALF_EXTENT := 0.42                                          # Convert normalized forward/back offsets into 3D cell units.
const DIAGNOSTIC_3D_SEPARATOR_THICKNESS := 0.025                                             # Set the thickness of black cell-separation guide strips.

const STRAIGHT_WALL_SLOTS := [                                                              # Start the table that maps wall numbers to view-relative map tests and draw order.
	{"id": 1, "lateral": -2, "depth": 4, "edge": VIEW_FRONT, "draw": 10},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 2, "lateral": -1, "depth": 4, "edge": VIEW_FRONT, "draw": 11},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 3, "lateral": -1, "depth": 3, "edge": VIEW_FRONT, "draw": 12},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 4, "lateral": 0, "depth": 3, "edge": VIEW_FRONT, "draw": 13},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 5, "lateral": 2, "depth": 4, "edge": VIEW_FRONT, "draw": 14},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 6, "lateral": -2, "depth": 3, "edge": VIEW_RIGHT, "draw": 20},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 7, "lateral": 0, "depth": 3, "edge": VIEW_LEFT, "draw": 21},                        # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 8, "lateral": 0, "depth": 3, "edge": VIEW_RIGHT, "draw": 22},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 9, "lateral": 1, "depth": 3, "edge": VIEW_LEFT, "draw": 23},                        # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 10, "lateral": -1, "depth": 3, "edge": VIEW_FRONT, "draw": 30},                     # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 11, "lateral": 0, "depth": 3, "edge": VIEW_FRONT, "draw": 31},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 12, "lateral": 0, "depth": 2, "edge": VIEW_FRONT, "draw": 32},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 13, "lateral": -2, "depth": 2, "edge": VIEW_RIGHT, "draw": 40},                     # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 14, "lateral": -1, "depth": 2, "edge": VIEW_RIGHT, "draw": 41},                     # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 15, "lateral": 0, "depth": 2, "edge": VIEW_LEFT, "draw": 42},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 16, "lateral": 0, "depth": 2, "edge": VIEW_LEFT, "draw": 43},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 17, "lateral": 0, "depth": 2, "edge": VIEW_RIGHT, "draw": 50},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 18, "lateral": 0, "depth": 2, "edge": VIEW_FRONT, "draw": 51},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 19, "lateral": 1, "depth": 2, "edge": VIEW_FRONT, "draw": 52},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 20, "lateral": 0, "depth": 1, "edge": VIEW_FRONT, "draw": 60},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 21, "lateral": 0, "depth": 1, "edge": VIEW_LEFT, "draw": 61},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 22, "lateral": 0, "depth": 1, "edge": VIEW_LEFT, "draw": 62},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 23, "lateral": 0, "depth": 1, "edge": VIEW_RIGHT, "draw": 63},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 24, "lateral": 0, "depth": 0, "edge": VIEW_LEFT, "draw": 70},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 25, "lateral": 0, "depth": 0, "edge": VIEW_FRONT, "draw": 80},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 26, "lateral": 0, "depth": 0, "edge": VIEW_FRONT, "draw": 90},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 27, "lateral": 0, "depth": 0, "edge": VIEW_LEFT, "draw": 91},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 28, "lateral": 0, "depth": 0, "edge": VIEW_RIGHT, "draw": 92},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
]                                                                                           # Close the current list, dictionary, call, or expression.

const STRAIGHT_VISIBILITY_BRANCHES := [                                                      # Define near-to-far wall checks that build the visible straight-view render list.
	[                                                                                          # Start the center sightline branch.
		{"id": 25, "occludes": true},                                                            # Check the nearest front wall first and stop the center sightline if present.
		{"id": 20, "occludes": true},                                                            # Check the next front wall if the nearest front edge is open.
		{"id": 12, "occludes": true},                                                            # Check the far center front wall.
		{"id": 4, "occludes": true},                                                             # Check the deepest center front wall.
	],                                                                                         # Close the center sightline branch.
	[                                                                                          # Start the left-center side branch.
		{"id": 27, "occludes": false},                                                           # Draw the immediate left hallway edge without hiding farther left wall segments.
		{"id": 22, "occludes": false},                                                           # Draw the next left hallway wall segment.
		{"id": 16, "occludes": false},                                                           # Draw the mid-distance left hallway wall segment.
		{"id": 7, "occludes": true},                                                             # Check the far left wall edge.
	],                                                                                         # Close the left-center side branch.
	[                                                                                          # Start the right-center side branch.
		{"id": 28, "occludes": false},                                                           # Draw the immediate right hallway edge without hiding farther right wall segments.
		{"id": 23, "occludes": false},                                                           # Draw the next right hallway wall segment.
		{"id": 17, "occludes": false},                                                           # Draw the mid-distance right hallway wall segment.
		{"id": 8, "occludes": true},                                                             # Check the far right wall edge.
	],                                                                                         # Close the right-center side branch.
	[                                                                                          # Start the outer-left branch.
		{"id": 27, "occludes": true},                                                            # Check the nearest outer-left wall edge.
		{"id": 20, "occludes": true},                                                            # Check the next outer-left wall edge.
		{"id": 14, "occludes": true},                                                            # Check the mid outer-left wall edge.
		{"id": 7, "occludes": true},                                                             # Check the far outer-left wall edge.
		{"id": 6, "occludes": true},                                                             # Check the deepest outer-left wall edge.
	],                                                                                         # Close the outer-left branch.
	[                                                                                          # Start the outer-right branch.
		{"id": 23, "occludes": true},                                                            # Recheck the near outer-right wall family for this sightline.
		{"id": 16, "occludes": true},                                                            # Check the next outer-right wall edge.
		{"id": 12, "occludes": false},                                                           # Allow a far-front right wall to add without stopping side checks.
		{"id": 9, "occludes": true},                                                             # Check the far outer-right wall edge.
	],                                                                                         # Close the outer-right branch.
	[                                                                                          # Start the far-front spread branch.
		{"id": 17, "occludes": true},                                                            # Check the far-left front wall.
		{"id": 10, "occludes": true},                                                            # Check the deeper far-left front wall.
		{"id": 2, "occludes": true},                                                             # Check the deepest far-left front wall.
	],                                                                                         # Close the far-left front branch.
	[                                                                                          # Start the far-right front branch.
		{"id": 19, "occludes": true},                                                            # Check the far-right front wall.
		{"id": 12, "occludes": true},                                                            # Check the deeper far-right front wall.
		{"id": 4, "occludes": true},                                                             # Check the deepest far-right front wall.
	],                                                                                         # Close the far-right front branch.
	[                                                                                          # Start the extreme far-front branch.
		{"id": 1, "occludes": true},                                                             # Check the extreme far-left front wall.
		{"id": 5, "occludes": true},                                                             # Check the extreme far-right front wall.
	],                                                                                         # Close the extreme far-front branch.
]                                                                                           # Close the visibility-tree branch list.

@export_group("Diagnostics")                                                                # Group inspector toggles for temporary visual debugging tools.
@export var enable_3d_diagnostic := false                                                    # Keep the experimental 3D view disabled unless it is explicitly needed.
@export var show_top_down_source_overlay := true                                             # Show the 2D source-of-truth map overlay during wall/collision debugging.

@export_group("3D Diagnostic Camera")                                                       # Group the editable 3D diagnostic camera controls in the Godot inspector.
@export_range(45.0, 110.0, 1.0) var diagnostic_3d_camera_fov := 78.0                         # Let the user tune the 3D diagnostic camera field of view.
@export_range(0.0, 0.49, 0.01) var diagnostic_3d_camera_back_offset := 0.49                  # Let the user tune how far behind the cell center the fixed camera sits.
@export_range(0.2, 1.4, 0.01) var diagnostic_3d_camera_height := 0.72                        # Let the user tune the fixed camera height inside the current cell.
@export_range(0.2, 5.0, 0.05) var diagnostic_3d_camera_target_distance := 2.1                # Let the user tune how far down the hallway the camera aims.
@export_range(0.0, 1.2, 0.01) var diagnostic_3d_camera_target_height := 0.16                 # Let the user tune the vertical point the camera looks at.

@onready var maze_viewport: Node2D = $MazeViewport                                          # Cache the node that scales and centers the cropped playfield.
@onready var playfield: Sprite2D = $MazeViewport/Playfield                                  # Cache the full-frame transition sprite.
@onready var player_sprite: AnimatedSprite2D = $MazeViewport/PlayerSprite                   # Cache the animated player sprite.
@onready var status_label: Label = $CanvasLayer/StatusLabel                                 # Cache the debug text label.
@onready var canvas_layer: CanvasLayer = $CanvasLayer                                       # Cache the overlay layer used for debug UI.

var phase_textures: Dictionary = {}                                                         # Store loaded full-frame transition texture sequences by sequence name.
var stable_textures: Dictionary = {}                                                        # Store old stable full-frame fallback textures by view name.
var slot_textures: Dictionary = {}                                                          # Store old coarse slot fallback textures by view name and slot name.
var slot_nodes: Dictionary = {}                                                             # Store old coarse slot Sprite2D nodes by slot name.
var straight_wall_textures: Dictionary = {}                                                 # Store the 28 numbered straight-wall textures by wall id.
var straight_wall_nodes: Dictionary = {}                                                    # Store the 28 numbered straight-wall Sprite2D nodes by wall id.
var straight_wall_label_nodes: Dictionary = {}                                               # Store debug labels attached to straight-wall overlay sprites.
var floor_texture: Texture2D                                                                # Store the loaded floor texture strip.
var floor_sprite: Sprite2D                                                                  # Store the base floor Sprite2D used by the straight renderer.
var environment_layer: Node2D                                                               # Store the parent node for all composited environment sprites.
var debug_map_overlay: Node2D                                                               # Store the top-down debug line map drawn over the game view.
var diagnostic_3d_viewport: SubViewport                                                     # Store the low-resolution 3D diagnostic renderer.
var diagnostic_3d_display: Sprite2D                                                         # Store the 2D sprite that displays the 3D diagnostic viewport texture.
var diagnostic_3d_world_root: Node3D                                                        # Store the generated 3D hallway root.
var diagnostic_3d_player_root: Node3D                                                       # Store the 3D player cube and forward marker parent.
var diagnostic_3d_camera: Camera3D                                                          # Store the 3D diagnostic camera that follows the player.
var diagnostic_3d_slot_labels: Dictionary = {}                                              # Store billboard labels for the 28 straight-view wall slot ids.
var active_sequence: Array[Texture2D] = []                                                  # Store the currently playing captured transition frames.
var active_sequence_name := "idle"                                                          # Store the currently playing captured transition frames.
var phase_index := 0                                                                        # Track the current frame index within the active transition.
var phase_timer := 0.0                                                                      # Accumulate time until the next transition frame should display.
var is_transitioning := false                                                               # Track whether a captured transition animation is currently playing.

var facing := 0                                                                             # Track the player camera direction as 0=N, 1=E, 2=S, 3=W.
var grid_position := Vector2i(0, 3)                                                         # Track the current cell in the top-down hallway map.
var local_floor_position := HOME_LOCAL_FLOOR_POSITION                                       # Track the character position inside the current tile.
var run_dir := DIR_N                                                                        # Track the body movement direction used for animation selection.
var aim_dir := DIR_N                                                                        # Track the aiming direction used for animation selection.
var last_animation: StringName = &""                                                        # Remember the last animation to avoid restarting it every frame.
var available_animations: Dictionary = {}                                                   # Store animation-name lookups for exact and fallback animation selection.
var pending_grid_delta := Vector2i.ZERO                                                     # Store the cell movement that will be applied after a transition finishes.
var last_blocked_direction := ""                                                            # Store the most recent blocked movement label for debug display.
var wall_edges: Dictionary = {}                                                             # Store explicit thin-wall edge flags for each open cell.
var last_visible_wall_ids: Array[int] = []                                                   # Store the currently selected straight-wall ids for debug display.



# _ready: Initializes the hallway wall data, loads textures, creates renderer nodes, and draws the starting view.
func _ready() -> void:                                                                      # Declare this function.
	_build_test_hallway_wall_edges()                                                           # Call a helper function as part of the current controller step.
	_load_phase_textures()                                                                     # Call a helper function as part of the current controller step.
	_load_stable_textures()                                                                    # Call a helper function as part of the current controller step.
	_load_slot_textures()                                                                      # Call a helper function as part of the current controller step.
	_load_straight_wall_textures()                                                             # Call a helper function as part of the current controller step.
	_setup_viewport()                                                                          # Call a helper function as part of the current controller step.
	_setup_environment_layer()                                                                 # Call a helper function as part of the current controller step.
	if enable_3d_diagnostic:                                                                   # Only create the deprecated 3D diagnostic when explicitly requested.
		_setup_3d_diagnostic()                                                                    # Create the side-by-side 3D map diagnostic view.
	_setup_debug_map_overlay()                                                                 # Create the top-down debug map overlay above the game view.
	_setup_player_animation()                                                                  # Call a helper function as part of the current controller step.
	_show_stable()                                                                             # Call a helper function as part of the current controller step.
	_position_player()                                                                         # Call a helper function as part of the current controller step.
	if enable_3d_diagnostic:                                                                   # Only sync the deprecated 3D diagnostic when it exists.
		_update_3d_diagnostic()                                                                   # Sync the 3D diagnostic view to the starting player state.
	_play_best_animation(false)                                                                # Call a helper function as part of the current controller step.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _process: Runs the per-frame input, movement, transition, animation, player positioning, and status update loop.
func _process(delta: float) -> void:                                                        # Declare this function.
	_layout_viewport()                                                                         # Call a helper function as part of the current controller step.
	_update_debug_map_overlay()                                                                # Keep the top-down debug map aligned with the scaled playfield.

	if is_transitioning:                                                                       # Run the following block only when this condition is true.
		_advance_transition(delta)                                                                # Call a helper function as part of the current controller step.
		_position_player()                                                                        # Call a helper function as part of the current controller step.
		if enable_3d_diagnostic:                                                                  # Only sync the deprecated 3D diagnostic when it is enabled.
			_update_3d_diagnostic()                                                                  # Keep the 3D diagnostic camera and cube aligned during transition playback.
		return                                                                                    # Return to the caller without producing a value.

	var turn_direction := _read_turn()                                                         # Store mutable runtime state for assets, rendering, movement, or debug output.
	if turn_direction < 0:                                                                     # Run the following block only when this condition is true.
		_start_transition("turn_left")                                                            # Call a helper function as part of the current controller step.
		return                                                                                    # Return to the caller without producing a value.
	if turn_direction > 0:                                                                     # Run the following block only when this condition is true.
		_start_transition("turn_right")                                                           # Call a helper function as part of the current controller step.
		return                                                                                    # Return to the caller without producing a value.

	var movement := _read_movement()                                                           # Store mutable runtime state for assets, rendering, movement, or debug output.
	if movement != Vector2.ZERO:                                                               # Run the following block only when this condition is true.
		run_dir = _movement_to_first_player_run_dir(movement)                                     # Compute and store this value for the current step.
		aim_dir = DIR_N                                                                           # Compute and store this value for the current step.
		_play_best_animation(true)                                                                # Call a helper function as part of the current controller step.
		_move_inside_tile(movement, delta)                                                        # Move after choosing the animation so sprite-width collision bounds match the visible frame.
	else:                                                                                      # Run this fallback branch when previous conditions were not met.
		run_dir = DIR_N                                                                           # Compute and store this value for the current step.
		aim_dir = DIR_N                                                                           # Compute and store this value for the current step.
		_play_best_animation(false)                                                               # Call a helper function as part of the current controller step.

	_position_player()                                                                         # Call a helper function as part of the current controller step.
	if enable_3d_diagnostic:                                                                   # Only sync the deprecated 3D diagnostic when it is enabled.
		_update_3d_diagnostic()                                                                   # Keep the 3D diagnostic camera and cube aligned with the 2D playfield state.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _setup_viewport: Configures nearest-neighbor rendering for the playfield and player, then lays out the cropped viewport.
func _setup_viewport() -> void:                                                             # Declare this function.
	playfield.centered = false                                                                 # Update the captured playfield sprite display.
	playfield.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                               # Update the captured playfield sprite display.
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                           # Update player sprite rendering or animation state.
	_layout_viewport()                                                                         # Call a helper function as part of the current controller step.



# _setup_environment_layer: Creates the runtime floor, straight-wall, and legacy slot sprites used to compose the environment.
func _setup_environment_layer() -> void:                                                    # Declare this function.
	environment_layer = Node2D.new()                                                           # Compute and store this value for the current step.
	environment_layer.name = "EnvironmentRenderer"                                             # Update the environment renderer container.
	environment_layer.z_index = -100                                                           # Keep wall-overlay child z layers behind the player sprite.
	maze_viewport.add_child(environment_layer)                                                 # Update the cropped playfield container transform.

	floor_sprite = Sprite2D.new()                                                              # Compute and store this value for the current step.
	floor_sprite.name = "Floor"                                                                # Update the reusable base floor sprite.
	floor_sprite.centered = false                                                              # Update the reusable base floor sprite.
	floor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                            # Update the reusable base floor sprite.
	floor_sprite.region_enabled = true                                                         # Update the reusable base floor sprite.
	floor_sprite.region_rect = Rect2(0.0, 0.0, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y)               # Update the reusable base floor sprite.
	floor_sprite.z_index = 0                                                                   # Update the reusable base floor sprite.
	environment_layer.add_child(floor_sprite)                                                  # Update the environment renderer container.

	for wall_id in range(1, 29):                                                               # Iterate across this collection or range.
		var wall_sprite := Sprite2D.new()                                                         # Store mutable runtime state for assets, rendering, movement, or debug output.
		wall_sprite.name = "WallStraight%02d" % wall_id                                           # Configure or update one numbered wall overlay sprite.
		wall_sprite.centered = false                                                              # Configure or update one numbered wall overlay sprite.
		wall_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                            # Configure or update one numbered wall overlay sprite.
		wall_sprite.position = Vector2.ZERO                                                       # Configure or update one numbered wall overlay sprite.
		environment_layer.add_child(wall_sprite)                                                  # Update the environment renderer container.
		straight_wall_nodes[wall_id] = wall_sprite                                                # Compute and store this value for the current step.
		var wall_label := Label.new()                                                             # Create a debug number label for this wall overlay.
		wall_label.name = "DebugLabel"                                                            # Name the label node for scene-tree inspection.
		wall_label.text = "%02d" % wall_id                                                         # Show the numbered wall id on top of the wall art.
		wall_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.0, 1.0))             # Use yellow text so the label stands out on blue wall art.
		wall_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))       # Add black shadow for readability.
		wall_label.add_theme_constant_override("shadow_offset_x", 1)                              # Offset the debug label shadow one pixel right.
		wall_label.add_theme_constant_override("shadow_offset_y", 1)                              # Offset the debug label shadow one pixel down.
		wall_label.scale = Vector2(0.35, 0.35)                                                    # Keep the debug label readable without covering the wall art.
		wall_label.visible = DEBUG_WALL_LABELS_ENABLED                                           # Respect the debug label enable flag.
		wall_sprite.add_child(wall_label)                                                         # Attach the label to this wall sprite so visibility follows the wall.
		straight_wall_label_nodes[wall_id] = wall_label                                           # Store the label for positioning when the wall is drawn.

	for slot_name in ["floor", "left_wall", "right_wall", "center_back", "ceiling"]:           # Iterate across this collection or range.
		var slot_sprite := Sprite2D.new()                                                         # Store mutable runtime state for assets, rendering, movement, or debug output.
		slot_sprite.name = slot_name                                                              # Configure or update a legacy slot sprite.
		slot_sprite.centered = false                                                              # Configure or update a legacy slot sprite.
		slot_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                            # Configure or update a legacy slot sprite.
		slot_sprite.z_index = _slot_z_index(slot_name)                                            # Configure or update a legacy slot sprite.
		slot_sprite.visible = false                                                               # Configure or update a legacy slot sprite.
		environment_layer.add_child(slot_sprite)                                                  # Update the environment renderer container.
		slot_nodes[slot_name] = slot_sprite                                                       # Compute and store this value for the current step.



# _setup_3d_diagnostic: Builds a 160x120 3D SubViewport that visualizes the same hallway map beside the 2D renderer.
func _setup_3d_diagnostic() -> void:                                                        # Declare this function.
	if not enable_3d_diagnostic:                                                              # Keep the deprecated diagnostic dormant unless the inspector toggle is enabled.
		return                                                                                    # Return without creating any 3D diagnostic nodes.
	diagnostic_3d_viewport = SubViewport.new()                                                 # Create the offscreen 3D viewport.
	diagnostic_3d_viewport.name = "Diagnostic3DViewport"                                       # Name the viewport for scene-tree inspection.
	diagnostic_3d_viewport.size = Vector2i(int(VIEWPORT_SIZE.x), int(VIEWPORT_SIZE.y))         # Match the cropped playfield resolution exactly.
	diagnostic_3d_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS               # Render the 3D diagnostic view every frame.
	diagnostic_3d_viewport.own_world_3d = true                                                  # Keep the diagnostic world separate from any future main 3D scene.
	add_child(diagnostic_3d_viewport)                                                           # Attach the offscreen viewport to the main scene.

	diagnostic_3d_display = Sprite2D.new()                                                       # Create the 2D display sprite for the 3D viewport texture.
	diagnostic_3d_display.name = "Diagnostic3DDisplay"                                          # Name the display node for scene-tree inspection.
	diagnostic_3d_display.centered = false                                                       # Anchor the 3D panel from its top-left corner like the 2D playfield.
	diagnostic_3d_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                    # Preserve the low-resolution diagnostic pixels when scaled.
	diagnostic_3d_display.texture = diagnostic_3d_viewport.get_texture()                         # Show the live 3D viewport texture in the 2D scene.
	add_child(diagnostic_3d_display)                                                             # Attach the display beside the 2D playfield.

	diagnostic_3d_world_root = Node3D.new()                                                      # Create the root for all diagnostic 3D content.
	diagnostic_3d_world_root.name = "Diagnostic3DWorld"                                         # Name the 3D root for scene-tree inspection.
	diagnostic_3d_viewport.add_child(diagnostic_3d_world_root)                                  # Place the 3D world inside the offscreen viewport.

	var world_environment := WorldEnvironment.new()                                              # Create a background and ambient-light environment.
	world_environment.name = "Diagnostic3DEnvironment"                                          # Name the environment node for scene-tree inspection.
	var environment := Environment.new()                                                         # Create the environment resource used by the viewport.
	environment.background_mode = Environment.BG_COLOR                                           # Use a flat color background for readable diagnostics.
	environment.background_color = Color(0.03, 0.035, 0.045, 1.0)                                # Set a dark neutral background outside the hallway.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR                          # Use constant ambient light so the cubes are easy to read.
	environment.ambient_light_color = Color(0.42, 0.44, 0.50, 1.0)                               # Set the ambient light color.
	environment.ambient_light_energy = 0.75                                                      # Set the ambient light strength.
	world_environment.environment = environment                                                  # Assign the environment resource to the 3D world.
	diagnostic_3d_world_root.add_child(world_environment)                                       # Add the environment to the diagnostic 3D world.

	var sun := DirectionalLight3D.new()                                                          # Create a directional light to reveal wall depth.
	sun.name = "Diagnostic3DLight"                                                               # Name the light for scene-tree inspection.
	sun.light_energy = 1.8                                                                       # Set the light strength.
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)                                           # Aim the light down the hallway at an angle.
	diagnostic_3d_world_root.add_child(sun)                                                     # Add the light to the diagnostic 3D world.

	_build_3d_hallway_geometry()                                                                 # Generate 3D floor, ceiling, and thin-wall cubes from the map.
	_build_3d_player_marker()                                                                    # Create the player cube and forward indicator.

	diagnostic_3d_camera = Camera3D.new()                                                        # Create the 3D camera for the diagnostic view.
	diagnostic_3d_camera.name = "Diagnostic3DCamera"                                            # Name the camera for scene-tree inspection.
	diagnostic_3d_camera.current = true                                                          # Make this camera active inside the diagnostic viewport.
	diagnostic_3d_camera.fov = diagnostic_3d_camera_fov                                          # Apply the inspector-controlled diagnostic camera field of view.
	diagnostic_3d_camera.near = 0.02                                                             # Allow the close camera to sit inside one tile without near clipping.
	diagnostic_3d_world_root.add_child(diagnostic_3d_camera)                                    # Add the camera to the diagnostic 3D world.
	_setup_3d_slot_labels()                                                                      # Create hidden billboard labels for the numbered 2D wall slots.

	_layout_viewport()                                                                           # Re-run layout now that the 3D display sprite exists.



# _build_3d_hallway_geometry: Creates visible 3D floor, ceiling, and wall cubes from the thin-wall hallway data.
func _build_3d_hallway_geometry() -> void:                                                  # Declare this function.
	var floor_material := _make_3d_material(Color(0.76, 0.49, 0.24, 1.0))                      # Create the diagnostic floor material.
	var ceiling_material := _make_3d_material(Color(0.52, 0.35, 0.18, 1.0))                    # Create the diagnostic ceiling material.
	var wall_material := _make_3d_material(Color(0.34, 0.40, 0.76, 1.0))                       # Create the diagnostic side-wall material.
	var end_wall_material := _make_3d_material(Color(0.20, 0.25, 0.42, 1.0))                   # Create the diagnostic end-wall material.
	var separator_material := _make_3d_material(Color(0.02, 0.02, 0.02, 1.0))                  # Create a dark material for cell boundary guide strips.

	for y in range(HALLWAY_LENGTH):                                                            # Generate one cubic cell for each row of the test hallway.
		var cell := Vector2i(0, y)                                                                # Build the current hallway cell coordinate.
		var center := _grid_cell_center_to_3d(cell)                                               # Convert this cell center into 3D world space.
		_add_3d_box("Floor_%d" % y, center + Vector3(0.0, -0.025, 0.0), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, 0.05, 1.0), floor_material) # Add a thin floor slab for this widened cell.
		_add_3d_box("Ceiling_%d" % y, center + Vector3(0.0, DIAGNOSTIC_3D_WALL_HEIGHT, 0.0), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, 0.05, 1.0), ceiling_material) # Add a thin ceiling slab for this widened cell.
		if _has_wall_edge(cell, Vector2i(-1, 0)):                                                  # Check the west edge for a thin wall.
			_add_3d_box("Wall_W_%d" % y, Vector3(0.0 - DIAGNOSTIC_3D_WALL_THICKNESS * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) + 0.5), Vector3(DIAGNOSTIC_3D_WALL_THICKNESS, DIAGNOSTIC_3D_WALL_HEIGHT, 1.0), wall_material) # Add a west wall segment.
		if _has_wall_edge(cell, Vector2i(1, 0)):                                                   # Check the east edge for a thin wall.
			_add_3d_box("Wall_E_%d" % y, Vector3(DIAGNOSTIC_3D_CELL_WIDTH + DIAGNOSTIC_3D_WALL_THICKNESS * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) + 0.5), Vector3(DIAGNOSTIC_3D_WALL_THICKNESS, DIAGNOSTIC_3D_WALL_HEIGHT, 1.0), wall_material) # Add an east wall segment.
		if _has_wall_edge(cell, Vector2i(0, -1)):                                                  # Check the north edge for a thin wall.
			_add_3d_box("Wall_N_%d" % y, Vector3(DIAGNOSTIC_3D_CELL_WIDTH * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) - DIAGNOSTIC_3D_WALL_THICKNESS * 0.5), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, DIAGNOSTIC_3D_WALL_HEIGHT, DIAGNOSTIC_3D_WALL_THICKNESS), end_wall_material) # Add a north end-wall segment.
		if _has_wall_edge(cell, Vector2i(0, 1)):                                                   # Check the south edge for a thin wall.
			_add_3d_box("Wall_S_%d" % y, Vector3(DIAGNOSTIC_3D_CELL_WIDTH * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) + 1.0 + DIAGNOSTIC_3D_WALL_THICKNESS * 0.5), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, DIAGNOSTIC_3D_WALL_HEIGHT, DIAGNOSTIC_3D_WALL_THICKNESS), end_wall_material) # Add a south end-wall segment.

	for boundary in range(HALLWAY_LENGTH + 1):                                                # Add visible cross-lines at every cell boundary along the hallway.
		var z := float(boundary)                                                                 # Convert this boundary index into 3D z space.
		_add_3d_box("FloorBoundary_%d" % boundary, Vector3(DIAGNOSTIC_3D_CELL_WIDTH * 0.5, 0.012, z), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, DIAGNOSTIC_3D_SEPARATOR_THICKNESS, DIAGNOSTIC_3D_SEPARATOR_THICKNESS), separator_material) # Draw a dark line across the floor.
		_add_3d_box("WestWallBoundary_%d" % boundary, Vector3(0.012, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, z), Vector3(DIAGNOSTIC_3D_SEPARATOR_THICKNESS, DIAGNOSTIC_3D_WALL_HEIGHT, DIAGNOSTIC_3D_SEPARATOR_THICKNESS), separator_material) # Draw a dark divider on the west wall.
		_add_3d_box("EastWallBoundary_%d" % boundary, Vector3(DIAGNOSTIC_3D_CELL_WIDTH - 0.012, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, z), Vector3(DIAGNOSTIC_3D_SEPARATOR_THICKNESS, DIAGNOSTIC_3D_WALL_HEIGHT, DIAGNOSTIC_3D_SEPARATOR_THICKNESS), separator_material) # Draw a dark divider on the east wall.



# _build_3d_player_marker: Creates a tall player-volume block plus a red forward-facing marker inside the diagnostic world.
func _build_3d_player_marker() -> void:                                                    # Declare this function.
	diagnostic_3d_player_root = Node3D.new()                                                   # Create a movable parent for the diagnostic player marker.
	diagnostic_3d_player_root.name = "Diagnostic3DPlayer"                                      # Name the player marker root for scene-tree inspection.
	diagnostic_3d_world_root.add_child(diagnostic_3d_player_root)                              # Add the player marker to the diagnostic 3D world.

	var body_material := _make_3d_material(Color(0.0, 0.85, 1.0, 1.0))                          # Create a cyan material for the player body cube.
	_add_3d_box_to_parent(diagnostic_3d_player_root, "Body", Vector3(0.0, 0.23, 0.0), Vector3(0.14, 0.46, 0.10), body_material) # Add a tall but readable rectangular block approximating the player's occupied volume.



# _setup_3d_slot_labels: Creates billboard labels for the same numbered straight-wall slots used by the 2D renderer.
func _setup_3d_slot_labels() -> void:                                                       # Declare this function.
	diagnostic_3d_slot_labels.clear()                                                          # Clear any previous label references.
	for wall_id in range(1, 29):                                                               # Create one reusable label for every straight-wall slot id.
		var label := Label3D.new()                                                                # Create a 3D text label.
		label.name = "SlotLabel%02d" % wall_id                                                     # Name the label node for scene-tree inspection.
		label.text = "%02d" % wall_id                                                             # Match the two-digit labels drawn in the 2D player view.
		label.modulate = Color(1.0, 0.95, 0.0, 1.0)                                               # Match the yellow debug labels used in the 2D view.
		label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)                                        # Add a dark outline for readability.
		label.outline_size = 8                                                                     # Set a thick enough outline for the low-resolution viewport.
		label.font_size = 48                                                                       # Set a large source font before scaling the label down.
		label.pixel_size = 0.0048                                                                  # Scale the billboard text into the wall coordinate system.
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED                                        # Keep the label facing the camera instead of lying flat on the wall.
		label.visible = false                                                                      # Hide the label until its slot is visible.
		diagnostic_3d_world_root.add_child(label)                                                 # Add the label to the diagnostic 3D world.
		diagnostic_3d_slot_labels[wall_id] = label                                                # Store the label by numbered straight-wall slot id.



# _update_3d_slot_labels: Shows billboard labels for the currently visible numbered straight-wall slots.
func _update_3d_slot_labels(visible_slots: Array) -> void:                                  # Declare this function.
	_hide_3d_slot_labels()                                                                     # Start from all labels hidden before showing the currently visible wall slots.
	for slot in visible_slots:                                                                 # Iterate through the same slots selected by the 2D straight-wall renderer.
		var wall_id := int(slot["id"])                                                            # Read the 2D player-view slot id.
		var label: Label3D = diagnostic_3d_slot_labels.get(wall_id)                               # Look up the matching billboard label.
		if label == null:                                                                          # Skip missing labels defensively.
			continue                                                                                 # Continue to the next visible slot.
		var depth := int(slot["depth"])                                                            # Read the slot depth so close labels can be scaled smaller.
		label.pixel_size = lerpf(0.0022, 0.0062, clampf(float(depth) / 4.0, 0.0, 1.0))             # Keep near billboard labels compact and distant labels readable.
		label.position = _straight_slot_label_position_3d(slot)                                   # Place the label on the corresponding 3D wall surface.
		label.visible = true                                                                       # Show this visible numbered wall slot in the 3D diagnostic view.



# _hide_3d_slot_labels: Hides every 3D numbered wall-slot label.
func _hide_3d_slot_labels() -> void:                                                        # Declare this function.
	for label in diagnostic_3d_slot_labels.values():                                           # Iterate through all reusable 3D slot labels.
		if label is Label3D:                                                                       # Ensure this dictionary value is a Label3D before touching it.
			label.visible = false                                                                    # Hide the label.



# _straight_slot_label_position_3d: Converts one visible 2D wall slot into a 3D billboard label position.
func _straight_slot_label_position_3d(slot: Dictionary) -> Vector3:                         # Declare this function.
	var lateral := int(slot["lateral"])                                                        # Read the view-relative lateral slot coordinate.
	var depth := int(slot["depth"])                                                            # Read the view-relative depth slot coordinate.
	var edge := String(slot["edge"])                                                           # Read which wall edge this slot represents.
	var cell := _view_cell(lateral, depth)                                                     # Convert the view-relative slot cell into a world grid cell.
	var center := _grid_cell_center_to_3d(cell)                                                # Convert that grid cell into 3D world space.
	var label_height := lerpf(0.86, 0.48, clampf(float(depth) / 4.0, 0.0, 1.0))                # Lower farther labels so they stay near the visible wall centers.
	var inset := 0.12                                                                          # Keep labels inside the hallway enough to remain readable near the screen edges.
	match edge:                                                                                # Place the label on the relevant physical wall surface.
		VIEW_FRONT:                                                                               # Handle front-facing wall pieces.
			return center + _grid_delta_to_3d(_facing_vector()) * (0.5 - inset) + Vector3(0.0, label_height, 0.0) # Place the label on the forward wall face.
		VIEW_LEFT:                                                                                # Handle viewer-left wall pieces.
			return center + _grid_delta_to_3d(_left_vector()) * _half_cell_extent_for_delta(_left_vector(), inset) + Vector3(0.0, label_height, 0.0) # Place the label on the left wall face.
		VIEW_RIGHT:                                                                               # Handle viewer-right wall pieces.
			var right_delta := -_left_vector()                                                       # Compute the viewer-right world direction.
			return center + _grid_delta_to_3d(right_delta) * _half_cell_extent_for_delta(right_delta, inset) + Vector3(0.0, label_height, 0.0) # Place the label on the right wall face.
		_:                                                                                        # Handle invalid slot metadata defensively.
			return center + Vector3(0.0, label_height, 0.0)                                           # Fall back to the cell center.



# _half_cell_extent_for_delta: Returns the half-size to the requested wall face, accounting for the widened 3D x-axis.
func _half_cell_extent_for_delta(delta: Vector2i, inset: float) -> float:                  # Declare this function.
	if delta.x != 0:                                                                           # Check whether this wall face lies on the widened horizontal axis.
		return DIAGNOSTIC_3D_CELL_WIDTH * 0.5 - inset                                            # Return the widened half-cell extent minus a visibility inset.
	return 0.5 - inset                                                                         # Return the normal depth half-cell extent minus a visibility inset.



# _add_3d_box: Adds a box mesh to the generated diagnostic hallway root.
func _add_3d_box(name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D: # Declare this function.
	return _add_3d_box_to_parent(diagnostic_3d_world_root, name, position, size, material)     # Add the box under the diagnostic world root.



# _add_3d_box_to_parent: Creates a box mesh instance under the requested 3D parent node.
func _add_3d_box_to_parent(parent: Node3D, name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D: # Declare this function.
	var mesh := BoxMesh.new()                                                                  # Create the cube mesh resource.
	mesh.size = size                                                                           # Set this cube's dimensions in world units.
	var instance := MeshInstance3D.new()                                                       # Create the renderable mesh instance.
	instance.name = name                                                                       # Name the mesh instance for scene-tree inspection.
	instance.mesh = mesh                                                                       # Assign the box mesh to the instance.
	instance.material_override = material                                                      # Assign the diagnostic material to the instance.
	instance.position = position                                                               # Place the box in local 3D space.
	parent.add_child(instance)                                                                 # Attach the box to the requested 3D parent.
	return instance                                                                            # Return the created mesh instance for optional later use.



# _make_3d_material: Builds an untextured material for readable 3D diagnostic geometry.
func _make_3d_material(color: Color) -> StandardMaterial3D:                                 # Declare this function.
	var material := StandardMaterial3D.new()                                                   # Create a material resource.
	material.albedo_color = color                                                              # Set the material base color.
	material.roughness = 0.82                                                                  # Keep surfaces matte for easier reading.
	return material                                                                            # Return the configured material.



# _layout_viewport: Scales and centers the 160x120 playfield crop inside the current Godot window.
func _layout_viewport() -> void:                                                            # Declare this function.
	var viewport_size := get_viewport_rect().size                                              # Store mutable runtime state for assets, rendering, movement, or debug output.
	var panel_count := 1                                                                       # Start with the main 2D playfield panel.
	if show_top_down_source_overlay and debug_map_overlay != null:                             # Reserve a side panel for the enlarged source-of-truth map.
		panel_count += 1                                                                          # Count the top-down map panel in the side-by-side layout.
	if enable_3d_diagnostic and diagnostic_3d_display != null:                                 # Reserve an extra panel only while the deprecated 3D diagnostic is active.
		panel_count += 1                                                                          # Count the optional 3D diagnostic panel after the map.
	var combined_size := Vector2(VIEWPORT_SIZE.x * float(panel_count) + SIDE_BY_SIDE_GUTTER * float(panel_count - 1), VIEWPORT_SIZE.y) # Compute the unscaled multi-panel layout size.
	var view_scale := minf(viewport_size.x / combined_size.x, viewport_size.y / combined_size.y) # Store mutable runtime state for assets, rendering, movement, or debug output.
	var scaled_size := combined_size * view_scale                                               # Store mutable runtime state for assets, rendering, movement, or debug output.
	var layout_origin := (viewport_size - scaled_size) * 0.5                                    # Compute the centered top-left of both playfield panels.
	maze_viewport.scale = Vector2.ONE * view_scale                                             # Update the cropped playfield container transform.
	maze_viewport.position = layout_origin                                                     # Update the cropped 2D playfield container transform.
	var next_panel_x := layout_origin.x + (VIEWPORT_SIZE.x + SIDE_BY_SIDE_GUTTER) * view_scale # Compute the x coordinate for the next right-side diagnostic panel.
	if debug_map_overlay != null:                                                              # Layout the enlarged top-down map when its node exists.
		debug_map_overlay.visible = show_top_down_source_overlay                                  # Hide or show the source map based on the inspector toggle.
		debug_map_overlay.scale = Vector2.ONE * view_scale                                        # Scale the map panel at the same pixel size as the 2D playfield.
		debug_map_overlay.position = Vector2(next_panel_x, layout_origin.y)                       # Place the map in the first right-side diagnostic panel.
		if show_top_down_source_overlay:                                                         # Advance the panel cursor only when the source map is visible.
			next_panel_x += (VIEWPORT_SIZE.x + SIDE_BY_SIDE_GUTTER) * view_scale                     # Move the next optional panel to the right of the map.
	if enable_3d_diagnostic and diagnostic_3d_display != null:                                 # Only layout the 3D view after it has been created and enabled.
		diagnostic_3d_display.scale = Vector2.ONE * view_scale                                    # Scale the 3D viewport texture at the same pixel size as the 2D view.
		diagnostic_3d_display.position = Vector2(next_panel_x, layout_origin.y)                   # Place the optional 3D panel to the right of the map panel.
		diagnostic_3d_display.visible = true                                                      # Show the deprecated 3D panel when it is enabled.
	elif diagnostic_3d_display != null:                                                        # Hide an existing 3D display if the toggle is turned off during a run.
		diagnostic_3d_display.visible = false                                                     # Keep the deprecated 3D panel out of the default prototype view.



# _setup_debug_map_overlay: Creates a runtime top-down map overlay for comparing map state to the rendered wall view.
func _setup_debug_map_overlay() -> void:                                                     # Declare this function.
	debug_map_overlay = Node2D.new()                                                           # Create the parent node for the top-down map lines and arrow.
	debug_map_overlay.name = "DebugTopDownMap"                                                 # Name the overlay node so it is easy to find in the scene tree.
	debug_map_overlay.z_index = 100                                                            # Draw the debug map above status and playfield art.
	canvas_layer.add_child(debug_map_overlay)                                                  # Attach the debug map to the UI canvas layer.
	_update_debug_map_overlay()                                                                # Draw the first version immediately after setup.



# _update_debug_map_overlay: Redraws the top-down hallway, thin-wall edges, player cell, and facing arrow.
func _update_debug_map_overlay() -> void:                                                    # Declare this function.
	if debug_map_overlay == null:                                                              # Skip drawing if the overlay has not been created yet.
		return                                                                                    # Return without drawing the map.
	debug_map_overlay.visible = show_top_down_source_overlay                                   # Apply the inspector/debug toggle before doing any drawing work.
	if not show_top_down_source_overlay:                                                       # Avoid rebuilding hidden debug primitives when the overlay is off.
		return                                                                                    # Return without drawing the map.

	for child in debug_map_overlay.get_children():                                             # Remove previous line and marker nodes before redrawing.
		child.free()                                                                              # Free the previous debug primitive immediately.
	_add_debug_panel_background()                                                             # Draw the dark 160x120 panel behind the source-of-truth map.

	var open_color := Color(0.2, 0.45, 0.55, 0.55)                                             # Define the color for non-blocking cell guide lines.
	var wall_color := Color(1.0, 1.0, 1.0, 0.95)                                               # Define the color for blocking wall edges.
	var player_color := Color(0.0, 0.95, 1.0, 0.95)                                           # Define the color for the player marker and facing arrow.

	for y in range(HALLWAY_LENGTH):                                                            # Draw every cell in the current four-cell test hallway.
		var cell := Vector2i(0, y)                                                                # Build the map cell coordinate for this hallway row.
		var top_left := _debug_map_cell_top_left(cell)                                           # Convert the map cell to overlay pixel coordinates.
		var top_right := top_left + Vector2(DEBUG_MAP_CELL_SIZE, 0.0)                            # Compute the top-right corner of the cell.
		var bottom_left := top_left + Vector2(0.0, DEBUG_MAP_CELL_SIZE)                          # Compute the bottom-left corner of the cell.
		var bottom_right := top_left + Vector2(DEBUG_MAP_CELL_SIZE, DEBUG_MAP_CELL_SIZE)         # Compute the bottom-right corner of the cell.
		_add_debug_line(top_left, top_right, open_color, 1.0)                                    # Draw the north guide edge for this cell.
		_add_debug_line(top_right, bottom_right, open_color, 1.0)                                # Draw the east guide edge for this cell.
		_add_debug_line(bottom_left, bottom_right, open_color, 1.0)                              # Draw the south guide edge for this cell.
		_add_debug_line(top_left, bottom_left, open_color, 1.0)                                  # Draw the west guide edge for this cell.
		if _has_wall_edge(cell, Vector2i(0, -1)):                                                # Check whether the north edge is blocked by a thin wall.
			_add_debug_line(top_left, top_right, wall_color, 3.0)                                   # Draw the north wall edge as a thick line.
		if _has_wall_edge(cell, Vector2i(1, 0)):                                                 # Check whether the east edge is blocked by a thin wall.
			_add_debug_line(top_right, bottom_right, wall_color, 3.0)                               # Draw the east wall edge as a thick line.
		if _has_wall_edge(cell, Vector2i(0, 1)):                                                 # Check whether the south edge is blocked by a thin wall.
			_add_debug_line(bottom_left, bottom_right, wall_color, 3.0)                             # Draw the south wall edge as a thick line.
		if _has_wall_edge(cell, Vector2i(-1, 0)):                                                # Check whether the west edge is blocked by a thin wall.
			_add_debug_line(top_left, bottom_left, wall_color, 3.0)                                  # Draw the west wall edge as a thick line.

	var home_center := _debug_map_cell_center(grid_position)                                    # Convert the current cell center into an overlay reference position.
	var player_center := _debug_map_player_position()                                           # Convert the actual intra-cell player offset into overlay coordinates.
	_add_debug_player_bounds(home_center)                                                       # Draw the playable/contact footprint inside the current cell.
	_add_debug_player_marker(home_center, Color(1.0, 1.0, 1.0, 0.35))                           # Draw a faint marker at the home center for offset comparison.
	var facing_end := player_center + Vector2(_facing_vector()) * (DEBUG_MAP_CELL_SIZE * 0.34)  # Compute the arrow tip from the actual current player position.
	_add_debug_line(player_center, facing_end, player_color, 3.0)                               # Draw the player facing arrow shaft.
	_add_debug_arrow_head(facing_end, Vector2(_facing_vector()), player_color)                  # Draw the player facing arrow head.
	_add_debug_player_marker(player_center, player_color)                                      # Draw the player position marker.



# _debug_map_cell_top_left: Converts a grid cell coordinate into a debug overlay top-left pixel position.
func _debug_map_cell_top_left(cell: Vector2i) -> Vector2:                                    # Declare this function.
	return DEBUG_MAP_PANEL_GRID_ORIGIN + Vector2(float(cell.x) * DEBUG_MAP_CELL_SIZE, float(cell.y) * DEBUG_MAP_CELL_SIZE) # Return the cell's top-left panel coordinate.



# _debug_map_cell_center: Converts a grid cell coordinate into a debug overlay center pixel position.
func _debug_map_cell_center(cell: Vector2i) -> Vector2:                                      # Declare this function.
	return _debug_map_cell_top_left(cell) + Vector2.ONE * (DEBUG_MAP_CELL_SIZE * 0.5)          # Return the center of this cell on the debug overlay.



# _debug_map_player_position: Converts the real player cell plus local offset into a top-down overlay point.
func _debug_map_player_position() -> Vector2:                                               # Declare this function.
	var local_offset := _local_position_to_tile_offset(local_floor_position)                   # Convert art-space position into right/forward tile offset.
	var world_offset := Vector2(-_left_vector()) * local_offset.x + Vector2(_facing_vector()) * local_offset.y # Rotate the local offset into world grid axes.
	return _debug_map_cell_center(grid_position) + world_offset * (DEBUG_MAP_CELL_SIZE * 0.42) # Return the overlay coordinate for the true intra-cell player position.



# _add_debug_player_bounds: Draws the current cell's source-of-truth movement/contact footprint.
func _add_debug_player_bounds(center: Vector2) -> void:                                     # Declare this function.
	var bounds_color := Color(0.0, 0.95, 1.0, 0.35)                                           # Use translucent cyan for the reachable local-position area.
	var half_extent := DEBUG_MAP_CELL_SIZE * 0.42                                             # Match the debug player's normalized -1..1 movement span.
	var top_left := center + Vector2(-half_extent, -half_extent)                              # Compute the top-left of the contact footprint.
	var top_right := center + Vector2(half_extent, -half_extent)                              # Compute the top-right of the contact footprint.
	var bottom_left := center + Vector2(-half_extent, half_extent)                            # Compute the bottom-left of the contact footprint.
	var bottom_right := center + Vector2(half_extent, half_extent)                            # Compute the bottom-right of the contact footprint.
	_add_debug_line(top_left, top_right, bounds_color, 1.0)                                   # Draw the front contact/limit guide.
	_add_debug_line(top_right, bottom_right, bounds_color, 1.0)                               # Draw the right contact/limit guide.
	_add_debug_line(bottom_left, bottom_right, bounds_color, 1.0)                             # Draw the back contact/limit guide.
	_add_debug_line(top_left, bottom_left, bounds_color, 1.0)                                 # Draw the left contact/limit guide.



# _add_debug_panel_background: Adds a 160x120 dark panel behind the enlarged top-down source map.
func _add_debug_panel_background() -> void:                                                 # Declare this function.
	var background := Polygon2D.new()                                                          # Create a filled rectangle for the diagnostic panel background.
	background.polygon = PackedVector2Array([                                                  # Define the four corners of the 160x120 source map panel.
		Vector2.ZERO,                                                                             # Add the top-left corner.
		Vector2(VIEWPORT_SIZE.x, 0.0),                                                            # Add the top-right corner.
		VIEWPORT_SIZE,                                                                            # Add the bottom-right corner.
		Vector2(0.0, VIEWPORT_SIZE.y),                                                            # Add the bottom-left corner.
	])                                                                                          # Close the panel polygon point list.
	background.color = Color(0.04, 0.05, 0.06, 0.92)                                           # Fill the panel with a dark diagnostic background.
	background.z_index = -10                                                                    # Keep the background behind the map lines and markers.
	debug_map_overlay.add_child(background)                                                     # Add the background to the map panel.



# _add_debug_line: Adds one line segment to the top-down debug map overlay.
func _add_debug_line(start: Vector2, end: Vector2, color: Color, width: float) -> void:       # Declare this function.
	var line := Line2D.new()                                                                    # Create a line primitive for the overlay.
	line.points = PackedVector2Array([start, end])                                             # Set the two endpoints of this debug line.
	line.width = width                                                                          # Set the line thickness.
	line.default_color = color                                                                  # Set the line color.
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                                    # Keep debug lines crisp at pixel-art scale.
	debug_map_overlay.add_child(line)                                                          # Add the line to the overlay node.



# _add_debug_player_marker: Adds a small square marker at the player's top-down map cell.
func _add_debug_player_marker(center: Vector2, color: Color) -> void:                        # Declare this function.
	var marker := Polygon2D.new()                                                               # Create a filled polygon marker for the player cell.
	var half_size := 3.5                                                                        # Set the square marker half-size in overlay pixels.
	marker.polygon = PackedVector2Array([                                                       # Define a small square around the player center.
		center + Vector2(-half_size, -half_size),                                                  # Add the top-left marker corner.
		center + Vector2(half_size, -half_size),                                                   # Add the top-right marker corner.
		center + Vector2(half_size, half_size),                                                    # Add the bottom-right marker corner.
		center + Vector2(-half_size, half_size),                                                   # Add the bottom-left marker corner.
	])                                                                                          # Close the marker polygon point list.
	marker.color = color                                                                        # Color the player marker.
	debug_map_overlay.add_child(marker)                                                         # Add the player marker to the overlay.



# _add_debug_arrow_head: Adds a triangular arrow head showing the player's facing direction.
func _add_debug_arrow_head(tip: Vector2, direction: Vector2, color: Color) -> void:           # Declare this function.
	if direction == Vector2.ZERO:                                                               # Avoid drawing an arrow if there is no valid facing direction.
		return                                                                                    # Return without adding an arrow head.
	var forward := direction.normalized()                                                       # Normalize the facing direction for arrow geometry.
	var side := Vector2(-forward.y, forward.x)                                                   # Compute the perpendicular vector used for the triangle width.
	var length := 6.0                                                                            # Set the arrow head length in overlay pixels.
	var width := 4.0                                                                             # Set the arrow head half-width in overlay pixels.
	var arrow := Polygon2D.new()                                                                 # Create the filled triangular arrow head.
	arrow.polygon = PackedVector2Array([                                                        # Define the arrow triangle points.
		tip,                                                                                        # Place the point at the arrow tip.
		tip - forward * length + side * width,                                                       # Place one rear corner of the arrow head.
		tip - forward * length - side * width,                                                       # Place the other rear corner of the arrow head.
	])                                                                                           # Close the arrow polygon point list.
	arrow.color = color                                                                          # Color the arrow head.
	debug_map_overlay.add_child(arrow)                                                           # Add the arrow head to the overlay.



# _setup_player_animation: Loads the player SpriteFrames resource, injects the idle frame, and prepares animation playback.
func _setup_player_animation() -> void:                                                     # Declare this function.
	var frames := load(PLAYER_FRAMES)                                                          # Store mutable runtime state for assets, rendering, movement, or debug output.
	if frames is SpriteFrames:                                                                 # Run the following block only when this condition is true.
		player_sprite.sprite_frames = frames.duplicate(true)                                      # Update player sprite rendering or animation state.
	else:                                                                                      # Run this fallback branch when previous conditions were not met.
		player_sprite.sprite_frames = SpriteFrames.new()                                          # Update player sprite rendering or animation state.

	_add_idle_animation()                                                                      # Call a helper function as part of the current controller step.
	_cache_animations()                                                                        # Call a helper function as part of the current controller step.
	player_sprite.centered = true                                                              # Update player sprite rendering or animation state.
	player_sprite.z_index = 10                                                                 # Update player sprite rendering or animation state.



# _add_idle_animation: Adds the one-frame IdleN_AimN animation from the user-provided idle PNG.
func _add_idle_animation() -> void:                                                         # Declare this function.
	var idle_texture := _load_png_texture(PLAYER_IDLE_TEXTURE)                                 # Store mutable runtime state for assets, rendering, movement, or debug output.
	if idle_texture == null:                                                                   # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.

	var frames := player_sprite.sprite_frames                                                  # Store mutable runtime state for assets, rendering, movement, or debug output.
	if frames.has_animation("IdleN_AimN"):                                                     # Run the following block only when this condition is true.
		frames.remove_animation("IdleN_AimN")                                                     # Continue the controller logic for this section.
	frames.add_animation("IdleN_AimN")                                                         # Continue the controller logic for this section.
	frames.set_animation_loop("IdleN_AimN", true)                                              # Continue the controller logic for this section.
	frames.set_animation_speed("IdleN_AimN", 1.0)                                              # Continue the controller logic for this section.
	frames.add_frame("IdleN_AimN", idle_texture)                                               # Continue the controller logic for this section.



# _cache_animations: Builds a quick lookup of available player animation names for fallback selection.
func _cache_animations() -> void:                                                           # Declare this function.
	available_animations.clear()                                                               # Continue the controller logic for this section.
	if player_sprite.sprite_frames == null:                                                    # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.
	for animation in player_sprite.sprite_frames.get_animation_names():                        # Iterate across this collection or range.
		available_animations[String(animation)] = true                                            # Compute and store this value for the current step.



# _load_phase_textures: Loads captured full-frame transition sequences for forward, backward, strafe, and turn movement.
func _load_phase_textures() -> void:                                                        # Declare this function.
	for sequence_name in ["forward", "backward", "turn_left", "turn_right", "strafe_left", "strafe_right"]: # Iterate across this collection or range.
		phase_textures[sequence_name] = _load_sequence(sequence_name)                             # Compute and store this value for the current step.



# _load_stable_textures: Loads old full-frame stable-view fallbacks retained for comparison and emergency fallback.
func _load_stable_textures() -> void:                                                       # Declare this function.
	for view_name in ["hallway_open", "front_wall"]:                                           # Iterate across this collection or range.
		var texture := _load_png_texture("%s/%s.png" % [STABLE_VIEW_ROOT, view_name])             # Store mutable runtime state for assets, rendering, movement, or debug output.
		if texture != null:                                                                       # Run the following block only when this condition is true.
			stable_textures[view_name] = texture                                                     # Compute and store this value for the current step.



# _load_slot_textures: Loads the older coarse environment-slot sprites, which remain as a fallback renderer path.
func _load_slot_textures() -> void:                                                         # Declare this function.
	for view_name in ["open", "front_wall"]:                                                   # Iterate across this collection or range.
		slot_textures[view_name] = {}                                                             # Compute and store this value for the current step.
		for slot_name in ["ceiling", "floor", "left_wall", "right_wall", "center_back"]:          # Iterate across this collection or range.
			var texture := _load_png_texture("%s/%s/%s.png" % [SLOT_ROOT, view_name, slot_name])     # Store mutable runtime state for assets, rendering, movement, or debug output.
			if texture != null:                                                                      # Run the following block only when this condition is true.
				slot_textures[view_name][slot_name] = texture                                           # Compute and store this value for the current step.



# _load_straight_wall_textures: Loads the floor strip and all 28 transparent straight-view wall overlay textures.
func _load_straight_wall_textures() -> void:                                                # Declare this function.
	floor_texture = _load_png_texture(FLOOR_TURN_TEXTURE)                                      # Compute and store this value for the current step.
	for wall_id in range(1, 29):                                                               # Iterate across this collection or range.
		var texture := _load_png_texture("%s/Walls_Straight_%02d.png" % [WALLS_STRAIGHT_ROOT, wall_id]) # Store mutable runtime state for assets, rendering, movement, or debug output.
		if texture != null:                                                                       # Run the following block only when this condition is true.
			straight_wall_textures[wall_id] = texture                                                # Compute and store this value for the current step.



# _load_sequence: Loads one sorted PNG sequence from a named phase directory.
func _load_sequence(sequence_name: String) -> Array[Texture2D]:                             # Declare this function.
	var sequence: Array[Texture2D] = []                                                        # Store mutable runtime state for assets, rendering, movement, or debug output.
	var directory := DirAccess.open("%s/%s" % [PHASE_ROOT, sequence_name])                     # Store mutable runtime state for assets, rendering, movement, or debug output.
	if directory == null:                                                                      # Run the following block only when this condition is true.
		push_error("Missing phase directory: %s/%s" % [PHASE_ROOT, sequence_name])                # Report a recoverable asset-loading problem in Godot.
		return sequence                                                                           # Return this computed result to the caller.

	var file_names: PackedStringArray = []                                                     # Store mutable runtime state for assets, rendering, movement, or debug output.
	directory.list_dir_begin()                                                                 # Continue the controller logic for this section.
	while true:                                                                                # Repeat this loop until the exit condition is met.
		var file_name := directory.get_next()                                                     # Store mutable runtime state for assets, rendering, movement, or debug output.
		if file_name.is_empty():                                                                  # Run the following block only when this condition is true.
			break                                                                                    # Exit the current loop.
		if directory.current_is_dir():                                                            # Run the following block only when this condition is true.
			continue                                                                                 # Skip the rest of this loop iteration.
		if file_name.to_lower().ends_with(".png"):                                                # Run the following block only when this condition is true.
			file_names.append(file_name)                                                             # Continue the controller logic for this section.
	directory.list_dir_end()                                                                   # Continue the controller logic for this section.
	file_names.sort()                                                                          # Continue the controller logic for this section.

	for file_name in file_names:                                                               # Iterate across this collection or range.
		var texture := _load_png_texture("%s/%s/%s" % [PHASE_ROOT, sequence_name, file_name])     # Store mutable runtime state for assets, rendering, movement, or debug output.
		if texture != null:                                                                       # Run the following block only when this condition is true.
			sequence.append(texture)                                                                 # Continue the controller logic for this section.

	return sequence                                                                            # Return this computed result to the caller.



# _load_png_texture: Loads a PNG by resource path through Image.load_from_file so unimported generated assets work in headless runs.
func _load_png_texture(resource_path: String) -> Texture2D:                                 # Declare this function.
	var image_path := ProjectSettings.globalize_path(resource_path)                            # Store mutable runtime state for assets, rendering, movement, or debug output.
	var image := Image.load_from_file(image_path)                                              # Store mutable runtime state for assets, rendering, movement, or debug output.
	if image == null or image.is_empty():                                                      # Run the following block only when this condition is true.
		push_error("Unable to load PNG: %s" % resource_path)                                      # Report a recoverable asset-loading problem in Godot.
		return null                                                                               # Return this computed result to the caller.
	return ImageTexture.create_from_image(image)                                               # Return this computed result to the caller.



# _show_stable: Displays the current non-transition view, preferring the new straight-wall renderer and falling back to older renderers.
func _show_stable() -> void:                                                                # Declare this function.
	if environment_layer != null and not straight_wall_textures.is_empty():                    # Run the following block only when this condition is true.
		playfield.visible = false                                                                 # Update the captured playfield sprite display.
		environment_layer.visible = true                                                          # Update the environment renderer container.
		_render_straight_wall_view()                                                              # Call a helper function as part of the current controller step.
		return                                                                                    # Return to the caller without producing a value.

	if environment_layer != null and not slot_textures.is_empty():                             # Run the following block only when this condition is true.
		playfield.visible = false                                                                 # Update the captured playfield sprite display.
		environment_layer.visible = true                                                          # Update the environment renderer container.
		_hide_straight_wall_nodes()                                                               # Call a helper function as part of the current controller step.
		_render_stable_slots()                                                                    # Call a helper function as part of the current controller step.
		return                                                                                    # Return to the caller without producing a value.

	var view_name := _stable_view_name()                                                       # Store mutable runtime state for assets, rendering, movement, or debug output.
	if stable_textures.has(view_name):                                                         # Run the following block only when this condition is true.
		playfield.visible = true                                                                  # Update the captured playfield sprite display.
		playfield.texture = stable_textures[view_name]                                            # Update the captured playfield sprite display.
		return                                                                                    # Return to the caller without producing a value.

	var fallback_sequence: Array[Texture2D] = phase_textures.get("forward", [])                # Store mutable runtime state for assets, rendering, movement, or debug output.
	if not fallback_sequence.is_empty():                                                       # Run the following block only when this condition is true.
		playfield.visible = true                                                                  # Update the captured playfield sprite display.
		playfield.texture = fallback_sequence[0]                                                  # Update the captured playfield sprite display.



# _stable_view_name: Returns the legacy stable-view name for the older slot/full-frame fallback renderers.
func _stable_view_name() -> String:                                                         # Declare this function.
	if not _can_cross_edge(grid_position, _facing_vector()):                                   # Run the following block only when this condition is true.
		return "front_wall"                                                                       # Return this computed result to the caller.
	return "open"                                                                              # Return this computed result to the caller.



# _render_straight_wall_view: Composes the stable environment from the floor and whichever numbered straight-wall overlays are visible from the map.
func _render_straight_wall_view() -> void:                                                  # Declare this function.
	_hide_slot_nodes()                                                                         # Call a helper function as part of the current controller step.

	if floor_sprite != null:                                                                   # Run the following block only when this condition is true.
		floor_sprite.visible = true                                                               # Update the reusable base floor sprite.
		floor_sprite.texture = floor_texture                                                      # Update the reusable base floor sprite.
		floor_sprite.position = Vector2.ZERO                                                      # Update the reusable base floor sprite.

	for wall_id in straight_wall_nodes.keys():                                                 # Iterate across this collection or range.
		var wall_sprite: Sprite2D = straight_wall_nodes[wall_id]                                  # Store mutable runtime state for assets, rendering, movement, or debug output.
		wall_sprite.visible = false                                                               # Configure or update one numbered wall overlay sprite.

	var visible_slots := _build_straight_render_list()                                         # Build the visible wall list from the top-down map visibility tree.
	last_visible_wall_ids.clear()                                                              # Reset the debug list of wall ids selected this frame.
	for visible_slot in visible_slots:                                                         # Iterate through selected slots for debug reporting.
		last_visible_wall_ids.append(int(visible_slot["id"]))                                     # Record the visible wall id selected by the visibility tree.

	visible_slots.sort_custom(func(a, b): return int(a["draw"]) < int(b["draw"]))              # Continue the controller logic for this section.

	for slot in visible_slots:                                                                 # Iterate across this collection or range.
		var wall_id := int(slot["id"])                                                            # Store mutable runtime state for assets, rendering, movement, or debug output.
		var wall_sprite: Sprite2D = straight_wall_nodes.get(wall_id)                              # Store mutable runtime state for assets, rendering, movement, or debug output.
		var texture: Texture2D = straight_wall_textures.get(wall_id)                              # Store mutable runtime state for assets, rendering, movement, or debug output.
		if wall_sprite == null or texture == null:                                                # Run the following block only when this condition is true.
			continue                                                                                 # Skip the rest of this loop iteration.
		wall_sprite.texture = texture                                                             # Configure or update one numbered wall overlay sprite.
		wall_sprite.position = Vector2.ZERO                                                       # Configure or update one numbered wall overlay sprite.
		wall_sprite.z_index = int(slot["draw"])                                                   # Configure or update one numbered wall overlay sprite.
		wall_sprite.visible = true                                                                # Configure or update one numbered wall overlay sprite.
		_position_wall_debug_label(wall_id, texture)                                              # Place the debug number label on the visible part of this wall.

	if enable_3d_diagnostic:                                                                   # Only mirror wall labels into the deprecated 3D diagnostic when it is active.
		_update_3d_slot_labels(visible_slots)                                                     # Mirror the same numbered wall-slot labels into the 3D diagnostic view.



# _hide_straight_wall_nodes: Hides the floor and all numbered straight-wall sprites.
func _hide_straight_wall_nodes() -> void:                                                   # Declare this function.
	if floor_sprite != null:                                                                   # Run the following block only when this condition is true.
		floor_sprite.visible = false                                                              # Update the reusable base floor sprite.
	for wall_id in straight_wall_nodes.keys():                                                 # Iterate across this collection or range.
		var wall_sprite: Sprite2D = straight_wall_nodes[wall_id]                                  # Store mutable runtime state for assets, rendering, movement, or debug output.
		wall_sprite.visible = false                                                               # Configure or update one numbered wall overlay sprite.



# _position_wall_debug_label: Moves a wall's debug number label to the center of that wall texture's opaque pixels.
func _position_wall_debug_label(wall_id: int, texture: Texture2D) -> void:                   # Declare this function.
	if not DEBUG_WALL_LABELS_ENABLED:                                                          # Skip label positioning when wall labels are disabled.
		return                                                                                    # Return without updating a label.
	var wall_label: Label = straight_wall_label_nodes.get(wall_id)                              # Look up the label attached to this wall sprite.
	if wall_label == null or texture == null:                                                   # Skip when the label or texture is missing.
		return                                                                                    # Return without updating a label.
	var bounds := _texture_opaque_bounds(texture)                                               # Measure the non-transparent wall art bounds inside the full overlay texture.
	if bounds.size == Vector2.ZERO:                                                             # Skip labels for fully transparent or unreadable textures.
		wall_label.visible = false                                                                 # Hide the label when no wall pixels were found.
		return                                                                                    # Return without positioning.
	wall_label.visible = true                                                                   # Show the label for this visible wall.
	wall_label.position = bounds.position + bounds.size * 0.5 - Vector2(4.0, 4.0)               # Center the label over the visible wall art.



# _texture_opaque_bounds: Finds the bounding rectangle of visible pixels in a texture.
func _texture_opaque_bounds(texture: Texture2D) -> Rect2:                                    # Declare this function.
	var image := texture.get_image()                                                           # Read texture pixels so the debug label can be placed on actual wall art.
	if image == null or image.is_empty():                                                       # Handle missing or empty image data.
		return Rect2(Vector2.ZERO, Vector2.ZERO)                                                  # Return an empty bounds rectangle.
	var min_x := image.get_width()                                                              # Start the minimum x bound at the far right.
	var min_y := image.get_height()                                                             # Start the minimum y bound at the bottom.
	var max_x := -1                                                                             # Start the maximum x bound before the image.
	var max_y := -1                                                                             # Start the maximum y bound before the image.
	for y in range(image.get_height()):                                                         # Scan each image row.
		for x in range(image.get_width()):                                                         # Scan each image column.
			if image.get_pixel(x, y).a > 0.0:                                                         # Treat any non-transparent pixel as visible wall art.
				min_x = mini(min_x, x)                                                                 # Shrink the left bound to this visible pixel.
				min_y = mini(min_y, y)                                                                 # Shrink the top bound to this visible pixel.
				max_x = maxi(max_x, x)                                                                 # Expand the right bound to this visible pixel.
				max_y = maxi(max_y, y)                                                                 # Expand the bottom bound to this visible pixel.
	if max_x < min_x or max_y < min_y:                                                        # Detect textures with no visible pixels.
		return Rect2(Vector2.ZERO, Vector2.ZERO)                                                  # Return an empty bounds rectangle.
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x + 1, max_y - min_y + 1))          # Return the visible pixel bounds.



# _hide_slot_nodes: Hides every legacy coarse environment slot sprite.
func _hide_slot_nodes() -> void:                                                            # Declare this function.
	for slot_name in slot_nodes.keys():                                                        # Iterate across this collection or range.
		var slot_sprite: Sprite2D = slot_nodes[slot_name]                                         # Store mutable runtime state for assets, rendering, movement, or debug output.
		slot_sprite.visible = false                                                               # Configure or update a legacy slot sprite.



# _build_straight_render_list: Walks the straight-view visibility tree and returns only the wall slots visible from the current map state.
func _build_straight_render_list() -> Array:                                                # Declare this function.
	var render_list := []                                                                      # Store the visible straight-wall slots selected by the visibility tree.
	var emitted_ids := {}                                                                      # Track wall ids already added so shared branch entries draw only once.
	if _is_wall_id_visible(25):                                                                # Treat the nearest front wall as a full-view blocker before side branches draw.
		var can_move_left := _can_cross_edge(grid_position, _left_vector())                       # Check whether the hallway continues to the viewer's left.
		var can_move_right := _can_cross_edge(grid_position, -_left_vector())                     # Check whether the hallway continues to the viewer's right.
		if can_move_left or can_move_right:                                                       # Side-wall views use near edge caps instead of the full front slab.
			var near_wall_ids := []                                                                 # Store the front-wall pieces visible in this side-wall view.
			if can_move_left:                                                                       # Check whether the hallway continues to the viewer's left.
				near_wall_ids.append(24)                                                              # Add the left front-wall cap.
			else:                                                                                  # Handle a blocked viewer-left side of the front wall.
				near_wall_ids.append(27)                                                              # Add the left outside edge strip for the wall end.
			near_wall_ids.append(25)                                                               # Add the center front-wall slab.
			if can_move_right:                                                                      # Check whether the hallway continues to the viewer's right.
				near_wall_ids.append(26)                                                              # Add the right front-wall cap.
			else:                                                                                  # Handle a blocked viewer-right side of the front wall.
				near_wall_ids.append(28)                                                              # Add the right outside edge strip for the wall end.
			for wall_id in near_wall_ids:                                                          # Emit the front-wall pieces selected for this side-wall view.
				var side_wall_slot := _straight_slot_by_id(wall_id)                                    # Look up the wall metadata for this side-wall piece.
				if not side_wall_slot.is_empty():                                                       # Only emit wall metadata that exists.
					render_list.append(side_wall_slot)                                                     # Add the side-wall piece to the render list.
			return render_list                                                                        # Stop deeper visibility because the front wall edge blocks the view.
		for wall_id in [27, 25, 28]:                                                              # Keep the immediate side strips visible around a near front wall.
			if _is_wall_id_visible(wall_id):                                                         # Only include this strip when its controlling map edge exists.
				var near_wall_slot := _straight_slot_by_id(wall_id)                                     # Look up the near wall metadata.
				if not near_wall_slot.is_empty():                                                       # Only emit wall metadata that exists.
					render_list.append(near_wall_slot)                                                     # Add the near dead-end wall piece to the render list.
		return render_list                                                                        # Stop deeper visibility because the near wall occludes anything behind it.
	for branch in STRAIGHT_VISIBILITY_BRANCHES:                                                # Iterate across each near-to-far top-view sightline branch.
		_walk_visibility_branch(render_list, emitted_ids, branch)                                 # Add visible walls from this branch and stop when an occluding wall blocks it.
	return render_list                                                                         # Return the final wall-slot list to the renderer.



# _walk_visibility_branch: Adds visible walls from one near-to-far branch and stops when a visible occluding wall blocks deeper checks.
func _walk_visibility_branch(render_list: Array, emitted_ids: Dictionary, branch: Array) -> void: # Declare this function.
	for entry in branch:                                                                       # Check this branch from the nearest wall candidate toward the farthest.
		var wall_id := int(entry["id"])                                                           # Read the numbered wall sprite controlled by this branch entry.
		if not _is_wall_id_visible(wall_id):                                                       # Skip this entry when the top-down map does not contain its controlling wall edge.
			continue                                                                                 # Continue deeper down the same visibility branch.

		if not emitted_ids.has(wall_id):                                                          # Add this wall only if no earlier branch already selected it.
			var slot := _straight_slot_by_id(wall_id)                                                # Look up the wall metadata used for draw order and edge testing.
			if not slot.is_empty():                                                                  # Only append metadata that exists in the slot table.
				render_list.append(slot)                                                                # Add the visible wall slot to the render list.
				emitted_ids[wall_id] = true                                                            # Mark the wall id as emitted so duplicate branches do not draw it twice.

		if bool(entry.get("occludes", true)):                                                       # Stop this branch when the visible wall blocks anything deeper behind it.
			return                                                                                    # Return to the caller with this branch complete.



# _straight_slot_by_id: Finds the slot metadata for one numbered straight-wall sprite.
func _straight_slot_by_id(wall_id: int) -> Dictionary:                                      # Declare this function.
	for slot in STRAIGHT_WALL_SLOTS:                                                          # Scan the straight-wall slot metadata table.
		if int(slot["id"]) == wall_id:                                                           # Match the requested numbered wall sprite.
			return slot                                                                             # Return the slot metadata for this wall id.
	return {}                                                                                  # Return an empty dictionary when the id is not defined.



# _is_wall_id_visible: Looks up one numbered wall slot and tests whether its controlling map edge is visible.
func _is_wall_id_visible(wall_id: int) -> bool:                                             # Declare this function.
	var slot := _straight_slot_by_id(wall_id)                                                  # Retrieve the metadata that maps this wall id to a top-down edge.
	if slot.is_empty():                                                                        # Treat unknown wall ids as not visible.
		return false                                                                             # Return false because there is no slot to test.
	return _is_straight_wall_slot_visible(slot)                                                # Delegate the actual map-edge visibility check to the existing slot tester.



# _is_straight_wall_slot_visible: Tests one numbered straight-wall slot against the current grid cell, facing, and thin-wall edge map.
func _is_straight_wall_slot_visible(slot: Dictionary) -> bool:                              # Declare this function.
	var lateral := int(slot["lateral"])                                                        # Store mutable runtime state for assets, rendering, movement, or debug output.
	var depth := int(slot["depth"])                                                            # Store mutable runtime state for assets, rendering, movement, or debug output.
	var edge := String(slot["edge"])                                                           # Store mutable runtime state for assets, rendering, movement, or debug output.
	var cell := _view_cell(lateral, depth)                                                     # Store mutable runtime state for assets, rendering, movement, or debug output.
	if not _is_open_cell(cell):                                                                # Run the following block only when this condition is true.
		return false                                                                              # Return this computed result to the caller.

	match edge:                                                                                # Branch behavior based on this value.
		VIEW_FRONT:                                                                               # Start this block.
			return _has_wall_edge(cell, _facing_vector())                                            # Return this computed result to the caller.
		VIEW_LEFT:                                                                                # Start this block.
			return _has_wall_edge(cell, _left_vector())                                              # Return this computed result to the caller.
		VIEW_RIGHT:                                                                               # Start this block.
			return _has_wall_edge(cell, -_left_vector())                                             # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return false                                                                             # Return this computed result to the caller.



# _view_cell: Converts a view-relative lateral/depth coordinate into a world grid cell for the current facing.
func _view_cell(lateral: int, depth: int) -> Vector2i:                                      # Declare this function.
	return grid_position + (_facing_vector() * depth) + ((-_left_vector()) * lateral)          # Return this computed result to the caller.



# _render_stable_slots: Composes the older coarse slot-based stable view fallback.
func _render_stable_slots() -> void:                                                        # Declare this function.
	var view_name := _stable_view_name()                                                       # Store mutable runtime state for assets, rendering, movement, or debug output.
	var textures: Dictionary = slot_textures.get(view_name, {})                                # Store mutable runtime state for assets, rendering, movement, or debug output.
	var fallback_textures: Dictionary = slot_textures.get("open", {})                          # Store mutable runtime state for assets, rendering, movement, or debug output.

	for slot_name in slot_nodes.keys():                                                        # Iterate across this collection or range.
		var slot_sprite: Sprite2D = slot_nodes[slot_name]                                         # Store mutable runtime state for assets, rendering, movement, or debug output.
		slot_sprite.visible = _should_show_slot(slot_name, view_name)                             # Configure or update a legacy slot sprite.
		if not slot_sprite.visible:                                                               # Run the following block only when this condition is true.
			continue                                                                                 # Skip the rest of this loop iteration.

		slot_sprite.texture = textures.get(slot_name, fallback_textures.get(slot_name))           # Configure or update a legacy slot sprite.
		slot_sprite.position = _slot_position(view_name, slot_name)                               # Configure or update a legacy slot sprite.



# _should_show_slot: Decides whether a legacy coarse slot should be shown for the current map state.
func _should_show_slot(slot_name: String, view_name: String) -> bool:                       # Declare this function.
	match slot_name:                                                                           # Branch behavior based on this value.
		"left_wall":                                                                              # Start this block.
			return _has_wall_at(_left_vector())                                                      # Return this computed result to the caller.
		"right_wall":                                                                             # Start this block.
			return _has_wall_at(-_left_vector())                                                     # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return true                                                                              # Return this computed result to the caller.



# _slot_position: Returns the screen position for a legacy coarse slot sprite.
func _slot_position(view_name: String, slot_name: String) -> Vector2:                       # Declare this function.
	if view_name == "front_wall" and slot_name == "center_back":                               # Run the following block only when this condition is true.
		return Vector2.ZERO                                                                       # Return this computed result to the caller.

	match slot_name:                                                                           # Branch behavior based on this value.
		"ceiling":                                                                                # Start this block.
			return Vector2.ZERO                                                                      # Return this computed result to the caller.
		"floor":                                                                                  # Start this block.
			return Vector2(0.0, 54.0)                                                                # Return this computed result to the caller.
		"left_wall":                                                                              # Start this block.
			return Vector2.ZERO                                                                      # Return this computed result to the caller.
		"right_wall":                                                                             # Start this block.
			return Vector2(104.0, 0.0)                                                               # Return this computed result to the caller.
		"center_back":                                                                            # Start this block.
			return Vector2(42.0, 27.0)                                                               # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return Vector2.ZERO                                                                      # Return this computed result to the caller.



# _slot_z_index: Returns the draw layer for a legacy coarse slot sprite.
func _slot_z_index(slot_name: String) -> int:                                               # Declare this function.
	match slot_name:                                                                           # Branch behavior based on this value.
		"floor":                                                                                  # Start this block.
			return 0                                                                                 # Return this computed result to the caller.
		"left_wall", "right_wall":                                                                # Start this block.
			return 1                                                                                 # Return this computed result to the caller.
		"center_back":                                                                            # Start this block.
			return 2                                                                                 # Return this computed result to the caller.
		"ceiling":                                                                                # Start this block.
			return 3                                                                                 # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return 0                                                                                 # Return this computed result to the caller.



# _read_turn: Reads Q/E or arrow-key turning input and returns the requested turn direction.
func _read_turn() -> int:                                                                   # Declare this function.
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):                          # Run the following block only when this condition is true.
		return -1                                                                                 # Return this computed result to the caller.
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_RIGHT):                         # Run the following block only when this condition is true.
		return 1                                                                                  # Return this computed result to the caller.
	return 0                                                                                   # Return this computed result to the caller.



# _read_movement: Reads WASD or arrow movement input and returns a normalized local movement vector.
func _read_movement() -> Vector2:                                                           # Declare this function.
	var movement := Vector2.ZERO                                                               # Store mutable runtime state for assets, rendering, movement, or debug output.
	if Input.is_key_pressed(KEY_A):                                                            # Run the following block only when this condition is true.
		movement.x -= 1.0                                                                         # Continue the controller logic for this section.
	if Input.is_key_pressed(KEY_D):                                                            # Run the following block only when this condition is true.
		movement.x += 1.0                                                                         # Continue the controller logic for this section.
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):                            # Run the following block only when this condition is true.
		movement.y -= 1.0                                                                         # Continue the controller logic for this section.
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):                          # Run the following block only when this condition is true.
		movement.y += 1.0                                                                         # Continue the controller logic for this section.
	return movement.normalized() if movement != Vector2.ZERO else Vector2.ZERO                 # Return this computed result to the caller.



# _move_inside_tile: Moves the player locally, crossing open edges at trigger thresholds and sliding to wall contact on blocked edges.
func _move_inside_tile(movement: Vector2, delta: float) -> void:                            # Declare this function.
	local_floor_position += movement * MOVE_UNITS_PER_SECOND * delta                           # Continue the controller logic for this section.
	var side_limits := _side_limits_for_depth(local_floor_position.y)                          # Compute visible side limits so logic and sprite registration stay coupled.

	if movement.y < 0.0 and local_floor_position.y <= FORWARD_TRIGGER_Y:                       # Run the following block only when this condition is true.
		if _can_cross_edge(grid_position, _facing_vector()):                                      # Check whether the forward tile edge is open.
			local_floor_position.y = FORWARD_TRIGGER_Y                                               # Hold the local position at the crossing threshold during the transition.
			_try_cross_tile("forward", _facing_vector(), "front")                                    # Start the forward tile-crossing transition.
		else:                                                                                     # Handle a blocked front wall.
			local_floor_position.y = maxf(local_floor_position.y, FORWARD_WALL_CONTACT_Y)            # Let the player reach the front wall contact instead of crossing.
			last_blocked_direction = "front"                                                         # Report the blocked front edge in the debug status.
	elif movement.y > 0.0 and local_floor_position.y >= BACKWARD_TRIGGER_Y:                    # Run this alternate branch when the previous conditions failed and this one is true.
		if _can_cross_edge(grid_position, -_facing_vector()):                                     # Check whether the backward tile edge is open.
			local_floor_position.y = BACKWARD_TRIGGER_Y                                              # Hold the local position at the crossing threshold during the transition.
			_try_cross_tile("backward", -_facing_vector(), "back")                                   # Start the backward tile-crossing transition.
		else:                                                                                     # Handle a blocked back wall.
			local_floor_position.y = minf(local_floor_position.y, BACKWARD_WALL_CONTACT_Y)           # Let the player reach the back wall contact instead of crossing.
			last_blocked_direction = "back"                                                          # Report the blocked back edge in the debug status.
	elif movement.x < 0.0 and local_floor_position.x <= side_limits.x:                         # Run this alternate branch when the player reaches the visible left-side limit.
		if _can_cross_edge(grid_position, _left_vector()):                                        # Check whether the camera-left tile edge is open.
			local_floor_position.x = side_limits.x                                                   # Hold the local position at the crossing threshold during the transition.
			_try_cross_tile("strafe_left", _left_vector(), "left")                                   # Start the left strafe tile-crossing transition.
		else:                                                                                     # Handle a blocked left wall.
			local_floor_position.x = maxf(local_floor_position.x, side_limits.x)                     # Let the player reach the left visible contact limit instead of crossing.
			last_blocked_direction = "left"                                                          # Report the blocked left edge in the debug status.
	elif movement.x > 0.0 and local_floor_position.x >= side_limits.y:                         # Run this alternate branch when the player reaches the visible right-side limit.
		if _can_cross_edge(grid_position, -_left_vector()):                                       # Check whether the camera-right tile edge is open.
			local_floor_position.x = side_limits.y                                                  # Hold the local position at the crossing threshold during the transition.
			_try_cross_tile("strafe_right", -_left_vector(), "right")                                # Start the right strafe tile-crossing transition.
		else:                                                                                     # Handle a blocked right wall.
			local_floor_position.x = minf(local_floor_position.x, side_limits.y)                    # Let the player reach the right visible contact limit instead of crossing.
			last_blocked_direction = "right"                                                         # Report the blocked right edge in the debug status.

	if not is_transitioning:                                                                   # Keep free local movement bounded when no tile-crossing transition started.
		side_limits = _side_limits_for_depth(local_floor_position.y)                              # Recompute side limits after any depth clamp changed the projected floor width.
		local_floor_position.x = clampf(local_floor_position.x, side_limits.x, side_limits.y)      # Clamp horizontal movement to the visible sprite-safe wall-contact span.
		local_floor_position.y = clampf(local_floor_position.y, FORWARD_WALL_CONTACT_Y, BACKWARD_WALL_CONTACT_Y) # Clamp depth movement to the reachable front/back contact span.



# _try_cross_tile: Attempts to cross a map edge, starting the matching transition if the thin wall map allows it.
func _try_cross_tile(sequence_name: String, grid_delta: Vector2i, blocked_label: String) -> void: # Declare this function.
	if _can_cross_edge(grid_position, grid_delta):                                             # Run the following block only when this condition is true.
		pending_grid_delta = grid_delta                                                           # Compute and store this value for the current step.
		last_blocked_direction = ""                                                               # Compute and store this value for the current step.
		_start_transition(sequence_name)                                                          # Call a helper function as part of the current controller step.
	else:                                                                                      # Run this fallback branch when previous conditions were not met.
		last_blocked_direction = blocked_label                                                    # Compute and store this value for the current step.



# _position_player: Projects the player local tile position into the 160x120 perspective floor trapezoid.
func _position_player() -> void:                                                            # Declare this function.
	var depth := clampf(local_floor_position.y, 0.0, 1.0)                                      # Store mutable runtime state for assets, rendering, movement, or debug output.
	var half_width := lerpf(FAR_FLOOR_HALF_WIDTH, NEAR_FLOOR_HALF_WIDTH, depth)                # Store mutable runtime state for assets, rendering, movement, or debug output.
	var x_min := 0.5 - half_width                                                              # Store mutable runtime state for assets, rendering, movement, or debug output.
	var x_max := 0.5 + half_width                                                              # Store mutable runtime state for assets, rendering, movement, or debug output.
	var screen_x := lerpf(x_min, x_max, local_floor_position.x) * VIEWPORT_SIZE.x              # Project unclamped side movement so wall contact can reach the visible side lines.
	var screen_y := lerpf(FAR_FLOOR_Y, NEAR_FLOOR_Y, depth) * VIEWPORT_SIZE.y                  # Store mutable runtime state for assets, rendering, movement, or debug output.
	var sprite_scale := _player_sprite_scale_for_depth(depth)                                  # Compute player scale from depth using the shared registration helper.
	var half_sprite_height := _current_player_texture_height() * sprite_scale * 0.5            # Store mutable runtime state for assets, rendering, movement, or debug output.
	screen_y = minf(screen_y, VIEWPORT_SIZE.y - half_sprite_height)                            # Compute and store this value for the current step.
	player_sprite.scale = Vector2.ONE * sprite_scale                                           # Update player sprite rendering or animation state.
	player_sprite.position = Vector2(screen_x, screen_y)                                       # Update player sprite rendering or animation state.



# _side_limits_for_depth: Returns local x limits that keep the player registered inside the visible floor trapezoid at this depth.
func _side_limits_for_depth(local_depth: float) -> Vector2:                                 # Declare this function.
	var depth := clampf(local_depth, 0.0, 1.0)                                                 # Clamp depth before using it for projection math.
	var half_width := lerpf(FAR_FLOOR_HALF_WIDTH, NEAR_FLOOR_HALF_WIDTH, depth)                # Compute the floor trapezoid half-width at this depth.
	var x_min := 0.5 - half_width                                                              # Compute the left projection boundary at this depth.
	var x_max := 0.5 + half_width                                                              # Compute the right projection boundary at this depth.
	var projected_width := maxf(x_max - x_min, 0.001)                                         # Avoid division by zero while converting screen bounds back to local x.
	var half_sprite_width := _current_player_texture_width() * _player_sprite_scale_for_depth(depth) * 0.5 # Measure half the current frame width after scaling.
	var sprite_screen_margin := half_sprite_width / VIEWPORT_SIZE.x                            # Convert the sprite half-width into normalized playfield space.
	var side_line_margin := sprite_screen_margin * 0.25                                        # Use a smaller foot/contact margin for the sloped wall line than for the full sprite crop.
	var min_screen_ratio := maxf(sprite_screen_margin, x_min + side_line_margin)                # Use the stricter left bound from the screen edge or the corridor wall line.
	var max_screen_ratio := minf(1.0 - sprite_screen_margin, x_max - side_line_margin)          # Use the stricter right bound from the screen edge or the corridor wall line.
	return Vector2(                                                                            # Return the local x span that keeps the sprite inside the cropped view.
		(min_screen_ratio - x_min) / projected_width,                                             # Convert the left screen-safe x back into local tile space.
		(max_screen_ratio - x_min) / projected_width                                              # Convert the right screen-safe x back into local tile space.
	)                                                                                         # Close the local side-limit vector.



# _player_sprite_scale_for_depth: Returns the character scale used by both projection and movement bounds.
func _player_sprite_scale_for_depth(depth: float) -> float:                                # Declare this function.
	return lerpf(0.72, 1.18, clampf(depth, 0.0, 1.0))                                         # Return the depth-scaled player size.



# _current_player_texture_width: Returns the current player frame width so the sprite can be clamped inside the playfield.
func _current_player_texture_width() -> float:                                              # Declare this function.
	var texture := player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame) # Store mutable runtime state for assets, rendering, movement, or debug output.
	if texture == null:                                                                        # Run the following block only when this condition is true.
		return 34.0                                                                               # Return a conservative fallback width for the player sprite.
	return float(texture.get_width())                                                          # Return this computed result to the caller.



# _current_player_texture_height: Returns the current player frame height so the sprite can be clamped inside the playfield.
func _current_player_texture_height() -> float:                                             # Declare this function.
	var texture := player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame) # Store mutable runtime state for assets, rendering, movement, or debug output.
	if texture == null:                                                                        # Run the following block only when this condition is true.
		return 46.0                                                                               # Return this computed result to the caller.
	return float(texture.get_height())                                                         # Return this computed result to the caller.



# _movement_to_first_player_run_dir: Maps local movement input to the first-player run animation while keeping aim camera-forward.
func _movement_to_first_player_run_dir(movement: Vector2) -> String:                        # Declare this function.
	# In first-player view, aim stays camera-forward/north. Side-facing run
	# animations describe how the body moves while still aiming north.
	if movement.y < 0.0 and movement.x < 0.0:                                                  # Run the following block only when this condition is true.
		return DIR_W                                                                              # Return this computed result to the caller.
	if movement.y < 0.0 and movement.x > 0.0:                                                  # Run the following block only when this condition is true.
		return DIR_E                                                                              # Return this computed result to the caller.
	if movement.x < 0.0:                                                                       # Run the following block only when this condition is true.
		return DIR_W                                                                              # Return this computed result to the caller.
	if movement.x > 0.0:                                                                       # Run the following block only when this condition is true.
		return DIR_E                                                                              # Return this computed result to the caller.
	if movement.y > 0.0:                                                                       # Run the following block only when this condition is true.
		return DIR_S                                                                              # Return this computed result to the caller.
	return DIR_N                                                                               # Return this computed result to the caller.



# _play_best_animation: Chooses and starts the best available player animation for the current movement state.
func _play_best_animation(is_moving: bool) -> void:                                         # Declare this function.
	var animation := _best_animation_for(run_dir, aim_dir, is_moving)                          # Store mutable runtime state for assets, rendering, movement, or debug output.
	if animation == &"":                                                                       # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.
	if animation == last_animation and player_sprite.is_playing():                             # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.

	last_animation = animation                                                                 # Compute and store this value for the current step.
	player_sprite.play(animation)                                                              # Update player sprite rendering or animation state.



# _best_animation_for: Finds the exact or nearest fallback animation for a requested run and aim direction.
func _best_animation_for(run: String, aim: String, is_moving: bool) -> StringName:          # Declare this function.
	if not is_moving and available_animations.has("IdleN_AimN"):                               # Run the following block only when this condition is true.
		return &"IdleN_AimN"                                                                      # Return this computed result to the caller.

	var exact := "Run%s_Aim%s" % [run, aim]                                                    # Store mutable runtime state for assets, rendering, movement, or debug output.
	if available_animations.has(exact):                                                        # Run the following block only when this condition is true.
		return StringName(exact)                                                                  # Return this computed result to the caller.

	var same_run := _first_animation_with_prefix("Run%s_Aim" % run)                            # Store mutable runtime state for assets, rendering, movement, or debug output.
	if same_run != &"":                                                                        # Run the following block only when this condition is true.
		return same_run                                                                           # Return this computed result to the caller.

	var same_aim_suffix := "_Aim%s" % aim                                                      # Store mutable runtime state for assets, rendering, movement, or debug output.
	for animation in available_animations.keys():                                              # Iterate across this collection or range.
		if String(animation).ends_with(same_aim_suffix):                                          # Run the following block only when this condition is true.
			return StringName(animation)                                                             # Return this computed result to the caller.

	if available_animations.has("IdleN_AimN"):                                                 # Run the following block only when this condition is true.
		return &"IdleN_AimN"                                                                      # Return this computed result to the caller.

	return &""                                                                                 # Return this computed result to the caller.



# _first_animation_with_prefix: Returns the first available animation whose name starts with the requested prefix.
func _first_animation_with_prefix(prefix: String) -> StringName:                            # Declare this function.
	var names := available_animations.keys()                                                   # Store mutable runtime state for assets, rendering, movement, or debug output.
	names.sort()                                                                               # Continue the controller logic for this section.
	for animation in names:                                                                    # Iterate across this collection or range.
		if String(animation).begins_with(prefix):                                                 # Run the following block only when this condition is true.
			return StringName(animation)                                                             # Return this computed result to the caller.
	return &""                                                                                 # Return this computed result to the caller.



# _start_transition: Starts a captured full-frame phase animation and temporarily hides the stable wall renderer.
func _start_transition(sequence_name: String) -> void:                                      # Declare this function.
	if is_transitioning:                                                                       # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.

	var sequence: Array[Texture2D] = phase_textures.get(sequence_name, [])                     # Store mutable runtime state for assets, rendering, movement, or debug output.
	if sequence.is_empty():                                                                    # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.

	active_sequence = sequence                                                                 # Compute and store this value for the current step.
	active_sequence_name = sequence_name                                                       # Compute and store this value for the current step.
	phase_index = 0                                                                            # Compute and store this value for the current step.
	phase_timer = 0.0                                                                          # Compute and store this value for the current step.
	is_transitioning = true                                                                    # Compute and store this value for the current step.
	if environment_layer != null:                                                              # Run the following block only when this condition is true.
		environment_layer.visible = false                                                         # Update the environment renderer container.
	if enable_3d_diagnostic:                                                                   # Only hide 3D labels when the deprecated diagnostic is active.
		_hide_3d_slot_labels()                                                                    # Hide stable wall-slot labels while a captured transition phase plays.
	playfield.visible = true                                                                   # Update the captured playfield sprite display.
	playfield.texture = active_sequence[phase_index]                                           # Update the captured playfield sprite display.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _advance_transition: Advances the active captured transition sequence based on elapsed time.
func _advance_transition(delta: float) -> void:                                             # Declare this function.
	phase_timer += delta                                                                       # Continue the controller logic for this section.
	if phase_timer < PHASE_SECONDS:                                                            # Run the following block only when this condition is true.
		return                                                                                    # Return to the caller without producing a value.

	phase_timer -= PHASE_SECONDS                                                               # Continue the controller logic for this section.
	phase_index += 1                                                                           # Continue the controller logic for this section.

	if phase_index >= active_sequence.size():                                                  # Run the following block only when this condition is true.
		_finish_transition()                                                                      # Call a helper function as part of the current controller step.
		return                                                                                    # Return to the caller without producing a value.

	playfield.texture = active_sequence[phase_index]                                           # Update the captured playfield sprite display.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _finish_transition: Completes a transition, applies its grid/facing result, resets local position, and redraws the stable view.
func _finish_transition() -> void:                                                          # Declare this function.
	is_transitioning = false                                                                   # Compute and store this value for the current step.
	_apply_grid_result(active_sequence_name)                                                   # Call a helper function as part of the current controller step.
	_reset_local_position_after_transition(active_sequence_name)                               # Call a helper function as part of the current controller step.
	phase_index = 0                                                                            # Compute and store this value for the current step.
	phase_timer = 0.0                                                                          # Compute and store this value for the current step.
	active_sequence = []                                                                       # Compute and store this value for the current step.
	_show_stable()                                                                             # Call a helper function as part of the current controller step.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _apply_grid_result: Applies the pending grid movement or facing rotation produced by the finished transition.
func _apply_grid_result(sequence_name: String) -> void:                                     # Declare this function.
	match sequence_name:                                                                       # Branch behavior based on this value.
		"forward", "backward", "strafe_left", "strafe_right":                                     # Start this block.
			grid_position += pending_grid_delta                                                      # Continue the controller logic for this section.
			pending_grid_delta = Vector2i.ZERO                                                       # Compute and store this value for the current step.
		"turn_left":                                                                              # Start this block.
			facing = wrapi(facing - 1, 0, 4)                                                         # Compute and store this value for the current step.
		"turn_right":                                                                             # Start this block.
			facing = wrapi(facing + 1, 0, 4)                                                         # Compute and store this value for the current step.



# _reset_local_position_after_transition: Recenters the local player offset on the axis affected by the completed transition.
func _reset_local_position_after_transition(sequence_name: String) -> void:                 # Declare this function.
	match sequence_name:                                                                       # Branch behavior based on this value.
		"forward":                                                                                # Handle a forward cell crossing.
			local_floor_position.y = BACKWARD_WALL_CONTACT_Y                                         # Enter the new cell from its back edge instead of snapping to center.
		"backward":                                                                               # Handle a backward cell crossing.
			local_floor_position.y = FORWARD_WALL_CONTACT_Y                                          # Enter the new cell from its front edge instead of snapping to center.
		"strafe_left":                                                                            # Handle a camera-left cell crossing.
			local_floor_position.x = _side_limits_for_depth(local_floor_position.y).y                # Enter the new cell from its camera-right side instead of snapping to center.
		"strafe_right":                                                                           # Handle a camera-right cell crossing.
			local_floor_position.x = _side_limits_for_depth(local_floor_position.y).x                # Enter the new cell from its camera-left side instead of snapping to center.
		"turn_left", "turn_right":                                                                # Start this block.
			local_floor_position = _rotated_local_position_for_turn(sequence_name)                   # Preserve the player's tile offset while rotating it into the new camera frame.



# _rotated_local_position_for_turn: Rotates the player's normalized within-tile offset when the camera turns.
func _rotated_local_position_for_turn(sequence_name: String) -> Vector2:                    # Declare this function.
	var offset := _local_position_to_tile_offset(local_floor_position)                         # Convert local art coordinates into normalized physical tile offset.
	match sequence_name:                                                                       # Branch based on the completed turn direction.
		"turn_left":                                                                              # Handle a left camera turn.
			offset = Vector2(offset.y, -offset.x)                                                    # Rotate the physical offset into the new camera frame after a left turn.
		"turn_right":                                                                             # Handle a right camera turn.
			offset = Vector2(-offset.y, offset.x)                                                    # Rotate the physical offset into the new camera frame after a right turn.
	return _tile_offset_to_local_position(offset)                                              # Convert the normalized physical offset back into local art coordinates.



# _local_position_to_tile_offset: Converts local art-space x/y into normalized physical right/forward offsets inside the tile.
func _local_position_to_tile_offset(local_position: Vector2) -> Vector2:                    # Declare this function.
	return Vector2(                                                                            # Return a normalized offset where x is right and y is forward.
		_axis_to_signed_unit(local_position.x, HOME_LOCAL_FLOOR_POSITION.x, STRAFE_LEFT_WALL_CONTACT_X, STRAFE_RIGHT_WALL_CONTACT_X), # Normalize horizontal position against wall contact limits.
		_forward_axis_to_signed_unit(local_position.y)                                           # Normalize vertical position so forward is positive.
	)                                                                                         # Close the returned normalized offset.



# _tile_offset_to_local_position: Converts normalized physical right/forward offsets back into local art-space x/y.
func _tile_offset_to_local_position(offset: Vector2) -> Vector2:                            # Declare this function.
	var clamped_offset := Vector2(clampf(offset.x, -1.0, 1.0), clampf(offset.y, -1.0, 1.0))    # Clamp rotated offsets to the reachable tile interior.
	return Vector2(                                                                            # Return the local art-space position for the rotated physical offset.
		_signed_unit_to_axis(clamped_offset.x, HOME_LOCAL_FLOOR_POSITION.x, STRAFE_LEFT_WALL_CONTACT_X, STRAFE_RIGHT_WALL_CONTACT_X), # Denormalize horizontal wall proximity.
		_signed_forward_unit_to_axis(clamped_offset.y)                                            # Denormalize forward/back wall proximity.
	)                                                                                         # Close the returned local position.



# _axis_to_signed_unit: Normalizes an asymmetric one-dimensional axis around its center into the -1..1 range.
func _axis_to_signed_unit(value: float, center: float, low_limit: float, high_limit: float) -> float: # Declare this function.
	if value < center:                                                                         # Choose the lower half of the asymmetric range.
		return -((center - value) / (center - low_limit))                                         # Return a negative unit offset toward the low limit.
	return (value - center) / (high_limit - center)                                           # Return a positive unit offset toward the high limit.



# _signed_unit_to_axis: Denormalizes a -1..1 value back onto an asymmetric one-dimensional axis.
func _signed_unit_to_axis(value: float, center: float, low_limit: float, high_limit: float) -> float: # Declare this function.
	if value < 0.0:                                                                            # Choose the lower half of the asymmetric range.
		return center + value * (center - low_limit)                                             # Return a coordinate between the center and low limit.
	return center + value * (high_limit - center)                                             # Return a coordinate between the center and high limit.



# _forward_axis_to_signed_unit: Normalizes local y so forward wall contact is +1 and back wall contact is -1.
func _forward_axis_to_signed_unit(value: float) -> float:                                   # Declare this function.
	if value < HOME_LOCAL_FLOOR_POSITION.y:                                                   # Choose the forward half of the local y range.
		return (HOME_LOCAL_FLOOR_POSITION.y - value) / (HOME_LOCAL_FLOOR_POSITION.y - FORWARD_WALL_CONTACT_Y) # Return positive normalized forward offset.
	return -((value - HOME_LOCAL_FLOOR_POSITION.y) / (BACKWARD_WALL_CONTACT_Y - HOME_LOCAL_FLOOR_POSITION.y)) # Return negative normalized backward offset.



# _signed_forward_unit_to_axis: Denormalizes a forward-positive -1..1 offset back into local y.
func _signed_forward_unit_to_axis(value: float) -> float:                                  # Declare this function.
	if value >= 0.0:                                                                          # Choose the forward half of the local y range.
		return HOME_LOCAL_FLOOR_POSITION.y - value * (HOME_LOCAL_FLOOR_POSITION.y - FORWARD_WALL_CONTACT_Y) # Return local y between home and front wall contact.
	return HOME_LOCAL_FLOOR_POSITION.y - value * (BACKWARD_WALL_CONTACT_Y - HOME_LOCAL_FLOOR_POSITION.y) # Return local y between home and back wall contact.



# _update_3d_diagnostic: Moves the 3D player cube and camera to match the current 2D/grid prototype state.
func _update_3d_diagnostic() -> void:                                                       # Declare this function.
	if diagnostic_3d_player_root == null or diagnostic_3d_camera == null:                      # Skip until the diagnostic 3D nodes exist.
		return                                                                                    # Return without updating the 3D diagnostic view.

	var player_position := _current_player_position_to_3d()                                    # Convert the current grid and local tile offset into 3D world space.
	var camera_anchor := _grid_cell_center_to_3d(grid_position)                                # Lock the diagnostic camera to the current cell, independent of player local offset.
	var forward := _grid_delta_to_3d(_facing_vector()).normalized()                            # Convert the current facing vector into a 3D forward direction.
	diagnostic_3d_player_root.position = player_position                                      # Place the 3D player marker at the same physical point as the 2D player.
	diagnostic_3d_player_root.rotation.y = _facing_to_3d_yaw()                                 # Rotate the red forward ray to match the camera/player facing.
	diagnostic_3d_camera.fov = diagnostic_3d_camera_fov                                        # Reapply the editable FOV so runtime inspector tweaks take effect.

	var camera_position := camera_anchor - forward * diagnostic_3d_camera_back_offset + Vector3(0.0, diagnostic_3d_camera_height, 0.0) # Put the 3D camera inside the current cell rather than following the player.
	var camera_target := camera_anchor + forward * diagnostic_3d_camera_target_distance + Vector3(0.0, diagnostic_3d_camera_target_height, 0.0) # Aim the camera down the hallway from the fixed cell anchor while fitting the player.
	diagnostic_3d_camera.global_position = camera_position                                    # Move the diagnostic camera.
	diagnostic_3d_camera.look_at(camera_target, Vector3.UP)                                   # Rotate the diagnostic camera toward the same view direction.



# _current_player_position_to_3d: Converts the player cell and normalized local offset into 3D hallway coordinates.
func _current_player_position_to_3d() -> Vector3:                                           # Declare this function.
	var local_offset := _local_position_to_tile_offset(local_floor_position)                   # Convert local art-space coordinates into normalized physical tile offsets.
	var right_direction := _grid_delta_to_3d(-_left_vector())                                  # Convert camera-right into 3D world space.
	var forward_direction := _grid_delta_to_3d(_facing_vector())                               # Convert camera-forward into 3D world space.
	return (                                                                                  # Return the combined 3D player ground position.
		_grid_cell_center_to_3d(grid_position)                                                    # Start from the center of the current map cell.
		+ right_direction * local_offset.x * DIAGNOSTIC_3D_LOCAL_SIDE_HALF_EXTENT                # Apply the player offset to the camera-right side of the widened tile.
		+ forward_direction * local_offset.y * DIAGNOSTIC_3D_LOCAL_DEPTH_HALF_EXTENT             # Apply the player offset to the camera-forward side of the tile.
	)                                                                                         # Close the combined 3D position expression.



# _grid_cell_center_to_3d: Converts a 2D grid cell coordinate into the 3D center of that cubic cell.
func _grid_cell_center_to_3d(cell: Vector2i) -> Vector3:                                    # Declare this function.
	return Vector3(float(cell.x) * DIAGNOSTIC_3D_CELL_WIDTH + DIAGNOSTIC_3D_CELL_WIDTH * 0.5, 0.0, float(cell.y) + 0.5) # Map grid x to widened 3D x and grid y to 3D z.



# _grid_delta_to_3d: Converts a 2D grid direction into the matching horizontal 3D vector.
func _grid_delta_to_3d(delta: Vector2i) -> Vector3:                                        # Declare this function.
	return Vector3(float(delta.x), 0.0, float(delta.y))                                       # Map grid x/y deltas onto 3D x/z deltas.



# _facing_to_3d_yaw: Converts the current cardinal facing index into a Godot yaw for a -Z-forward marker.
func _facing_to_3d_yaw() -> float:                                                         # Declare this function.
	match facing:                                                                              # Branch behavior based on this value.
		0:                                                                                        # Handle north, which matches Godot's -Z forward direction.
			return 0.0                                                                               # Return the yaw for north.
		1:                                                                                        # Handle east.
			return -PI * 0.5                                                                         # Return the yaw that rotates -Z to +X.
		2:                                                                                        # Handle south.
			return PI                                                                                # Return the yaw that rotates -Z to +Z.
		_:                                                                                        # Handle west.
			return PI * 0.5                                                                          # Return the yaw that rotates -Z to -X.



# _facing_vector: Returns the world grid direction vector for the current facing index.
func _facing_vector() -> Vector2i:                                                          # Declare this function.
	match facing:                                                                              # Branch behavior based on this value.
		0:                                                                                        # Start this block.
			return Vector2i(0, -1)                                                                   # Return this computed result to the caller.
		1:                                                                                        # Start this block.
			return Vector2i(1, 0)                                                                    # Return this computed result to the caller.
		2:                                                                                        # Start this block.
			return Vector2i(0, 1)                                                                    # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return Vector2i(-1, 0)                                                                   # Return this computed result to the caller.



# _left_vector: Returns the world grid direction vector that is camera-left for the current facing index.
func _left_vector() -> Vector2i:                                                            # Declare this function.
	match facing:                                                                              # Branch behavior based on this value.
		0:                                                                                        # Start this block.
			return Vector2i(-1, 0)                                                                   # Return this computed result to the caller.
		1:                                                                                        # Start this block.
			return Vector2i(0, -1)                                                                   # Return this computed result to the caller.
		2:                                                                                        # Start this block.
			return Vector2i(1, 0)                                                                    # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return Vector2i(0, 1)                                                                    # Return this computed result to the caller.



# _build_test_hallway_wall_edges: Builds the current four-cell one-wide hallway using explicit north/east/south/west thin-wall edges.
func _build_test_hallway_wall_edges() -> void:                                              # Declare this function.
	wall_edges.clear()                                                                         # Continue the controller logic for this section.
	for y in range(HALLWAY_LENGTH):                                                            # Iterate across this collection or range.
		var cell := Vector2i(0, y)                                                                # Store mutable runtime state for assets, rendering, movement, or debug output.
		wall_edges[cell] = {                                                                      # Compute and store this value for the current step.
			WALL_EDGE_N: y == 0,                                                                     # Continue the controller logic for this section.
			WALL_EDGE_E: true,                                                                       # Continue the controller logic for this section.
			WALL_EDGE_S: y == HALLWAY_LENGTH - 1,                                                    # Continue the controller logic for this section.
			WALL_EDGE_W: true,                                                                       # Continue the controller logic for this section.
		}                                                                                         # Close the current list, dictionary, call, or expression.



# _can_cross_edge: Returns whether the player can cross from one cell to the adjacent cell in the requested direction.
func _can_cross_edge(from_cell: Vector2i, delta: Vector2i) -> bool:                         # Declare this function.
	if delta == Vector2i.ZERO:                                                                 # Run the following block only when this condition is true.
		return false                                                                              # Return this computed result to the caller.
	var to_cell := from_cell + delta                                                           # Store mutable runtime state for assets, rendering, movement, or debug output.
	return _is_open_cell(from_cell) and _is_open_cell(to_cell) and not _has_wall_edge(from_cell, delta) # Return this computed result to the caller.



# _has_wall_at: Returns whether the current player cell has a wall in the requested world direction.
func _has_wall_at(delta: Vector2i) -> bool:                                                 # Declare this function.
	return _has_wall_edge(grid_position, delta)                                                # Return this computed result to the caller.



# _has_wall_edge: Returns whether a specific cell edge is blocked by the thin-wall map or by out-of-map space.
func _has_wall_edge(cell: Vector2i, delta: Vector2i) -> bool:                               # Declare this function.
	if delta == Vector2i.ZERO:                                                                 # Run the following block only when this condition is true.
		return true                                                                               # Return this computed result to the caller.
	if not _is_open_cell(cell):                                                                # Run the following block only when this condition is true.
		return true                                                                               # Return this computed result to the caller.

	var edge := _edge_from_delta(delta)                                                        # Store mutable runtime state for assets, rendering, movement, or debug output.
	if edge < 0:                                                                               # Run the following block only when this condition is true.
		return true                                                                               # Return this computed result to the caller.

	var cell_edges: Dictionary = wall_edges.get(cell, {})                                      # Store mutable runtime state for assets, rendering, movement, or debug output.
	if bool(cell_edges.get(edge, true)):                                                       # Run the following block only when this condition is true.
		return true                                                                               # Return this computed result to the caller.

	var other_cell := cell + delta                                                             # Store mutable runtime state for assets, rendering, movement, or debug output.
	if not _is_open_cell(other_cell):                                                          # Run the following block only when this condition is true.
		return true                                                                               # Return this computed result to the caller.

	var other_edges: Dictionary = wall_edges.get(other_cell, {})                               # Store mutable runtime state for assets, rendering, movement, or debug output.
	return bool(other_edges.get(_opposite_edge(edge), true))                                   # Return this computed result to the caller.



# _edge_from_delta: Converts a one-cell direction vector into a wall-edge constant.
func _edge_from_delta(delta: Vector2i) -> int:                                              # Declare this function.
	if delta == Vector2i(0, -1):                                                               # Run the following block only when this condition is true.
		return WALL_EDGE_N                                                                        # Return this computed result to the caller.
	if delta == Vector2i(1, 0):                                                                # Run the following block only when this condition is true.
		return WALL_EDGE_E                                                                        # Return this computed result to the caller.
	if delta == Vector2i(0, 1):                                                                # Run the following block only when this condition is true.
		return WALL_EDGE_S                                                                        # Return this computed result to the caller.
	if delta == Vector2i(-1, 0):                                                               # Run the following block only when this condition is true.
		return WALL_EDGE_W                                                                        # Return this computed result to the caller.
	return -1                                                                                  # Return this computed result to the caller.



# _opposite_edge: Returns the edge constant on the opposite side of a shared wall.
func _opposite_edge(edge: int) -> int:                                                      # Declare this function.
	match edge:                                                                                # Branch behavior based on this value.
		WALL_EDGE_N:                                                                              # Start this block.
			return WALL_EDGE_S                                                                       # Return this computed result to the caller.
		WALL_EDGE_E:                                                                              # Start this block.
			return WALL_EDGE_W                                                                       # Return this computed result to the caller.
		WALL_EDGE_S:                                                                              # Start this block.
			return WALL_EDGE_N                                                                       # Return this computed result to the caller.
		WALL_EDGE_W:                                                                              # Start this block.
			return WALL_EDGE_E                                                                       # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return -1                                                                                # Return this computed result to the caller.



# _is_open_cell: Returns whether a cell belongs to the current test hallway footprint.
func _is_open_cell(cell: Vector2i) -> bool:                                                 # Declare this function.
	return cell.x == 0 and cell.y >= 0 and cell.y < HALLWAY_LENGTH                             # Return this computed result to the caller.



# _update_status: Writes debug state text showing phase, facing, cell, local offset, animation, and blocked direction.
func _update_status() -> void:                                                              # Declare this function.
	var facing_names: Array[String] = ["N", "E", "S", "W"]                                     # Track the player camera direction as 0=N, 1=E, 2=S, 3=W.
	var facing_name: String = facing_names[facing]                                             # Track the player camera direction as 0=N, 1=E, 2=S, 3=W.
	var phase_text := "stable"                                                                 # Store mutable runtime state for assets, rendering, movement, or debug output.
	var wall_text := _visible_wall_ids_text()                                                  # Format the currently selected wall ids for debug display.
	if is_transitioning:                                                                       # Run the following block only when this condition is true.
		phase_text = "%s phase %d/%d" % [active_sequence_name, phase_index + 1, active_sequence.size()] # Compute and store this value for the current step.

	status_label.text = (                                                                      # Update the on-screen debug status label.
		"Xybots phase prototype | %s | Facing %s | Cell %d,%d | Local %.2f,%.2f | Anim %s | Walls %s%s\n" # Continue the controller logic for this section.
		+ "Four-cell thin-wall hallway. WASD moves inside tile; boundary crossing checks the edge wall. Q/E or arrows turn." # Continue the controller logic for this section.
	) % [                                                                                      # Close the current list, dictionary, call, or expression.
		phase_text,                                                                               # Continue the controller logic for this section.
		facing_name,                                                                              # Continue the controller logic for this section.
		grid_position.x,                                                                          # Continue the controller logic for this section.
		grid_position.y,                                                                          # Continue the controller logic for this section.
		local_floor_position.x,                                                                   # Continue the controller logic for this section.
		local_floor_position.y,                                                                   # Continue the controller logic for this section.
		String(player_sprite.animation),                                                          # Continue the controller logic for this section.
		wall_text,                                                                                # Continue the controller logic for this section.
		(" | Blocked " + last_blocked_direction) if not last_blocked_direction.is_empty() else "" # Continue the controller logic for this section.
	]                                                                                          # Close the current list, dictionary, call, or expression.



# _visible_wall_ids_text: Formats the selected wall ids so screenshots show what the visibility tree chose.
func _visible_wall_ids_text() -> String:                                                     # Declare this function.
	if last_visible_wall_ids.is_empty():                                                       # Show a placeholder when no stable wall overlays are selected.
		return "-"                                                                               # Return a no-walls marker for the status text.
	var parts: Array[String] = []                                                              # Store formatted wall ids before joining them.
	for wall_id in last_visible_wall_ids:                                                      # Iterate through the selected wall id list.
		parts.append("%02d" % wall_id)                                                            # Add this wall id as a two-digit label.
	return ",".join(parts)                                                                     # Return the comma-separated wall id list.
