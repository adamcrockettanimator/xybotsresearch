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
const MOVE_UNITS_PER_SECOND := 1.70                                                         # Set movement in normalized half-tile units so X and Y ground speed match.
const HOME_LOCAL_FLOOR_POSITION := Vector2(0.5, 0.68)                                       # Set the resting local position inside a tile.
const FORWARD_TRIGGER_Y := 0.56                                                             # Set the forward threshold where crossing into the next tile begins.
const BACKWARD_TRIGGER_Y := 0.84                                                            # Set the backward threshold where crossing into the previous tile begins.
const STRAFE_LEFT_WALL_CONTACT_X := 0.0                                                     # Set the left tile-edge contact; camera clipping trims any body pixels beyond the frame.
const STRAFE_RIGHT_WALL_CONTACT_X := 1.0                                                    # Set the right tile-edge contact; camera clipping trims any body pixels beyond the frame.
const FORWARD_WALL_CONTACT_Y := 0.56                                                        # Set the closest blocked-wall contact position in front of the viewer.
const BACKWARD_WALL_CONTACT_Y := 0.84                                                       # Set the closest blocked-wall contact position behind the viewer.
const MAP_WIDTH := 4                                                                        # Set the generated test map width in thin-wall cells.
const MAP_HEIGHT := 4                                                                       # Set the generated test map height in thin-wall cells.
const MAP_EXTRA_OPENING_CHANCE := 0.18                                                      # Add a few loops after maze carving so the interior is not a strict tree.

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
const CORRIDOR_FAR_FLOOR_DEPTH := 0.0                                                         # Set the farthest local floor-depth sample used by the shared corridor trapezoid.
const FRONT_WALL_HEIGHT_BY_DEPTH := [88.0, 56.0, 36.0, 24.0]                                  # Store measured front-wall pixel heights for depth rows 0..3 from the straight wall art.
const PERSPECTIVE_CELL_EXTENTS := [                                                          # Store measured per-square trapezoids from the player/opponent square studies.
	{"near_depth": 0.04, "far_depth": 0.96, "near_left_x": 0.0, "near_right_x": 159.0, "far_left_x": 16.0, "far_right_x": 143.0, "near_feet_y": 119.0, "far_feet_y": 96.0, "near_actor_height": 66.0, "far_actor_height": 43.0}, # Current camera square: measured from the red floor-zone guide in floor zones.png.
	{"near_depth": 0.96, "far_depth": 1.96, "near_left_x": 18.0, "near_right_x": 141.0, "far_left_x": 40.0, "far_right_x": 119.0, "near_feet_y": 94.0, "far_feet_y": 72.0, "near_actor_height": 43.0, "far_actor_height": 30.0}, # One square away: measured from the yellow floor-zone guide in floor zones.png.
	{"near_depth": 1.96, "far_depth": 2.96, "near_left_x": 42.0, "near_right_x": 117.0, "far_left_x": 56.0, "far_right_x": 103.0, "near_feet_y": 70.0, "far_feet_y": 56.0, "near_actor_height": 30.0, "far_actor_height": 21.0}, # Two squares away: measured from the green floor-zone guide in floor zones.png.
	{"near_depth": 2.96, "far_depth": 3.96, "near_left_x": 58.0, "near_right_x": 101.0, "far_left_x": 64.0, "far_right_x": 95.0, "near_feet_y": 54.0, "far_feet_y": 48.0, "near_actor_height": 21.0, "far_actor_height": 14.0}, # Three squares away: measured from the blue floor-zone guide in floor zones.png.
]                                                                                             # End the measured per-square perspective calibration table.
const SIDE_PERSPECTIVE_CELL_EXTENTS := [                                                     # Store measured right-side opponent-entry bands from floor zones side.png; left side mirrors these values.
	{"near_depth": 0.04, "far_depth": 0.96, "near_inner_x": 159.0, "far_inner_x": 145.0, "near_feet_y": 110.0, "far_feet_y": 96.0}, # Current side square: measured from the red right-side zone.
	{"near_depth": 0.96, "far_depth": 1.96, "near_inner_x": 159.0, "far_inner_x": 121.0, "near_feet_y": 94.0, "far_feet_y": 72.0}, # One square away side entry: measured from the yellow right-side zone.
	{"near_depth": 1.96, "far_depth": 2.96, "near_inner_x": 159.0, "far_inner_x": 105.0, "near_feet_y": 70.0, "far_feet_y": 56.0}, # Two squares away side entry: measured from the green right-side zone.
	{"near_depth": 2.96, "far_depth": 3.96, "near_inner_x": 159.0, "far_inner_x": 95.0, "near_feet_y": 54.0, "far_feet_y": 46.0}, # Three squares away side entry: measured from the cyan right-side zone.
]                                                                                             # End the side-entry perspective calibration table.
const WALL_EDGE_N := 0                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_E := 1                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_S := 2                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const WALL_EDGE_W := 3                                                                      # Define a fixed value used by the movement, rendering, or asset-loading system.
const VIEW_FRONT := "front"                                                                 # Define a fixed value used by the movement, rendering, or asset-loading system.
const VIEW_LEFT := "left"                                                                   # Define a fixed value used by the movement, rendering, or asset-loading system.
const VIEW_RIGHT := "right"                                                                 # Define a fixed value used by the movement, rendering, or asset-loading system.
const ACTION_MOVE_LEFT := "xybots_move_left"                                                # Name the explicit input action for moving camera-left inside the current tile.
const ACTION_MOVE_RIGHT := "xybots_move_right"                                              # Name the explicit input action for moving camera-right inside the current tile.
const ACTION_MOVE_FORWARD := "xybots_move_forward"                                          # Name the explicit input action for moving toward the camera-facing edge.
const ACTION_MOVE_BACKWARD := "xybots_move_backward"                                        # Name the explicit input action for moving away from the camera-facing edge.
const ACTION_TURN_LEFT := "xybots_turn_left"                                                # Name the explicit input action for rotating the view left.
const ACTION_TURN_RIGHT := "xybots_turn_right"                                              # Name the explicit input action for rotating the view right.
const ACTION_REGENERATE_MAP := "xybots_regenerate_map"                                      # Name the explicit input action for rerolling the debug maze at runtime.
const ACTION_P2_MOVE_LEFT := "xybots_p2_move_left"                                          # Name the second-player input action for moving camera-left inside the current tile.
const ACTION_P2_MOVE_RIGHT := "xybots_p2_move_right"                                        # Name the second-player input action for moving camera-right inside the current tile.
const ACTION_P2_MOVE_FORWARD := "xybots_p2_move_forward"                                    # Name the second-player input action for moving toward the camera-facing edge.
const ACTION_P2_MOVE_BACKWARD := "xybots_p2_move_backward"                                  # Name the second-player input action for moving away from the camera-facing edge.
const ACTION_P2_TURN_LEFT := "xybots_p2_turn_left"                                          # Name the second-player input action for rotating the view left.
const ACTION_P2_TURN_RIGHT := "xybots_p2_turn_right"                                        # Name the second-player input action for rotating the view right.
const DEBUG_MAP_CELL_SIZE := 24.0                                                           # Set the top-down debug map cell size inside the 160x120 diagnostic panel.
const DEBUG_MAP_PANEL_GRID_ORIGIN := Vector2(32.0, 12.0)                                    # Center the 4x4 debug maze inside the source-map panel.
const DEBUG_VIEW_CONE_DEPTH := 4.0                                                           # Draw the diagnostic view cone out to the farthest straight wall slot depth.
const DEBUG_VIEW_CONE_HALF_WIDTH := 2.25                                                     # Match the top-down cone width from the Wall_Grid reference image.
const CAMERA_REAR_OFFSET := 0.46                                                             # Place the cell-locked camera just in front of the rear wall for the current facing.
const LOCAL_TILE_WORLD_HALF_EXTENT := 0.5                                                    # Convert one normalized in-tile offset into one full square half-width in world-grid units.
const SELF_MIN_ACTOR_SCALE_VIEW_DEPTH := 0.78                                                # Keep the self-view body scale sampled from visible S0 space, not the camera-plane crop edge.
const LOCAL_FEET_FLOOR_MARGIN_PIXELS := 7.0                                                  # Keep the local feet anchor inside the projected floor-zone polygon.
const LOCAL_FEET_DEPTH_MARGIN_PIXELS := 4.0                                                  # Keep the local feet slightly inside the front edge of the projected floor-zone polygon.
const CHARACTER_NEAREST_LAYER := 96                                                          # Set the closest character draw layer; this is only z-order, not perspective math.
const LOCAL_CHARACTER_LAYER := 96                                                            # Draw the local body above wall art; the camera clipper handles frame-edge cropping.
const CHARACTER_LAYER_BY_DEPTH := [96, 74, 56, 32]                                           # Keep actors in front of same-depth side walls but behind nearer wall rows.
const LOCAL_REAR_CAMERA_CROP_PIXELS := 22.0                                                   # Let the local body sink out of frame when backed into the camera-side wall.
const LOCAL_REAR_CAMERA_SCALE_BOOST := 0.20                                                   # Enlarge the local body near the camera after cropping hides the lower frame.
const DEBUG_WALL_LABELS_ENABLED := true                                                     # Enable numeric debug labels on visible wall overlay sprites.
const VISIBILITY_RAY_COUNT := 91                                                            # Cast enough rays across the view fan to discover side and front wall edges.
const VISIBILITY_RAY_HALF_ANGLE_DEGREES := rad_to_deg(atan(DEBUG_VIEW_CONE_HALF_WIDTH / DEBUG_VIEW_CONE_DEPTH)) # Match ray casting to the Wall_Grid cone shape.
const VISIBILITY_MAX_DISTANCE := 5.2                                                        # Limit ray tests to the straight-view art depth.
const DIAGNOSTIC_3D_WALL_HEIGHT := 1.2                                                       # Set the generated 3D wall height in world units.
const DIAGNOSTIC_3D_WALL_THICKNESS := 0.06                                                   # Set the generated 3D thin-wall thickness in world units.
const DIAGNOSTIC_3D_CELL_WIDTH := 1.35                                                       # Widen the diagnostic cell volume so the 3D hallway better matches the 2D projection.
const DIAGNOSTIC_3D_LOCAL_SIDE_HALF_EXTENT := 0.56                                           # Convert normalized side offsets into widened 3D cell units.
const DIAGNOSTIC_3D_LOCAL_DEPTH_HALF_EXTENT := 0.42                                          # Convert normalized forward/back offsets into 3D cell units.
const DIAGNOSTIC_3D_SEPARATOR_THICKNESS := 0.025                                             # Set the thickness of black cell-separation guide strips.

const STRAIGHT_WALL_SLOTS := [                                                              # Start the table that maps wall numbers to view-relative map tests and draw order.
	{"id": 1, "lateral": -2, "depth": 4, "edge": VIEW_FRONT, "draw": 10},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 2, "lateral": -1, "depth": 4, "edge": VIEW_FRONT, "draw": 11},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 3, "lateral": -1, "depth": 3, "edge": VIEW_FRONT, "draw": 12},                      # Draw the left piece of the front wall three cells ahead.
	{"id": 4, "lateral": 0, "depth": 3, "edge": VIEW_FRONT, "draw": 13},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 5, "lateral": 1, "depth": 3, "edge": VIEW_FRONT, "draw": 14},                       # Draw the right piece of the front wall three cells ahead.
	{"id": 6, "lateral": 0, "depth": 4, "edge": VIEW_LEFT, "draw": 20},                        # Draw the far left side-wall run.
	{"id": 7, "lateral": 0, "depth": 3, "edge": VIEW_LEFT, "draw": 21},                        # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 8, "lateral": 0, "depth": 3, "edge": VIEW_RIGHT, "draw": 22},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 9, "lateral": 0, "depth": 4, "edge": VIEW_RIGHT, "draw": 23},                       # Draw the far right side-wall run.
	{"id": 10, "lateral": -1, "depth": 3, "edge": VIEW_FRONT, "draw": 30},                     # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 11, "lateral": -1, "depth": 2, "edge": VIEW_FRONT, "draw": 31},                     # Draw the left piece of the front wall two cells ahead.
	{"id": 12, "lateral": 0, "depth": 2, "edge": VIEW_FRONT, "draw": 32},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 13, "lateral": 1, "depth": 2, "edge": VIEW_FRONT, "draw": 40},                      # Draw the right piece of the front wall two cells ahead.
	{"id": 14, "lateral": -1, "depth": 2, "edge": VIEW_RIGHT, "draw": 41},                     # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 15, "lateral": 0, "depth": 2, "edge": VIEW_LEFT, "draw": 42},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 16, "lateral": 0, "depth": 2, "edge": VIEW_LEFT, "draw": 43},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 17, "lateral": 0, "depth": 2, "edge": VIEW_RIGHT, "draw": 50},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 18, "lateral": 0, "depth": 2, "edge": VIEW_FRONT, "draw": 51},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 19, "lateral": -1, "depth": 1, "edge": VIEW_FRONT, "draw": 58},                     # Draw the left piece of the front wall one cell ahead.
	{"id": 20, "lateral": 0, "depth": 1, "edge": VIEW_FRONT, "draw": 60},                      # Draw the center piece of the front wall one cell ahead.
	{"id": 21, "lateral": 1, "depth": 1, "edge": VIEW_FRONT, "draw": 62},                      # Draw the right piece of the front wall one cell ahead.
	{"id": 22, "lateral": 0, "depth": 1, "edge": VIEW_LEFT, "draw": 62},                       # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 23, "lateral": 0, "depth": 1, "edge": VIEW_RIGHT, "draw": 63},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 24, "lateral": -1, "depth": 0, "edge": VIEW_FRONT, "draw": 70},                     # Draw the left piece of an immediate front wall.
	{"id": 25, "lateral": 0, "depth": 0, "edge": VIEW_FRONT, "draw": 80},                      # Describe one numbered straight-wall overlay and the map edge that controls it.
	{"id": 26, "lateral": 1, "depth": 0, "edge": VIEW_FRONT, "draw": 90},                      # Draw the right piece of an immediate front wall.
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

@export_group("Movement Phases")                                                            # Group inspector controls for captured movement and turn phase playback.
@export var use_captured_transitions := false                                                # Snap movement/turns by default until the matching transition art is rebuilt.

@export_group("Diagnostics")                                                                # Group inspector toggles for temporary visual debugging tools.
@export var enable_3d_diagnostic := false                                                    # Keep the experimental 3D view disabled unless it is explicitly needed.
@export var show_top_down_source_overlay := true                                             # Show the 2D source-of-truth map overlay during wall/collision debugging.
@export var show_perspective_extents_overlay := true                                         # Show colored projected square extents over each 160x120 player view.

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

var maze_content: Node2D                                                                     # Store the clipped 160x120 content root inside the currently bound player view.
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
var perspective_extents_overlay: Node2D                                                     # Store the projected-square debug overlay for the currently bound player view.
var debug_map_overlay: Node2D                                                               # Store the top-down debug line map drawn over the game view.
var opponent_sprite: AnimatedSprite2D                                                       # Store the currently bound sprite used to show the other local player.
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
var grid_position := Vector2i(0, 3)                                                         # Track the current cell in the top-down maze map.
var local_floor_position := HOME_LOCAL_FLOOR_POSITION                                       # Track the character position inside the current tile.
var run_dir := DIR_N                                                                        # Track the body movement direction used for animation selection.
var aim_dir := DIR_N                                                                        # Track the aiming direction used for animation selection.
var last_animation: StringName = &""                                                        # Remember the last animation to avoid restarting it every frame.
var character_is_moving := false                                                            # Track whether the bound player is actively moving this frame.
var world_run_dir := DIR_N                                                                  # Track this player's movement direction in shared world space for opponent rendering.
var world_aim_dir := DIR_N                                                                  # Track this player's aim direction in shared world space for opponent rendering.
var available_animations: Dictionary = {}                                                   # Store animation-name lookups for exact and fallback animation selection.
var pending_grid_delta := Vector2i.ZERO                                                     # Store the cell movement that will be applied after a transition finishes.
var last_blocked_direction := ""                                                            # Store the most recent blocked movement label for debug display.
var wall_edges: Dictionary = {}                                                             # Store explicit thin-wall edge flags for each open cell.
var last_visible_wall_ids: Array[int] = []                                                   # Store the currently selected straight-wall ids for debug display.
var was_left_turn_pressed := false                                                          # Track previous-frame left turn input so snapped turns only fire once per press.
var was_right_turn_pressed := false                                                         # Track previous-frame right turn input so snapped turns only fire once per press.
var was_regenerate_map_pressed := false                                                      # Track previous-frame map-regenerate input so it fires once per key press.
var held_keycodes := {}                                                                      # Track key press/release events delivered to this controller as an input fallback.
var active_player_index := 0                                                                 # Track which local player is currently bound into the legacy single-player renderer state.
var player_states: Array[Dictionary] = []                                                    # Store per-player movement, facing, transition, and debug state.
var player_views: Array[Dictionary] = []                                                     # Store per-player playfield, map, wall, and sprite node references.



# _ready: Initializes the maze wall data, loads textures, creates renderer nodes, and draws the starting view.
func _ready() -> void:                                                                      # Declare this function.
	_ensure_input_actions()                                                                    # Register local input actions before the first input polling frame.
	_build_fixed_reference_maze_wall_edges()                                                     # Load the current fixed 4x4 thin-wall test maze before rendering.
	_load_phase_textures()                                                                     # Call a helper function as part of the current controller step.
	_load_stable_textures()                                                                    # Call a helper function as part of the current controller step.
	_load_slot_textures()                                                                      # Call a helper function as part of the current controller step.
	_load_straight_wall_textures()                                                             # Call a helper function as part of the current controller step.
	_setup_viewport()                                                                          # Call a helper function as part of the current controller step.
	_setup_player_animation()                                                                  # Call a helper function as part of the current controller step.
	_setup_local_multiplayer()                                                                 # Create the second local screen and player-state records.
	_setup_all_player_renderers()                                                              # Create an independent wall renderer and top-down map for each local player.
	if enable_3d_diagnostic:                                                                   # Only create the deprecated 3D diagnostic when explicitly requested.
		_setup_3d_diagnostic()                                                                    # Create the side-by-side 3D map diagnostic view.
	_render_all_player_views()                                                                 # Draw both starting screens and both debug maps.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _input: Records keyboard press and release events so movement does not depend only on raw polling.
func _input(event: InputEvent) -> void:                                                     # Declare this function.
	if event is InputEventKey and not event.echo:                                             # Only handle real keyboard press/release events once.
		held_keycodes[int(event.keycode)] = event.pressed                                       # Store whether this logical key is currently held.
		if event.physical_keycode != 0:                                                         # Preserve physical key bindings when Godot supplies them.
			held_keycodes[int(event.physical_keycode)] = event.pressed                            # Store the physical key state as another lookup option.



# _setup_local_multiplayer: Creates player two's view nodes and initializes two independent local player states.
func _setup_local_multiplayer() -> void:                                                    # Declare this function.
	var player_one_opponent := _create_character_sprite("OpponentSprite")                       # Create player one's sprite used for seeing player two.
	maze_content.add_child(player_one_opponent)                                                 # Put the opponent sprite into player one's clipped camera content.
	var player_two_viewport := Node2D.new()                                                     # Create a second cropped playfield container for player two.
	player_two_viewport.name = "MazeViewportP2"                                                 # Name the player-two view for scene-tree inspection.
	add_child(player_two_viewport)                                                              # Attach player two's screen to the main scene.
	var player_two_content := _ensure_viewport_clipper(player_two_viewport)                     # Give player two the same 160x120 camera clipper.
	var player_two_playfield := Sprite2D.new()                                                   # Create player two's transition-frame sprite.
	player_two_playfield.name = "Playfield"                                                     # Match player one's child naming convention.
	player_two_playfield.centered = false                                                       # Anchor player two's playfield from its top-left corner.
	player_two_playfield.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                     # Preserve the cropped pixel art.
	player_two_content.add_child(player_two_playfield)                                          # Add the playfield to player two's clipped camera content.
	var player_two_sprite := _create_character_sprite("PlayerSprite")                           # Create player two's own character sprite.
	player_two_content.add_child(player_two_sprite)                                             # Add player two's self sprite to the clipped camera content.
	var player_two_opponent := _create_character_sprite("OpponentSprite")                       # Create player two's sprite used for seeing player one.
	player_two_content.add_child(player_two_opponent)                                           # Add player two's opponent sprite to the clipped camera content.
	player_views = [                                                                            # Store view-node bundles for each local player.
		{"maze_viewport": maze_viewport, "maze_content": maze_content, "playfield": playfield, "player_sprite": player_sprite, "opponent_sprite": player_one_opponent}, # Store player one's existing view nodes.
		{"maze_viewport": player_two_viewport, "maze_content": player_two_content, "playfield": player_two_playfield, "player_sprite": player_two_sprite, "opponent_sprite": player_two_opponent}, # Store player two's new view nodes.
	]                                                                                           # Close the local-player view list.
	player_states = [                                                                           # Create initial player-state records for both local players.
		_make_player_state(0, Vector2i(0, MAP_HEIGHT - 1), 0),                                    # Start player one in the southwest corner facing north.
		_make_player_state(1, Vector2i(MAP_WIDTH - 1, 0), 2),                                     # Start player two in the northeast corner facing south.
	]                                                                                           # Close the local-player state list.
	_bind_player_context(0)                                                                     # Bind player one back into the legacy globals after setup.



# _create_character_sprite: Builds a character AnimatedSprite2D with duplicated frames for a local player or opponent.
func _create_character_sprite(sprite_name: String) -> AnimatedSprite2D:                    # Declare this function.
	var sprite := AnimatedSprite2D.new()                                                       # Create a fresh animated character sprite.
	sprite.name = sprite_name                                                                   # Name the sprite for scene-tree inspection.
	sprite.sprite_frames = player_sprite.sprite_frames.duplicate(true)                          # Give this sprite its own copy of the loaded player animations.
	sprite.centered = true                                                                      # Register the sprite from its center like the original player node.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                                  # Preserve the source sprite pixels when scaled.
	sprite.z_index = 10 if sprite_name == "PlayerSprite" else 9                                 # Give characters a default layer before runtime depth sorting.
	sprite.visible = sprite_name == "PlayerSprite"                                             # Hide opponent sprites until another player is actually visible.
	return sprite                                                                               # Return the configured character sprite.



# _make_player_state: Builds one serializable local player state dictionary.
func _make_player_state(player_index: int, start_cell: Vector2i, start_facing: int) -> Dictionary: # Declare this function.
	return {                                                                                    # Return a complete player-state record.
		"player_index": player_index,                                                             # Store this player's local index.
		"active_sequence": [],                                                                     # Store any currently playing captured transition frames.
		"active_sequence_name": "idle",                                                            # Store the current transition or idle label.
		"phase_index": 0,                                                                          # Store the current transition frame index.
		"phase_timer": 0.0,                                                                        # Store elapsed time inside the current transition frame.
		"is_transitioning": false,                                                                 # Store whether this player is in a captured transition.
		"facing": start_facing,                                                                    # Store this player's camera direction.
		"grid_position": start_cell,                                                               # Store this player's source-map cell.
		"local_floor_position": HOME_LOCAL_FLOOR_POSITION,                                        # Store this player's position inside the current cell.
		"run_dir": DIR_N,                                                                          # Store this player's current body movement animation direction.
		"aim_dir": DIR_N,                                                                          # Store this player's current aim animation direction.
		"last_animation": &"",                                                                     # Store this player's last animation name.
		"character_is_moving": false,                                                              # Store whether this player is actively running this frame.
		"world_run_dir": _direction_string_for_facing(start_facing),                                # Store this player's shared-world movement direction.
		"world_aim_dir": _direction_string_for_facing(start_facing),                                # Store this player's shared-world aim direction.
		"pending_grid_delta": Vector2i.ZERO,                                                       # Store any pending cell-crossing movement.
		"last_blocked_direction": "",                                                             # Store this player's most recent blocked edge.
		"last_visible_wall_ids": [],                                                               # Store this player's currently rendered wall ids.
		"was_left_turn_pressed": false,                                                            # Store this player's left-turn one-shot latch.
		"was_right_turn_pressed": false,                                                           # Store this player's right-turn one-shot latch.
	}                                                                                           # Close the player-state dictionary.



# _setup_all_player_renderers: Creates separate environment and map overlays for every local player view.
func _setup_all_player_renderers() -> void:                                                # Declare this function.
	for player_index in range(player_views.size()):                                           # Visit each local player's view bundle.
		_bind_player_context(player_index)                                                       # Bind this player's view and state before creating renderer nodes.
		slot_nodes = {}                                                                           # Give this player a separate legacy slot-node dictionary.
		straight_wall_nodes = {}                                                                  # Give this player a separate straight-wall-node dictionary.
		straight_wall_label_nodes = {}                                                            # Give this player a separate wall-label-node dictionary.
		_setup_environment_layer()                                                                # Build this player's independent environment sprite stack.
		_setup_perspective_extents_overlay()                                                      # Build this player's projected-square debug overlay.
		_setup_debug_map_overlay()                                                                # Build this player's independent top-down source map.
		_store_bound_view_nodes(player_index)                                                     # Save the renderer nodes back into the player's view bundle.
		_save_player_context(player_index)                                                        # Save any state touched during renderer setup.
	_bind_player_context(0)                                                                     # Leave player one bound after setup for editor inspection.



# _store_bound_view_nodes: Saves the currently bound renderer and overlay nodes into one player's view bundle.
func _store_bound_view_nodes(player_index: int) -> void:                                  # Declare this function.
	var view := player_views[player_index]                                                     # Read this player's view bundle.
	view["environment_layer"] = environment_layer                                              # Store this player's environment renderer node.
	view["maze_content"] = maze_content                                                        # Store this player's clipped camera content root.
	view["floor_sprite"] = floor_sprite                                                        # Store this player's floor sprite.
	view["slot_nodes"] = slot_nodes                                                            # Store this player's legacy slot sprites.
	view["straight_wall_nodes"] = straight_wall_nodes                                          # Store this player's numbered wall sprites.
	view["straight_wall_label_nodes"] = straight_wall_label_nodes                              # Store this player's numbered wall debug labels.
	view["perspective_extents_overlay"] = perspective_extents_overlay                          # Store this player's projected-square debug overlay.
	view["debug_map_overlay"] = debug_map_overlay                                              # Store this player's top-down debug map overlay.
	player_views[player_index] = view                                                          # Write the updated view bundle back into the array.



# _bind_player_context: Loads one player's state and view nodes into the existing single-player globals.
func _bind_player_context(player_index: int) -> void:                                     # Declare this function.
	active_player_index = player_index                                                        # Remember which player the shared helpers are currently serving.
	var view: Dictionary = player_views[player_index] if player_index < player_views.size() else {} # Read the player's view-node bundle.
	maze_viewport = view.get("maze_viewport", maze_viewport)                                  # Bind the cropped playfield container.
	maze_content = view.get("maze_content", maze_content)                                     # Bind the clipped 160x120 camera content root.
	playfield = view.get("playfield", playfield)                                               # Bind the transition-frame sprite.
	player_sprite = view.get("player_sprite", player_sprite)                                   # Bind this player's character sprite.
	opponent_sprite = view.get("opponent_sprite", opponent_sprite)                             # Bind this player's opponent sprite.
	environment_layer = view.get("environment_layer", environment_layer)                       # Bind this player's environment renderer.
	floor_sprite = view.get("floor_sprite", floor_sprite)                                      # Bind this player's floor sprite.
	slot_nodes = view.get("slot_nodes", slot_nodes)                                            # Bind this player's legacy slot nodes.
	straight_wall_nodes = view.get("straight_wall_nodes", straight_wall_nodes)                 # Bind this player's numbered wall nodes.
	straight_wall_label_nodes = view.get("straight_wall_label_nodes", straight_wall_label_nodes) # Bind this player's wall-label nodes.
	perspective_extents_overlay = view.get("perspective_extents_overlay", perspective_extents_overlay) # Bind this player's projected-square debug overlay.
	debug_map_overlay = view.get("debug_map_overlay", debug_map_overlay)                       # Bind this player's top-down source map.
	if player_index >= player_states.size():                                                   # Skip state loading if setup has not created states yet.
		return                                                                                    # Return with only view nodes bound.
	var state: Dictionary = player_states[player_index]                                        # Read this player's movement-state bundle.
	active_sequence = _texture_sequence_from_state(state.get("active_sequence", []))            # Restore this player's transition frame list.
	active_sequence_name = String(state.get("active_sequence_name", "idle"))                    # Restore this player's transition label.
	phase_index = int(state.get("phase_index", 0))                                             # Restore this player's transition frame index.
	phase_timer = float(state.get("phase_timer", 0.0))                                         # Restore this player's transition timer.
	is_transitioning = bool(state.get("is_transitioning", false))                              # Restore whether this player is in a captured transition.
	facing = int(state.get("facing", 0))                                                        # Restore this player's facing.
	grid_position = state.get("grid_position", Vector2i.ZERO)                                  # Restore this player's current map cell.
	local_floor_position = state.get("local_floor_position", HOME_LOCAL_FLOOR_POSITION)        # Restore this player's local cell position.
	run_dir = String(state.get("run_dir", DIR_N))                                              # Restore this player's run animation direction.
	aim_dir = String(state.get("aim_dir", DIR_N))                                              # Restore this player's aim animation direction.
	last_animation = state.get("last_animation", &"")                                          # Restore this player's last animation name.
	character_is_moving = bool(state.get("character_is_moving", false))                        # Restore whether this player is actively running.
	world_run_dir = String(state.get("world_run_dir", _direction_string_for_facing(facing)))    # Restore this player's world movement direction.
	world_aim_dir = String(state.get("world_aim_dir", _direction_string_for_facing(facing)))    # Restore this player's world aim direction.
	pending_grid_delta = state.get("pending_grid_delta", Vector2i.ZERO)                        # Restore this player's pending cell crossing.
	last_blocked_direction = String(state.get("last_blocked_direction", ""))                    # Restore this player's blocked-edge label.
	was_left_turn_pressed = bool(state.get("was_left_turn_pressed", false))                    # Restore this player's left-turn input latch.
	was_right_turn_pressed = bool(state.get("was_right_turn_pressed", false))                  # Restore this player's right-turn input latch.
	last_visible_wall_ids.clear()                                                              # Clear this player's visible-wall debug list before restoring it.
	for wall_id in state.get("last_visible_wall_ids", []):                                     # Copy wall ids out of the saved state.
		last_visible_wall_ids.append(int(wall_id))                                                # Restore one visible-wall id.



# _save_player_context: Stores the currently bound legacy globals back into one local player state.
func _save_player_context(player_index: int) -> void:                                     # Declare this function.
	if player_index >= player_states.size():                                                   # Guard against saving before states exist.
		return                                                                                    # Return without changing player state.
	var state: Dictionary = player_states[player_index]                                        # Read this player's existing state dictionary.
	state["active_sequence"] = active_sequence.duplicate()                                     # Save this player's transition sequence.
	state["active_sequence_name"] = active_sequence_name                                       # Save this player's transition label.
	state["phase_index"] = phase_index                                                         # Save this player's transition frame index.
	state["phase_timer"] = phase_timer                                                         # Save this player's transition timer.
	state["is_transitioning"] = is_transitioning                                               # Save this player's transition flag.
	state["facing"] = facing                                                                    # Save this player's facing.
	state["grid_position"] = grid_position                                                     # Save this player's map cell.
	state["local_floor_position"] = local_floor_position                                       # Save this player's local cell position.
	state["run_dir"] = run_dir                                                                  # Save this player's run animation direction.
	state["aim_dir"] = aim_dir                                                                  # Save this player's aim animation direction.
	state["last_animation"] = last_animation                                                   # Save this player's last animation name.
	state["character_is_moving"] = character_is_moving                                         # Save whether this player is actively running.
	state["world_run_dir"] = world_run_dir                                                     # Save this player's world movement direction for other views.
	state["world_aim_dir"] = world_aim_dir                                                     # Save this player's world aim direction for other views.
	state["pending_grid_delta"] = pending_grid_delta                                           # Save this player's pending cell crossing.
	state["last_blocked_direction"] = last_blocked_direction                                   # Save this player's blocked-edge label.
	state["last_visible_wall_ids"] = last_visible_wall_ids.duplicate()                         # Save this player's visible-wall debug ids.
	state["was_left_turn_pressed"] = was_left_turn_pressed                                     # Save this player's left-turn input latch.
	state["was_right_turn_pressed"] = was_right_turn_pressed                                   # Save this player's right-turn input latch.
	player_states[player_index] = state                                                        # Write this player's state back into the array.



# _texture_sequence_from_state: Converts a saved untyped array back into the typed transition frame list.
func _texture_sequence_from_state(value: Variant) -> Array[Texture2D]:                    # Declare this function.
	var sequence: Array[Texture2D] = []                                                        # Create a typed transition sequence result.
	if value is Array:                                                                          # Only copy values from array-like state.
		for item in value:                                                                         # Visit each saved sequence item.
			if item is Texture2D:                                                                     # Keep only actual transition textures.
				sequence.append(item)                                                                 # Add this transition texture to the typed result.
	return sequence                                                                             # Return the typed transition sequence.



# _process_player_context: Runs input, movement, turn, transition, and animation for the currently bound player.
func _process_player_context(delta: float) -> void:                                      # Declare this function.
	if is_transitioning:                                                                       # Advance captured transition playback for this player if enabled.
		_advance_transition(delta)                                                                # Move this player's transition to the next frame when needed.
		return                                                                                    # Return after transition processing.
	var turn_direction := _read_turn()                                                         # Read this player's one-shot turn input.
	if turn_direction < 0:                                                                     # Handle a left turn request.
		_request_transition("turn_left")                                                           # Snap or animate this player's left turn.
		return                                                                                    # Return after turn processing.
	if turn_direction > 0:                                                                     # Handle a right turn request.
		_request_transition("turn_right")                                                          # Snap or animate this player's right turn.
		return                                                                                    # Return after turn processing.
	var movement := _read_movement()                                                           # Read this player's local movement input.
	if movement != Vector2.ZERO:                                                               # Choose moving animation and move through the current cell.
		run_dir = _movement_to_first_player_run_dir(movement)                                     # Select the visible body-run direction for this local view.
		aim_dir = DIR_N                                                                           # Keep this player's aim locked camera-forward in their own view.
		character_is_moving = true                                                                # Mark this player as moving so opponents can play run animations.
		world_run_dir = _world_movement_dir_for_local_movement(movement, facing)                  # Convert local movement into shared-world direction for other players.
		world_aim_dir = _direction_string_for_facing(facing)                                      # Store the camera-facing aim direction in shared-world space.
		_play_best_animation(true)                                                                # Start or maintain the moving animation.
		_move_inside_tile(movement, delta)                                                        # Apply local movement and wall/crossing checks.
	else:                                                                                      # Handle no movement input.
		run_dir = DIR_N                                                                           # Reset the visible body direction to camera-forward idle.
		aim_dir = DIR_N                                                                           # Keep aim camera-forward while idle.
		character_is_moving = false                                                               # Mark this player as idle for opponent first-frame fallback.
		world_run_dir = _direction_string_for_facing(facing)                                      # Use facing as the idle body direction until idle variants exist.
		world_aim_dir = _direction_string_for_facing(facing)                                      # Store the camera-facing aim direction in shared-world space.
		_play_best_animation(false)                                                               # Play the best idle animation.



# _render_bound_player_context: Redraws the currently bound player's wall view, self sprite, opponent sprite, and map.
func _render_bound_player_context() -> void:                                              # Declare this function.
	if is_transitioning:                                                                       # Keep captured transition frames visible when a transition is playing.
		_position_player()                                                                        # Keep the player sprite registered over the transition frame.
	else:                                                                                      # Render a stable wall-sprite scene when no transition is playing.
		_show_stable()                                                                            # Compose the floor and visible wall sprites for this player's view.
		_position_player()                                                                        # Project this player's local cell position into the playfield.
	_position_opponent_sprite()                                                               # Project the other local player into this player's screen when visible.
	_update_perspective_extents_overlay()                                                     # Redraw the projected-square extents over this player's camera view.
	_update_debug_map_overlay()                                                               # Redraw this player's top-down map with the shared maze and both players.
	if enable_3d_diagnostic and active_player_index == 0:                                     # Keep deprecated 3D diagnostics tied to player one only.
		_update_3d_diagnostic()                                                                  # Sync the deprecated 3D diagnostic to player one's state.



# _render_all_player_views: Redraws every local player view after setup or a map reset.
func _render_all_player_views() -> void:                                                   # Declare this function.
	for player_index in range(player_states.size()):                                          # Visit each local player.
		_bind_player_context(player_index)                                                       # Bind that player's view and state.
		_play_best_animation(false)                                                               # Put the player in the idle animation after a full redraw.
		_render_bound_player_context()                                                           # Redraw that player's view and map.
		_save_player_context(player_index)                                                       # Store any renderer-updated debug ids.
	_bind_player_context(0)                                                                    # Leave player one bound after the all-player redraw.



# _process: Runs the per-frame input, movement, transition, animation, player positioning, and status update loop.
func _process(delta: float) -> void:                                                        # Declare this function.
	_layout_viewport()                                                                         # Call a helper function as part of the current controller step.
	if _read_regenerate_map():                                                                 # Check for a one-shot request to reroll the current 4x4 maze.
		_regenerate_runtime_map()                                                                 # Build and display a new random maze immediately.
		return                                                                                    # Skip movement this frame because the player was reset into the new map.
	for player_index in range(player_states.size()):                                          # First update every local player so all shared world positions are final for this frame.
		_bind_player_context(player_index)                                                       # Load this player's movement state and view nodes into the existing renderer.
		_process_player_context(delta)                                                           # Run one player's input, movement, turn, and animation logic.
		_save_player_context(player_index)                                                       # Store this player's updated state before binding the next player.
	for player_index in range(player_states.size()):                                          # Then render every local view against the completed shared player state.
		_bind_player_context(player_index)                                                       # Load this player's movement state and view nodes into the existing renderer.
		_render_bound_player_context()                                                           # Redraw that player's 2D view, opponent sprite, and source map.
		_save_player_context(player_index)                                                       # Store renderer-updated debug values for this player.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _setup_viewport: Configures nearest-neighbor rendering for the playfield and player, then lays out the cropped viewport.
func _setup_viewport() -> void:                                                             # Declare this function.
	maze_content = _ensure_viewport_clipper(maze_viewport)                                    # Give the first player view an actual 160x120 rectangular camera crop.
	playfield.centered = false                                                                 # Update the captured playfield sprite display.
	playfield.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                               # Update the captured playfield sprite display.
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                           # Update player sprite rendering or animation state.
	_layout_viewport()                                                                         # Call a helper function as part of the current controller step.



# _ensure_viewport_clipper: Creates a 160x120 clipping Control and moves playfield content under it.
func _ensure_viewport_clipper(view_root: Node2D) -> Node2D:                                  # Declare this function.
	var existing_content := view_root.get_node_or_null("Clipper/Content")                     # Reuse the clipped content root if this view was already configured.
	if existing_content is Node2D:                                                            # Detect an existing content root.
		return existing_content                                                                 # Return it without rebuilding the child tree.
	var clipper := Control.new()                                                              # Create a rectangular CanvasItem that can clip its children.
	clipper.name = "Clipper"                                                                  # Name the clipper for scene-tree inspection.
	clipper.position = Vector2.ZERO                                                           # Align the crop with the playfield origin.
	clipper.size = VIEWPORT_SIZE                                                              # Match the original 160x120 playfield crop.
	clipper.clip_contents = true                                                              # Clip children to the camera rectangle instead of using walls as masks.
	view_root.add_child(clipper)                                                              # Add the clipper to the view root.
	var content := Node2D.new()                                                               # Create a Node2D content root for the playfield, walls, and characters.
	content.name = "Content"                                                                  # Name the content root for scene-tree inspection.
	clipper.add_child(content)                                                                # Place all camera-visible content under the clipper.
	for child in view_root.get_children():                                                    # Move existing playfield children under the clipped content root.
		if child == clipper:                                                                    # Do not move the clipper into itself.
			continue                                                                               # Continue to the next child.
		view_root.remove_child(child)                                                           # Detach this existing playfield child from the unbounded view root.
		content.add_child(child)                                                                # Reattach it under the clipped camera content root.
	return content                                                                             # Return the content node used for later runtime children.



# _setup_environment_layer: Creates the runtime floor, straight-wall, and legacy slot sprites used to compose the environment.
func _setup_environment_layer() -> void:                                                    # Declare this function.
	environment_layer = Node2D.new()                                                           # Compute and store this value for the current step.
	environment_layer.name = "EnvironmentRenderer"                                             # Update the environment renderer container.
	environment_layer.z_index = 0                                                              # Keep wall overlays on the same z scale as opponent sprites for depth sorting.
	maze_content.add_child(environment_layer)                                                   # Add the environment under the clipped 160x120 camera content root.

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



# _setup_perspective_extents_overlay: Creates the per-player 160x120 projected-square debug overlay.
func _setup_perspective_extents_overlay() -> void:                                         # Declare this function.
	perspective_extents_overlay = Node2D.new()                                                # Create the overlay root used for projected-square guide geometry.
	perspective_extents_overlay.name = "DebugPerspectiveCellExtents"                           # Name the overlay so it is easy to find in the scene tree.
	perspective_extents_overlay.z_index = 150                                                  # Draw this diagnostic above wall and actor art.
	maze_content.add_child(perspective_extents_overlay)                                        # Attach the overlay inside the clipped camera content.
	_update_perspective_extents_overlay()                                                      # Draw the initial projected square extents immediately.



# _update_perspective_extents_overlay: Redraws colored trapezoids for every measured visible square.
func _update_perspective_extents_overlay() -> void:                                        # Declare this function.
	if perspective_extents_overlay == null:                                                    # Skip when this player view has no extent overlay.
		return                                                                                    # Return without drawing anything.
	perspective_extents_overlay.visible = show_perspective_extents_overlay                     # Apply the inspector toggle to this player's overlay.
	for child in perspective_extents_overlay.get_children():                                   # Remove the previous frame's guide primitives.
		child.free()                                                                              # Free this old debug primitive.
	if not show_perspective_extents_overlay:                                                   # Avoid rebuilding hidden guide geometry.
		return                                                                                    # Return after clearing stale children.
	var colors: Array[Color] = [                                                               # Define one readable color per projected square.
		Color(1.0, 0.15, 0.15, 0.34),                                                            # Use red for the current camera square.
		Color(1.0, 0.75, 0.0, 0.30),                                                             # Use amber for the next square.
		Color(0.0, 0.9, 0.35, 0.28),                                                             # Use green for the third square.
		Color(0.1, 0.55, 1.0, 0.28),                                                             # Use blue for the farthest square.
	]                                                                                           # Close the color list.
	for cell_index in range(PERSPECTIVE_CELL_EXTENTS.size()):                                  # Draw each measured projection square.
		var cell: Dictionary = PERSPECTIVE_CELL_EXTENTS[cell_index]                               # Read this square's near/far projection bounds.
		var color := colors[cell_index % colors.size()]                                           # Pick this square's debug color.
		var near_left := Vector2(float(cell["near_left_x"]), float(cell["near_feet_y"]))          # Compute the near-left projected floor corner.
		var near_right := Vector2(float(cell["near_right_x"]), float(cell["near_feet_y"]))        # Compute the near-right projected floor corner.
		var far_left := Vector2(float(cell["far_left_x"]), float(cell["far_feet_y"]))             # Compute the far-left projected floor corner.
		var far_right := Vector2(float(cell["far_right_x"]), float(cell["far_feet_y"]))           # Compute the far-right projected floor corner.
		_add_perspective_extent_polygon(cell_index, near_left, near_right, far_right, far_left, color) # Draw the translucent square volume footprint.
		_add_perspective_extent_line(near_left, near_right, Color(color.r, color.g, color.b, 0.95), 1.5) # Draw the near edge.
		_add_perspective_extent_line(far_left, far_right, Color(color.r, color.g, color.b, 0.95), 1.5) # Draw the far edge.
		_add_perspective_extent_line(near_left, far_left, Color(color.r, color.g, color.b, 0.85), 1.0) # Draw the left edge.
		_add_perspective_extent_line(near_right, far_right, Color(color.r, color.g, color.b, 0.85), 1.0) # Draw the right edge.
		var near_center := (near_left + near_right) * 0.5                                         # Compute the near-edge center for the depth centerline.
		var far_center := (far_left + far_right) * 0.5                                            # Compute the far-edge center for the depth centerline.
		_add_perspective_extent_line(near_center, far_center, Color(color.r, color.g, color.b, 0.55), 1.0) # Draw the center depth guide.
		_add_perspective_actor_height_tick(near_center, float(cell["near_actor_height"]), color)  # Draw the near actor-height measurement.
		_add_perspective_actor_height_tick(far_center, float(cell["far_actor_height"]), color)    # Draw the far actor-height measurement.
		_add_perspective_extent_label("S%d" % cell_index, (near_center + far_center) * 0.5, Color(color.r, color.g, color.b, 1.0)) # Label the square.
	_add_perspective_sprite_bounds(player_sprite, Color(0.0, 0.95, 1.0, 0.95), "P")          # Draw the local player's actual projected sprite bounds and feet point.
	if opponent_sprite != null and opponent_sprite.visible:                                  # Draw the opponent marker only when this view can currently see the opponent.
		_add_perspective_sprite_bounds(opponent_sprite, Color(1.0, 0.0, 0.85, 0.95), "O")       # Draw the opponent's projected sprite bounds and feet point.



# _add_perspective_extent_polygon: Adds a translucent projected-square fill to the camera overlay.
func _add_perspective_extent_polygon(cell_index: int, near_left: Vector2, near_right: Vector2, far_right: Vector2, far_left: Vector2, color: Color) -> void: # Declare this function.
	var polygon := Polygon2D.new()                                                            # Create a filled polygon for the square extent.
	polygon.name = "PerspectiveSquare%dFill" % cell_index                                      # Name the fill by square index.
	polygon.polygon = PackedVector2Array([near_left, near_right, far_right, far_left])         # Use the near/far edge corners as the trapezoid shape.
	polygon.color = color                                                                      # Apply the translucent square color.
	polygon.z_index = 0                                                                        # Draw fills below outline and label children within this overlay.
	perspective_extents_overlay.add_child(polygon)                                             # Add the fill to the active overlay.



# _add_perspective_extent_line: Adds one colored line segment to the projected-square overlay.
func _add_perspective_extent_line(start: Vector2, end: Vector2, color: Color, width: float) -> void: # Declare this function.
	var line := Line2D.new()                                                                    # Create a line primitive for the square guide.
	line.points = PackedVector2Array([start, end])                                             # Set the segment endpoints.
	line.width = width                                                                          # Set the line thickness.
	line.default_color = color                                                                  # Set the guide color.
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                                    # Keep the debug line crisp over pixel art.
	line.z_index = 1                                                                            # Draw outlines above translucent fills.
	perspective_extents_overlay.add_child(line)                                                 # Add the line to the active overlay.



# _add_perspective_actor_height_tick: Draws the measured actor height at one square edge center.
func _add_perspective_actor_height_tick(feet: Vector2, actor_height: float, color: Color) -> void: # Declare this function.
	var top := feet + Vector2(0.0, -actor_height)                                               # Compute the measured actor top from the feet line.
	var tick_color := Color(color.r, color.g, color.b, 1.0)                                     # Use an opaque version of the square color for height ticks.
	_add_perspective_extent_line(top, feet, tick_color, 1.0)                                    # Draw the vertical actor-height sample.
	_add_perspective_extent_line(top + Vector2(-3.0, 0.0), top + Vector2(3.0, 0.0), tick_color, 1.0) # Mark the measured top of the actor.
	_add_perspective_extent_line(feet + Vector2(-3.0, 0.0), feet + Vector2(3.0, 0.0), tick_color, 1.0) # Mark the measured feet line.



# _add_perspective_extent_label: Adds a small square-index label to the projected-square overlay.
func _add_perspective_extent_label(text: String, position: Vector2, color: Color) -> void:  # Declare this function.
	var label := Label.new()                                                                   # Create a compact text label for the guide square.
	label.text = text                                                                           # Set the square label text.
	label.add_theme_color_override("font_color", color)                                        # Tint the label to match the square color.
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))             # Add black shadow for readability over wall art.
	label.add_theme_constant_override("shadow_offset_x", 1)                                    # Offset the shadow one pixel right.
	label.add_theme_constant_override("shadow_offset_y", 1)                                    # Offset the shadow one pixel down.
	label.scale = Vector2(0.35, 0.35)                                                          # Keep the label small inside the 160x120 playfield.
	label.position = position + Vector2(-5.0, -5.0)                                            # Center the label around the guide position.
	label.z_index = 2                                                                           # Draw labels above fills and outlines.
	perspective_extents_overlay.add_child(label)                                                # Add the label to the active overlay.



# _add_perspective_sprite_bounds: Draws the actual projected sprite rectangle and feet point for debugging.
func _add_perspective_sprite_bounds(sprite: AnimatedSprite2D, color: Color, label_text: String) -> void: # Declare this function.
	if sprite == null or sprite.sprite_frames == null:                                         # Skip missing or uninitialized sprites.
		return                                                                                    # Return without drawing sprite diagnostics.
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)       # Read the current displayed frame texture.
	if texture == null:                                                                        # Skip sprites without an active frame.
		return                                                                                    # Return without drawing sprite diagnostics.
	var size := Vector2(float(texture.get_width()), float(texture.get_height())) * sprite.scale # Compute the current scaled sprite size in playfield pixels.
	var half := size * 0.5                                                                      # Compute half-size because AnimatedSprite2D is centered.
	var top_left := sprite.position - half                                                     # Compute the sprite rectangle top-left.
	var top_right := sprite.position + Vector2(half.x, -half.y)                                # Compute the sprite rectangle top-right.
	var bottom_left := sprite.position + Vector2(-half.x, half.y)                              # Compute the sprite rectangle bottom-left.
	var bottom_right := sprite.position + half                                                 # Compute the sprite rectangle bottom-right.
	var feet := sprite.position + Vector2(0.0, half.y)                                         # Compute the projected feet point from the centered sprite.
	_add_perspective_extent_line(top_left, top_right, color, 1.0)                              # Draw the sprite top edge.
	_add_perspective_extent_line(top_right, bottom_right, color, 1.0)                          # Draw the sprite right edge.
	_add_perspective_extent_line(bottom_left, bottom_right, color, 1.0)                        # Draw the sprite bottom edge.
	_add_perspective_extent_line(top_left, bottom_left, color, 1.0)                            # Draw the sprite left edge.
	_add_perspective_extent_line(feet + Vector2(-3.0, 0.0), feet + Vector2(3.0, 0.0), color, 1.0) # Draw the horizontal feet crossbar.
	_add_perspective_extent_line(feet + Vector2(0.0, -3.0), feet + Vector2(0.0, 3.0), color, 1.0) # Draw the vertical feet crossbar.
	_add_perspective_extent_label(label_text, feet + Vector2(4.0, -6.0), color)                # Label the sprite bounds marker.



# _setup_3d_diagnostic: Builds a 160x120 3D SubViewport that visualizes the same maze map beside the 2D renderer.
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



# _build_3d_hallway_geometry: Creates visible 3D floor, ceiling, and wall cubes from the thin-wall maze data.
func _build_3d_hallway_geometry() -> void:                                                  # Declare this function.
	var floor_material := _make_3d_material(Color(0.76, 0.49, 0.24, 1.0))                      # Create the diagnostic floor material.
	var ceiling_material := _make_3d_material(Color(0.52, 0.35, 0.18, 1.0))                    # Create the diagnostic ceiling material.
	var wall_material := _make_3d_material(Color(0.34, 0.40, 0.76, 1.0))                       # Create the diagnostic side-wall material.
	var end_wall_material := _make_3d_material(Color(0.20, 0.25, 0.42, 1.0))                   # Create the diagnostic end-wall material.
	var separator_material := _make_3d_material(Color(0.02, 0.02, 0.02, 1.0))                  # Create a dark material for cell boundary guide strips.

	for y in range(MAP_HEIGHT):                                                               # Generate one row of 3D diagnostic cells for each maze row.
		for x in range(MAP_WIDTH):                                                              # Generate one 3D diagnostic cell for each maze column.
			var cell := Vector2i(x, y)                                                              # Build the current maze cell coordinate.
			var center := _grid_cell_center_to_3d(cell)                                             # Convert this cell center into 3D world space.
			_add_3d_box("Floor_%d_%d" % [x, y], center + Vector3(0.0, -0.025, 0.0), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, 0.05, 1.0), floor_material) # Add a thin floor slab for this widened cell.
			_add_3d_box("Ceiling_%d_%d" % [x, y], center + Vector3(0.0, DIAGNOSTIC_3D_WALL_HEIGHT, 0.0), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, 0.05, 1.0), ceiling_material) # Add a thin ceiling slab for this widened cell.
			if _has_wall_edge(cell, Vector2i(-1, 0)):                                                # Check the west edge for a thin wall.
				_add_3d_box("Wall_W_%d_%d" % [x, y], Vector3(float(x) * DIAGNOSTIC_3D_CELL_WIDTH - DIAGNOSTIC_3D_WALL_THICKNESS * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) + 0.5), Vector3(DIAGNOSTIC_3D_WALL_THICKNESS, DIAGNOSTIC_3D_WALL_HEIGHT, 1.0), wall_material) # Add a west wall segment.
			if _has_wall_edge(cell, Vector2i(1, 0)):                                                 # Check the east edge for a thin wall.
				_add_3d_box("Wall_E_%d_%d" % [x, y], Vector3(float(x + 1) * DIAGNOSTIC_3D_CELL_WIDTH + DIAGNOSTIC_3D_WALL_THICKNESS * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) + 0.5), Vector3(DIAGNOSTIC_3D_WALL_THICKNESS, DIAGNOSTIC_3D_WALL_HEIGHT, 1.0), wall_material) # Add an east wall segment.
			if _has_wall_edge(cell, Vector2i(0, -1)):                                                # Check the north edge for a thin wall.
				_add_3d_box("Wall_N_%d_%d" % [x, y], Vector3(float(x) * DIAGNOSTIC_3D_CELL_WIDTH + DIAGNOSTIC_3D_CELL_WIDTH * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) - DIAGNOSTIC_3D_WALL_THICKNESS * 0.5), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, DIAGNOSTIC_3D_WALL_HEIGHT, DIAGNOSTIC_3D_WALL_THICKNESS), end_wall_material) # Add a north wall segment.
			if _has_wall_edge(cell, Vector2i(0, 1)):                                                 # Check the south edge for a thin wall.
				_add_3d_box("Wall_S_%d_%d" % [x, y], Vector3(float(x) * DIAGNOSTIC_3D_CELL_WIDTH + DIAGNOSTIC_3D_CELL_WIDTH * 0.5, DIAGNOSTIC_3D_WALL_HEIGHT * 0.5, float(y) + 1.0 + DIAGNOSTIC_3D_WALL_THICKNESS * 0.5), Vector3(DIAGNOSTIC_3D_CELL_WIDTH, DIAGNOSTIC_3D_WALL_HEIGHT, DIAGNOSTIC_3D_WALL_THICKNESS), end_wall_material) # Add a south wall segment.
			_add_3d_box("FloorCenter_%d_%d" % [x, y], center + Vector3(0.0, 0.012, 0.0), Vector3(DIAGNOSTIC_3D_SEPARATOR_THICKNESS, DIAGNOSTIC_3D_SEPARATOR_THICKNESS, DIAGNOSTIC_3D_SEPARATOR_THICKNESS), separator_material) # Mark each diagnostic floor cell center.



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
	var status_margin := 84.0                                                                  # Reserve screen space for the three-line debug status text.
	var combined_size := Vector2(VIEWPORT_SIZE.x * 2.0 + SIDE_BY_SIDE_GUTTER, VIEWPORT_SIZE.y * 2.0 + SIDE_BY_SIDE_GUTTER) # Build a two-column, two-row source-pixel layout.
	var available_size := Vector2(viewport_size.x, maxf(viewport_size.y - status_margin, VIEWPORT_SIZE.y)) # Compute the window area available below the status label.
	var view_scale := minf(available_size.x / combined_size.x, available_size.y / combined_size.y) # Scale the full four-panel layout uniformly.
	var scaled_size := combined_size * view_scale                                               # Store mutable runtime state for assets, rendering, movement, or debug output.
	var layout_origin := Vector2((viewport_size.x - scaled_size.x) * 0.5, status_margin + (available_size.y - scaled_size.y) * 0.5) # Center the four panels below status.
	for player_index in range(player_views.size()):                                           # Layout each local player's top map and bottom playfield.
		var view: Dictionary = player_views[player_index]                                        # Read this player's view bundle.
		var column_x := layout_origin.x + float(player_index) * (VIEWPORT_SIZE.x + SIDE_BY_SIDE_GUTTER) * view_scale # Compute the panel column x coordinate.
		var map_node: Node2D = view.get("debug_map_overlay", null)                               # Read this player's top-down map node.
		var view_node: Node2D = view.get("maze_viewport", null)                                  # Read this player's playfield node.
		if map_node != null:                                                                      # Layout this player's debug map if it exists.
			map_node.visible = show_top_down_source_overlay                                         # Apply the map visibility toggle.
			map_node.scale = Vector2.ONE * view_scale                                               # Match the source-pixel scale of the playfield.
			map_node.position = Vector2(column_x, layout_origin.y)                                  # Place this player's map in the top row.
		if view_node != null:                                                                     # Layout this player's playfield if it exists.
			view_node.scale = Vector2.ONE * view_scale                                               # Match the source-pixel scale of the map.
			view_node.position = Vector2(column_x, layout_origin.y + (VIEWPORT_SIZE.y + SIDE_BY_SIDE_GUTTER) * view_scale) # Place this player's view in the bottom row.
	if enable_3d_diagnostic and diagnostic_3d_display != null:                                 # Only layout the 3D view after it has been created and enabled.
		diagnostic_3d_display.scale = Vector2.ONE * view_scale                                    # Scale the 3D viewport texture at the same pixel size as the 2D view.
		diagnostic_3d_display.position = layout_origin                                            # Keep the deprecated 3D panel parked on top of the first map when enabled.
		diagnostic_3d_display.visible = false                                                     # Keep the deprecated 3D panel hidden in the local two-player layout.
	elif diagnostic_3d_display != null:                                                        # Hide an existing 3D display if the toggle is turned off during a run.
		diagnostic_3d_display.visible = false                                                     # Keep the deprecated 3D panel out of the default prototype view.



# _setup_debug_map_overlay: Creates a runtime top-down map overlay for comparing map state to the rendered wall view.
func _setup_debug_map_overlay() -> void:                                                     # Declare this function.
	debug_map_overlay = Node2D.new()                                                           # Create the parent node for the top-down map lines and arrow.
	debug_map_overlay.name = "DebugTopDownMap"                                                 # Name the overlay node so it is easy to find in the scene tree.
	debug_map_overlay.z_index = 100                                                            # Draw the debug map above status and playfield art.
	canvas_layer.add_child(debug_map_overlay)                                                  # Attach the debug map to the UI canvas layer.
	_update_debug_map_overlay()                                                                # Draw the first version immediately after setup.



# _update_debug_map_overlay: Redraws the top-down maze, thin-wall edges, player cell, and facing arrow.
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

	for y in range(MAP_HEIGHT):                                                               # Draw every row in the generated 4x4 maze.
		for x in range(MAP_WIDTH):                                                              # Draw every column in the generated 4x4 maze.
			var cell := Vector2i(x, y)                                                              # Build the map cell coordinate for this maze cell.
			var top_left := _debug_map_cell_top_left(cell)                                         # Convert the map cell to overlay pixel coordinates.
			var top_right := top_left + Vector2(DEBUG_MAP_CELL_SIZE, 0.0)                          # Compute the top-right corner of the cell.
			var bottom_left := top_left + Vector2(0.0, DEBUG_MAP_CELL_SIZE)                        # Compute the bottom-left corner of the cell.
			var bottom_right := top_left + Vector2(DEBUG_MAP_CELL_SIZE, DEBUG_MAP_CELL_SIZE)       # Compute the bottom-right corner of the cell.
			_add_debug_line(top_left, top_right, open_color, 1.0)                                  # Draw the north guide edge for this cell.
			_add_debug_line(top_right, bottom_right, open_color, 1.0)                              # Draw the east guide edge for this cell.
			_add_debug_line(bottom_left, bottom_right, open_color, 1.0)                            # Draw the south guide edge for this cell.
			_add_debug_line(top_left, bottom_left, open_color, 1.0)                                # Draw the west guide edge for this cell.
			if _has_wall_edge(cell, Vector2i(0, -1)):                                              # Check whether the north edge is blocked by a thin wall.
				_add_debug_line(top_left, top_right, wall_color, 3.0)                                 # Draw the north wall edge as a thick line.
			if _has_wall_edge(cell, Vector2i(1, 0)):                                               # Check whether the east edge is blocked by a thin wall.
				_add_debug_line(top_right, bottom_right, wall_color, 3.0)                             # Draw the east wall edge as a thick line.
			if _has_wall_edge(cell, Vector2i(0, 1)):                                               # Check whether the south edge is blocked by a thin wall.
				_add_debug_line(bottom_left, bottom_right, wall_color, 3.0)                           # Draw the south wall edge as a thick line.
			if _has_wall_edge(cell, Vector2i(-1, 0)):                                              # Check whether the west edge is blocked by a thin wall.
				_add_debug_line(top_left, bottom_left, wall_color, 3.0)                                # Draw the west wall edge as a thick line.

	var home_center := _debug_map_cell_center(grid_position)                                    # Convert the current cell center into an overlay reference position.
	var player_center := _debug_map_player_position()                                           # Convert the actual intra-cell player offset into overlay coordinates.
	var camera_center := _debug_map_world_position(_camera_grid_origin())                        # Convert the actual visibility-camera origin into overlay coordinates.
	_add_debug_view_cone(camera_center)                                                         # Draw the camera/view cone from the same backed-up origin used by ray casting.
	_add_debug_visible_wall_slots()                                                            # Highlight the wall slots selected by the renderer on the source map.
	_add_debug_player_bounds(home_center)                                                       # Draw the playable/contact footprint inside the current cell.
	_add_debug_player_marker(home_center, Color(1.0, 1.0, 1.0, 0.35))                           # Draw a faint marker at the home center for offset comparison.
	var facing_end := player_center + Vector2(_facing_vector()) * (DEBUG_MAP_CELL_SIZE * 0.34)  # Compute the arrow tip from the actual current player position.
	_add_debug_line(player_center, facing_end, player_color, 3.0)                               # Draw the player facing arrow shaft.
	_add_debug_arrow_head(facing_end, Vector2(_facing_vector()), player_color)                  # Draw the player facing arrow head.
	_add_debug_player_marker(player_center, player_color)                                      # Draw the player position marker.
	_add_debug_other_player_markers()                                                          # Draw the other local player on this player's top-down map.



# _debug_map_cell_top_left: Converts a grid cell coordinate into a debug overlay top-left pixel position.
func _debug_map_cell_top_left(cell: Vector2i) -> Vector2:                                    # Declare this function.
	return DEBUG_MAP_PANEL_GRID_ORIGIN + Vector2(float(cell.x) * DEBUG_MAP_CELL_SIZE, float(cell.y) * DEBUG_MAP_CELL_SIZE) # Return the cell's top-left panel coordinate.



# _debug_map_cell_center: Converts a grid cell coordinate into a debug overlay center pixel position.
func _debug_map_cell_center(cell: Vector2i) -> Vector2:                                      # Declare this function.
	return _debug_map_cell_top_left(cell) + Vector2.ONE * (DEBUG_MAP_CELL_SIZE * 0.5)          # Return the center of this cell on the debug overlay.



# _debug_map_world_position: Converts a world-grid coordinate into a debug overlay pixel position.
func _debug_map_world_position(world_position: Vector2) -> Vector2:                          # Declare this function.
	return DEBUG_MAP_PANEL_GRID_ORIGIN + world_position * DEBUG_MAP_CELL_SIZE                  # Scale grid units into the top-down panel coordinate system.



# _debug_map_player_position: Converts the real player cell plus local offset into a top-down overlay point.
func _debug_map_player_position() -> Vector2:                                               # Declare this function.
	var local_offset := _local_position_to_tile_offset(local_floor_position)                   # Convert art-space position into right/forward tile offset.
	var world_offset := Vector2(-_left_vector()) * local_offset.x + Vector2(_facing_vector()) * local_offset.y # Rotate the local offset into world grid axes.
	return _debug_map_cell_center(grid_position) + world_offset * (DEBUG_MAP_CELL_SIZE * LOCAL_TILE_WORLD_HALF_EXTENT) # Return the overlay coordinate for the true intra-cell player position.



# _add_debug_view_cone: Draws the cell-locked camera cone on top of the source-of-truth map.
func _add_debug_view_cone(origin: Vector2) -> void:                                        # Declare this function.
	var cone_color := Color(0.0, 0.75, 1.0, 0.22)                                            # Use translucent cyan for the cone fill.
	var cone_line_color := Color(0.0, 0.95, 1.0, 0.75)                                       # Use brighter cyan for the cone boundary lines.
	var forward := Vector2(_facing_vector())                                                  # Convert the current camera-facing grid direction to overlay space.
	var left := Vector2(_left_vector())                                                       # Convert camera-left to overlay space.
	var far_center := origin + forward * (DEBUG_MAP_CELL_SIZE * DEBUG_VIEW_CONE_DEPTH)        # Compute the center of the far end of the view cone.
	var far_left := far_center + left * (DEBUG_MAP_CELL_SIZE * DEBUG_VIEW_CONE_HALF_WIDTH)    # Compute the left boundary point at the far end of the cone.
	var far_right := far_center - left * (DEBUG_MAP_CELL_SIZE * DEBUG_VIEW_CONE_HALF_WIDTH)   # Compute the right boundary point at the far end of the cone.
	var cone := Polygon2D.new()                                                               # Create a filled triangle for the view cone area.
	cone.polygon = PackedVector2Array([origin, far_left, far_right])                          # Define the triangle from camera origin to far left/right limits.
	cone.color = cone_color                                                                   # Tint the cone fill without hiding the wall map.
	cone.z_index = -1                                                                         # Draw the cone above the panel background but below wall highlights.
	debug_map_overlay.add_child(cone)                                                         # Add the cone fill to the top-down overlay.
	_add_debug_line(origin, far_left, cone_line_color, 1.0)                                   # Draw the left cone boundary line.
	_add_debug_line(origin, far_right, cone_line_color, 1.0)                                  # Draw the right cone boundary line.
	_add_debug_line(origin, far_center, cone_line_color, 1.0)                                 # Draw the center sightline for camera-facing reference.



# _add_debug_visible_wall_slots: Highlights the renderer-selected wall slots as green edge segments on the top-down map.
func _add_debug_visible_wall_slots() -> void:                                               # Declare this function.
	var highlight_color := Color(0.0, 1.0, 0.25, 0.95)                                       # Use green to mark wall slots that the renderer currently selected.
	var visible_slots := _build_straight_render_list()                                       # Rebuild the same ray-constrained visible-slot list used by the 2D renderer.
	var labeled_segments := {}                                                                # Track label positions so repeated physical edges do not stack identical labels.
	for slot in visible_slots:                                                                # Iterate through every wall slot currently selected for drawing.
		var wall_id := int(slot["id"])                                                          # Read the numbered 2D wall-slot id.
		var segment := _debug_wall_slot_segment(slot)                                           # Convert the selected wall slot into a top-down source-map edge.
		if segment.size() < 2:                                                                  # Skip invalid slot metadata defensively.
			continue                                                                               # Continue to the next ray-hit wall edge.
		_add_debug_line(segment[0], segment[1], highlight_color, 5.0)                            # Draw the selected physical wall segment in green.
		var label_position := (segment[0] + segment[1]) * 0.5                                    # Place the label at the center of the highlighted edge.
		var segment_key := "%d,%d" % [int(round(label_position.x)), int(round(label_position.y))] # Build a coarse key for stacking labels on the same edge.
		var label_offset := float(labeled_segments.get(segment_key, 0)) * 7.0                    # Offset repeated labels so companion slots remain readable.
		labeled_segments[segment_key] = int(labeled_segments.get(segment_key, 0)) + 1            # Store that another label used this edge midpoint.
		_add_debug_wall_slot_label(label_position + Vector2(0.0, label_offset), wall_id, highlight_color) # Add the wall-slot number beside the green segment.



# _debug_physical_wall_edge_segment: Converts a ray-hit physical wall edge into top-down overlay points.
func _debug_physical_wall_edge_segment(edge: Dictionary) -> Array[Vector2]:                 # Declare this function.
	if not edge.has("a") or not edge.has("b"):                                                # Require both physical wall endpoints.
		return []                                                                               # Return no segment when edge metadata is incomplete.
	return [_debug_map_world_position(edge["a"]), _debug_map_world_position(edge["b"])]        # Convert physical grid endpoints into debug-map pixel coordinates.



# _debug_wall_slot_segment: Converts a visible 2D wall slot into its corresponding source-map edge segment.
func _debug_wall_slot_segment(slot: Dictionary) -> Array[Vector2]:                          # Declare this function.
	var lateral := int(slot["lateral"])                                                       # Read the view-relative lateral slot coordinate.
	var depth := int(slot["depth"])                                                           # Read the view-relative depth slot coordinate.
	var edge := String(slot["edge"])                                                          # Read which face of the view-relative cell this slot represents.
	var cell := _view_cell(lateral, depth)                                                    # Convert the view-relative slot coordinate into a world-grid cell.
	match edge:                                                                               # Convert the slot's face type into a world-grid edge vector.
		VIEW_FRONT:                                                                              # Handle front-facing wall slots.
			return _debug_cell_edge_segment(cell, _facing_vector())                                # Return the front edge of the slot's cell.
		VIEW_LEFT:                                                                               # Handle camera-left wall slots.
			return _debug_cell_edge_segment(cell, _left_vector())                                  # Return the left edge of the slot's cell.
		VIEW_RIGHT:                                                                              # Handle camera-right wall slots.
			return _debug_cell_edge_segment(cell, -_left_vector())                                 # Return the right edge of the slot's cell.
		_:                                                                                       # Handle unknown slot metadata defensively.
			return []                                                                               # Return no segment for invalid metadata.



# _debug_cell_edge_segment: Converts one cell edge into two top-down overlay points.
func _debug_cell_edge_segment(cell: Vector2i, delta: Vector2i) -> Array[Vector2]:           # Declare this function.
	var top_left := _debug_map_cell_top_left(cell)                                            # Convert the cell to the top-left corner of its debug-map square.
	var top_right := top_left + Vector2(DEBUG_MAP_CELL_SIZE, 0.0)                             # Compute the top-right corner of the cell.
	var bottom_left := top_left + Vector2(0.0, DEBUG_MAP_CELL_SIZE)                           # Compute the bottom-left corner of the cell.
	var bottom_right := top_left + Vector2(DEBUG_MAP_CELL_SIZE, DEBUG_MAP_CELL_SIZE)          # Compute the bottom-right corner of the cell.
	if delta == Vector2i(0, -1):                                                              # Handle the north edge.
		return [top_left, top_right]                                                            # Return the north edge segment.
	if delta == Vector2i(1, 0):                                                               # Handle the east edge.
		return [top_right, bottom_right]                                                        # Return the east edge segment.
	if delta == Vector2i(0, 1):                                                               # Handle the south edge.
		return [bottom_left, bottom_right]                                                      # Return the south edge segment.
	if delta == Vector2i(-1, 0):                                                              # Handle the west edge.
		return [top_left, bottom_left]                                                          # Return the west edge segment.
	return []                                                                                 # Return no segment for invalid edge vectors.



# _add_debug_wall_slot_label: Adds a green wall-slot number to the top-down debug map.
func _add_debug_wall_slot_label(position: Vector2, wall_id: int, color: Color) -> void:      # Declare this function.
	var label := Label.new()                                                                   # Create a small 2D label for the top-down wall-slot number.
	label.text = "%02d" % wall_id                                                              # Match the two-digit wall labels shown on the player view.
	label.add_theme_color_override("font_color", color)                                       # Use the same green as the highlighted wall segment.
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))            # Add a black shadow so the label reads on white walls.
	label.add_theme_constant_override("shadow_offset_x", 1)                                   # Offset the label shadow one pixel right.
	label.add_theme_constant_override("shadow_offset_y", 1)                                   # Offset the label shadow one pixel down.
	label.scale = Vector2(0.32, 0.32)                                                         # Keep the debug label compact inside the 160x120 map panel.
	label.position = position + Vector2(-4.0, -4.0)                                           # Center the small label around the requested point.
	debug_map_overlay.add_child(label)                                                        # Add the wall-slot label to the top-down overlay.



# _add_debug_player_bounds: Draws the current cell's source-of-truth movement/contact footprint.
func _add_debug_player_bounds(center: Vector2) -> void:                                     # Declare this function.
	var bounds_color := Color(0.0, 0.95, 1.0, 0.35)                                           # Use translucent cyan for the reachable local-position area.
	var half_extent := DEBUG_MAP_CELL_SIZE * LOCAL_TILE_WORLD_HALF_EXTENT                                             # Match the debug player's normalized -1..1 movement span.
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



# _add_debug_other_player_markers: Draws the non-bound local player on the currently bound player's source map.
func _add_debug_other_player_markers() -> void:                                             # Declare this function.
	var other_color := Color(1.0, 0.0, 0.85, 0.9)                                             # Use magenta so the opponent marker differs from the cyan self marker.
	for player_index in range(player_states.size()):                                          # Check every known local player.
		if player_index == active_player_index:                                                  # Skip the player whose map is currently being drawn.
			continue                                                                                 # Continue to the next player state.
		var other_state := _effective_player_state(player_index)                                  # Read the newest available state for this other player.
		if other_state.is_empty():                                                                # Skip missing player state defensively.
			continue                                                                                 # Continue to the next player state.
		var other_center := _debug_map_world_position(_player_state_world_position(other_state))    # Convert the other player's physical position to map pixels.
		var facing_end := other_center + Vector2(_facing_vector_for_index(int(other_state.get("facing", 0)))) * (DEBUG_MAP_CELL_SIZE * 0.26) # Compute the other player's facing arrow tip.
		_add_debug_line(other_center, facing_end, other_color, 2.0)                                # Draw the other player's facing arrow shaft.
		_add_debug_arrow_head(facing_end, Vector2(_facing_vector_for_index(int(other_state.get("facing", 0)))), other_color) # Draw the other player's facing arrow head.
		_add_debug_player_marker(other_center, other_color)                                        # Draw the other player's marker body.



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



# _build_straight_render_list: Casts the top-down view fan, maps ray-hit physical edges to Xybots wall slots, and returns those slots.
func _build_straight_render_list() -> Array:                                                # Declare this function.
	var render_list := []                                                                      # Store the visible straight-wall slots selected by ray hits.
	var emitted_ids := {}                                                                      # Track wall ids already added so shared branch entries draw only once.
	var physical_edges := _visible_physical_wall_edges()                                       # Collect wall edges visible from the current cell-locked camera fan.
	var visible_keys := {}                                                                     # Store canonical keys for physical edges hit by the ray fan.
	for edge in physical_edges:                                                                # Iterate through every physical wall edge the ray fan can see.
		visible_keys[String(edge["key"])] = true                                                 # Mark this source-map edge as visible.
	for slot in STRAIGHT_WALL_SLOTS:                                                          # Check every numbered slot footprint against the ray-hit edge set.
		var wall_id := int(slot["id"])                                                           # Read this numbered wall slot id.
		var key := _physical_edge_key_for_wall_slot(slot)                                         # Compute the physical edge key controlled by this numbered slot.
		if key == "" or not visible_keys.has(key):                                                # Skip slot footprints whose physical edge was not ray-visible.
			continue                                                                                 # Continue to the next slot.
		_append_wall_slot_unchecked(render_list, emitted_ids, wall_id)                            # Add this specific visible slot.
	render_list.sort_custom(func(a, b): return int(a["draw"]) < int(b["draw"]))                # Sort by existing art draw order so near pieces paint over far pieces.
	return render_list                                                                         # Return the final wall-slot list to the renderer.



# _visible_physical_wall_edges: Finds physical wall segments that are first-hit by rays in the current top-down view fan.
func _visible_physical_wall_edges() -> Array:                                               # Declare this function.
	var all_edges := _all_physical_wall_edges()                                                # Gather unique wall segments from the thin-wall map.
	var visible_by_key := {}                                                                   # Store the nearest-hit wall segments by canonical edge key.
	var origin := _camera_grid_origin()                                                        # Use the center of the current cell as the cell-locked camera origin.
	var forward := Vector2(_facing_vector()).normalized()                                      # Convert the current facing direction into a world-space vector.
	var right := Vector2(-_left_vector()).normalized()                                         # Convert camera-right into a world-space vector.
	for ray_index in range(VISIBILITY_RAY_COUNT):                                             # Cast a fixed fan of rays across the view cone.
		var ratio := 0.0 if VISIBILITY_RAY_COUNT == 1 else float(ray_index) / float(VISIBILITY_RAY_COUNT - 1) # Convert ray index to 0..1 across the fan.
		var angle := deg_to_rad(lerpf(-VISIBILITY_RAY_HALF_ANGLE_DEGREES, VISIBILITY_RAY_HALF_ANGLE_DEGREES, ratio)) # Convert this ray's fan angle to radians.
		var ray_direction := (forward * cos(angle) + right * sin(angle)).normalized()             # Rotate the ray around the forward vector inside the top-down plane.
		var best_hit := {}                                                                        # Track the closest wall edge hit by this ray.
		var best_distance := VISIBILITY_MAX_DISTANCE                                              # Start with the farthest allowable hit distance.
		for edge in all_edges:                                                                    # Test this ray against every physical wall edge.
			var distance := _ray_segment_hit_distance(origin, ray_direction, edge["a"], edge["b"])   # Compute the distance to this edge if the ray intersects it.
			if distance >= 0.0 and distance < best_distance:                                         # Keep the closest positive hit along the ray.
				best_distance = distance                                                               # Store the nearest hit distance.
				best_hit = edge                                                                        # Store the nearest hit edge.
		if not best_hit.is_empty():                                                               # Add the ray's nearest wall edge if it hit one.
			best_hit["distance"] = best_distance                                                    # Store the hit distance for draw ordering and diagnostics.
			visible_by_key[String(best_hit["key"])] = best_hit                                      # Mark this physical edge as visible from at least one ray.
	var visible_edges := []                                                                    # Convert the keyed dictionary back into an ordered array.
	for edge in visible_by_key.values():                                                       # Iterate through unique visible physical edges.
		visible_edges.append(edge)                                                               # Add the visible edge to the result array.
	return visible_edges                                                                       # Return all visible physical wall segments.



# _all_physical_wall_edges: Returns every unique blocking wall edge in world-grid coordinates.
func _all_physical_wall_edges() -> Array:                                                   # Declare this function.
	var edges := []                                                                            # Store unique physical wall segments.
	var emitted_keys := {}                                                                     # Track canonical endpoint keys so shared walls are emitted once.
	for y in range(MAP_HEIGHT):                                                                # Iterate through each map row.
		for x in range(MAP_WIDTH):                                                               # Iterate through each map column.
			var cell := Vector2i(x, y)                                                              # Build the current map cell coordinate.
			for delta in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:       # Check all four thin-wall edges.
				if not _has_wall_edge(cell, delta):                                                   # Skip open edges.
					continue                                                                              # Continue to the next edge.
				var segment := _physical_cell_edge_segment(cell, delta)                               # Convert this map edge to world-space endpoints.
				var key := _physical_edge_key(segment[0], segment[1])                                  # Build a stable key independent of which cell reported the edge.
				if emitted_keys.has(key):                                                             # Skip duplicate shared walls.
					continue                                                                              # Continue to the next edge.
				emitted_keys[key] = true                                                              # Mark this physical edge as emitted.
				edges.append({"a": segment[0], "b": segment[1], "delta": delta, "key": key})          # Store this unique wall edge and its source orientation.
	return edges                                                                              # Return the full physical wall edge list.



# _physical_cell_edge_segment: Converts a cell edge into two world-grid endpoint coordinates.
func _physical_cell_edge_segment(cell: Vector2i, delta: Vector2i) -> Array[Vector2]:        # Declare this function.
	var x := float(cell.x)                                                                     # Convert the cell x coordinate into world-grid units.
	var y := float(cell.y)                                                                     # Convert the cell y coordinate into world-grid units.
	if delta == Vector2i(0, -1):                                                              # Handle the north edge.
		return [Vector2(x, y), Vector2(x + 1.0, y)]                                             # Return the north wall segment.
	if delta == Vector2i(1, 0):                                                               # Handle the east edge.
		return [Vector2(x + 1.0, y), Vector2(x + 1.0, y + 1.0)]                                 # Return the east wall segment.
	if delta == Vector2i(0, 1):                                                               # Handle the south edge.
		return [Vector2(x, y + 1.0), Vector2(x + 1.0, y + 1.0)]                                 # Return the south wall segment.
	if delta == Vector2i(-1, 0):                                                              # Handle the west edge.
		return [Vector2(x, y), Vector2(x, y + 1.0)]                                             # Return the west wall segment.
	return []                                                                                 # Return no segment for invalid edge vectors.



# _physical_edge_key: Builds a canonical string key for a wall segment regardless of endpoint order.
func _physical_edge_key(a: Vector2, b: Vector2) -> String:                                  # Declare this function.
	var first := a                                                                             # Store one endpoint for ordering.
	var second := b                                                                            # Store the other endpoint for ordering.
	if first.x > second.x or (is_equal_approx(first.x, second.x) and first.y > second.y):      # Ensure the key is stable when endpoints are reversed.
		first = b                                                                                # Swap the first endpoint.
		second = a                                                                               # Swap the second endpoint.
	return "%.2f,%.2f:%.2f,%.2f" % [first.x, first.y, second.x, second.y]                      # Return a compact coordinate key.



# _physical_edge_key_for_wall_slot: Returns the physical map-edge key controlled by one numbered wall slot.
func _physical_edge_key_for_wall_slot(slot: Dictionary) -> String:                          # Declare this function.
	var segment := _physical_wall_slot_segment(slot)                                          # Convert this numbered slot into a physical grid edge.
	if segment.size() < 2:                                                                    # Skip invalid slot metadata defensively.
		return ""                                                                                # Return no key for invalid slots.
	return _physical_edge_key(segment[0], segment[1])                                         # Return the canonical physical edge key for this slot footprint.



# _physical_wall_slot_segment: Converts a numbered wall slot into its source physical map edge.
func _physical_wall_slot_segment(slot: Dictionary) -> Array[Vector2]:                       # Declare this function.
	var lateral := int(slot["lateral"])                                                       # Read the view-relative lateral slot coordinate.
	var depth := int(slot["depth"])                                                           # Read the view-relative depth slot coordinate.
	var edge := String(slot["edge"])                                                          # Read which face of the view-relative cell controls this slot.
	var cell := _view_cell(lateral, depth)                                                    # Convert the view-relative slot coordinate into a world-grid cell.
	match edge:                                                                               # Convert the slot's face type into a world-grid edge vector.
		VIEW_FRONT:                                                                              # Handle front-facing wall slots.
			return _physical_cell_edge_segment(cell, _facing_vector())                              # Return the front edge of this slot cell.
		VIEW_LEFT:                                                                               # Handle camera-left wall slots.
			return _physical_cell_edge_segment(cell, _left_vector())                                # Return the left edge of this slot cell.
		VIEW_RIGHT:                                                                              # Handle camera-right wall slots.
			return _physical_cell_edge_segment(cell, -_left_vector())                               # Return the right edge of this slot cell.
		_:                                                                                       # Handle unknown slot metadata defensively.
			return []                                                                               # Return no segment for invalid metadata.



# _ray_segment_hit_distance: Returns the positive ray distance to a segment, or -1 when there is no hit.
func _ray_segment_hit_distance(origin: Vector2, ray_direction: Vector2, a: Vector2, b: Vector2) -> float: # Declare this function.
	var segment_vector := b - a                                                                # Compute the wall segment direction.
	var denominator := _cross2(ray_direction, segment_vector)                                  # Compute the 2D line-intersection denominator.
	if absf(denominator) < 0.0001:                                                            # Treat nearly parallel ray/segment pairs as no hit.
		return -1.0                                                                              # Return no hit for parallel geometry.
	var offset := a - origin                                                                   # Compute the vector from ray origin to segment start.
	var ray_t := _cross2(offset, segment_vector) / denominator                                 # Compute distance along the ray.
	var segment_t := _cross2(offset, ray_direction) / denominator                              # Compute normalized position along the segment.
	if ray_t < 0.0 or ray_t > VISIBILITY_MAX_DISTANCE:                                        # Reject hits behind the camera or beyond the straight-view distance.
		return -1.0                                                                              # Return no hit outside the usable ray range.
	if segment_t < 0.0 or segment_t > 1.0:                                                     # Reject intersections outside the wall segment endpoints.
		return -1.0                                                                              # Return no hit outside the segment.
	return ray_t                                                                               # Return the valid ray hit distance.



# _cross2: Computes the scalar 2D cross product.
func _cross2(a: Vector2, b: Vector2) -> float:                                              # Declare this function.
	return a.x * b.y - a.y * b.x                                                              # Return the 2D cross-product scalar.



# _camera_grid_origin: Returns the fixed camera origin for visibility tests in world-grid coordinates.
func _camera_grid_origin() -> Vector2:                                                      # Declare this function.
	var cell_center := Vector2(float(grid_position.x) + 0.5, float(grid_position.y) + 0.5)     # Compute the rotation center of the current grid cell.
	var forward := Vector2(_facing_vector()).normalized()                                     # Convert the current facing into a world-grid direction.
	return cell_center - forward * CAMERA_REAR_OFFSET                                         # Return the rear-biased camera point just inside the wall behind the viewer.



# _wall_slot_ids_for_physical_edge: Maps one physically visible wall segment to the numbered straight-view sprite slots.
func _wall_slot_ids_for_physical_edge(edge: Dictionary) -> Array[int]:                      # Declare this function.
	var a: Vector2 = edge["a"]                                                                 # Read the first physical wall endpoint.
	var b: Vector2 = edge["b"]                                                                 # Read the second physical wall endpoint.
	var center := (a + b) * 0.5                                                                # Compute the wall segment midpoint for camera-relative mapping.
	var segment_direction := (b - a).normalized()                                             # Compute the wall segment orientation.
	var origin := _camera_grid_origin()                                                       # Use the same cell-locked camera origin as ray casting.
	var forward := Vector2(_facing_vector()).normalized()                                     # Convert camera-forward to world-grid space.
	var right := Vector2(-_left_vector()).normalized()                                        # Convert camera-right to world-grid space.
	var to_center := center - origin                                                          # Compute the wall midpoint relative to the camera.
	var depth := to_center.dot(forward)                                                       # Measure how far forward this wall segment is.
	var side := to_center.dot(right)                                                          # Measure how far camera-right this wall segment is.
	if absf(segment_direction.dot(right)) > 0.9:                                              # Front walls run left/right across the camera view.
		return _front_wall_slot_ids_for_depth(depth, side)                                      # Map a front-facing wall segment to its depth family.
	if absf(segment_direction.dot(forward)) > 0.9:                                            # Side walls run along the camera depth axis.
		return _side_wall_slot_ids_for_depth(depth, side)                                       # Map a side-wall segment to its depth family.
	return []                                                                                 # Return no slots for invalid or diagonal wall data.



# _front_wall_slot_ids_for_depth: Returns the front-wall sprite ids for a camera-relative front wall.
func _front_wall_slot_ids_for_depth(depth: float, side: float) -> Array[int]:                # Declare this function.
	var depth_index := int(round(depth - 0.5))                                                # Convert front-edge midpoint depth into the Xybots slot depth row.
	var lateral_index := int(round(side))                                                     # Convert side offset into the nearest slot lane.
	if abs(lateral_index) > 1:                                                                # Ignore front walls that are too far outside the straight-view art fan.
		return []                                                                               # Return no slots for out-of-fan front walls.
	match depth_index:                                                                        # Choose the front-wall slot family by depth.
		0:                                                                                       # Handle an immediate front wall.
			if lateral_index < 0:                                                                  # Handle a front wall offset to the viewer's left.
				return [24]                                                                           # Return the left near front slice.
			if lateral_index > 0:                                                                  # Handle a front wall offset to the viewer's right.
				return [26]                                                                           # Return the right near front slice.
			return [24, 25, 26]                                                                    # Return the full immediate front wall family.
		1:                                                                                       # Handle a front wall one cell ahead.
			if lateral_index < 0:                                                                  # Handle a depth-one wall offset left.
				return [19]                                                                           # Return the left depth-one front slice.
			if lateral_index > 0:                                                                  # Handle a depth-one wall offset right.
				return [21]                                                                           # Return the right depth-one front slice.
			return [19, 20, 21]                                                                    # Return the full depth-one front wall family.
		2:                                                                                       # Handle a front wall two cells ahead.
			if lateral_index < 0:                                                                  # Handle a depth-two wall offset left.
				return [11]                                                                           # Return the left depth-two front slice.
			if lateral_index > 0:                                                                  # Handle a depth-two wall offset right.
				return [13]                                                                           # Return the right depth-two front slice.
			return [11, 12, 13]                                                                    # Return the full depth-two front wall family.
		3:                                                                                       # Handle a front wall three cells ahead.
			if lateral_index < 0:                                                                  # Handle a depth-three wall offset left.
				return [3]                                                                            # Return the left depth-three front slice.
			if lateral_index > 0:                                                                  # Handle a depth-three wall offset right.
				return [5]                                                                            # Return the right depth-three front slice.
			return [3, 4, 5]                                                                       # Return the full depth-three front wall family.
		_:                                                                                       # Ignore deeper front walls until more art mapping is verified.
			return []                                                                               # Return no slots for unsupported depths.



# _front_wall_ids_for_depth_index: Returns the full straight-view front-wall family for one corridor depth.
func _front_wall_ids_for_depth_index(depth_index: int) -> Array[int]:                       # Declare this function.
	match depth_index:                                                                        # Choose the front-wall family by center-corridor depth.
		0:                                                                                       # Handle the wall immediately in front of the current cell.
			return [24, 25, 26]                                                                    # Return the near full-front wall family.
		1:                                                                                       # Handle the wall one cell ahead.
			return [19, 20, 21]                                                                    # Return the next full-front wall family.
		2:                                                                                       # Handle the wall two cells ahead.
			return [11, 12, 13]                                                                    # Return the far full-front wall family.
		3:                                                                                       # Handle the wall three cells ahead.
			return [3, 4, 5]                                                                       # Return the deepest full-front wall family currently mapped.
		_:                                                                                       # Ignore unsupported far-depth walls.
			return []                                                                               # Return no wall ids.



# _left_side_wall_id_for_depth_index: Returns the viewer-left side-wall slot id for one corridor depth.
func _left_side_wall_id_for_depth_index(depth_index: int) -> int:                           # Declare this function.
	match depth_index:                                                                        # Map corridor depth to the left-side wall art sequence.
		0:                                                                                       # Handle the nearest left wall.
			return 27                                                                               # Return the immediate left wall sprite id.
		1:                                                                                       # Handle the next left wall.
			return 22                                                                               # Return the depth-one left wall sprite id.
		2:                                                                                       # Handle the middle left wall.
			return 16                                                                               # Return the depth-two left wall sprite id.
		3:                                                                                       # Handle the far left wall.
			return 7                                                                                # Return the depth-three left wall sprite id.
		4:                                                                                       # Handle the farthest left wall.
			return 6                                                                                # Return the depth-four left wall sprite id.
		_:                                                                                       # Ignore unsupported side-wall depths.
			return -1                                                                               # Return no wall id.



# _right_side_wall_id_for_depth_index: Returns the viewer-right side-wall slot id for one corridor depth.
func _right_side_wall_id_for_depth_index(depth_index: int) -> int:                          # Declare this function.
	match depth_index:                                                                        # Map corridor depth to the right-side wall art sequence.
		0:                                                                                       # Handle the nearest right wall.
			return 28                                                                               # Return the immediate right wall sprite id.
		1:                                                                                       # Handle the next right wall.
			return 23                                                                               # Return the depth-one right wall sprite id.
		2:                                                                                       # Handle the middle right wall.
			return 17                                                                               # Return the depth-two right wall sprite id.
		3:                                                                                       # Handle the far right wall.
			return 8                                                                                # Return the depth-three right wall sprite id.
		4:                                                                                       # Handle the farthest right wall.
			return 9                                                                                # Return the depth-four right wall sprite id.
		_:                                                                                       # Ignore unsupported side-wall depths.
			return -1                                                                               # Return no wall id.



# _side_wall_slot_ids_for_depth: Returns the side-wall sprite id for a camera-relative side wall.
func _side_wall_slot_ids_for_depth(depth: float, side: float) -> Array[int]:                 # Declare this function.
	var depth_index := int(round(depth))                                                      # Convert side-wall midpoint depth into the Xybots side-wall row.
	var viewer_left := side < 0.0                                                             # Negative camera-right offset means the wall is on the viewer's left.
	if viewer_left:                                                                           # Choose from the viewer-left side-wall sequence.
		match depth_index:                                                                       # Map left side-wall depth to a numbered sprite slot.
			0:                                                                                      # Handle the immediate left wall.
				return [27]                                                                          # Return the nearest left side-wall strip.
			1:                                                                                      # Handle the next left wall.
				return [22]                                                                          # Return the depth-one left side-wall strip.
			2:                                                                                      # Handle the middle left wall.
				return [16]                                                                          # Return the depth-two left side-wall strip.
			3:                                                                                      # Handle the far left wall.
				return [7]                                                                           # Return the depth-three left side-wall strip.
			4:                                                                                      # Handle the farthest left wall.
				return [6]                                                                           # Return the depth-four left side-wall strip.
			_:                                                                                      # Ignore unsupported side-wall depths.
				return []                                                                              # Return no slots.
	match depth_index:                                                                        # Map right side-wall depth to a numbered sprite slot.
		0:                                                                                       # Handle the immediate right wall.
			return [28]                                                                             # Return the nearest right side-wall strip.
		1:                                                                                       # Handle the next right wall.
			return [23]                                                                             # Return the depth-one right side-wall strip.
		2:                                                                                       # Handle the middle right wall.
			return [17]                                                                             # Return the depth-two right side-wall strip.
		3:                                                                                       # Handle the far right wall.
			return [8]                                                                              # Return the depth-three right side-wall strip.
		4:                                                                                       # Handle the farthest right wall.
			return [9]                                                                              # Return the depth-four right side-wall strip.
		_:                                                                                       # Ignore unsupported side-wall depths.
			return []                                                                               # Return no slots.



# _add_empirical_companion_wall_slots: Adds wall-art pieces that share another slot's map edge but need their own draw layer.
func _add_empirical_companion_wall_slots(render_list: Array, emitted_ids: Dictionary) -> void: # Declare this function.
	if emitted_ids.has(20):                                                                    # Detect the center slice of a front wall one cell ahead.
		_append_wall_slot_unchecked(render_list, emitted_ids, 19)                                 # Add the matching left slice of that front wall.
		_append_wall_slot_unchecked(render_list, emitted_ids, 21)                                 # Add the matching right slice of that front wall.
	if emitted_ids.has(12):                                                                    # Detect the center slice of a front wall two cells ahead.
		_append_wall_slot_unchecked(render_list, emitted_ids, 11)                                 # Add the matching left slice of that deeper front wall.
		_append_wall_slot_unchecked(render_list, emitted_ids, 13)                                 # Add the matching right slice of that deeper front wall.



# _append_wall_slot_unchecked: Adds one numbered slot without rerunning the map-edge visibility test.
func _append_wall_slot_unchecked(render_list: Array, emitted_ids: Dictionary, wall_id: int) -> void: # Declare this function.
	if emitted_ids.has(wall_id):                                                               # Avoid adding a duplicate slot when another branch already emitted it.
		return                                                                                    # Return without changing the render list.
	var slot := _straight_slot_by_id(wall_id)                                                   # Look up this wall id's texture and draw-order metadata.
	if slot.is_empty():                                                                        # Skip ids that are not in the straight-wall slot table.
		return                                                                                    # Return without changing the render list.
	render_list.append(slot)                                                                   # Add this empirically required companion wall to the render list.
	emitted_ids[wall_id] = true                                                                # Mark the wall id as emitted so later rules do not duplicate it.



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



# _ensure_input_actions: Creates runtime input actions for the prototype controls so manual keys and test input use the same path.
func _ensure_input_actions() -> void:                                                       # Declare this function.
	_ensure_key_action(ACTION_MOVE_LEFT, [KEY_A])                                             # Bind A to local strafe-left movement.
	_ensure_key_action(ACTION_MOVE_RIGHT, [KEY_D])                                            # Bind D to local strafe-right movement.
	_ensure_key_action(ACTION_MOVE_FORWARD, [KEY_W])                                          # Bind W to player-one local forward movement.
	_ensure_key_action(ACTION_MOVE_BACKWARD, [KEY_S])                                         # Bind S to player-one local backward movement.
	_ensure_key_action(ACTION_TURN_LEFT, [KEY_Q])                                             # Bind Q to player-one snapped left turns.
	_ensure_key_action(ACTION_TURN_RIGHT, [KEY_E])                                            # Bind E to player-one snapped right turns.
	_ensure_key_action(ACTION_REGENERATE_MAP, [KEY_R])                                        # Bind R to runtime maze regeneration.
	_ensure_key_action(ACTION_P2_MOVE_LEFT, [KEY_KP_4])                                       # Bind numpad 4 to player-two local strafe-left movement.
	_ensure_key_action(ACTION_P2_MOVE_RIGHT, [KEY_KP_6])                                      # Bind numpad 6 to player-two local strafe-right movement.
	_ensure_key_action(ACTION_P2_MOVE_FORWARD, [KEY_KP_8])                                    # Bind numpad 8 to player-two local forward movement.
	_ensure_key_action(ACTION_P2_MOVE_BACKWARD, [KEY_KP_5])                                   # Bind numpad 5 to player-two local backward movement.
	_ensure_key_action(ACTION_P2_TURN_LEFT, [KEY_KP_7])                                       # Bind numpad 7 to player-two snapped left turns.
	_ensure_key_action(ACTION_P2_TURN_RIGHT, [KEY_KP_9])                                      # Bind numpad 9 to player-two snapped right turns.



# _ensure_key_action: Adds one named InputMap action and any missing keyboard events for it.
func _ensure_key_action(action_name: String, keycodes: Array) -> void:                      # Declare this function.
	if not InputMap.has_action(action_name):                                                  # Check whether this prototype action is absent from the input map.
		InputMap.add_action(action_name)                                                         # Create the action at runtime when it is missing.
	for keycode in keycodes:                                                                  # Iterate over each requested keyboard binding.
		var keycode_int := int(keycode)                                                          # Normalize the keycode value for comparison.
		if _action_has_keycode(action_name, keycode_int):                                        # Skip bindings that are already present.
			continue                                                                                 # Continue to the next requested keycode.
		var event := InputEventKey.new()                                                         # Create a key event binding for this action.
		event.keycode = keycode_int                                                              # Assign the logical keyboard key to the event.
		InputMap.action_add_event(action_name, event)                                            # Add the key event to the named action.



# _action_has_keycode: Returns true when an input action already contains a matching key binding.
func _action_has_keycode(action_name: String, keycode: int) -> bool:                       # Declare this function.
	for event in InputMap.action_get_events(action_name):                                    # Inspect every event currently bound to the action.
		if event is InputEventKey and int(event.keycode) == keycode:                            # Match existing keyboard events by logical keycode.
			return true                                                                            # Report that this key binding already exists.
	return false                                                                               # Report that this key binding still needs to be added.



# _is_key_down: Checks the controller key cache and raw polling for one keyboard key.
func _is_key_down(keycode: int) -> bool:                                                    # Declare this function.
	if bool(held_keycodes.get(keycode, false)):                                               # Check whether this controller received and retained a pressed event.
		return true                                                                            # Report this key as down from the controller-owned cache.
	return Input.is_key_pressed(keycode)                                                      # Fall back to Godot's raw key polling for direct keyboard focus.



# _is_player_move_left_pressed: Returns whether the currently bound player is holding local-left movement.
func _is_player_move_left_pressed() -> bool:                                                # Declare this function.
	if active_player_index == 1:                                                              # Use number keys for player two.
		return Input.is_action_pressed(ACTION_P2_MOVE_LEFT) or _is_key_down(KEY_KP_4)          # Read player two's local-left input.
	return Input.is_action_pressed(ACTION_MOVE_LEFT) or _is_key_down(KEY_A)                   # Read player one's local-left input.



# _is_player_move_right_pressed: Returns whether the currently bound player is holding local-right movement.
func _is_player_move_right_pressed() -> bool:                                               # Declare this function.
	if active_player_index == 1:                                                              # Use number keys for player two.
		return Input.is_action_pressed(ACTION_P2_MOVE_RIGHT) or _is_key_down(KEY_KP_6)         # Read player two's local-right input.
	return Input.is_action_pressed(ACTION_MOVE_RIGHT) or _is_key_down(KEY_D)                  # Read player one's local-right input.



# _is_player_move_forward_pressed: Returns whether the currently bound player is holding local-forward movement.
func _is_player_move_forward_pressed() -> bool:                                             # Declare this function.
	if active_player_index == 1:                                                              # Use number keys for player two.
		return Input.is_action_pressed(ACTION_P2_MOVE_FORWARD) or _is_key_down(KEY_KP_8)       # Read player two's local-forward input.
	return Input.is_action_pressed(ACTION_MOVE_FORWARD) or _is_key_down(KEY_W)                 # Read player one's local-forward input.



# _is_player_move_backward_pressed: Returns whether the currently bound player is holding local-backward movement.
func _is_player_move_backward_pressed() -> bool:                                            # Declare this function.
	if active_player_index == 1:                                                              # Use number keys for player two.
		return Input.is_action_pressed(ACTION_P2_MOVE_BACKWARD) or _is_key_down(KEY_KP_5)      # Read player two's local-backward input.
	return Input.is_action_pressed(ACTION_MOVE_BACKWARD) or _is_key_down(KEY_S)                # Read player one's local-backward input.



# _is_player_turn_left_pressed: Returns whether the currently bound player is pressing a left-turn key.
func _is_player_turn_left_pressed() -> bool:                                                # Declare this function.
	if active_player_index == 1:                                                              # Use number keys for player two.
		return Input.is_action_pressed(ACTION_P2_TURN_LEFT) or _is_key_down(KEY_KP_7)          # Read player two's left-turn input.
	return Input.is_action_pressed(ACTION_TURN_LEFT) or _is_key_down(KEY_Q)                   # Read player one's left-turn input.



# _is_player_turn_right_pressed: Returns whether the currently bound player is pressing a right-turn key.
func _is_player_turn_right_pressed() -> bool:                                               # Declare this function.
	if active_player_index == 1:                                                              # Use number keys for player two.
		return Input.is_action_pressed(ACTION_P2_TURN_RIGHT) or _is_key_down(KEY_KP_9)         # Read player two's right-turn input.
	return Input.is_action_pressed(ACTION_TURN_RIGHT) or _is_key_down(KEY_E)                  # Read player one's right-turn input.



# _read_turn: Reads Q/E or arrow-key turning input and returns the requested turn direction.
func _read_turn() -> int:                                                                   # Declare this function.
	var left_pressed := _is_player_turn_left_pressed()                                        # Read the current left-turn key state for the bound player.
	var right_pressed := _is_player_turn_right_pressed()                                      # Read the current right-turn key state for the bound player.
	var left_just_pressed := left_pressed and not was_left_turn_pressed                        # Detect the first frame of a left-turn key press.
	var right_just_pressed := right_pressed and not was_right_turn_pressed                     # Detect the first frame of a right-turn key press.
	was_left_turn_pressed = left_pressed                                                      # Store current left-turn state for next frame.
	was_right_turn_pressed = right_pressed                                                    # Store current right-turn state for next frame.
	if left_just_pressed:                                                                      # Turn once per key press when phase animations are disabled.
		return -1                                                                                 # Return this computed result to the caller.
	if right_just_pressed:                                                                     # Turn once per key press when phase animations are disabled.
		return 1                                                                                  # Return this computed result to the caller.
	return 0                                                                                   # Return this computed result to the caller.



# _read_regenerate_map: Returns true once when the runtime random-map hotkey is pressed.
func _read_regenerate_map() -> bool:                                                        # Declare this function.
	var regenerate_pressed := Input.is_action_pressed(ACTION_REGENERATE_MAP) or _is_key_down(KEY_R) # Read the current map-regenerate key state.
	var regenerate_just_pressed := regenerate_pressed and not was_regenerate_map_pressed       # Detect the first frame of the regenerate key press.
	was_regenerate_map_pressed = regenerate_pressed                                           # Store current regenerate state for next frame.
	return regenerate_just_pressed                                                            # Return whether the hotkey should fire this frame.



# _read_movement: Reads WASD or arrow movement input and returns a normalized local movement vector.
func _read_movement() -> Vector2:                                                           # Declare this function.
	var movement := Vector2.ZERO                                                               # Store mutable runtime state for assets, rendering, movement, or debug output.
	if _is_player_move_left_pressed():                                                         # Read the bound player's local strafe-left input.
		movement.x -= 1.0                                                                         # Continue the controller logic for this section.
	if _is_player_move_right_pressed():                                                        # Read the bound player's local strafe-right input.
		movement.x += 1.0                                                                         # Continue the controller logic for this section.
	if _is_player_move_forward_pressed():                                                      # Read the bound player's local forward input.
		movement.y -= 1.0                                                                         # Continue the controller logic for this section.
	if _is_player_move_backward_pressed():                                                     # Read the bound player's local backward input.
		movement.y += 1.0                                                                         # Continue the controller logic for this section.
	return movement.normalized() if movement != Vector2.ZERO else Vector2.ZERO                 # Return this computed result to the caller.



# _move_inside_tile: Moves the player locally, crossing open edges at trigger thresholds and sliding to wall contact on blocked edges.
func _move_inside_tile(movement: Vector2, delta: float) -> void:                            # Declare this function.
	var physical_movement := Vector2(movement.x, -movement.y)                                  # Convert screen-local input into right/forward physical tile-offset movement.
	var tile_offset := _local_position_to_tile_offset(local_floor_position)                     # Convert current local art position into normalized physical tile offset.
	tile_offset += physical_movement * MOVE_UNITS_PER_SECOND * delta                           # Move in physical tile space so every direction uses the same ground speed.
	local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Convert the physical offset back into local art-space registration.

	if physical_movement.y > 0.0 and tile_offset.y >= 1.0:                                     # Handle crossing or blocking at the camera-forward physical edge.
		if _can_cross_edge(grid_position, _facing_vector()):                                      # Check whether the forward tile edge is open.
			tile_offset.y = 1.0                                                                       # Hold the physical offset at the forward edge during the transition.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the player on the matching local forward edge.
			_try_cross_tile("forward", _facing_vector(), "front")                                    # Start the forward tile-crossing transition.
			return                                                                                    # Stop before the stale pre-crossing offset can overwrite the new-cell entry point.
		else:                                                                                     # Handle a blocked front wall.
			tile_offset.y = 1.0                                                                       # Clamp the physical offset to the forward wall contact.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the blocked player at the forward wall contact.
			last_blocked_direction = "front"                                                         # Report the blocked front edge in the debug status.
	elif physical_movement.y < 0.0 and tile_offset.y <= -1.0:                                  # Handle crossing or blocking at the camera-back physical edge.
		if _can_cross_edge(grid_position, -_facing_vector()):                                     # Check whether the backward tile edge is open.
			tile_offset.y = -1.0                                                                      # Hold the physical offset at the back edge during the transition.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the player on the matching local back edge.
			_try_cross_tile("backward", -_facing_vector(), "back")                                   # Start the backward tile-crossing transition.
			return                                                                                    # Stop before the stale pre-crossing offset can overwrite the new-cell entry point.
		else:                                                                                     # Handle a blocked back wall.
			tile_offset.y = -1.0                                                                      # Clamp the physical offset to the back wall contact.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the blocked player at the back wall contact.
			last_blocked_direction = "back"                                                          # Report the blocked back edge in the debug status.
	elif physical_movement.x < 0.0 and tile_offset.x <= -1.0:                                  # Handle crossing or blocking at the camera-left physical edge.
		if _can_cross_edge(grid_position, _left_vector()):                                        # Check whether the camera-left tile edge is open.
			tile_offset.x = -1.0                                                                      # Hold the physical offset at the left edge during the transition.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the player on the matching local left edge.
			_try_cross_tile("strafe_left", _left_vector(), "left")                                   # Start the left strafe tile-crossing transition.
			return                                                                                    # Stop before the stale pre-crossing offset can overwrite the new-cell entry point.
		else:                                                                                     # Handle a blocked left wall.
			tile_offset.x = -1.0                                                                      # Clamp the physical offset to the left wall contact.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the blocked player at the left wall contact.
			last_blocked_direction = "left"                                                          # Report the blocked left edge in the debug status.
	elif physical_movement.x > 0.0 and tile_offset.x >= 1.0:                                   # Handle crossing or blocking at the camera-right physical edge.
		if _can_cross_edge(grid_position, -_left_vector()):                                       # Check whether the camera-right tile edge is open.
			tile_offset.x = 1.0                                                                       # Hold the physical offset at the right edge during the transition.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the player on the matching local right edge.
			_try_cross_tile("strafe_right", -_left_vector(), "right")                                # Start the right strafe tile-crossing transition.
			return                                                                                    # Stop before the stale pre-crossing offset can overwrite the new-cell entry point.
		else:                                                                                     # Handle a blocked right wall.
			tile_offset.x = 1.0                                                                       # Clamp the physical offset to the right wall contact.
			local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Register the blocked player at the right wall contact.
			last_blocked_direction = "right"                                                         # Report the blocked right edge in the debug status.

	if not is_transitioning:                                                                   # Keep free local movement bounded when no tile-crossing transition started.
		tile_offset = Vector2(clampf(tile_offset.x, -1.0, 1.0), clampf(tile_offset.y, -1.0, 1.0)) # Keep the physical offset inside this tile after free movement.
		local_floor_position = _tile_offset_to_local_position(tile_offset)                         # Convert the clamped physical offset back into local art-space registration.



# _try_cross_tile: Attempts to cross a map edge, starting the matching transition if the thin wall map allows it.
func _try_cross_tile(sequence_name: String, grid_delta: Vector2i, blocked_label: String) -> void: # Declare this function.
	if _can_cross_edge(grid_position, grid_delta):                                             # Run the following block only when this condition is true.
		pending_grid_delta = grid_delta                                                           # Compute and store this value for the current step.
		last_blocked_direction = ""                                                               # Compute and store this value for the current step.
		_request_transition(sequence_name)                                                         # Cross through a captured phase or immediate snap.
	else:                                                                                      # Run this fallback branch when previous conditions were not met.
		last_blocked_direction = blocked_label                                                    # Compute and store this value for the current step.



# _position_player: Projects the player local tile position into the 160x120 perspective floor trapezoid.
func _position_player() -> void:                                                            # Declare this function.
	var depth := clampf(local_floor_position.y, 0.0, 1.0)                                      # Store mutable runtime state for assets, rendering, movement, or debug output.
	var projection := _self_actor_projection_at_local_depth(depth)                              # Sample self-view feet from the true local position and scale from visible S0 space.
	var screen_ratio_x := _self_screen_side_ratio_for_projection(local_floor_position.x, projection) # Clamp only the rendered feet anchor inside the visible floor polygon.
	var screen_x := lerpf(float(projection["left_x"]), float(projection["right_x"]), screen_ratio_x) # Project side movement through the measured floor-zone trapezoid.
	var actor_height := float(projection["actor_height"])                                      # Read the measured character height for this depth.
	var sprite_scale := actor_height / _sprite_texture_height(player_sprite)                    # Scale the current frame so its body height matches the measured study.
	var screen_y := float(projection["feet_y"]) - actor_height * 0.5                            # Register centered sprites from the measured feet line.
	player_sprite.scale = Vector2.ONE * sprite_scale                                           # Update player sprite rendering or animation state.
	player_sprite.position = Vector2(screen_x, screen_y)                                       # Update player sprite rendering or animation state.
	player_sprite.z_index = LOCAL_CHARACTER_LAYER                                              # Keep the local body above wall art; the clipped viewport trims anything outside the camera frame.



# _position_opponent_sprite: Projects the other local player into the currently bound player's 2D screen.
func _position_opponent_sprite() -> void:                                                   # Declare this function.
	if opponent_sprite == null:                                                                # Skip when this view has no opponent sprite.
		return                                                                                    # Return without changing an opponent sprite.
	var other_state := _first_other_player_state()                                             # Read the other local player's latest state.
	if other_state.is_empty():                                                                 # Hide the sprite if there is no other player.
		opponent_sprite.visible = false                                                           # Hide the opponent sprite.
		return                                                                                    # Return without projecting anything.
	var target_world := _player_state_world_position(other_state)                               # Convert the opponent to world-grid coordinates.
	_apply_opponent_animation(other_state)                                                     # Choose the opponent animation before projection so sprite dimensions are current.
	var projection := _opponent_projection_from_current_camera(target_world)                    # Project the opponent through the current player's camera model.
	var screen_x := float(projection["screen_x"])                                               # Read the projected opponent x coordinate.
	var screen_y := float(projection["screen_y"])                                               # Read the projected opponent y coordinate.
	var actor_height := float(projection["actor_height"])                                      # Read the measured opponent body height at this depth.
	var sprite_scale := actor_height / _sprite_texture_height(opponent_sprite)                  # Scale the opponent from the same measured perspective table.
	var actor_half_width := _opponent_camera_side_margin_from_projection(projection, sprite_scale) # Convert the projected sprite half-width into camera-space fan overlap.
	if not _world_actor_overlaps_current_camera_fan(target_world, actor_half_width):            # Cull only after the whole opponent body leaves the fan.
		opponent_sprite.visible = false                                                           # Hide the opponent once no body pixels should remain visible.
		return                                                                                    # Return without displaying this opponent.
	if not _projected_sprite_overlaps_viewport(screen_x, screen_y, opponent_sprite, sprite_scale): # Let viewport clipping handle partial bodies but skip fully offscreen sprites.
		opponent_sprite.visible = false                                                           # Hide the opponent once the full sprite rectangle is outside the playfield.
		return                                                                                    # Return without displaying this opponent.
	var character_layer := int(projection["z_index"])                                                  # Read the opponent's wall-relative character layer.
	opponent_sprite.scale = Vector2.ONE * sprite_scale                                         # Apply the opponent sprite scale.
	opponent_sprite.position = Vector2(screen_x, screen_y)                                     # Apply the opponent sprite position.
	opponent_sprite.z_index = character_layer                                                          # Put the opponent into the same z-depth range as wall overlays.
	opponent_sprite.visible = true                                                             # Show the opponent because it passed visibility checks.



# _first_other_player_state: Returns the first player state that does not belong to the current view.
func _first_other_player_state() -> Dictionary:                                             # Declare this function.
	for player_index in range(player_states.size()):                                          # Check all known local player states.
		if player_index != active_player_index:                                                  # Find the first non-bound player.
			return _effective_player_state(player_index)                                           # Return the latest state for that other player.
	return {}                                                                                  # Return no opponent when only one player exists.



# _effective_player_state: Returns the current globals for the bound player or saved state for other players.
func _effective_player_state(player_index: int) -> Dictionary:                              # Declare this function.
	if player_index == active_player_index:                                                   # Build a live state record for the player currently being processed.
		return {                                                                                  # Return the freshest state from current globals.
			"player_index": active_player_index,                                                     # Include the current player index.
			"facing": facing,                                                                        # Include the current facing.
			"grid_position": grid_position,                                                         # Include the current grid cell.
			"local_floor_position": local_floor_position,                                           # Include the current local position.
			"character_is_moving": character_is_moving,                                             # Include whether the current player is running.
			"world_run_dir": world_run_dir,                                                         # Include the current player's world movement direction.
			"world_aim_dir": world_aim_dir,                                                         # Include the current player's world aim direction.
		}                                                                                           # Close the live state dictionary.
	if player_index >= 0 and player_index < player_states.size():                              # Check that the requested saved player index exists.
		return player_states[player_index]                                                         # Return the saved player state.
	return {}                                                                                  # Return an empty state for invalid player indexes.



# _player_state_world_position: Converts a player's cell and local offset into shared world-grid coordinates.
func _player_state_world_position(state: Dictionary) -> Vector2:                            # Declare this function.
	var state_facing := int(state.get("facing", 0))                                            # Read the player's facing for local-offset rotation.
	var state_cell: Vector2i = state.get("grid_position", Vector2i.ZERO)                       # Read the player's current cell.
	var state_local: Vector2 = state.get("local_floor_position", HOME_LOCAL_FLOOR_POSITION)    # Read the player's local position inside that cell.
	var local_offset := _local_position_to_tile_offset(state_local)                            # Convert art-space local position into right/forward tile offsets.
	var right := Vector2(-_left_vector_for_index(state_facing)).normalized()                   # Compute that player's world-right direction.
	var forward := Vector2(_facing_vector_for_index(state_facing)).normalized()                # Compute that player's world-forward direction.
	return Vector2(float(state_cell.x) + 0.5, float(state_cell.y) + 0.5) + right * local_offset.x * LOCAL_TILE_WORLD_HALF_EXTENT + forward * local_offset.y * LOCAL_TILE_WORLD_HALF_EXTENT # Return the world-grid point inside the cell.



# _opponent_projection_from_current_camera: Projects an opponent using the same corridor wall/floor perspective at every depth.
func _opponent_projection_from_current_camera(target_world: Vector2) -> Dictionary:         # Declare this function.
	var origin := _camera_grid_origin()                                                        # Read this player's fixed camera origin.
	var forward := Vector2(_facing_vector()).normalized()                                      # Read this player's camera-forward vector.
	var right := Vector2(-_left_vector()).normalized()                                         # Read this player's camera-right vector.
	var relative := target_world - origin                                                      # Measure the opponent relative to this player's camera.
	var view_depth := maxf(relative.dot(forward), 0.0)                                         # Compute the actor depth in the same top-down camera space as walls.
	var view_side := relative.dot(right)                                                       # Compute the actor side offset in the same top-down camera space as walls.
	var corridor := _corridor_projection_at_view_depth(view_depth)                             # Ask the shared corridor perspective for wall X bounds and floor Y at this depth.
	var screen_x := 0.0                                                                        # Store the projected opponent x coordinate.
	var feet_y := float(corridor["feet_y"])                                                    # Start with the main corridor feet line.
	if absf(view_side) <= LOCAL_TILE_WORLD_HALF_EXTENT:                                       # Use the main corridor projection while the actor is inside the visible hallway span.
		var side_unit := view_side / LOCAL_TILE_WORLD_HALF_EXTENT                                 # Normalize side position across the physical tile width.
		var screen_ratio_x := (side_unit + 1.0) * 0.5                                             # Convert normalized side from -1..1 into left-to-right interpolation space.
		screen_x = lerpf(float(corridor["left_x"]), float(corridor["right_x"]), screen_ratio_x)   # Place actor X between the projected corridor walls.
	else:                                                                                      # Use the measured side-entry band when the actor is past a hallway side edge.
		var side_projection := _side_entry_projection_at_view_depth(view_depth, signf(view_side)) # Sample the mirrored side-entry floor wedge.
		var cone_edge_side := _camera_fan_half_width_at_depth(view_depth)                         # Use the visible camera cone edge, not the full side-cell width, as the side-travel end.
		var side_visible_span := maxf(cone_edge_side - LOCAL_TILE_WORLD_HALF_EXTENT, 0.001)       # Measure the slice of the side square that can appear inside the view cone.
		var side_travel := (absf(view_side) - LOCAL_TILE_WORLD_HALF_EXTENT) / side_visible_span   # Let side travel continue past 1.0 so actors can run fully offscreen.
		var corridor_edge_x := float(corridor["right_x"]) if view_side > 0.0 else float(corridor["left_x"]) # Start side handoff exactly on the corridor boundary to avoid a branch pop.
		screen_x = lerpf(corridor_edge_x, float(side_projection["outer_x"]), side_travel)          # Let the actor move continuously from corridor edge to side-frame edge.
		feet_y = lerpf(float(corridor["feet_y"]), float(side_projection["feet_y"]), side_travel)   # Blend feet registration from corridor floor to side-entry floor without popping.
	var actor_height := float(corridor["actor_height"])                                       # Read actor height from the same measured perspective sample as the floor.
	var screen_y := feet_y - actor_height * 0.5                                                 # Register centered sprites from the selected feet line.
	var character_layer := _character_layer_for_view_depth(view_depth)                         # Use wall-depth buckets so same-depth side walls do not erase visible actors.
	var corridor_width := maxf(float(corridor["right_x"]) - float(corridor["left_x"]), 1.0)    # Measure how many screen pixels represent one visible tile width at this depth.
	return {"screen_x": screen_x, "screen_y": screen_y, "actor_height": actor_height, "z_index": character_layer, "corridor_width": corridor_width} # Return the projected screen coordinates, scale input, and character layer.



# _side_entry_projection_at_view_depth: Samples a side-entry floor wedge for actors outside the main corridor span.
func _side_entry_projection_at_view_depth(view_depth: float, side_sign: float) -> Dictionary: # Declare this function.
	var first_cell: Dictionary = SIDE_PERSPECTIVE_CELL_EXTENTS[0]                              # Read the nearest measured side square.
	var last_cell: Dictionary = SIDE_PERSPECTIVE_CELL_EXTENTS[SIDE_PERSPECTIVE_CELL_EXTENTS.size() - 1] # Read the farthest measured side square.
	var clamped_depth := clampf(view_depth, float(first_cell["near_depth"]), float(last_cell["far_depth"])) # Keep side samples inside measured depths.
	var cell: Dictionary = last_cell                                                           # Default to the farthest side square for edge cases.
	for cell_index in range(SIDE_PERSPECTIVE_CELL_EXTENTS.size()):                             # Search each measured side square.
		var candidate: Dictionary = SIDE_PERSPECTIVE_CELL_EXTENTS[cell_index]                     # Read this side square's projection bounds.
		if clamped_depth >= float(candidate["near_depth"]) and clamped_depth <= float(candidate["far_depth"]): # Find the square containing this depth.
			cell = candidate                                                                        # Store the active side square.
			break                                                                                   # Stop once the side square is known.
	var span := maxf(float(cell["far_depth"]) - float(cell["near_depth"]), 0.001)             # Avoid division by zero on malformed side samples.
	var blend := clampf((clamped_depth - float(cell["near_depth"])) / span, 0.0, 1.0)         # Compute the actor's forward/back position inside this side square.
	var right_inner_x := lerpf(float(cell["near_inner_x"]), float(cell["far_inner_x"]), blend) # Interpolate the corridor-side edge of the right-side wedge.
	var right_outer_x := VIEWPORT_SIZE.x - 1.0                                                 # Use the right frame edge as the outside of the side wedge.
	var feet_y := lerpf(float(cell["near_feet_y"]), float(cell["far_feet_y"]), blend)          # Interpolate the side wedge feet line.
	if side_sign < 0.0:                                                                        # Mirror right-side measurements for actors entering from the left.
		return {"inner_x": VIEWPORT_SIZE.x - 1.0 - right_inner_x, "outer_x": 0.0, "feet_y": feet_y} # Return a left-side wedge sample.
	return {"inner_x": right_inner_x, "outer_x": right_outer_x, "feet_y": feet_y}              # Return a right-side wedge sample.



# _corridor_projection_at_view_depth: Returns measured square bounds, feet line, and actor height for one camera-space depth.
func _corridor_projection_at_view_depth(view_depth: float) -> Dictionary:                  # Declare this function.
	return _perspective_square_sample_at_view_depth(view_depth)                               # Sample the shared measured square-trapezoid table.



# _self_actor_projection_at_local_depth: Projects the first-person body while avoiding camera-plane scale blowups.
func _self_actor_projection_at_local_depth(local_depth: float) -> Dictionary:              # Declare this function.
	var feet_view_depth := _clamped_self_feet_view_depth(_view_depth_for_local_floor_depth(local_depth)) # Convert the real local position into camera-space depth while keeping rendered feet inside S0.
	var feet_projection := _corridor_projection_at_view_depth(feet_view_depth)                # Sample the true projected floor location where the player's feet stand.
	var scale_view_depth := maxf(feet_view_depth, SELF_MIN_ACTOR_SCALE_VIEW_DEPTH)            # Keep self body scale from collapsing to the near-camera edge sample.
	var scale_projection := _corridor_projection_at_view_depth(scale_view_depth)              # Sample the visible S0 scale row used for the local body height.
	var projection := feet_projection.duplicate()                                             # Start from the true feet projection so X and feet Y stay in the real square.
	projection["actor_height"] = float(scale_projection["actor_height"])                      # Replace only actor height with the visible-body scale sample.
	projection["scale_view_depth"] = scale_view_depth                                         # Expose the self scale depth for debugging if needed.
	return projection                                                                         # Return the combined self-view projection.



# _self_screen_side_ratio_for_projection: Keeps local feet visually inside the projected floor while preserving physical tile movement.
func _self_screen_side_ratio_for_projection(local_x: float, projection: Dictionary) -> float: # Declare this function.
	var floor_width := maxf(float(projection["right_x"]) - float(projection["left_x"]), 1.0)    # Measure the visible floor span for the feet line.
	var side_margin := clampf(LOCAL_FEET_FLOOR_MARGIN_PIXELS / floor_width, 0.0, 0.25)          # Convert the pixel foot margin into normalized side padding.
	return clampf(local_x, side_margin, 1.0 - side_margin)                                      # Clamp the rendered feet anchor while leaving local_floor_position unchanged.



# _clamped_self_feet_view_depth: Keeps the first-person body feet inside the visible current-square floor zone.
func _clamped_self_feet_view_depth(view_depth: float) -> float:                            # Declare this function.
	var first_cell: Dictionary = PERSPECTIVE_CELL_EXTENTS[0]                                  # Read the current camera square calibration.
	var depth_span := maxf(float(first_cell["far_depth"]) - float(first_cell["near_depth"]), 0.001) # Measure the current square depth span.
	var feet_span := maxf(absf(float(first_cell["near_feet_y"]) - float(first_cell["far_feet_y"])), 1.0) # Measure the current square feet-line pixel span.
	var front_margin_depth := depth_span * LOCAL_FEET_DEPTH_MARGIN_PIXELS / feet_span          # Convert the desired front-edge pixel margin into camera-space depth.
	var max_self_depth := float(first_cell["far_depth"]) - front_margin_depth                  # Stop the rendered self feet just inside the S0 front edge.
	return minf(view_depth, max_self_depth)                                                    # Return the clamped self-view feet depth.



# _perspective_square_sample_at_view_depth: Interpolates inside the visible square trapezoid that contains this depth.
func _perspective_square_sample_at_view_depth(view_depth: float) -> Dictionary:            # Declare this function.
	var first_cell: Dictionary = PERSPECTIVE_CELL_EXTENTS[0]                                  # Read the nearest measured square.
	var last_cell: Dictionary = PERSPECTIVE_CELL_EXTENTS[PERSPECTIVE_CELL_EXTENTS.size() - 1] # Read the farthest measured square.
	var clamped_depth := clampf(view_depth, float(first_cell["near_depth"]), float(last_cell["far_depth"])) # Keep samples inside measured square depths.
	var cell: Dictionary = last_cell                                                          # Default to the farthest square for edge cases.
	for cell_index in range(PERSPECTIVE_CELL_EXTENTS.size()):                                 # Search each measured visible square.
		var candidate: Dictionary = PERSPECTIVE_CELL_EXTENTS[cell_index]                         # Read this square's projection bounds.
		if clamped_depth >= float(candidate["near_depth"]) and clamped_depth <= float(candidate["far_depth"]): # Find the square containing this depth.
			cell = candidate                                                                        # Store the active square.
			break                                                                                   # Stop once the active square is known.
	var span := maxf(float(cell["far_depth"]) - float(cell["near_depth"]), 0.001)            # Avoid division by zero on malformed square samples.
	var blend := clampf((clamped_depth - float(cell["near_depth"])) / span, 0.0, 1.0)        # Compute the actor's forward/back position inside this square.
	return {                                                                                 # Return one interpolated projection sample.
		"left_x": lerpf(float(cell["near_left_x"]), float(cell["far_left_x"]), blend),           # Interpolate the left boundary of this square from near edge to far edge.
		"right_x": lerpf(float(cell["near_right_x"]), float(cell["far_right_x"]), blend),        # Interpolate the right boundary of this square from near edge to far edge.
		"feet_y": lerpf(float(cell["near_feet_y"]), float(cell["far_feet_y"]), blend),           # Interpolate the projected floor/feet line inside this square.
		"actor_height": lerpf(float(cell["near_actor_height"]), float(cell["far_actor_height"]), blend), # Interpolate actor scale inside this exact square.
		"depth_t": clampf(clamped_depth / DEBUG_VIEW_CONE_DEPTH, 0.0, 1.0),                      # Return normalized depth for existing callers/debugging.
		"floor_depth": clamped_depth,                                                            # Preserve the physical camera depth for debug and future tuning.
		"cell_t": blend,                                                                          # Expose the actor's forward/back interpolation within this square.
	}                                                                                         # Close the projection sample dictionary.



# _view_depth_for_local_floor_depth: Converts local art-space y into physical camera-space depth.
func _view_depth_for_local_floor_depth(local_depth: float) -> float:                       # Declare this function.
	var forward_offset := _forward_axis_to_signed_unit(local_depth)                           # Convert local y into forward-positive physical tile offset.
	return CAMERA_REAR_OFFSET + forward_offset * LOCAL_TILE_WORLD_HALF_EXTENT                 # Return the same camera-space depth used by world-space opponent projection.



# _front_wall_height_at_view_depth: Interpolates measured straight-front wall heights across camera depth.
func _front_wall_height_at_view_depth(view_depth: float) -> float:                          # Declare this function.
	var clamped_depth := clampf(view_depth, 0.0, float(FRONT_WALL_HEIGHT_BY_DEPTH.size() - 1)) # Keep depth samples inside the currently measured straight-wall art rows.
	var lower_index := int(floor(clamped_depth))                                               # Pick the shallower measured wall row.
	var upper_index := mini(lower_index + 1, FRONT_WALL_HEIGHT_BY_DEPTH.size() - 1)            # Pick the next deeper measured wall row.
	var blend := clamped_depth - float(lower_index)                                            # Compute interpolation between the two measured rows.
	return lerpf(float(FRONT_WALL_HEIGHT_BY_DEPTH[lower_index]), float(FRONT_WALL_HEIGHT_BY_DEPTH[upper_index]), blend) # Return the interpolated wall height.



# _character_layer_for_view_depth: Places actors between wall draw rows using the renderer's depth buckets.
func _character_layer_for_view_depth(view_depth: float) -> int:                             # Declare this function.
	var depth_index := clampi(int(floor(maxf(view_depth, 0.0))), 0, CHARACTER_LAYER_BY_DEPTH.size() - 1) # Convert camera depth into the matching wall-art row.
	return int(CHARACTER_LAYER_BY_DEPTH[depth_index])                                        # Return the actor layer for this shared wall/floor perspective depth.


# _opponent_camera_side_margin_from_projection: Converts projected sprite width into camera-space fan overlap.
func _opponent_camera_side_margin_from_projection(projection: Dictionary, sprite_scale: float) -> float: # Declare this function.
	var projected_half_width := _sprite_texture_width(opponent_sprite) * sprite_scale * 0.5    # Measure half of the currently drawn opponent frame in screen pixels.
	var corridor_width := maxf(float(projection.get("corridor_width", VIEWPORT_SIZE.x)), 1.0)  # Read the projected one-tile corridor width at the actor's depth.
	return projected_half_width / corridor_width                                              # Convert the projected half-width into world-side units for cone overlap.



# _projected_sprite_overlaps_viewport: Checks whether any part of a projected sprite rectangle remains inside the playfield.
func _projected_sprite_overlaps_viewport(screen_x: float, screen_y: float, sprite: AnimatedSprite2D, sprite_scale: float) -> bool: # Declare this function.
	var half_width := _sprite_texture_width(sprite) * sprite_scale * 0.5                       # Measure the scaled horizontal sprite half-extents.
	var half_height := _sprite_texture_height(sprite) * sprite_scale * 0.5                     # Measure the scaled vertical sprite half-extents.
	if screen_x + half_width < 0.0 or screen_x - half_width > VIEWPORT_SIZE.x:                 # Reject only when the whole sprite is horizontally offscreen.
		return false                                                                              # Report no visible sprite pixels.
	if screen_y + half_height < 0.0 or screen_y - half_height > VIEWPORT_SIZE.y:               # Reject only when the whole sprite is vertically offscreen.
		return false                                                                              # Report no visible sprite pixels.
	return true                                                                               # Report that at least part of the sprite overlaps the playfield.



# _world_actor_overlaps_current_camera_fan: Checks whether an actor body overlaps this player's camera fan.
func _world_actor_overlaps_current_camera_fan(target_world: Vector2, side_margin: float) -> bool: # Declare this function.
	var origin := _camera_grid_origin()                                                        # Use the same rear-biased camera point as wall visibility.
	var forward := Vector2(_facing_vector()).normalized()                                      # Use the current player's camera-forward vector.
	var relative := target_world - origin                                                      # Measure the target relative to the camera.
	var depth := relative.dot(forward)                                                         # Compute target depth along camera-forward.
	if depth <= -0.05 - side_margin or depth > DEBUG_VIEW_CONE_DEPTH + 0.75 + side_margin:     # Reject actors only once their body is behind or beyond the useful straight-view art.
		return false                                                                              # Report the opponent as not visible.
	return true                                                                               # Let projected sprite/viewport overlap decide lateral edge visibility.



# _camera_fan_half_width_at_depth: Returns the top-down camera cone half-width for one forward depth.
func _camera_fan_half_width_at_depth(depth: float) -> float:                                # Declare this function.
	return maxf(0.48, depth * DEBUG_VIEW_CONE_HALF_WIDTH / DEBUG_VIEW_CONE_DEPTH + 0.10)      # Match the existing debug cone half-width calculation.



# _side_limits_for_depth: Returns local x limits that keep the player registered inside the visible floor trapezoid at this depth.
func _side_limits_for_depth(_local_depth: float) -> Vector2:                                # Declare this function.
	return Vector2(STRAFE_LEFT_WALL_CONTACT_X, STRAFE_RIGHT_WALL_CONTACT_X)                    # Keep movement and tile crossing on the real physical tile edges.



# _player_sprite_scale_for_depth: Returns the character scale used by both projection and movement bounds.
func _player_sprite_scale_for_depth(depth: float) -> float:                                # Declare this function.
	var projection := _self_actor_projection_at_local_depth(depth)                              # Sample the same self-body projection used by the renderer.
	return float(projection["actor_height"]) / maxf(_current_player_texture_height(), 1.0)     # Return the scale needed to match the measured character height.



# _current_player_texture_width: Returns the current player frame width so the sprite can be clamped inside the playfield.
func _current_player_texture_width() -> float:                                              # Declare this function.
	var texture := player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame) # Store mutable runtime state for assets, rendering, movement, or debug output.
	if texture == null:                                                                        # Run the following block only when this condition is true.
		return 34.0                                                                               # Return a conservative fallback width for the player sprite.
	return float(texture.get_width())                                                          # Return this computed result to the caller.



# _current_player_texture_height: Returns the current player frame height for perspective scaling.
func _current_player_texture_height() -> float:                                             # Declare this function.
	return _sprite_texture_height(player_sprite)                                               # Measure the currently bound local player sprite.



# _sprite_texture_height: Returns one sprite's current frame height with a safe fallback.
func _sprite_texture_height(sprite: AnimatedSprite2D) -> float:                             # Declare this function.
	if sprite == null or sprite.sprite_frames == null:                                        # Handle missing sprite resources defensively.
		return 46.0                                                                              # Return the known idle frame height as a fallback.
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)       # Read the current frame texture from this sprite.
	if texture == null:                                                                        # Handle animations that have not selected a visible frame yet.
		return 46.0                                                                              # Return the known idle frame height as a fallback.
	return maxf(float(texture.get_height()), 1.0)                                              # Return the frame height while avoiding division by zero.



# _sprite_texture_width: Returns one sprite's current frame width with a safe fallback.
func _sprite_texture_width(sprite: AnimatedSprite2D) -> float:                              # Declare this function.
	if sprite == null or sprite.sprite_frames == null:                                        # Handle missing sprite resources defensively.
		return 34.0                                                                              # Return the known idle frame width as a fallback.
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)       # Read the current frame texture from this sprite.
	if texture == null:                                                                        # Handle animations that have not selected a visible frame yet.
		return 34.0                                                                              # Return the known idle frame width as a fallback.
	return maxf(float(texture.get_width()), 1.0)                                               # Return the frame width while avoiding division by zero.



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



# _world_movement_dir_for_local_movement: Converts camera-local movement input into a shared cardinal world direction.
func _world_movement_dir_for_local_movement(movement: Vector2, facing_index: int) -> String: # Declare this function.
	var forward := Vector2(_facing_vector_for_index(facing_index))                              # Convert the player's camera-forward direction into a Vector2.
	var right := Vector2(-_left_vector_for_index(facing_index))                                 # Convert the player's camera-right direction into a Vector2.
	var world_vector := right * movement.x + forward * -movement.y                              # Rotate local side/forward input into world grid space.
	return _direction_string_for_world_vector(world_vector)                                     # Return the cardinal direction that best describes the movement.



# _direction_string_for_world_vector: Converts a world-space vector into one N/E/S/W animation direction.
func _direction_string_for_world_vector(world_vector: Vector2) -> String:                  # Declare this function.
	if world_vector.length_squared() <= 0.0001:                                                # Treat tiny vectors as no meaningful direction.
		return DIR_N                                                                              # Return north as the stable fallback direction.
	if absf(world_vector.x) >= absf(world_vector.y):                                           # Prefer side motion when diagonal values are tied.
		return DIR_E if world_vector.x > 0.0 else DIR_W                                          # Return east or west from the dominant x component.
	return DIR_S if world_vector.y > 0.0 else DIR_N                                            # Return south or north from the dominant y component.



# _direction_string_for_facing: Converts a facing index into the matching world direction string.
func _direction_string_for_facing(facing_index: int) -> String:                            # Declare this function.
	return _direction_string_for_world_vector(Vector2(_facing_vector_for_index(facing_index))) # Return the cardinal label for this facing vector.



# _world_vector_for_direction_string: Converts an N/E/S/W animation direction back into a world vector.
func _world_vector_for_direction_string(direction: String) -> Vector2:                    # Declare this function.
	match direction:                                                                          # Branch by the direction label stored in player state.
		DIR_E:                                                                                   # Handle east.
			return Vector2(1.0, 0.0)                                                               # Return the east vector.
		DIR_S:                                                                                   # Handle south.
			return Vector2(0.0, 1.0)                                                               # Return the south vector.
		DIR_W:                                                                                   # Handle west.
			return Vector2(-1.0, 0.0)                                                              # Return the west vector.
		_:                                                                                       # Handle north and any malformed fallback.
			return Vector2(0.0, -1.0)                                                              # Return the north vector.



# _view_relative_dir: Converts a world direction into the viewer's screen-relative animation direction.
func _view_relative_dir(world_direction: String, viewer_facing: int) -> String:           # Declare this function.
	var world_vector := _world_vector_for_direction_string(world_direction)                    # Convert the saved world direction into a vector.
	var forward := Vector2(_facing_vector_for_index(viewer_facing))                            # Read the viewer's camera-forward vector.
	var right := Vector2(-_left_vector_for_index(viewer_facing))                               # Read the viewer's camera-right vector.
	var depth_amount := world_vector.dot(forward)                                              # Measure how much this direction points into or out of the viewer's screen.
	var side_amount := world_vector.dot(right)                                                 # Measure how much this direction points left or right on the viewer's screen.
	if absf(side_amount) >= absf(depth_amount):                                                # Prefer side views when a tie is possible.
		return DIR_E if side_amount > 0.0 else DIR_W                                             # Return the screen-side direction.
	return DIR_N if depth_amount > 0.0 else DIR_S                                              # Return forward-away or backward-toward direction.



# _apply_opponent_animation: Plays the other player's full view-relative run/aim set when visible in this screen.
func _apply_opponent_animation(other_state: Dictionary) -> void:                           # Declare this function.
	if opponent_sprite.sprite_frames == null:                                                  # Skip animation if the opponent sprite has no SpriteFrames resource.
		return                                                                                    # Return without changing animation.
	var moving := bool(other_state.get("character_is_moving", false))                          # Read whether the opponent is actively running.
	var other_facing := int(other_state.get("facing", 0))                                      # Read the opponent's camera/aim facing for fallbacks.
	var other_world_run := String(other_state.get("world_run_dir", _direction_string_for_facing(other_facing))) # Read the opponent's world run direction.
	var other_world_aim := String(other_state.get("world_aim_dir", _direction_string_for_facing(other_facing))) # Read the opponent's world aim direction.
	var relative_run := _view_relative_dir(other_world_run, facing)                            # Convert run direction into this viewer's animation space.
	var relative_aim := _view_relative_dir(other_world_aim, facing)                            # Convert aim direction into this viewer's animation space.
	if not moving:                                                                             # Use a first run frame as the idle placeholder until idle variants exist.
		relative_run = relative_aim                                                               # Face the idle fallback body in the same direction as the opponent's aim.
	var animation := _best_opponent_animation_for(relative_run, relative_aim)                  # Pick the exact or nearest available opponent animation.
	if animation == &"":                                                                       # Skip if no usable animation exists.
		return                                                                                    # Return without changing the opponent sprite.
	if opponent_sprite.animation != animation:                                                 # Avoid restarting the same opponent animation every frame.
		opponent_sprite.play(animation)                                                           # Start the selected opponent animation.
	if moving:                                                                                 # Keep active opponents animated.
		if not opponent_sprite.is_playing():                                                       # Resume if the sprite was paused or stopped while idle.
			opponent_sprite.play(animation)                                                            # Play the selected opponent animation.
	else:                                                                                      # Freeze idle opponents on the first frame of the chosen directional run.
		opponent_sprite.frame = 0                                                                  # Display the first frame as the temporary idle pose.
		opponent_sprite.stop()                                                                     # Stop playback so the first-frame idle fallback holds still.



# _best_opponent_animation_for: Finds the best available run/aim animation for another player.
func _best_opponent_animation_for(run: String, aim: String) -> StringName:                # Declare this function.
	var exact := "Run%s_Aim%s" % [run, aim]                                                   # Build the preferred exact run/aim animation name.
	if available_animations.has(exact):                                                        # Use the exact opponent angle when the art exists.
		return StringName(exact)                                                                  # Return the exact animation name.
	var same_aim_suffix := "_Aim%s" % aim                                                      # Build a suffix for animations that at least aim the correct way.
	for animation in available_animations.keys():                                              # Search all loaded animations.
		if String(animation).ends_with(same_aim_suffix):                                          # Prefer correct aiming direction over body direction when exact art is missing.
			return StringName(animation)                                                             # Return this aim-compatible fallback.
	var same_run := _first_animation_with_prefix("Run%s_Aim" % run)                            # Search for a fallback with the requested body/run direction.
	if same_run != &"":                                                                        # Use same-run fallback if available.
		return same_run                                                                           # Return that fallback.
	if available_animations.has("IdleN_AimN"):                                                 # Keep the old north idle as a final readable fallback.
		return &"IdleN_AimN"                                                                      # Return the generic idle fallback.
	return &""                                                                                 # Return no animation when the resource is unexpectedly empty.



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



# _request_transition: Starts a captured phase or immediately snaps the transition result based on the phase toggle.
func _request_transition(sequence_name: String) -> void:                                    # Declare this function.
	if use_captured_transitions:                                                               # Use the captured phase art only when that temporary option is enabled.
		_start_transition(sequence_name)                                                          # Play the captured transition sequence.
		return                                                                                    # Return after starting captured phase playback.
	active_sequence_name = sequence_name                                                       # Store the requested transition name so the shared result helpers can apply it.
	_finish_snap_transition(sequence_name)                                                     # Apply the transition result immediately with no captured phase playback.



# _finish_snap_transition: Applies a movement or turn result immediately and redraws the stable view.
func _finish_snap_transition(sequence_name: String) -> void:                                # Declare this function.
	is_transitioning = false                                                                   # Ensure the controller stays in stable/input mode.
	_apply_grid_result(sequence_name)                                                          # Apply the pending cell delta or facing rotation.
	_reset_local_position_after_transition(sequence_name)                                      # Put the player on the correct entry edge in the new cell or facing.
	active_sequence = []                                                                       # Clear any previous captured sequence frames.
	phase_index = 0                                                                            # Reset captured phase bookkeeping.
	phase_timer = 0.0                                                                          # Reset captured phase timing.
	_show_stable()                                                                             # Redraw the environment for the new cell/facing immediately.
	_position_player()                                                                         # Reposition the player sprite for the snapped state.
	if enable_3d_diagnostic:                                                                   # Keep optional diagnostics in sync when enabled.
		_update_3d_diagnostic()                                                                   # Sync the deprecated 3D diagnostic.
	_update_debug_map_overlay()                                                                # Redraw the right-side top-down source map for the snapped state.
	_update_status()                                                                           # Refresh the status label after the snap.



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
	return _facing_vector_for_index(facing)                                                    # Return the world direction for the currently bound player.



# _facing_vector_for_index: Returns the world grid direction vector for a supplied cardinal facing index.
func _facing_vector_for_index(facing_index: int) -> Vector2i:                               # Declare this function.
	match facing_index:                                                                        # Branch behavior based on this value.
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
	return _left_vector_for_index(facing)                                                      # Return the camera-left vector for the currently bound player.



# _left_vector_for_index: Returns the world grid direction that is camera-left for a supplied cardinal facing index.
func _left_vector_for_index(facing_index: int) -> Vector2i:                                # Declare this function.
	match facing_index:                                                                        # Branch behavior based on this value.
		0:                                                                                        # Start this block.
			return Vector2i(-1, 0)                                                                   # Return this computed result to the caller.
		1:                                                                                        # Start this block.
			return Vector2i(0, -1)                                                                   # Return this computed result to the caller.
		2:                                                                                        # Start this block.
			return Vector2i(1, 0)                                                                    # Return this computed result to the caller.
		_:                                                                                        # Call a helper function as part of the current controller step.
			return Vector2i(0, 1)                                                                    # Return this computed result to the caller.



# _build_fixed_reference_maze_wall_edges: Restores the current saved 4x4 thin-wall maze instead of rerolling on startup.
func _build_fixed_reference_maze_wall_edges() -> void:                                     # Declare this function.
	wall_edges.clear()                                                                         # Clear any previous map wall data before loading the fixed reference map.
	var saved_rows := [                                                                       # Store the saved generated map as north/east/south/west wall bits per cell.
		"1001 1000 1010 1100",                                                                  # Store row 0 of the saved generated map.
		"0101 0001 1000 0100",                                                                  # Store row 1 of the saved generated map.
		"0001 0100 0001 0100",                                                                  # Store row 2 of the saved generated map.
		"0011 0110 0011 0110",                                                                  # Store row 3 of the saved generated map.
	]                                                                                         # Close the saved map row list.
	for y in range(MAP_HEIGHT):                                                                # Iterate through every row in the fixed 4x4 map.
		var row_cells: PackedStringArray = String(saved_rows[y]).split(" ")                       # Split this saved row into one four-bit string per cell.
		for x in range(MAP_WIDTH):                                                               # Iterate through every column in the fixed 4x4 map.
			var bits := row_cells[x]                                                                # Read the north/east/south/west wall bits for this cell.
			var cell := Vector2i(x, y)                                                              # Build the current map cell coordinate.
			wall_edges[cell] = {                                                                    # Load the exact saved generated wall state for this cell.
				WALL_EDGE_N: bits[0] == "1",                                                         # Load this cell's north wall bit.
				WALL_EDGE_E: bits[1] == "1",                                                         # Load this cell's east wall bit.
				WALL_EDGE_S: bits[2] == "1",                                                         # Load this cell's south wall bit.
				WALL_EDGE_W: bits[3] == "1",                                                         # Load this cell's west wall bit.
			}                                                                                       # Close the cell wall dictionary.
	grid_position = Vector2i(0, MAP_HEIGHT - 1)                                               # Start at the southwest cell used by the random-map generator.
	facing = 0                                                                                 # Face north into the saved generated map.
	local_floor_position = HOME_LOCAL_FLOOR_POSITION                                           # Reset the player to the normal local tile position.
	pending_grid_delta = Vector2i.ZERO                                                         # Clear any stale cell-crossing request.
	last_blocked_direction = ""                                                                # Clear any stale blocked-movement status.



# _regenerate_runtime_map: Rerolls the 4x4 thin-wall maze during play and redraws every dependent view.
func _regenerate_runtime_map() -> void:                                                     # Declare this function.
	held_keycodes.clear()                                                                      # Clear held-key fallback state so the reset starts from neutral input.
	was_regenerate_map_pressed = true                                                          # Keep the regenerate key from firing again until released.
	_build_random_maze_wall_edges()                                                            # Build a fresh connected 4x4 thin-wall maze and reset the player.
	_reset_player_states_after_map(Vector2i(0, MAP_HEIGHT - 1))                                # Reset both local players into opposite corners of the new shared map.
	_render_all_player_views()                                                                 # Redraw both screens and maps after the shared maze changes.
	_update_status()                                                                           # Update the status text for the new map state.



# _reset_player_states_after_map: Reinitializes both local players after the shared thin-wall map changes.
func _reset_player_states_after_map(player_one_cell: Vector2i) -> void:                    # Declare this function.
	player_states = [                                                                          # Replace both state records with clean starts.
		_make_player_state(0, player_one_cell, 0),                                                # Put player one at the requested start facing north.
		_make_player_state(1, Vector2i(MAP_WIDTH - 1, 0), 2),                                     # Put player two at the opposite corner facing south.
	]                                                                                           # Close the regenerated player-state list.
	for player_index in range(player_views.size()):                                           # Reset the visible animation latch for every player view.
		_bind_player_context(player_index)                                                       # Bind this player's state and sprite.
		_play_best_animation(false)                                                               # Return this player to idle.
		_save_player_context(player_index)                                                        # Store the reset animation state.
	_bind_player_context(0)                                                                    # Leave player one bound after the reset.



# _build_random_maze_wall_edges: Builds a generated 4x4 thin-wall maze with closed outside borders.
func _build_random_maze_wall_edges() -> void:                                               # Declare this function.
	wall_edges.clear()                                                                         # Clear any previous map wall data before generating the maze.
	for y in range(MAP_HEIGHT):                                                                # Iterate through every row in the 4x4 map.
		for x in range(MAP_WIDTH):                                                               # Iterate through every column in the 4x4 map.
			var cell := Vector2i(x, y)                                                              # Build the current map cell coordinate.
			wall_edges[cell] = {                                                                    # Start each cell as a closed box before carving passages.
				WALL_EDGE_N: true,                                                                    # Close the north edge until the maze carver opens it.
				WALL_EDGE_E: true,                                                                    # Close the east edge until the maze carver opens it.
				WALL_EDGE_S: true,                                                                    # Close the south edge until the maze carver opens it.
				WALL_EDGE_W: true,                                                                    # Close the west edge until the maze carver opens it.
			}                                                                                       # Close the cell wall dictionary.
	var rng := RandomNumberGenerator.new()                                                     # Create a local random source for this generated test maze.
	rng.randomize()                                                                            # Seed the random source from the current run so the maze changes between launches.
	var visited: Dictionary = {}                                                               # Track which cells have already been reached by the maze carver.
	var start_cell := Vector2i(0, MAP_HEIGHT - 1)                                              # Start the test player in the southwest corner of the generated map.
	_carve_maze_from(start_cell, visited, rng)                                                 # Carve a connected maze from the starting cell.
	_add_extra_maze_openings(rng)                                                              # Open a few extra internal walls so the map has some loops.
	grid_position = start_cell                                                                 # Place the player at the start of the generated maze.
	facing = 0                                                                                 # Face north so the first view looks into the map.
	local_floor_position = HOME_LOCAL_FLOOR_POSITION                                           # Reset the player to the normal local tile position.
	pending_grid_delta = Vector2i.ZERO                                                         # Clear any stale cell-crossing request.
	last_blocked_direction = ""                                                                # Clear any stale blocked-movement status.



# _carve_maze_from: Recursively carves passages through internal wall edges to make all cells reachable.
func _carve_maze_from(cell: Vector2i, visited: Dictionary, rng: RandomNumberGenerator) -> void: # Declare this function.
	visited[cell] = true                                                                       # Mark this cell as part of the carved maze.
	for delta in _shuffled_cardinal_directions(rng):                                           # Visit neighboring cells in random order.
		var next_cell := cell + delta                                                            # Compute the adjacent cell in this direction.
		if not _is_open_cell(next_cell):                                                          # Skip neighbors outside the 4x4 map.
			continue                                                                                 # Continue to the next shuffled direction.
		if visited.has(next_cell):                                                                # Skip neighbors that have already been carved.
			continue                                                                                 # Continue to the next shuffled direction.
		_set_wall_between(cell, delta, false)                                                     # Open the wall between this cell and the unvisited neighbor.
		_carve_maze_from(next_cell, visited, rng)                                                 # Continue carving from that newly reached neighbor.



# _add_extra_maze_openings: Opens a small number of remaining internal walls to make the maze less linear.
func _add_extra_maze_openings(rng: RandomNumberGenerator) -> void:                          # Declare this function.
	for y in range(MAP_HEIGHT):                                                                # Iterate through every row in the generated map.
		for x in range(MAP_WIDTH):                                                               # Iterate through every column in the generated map.
			var cell := Vector2i(x, y)                                                              # Build the current map cell coordinate.
			for delta in [Vector2i(1, 0), Vector2i(0, 1)]:                                         # Check only east and south so each shared edge is considered once.
				if not _is_open_cell(cell + delta):                                                   # Keep outside borders walled by skipping out-of-map neighbors.
					continue                                                                              # Continue to the next candidate edge.
				if rng.randf() <= MAP_EXTRA_OPENING_CHANCE:                                           # Randomly decide whether to add a loop at this internal wall.
					_set_wall_between(cell, delta, false)                                                # Open this internal wall while keeping both cells consistent.



# _shuffled_cardinal_directions: Returns the four grid movement directions in random order.
func _shuffled_cardinal_directions(rng: RandomNumberGenerator) -> Array[Vector2i]:          # Declare this function.
	var directions: Array[Vector2i] = [                                                       # Start with all four possible neighboring directions.
		Vector2i(0, -1),                                                                          # Include north.
		Vector2i(1, 0),                                                                           # Include east.
		Vector2i(0, 1),                                                                           # Include south.
		Vector2i(-1, 0),                                                                          # Include west.
	]                                                                                          # Close the direction list.
	for i in range(directions.size() - 1, 0, -1):                                             # Walk backward through the list for a Fisher-Yates shuffle.
		var j := rng.randi_range(0, i)                                                           # Pick a random earlier-or-current index.
		var temp := directions[i]                                                                 # Store the current direction before swapping.
		directions[i] = directions[j]                                                            # Move the random direction into this slot.
		directions[j] = temp                                                                      # Move the stored direction into the random slot.
	return directions                                                                          # Return the shuffled direction list.



# _set_wall_between: Sets a shared edge on both neighboring cells so the thin-wall map stays symmetric.
func _set_wall_between(cell: Vector2i, delta: Vector2i, has_wall: bool) -> void:             # Declare this function.
	var edge := _edge_from_delta(delta)                                                        # Convert the neighbor direction into this cell's edge id.
	if edge < 0:                                                                               # Ignore invalid neighbor directions defensively.
		return                                                                                    # Return without changing the map.
	var cell_edges: Dictionary = wall_edges.get(cell, {})                                      # Read this cell's mutable edge dictionary.
	cell_edges[edge] = has_wall                                                                # Set the requested wall state on this cell.
	wall_edges[cell] = cell_edges                                                              # Store the updated edge dictionary back into the wall map.
	var other_cell := cell + delta                                                             # Compute the neighboring cell sharing the same edge.
	if not _is_open_cell(other_cell):                                                          # Skip mirrored updates for out-of-map space.
		return                                                                                    # Return after updating the in-map side.
	var other_edges: Dictionary = wall_edges.get(other_cell, {})                               # Read the neighboring cell's edge dictionary.
	other_edges[_opposite_edge(edge)] = has_wall                                               # Mirror the wall state onto the neighbor's opposite edge.
	wall_edges[other_cell] = other_edges                                                       # Store the mirrored edge dictionary back into the wall map.



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



# _is_open_cell: Returns whether a cell belongs to the generated 4x4 map footprint.
func _is_open_cell(cell: Vector2i) -> bool:                                                 # Declare this function.
	return cell.x >= 0 and cell.x < MAP_WIDTH and cell.y >= 0 and cell.y < MAP_HEIGHT          # Return whether this coordinate is inside the 4x4 map.



# _update_status: Writes debug state text showing phase, facing, cell, local offset, animation, and blocked direction.
func _update_status() -> void:                                                              # Declare this function.
	var facing_names: Array[String] = ["N", "E", "S", "W"]                                     # Track the player camera direction as 0=N, 1=E, 2=S, 3=W.
	var lines: Array[String] = []                                                              # Build one compact status line per local player.
	for player_index in range(player_states.size()):                                          # Format every local player's saved state.
		var state: Dictionary = player_states[player_index]                                      # Read this player's state.
		var state_facing := int(state.get("facing", 0))                                          # Read this player's facing index.
		var state_cell: Vector2i = state.get("grid_position", Vector2i.ZERO)                     # Read this player's current cell.
		var state_local: Vector2 = state.get("local_floor_position", HOME_LOCAL_FLOOR_POSITION)  # Read this player's local tile position.
		var state_view: Dictionary = player_views[player_index] if player_index < player_views.size() else {} # Read this player's view bundle.
		var state_sprite: AnimatedSprite2D = state_view.get("player_sprite", null)               # Read this player's sprite for animation reporting.
		var state_animation := String(state_sprite.animation) if state_sprite != null else "-"    # Format this player's current animation name.
		var phase_text := "stable"                                                               # Default this player to stable mode.
		if bool(state.get("is_transitioning", false)):                                           # Show captured phase progress when this player is transitioning.
			phase_text = "%s phase %d" % [String(state.get("active_sequence_name", "idle")), int(state.get("phase_index", 0)) + 1] # Format the transition status.
		lines.append("P%d %s Facing %s Cell %d,%d Local %.2f,%.2f Anim %s Walls %s%s" % [player_index + 1, phase_text, facing_names[state_facing], state_cell.x, state_cell.y, state_local.x, state_local.y, state_animation, _visible_wall_ids_text_for_state(state), (" Blocked " + String(state.get("last_blocked_direction", ""))) if not String(state.get("last_blocked_direction", "")).is_empty() else ""]) # Add this player status line.
	status_label.text = "%s\n%s\nP1: WASD move, Q/E turn. P2: numpad 8/5/4/6 move, numpad 7/9 twist. R rerolls map." % [lines[0] if lines.size() > 0 else "P1 missing", lines[1] if lines.size() > 1 else "P2 missing"] # Update the on-screen debug status label.



# _visible_wall_ids_text: Formats the selected wall ids so screenshots show what the visibility tree chose.
func _visible_wall_ids_text() -> String:                                                     # Declare this function.
	if last_visible_wall_ids.is_empty():                                                       # Show a placeholder when no stable wall overlays are selected.
		return "-"                                                                               # Return a no-walls marker for the status text.
	var parts: Array[String] = []                                                              # Store formatted wall ids before joining them.
	for wall_id in last_visible_wall_ids:                                                      # Iterate through the selected wall id list.
		parts.append("%02d" % wall_id)                                                            # Add this wall id as a two-digit label.
	return ",".join(parts)                                                                     # Return the comma-separated wall id list.



# _visible_wall_ids_text_for_state: Formats visible wall ids from a saved player state.
func _visible_wall_ids_text_for_state(state: Dictionary) -> String:                         # Declare this function.
	var ids: Array = state.get("last_visible_wall_ids", [])                                    # Read this player's saved visible wall ids.
	if ids.is_empty():                                                                         # Show a placeholder when no stable wall overlays are selected.
		return "-"                                                                               # Return a no-walls marker for the status text.
	var parts: Array[String] = []                                                              # Store formatted wall ids before joining them.
	for wall_id in ids:                                                                        # Iterate through the selected wall id list.
		parts.append("%02d" % int(wall_id))                                                       # Add this wall id as a two-digit label.
	return ",".join(parts)                                                                     # Return the comma-separated wall id list.
