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
const TURN_PASSTHROUGH_SECONDS := 0.10                                                      # Display each 22/66 camera interpolation frame briefly before the next stable orientation.
const MOVE_UNITS_PER_SECOND := 1.70                                                         # Set movement in normalized half-tile units so X and Y ground speed match.
const DIAGONAL_CORNER_GRACE := 0.15                                                         # Give true 45-degree crossings roughly three body widths of tolerance before allowing a side-cell camera handoff.
const HOME_LOCAL_FLOOR_POSITION := Vector2(0.5, 0.68)                                       # Set the resting local position inside a tile.
const FORWARD_TRIGGER_Y := 0.56                                                             # Set the forward threshold where crossing into the next tile begins.
const BACKWARD_TRIGGER_Y := 0.84                                                            # Set the backward threshold where crossing into the previous tile begins.
const STRAFE_LEFT_WALL_CONTACT_X := 0.0                                                     # Set the left tile-edge contact; camera clipping trims any body pixels beyond the frame.
const STRAFE_RIGHT_WALL_CONTACT_X := 1.0                                                    # Set the right tile-edge contact; camera clipping trims any body pixels beyond the frame.
const FORWARD_WALL_CONTACT_Y := 0.56                                                        # Set the closest blocked-wall contact position in front of the viewer.
const BACKWARD_WALL_CONTACT_Y := 0.84                                                       # Set the closest blocked-wall contact position behind the viewer.
const MAP_WIDTH := 9                                                                        # Temporarily use a 9x9 thin-wall test grid for the slot-diagram audit.
const MAP_HEIGHT := 9                                                                       # Temporarily use a 9x9 thin-wall test grid for the slot-diagram audit.
const TEMP_EMPTY_GRID_AUDIT := false                                                        # Leave the floor-only audit available when isolated projection tuning is needed.
const TEMP_RANDOM_GRID_AUDIT := true                                                        # Use a mixed open/blocked 9x9 maze to check tuned local projections against real wall selection.
const TEMP_GRID_AUDIT := TEMP_EMPTY_GRID_AUDIT or TEMP_RANDOM_GRID_AUDIT                    # Keep the temporary audit layout single-player and side-by-side in either test mode.
const MAP_EXTRA_OPENING_CHANCE := 0.18                                                      # Add a few loops after maze carving so the interior is not a strict tree.

const PHASE_ROOT := "res://assets/reference_xybots_local/playfield_phases"                  # Point to captured full-frame movement and turn phase assets.
const STABLE_VIEW_ROOT := "res://assets/reference_xybots_local/stable_views"                # Point to old full-frame stable-view fallback assets.
const SLOT_ROOT := "res://assets/reference_xybots_local/environment_slots"                  # Point to old coarse slot fallback assets.
const WALLS_STRAIGHT_ROOT := "res://assets/Environment/WallsStraight"                       # Point to the 28 transparent straight-wall overlay sprites.
const WALLS_TURN_22_ROOT := "res://assets/Environment/Walls_Turn_22"                        # Point to the 17 transparent first-quarter turn wall overlays.
const WALLS_TURN_45_ROOT := "res://assets/Environment/Walls_Turn_45"                        # Point to the 16 transparent halfway-turn wall overlay sprites.
const WALLS_TURN_66_ROOT := "res://assets/Environment/Walls_Turn_66"                        # Point to the 17 transparent third-quarter turn wall overlays.
const WALLS_FWD_1_ROOT := "res://assets/Environment/Walls_Fwd_1"                            # Point to the 20 transparent first forward-transition wall overlays.
const WALLS_FWD_2_ROOT := "res://assets/Environment/Walls_Fwd_2"                            # Point to the 26 transparent second forward-transition wall overlays.
const WALLS_RIGHT_1_ROOT := "res://assets/Environment/Walls_Right_1"                        # Point to the 24 transparent first local-right strafe overlays.
const WALLS_RIGHT_2_ROOT := "res://assets/Environment/Walls_Right_2"                        # Point to the 22 transparent second local-right strafe overlays.
const WALLS_RIGHT_3_ROOT := "res://assets/Environment/Walls_Right_3"                        # Point to the 24 transparent third local-right strafe overlays.
const FLOOR_TURN_TEXTURE := "res://assets/Environment/Floor_Turn.png"                       # Point to the floor strip whose first frame is used as the straight-view base.
const FLOOR_FWD_1_TEXTURE := "res://assets/Environment/FloorFwd_1.png"                      # Point to the first authored forward-transition floor frame.
const FLOOR_FWD_2_TEXTURE := "res://assets/Environment/FloorFwd_2.png"                      # Point to the second authored forward-transition floor frame.
const FLOOR_RIGHT_1_TEXTURE := "res://assets/Environment/FloorRight_1.png"                  # Point to the first authored local-right strafe floor frame.
const FLOOR_RIGHT_2_TEXTURE := "res://assets/Environment/FloorRight_2.png"                  # Point to the second authored local-right strafe floor frame.
const FLOOR_RIGHT_3_TEXTURE := "res://assets/Environment/FloorRight_3.png"                  # Point to the third authored local-right strafe floor frame.
const FORWARD_PASSTHROUGH_SECONDS := 0.075                                                   # Keep both forward camera frames brisk while still making their geometry readable.
const FORWARD_RUN_ANIMATION_SPEED := 1.75                                                     # Let the body visibly keep running while the two authored camera frames catch up.
const STRAFE_PASSTHROUGH_SECONDS := 0.075                                                    # Keep each authored side-camera frame equally brisk during ordinary automatic strafing.
const TURN_STAGE_SEQUENCE_NAMES := ["idle", "turn_22", "turn_45", "turn_66"]               # Name the cardinal and authored intermediate turn views for debug status.
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
const ACTION_TOGGLE_SLOT_GRID_DEBUG := "xybots_toggle_slot_grid_debug"                       # Name the explicit input action for toggling the blue slot-grid audit overlay.
const ACTION_TOGGLE_DEBUG_MENU := "xybots_toggle_debug_menu"                                 # Name the explicit input action for opening the grouped debug-overlay menu.
const ACTION_P2_MOVE_LEFT := "xybots_p2_move_left"                                          # Name the second-player input action for moving camera-left inside the current tile.
const ACTION_P2_MOVE_RIGHT := "xybots_p2_move_right"                                        # Name the second-player input action for moving camera-right inside the current tile.
const ACTION_P2_MOVE_FORWARD := "xybots_p2_move_forward"                                    # Name the second-player input action for moving toward the camera-facing edge.
const ACTION_P2_MOVE_BACKWARD := "xybots_p2_move_backward"                                  # Name the second-player input action for moving away from the camera-facing edge.
const ACTION_P2_TURN_LEFT := "xybots_p2_turn_left"                                          # Name the second-player input action for rotating the view left.
const ACTION_P2_TURN_RIGHT := "xybots_p2_turn_right"                                        # Name the second-player input action for rotating the view right.
const XBOX_STICK_DEADZONE := 0.22                                                            # Ignore small Xbox-stick drift around its physical center.
const XBOX_TURN_THRESHOLD := 0.62                                                            # Require a deliberate right-stick push before issuing one turn input.
const DEBUG_MAP_CELL_SIZE := 16.0                                                           # Fit the temporary 9x9 diagnostic grid inside its own side panel.
const DEBUG_MAP_PANEL_SIZE := Vector2(160.0, 160.0)                                        # Give the 9x9 source grid a square panel beside the player view.
const DEBUG_MAP_PANEL_GRID_ORIGIN := Vector2(8.0, 8.0)                                      # Center the temporary 9x9 grid inside its 160x160 side panel.
const CARDINAL_SLOT_GUIDE_MAP_SCALE := 1.0                                                   # Keep authored guide coordinates in their native maze-cell scale; they may extend beyond the panel.
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
const DEBUG_WALL_LABELS_ENABLED := false                                                    # Hide renderer-selected wall labels while the blue slot-grid audit is being checked.
const VISIBILITY_RAY_COUNT := 91                                                            # Cast enough rays across the view fan to discover side and front wall edges.
const VISIBILITY_RAY_HALF_ANGLE_DEGREES := rad_to_deg(atan(DEBUG_VIEW_CONE_HALF_WIDTH / DEBUG_VIEW_CONE_DEPTH)) # Match ray casting to the Wall_Grid cone shape.
const VISIBILITY_MAX_DISTANCE := 5.2                                                        # Limit ray tests to the straight-view art depth.
const SLOT_GRID_DEBUG_LABEL_COLOR := Color(0.05, 0.45, 1.0, 1.0)                            # Use blue for the independent slot-number audit labels.
const SLOT_GRID_DEBUG_WALL_COLOR := Color(0.05, 0.55, 1.0, 0.95)                             # Use bright blue for slot guide lines whose source-map edge is currently blocked.
const SLOT_GRID_DEBUG_OPEN_COLOR := Color(0.05, 0.45, 1.0, 0.32)                             # Use faint blue for slot guide lines whose source-map edge is currently open.
const TURN_45_DIAGNOSTIC_ROW_DEPTHS := [3.45, 2.55, 1.65, 0.78]                              # Store far-to-near camera-local depth rows for the 16 halfway-turn slot audit.
const TURN_45_DIAGNOSTIC_ROW_SIDES := [                                                     # Store far-to-near camera-local side columns for the 16 halfway-turn slot audit.
	[-1.50, -0.50, 0.50, 1.50],                                                                 # Spread the far row across the full diagonal view fan.
	[-1.30, -0.43, 0.43, 1.30],                                                                 # Pull the next row slightly inward with the cone.
	[-1.05, -0.35, 0.35, 1.05],                                                                 # Pull the near-mid row farther inward.
	[-0.78, -0.26, 0.26, 0.78],                                                                 # Keep the closest row inside the near camera footprint.
]                                                                                           # Close the halfway-turn diagnostic side table.
const TURN_45_DIAGNOSTIC_ROW_IDS := [                                                       # Store local player-view slot ids from Wall_Grid_45.png, always left-to-right.
	[3, 1, 2, 6],                                                                               # Label the far row from local left to local right.
	[7, 4, 5, 10],                                                                              # Label the next row from local left to local right.
	[11, 8, 9, 14],                                                                             # Label the near-mid row from local left to local right.
	[15, 12, 13, 16],                                                                           # Label the closest row from local left to local right.
]                                                                                           # Close the halfway-turn diagnostic id table.
const TURN_22_PLAYER_SLOT_GUIDE := [                                                        # Copy the player-view positions from Grid_Turn22_NE.png in 160x120 playfield pixels.
	{"id": 1, "label": Vector2(56.3, 50.0), "tangent": Vector2.DOWN, "half": 5.0},      # Far inner-left vertical wall.
	{"id": 2, "label": Vector2(94.6, 50.0), "tangent": Vector2.DOWN, "half": 5.0},      # Far inner-right vertical wall.
	{"id": 3, "label": Vector2(8.3, 54.0), "tangent": Vector2.RIGHT, "half": 6.0},      # Far local-left horizontal wall.
	{"id": 4, "label": Vector2(36.3, 54.0), "tangent": Vector2.RIGHT, "half": 6.0},     # Far inner-left horizontal wall.
	{"id": 5, "label": Vector2(85.7, 54.0), "tangent": Vector2.RIGHT, "half": 6.0},     # Far inner-right horizontal wall.
	{"id": 6, "label": Vector2(127.7, 51.0), "tangent": Vector2.RIGHT, "half": 6.0},    # Far local-right horizontal wall.
	{"id": 7, "label": Vector2(9.4, 67.9), "tangent": Vector2.DOWN, "half": 6.0},       # Left middle vertical wall.
	{"id": 8, "label": Vector2(71.0, 60.9), "tangent": Vector2(1.0, 0.5), "half": 6.0}, # Inner-left middle diagonal wall.
	{"id": 9, "label": Vector2(124.0, 57.9), "tangent": Vector2(1.0, 0.5), "half": 6.0},# Inner-right middle diagonal wall.
	{"id": 10, "label": Vector2(36.7, 72.7), "tangent": Vector2.RIGHT, "half": 7.0},    # Left middle horizontal wall.
	{"id": 11, "label": Vector2(116.3, 63.9), "tangent": Vector2.RIGHT, "half": 7.0},   # Center middle horizontal wall.
	{"id": 12, "label": Vector2(159.0, 59.9), "tangent": Vector2.RIGHT, "half": 6.0},   # Right middle horizontal wall.
	{"id": 13, "label": Vector2(99.4, 77.6), "tangent": Vector2(1.0, 0.5), "half": 8.0},# Near inner-left diagonal wall.
	{"id": 14, "label": Vector2(159.0, 66.7), "tangent": Vector2.RIGHT, "half": 6.0},   # Near inner-right horizontal wall.
	{"id": 15, "label": Vector2(46.3, 102.1), "tangent": Vector2(1.0, -0.5), "half": 10.0}, # Near left floor diagonal.
	{"id": 16, "label": Vector2(152.3, 83.3), "tangent": Vector2.RIGHT, "half": 8.0},   # Near right horizontal wall.
	{"id": 17, "label": Vector2(147.4, 103.9), "tangent": Vector2(1.0, 0.5), "half": 10.0}, # Near right floor diagonal.
]                                                                                           # Close the authored 22-degree player-view guide.
const TURN_66_PLAYER_SLOT_GUIDE := [                                                        # Copy the player-view positions from Grid_Turn66_NE.png in 160x120 playfield pixels.
	{"id": 1, "label": Vector2(78.6, 47.0), "tangent": Vector2.RIGHT, "half": 6.0},     # Far inner-left horizontal wall.
	{"id": 2, "label": Vector2(116.0, 48.4), "tangent": Vector2.RIGHT, "half": 6.0},    # Far inner-right horizontal wall.
	{"id": 3, "label": Vector2(46.3, 49.4), "tangent": Vector2.DOWN, "half": 5.0},      # Far-right vertical wall.
	{"id": 4, "label": Vector2(87.1, 54.0), "tangent": Vector2.RIGHT, "half": 6.0},     # Upper-right middle wall.
	{"id": 5, "label": Vector2(137.7, 56.0), "tangent": Vector2.RIGHT, "half": 6.0},    # Lower-right middle wall.
	{"id": 6, "label": Vector2(160.0, 56.7), "tangent": Vector2.DOWN, "half": 6.0},     # Nearest right vertical wall.
	{"id": 7, "label": Vector2(46.4, 57.9), "tangent": Vector2.RIGHT, "half": 6.0},     # Upper center-right horizontal wall.
	{"id": 8, "label": Vector2(101.0, 59.1), "tangent": Vector2.RIGHT, "half": 6.0},    # Middle center-right horizontal wall.
	{"id": 9, "label": Vector2(159.1, 66.7), "tangent": Vector2.DOWN, "half": 6.0},     # Lower center-right horizontal wall.
	{"id": 10, "label": Vector2(12.3, 58.4), "tangent": Vector2.DOWN, "half": 6.0},     # Far center vertical wall.
	{"id": 11, "label": Vector2(52.6, 64.4), "tangent": Vector2.DOWN, "half": 7.0},     # Upper center vertical wall.
	{"id": 12, "label": Vector2(130.3, 70.7), "tangent": Vector2.RIGHT, "half": 7.0},   # Lower center vertical wall.
	{"id": 13, "label": Vector2(13.1, 67.0), "tangent": Vector2.RIGHT, "half": 6.0},    # Upper inner horizontal wall.
	{"id": 14, "label": Vector2(66.6, 76.7), "tangent": Vector2(1.0, -0.5), "half": 8.0}, # Middle inner diagonal wall.
	{"id": 15, "label": Vector2(22.4, 85.3), "tangent": Vector2(1.0, 0.5), "half": 9.0}, # Upper inner vertical wall.
	{"id": 16, "label": Vector2(120.9, 100.1), "tangent": Vector2(1.0, 0.5), "half": 10.0}, # Lower inner floor diagonal.
	{"id": 17, "label": Vector2(22.6, 103.0), "tangent": Vector2(1.0, -0.5), "half": 10.0}, # Nearest left floor diagonal.
]                                                                                           # Close the authored 66-degree player-view guide.
const TURN_45_DIAGNOSTIC_SLOT_EDGES := [                                                    # Store each 45-degree slot as a unique grid-edge in local turn-space u/v coordinates.
	{"id": 3, "a": Vector2(1.0, 2.0), "b": Vector2(2.0, 2.0)},                                 # Map the far local-left horizontal slot from the corrected guide.
	{"id": 1, "a": Vector2(2.0, 2.0), "b": Vector2(3.0, 2.0)},                                 # Map the far inner-left horizontal slot from the corrected guide.
	{"id": 2, "a": Vector2(3.0, 2.0), "b": Vector2(3.0, 1.0)},                                 # Map the far inner-right vertical slot from the corrected guide.
	{"id": 6, "a": Vector2(3.0, 1.0), "b": Vector2(3.0, 0.0)},                                 # Map the far local-right vertical slot from the corrected guide.
	{"id": 7, "a": Vector2(1.0, 2.0), "b": Vector2(1.0, 1.0)},                                 # Map the second-row local-left vertical slot from the corrected guide.
	{"id": 4, "a": Vector2(2.0, 2.0), "b": Vector2(2.0, 1.0)},                                 # Map the second-row inner-left vertical slot from the corrected guide.
	{"id": 5, "a": Vector2(2.0, 1.0), "b": Vector2(3.0, 1.0)},                                 # Map the second-row inner-right horizontal slot from the corrected guide.
	{"id": 10, "a": Vector2(2.0, 0.0), "b": Vector2(3.0, 0.0)},                                # Map the second-row local-right horizontal slot from the corrected guide.
	{"id": 11, "a": Vector2(0.0, 1.0), "b": Vector2(1.0, 1.0)},                                # Map the third-row local-left horizontal slot from the corrected guide.
	{"id": 8, "a": Vector2(1.0, 1.0), "b": Vector2(2.0, 1.0)},                                 # Map the third-row inner-left horizontal slot from the corrected guide.
	{"id": 9, "a": Vector2(2.0, 1.0), "b": Vector2(2.0, 0.0)},                                 # Map the third-row inner-right vertical slot from the corrected guide.
	{"id": 14, "a": Vector2(2.0, 0.0), "b": Vector2(2.0, -1.0)},                               # Map the third-row local-right vertical slot from the corrected guide.
	{"id": 15, "a": Vector2(0.0, 0.0), "b": Vector2(1.0, 0.0)},                                # Map the closest local-left horizontal slot from the corrected guide.
	{"id": 12, "a": Vector2(1.0, 1.0), "b": Vector2(1.0, 0.0)},                                # Map the closest inner-left vertical slot from the corrected guide.
	{"id": 13, "a": Vector2(1.0, 0.0), "b": Vector2(2.0, 0.0)},                                # Map the closest inner-right horizontal slot from the corrected guide.
	{"id": 16, "a": Vector2(1.0, 0.0), "b": Vector2(1.0, -1.0)},                               # Map the closest local-right vertical slot from the corrected guide.
]                                                                                           # Close the corrected 45-degree source-map audit edge table.
const TURN_22_DIAGNOSTIC_SLOT_EDGES := [                                                    # Store the independent 17-slot Grid_Turn22_NE graph.
	{"id": 1, "a": Vector2(1, 3), "b": Vector2(1, 2)},                                  # Slot 01: far inner-left vertical edge.
	{"id": 2, "a": Vector2(2, 3), "b": Vector2(2, 2)},                                  # Slot 02: far inner-right vertical edge.
	{"id": 3, "a": Vector2(-1, 2), "b": Vector2(0, 2)},                                 # Slot 03: far left horizontal edge.
	{"id": 4, "a": Vector2(0, 2), "b": Vector2(1, 2)},                                  # Slot 04: far inner-left horizontal edge.
	{"id": 5, "a": Vector2(1, 2), "b": Vector2(2, 2)},                                  # Slot 05: far inner-right horizontal edge.
	{"id": 6, "a": Vector2(2, 2), "b": Vector2(3, 2)},                                  # Slot 06: far right horizontal edge.
	{"id": 7, "a": Vector2(0, 2), "b": Vector2(0, 1)},                                  # Slot 07: left middle vertical edge.
	{"id": 8, "a": Vector2(1, 2), "b": Vector2(1, 1)},                                  # Slot 08: inner-left middle vertical edge.
	{"id": 9, "a": Vector2(2, 2), "b": Vector2(2, 1)},                                  # Slot 09: inner-right middle vertical edge.
	{"id": 10, "a": Vector2(0, 1), "b": Vector2(1, 1)},                                 # Slot 10: left middle horizontal edge.
	{"id": 11, "a": Vector2(1, 1), "b": Vector2(2, 1)},                                 # Slot 11: center middle horizontal edge.
	{"id": 12, "a": Vector2(2, 1), "b": Vector2(3, 1)},                                 # Slot 12: right middle horizontal edge.
	{"id": 13, "a": Vector2(1, 1), "b": Vector2(1, 0)},                                 # Slot 13: near inner-left vertical edge.
	{"id": 14, "a": Vector2(2, 1), "b": Vector2(2, 0)},                                 # Slot 14: near inner-right vertical edge.
	{"id": 15, "a": Vector2(0, 0), "b": Vector2(1, 0)},                                 # Slot 15: near left horizontal edge.
	{"id": 16, "a": Vector2(1, 0), "b": Vector2(2, 0)},                                 # Slot 16: near center horizontal edge.
	{"id": 17, "a": Vector2(1, 0), "b": Vector2(1, -1)},                                # Slot 17: closest inner-left vertical edge.
]                                                                                           # Close the authored 22-degree source-map graph.
const TURN_66_DIAGNOSTIC_SLOT_EDGES := [                                                    # Store the independent 17-slot Grid_Turn66_NE graph.
	{"id": 1, "a": Vector2(3, 1), "b": Vector2(4, 1)},                                  # Slot 01: upper-right horizontal edge.
	{"id": 2, "a": Vector2(3, 0), "b": Vector2(4, 0)},                                  # Slot 02: middle-right horizontal edge.
	{"id": 3, "a": Vector2(3, 2), "b": Vector2(3, 1)},                                  # Slot 03: far-right vertical edge.
	{"id": 4, "a": Vector2(3, 1), "b": Vector2(3, 0)},                                  # Slot 04: upper-right middle vertical edge.
	{"id": 5, "a": Vector2(3, 0), "b": Vector2(3, -1)},                                 # Slot 05: lower-right middle vertical edge.
	{"id": 6, "a": Vector2(3, -1), "b": Vector2(3, -2)},                                # Slot 06: nearest right vertical edge.
	{"id": 7, "a": Vector2(2, 1), "b": Vector2(3, 1)},                                  # Slot 07: upper center-right horizontal edge.
	{"id": 8, "a": Vector2(2, 0), "b": Vector2(3, 0)},                                  # Slot 08: middle center-right horizontal edge.
	{"id": 9, "a": Vector2(2, -1), "b": Vector2(3, -1)},                                # Slot 09: lower center-right horizontal edge.
	{"id": 10, "a": Vector2(2, 2), "b": Vector2(2, 1)},                                 # Slot 10: far center vertical edge.
	{"id": 11, "a": Vector2(2, 1), "b": Vector2(2, 0)},                                 # Slot 11: upper center vertical edge.
	{"id": 12, "a": Vector2(2, 0), "b": Vector2(2, -1)},                                # Slot 12: lower center vertical edge.
	{"id": 13, "a": Vector2(1, 1), "b": Vector2(2, 1)},                                 # Slot 13: upper inner horizontal edge.
	{"id": 14, "a": Vector2(1, 0), "b": Vector2(2, 0)},                                 # Slot 14: middle inner horizontal edge.
	{"id": 15, "a": Vector2(1, 1), "b": Vector2(1, 0)},                                 # Slot 15: upper inner vertical edge.
	{"id": 16, "a": Vector2(1, 0), "b": Vector2(1, -1)},                                # Slot 16: lower inner vertical edge.
	{"id": 17, "a": Vector2(0, 0), "b": Vector2(1, 0)},                                 # Slot 17: nearest left horizontal edge.
]                                                                                           # Close the authored 66-degree source-map graph.
const FWD_1_DIAGNOSTIC_SLOT_EDGES := [                                                      # Store the authored first forward-frame graph in camera-local grid space.
	{"id": 1, "a": Vector2(-0.5, 3.96), "b": Vector2(0.5, 3.96), "draw": 10},          # Far center horizontal edge.
	{"id": 2, "a": Vector2(-0.5, 3.96), "b": Vector2(-0.5, 2.96), "draw": 11},        # Far inner-left vertical edge.
	{"id": 3, "a": Vector2(0.5, 3.96), "b": Vector2(0.5, 2.96), "draw": 12},          # Far inner-right vertical edge.
	{"id": 4, "a": Vector2(-1.5, 2.96), "b": Vector2(-0.5, 2.96), "draw": 20},        # Upper outer-left horizontal edge.
	{"id": 5, "a": Vector2(-0.5, 2.96), "b": Vector2(0.5, 2.96), "draw": 21},         # Upper center horizontal edge.
	{"id": 6, "a": Vector2(0.5, 2.96), "b": Vector2(1.5, 2.96), "draw": 22},          # Upper outer-right horizontal edge.
	{"id": 7, "a": Vector2(-1.5, 2.96), "b": Vector2(-1.5, 1.96), "draw": 30},        # Upper outer-left vertical edge.
	{"id": 8, "a": Vector2(-0.5, 2.96), "b": Vector2(-0.5, 1.96), "draw": 31},        # Upper inner-left vertical edge.
	{"id": 9, "a": Vector2(0.5, 2.96), "b": Vector2(0.5, 1.96), "draw": 32},          # Upper inner-right vertical edge.
	{"id": 10, "a": Vector2(1.5, 2.96), "b": Vector2(1.5, 1.96), "draw": 33},         # Upper outer-right vertical edge.
	{"id": 11, "a": Vector2(-1.5, 1.96), "b": Vector2(-0.5, 1.96), "draw": 40},       # Middle outer-left horizontal edge.
	{"id": 12, "a": Vector2(-0.5, 1.96), "b": Vector2(0.5, 1.96), "draw": 41},        # Middle center horizontal edge.
	{"id": 13, "a": Vector2(0.5, 1.96), "b": Vector2(1.5, 1.96), "draw": 42},         # Middle outer-right horizontal edge.
	{"id": 14, "a": Vector2(-0.5, 1.96), "b": Vector2(-0.5, 0.96), "draw": 50},       # Lower inner-left vertical edge.
	{"id": 15, "a": Vector2(0.5, 1.96), "b": Vector2(0.5, 0.96), "draw": 51},         # Lower inner-right vertical edge.
	{"id": 16, "a": Vector2(-1.5, 0.96), "b": Vector2(-0.5, 0.96), "draw": 60},       # Near left horizontal edge.
	{"id": 17, "a": Vector2(-0.5, 0.96), "b": Vector2(0.5, 0.96), "draw": 61},        # Near center/front horizontal edge.
	{"id": 18, "a": Vector2(0.5, 0.96), "b": Vector2(1.5, 0.96), "draw": 62},         # Near right horizontal edge.
	{"id": 19, "a": Vector2(-0.5, 0.96), "b": Vector2(-0.5, -0.04), "draw": 70},      # Closest left inner vertical continuation: 02 -> 08 -> 14 -> 19.
	{"id": 20, "a": Vector2(0.5, 0.96), "b": Vector2(0.5, -0.04), "draw": 71},        # Closest right inner vertical continuation: 03 -> 09 -> 15 -> 20.
]                                                                                           # Keep Fwd 1 independent of cardinal and turn graph data.
const FWD_2_DIAGNOSTIC_SLOT_EDGES := [                                                      # Store the authored second forward-frame graph in camera-local grid space.
	{"id": 1, "a": Vector2(-0.5, 4.96), "b": Vector2(-0.5, 3.96), "draw": 10},        # Far left inner vertical edge: 01 -> 07 -> 14 -> 20 -> 25.
	{"id": 2, "a": Vector2(0.5, 4.96), "b": Vector2(0.5, 3.96), "draw": 11},          # Far right inner vertical edge: 02 -> 08 -> 15 -> 21 -> 26.
	{"id": 3, "a": Vector2(-1.5, 3.96), "b": Vector2(-0.5, 3.96), "draw": 20},        # Far outer-left horizontal edge.
	{"id": 4, "a": Vector2(-0.5, 3.96), "b": Vector2(0.5, 3.96), "draw": 21},         # Far center horizontal edge.
	{"id": 5, "a": Vector2(0.5, 3.96), "b": Vector2(1.5, 3.96), "draw": 22},          # Far outer-right horizontal edge.
	{"id": 6, "a": Vector2(-1.5, 3.96), "b": Vector2(-1.5, 2.96), "draw": 30},        # Far outer-left vertical edge.
	{"id": 7, "a": Vector2(-0.5, 3.96), "b": Vector2(-0.5, 2.96), "draw": 31},        # Far inner-left vertical edge.
	{"id": 8, "a": Vector2(0.5, 3.96), "b": Vector2(0.5, 2.96), "draw": 32},          # Far inner-right vertical edge.
	{"id": 9, "a": Vector2(1.5, 3.96), "b": Vector2(1.5, 2.96), "draw": 33},          # Far outer-right vertical edge.
	{"id": 10, "a": Vector2(-1.5, 2.96), "b": Vector2(-0.5, 2.96), "draw": 40},       # Upper outer-left horizontal edge.
	{"id": 11, "a": Vector2(-0.5, 2.96), "b": Vector2(0.5, 2.96), "draw": 41},        # Upper center horizontal edge.
	{"id": 12, "a": Vector2(0.5, 2.96), "b": Vector2(1.5, 2.96), "draw": 42},         # Upper outer-right horizontal edge.
	{"id": 13, "a": Vector2(-1.5, 2.96), "b": Vector2(-1.5, 1.96), "draw": 50},       # Upper outer-left vertical edge.
	{"id": 14, "a": Vector2(-0.5, 2.96), "b": Vector2(-0.5, 1.96), "draw": 51},       # Upper inner-left vertical edge.
	{"id": 15, "a": Vector2(0.5, 2.96), "b": Vector2(0.5, 1.96), "draw": 52},         # Upper inner-right vertical edge.
	{"id": 16, "a": Vector2(1.5, 2.96), "b": Vector2(1.5, 1.96), "draw": 53},         # Upper outer-right vertical edge.
	{"id": 17, "a": Vector2(-1.5, 1.96), "b": Vector2(-0.5, 1.96), "draw": 60},       # Middle outer-left horizontal edge.
	{"id": 18, "a": Vector2(-0.5, 1.96), "b": Vector2(0.5, 1.96), "draw": 61},        # Middle center horizontal edge.
	{"id": 19, "a": Vector2(0.5, 1.96), "b": Vector2(1.5, 1.96), "draw": 62},         # Middle outer-right horizontal edge.
	{"id": 20, "a": Vector2(-0.5, 1.96), "b": Vector2(-0.5, 0.96), "draw": 70},       # Lower inner-left vertical edge.
	{"id": 21, "a": Vector2(0.5, 1.96), "b": Vector2(0.5, 0.96), "draw": 71},         # Lower inner-right vertical edge.
	{"id": 22, "a": Vector2(-1.5, 0.96), "b": Vector2(-0.5, 0.96), "draw": 80},       # Immediate front row, left segment.
	{"id": 23, "a": Vector2(-0.5, 0.96), "b": Vector2(0.5, 0.96), "draw": 81},        # Immediate front row, center segment.
	{"id": 24, "a": Vector2(0.5, 0.96), "b": Vector2(1.5, 0.96), "draw": 82},         # Immediate front row, right segment.
	{"id": 25, "a": Vector2(-0.5, 0.96), "b": Vector2(-0.5, -0.04), "draw": 90},      # Closest left side of the entered cell.
	{"id": 26, "a": Vector2(0.5, 0.96), "b": Vector2(0.5, -0.04), "draw": 91},        # Closest right side of the entered cell.
]                                                                                           # Keep Fwd 2 independent of cardinal and turn graph data.
const STRAFE_1_DIAGNOSTIC_SLOT_EDGES := [                                                   # Store the authored first side-transition graph in camera-local grid space.
	{"id": 1, "a": Vector2(-0.5, 4.96), "b": Vector2(-0.5, 3.96), "draw": 10},       # Far-left parallel wall four whole cells away: first member of 01 -> 08 -> 15 -> 21.
	{"id": 2, "a": Vector2(0.5, 4.96), "b": Vector2(0.5, 3.96), "draw": 11},         # Far-right parallel wall four whole cells away: first member of 02 -> 09 -> 16 -> 22.
	{"id": 3, "a": Vector2(1.5, 4.96), "b": Vector2(1.5, 3.96), "draw": 12},         # Third parallel wall four whole cells away: first member of 03 -> 10 -> 17.
	{"id": 4, "a": Vector2(-1.5, 3.96), "b": Vector2(-0.5, 3.96), "draw": 20},       # First perpendicular wall segment four cells away, shifted one cell player-right.
	{"id": 5, "a": Vector2(-0.5, 3.96), "b": Vector2(0.5, 3.96), "draw": 21},        # Second perpendicular wall segment four cells away, shifted one cell player-right.
	{"id": 6, "a": Vector2(0.5, 3.96), "b": Vector2(1.5, 3.96), "draw": 22},         # Third perpendicular wall segment four cells away, shifted one cell player-right.
	{"id": 7, "a": Vector2(1.5, 3.96), "b": Vector2(2.5, 3.96), "draw": 23},         # Fourth perpendicular wall segment four cells away, shifted one cell player-right.
	{"id": 8, "a": Vector2(-0.5, 3.96), "b": Vector2(-0.5, 2.96), "draw": 30},       # Left parallel wall three cells away.
	{"id": 9, "a": Vector2(0.5, 3.96), "b": Vector2(0.5, 2.96), "draw": 31},         # Right parallel wall three cells away.
	{"id": 10, "a": Vector2(1.5, 3.96), "b": Vector2(1.5, 2.96), "draw": 32},        # Third parallel wall three cells away: second member of 03 -> 10 -> 17.
	{"id": 11, "a": Vector2(-1.5, 2.96), "b": Vector2(-0.5, 2.96), "draw": 40},      # First perpendicular wall segment three cells away, shifted one cell player-right.
	{"id": 12, "a": Vector2(-0.5, 2.96), "b": Vector2(0.5, 2.96), "draw": 41},       # Second perpendicular wall segment three cells away, shifted one cell player-right.
	{"id": 13, "a": Vector2(0.5, 2.96), "b": Vector2(1.5, 2.96), "draw": 42},        # Third perpendicular wall segment three cells away, shifted one cell player-right.
	{"id": 14, "a": Vector2(1.5, 2.96), "b": Vector2(2.5, 2.96), "draw": 43},        # Fourth perpendicular wall segment three cells away, shifted one cell player-right.
	{"id": 15, "a": Vector2(-0.5, 2.96), "b": Vector2(-0.5, 1.96), "draw": 50},      # Left parallel wall two cells away.
	{"id": 16, "a": Vector2(0.5, 2.96), "b": Vector2(0.5, 1.96), "draw": 51},        # Right parallel wall two cells away.
	{"id": 17, "a": Vector2(1.5, 2.96), "b": Vector2(1.5, 1.96), "draw": 52},        # Third parallel wall two cells away: final member of 03 -> 10 -> 17.
	{"id": 18, "a": Vector2(-1.5, 1.96), "b": Vector2(-0.5, 1.96), "draw": 60},      # First perpendicular wall segment two cells away.
	{"id": 19, "a": Vector2(-0.5, 1.96), "b": Vector2(0.5, 1.96), "draw": 61},       # Second perpendicular wall segment two cells away.
	{"id": 20, "a": Vector2(0.5, 1.96), "b": Vector2(1.5, 1.96), "draw": 62},        # Third perpendicular wall segment two cells away.
	{"id": 21, "a": Vector2(-0.5, 1.96), "b": Vector2(-0.5, 0.96), "draw": 70},      # Near-left parallel wall one cell away: final member of 01 -> 08 -> 15 -> 21.
	{"id": 22, "a": Vector2(0.5, 1.96), "b": Vector2(0.5, 0.96), "draw": 71},        # Near-right parallel wall one cell away: final member of 02 -> 09 -> 16 -> 22.
	{"id": 23, "a": Vector2(-0.5, 0.96), "b": Vector2(0.5, 0.96), "draw": 80},       # Perpendicular wall at the shared edge of the current and right-adjacent cells, shifted one cell player-right.
	{"id": 24, "a": Vector2(0.5, 0.96), "b": Vector2(1.5, 0.96), "draw": 81},        # Perpendicular wall at the shared edge of the current and right-adjacent cells.
]                                                                                           # Keep Right 1 independent of Fwd, cardinal, and turn graph data.
const STRAFE_2_DIAGNOSTIC_SLOT_EDGES := [                                                   # Store the authored middle side-transition graph in camera-local grid space.
	{"id": 1, "a": Vector2(-0.5, 4.96), "b": Vector2(-0.5, 3.96), "draw": 10},       # First far parallel edge: first member of 01 -> 08 -> 15.
	{"id": 2, "a": Vector2(0.5, 4.96), "b": Vector2(0.5, 3.96), "draw": 11},         # Second far parallel edge: first member of 02 -> 09 -> 16 -> 20.
	{"id": 3, "a": Vector2(1.5, 4.96), "b": Vector2(1.5, 3.96), "draw": 12},         # Third far parallel edge: first member of 03 -> 10 -> 17.
	{"id": 4, "a": Vector2(-1.5, 3.96), "b": Vector2(-0.5, 3.96), "draw": 20},       # First four-cell perpendicular row edge.
	{"id": 5, "a": Vector2(-0.5, 3.96), "b": Vector2(0.5, 3.96), "draw": 21},        # Second four-cell perpendicular row edge.
	{"id": 6, "a": Vector2(0.5, 3.96), "b": Vector2(1.5, 3.96), "draw": 22},         # Third four-cell perpendicular row edge.
	{"id": 7, "a": Vector2(1.5, 3.96), "b": Vector2(2.5, 3.96), "draw": 23},         # Fourth four-cell perpendicular row edge.
	{"id": 8, "a": Vector2(-0.5, 3.96), "b": Vector2(-0.5, 2.96), "draw": 30},       # First three-cell parallel column continuation.
	{"id": 9, "a": Vector2(0.5, 3.96), "b": Vector2(0.5, 2.96), "draw": 31},         # Second three-cell parallel column continuation.
	{"id": 10, "a": Vector2(1.5, 3.96), "b": Vector2(1.5, 2.96), "draw": 32},        # Third three-cell parallel column continuation.
	{"id": 11, "a": Vector2(-1.5, 2.96), "b": Vector2(-0.5, 2.96), "draw": 40},      # First three-cell perpendicular row edge.
	{"id": 12, "a": Vector2(-0.5, 2.96), "b": Vector2(0.5, 2.96), "draw": 41},       # Second three-cell perpendicular row edge.
	{"id": 13, "a": Vector2(0.5, 2.96), "b": Vector2(1.5, 2.96), "draw": 42},        # Third three-cell perpendicular row edge.
	{"id": 14, "a": Vector2(1.5, 2.96), "b": Vector2(2.5, 2.96), "draw": 43},        # Fourth three-cell perpendicular row edge.
	{"id": 15, "a": Vector2(-0.5, 2.96), "b": Vector2(-0.5, 1.96), "draw": 50},      # First two-cell parallel column continuation.
	{"id": 16, "a": Vector2(0.5, 2.96), "b": Vector2(0.5, 1.96), "draw": 51},        # Second two-cell parallel column continuation.
	{"id": 17, "a": Vector2(1.5, 2.96), "b": Vector2(1.5, 1.96), "draw": 52},        # Third two-cell parallel column continuation.
	{"id": 18, "a": Vector2(-0.5, 1.96), "b": Vector2(0.5, 1.96), "draw": 60},       # First two-cell perpendicular row edge.
	{"id": 19, "a": Vector2(0.5, 1.96), "b": Vector2(1.5, 1.96), "draw": 61},        # Second two-cell perpendicular row edge.
	{"id": 20, "a": Vector2(0.5, 1.96), "b": Vector2(0.5, 0.96), "draw": 70},        # Final member of the 02 -> 09 -> 16 -> 20 parallel column.
	{"id": 21, "a": Vector2(-0.5, 0.96), "b": Vector2(0.5, 0.96), "draw": 80},       # Closest perpendicular row edge, parallel with 18/19, on the cell the player is leaving.
	{"id": 22, "a": Vector2(0.5, 0.96), "b": Vector2(1.5, 0.96), "draw": 81},        # Closest perpendicular row edge, parallel with 18/19, on the cell the player is entering.
]                                                                                           # Keep Right 2 independent of Right 1, Right 3, Fwd, cardinal, and turn graph data.
const STRAFE_3_DIAGNOSTIC_SLOT_EDGES := [                                                   # Store the authored final side-transition graph in camera-local grid space.
	{"id": 1, "a": Vector2(-0.5, 4.96), "b": Vector2(-0.5, 3.96), "draw": 10},       # First far parallel edge: first member of 01 -> 08 -> 15.
	{"id": 2, "a": Vector2(0.5, 4.96), "b": Vector2(0.5, 3.96), "draw": 11},         # Center parallel edge: first member of 02 -> 09 -> 16 -> 21.
	{"id": 3, "a": Vector2(1.5, 4.96), "b": Vector2(1.5, 3.96), "draw": 12},         # Right parallel edge: first member of 03 -> 10 -> 17 -> 22.
	{"id": 4, "a": Vector2(-1.5, 3.96), "b": Vector2(-0.5, 3.96), "draw": 20},       # First far perpendicular row edge.
	{"id": 5, "a": Vector2(-0.5, 3.96), "b": Vector2(0.5, 3.96), "draw": 21},        # Second far perpendicular row edge.
	{"id": 6, "a": Vector2(0.5, 3.96), "b": Vector2(1.5, 3.96), "draw": 22},         # Third far perpendicular row edge.
	{"id": 7, "a": Vector2(1.5, 3.96), "b": Vector2(2.5, 3.96), "draw": 23},         # Fourth far perpendicular row edge.
	{"id": 8, "a": Vector2(-0.5, 3.96), "b": Vector2(-0.5, 2.96), "draw": 30},       # First three-cell parallel column continuation.
	{"id": 9, "a": Vector2(0.5, 3.96), "b": Vector2(0.5, 2.96), "draw": 31},         # Center three-cell parallel column continuation.
	{"id": 10, "a": Vector2(1.5, 3.96), "b": Vector2(1.5, 2.96), "draw": 32},        # Right three-cell parallel column continuation.
	{"id": 11, "a": Vector2(-1.5, 2.96), "b": Vector2(-0.5, 2.96), "draw": 40},      # First three-cell perpendicular row edge.
	{"id": 12, "a": Vector2(-0.5, 2.96), "b": Vector2(0.5, 2.96), "draw": 41},       # Second three-cell perpendicular row edge.
	{"id": 13, "a": Vector2(0.5, 2.96), "b": Vector2(1.5, 2.96), "draw": 42},        # Third three-cell perpendicular row edge.
	{"id": 14, "a": Vector2(1.5, 2.96), "b": Vector2(2.5, 2.96), "draw": 43},        # Fourth three-cell perpendicular row edge.
	{"id": 15, "a": Vector2(-0.5, 2.96), "b": Vector2(-0.5, 1.96), "draw": 50},      # First near parallel column continuation.
	{"id": 16, "a": Vector2(0.5, 2.96), "b": Vector2(0.5, 1.96), "draw": 51},        # Center near parallel column continuation.
	{"id": 17, "a": Vector2(1.5, 2.96), "b": Vector2(1.5, 1.96), "draw": 52},        # Right near parallel column continuation.
	{"id": 18, "a": Vector2(-0.5, 1.96), "b": Vector2(0.5, 1.96), "draw": 60},       # First near perpendicular row edge, shifted one cell player-right with the authored Right 3 grid.
	{"id": 19, "a": Vector2(0.5, 1.96), "b": Vector2(1.5, 1.96), "draw": 61},        # Second near perpendicular row edge, shifted one cell player-right with the authored Right 3 grid.
	{"id": 20, "a": Vector2(1.5, 1.96), "b": Vector2(2.5, 1.96), "draw": 62},        # Third near perpendicular row edge, shifted one cell player-right with the authored Right 3 grid.
	{"id": 21, "a": Vector2(0.5, 1.96), "b": Vector2(0.5, 0.96), "draw": 70},        # Final center parallel edge: 02 -> 09 -> 16 -> 21.
	{"id": 22, "a": Vector2(1.5, 1.96), "b": Vector2(1.5, 0.96), "draw": 71},        # Final right parallel edge: 03 -> 10 -> 17 -> 22.
	{"id": 23, "a": Vector2(-0.5, 0.96), "b": Vector2(0.5, 0.96), "draw": 80},       # Closest first perpendicular row edge, below 05 -> 12 -> 19.
	{"id": 24, "a": Vector2(0.5, 0.96), "b": Vector2(1.5, 0.96), "draw": 81},        # Closest second perpendicular row edge, below 06 -> 13 -> 20.
]                                                                                           # Keep Right 3 independent of all earlier transition, turn, and cardinal graph data.
const FWD_GRAPH_FORWARD_OFFSET := Vector2(0.0, 1.0)                                        # Both Fwd frames sample one cell ahead toward the destination camera position.
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

# Authored straight-view audit labels copied from StraightViewGraph_N_S_E_W_Blue.png.
# "screen" is the invariant 160x120 player view; "map" is relative to the current cell's fixed center.
const CARDINAL_SLOT_GUIDE := [
	{"id": 1, "screen": Vector2(66, 42), "map": Vector2(0.0, -3.5)},
	{"id": 2, "screen": Vector2(92, 42), "map": Vector2(0.5, -3.5)},
	{"id": 3, "screen": Vector2(49, 45), "map": Vector2(-1.0, -3.0)},
	{"id": 4, "screen": Vector2(78, 45), "map": Vector2(0.0, -3.0)},
	{"id": 5, "screen": Vector2(111, 45), "map": Vector2(1.0, -3.0)},
	{"id": 6, "screen": Vector2(26, 50), "map": Vector2(-1.5, -2.5)},
	{"id": 7, "screen": Vector2(60, 50), "map": Vector2(-0.5, -2.5)},
	{"id": 8, "screen": Vector2(100, 50), "map": Vector2(0.5, -2.5)},
	{"id": 9, "screen": Vector2(138, 52), "map": Vector2(1.5, -2.5)},
	{"id": 10, "screen": Vector2(3, 54), "map": Vector2(-2.3, -2.0)},
	{"id": 11, "screen": Vector2(35, 55), "map": Vector2(-1.0, -2.0)},
	{"id": 12, "screen": Vector2(80, 55), "map": Vector2(0.0, -2.0)},
	{"id": 13, "screen": Vector2(124, 55), "map": Vector2(1.0, -2.0)},
	{"id": 14, "screen": Vector2(157, 55), "map": Vector2(2.3, -2.0)},
	{"id": 15, "screen": Vector2(2, 61), "map": Vector2(-1.0, -1.5)},
	{"id": 16, "screen": Vector2(50, 63), "map": Vector2(0.0, -1.5)},
	{"id": 17, "screen": Vector2(110, 64), "map": Vector2(1.0, -1.5)},
	{"id": 18, "screen": Vector2(157, 61), "map": Vector2(2.0, -1.5)},
	{"id": 19, "screen": Vector2(16, 74), "map": Vector2(-1.0, -1.0)},
	{"id": 20, "screen": Vector2(80, 74), "map": Vector2(0.0, -1.0)},
	{"id": 21, "screen": Vector2(141, 74), "map": Vector2(1.0, -1.0)},
	{"id": 22, "screen": Vector2(25, 88), "map": Vector2(-0.5, -0.5)},
	{"id": 23, "screen": Vector2(130, 88), "map": Vector2(0.5, -0.5)},
	{"id": 24, "screen": Vector2(3, 96), "map": Vector2(-1.0, -0.25)},
	{"id": 25, "screen": Vector2(80, 96), "map": Vector2(0.0, -0.25)},
	{"id": 26, "screen": Vector2(155, 96), "map": Vector2(1.0, -0.25)},
	{"id": 27, "screen": Vector2(5, 108), "map": Vector2(-0.4, 0.0)},
	{"id": 28, "screen": Vector2(153, 108), "map": Vector2(0.4, 0.0)},
]

# Fixed player-camera grid copied from the straight-view reference. It never rotates with cardinal facing.
const CARDINAL_PLAYER_GRID_LINES := [
	[Vector2(0, 58), Vector2(32, 46)], [Vector2(32, 46), Vector2(64, 44)], [Vector2(64, 44), Vector2(96, 44)], [Vector2(96, 44), Vector2(128, 46)], [Vector2(128, 46), Vector2(160, 58)],
	[Vector2(0, 56), Vector2(160, 56)], [Vector2(64, 44), Vector2(40, 70)], [Vector2(96, 44), Vector2(120, 70)],
	[Vector2(40, 70), Vector2(0, 112)], [Vector2(120, 70), Vector2(160, 112)], [Vector2(0, 70), Vector2(160, 70)], [Vector2(0, 96), Vector2(160, 96)],
]

# Same guide's top-down world diagram, expressed relative to the fixed center of the player cell.
const CARDINAL_TOPDOWN_GRID_LINES := [
	[Vector2(-0.8, -3.9), Vector2(0.8, -3.9)], [Vector2(-1.7, -3.0), Vector2(1.7, -3.0)], [Vector2(-2.5, -2.5), Vector2(2.5, -2.5)],
	[Vector2(-2.5, -2.0), Vector2(2.5, -2.0)], [Vector2(-2.0, -1.5), Vector2(2.0, -1.5)], [Vector2(-1.0, -1.0), Vector2(1.0, -1.0)], [Vector2(-0.5, -0.5), Vector2(0.5, -0.5)], [Vector2(-1.0, -0.25), Vector2(1.0, -0.25)],
	[Vector2(-1.7, -3.0), Vector2(-1.7, -1.5)], [Vector2(-0.8, -3.9), Vector2(-0.8, 0.0)], [Vector2(0.8, -3.9), Vector2(0.8, 0.0)], [Vector2(1.7, -3.0), Vector2(1.7, -1.5)], [Vector2(-0.4, 0.0), Vector2(0.4, 0.0)],
]

# Canonical cardinal source-grid segments. Each blue segment owns exactly one 01..28 art-slot label.
const CARDINAL_SLOT_TOPOLOGY := [
	{"id": 1, "a": Vector2(-0.5, -4.0), "b": Vector2(-0.5, -3.5)}, {"id": 2, "a": Vector2(0.5, -4.0), "b": Vector2(0.5, -3.5)},
	{"id": 3, "a": Vector2(-1.5, -3.5), "b": Vector2(-0.5, -3.5)}, {"id": 4, "a": Vector2(-0.5, -3.5), "b": Vector2(0.5, -3.5)}, {"id": 5, "a": Vector2(0.5, -3.5), "b": Vector2(1.5, -3.5)},
	{"id": 6, "a": Vector2(-1.5, -3.5), "b": Vector2(-1.5, -2.5)}, {"id": 7, "a": Vector2(-0.5, -3.5), "b": Vector2(-0.5, -2.5)}, {"id": 8, "a": Vector2(0.5, -3.5), "b": Vector2(0.5, -2.5)}, {"id": 9, "a": Vector2(1.5, -3.5), "b": Vector2(1.5, -2.5)},
	{"id": 10, "a": Vector2(-2.5, -2.5), "b": Vector2(-1.5, -2.5)}, {"id": 11, "a": Vector2(-1.5, -2.5), "b": Vector2(-0.5, -2.5)}, {"id": 12, "a": Vector2(-0.5, -2.5), "b": Vector2(0.5, -2.5)}, {"id": 13, "a": Vector2(0.5, -2.5), "b": Vector2(1.5, -2.5)}, {"id": 14, "a": Vector2(1.5, -2.5), "b": Vector2(2.5, -2.5)},
	{"id": 15, "a": Vector2(-1.5, -2.5), "b": Vector2(-1.5, -1.5)}, {"id": 16, "a": Vector2(-0.5, -2.5), "b": Vector2(-0.5, -1.5)}, {"id": 17, "a": Vector2(0.5, -2.5), "b": Vector2(0.5, -1.5)}, {"id": 18, "a": Vector2(1.5, -2.5), "b": Vector2(1.5, -1.5)},
	{"id": 19, "a": Vector2(-1.5, -1.5), "b": Vector2(-0.5, -1.5)}, {"id": 20, "a": Vector2(-0.5, -1.5), "b": Vector2(0.5, -1.5)}, {"id": 21, "a": Vector2(0.5, -1.5), "b": Vector2(1.5, -1.5)},
	{"id": 22, "a": Vector2(-0.5, -1.5), "b": Vector2(-0.5, -0.5)}, {"id": 23, "a": Vector2(0.5, -1.5), "b": Vector2(0.5, -0.5)},
	{"id": 24, "a": Vector2(-1.5, -0.5), "b": Vector2(-0.5, -0.5)}, {"id": 25, "a": Vector2(-0.5, -0.5), "b": Vector2(0.5, -0.5)}, {"id": 26, "a": Vector2(0.5, -0.5), "b": Vector2(1.5, -0.5)},
	{"id": 27, "a": Vector2(-0.5, -0.5), "b": Vector2(-0.5, 0.0)}, {"id": 28, "a": Vector2(0.5, -0.5), "b": Vector2(0.5, 0.0)},
]

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

const TURN_45_WALL_SLOTS := [                                                               # Map 45-degree wall ids to row/lane buckets from Wall_Grid_45.png.
	{"id": 1, "row": 0, "lane": -1, "draw": 10},                                               # Draw the far upper-left 45-degree wall overlay first.
	{"id": 2, "row": 0, "lane": 1, "draw": 11},                                                # Draw the far upper-right 45-degree wall overlay after its matching left piece.
	{"id": 3, "row": 1, "lane": -2, "draw": 20},                                               # Draw the next-row outer-left 45-degree wall overlay.
	{"id": 4, "row": 1, "lane": -1, "draw": 21},                                               # Draw the next-row inner-left 45-degree wall overlay.
	{"id": 5, "row": 1, "lane": 1, "draw": 22},                                                # Draw the next-row inner-right 45-degree wall overlay.
	{"id": 6, "row": 1, "lane": 2, "draw": 23},                                                # Draw the next-row outer-right 45-degree wall overlay.
	{"id": 7, "row": 2, "lane": -2, "draw": 30},                                               # Draw the middle-row outer-left 45-degree wall overlay.
	{"id": 8, "row": 2, "lane": -1, "draw": 31},                                               # Draw the middle-row inner-left 45-degree wall overlay.
	{"id": 9, "row": 2, "lane": 1, "draw": 32},                                                # Draw the middle-row inner-right 45-degree wall overlay.
	{"id": 10, "row": 2, "lane": 2, "draw": 33},                                               # Draw the middle-row outer-right 45-degree wall overlay.
	{"id": 11, "row": 3, "lane": -2, "draw": 40},                                              # Draw the near-row outer-left 45-degree wall overlay.
	{"id": 12, "row": 3, "lane": -1, "draw": 41},                                              # Draw the near-row inner-left 45-degree wall overlay.
	{"id": 13, "row": 3, "lane": 1, "draw": 42},                                               # Draw the near-row inner-right 45-degree wall overlay.
	{"id": 14, "row": 3, "lane": 2, "draw": 43},                                               # Draw the near-row outer-right 45-degree wall overlay.
	{"id": 15, "row": 4, "lane": -1, "draw": 50},                                              # Draw the closest left 45-degree wall overlay.
	{"id": 16, "row": 4, "lane": 1, "draw": 51},                                               # Draw the closest right 45-degree wall overlay.
]                                                                                           # Close the 45-degree wall slot table.

const TURN_45_EDGE_ANY := "any"                                                             # Allow a 45-degree footprint to accept either physical map edge orientation.
const TURN_45_EDGE_VERTICAL := "vertical"                                                    # Mark a footprint that expects a north/south source-map wall edge.
const TURN_45_EDGE_HORIZONTAL := "horizontal"                                                # Mark a footprint that expects an east/west source-map wall edge.
const TURN_45_CLOSE_ROW_DEPTH_MAX := 1.05                                                     # Reserve the nearest halfway-turn depth band for slots 15 and 16 from Wall_Grid_45.png.
const TURN_45_AXIS_MISMATCH_SCORE_PENALTY := 0.35                                            # Legacy score value kept for reference; the 45-degree mapper now rejects mismatched wall families.
const TURN_45_SLOT_FOOTPRINTS := [                                                          # Calibrate 45-degree wall ids as camera-local side/depth footprints.
	{"id": 1, "axis": TURN_45_EDGE_ANY, "center": Vector2(-0.35, 3.95), "radius": Vector2(0.55, 0.60)}, # Match the far upper-left 45-degree wall sample.
	{"id": 2, "axis": TURN_45_EDGE_ANY, "center": Vector2(0.35, 3.95), "radius": Vector2(0.55, 0.60)}, # Match the far upper-right 45-degree wall sample.
	{"id": 3, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-1.75, 1.88), "radius": Vector2(0.45, 0.60)}, # Match the far outer-left vertical branch.
	{"id": 4, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-0.35, 3.30), "radius": Vector2(0.55, 0.70)}, # Match the far inner-left vertical branch.
	{"id": 5, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(0.35, 2.60), "radius": Vector2(0.55, 0.70)}, # Match the far inner-right vertical branch.
	{"id": 6, "axis": TURN_45_EDGE_ANY, "center": Vector2(1.75, 3.30), "radius": Vector2(0.55, 0.75)}, # Match the far outer-right branch near the horizon.
	{"id": 7, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-1.05, 1.88), "radius": Vector2(0.50, 0.60)}, # Match the middle outer-left vertical branch.
	{"id": 7, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-1.75, 2.60), "radius": Vector2(0.50, 0.70)}, # Match the same left branch one grid segment farther out.
	{"id": 8, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-0.35, 1.88), "radius": Vector2(0.55, 0.65)}, # Match the middle inner-left vertical branch.
	{"id": 9, "axis": TURN_45_EDGE_HORIZONTAL, "center": Vector2(1.05, 2.60), "radius": Vector2(0.65, 0.70)}, # Match the middle right horizontal branch.
	{"id": 9, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(0.35, 2.23), "radius": Vector2(0.45, 0.35)}, # Match the visible right-side branch that should step from slot 5 to slot 9.
	{"id": 10, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(1.05, 1.88), "radius": Vector2(0.55, 0.65)}, # Match the middle outer-right vertical branch.
	{"id": 10, "axis": TURN_45_EDGE_HORIZONTAL, "center": Vector2(1.75, 3.30), "radius": Vector2(0.55, 0.75)}, # Match the far outer-right horizontal continuation.
	{"id": 11, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-1.05, 1.17), "radius": Vector2(0.55, 0.55)}, # Match the near outer-left vertical branch.
	{"id": 12, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-0.35, 1.17), "radius": Vector2(0.55, 0.55)}, # Match the near inner-left vertical branch.
	{"id": 12, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(-0.34, 1.51), "radius": Vector2(0.35, 0.30)}, # Match the left-center floor-grid branch that should step from slot 8 to slot 12.
	{"id": 13, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(0.35, 1.70), "radius": Vector2(0.55, 0.45)}, # Match the near inner-right vertical branch when it sits beyond wall 16.
	{"id": 14, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(1.05, 1.17), "radius": Vector2(0.55, 0.55)}, # Match the near outer-right vertical branch.
	{"id": 14, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(0.82, 1.76), "radius": Vector2(0.35, 0.35)}, # Match the visible right-side branch that should step from slot 10 to slot 14.
	{"id": 15, "axis": TURN_45_EDGE_ANY, "center": Vector2(-0.35, 0.46), "radius": Vector2(0.55, 0.55)}, # Match the closest left 45-degree wall sample.
	{"id": 16, "axis": TURN_45_EDGE_VERTICAL, "center": Vector2(0.35, 0.80), "radius": Vector2(0.55, 0.85)}, # Match the closest right 45-degree wall sample.
]                                                                                           # Close the calibrated 45-degree footprint table.
const TURN_45_OCCLUSION_BRANCHES := [                                                       # Keep 45-degree occlusion as data ordered from near to far.
	[15, 11, 7, 3],                                                                            # Describe the outer-left branch from closest to farthest.
	[12, 8, 4, 1],                                                                             # Describe the inner-left branch from closest to farthest.
	[13, 9, 5, 2],                                                                             # Describe the inner-right branch from closest to farthest.
	[16, 14, 10, 6],                                                                           # Describe the outer-right branch from closest to farthest.
]                                                                                           # Close the 45-degree occlusion branch table.

const AUDIT_START_ENABLED := true                                                           # Force the current startup into the slot-grid correction frame while this diagnostic pass is active.
const AUDIT_P1_CELL := Vector2i(0, MAP_HEIGHT - 1)                                          # Match the left guide panel's player-one source-map cell.
const AUDIT_P1_FACING := 0                                                                   # Point player one north before applying the temporary 45-degree turn.
const AUDIT_P1_TURN_45_DIRECTION := 1                                                       # Stop player one on the NE halfway-turn audit view.
const AUDIT_P1_LOCAL_POSITION := Vector2(0.63, 0.84)                                        # Match the player-one local position shown in gridCorrector.png.
const AUDIT_P2_CELL := Vector2i(0, MAP_HEIGHT - 1)                                          # Match the right guide panel's player-two source-map cell.
const AUDIT_P2_FACING := 0                                                                   # Keep player two on the cardinal north audit view.
const AUDIT_P2_TURN_45_DIRECTION := 0                                                       # Keep player two out of the halfway-turn view for the right guide panel.
const AUDIT_P2_LOCAL_POSITION := Vector2(0.37, 0.84)                                        # Match the player-two local position shown in gridCorrector.png.

@export_group("Movement Phases")                                                            # Group inspector controls for captured movement and turn phase playback.
@export var use_captured_transitions := false                                                # Snap movement/turns by default until the matching transition art is rebuilt.

@export_group("Diagnostics")                                                                # Group inspector toggles for temporary visual debugging tools.
@export var enable_3d_diagnostic := false                                                    # Keep the experimental 3D view disabled unless it is explicitly needed.
@export var show_top_down_source_overlay := true                                             # Show the 2D source-of-truth map overlay during wall/collision debugging.
@export var show_raycast_debug := false                                                      # Show individual visibility rays and their first-hit points on the top-down map.
@export_range(1, 15, 1) var debug_raycast_stride: int = 5                                    # Draw every Nth ray so the debug overlay stays readable.
@export var show_perspective_extents_overlay := false                                        # Show colored projected square extents over each 160x120 player view.
@export var show_slot_grid_debug := true                                                     # Show blue diagnostic slot numbers in the top-down and player-view grids.
@export var show_selected_wall_slot_debug := false                                           # Show the renderer-selected green wall-slot overlay only when comparing selection logic.
@export var render_wall_art := true                                                          # Let the debug menu hide only transparent wall artwork while retaining floor, collision, and source-map logic.

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
var turn_45_wall_textures: Dictionary = {}                                                  # Store the 16 numbered halfway-turn wall textures by wall id.
var turn_22_wall_textures: Dictionary = {}                                                  # Store the 17 numbered 22-degree turn wall textures by wall id.
var turn_66_wall_textures: Dictionary = {}                                                  # Store the 17 numbered 66-degree turn wall textures by wall id.
var fwd_1_wall_textures: Dictionary = {}                                                    # Store the 20 numbered first forward-frame wall textures by wall id.
var fwd_2_wall_textures: Dictionary = {}                                                    # Store the 26 numbered second forward-frame wall textures by wall id.
var right_1_wall_textures: Dictionary = {}                                                  # Store the 24 numbered first local-right strafe wall textures by wall id.
var right_2_wall_textures: Dictionary = {}                                                  # Store the 22 numbered second local-right strafe wall textures by wall id.
var right_3_wall_textures: Dictionary = {}                                                  # Store the 24 numbered third local-right strafe wall textures by wall id.
var straight_wall_nodes: Dictionary = {}                                                    # Store the 28 numbered straight-wall Sprite2D nodes by wall id.
var straight_wall_label_nodes: Dictionary = {}                                               # Store debug labels attached to straight-wall overlay sprites.
var floor_texture: Texture2D                                                                # Store the loaded floor texture strip.
var floor_fwd_1_texture: Texture2D                                                          # Store the first forward-transition floor texture.
var floor_fwd_2_texture: Texture2D                                                          # Store the second forward-transition floor texture.
var floor_right_1_texture: Texture2D                                                        # Store the first local-right strafe floor texture.
var floor_right_2_texture: Texture2D                                                        # Store the second local-right strafe floor texture.
var floor_right_3_texture: Texture2D                                                        # Store the third local-right strafe floor texture.
var floor_sprite: Sprite2D                                                                  # Store the base floor Sprite2D used by the straight renderer.
var environment_layer: Node2D                                                               # Store the parent node for all composited environment sprites.
var perspective_extents_overlay: Node2D                                                     # Store the projected-square debug overlay for the currently bound player view.
var view_slot_overlay: Node2D                                                               # Store the blue player-view slot-number diagnostic overlay for the currently bound view.
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
var is_turn_passthrough := false                                                            # Track whether a 22 or 66-degree camera interpolation frame is currently playing.
var turn_passthrough_timer := 0.0                                                          # Accumulate the visible duration of the active 22/66 frame.
var turn_passthrough_target := ""                                                         # Store whether the interpolation lands on a diagonal, next cardinal, or previous cardinal view.

var facing := 0                                                                             # Track the player camera direction as 0=N, 1=E, 2=S, 3=W.
var turn_45_direction := 0                                                                   # Track a temporary halfway turn stop: -1=left, 0=cardinal, 1=right.
var turn_step := 0                                                                           # Track a view-relative quarter-turn stage: 0=cardinal, 1=22, 2=45, 3=66.
var manual_turn_step_enabled := false                                                       # Let the debug menu hold the authored 22/66 turn frames until a fresh turn input advances them.
var forward_step := 0                                                                        # Track a forward camera stage: 0=stable, 1=Floor/WallsFwd_1, 2=Floor/WallsFwd_2.
var forward_passthrough_timer := 0.0                                                        # Accumulate the display time of the active forward frame.
var forward_transition_name := ""                                                          # Remember whether the staged crossing finishes forward or backward.
var manual_forward_step_enabled := false                                                    # Let the debug menu hold Fwd frames until a fresh forward input advances them.
var was_manual_forward_step_pressed := false                                                # Latch forward input so a held left stick cannot skip multiple Fwd frames.
var strafe_step := 0                                                                         # Track a side-camera stage: 0=stable, 1..3=Floor/WallsRight_1..3.
var strafe_passthrough_timer := 0.0                                                         # Accumulate automatic display time for the active side-camera frame.
var strafe_transition_name := ""                                                           # Remember whether the staged crossing commits to local left or local right.
var manual_strafe_step_enabled := false                                                     # Automatic by default; the debug menu can still hold each side-camera stage for inspection.
var was_manual_strafe_step_pressed := false                                                 # Latch lateral input so a held stick cannot skip multiple side-camera stages.
var grid_position := Vector2i(0, 3)                                                         # Track the current cell in the top-down maze map.
var local_floor_position := HOME_LOCAL_FLOOR_POSITION                                       # Track the character position inside the current tile.
var run_dir := DIR_N                                                                        # Track the body movement direction used for animation selection.
var aim_dir := DIR_N                                                                        # Track the aiming direction used for animation selection.
var last_animation: StringName = &""                                                        # Remember the last animation to avoid restarting it every frame.
var character_is_moving := false                                                            # Track whether the bound player is actively moving this frame.
var world_run_dir := DIR_N                                                                  # Track this player's movement direction in shared world space for opponent rendering.
var world_aim_dir := DIR_N                                                                  # Track this player's aim direction in shared world space for opponent rendering.
var available_animations: Dictionary = {}                                                   # Store animation-name lookups for exact and fallback animation selection.
var sprite_foot_anchor_cache: Dictionary = {}                                                # Cache per-texture foot/shadow anchor rows so sprite registration can ignore transparent padding.
var sprite_body_height_cache: Dictionary = {}                                                # Cache per-texture visible body spans so sprite scale ignores transparent frame padding.
var pending_grid_delta := Vector2i.ZERO                                                     # Store the cell movement that will be applied after a transition finishes.
var last_blocked_direction := ""                                                            # Store the most recent blocked movement label for debug display.
var wall_edges: Dictionary = {}                                                             # Store explicit thin-wall edge flags for each open cell.
var last_visible_wall_ids: Array[int] = []                                                   # Store the currently selected straight-wall ids for debug display.
var was_left_turn_pressed := false                                                          # Track previous-frame left turn input so snapped turns only fire once per press.
var was_right_turn_pressed := false                                                         # Track previous-frame right turn input so snapped turns only fire once per press.
var was_regenerate_map_pressed := false                                                      # Track previous-frame map-regenerate input so it fires once per key press.
var was_slot_grid_debug_pressed := false                                                     # Track previous-frame slot-grid toggle input so it fires once per key press.
var was_debug_menu_pressed := false                                                          # Track previous-frame debug-menu input so it opens or closes once per key press.
var held_keycodes := {}                                                                      # Track key press/release events delivered to this controller as an input fallback.
var active_player_index := 0                                                                 # Track which local player is currently bound into the legacy single-player renderer state.
var player_states: Array[Dictionary] = []                                                    # Store per-player movement, facing, transition, and debug state.
var player_views: Array[Dictionary] = []                                                     # Store per-player playfield, map, wall, and sprite node references.
var debug_menu_panel: PanelContainer                                                         # Store the shared CanvasLayer panel that exposes the existing debug draw toggles.
var debug_menu_checks: Dictionary = {}                                                       # Store each debug-menu checkbox by its option key so displayed state stays synchronized.
var debug_menu_open := false                                                                 # Track whether the debug-menu panel is currently visible.
var slot_graph_tuner_enabled := false                                                        # Let the visible current graph accept direct endpoint tuning.
var slot_graph_tuner_overrides: Dictionary = {}                                              # Store source-vector edits by active graph and slot ID.
var slot_graph_tuner_drag: Dictionary = {}                                                   # Track the one player-view endpoint currently under the mouse.
var slot_graph_tuner_hover: Dictionary = {}                                                  # Track the endpoint under the cursor so handles have a clear hover state.
var slot_graph_tuner_undo: Array[Dictionary] = []                                            # Preserve complete override snapshots for Ctrl+Z during a tuning session.
const SLOT_GRAPH_TUNER_PATH := "res://slot_graph_tuner.json"                                # Keep saved tuning data in the project for Git backup.



# _ready: Initializes the maze wall data, loads textures, creates renderer nodes, and draws the starting view.
func _ready() -> void:                                                                      # Declare this function.
	_ensure_input_actions()                                                                    # Register local input actions before the first input polling frame.
	if TEMP_EMPTY_GRID_AUDIT:                                                                  # Use the isolated wall-free slot-guide test surface when explicitly requested.
		_build_empty_grid_audit_wall_edges()                                                       # Build an empty 5x5 map with no physical wall edges.
	elif TEMP_RANDOM_GRID_AUDIT:                                                               # Exercise the renderer and debug overlay against a populated test maze.
		_build_random_maze_wall_edges()                                                             # Build a connected 9x9 maze while preserving its closed outer boundary.
	else:                                                                                      # Preserve the saved reference maze outside this temporary audit mode.
		_build_fixed_reference_maze_wall_edges()                                                   # Load the current fixed 4x4 thin-wall test maze before rendering.
	_load_phase_textures()                                                                     # Call a helper function as part of the current controller step.
	_load_stable_textures()                                                                    # Call a helper function as part of the current controller step.
	_load_slot_textures()                                                                      # Call a helper function as part of the current controller step.
	_load_straight_wall_textures()                                                             # Call a helper function as part of the current controller step.
	_load_turn_wall_textures()                                                                 # Load the 22, 45, and 66-degree turn wall overlay sprites.
	_load_forward_wall_textures()                                                              # Load the two authored forward-transition floor and wall overlay sets.
	_load_strafe_wall_textures()                                                               # Load the three authored side-transition floor and wall overlay sets.
	_setup_viewport()                                                                          # Call a helper function as part of the current controller step.
	_setup_player_animation()                                                                  # Call a helper function as part of the current controller step.
	_setup_local_multiplayer()                                                                 # Create the second local screen and player-state records.
	_setup_all_player_renderers()                                                              # Create an independent wall renderer and top-down map for each local player.
	_setup_debug_menu()                                                                        # Create the shared on-screen menu for toggling diagnostic overlays.
	_load_slot_graph_tuner_overrides()                                                         # Restore saved slot-vector adjustments before the first render.
	if enable_3d_diagnostic:                                                                   # Only create the deprecated 3D diagnostic when explicitly requested.
		_setup_3d_diagnostic()                                                                    # Create the side-by-side 3D map diagnostic view.
	_render_all_player_views()                                                                 # Draw both starting screens and both debug maps.
	_update_status()                                                                           # Call a helper function as part of the current controller step.



# _input: Records keyboard press and release events so movement does not depend only on raw polling.
func _input(event: InputEvent) -> void:                                                     # Declare this function.
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_Z: # Reserve standard Ctrl+Z for graph tuning undo.
		if _slot_graph_tuner_undo_last_edit():                                                   # Undo only when an edit snapshot exists.
			return                                                                                # Keep Ctrl+Z from reaching unrelated input handling.
	if _handle_slot_graph_tuner_input(event):                                                  # Let the visible graph consume endpoint drags before gameplay input.
		return                                                                                    # Prevent a graph drag from also driving the player.
	if event is InputEventKey and not event.echo:                                             # Only handle real keyboard press/release events once.
		held_keycodes[int(event.keycode)] = event.pressed                                       # Store whether this logical key is currently held.
		if event.physical_keycode != 0:                                                         # Preserve physical key bindings when Godot supplies them.
			held_keycodes[int(event.physical_keycode)] = event.pressed                            # Store the physical key state as another lookup option.



# _setup_debug_menu: Builds a shared on-screen menu for the current overlay diagnostics.
func _setup_debug_menu() -> void:
	debug_menu_panel = PanelContainer.new()                                                    # Create one UI panel above both local player views.
	debug_menu_panel.name = "DebugOverlayMenu"                                                # Give the panel a clear scene-tree name for editor inspection.
	debug_menu_panel.position = Vector2(12.0, 92.0)                                            # Place the menu below the existing runtime status text.
	debug_menu_panel.custom_minimum_size = Vector2(268.0, 0.0)                                # Keep labels readable without covering the entire game window.
	debug_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP                                  # Prevent mouse clicks on the menu from passing to the playfield.
	debug_menu_panel.visible = false                                                           # Start closed so the prototype view stays uncluttered.
	canvas_layer.add_child(debug_menu_panel)                                                   # Put the menu on the same UI layer as the status text and source maps.

	var content := VBoxContainer.new()                                                         # Stack the title, option rows, and usage hint vertically.
	content.add_theme_constant_override("separation", 4)                                     # Keep the compact debug controls easy to scan.
	debug_menu_panel.add_child(content)                                                        # Place the menu content inside the bordered panel.

	var title := Label.new()                                                                   # Create a concise header for the menu.
	title.text = "DEBUG OVERLAYS"                                                             # Identify the runtime diagnostic control panel.
	title.add_theme_font_size_override("font_size", 18)                                      # Give the header a distinct visual weight.
	content.add_child(title)                                                                   # Add the header before the option rows.

	_add_debug_menu_check(content, "source_map", "Map Walls")                               # Add the logical-map and wall-contact overlay toggle.
	_add_debug_menu_check(content, "rays", "Ray Casts")                                     # Add the raycast inspection overlay toggle.
	_add_debug_menu_check(content, "extents", "Floor Bounds")                               # Add the measured floor and sprite registration guides.
	_add_debug_menu_check(content, "slot_grid", "Slot Grid (F2)")                           # Add the existing F2 quick-toggle as a menu option.
	_add_debug_menu_check(content, "render_walls", "Render Walls")                          # Let floor/grid tuning run without opaque wall art covering the player view.
	_add_debug_menu_check(content, "selected_slots", "Selected Slots")                       # Add the selected-wall comparison overlay toggle.
	_add_debug_menu_check(content, "manual_forward", "Manual Forward")                      # Hold Fwd frames until the player deliberately presses forward again.
	_add_debug_menu_check(content, "manual_strafe", "Manual Strafe")                        # Hold side-camera frames until the player deliberately presses sideways again.
	_add_debug_menu_check(content, "manual_turn", "Manual Turn")                            # Hold 22/66 frames until a fresh Q/E or right-stick turn input advances them.
	_add_debug_menu_check(content, "slot_tuner", "Slot Graph Tuner")                        # Enable current-screen graph endpoint dragging.
	var save_tuner := Button.new()                                                             # Provide an explicit, reversible save action.
	save_tuner.text = "Save Slot Graph JSON"                                                  # State exactly what will be written.
	save_tuner.pressed.connect(_save_slot_graph_tuner_overrides)                              # Save edits only when deliberately requested.
	content.add_child(save_tuner)                                                              # Place save beneath the tuner toggle.

	var hint := Label.new()                                                                    # Provide the close hotkey inside the panel itself.
	hint.text = "F3 closes this menu"                                                         # Make the invocation/close behavior discoverable at runtime.
	hint.add_theme_font_size_override("font_size", 14)                                       # Keep the hint secondary to the controls.
	content.add_child(hint)                                                                    # Finish the panel with the usage hint.



# _add_debug_menu_check: Adds one checkbox and binds it to a named existing debug option.
func _add_debug_menu_check(parent: VBoxContainer, option_key: String, label_text: String) -> void:
	var check := CheckBox.new()                                                                # Create a visible checkbox before the compact option title.
	check.text = label_text                                                                    # Describe the visual diagnostic controlled by the checkbox.
	check.button_pressed = _debug_option_value(option_key)                                    # Match its initial state to the existing inspector/runtime toggle.
	check.toggled.connect(_set_debug_option.bind(option_key))                                 # Apply user clicks through the shared option setter.
	parent.add_child(check)                                                                    # Add the checkbox to the menu's vertical stack.
	debug_menu_checks[option_key] = check                                                     # Save the node so keyboard toggles can refresh it later.



# _toggle_debug_menu: Opens or closes the debug control panel and refreshes its displayed state.
func _toggle_debug_menu() -> void:
	debug_menu_open = not debug_menu_open                                                      # Flip the menu visibility state once per F3 press.
	if debug_menu_panel != null:                                                               # Guard against calls before _ready has created the panel.
		debug_menu_panel.visible = debug_menu_open                                               # Apply the new panel visibility.
	if debug_menu_open:                                                                        # Refresh checkbox state whenever the panel is opened.
		_refresh_debug_menu()                                                                    # Reflect inspector values and F2 toggles in every row.
	_update_status()                                                                           # Update the runtime help text to advertise the current menu state.



# _debug_option_value: Reads one existing debug toggle by its stable menu key.
func _debug_option_value(option_key: String) -> bool:
	match option_key:                                                                          # Resolve the menu key without exposing property names to UI construction.
		"source_map":
			return show_top_down_source_overlay                                                     # Return the logical-map and physical-wall overlay state.
		"rays":
			return show_raycast_debug                                                              # Return the visibility ray overlay state.
		"extents":
			return show_perspective_extents_overlay                                                # Return the measured floor/actor extent overlay state.
		"slot_grid":
			return show_slot_grid_debug                                                            # Return the blue wall-slot audit overlay state.
		"render_walls":
			return render_wall_art                                                                 # Return whether transparent wall overlays are currently visible.
		"selected_slots":
			return show_selected_wall_slot_debug                                                   # Return the renderer-selection comparison overlay state.
		"manual_forward":
			return manual_forward_step_enabled                                                      # Return whether Fwd frames wait for repeated forward input.
		"manual_strafe":
			return manual_strafe_step_enabled                                                       # Return whether side-camera frames wait for repeated lateral input.
		"manual_turn":
			return manual_turn_step_enabled                                                         # Return whether 22/66 turn frames wait for repeated turn input.
		"slot_tuner":
			return slot_graph_tuner_enabled                                                        # Return whether the current graph accepts endpoint drags.
		_:
			return false                                                                           # Keep unknown future menu keys safely disabled.



# _set_debug_option: Updates one existing debug toggle, redraws both views, and syncs the menu.
func _set_debug_option(enabled: bool, option_key: String) -> void:
	match option_key:                                                                          # Assign only the existing diagnostic flags selected by the menu.
		"source_map":
			show_top_down_source_overlay = enabled                                                 # Show or hide the top-down wall/contact source map.
		"rays":
			show_raycast_debug = enabled                                                           # Show or hide sampled visibility rays and their hit markers.
		"extents":
			show_perspective_extents_overlay = enabled                                             # Show or hide projected floor and actor-boundary guides.
		"slot_grid":
			show_slot_grid_debug = enabled                                                         # Show or hide the blue numbered wall-slot audit grid.
		"render_walls":
			render_wall_art = enabled                                                              # Hide/reveal only rendered wall overlays; map walls and collision remain active.
		"selected_slots":
			show_selected_wall_slot_debug = enabled                                                # Show or hide renderer-selected wall-slot highlights.
		"manual_forward":
			manual_forward_step_enabled = enabled                                                   # Toggle input-driven Fwd 1 -> Fwd 2 -> destination stepping.
		"manual_strafe":
			manual_strafe_step_enabled = enabled                                                    # Toggle input-driven Right 1 -> 2 -> 3 stepping.
		"manual_turn":
			manual_turn_step_enabled = enabled                                                      # Toggle input-driven 22/66 turn stepping.
		"slot_tuner":
			slot_graph_tuner_enabled = enabled                                                     # Toggle direct editing of the graph currently on screen.
			if enabled: show_slot_grid_debug = true                                                 # Ensure the draggable blue endpoints are visible when tuning starts.
		_:
			return                                                                                # Ignore unsupported keys without redrawing.
	_render_all_player_views()                                                                 # Redraw every local view immediately so changes are visible at once.
	_refresh_debug_menu()                                                                      # Keep all checkbox states synchronized after a click.
	_update_status()                                                                           # Keep the status hint synchronized with the current menu state.



# _refresh_debug_menu: Synchronizes visible menu checkboxes without emitting extra toggle callbacks.
func _refresh_debug_menu() -> void:
	for option_key in debug_menu_checks:                                                       # Visit every checkbox created by _setup_debug_menu.
		var check: CheckBox = debug_menu_checks[option_key]                                      # Read the checkbox stored for this menu key.
		if check != null:                                                                        # Skip a node only if it has been freed during scene teardown.
			check.set_pressed_no_signal(_debug_option_value(String(option_key)))                   # Reflect the current flag without recursively redrawing.



# _setup_local_multiplayer: Creates player two's view nodes and initializes two independent local player states.
func _setup_local_multiplayer() -> void:                                                    # Declare this function.
	if TEMP_GRID_AUDIT:                                                                        # Keep this focused slot-grid test free of a second player or second viewport.
		player_views = [{"maze_viewport": maze_viewport, "maze_content": maze_content, "playfield": playfield, "player_sprite": player_sprite, "opponent_sprite": null}] # Retain only player one's existing view nodes.
		player_states = [_make_player_state(0, Vector2i(4, 4), 0)]                               # Place one player at the center of the empty 9x9 grid, facing north.
		_bind_player_context(0)                                                                   # Bind the sole test player into the legacy renderer globals.
		return                                                                                    # Skip creating player two's view and opponent sprites.
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
	player_states = _make_start_player_states()                                                 # Create initial player-state records for both local players.
	_bind_player_context(0)                                                                     # Bind player one back into the legacy globals after setup.



# _make_start_player_states: Returns the normal gameplay start or the pinned slot-audit start.
func _make_start_player_states() -> Array[Dictionary]:                                    # Declare this function.
	if AUDIT_START_ENABLED:                                                                    # Use the deterministic correction frame while auditing the slot grid.
		return [                                                                                  # Return the two-player audit state list.
			_make_audit_player_state(0, AUDIT_P1_CELL, AUDIT_P1_FACING, AUDIT_P1_TURN_45_DIRECTION, AUDIT_P1_LOCAL_POSITION), # Start player one on the NE guide panel state.
			_make_audit_player_state(1, AUDIT_P2_CELL, AUDIT_P2_FACING, AUDIT_P2_TURN_45_DIRECTION, AUDIT_P2_LOCAL_POSITION), # Start player two on the north guide panel state.
		]                                                                                         # Close the audit state list.
	return [                                                                                    # Return the normal two-player gameplay state list.
		_make_player_state(0, Vector2i(0, MAP_HEIGHT - 1), 0),                                    # Start player one in the southwest corner facing north.
		_make_player_state(1, Vector2i(MAP_WIDTH - 1, 0), 2),                                     # Start player two in the northeast corner facing south.
	]                                                                                           # Close the normal state list.



# _make_audit_player_state: Builds a player state and applies fixed local/facing values for the grid-correction screenshot.
func _make_audit_player_state(player_index: int, start_cell: Vector2i, start_facing: int, start_turn_45: int, start_local_position: Vector2) -> Dictionary: # Declare this function.
	var state := _make_player_state(player_index, start_cell, start_facing)                    # Build the normal state record first.
	state["turn_45_direction"] = start_turn_45                                                  # Apply the requested cardinal or halfway-turn view.
	state["turn_step"] = 2 if start_turn_45 != 0 else 0                                         # Keep audit diagonal starts on the 45-degree stage.
	state["local_floor_position"] = start_local_position                                       # Apply the requested in-cell actor position.
	state["world_run_dir"] = _direction_string_for_facing(start_facing)                        # Keep the world run direction coherent with the audit facing.
	state["world_aim_dir"] = _direction_string_for_facing(start_facing)                        # Keep the world aim direction coherent with the audit facing.
	return state                                                                               # Return the corrected audit state.



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
		"is_turn_passthrough": false,                                                              # Store whether this player is crossing a 22/66 camera stage.
		"turn_passthrough_timer": 0.0,                                                             # Store the elapsed interpolation-frame time.
		"turn_passthrough_target": "",                                                            # Store the interpolation destination.
		"facing": start_facing,                                                                    # Store this player's camera direction.
		"turn_45_direction": 0,                                                                     # Store whether this player is stopped on a halfway turn view.
		"turn_step": 0,                                                                              # Store the current 22/45/66 interpolation stage.
		"forward_step": 0,                                                                           # Store the current Fwd 1/Fwd 2 camera stage.
		"forward_passthrough_timer": 0.0,                                                           # Store elapsed automatic Fwd stage time.
		"forward_transition_name": "",                                                            # Store the pending cell-crossing result after Fwd 2.
		"was_manual_forward_step_pressed": false,                                                   # Store the one-shot forward-step input latch.
		"strafe_step": 0,                                                                            # Store the current Right 1/2/3 camera stage.
		"strafe_passthrough_timer": 0.0,                                                            # Store elapsed automatic side-camera stage time.
		"strafe_transition_name": "",                                                             # Store the pending left/right cell-crossing result after Right 3/1.
		"was_manual_strafe_step_pressed": false,                                                    # Store the one-shot lateral-step input latch.
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
		_setup_view_slot_overlay()                                                                # Build this player's blue slot-number audit overlay.
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
	view["view_slot_overlay"] = view_slot_overlay                                              # Store this player's blue slot-number audit overlay.
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
	view_slot_overlay = view.get("view_slot_overlay", view_slot_overlay)                       # Bind this player's blue slot-number audit overlay.
	debug_map_overlay = view.get("debug_map_overlay", debug_map_overlay)                       # Bind this player's top-down source map.
	if player_index >= player_states.size():                                                   # Skip state loading if setup has not created states yet.
		return                                                                                    # Return with only view nodes bound.
	var state: Dictionary = player_states[player_index]                                        # Read this player's movement-state bundle.
	active_sequence = _texture_sequence_from_state(state.get("active_sequence", []))            # Restore this player's transition frame list.
	active_sequence_name = String(state.get("active_sequence_name", "idle"))                    # Restore this player's transition label.
	phase_index = int(state.get("phase_index", 0))                                             # Restore this player's transition frame index.
	phase_timer = float(state.get("phase_timer", 0.0))                                         # Restore this player's transition timer.
	is_transitioning = bool(state.get("is_transitioning", false))                              # Restore whether this player is in a captured transition.
	is_turn_passthrough = bool(state.get("is_turn_passthrough", false))                         # Restore whether this player is crossing a 22/66 camera stage.
	turn_passthrough_timer = float(state.get("turn_passthrough_timer", 0.0))                    # Restore elapsed interpolation-frame time.
	turn_passthrough_target = String(state.get("turn_passthrough_target", ""))                  # Restore the interpolation destination.
	facing = int(state.get("facing", 0))                                                        # Restore this player's facing.
	turn_45_direction = int(state.get("turn_45_direction", 0))                                  # Restore this player's temporary halfway-turn direction.
	turn_step = int(state.get("turn_step", 2 if turn_45_direction != 0 else 0))                   # Restore the current interpolation stage, preserving old saved diagonal states.
	forward_step = int(state.get("forward_step", 0))                                          # Restore this player's active forward camera stage.
	forward_passthrough_timer = float(state.get("forward_passthrough_timer", 0.0))             # Restore elapsed time in the active forward frame.
	forward_transition_name = String(state.get("forward_transition_name", ""))                # Restore the cell-crossing result that follows the second forward frame.
	was_manual_forward_step_pressed = bool(state.get("was_manual_forward_step_pressed", false)) # Restore the one-shot Fwd-step input latch.
	strafe_step = int(state.get("strafe_step", 0))                                             # Restore this player's active side-camera stage.
	strafe_passthrough_timer = float(state.get("strafe_passthrough_timer", 0.0))              # Restore elapsed time in the active side-camera frame.
	strafe_transition_name = String(state.get("strafe_transition_name", ""))                 # Restore the side-crossing result that follows the third frame.
	was_manual_strafe_step_pressed = bool(state.get("was_manual_strafe_step_pressed", false)) # Restore the one-shot side-step input latch.
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
	state["is_turn_passthrough"] = is_turn_passthrough                                         # Save whether this player is crossing a 22/66 camera stage.
	state["turn_passthrough_timer"] = turn_passthrough_timer                                   # Save elapsed interpolation-frame time.
	state["turn_passthrough_target"] = turn_passthrough_target                                 # Save the interpolation destination.
	state["facing"] = facing                                                                    # Save this player's facing.
	state["turn_45_direction"] = turn_45_direction                                             # Save this player's temporary halfway-turn direction.
	state["turn_step"] = turn_step                                                             # Save this player's current interpolation stage.
	state["forward_step"] = forward_step                                                       # Save this player's active forward camera stage.
	state["forward_passthrough_timer"] = forward_passthrough_timer                            # Save elapsed time in the active forward frame.
	state["forward_transition_name"] = forward_transition_name                                # Save the cell-crossing result that follows the forward frames.
	state["was_manual_forward_step_pressed"] = was_manual_forward_step_pressed                 # Save the one-shot Fwd-step input latch.
	state["strafe_step"] = strafe_step                                                        # Save this player's active side-camera stage.
	state["strafe_passthrough_timer"] = strafe_passthrough_timer                              # Save elapsed time in the active side-camera frame.
	state["strafe_transition_name"] = strafe_transition_name                                  # Save the side-crossing result that follows the third frame.
	state["was_manual_strafe_step_pressed"] = was_manual_strafe_step_pressed                  # Save the one-shot side-step input latch.
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
	var manual_forward_step_just_pressed := _read_manual_forward_step_input() if manual_forward_step_enabled else false # Sample every enabled frame so a held stick cannot skip stages.
	var manual_strafe_step_just_pressed := _read_manual_strafe_step_input() if manual_strafe_step_enabled else false # Sample every enabled frame so a held stick cannot skip side stages.
	var manual_turn_step_direction := _read_turn() if manual_turn_step_enabled else 0         # Sample a fresh Q/E or right-stick turn only when turn-stage inspection is enabled.
	if is_transitioning:                                                                       # Advance captured transition playback for this player if enabled.
		_advance_transition(delta)                                                                # Move this player's transition to the next frame when needed.
		return                                                                                    # Return after transition processing.
	if forward_step != 0:                                                                      # Keep input frozen while either authored forward camera frame is on screen.
		character_is_moving = true                                                               # Keep the player in the running state while the camera crosses the cell edge.
		_keep_forward_run_animating()                                                            # Force continuous, slightly faster run playback so the camera transition cannot read as a body pause.
		if manual_forward_step_enabled:                                                           # Hold Fwd 1 and Fwd 2 until the player presses forward again.
			if manual_forward_step_just_pressed:                                                    # Advance exactly one authored stage per fresh forward input.
				_advance_forward_passthrough(delta, true)                                             # Move Fwd 1 -> Fwd 2 or Fwd 2 -> destination immediately.
		else:
			_advance_forward_passthrough(delta)                                                     # Preserve automatic, brisk Fwd playback when the debug toggle is off.
		return                                                                                    # Do not accept another move or turn during the short camera transition.
	if strafe_step != 0:                                                                       # Keep input frozen while one of the authored side-camera frames is on screen.
		character_is_moving = true                                                               # Keep the player marked as running for their own and the opponent's view.
		_keep_forward_run_animating()                                                            # Reuse the visibly continuous running animation used by Fwd transitions.
		if manual_strafe_step_enabled:                                                           # Hold Right 1/2/3 until a fresh matching lateral input arrives.
			if manual_strafe_step_just_pressed:
				_advance_strafe_passthrough(delta, true)                                             # Advance exactly one authored side-camera frame per new sideways push.
		else:
			_advance_strafe_passthrough(delta)                                                     # Preserve automatic three-frame side-camera playback by default.
		return                                                                                    # Do not accept another move or turn during the short side transition.
	player_sprite.speed_scale = 1.0                                                            # Restore the ordinary animation pace as soon as Fwd playback has completed.
	if is_turn_passthrough:                                                                    # Let an authored 22/66 camera frame finish before accepting new movement or turn input.
		if manual_turn_step_enabled:                                                              # Hold the current 22/66 visual frame for direct graph tuning.
			if manual_turn_step_direction != 0:                                                     # Require a release and a new turn input before progressing.
				_advance_turn_passthrough(delta, true)                                                # Advance exactly one authored turn stage.
		else:
			_advance_turn_passthrough(delta)                                                       # Preserve ordinary short automatic turns when debug stepping is off.
		return                                                                                    # Keep the player physically fixed during this brief camera movement.
	var turn_direction := manual_turn_step_direction if manual_turn_step_enabled else _read_turn() # Reuse the sampled turn edge so manual mode cannot consume it twice.
	if _is_turn_45_view() and turn_direction != 0:                                             # Reserve a new Q/E press for committing or cancelling the halfway turn.
		_process_turn_45_input(turn_direction)                                                     # Apply the requested twist while leaving ordinary movement available at 45 degrees.
		return                                                                                    # Do not also move during the twist button press.
	if turn_direction < 0:                                                                     # Handle a left turn request.
		_request_half_turn_or_transition("turn_left", -1)                                          # Enter a 45-degree stop or use the old captured transition path.
		return                                                                                    # Return after turn processing.
	if turn_direction > 0:                                                                     # Handle a right turn request.
		_request_half_turn_or_transition("turn_right", 1)                                          # Enter a 45-degree stop or use the old captured transition path.
		return                                                                                    # Return after turn processing.
	var movement := _read_movement()                                                           # Read this player's local movement input.
	if movement != Vector2.ZERO:                                                               # Choose moving animation and move through the current cell.
		run_dir = _movement_to_first_player_run_dir(movement)                                     # Select the visible body-run direction for this local view.
		aim_dir = DIR_N                                                                           # Keep this player's aim locked camera-forward in their own view.
		character_is_moving = true                                                                # Mark this player as moving so opponents can play run animations.
		world_run_dir = _world_movement_dir_for_current_view(movement)                            # Convert local movement through the visible cardinal or diagonal camera basis.
		world_aim_dir = _direction_string_for_world_vector(_view_forward_vector())                # Store the visible camera aim direction in shared-world space.
		_play_best_animation(true)                                                                # Start or maintain the moving animation.
		if _is_turn_45_view():                                                                  # Keep the world position aligned with the visible diagonal camera basis.
			_move_inside_tile_diagonal(movement, delta)                                               # Move and collide in actual world space while retaining the halfway view.
		else:                                                                                    # Preserve the established cardinal movement and transition behavior.
			_move_inside_tile(movement, delta)                                                        # Apply local movement and wall/crossing checks.
	else:                                                                                      # Handle no movement input.
		run_dir = DIR_N                                                                           # Reset the visible body direction to camera-forward idle.
		aim_dir = DIR_N                                                                           # Keep aim camera-forward while idle.
		character_is_moving = false                                                               # Mark this player as idle for opponent first-frame fallback.
		world_run_dir = _direction_string_for_world_vector(_view_forward_vector())                # Use the visible camera direction as the idle body fallback.
		world_aim_dir = _direction_string_for_world_vector(_view_forward_vector())                # Store the visible camera aim direction in shared-world space.
		_play_best_animation(false)                                                               # Play the best idle animation.



# _render_bound_player_context: Redraws the currently bound player's wall view, self sprite, opponent sprite, and map.
func _render_bound_player_context() -> void:                                              # Declare this function.
	if is_transitioning:                                                                       # Keep captured transition frames visible when a transition is playing.
		_position_player()                                                                        # Keep the player sprite registered over the transition frame.
	elif _is_forward_view() or _is_strafe_view():                                               # Compose either authored translation camera over its matching standalone floor frame.
		_show_stable()                                                                            # Draw floor first, then the selected wall overlays.
		_position_player()                                                                        # Keep the local player above the forward-frame environment.
		_position_opponent_sprite()                                                              # Keep the other player in the normal depth-sorted layer.
	elif _is_turn_45_view():                                                                  # Render the halfway-turn floor and wall sprites with normal actor support.
		_show_stable()                                                                            # Compose the 45-degree floor and wall sprites.
		_position_player()                                                                        # Keep the local player visible and mobile in a diagonal view.
		_position_opponent_sprite()                                                              # Keep other players visible when their projection overlaps the diagonal view.
	else:                                                                                      # Render a stable wall-sprite scene when no transition is playing.
		_show_stable()                                                                            # Compose the floor and visible wall sprites for this player's view.
		_position_player()                                                                        # Project this player's local cell position into the playfield.
		_position_opponent_sprite()                                                              # Project the other local player into this player's screen when visible.
	_apply_wall_art_debug_visibility()                                                         # Let the debug toggle hide wall art after any renderer has selected its real source-map slots.
	_update_perspective_extents_overlay()                                                       # Keep the actor-position diagnostics available for cardinal and diagonal views.
	_update_view_slot_debug_overlay()                                                         # Redraw the blue player-view slot audit labels for this camera orientation.
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


# _apply_wall_art_debug_visibility: Hides only selected transparent wall layers while preserving the floor, source graph, raycasts, and collisions.
func _apply_wall_art_debug_visibility() -> void:
	if render_wall_art:                                                                        # Each renderer has already made its selected wall sprites visible during this redraw.
		return                                                                                   # Leave that normal compositing result untouched.
	for wall_sprite in straight_wall_nodes.values():                                           # Visit the reusable sprites shared by straight, turn, forward, and strafe renderers.
		if wall_sprite is Sprite2D:                                                              # Ignore any malformed future dictionary entry defensively.
			wall_sprite.visible = false                                                            # Hide artwork only; do not alter map edges or selected-slot records.



# _process: Runs the per-frame input, movement, transition, animation, player positioning, and status update loop.
func _process(delta: float) -> void:                                                        # Declare this function.
	_layout_viewport()                                                                         # Call a helper function as part of the current controller step.
	if _read_toggle_debug_menu():                                                              # Check for a one-shot request to open or close the debug menu.
		_toggle_debug_menu()                                                                     # Change panel visibility without changing any diagnostic state.
		return                                                                                   # Keep the menu hotkey from also advancing gameplay this frame.
	if _read_toggle_slot_grid_debug():                                                         # Check for a one-shot request to toggle the blue slot-grid audit overlay.
		show_slot_grid_debug = not show_slot_grid_debug                                           # Flip the diagnostic overlay visibility for every local viewport.
		_render_all_player_views()                                                                # Redraw immediately so the overlay appears or disappears without waiting for movement.
		_refresh_debug_menu()                                                                     # Keep the menu checkbox synchronized with the F2 quick toggle.
		_update_status()                                                                          # Refresh the status text after the debug toggle.
		return                                                                                    # Skip movement this frame because this key press was only a debug toggle.
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



# _setup_view_slot_overlay: Creates the per-player blue slot-number audit overlay inside the cropped playfield.
func _setup_view_slot_overlay() -> void:                                                   # Declare this function.
	view_slot_overlay = Node2D.new()                                                          # Create the overlay root used for player-view slot labels.
	view_slot_overlay.name = "DebugViewSlotGrid"                                              # Name the overlay so it is easy to inspect in the scene tree.
	view_slot_overlay.z_index = 220                                                           # Draw the slot audit above wall art and character sprites.
	maze_content.add_child(view_slot_overlay)                                                  # Attach the overlay inside the clipped camera content.
	_update_view_slot_debug_overlay()                                                         # Draw the initial slot audit labels immediately.



# _update_perspective_extents_overlay: Redraws colored trapezoids for every measured visible square.
func _update_perspective_extents_overlay() -> void:                                        # Declare this function.
	if perspective_extents_overlay == null:                                                    # Skip when this player view has no extent overlay.
		return                                                                                    # Return without drawing anything.
	perspective_extents_overlay.visible = show_perspective_extents_overlay                     # Apply the inspector toggle to this player's overlay.
	for child in perspective_extents_overlay.get_children():                                   # Remove the previous frame's guide primitives.
		if is_instance_valid(child) and not child.is_queued_for_deletion():                       # Skip nodes already queued by an earlier redraw.
			perspective_extents_overlay.remove_child(child)                                          # Detach it now so same-frame redraws cannot double up visually.
			child.queue_free()                                                                       # Queue this old debug primitive for safe end-of-frame cleanup.
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
	var feet_anchor_y := _sprite_foot_anchor_y(sprite)                                         # Read the per-frame foot/shadow anchor inside the actual character pixels.
	var center_to_feet := (feet_anchor_y - float(texture.get_height()) * 0.5) * sprite.scale.y # Convert the texture-space anchor into centered-sprite local pixels.
	var feet := sprite.position + Vector2(0.0, center_to_feet)                                 # Compute the projected feet point from the actual art anchor.
	_add_perspective_extent_line(top_left, top_right, color, 1.0)                              # Draw the sprite top edge.
	_add_perspective_extent_line(top_right, bottom_right, color, 1.0)                          # Draw the sprite right edge.
	_add_perspective_extent_line(bottom_left, bottom_right, color, 1.0)                        # Draw the sprite bottom edge.
	_add_perspective_extent_line(top_left, bottom_left, color, 1.0)                            # Draw the sprite left edge.
	_add_perspective_extent_line(feet + Vector2(-3.0, 0.0), feet + Vector2(3.0, 0.0), color, 1.0) # Draw the horizontal feet crossbar.
	_add_perspective_extent_line(feet + Vector2(0.0, -3.0), feet + Vector2(0.0, 3.0), color, 1.0) # Draw the vertical feet crossbar.
	_add_perspective_extent_label(label_text, feet + Vector2(4.0, -6.0), color)                # Label the sprite bounds marker.



# _update_view_slot_debug_overlay: Redraws blue player-view slot labels from the local reference slot guide.
func _update_view_slot_debug_overlay() -> void:                                             # Declare this function.
	if view_slot_overlay == null:                                                            # Skip when this player view has no slot audit overlay.
		return                                                                                    # Return without drawing slot labels.
	view_slot_overlay.visible = show_slot_grid_debug                                           # Apply the inspector/debug toggle to the player-view audit overlay.
	for child in view_slot_overlay.get_children():                                            # Remove previous frame's blue slot guide primitives.
		if is_instance_valid(child) and not child.is_queued_for_deletion():                       # Skip nodes already queued by an earlier redraw.
			view_slot_overlay.remove_child(child)                                                  # Detach it now so the rebuilt audit labels do not visually stack.
			child.queue_free()                                                                       # Queue the old slot audit primitive for safe end-of-frame cleanup.
	if not show_slot_grid_debug:                                                              # Avoid rebuilding hidden guide geometry.
		return                                                                                    # Return after clearing stale children.
	var source_presence := _debug_slot_has_wall_by_id()                                        # Read which numbered source-map slots are currently blocked.
	var screen_slots := _view_slot_screen_segments()                                           # Read the local screen-space guide lines for this camera angle.
	if _is_forward_view() or _is_strafe_view():                                                 # Translation frames own distinct local graphs; never substitute the cardinal guide.
		for slot in screen_slots:                                                                  # Draw the active frame's art-derived labels and ticks.
			var segment: Array[Vector2] = [slot["a"], slot["b"]]                                 # Read the screen guide endpoints paired with one Fwd overlay.
			var wall_id := int(slot["id"])                                                         # Keep the local label tied to the same source-edge id.
			var color := SLOT_GRID_DEBUG_WALL_COLOR if bool(source_presence.get(wall_id, false)) else SLOT_GRID_DEBUG_OPEN_COLOR # Match the actual selected art state.
			_add_view_slot_debug_line(segment[0], segment[1], color, 1.0)                           # Draw the source segment projected onto this frame's floor grid.
			_add_view_slot_debug_label(slot.get("label", (segment[0] + segment[1]) * 0.5), wall_id, color) # Keep the label on the same projected floor-grid segment.
			if slot_graph_tuner_enabled:                                                           # Let the same current-screen tuner edit any active transition graph.
				_add_slot_graph_tuner_handle(segment[0], wall_id, "a")                              # Draw the first source-vector endpoint with hover/selection feedback.
				_add_slot_graph_tuner_handle(segment[1], wall_id, "b")                              # Draw the second source-vector endpoint with hover/selection feedback.
		return
	if not _is_turn_45_view():                                                                 # Cardinal camera views now draw their editable slot vectors directly instead of an unrelated fixed skeleton.
		for slot in screen_slots:                                                                  # Draw the 01..28 player-local vectors whose endpoints the tuner actually owns.
			var wall_id := int(slot["id"])                                                          # Read the stable transparent-wall art-slot ID.
			var segment: Array[Vector2] = [slot["a"], slot["b"]]                                   # Use exactly the two draggable player-local endpoints.
			var line_color := SLOT_GRID_DEBUG_WALL_COLOR if bool(source_presence.get(wall_id, false)) else SLOT_GRID_DEBUG_OPEN_COLOR # Keep color tied to the unchanged top-down wall selection.
			_add_view_slot_debug_line(segment[0], segment[1], line_color, 1.0)                       # Draw a vector that remains connected to its visible handles.
			_add_view_slot_debug_label(slot["label"], wall_id, line_color)                           # Keep the slot number with its user-tuned vector.
			if slot_graph_tuner_enabled:                                                             # Expose the main idle/cardinal guide through the same endpoint handles.
				_add_slot_graph_tuner_handle(segment[0], wall_id, "a")                                # Make the first authored endpoint draggable.
				_add_slot_graph_tuner_handle(segment[1], wall_id, "b")                                # Make the second authored endpoint draggable.
		return                                                                                    # The old fixed skeleton is intentionally omitted because it cannot follow player-local edits.
	for slot in screen_slots:                                                                  # Draw every local slot guide for the current cardinal or halfway-turn view.
		var segment: Array[Vector2] = [slot["a"], slot["b"]]                                     # Read the screen-space endpoints from the guide table.
		if segment.size() < 2:                                                                    # Skip invalid slot geometry defensively.
			continue                                                                                 # Continue to the next diagnostic slot.
		var wall_id := int(slot["id"])                                                            # Read the player/local wall-slot id.
		var line_color := SLOT_GRID_DEBUG_WALL_COLOR if bool(source_presence.get(wall_id, false)) else SLOT_GRID_DEBUG_OPEN_COLOR # Brighten blocked source edges and fade open candidates.
		_add_view_slot_debug_line(segment[0], segment[1], line_color, 1.0)                        # Draw the projected slot line on the player-view grid.
		var label_position: Vector2 = slot.get("label", (segment[0] + segment[1]) * 0.5)           # Use the tuned label position when the guide table supplies one.
		_add_view_slot_debug_label(label_position, wall_id, line_color)                            # Give the player-view number the same selected/open state as its source edge.
		if slot_graph_tuner_enabled:                                                               # Let 22/45/66 guides use the same no-snap point editor.
			_add_slot_graph_tuner_handle(segment[0], wall_id, "a")                                  # Draw the first direct-edit endpoint.
			_add_slot_graph_tuner_handle(segment[1], wall_id, "b")                                  # Draw the second direct-edit endpoint.



# _debug_slot_has_wall_by_id: Collapses source-map diagnostic slots into a quick wall-present lookup by local id.
func _debug_slot_has_wall_by_id() -> Dictionary:                                            # Declare this function.
	var source_presence := {}                                                                  # Store whether each local slot id currently maps to a real wall.
	if _is_forward_view() or _is_strafe_view():                                                 # Evaluate the active translation graph independently from straight and turn slots.
		var translation_slots := _build_forward_render_list() if _is_forward_view() else _build_strafe_render_list() # Reuse the active renderer's final selection.
		for slot in translation_slots:
			source_presence[int(slot["id"])] = true
		return source_presence
	if not _is_turn_45_view():                                                                 # Straight ids name renderer art slots rather than unique physical map edges.
		for slot in _build_straight_render_list():                                                # Reuse the renderer's final, visibility-filtered art-slot selection.
			source_presence[int(slot["id"])] = true                                                 # Mark precisely the IDs whose transparent wall art is being drawn.
		return source_presence                                                                     # Keep both debug diagrams 1:1 with the player view.
	if turn_step != 2:                                                                         # The 22 and 66 guides are authored in screen space, not on the old 45-degree lookup grid.
		for slot in _build_turn_45_render_list():                                                # Reuse the current stage's actual ray-visible wall selection.
			source_presence[int(slot["id"])] = true                                                # Mark only the overlays currently selected for this intermediate view.
		return source_presence                                                                    # Keep the intermediate guide colors tied to what is actually drawn.
	for slot in _all_debug_wall_slot_segments():                                               # Visit every source-map slot candidate for this view.
		var wall_id := int(slot["id"])                                                            # Read this local wall-slot id.
		var already_present := bool(source_presence.get(wall_id, false))                          # Preserve any earlier true value for repeated ids.
		source_presence[wall_id] = already_present or bool(slot["has_wall"])                      # Mark the id as blocked when any source edge for it is blocked.
	return source_presence                                                                     # Return the wall-present lookup for player-view coloring.



# _view_slot_screen_segments: Returns the player-view guide segments for cardinal or halfway-turn slot audits.
func _view_slot_screen_segments() -> Array:                                                 # Declare this function.
	if _is_strafe_view():                                                                      # Side art has its own authored slot graphs and cannot use the stable cardinal guide.
		return _slot_graph_tuner_apply_screen_overrides(_strafe_view_slot_screen_segments())     # Tune the displayed side guide without changing its world-space source graph.
	if _is_forward_view():                                                                     # Forward art has its own authored slot graphs and cannot use the stable cardinal guide.
		return _slot_graph_tuner_apply_screen_overrides(_forward_view_slot_screen_segments())     # Keep editable player-local tuning separate from the Fwd source graph.
	if _is_turn_45_view():                                                                    # Use the explicit halfway-turn guide because physical map projection is not the screen diagram.
		if turn_step != 2:                                                                        # Do not reuse the 45-degree guide at either interpolation stage.
			return _slot_graph_tuner_apply_screen_overrides(_turn_stage_slot_screen_segments())    # Tune the displayed 22/66 guide without changing its rotated source edges.
		return _slot_graph_tuner_apply_screen_overrides(_turn_45_view_slot_screen_segments())    # Tune the displayed 45-degree guide without changing its source graph.
	var segments := []                                                                         # Store the camera-invariant straight-view guide records.
	for slot in _cardinal_debug_slot_records():                                                # Use the same conceptual art-slot diagram as the top-down overlay.
		segments.append(_view_slot_screen_record(int(slot["id"]), slot["screen_a"], slot["screen_b"], slot["screen_label"])) # Preserve the matching canonical label position without a Variant-array cast.
	return _slot_graph_tuner_apply_screen_overrides(segments)                                  # Let the idle/cardinal player-view graph be tuned independently of its source topology.


# _turn_stage_slot_screen_segments: Returns the authored local guide that pairs every 22/66 art id to its source-map edge.
func _turn_stage_slot_screen_segments() -> Array:
	var guide := TURN_22_PLAYER_SLOT_GUIDE if _active_turn_visual_stage() == 1 else TURN_66_PLAYER_SLOT_GUIDE # Select the stage's reference diagram, including reverse turns.
	var segments := []                                                                         # Store the local labels for every authored intermediate overlay.
	for entry in guide:                                                                        # Visit each reference number exactly once.
		var label: Vector2 = entry["label"]                                                     # Read the hand-authored player-view label position.
		var tangent: Vector2 = entry["tangent"]                                                 # Read the matching local guide-line direction.
		tangent = tangent.normalized()                                                            # Keep diagonal guide marks at their authored length.
		var half_length := float(entry["half"])                                                 # Keep the guide line at its authored readable length.
		segments.append(_view_slot_screen_record(int(entry["id"]), label - tangent * half_length, label + tangent * half_length, label)) # Keep the screen number paired to the same source-edge id.
	return segments                                                                            # Return all 22/66 reference-aligned slot guides.



# _cardinal_debug_slot_records: Builds one camera-relative art-slot diagram for both cardinal debug views.
func _cardinal_debug_slot_records() -> Array:                                               # Declare this function.
	var records := []                                                                          # Store one canonical record per transparent straight-wall art asset.
	for guide in CARDINAL_SLOT_GUIDE:                                                          # Use the authored N/S/E/W guide instead of deriving art labels from map edges.
		var wall_id := int(guide["id"])                                                          # Read the renderer asset ID represented by this authored guide mark.
		var screen_label: Vector2 = guide["screen"]                                               # Keep the player-view label at its exact guide location.
		var topology := {}                                                                         # Find the one canonical world-grid segment that owns this art-slot ID.
		for candidate in CARDINAL_SLOT_TOPOLOGY:                                                   # Search the explicit 01..28 segment table.
			if int(candidate["id"]) == wall_id:                                                     # Match this screen label to its world segment.
				topology = candidate                                                                    # Keep the matching segment record.
				break                                                                                   # Each ID has exactly one segment.
		if topology.is_empty():                                                                   # Guard against incomplete future tables.
			continue                                                                                  # Skip an unpaired slot instead of inventing a line.
		var map_a: Vector2 = topology["a"]                                                        # Read the exact first endpoint of the owned source-grid segment.
		var map_b: Vector2 = topology["b"]                                                        # Read the exact second endpoint of the owned source-grid segment.
		var map_label := (map_a + map_b) * 0.5                                                     # Place this ID directly on its own blue source-grid segment.
		var half_line := 4.0 if screen_label.y < 60.0 else 7.0                                    # Use compact guide ticks so labels stay legible instead of becoming a second floor mesh.
		var edge := _straight_wall_slot_edge(wall_id)                                              # Recover whether this asset represents a front, left, or right wall family.
		var screen_tangent := Vector2.RIGHT if edge == VIEW_FRONT else Vector2.DOWN               # Preserve vertical player-view guide lines for side-wall art.
		records.append({"id": wall_id, "local_label": map_label, "map_a": map_a, "map_b": map_b, "screen_a": screen_label - screen_tangent * half_line, "screen_b": screen_label + screen_tangent * half_line, "screen_label": screen_label}) # Store the shared orientation-aware art-slot definition.
	return records                                                                             # Return the stable 28-slot diagram.



# _straight_wall_slot_edge: Returns the art-wall family associated with one straight-view slot ID.
func _straight_wall_slot_edge(wall_id: int) -> String:                                      # Declare this function.
	for slot in STRAIGHT_WALL_SLOTS:                                                          # Look up the renderer's authoritative metadata for this asset ID.
		if int(slot["id"]) == wall_id:                                                           # Stop at the exact numbered wall art slot.
			return str(slot["edge"])                                                               # Return its front/left/right wall family.
	return VIEW_FRONT                                                                           # Fall back safely to a front-facing guide segment for unknown IDs.



# _turn_45_view_slot_screen_segments: Returns the hand-authored 16-slot guide from Wall_Grid_45.png.
func _turn_45_view_slot_screen_segments() -> Array:                                        # Declare this function.
	return [                                                                                  # Return fixed player-view guide lines in 160x120 playfield pixels.
		_view_slot_screen_record(3, Vector2(0.0, 56.0), Vector2(26.0, 56.0), Vector2(11.0, 56.0)), # Place slot 3 on the source diagram's far local-left seam.
		_view_slot_screen_record(1, Vector2(26.0, 51.0), Vector2(80.0, 51.0), Vector2(52.0, 51.0)), # Place slot 1 on the source diagram's far inner-left seam.
		_view_slot_screen_record(2, Vector2(80.0, 51.0), Vector2(134.0, 51.0), Vector2(107.0, 51.0)), # Place slot 2 on the source diagram's far inner-right seam.
		_view_slot_screen_record(6, Vector2(134.0, 54.0), Vector2(160.0, 54.0), Vector2(147.0, 54.0)), # Place slot 6 on the source diagram's far local-right seam.
		_view_slot_screen_record(7, Vector2(0.0, 66.0), Vector2(31.0, 66.0), Vector2(11.0, 66.0)), # Place slot 7 on the source diagram's second local-left seam.
		_view_slot_screen_record(4, Vector2(31.0, 58.0), Vector2(80.0, 67.0), Vector2(52.0, 58.0)), # Place slot 4 on the source diagram's second inner-left seam.
		_view_slot_screen_record(5, Vector2(80.0, 67.0), Vector2(129.0, 58.0), Vector2(107.0, 58.0)), # Place slot 5 on the source diagram's second inner-right seam.
		_view_slot_screen_record(10, Vector2(129.0, 67.0), Vector2(160.0, 67.0), Vector2(148.0, 67.0)), # Place slot 10 on the source diagram's second local-right seam.
		_view_slot_screen_record(11, Vector2(0.0, 76.0), Vector2(34.0, 76.0), Vector2(12.0, 76.0)), # Place slot 11 on the source diagram's third local-left seam.
		_view_slot_screen_record(8, Vector2(34.0, 67.0), Vector2(80.0, 82.0), Vector2(51.0, 67.0)), # Place slot 8 on the source diagram's third inner-left seam.
		_view_slot_screen_record(9, Vector2(80.0, 82.0), Vector2(126.0, 66.0), Vector2(107.0, 66.0)), # Place slot 9 on the source diagram's third inner-right seam.
		_view_slot_screen_record(14, Vector2(126.0, 75.0), Vector2(160.0, 75.0), Vector2(148.0, 75.0)), # Place slot 14 on the source diagram's third local-right seam.
		_view_slot_screen_record(15, Vector2(0.0, 112.0), Vector2(80.0, 82.0), Vector2(51.0, 97.0)), # Place slot 15 on the source diagram's nearest left diagonal.
		_view_slot_screen_record(12, Vector2(43.0, 79.0), Vector2(80.0, 82.0), Vector2(51.0, 79.0)), # Place slot 12 on the source diagram's nearest inner-left diagonal.
		_view_slot_screen_record(13, Vector2(80.0, 82.0), Vector2(117.0, 80.0), Vector2(108.0, 80.0)), # Place slot 13 on the source diagram's nearest inner-right diagonal.
		_view_slot_screen_record(16, Vector2(80.0, 82.0), Vector2(160.0, 112.0), Vector2(108.0, 97.0)), # Place slot 16 on the source diagram's nearest right diagonal.
	]                                                                                          # Close the halfway-turn screen guide list.



# _view_slot_screen_record: Builds one player-view slot guide record.
func _view_slot_screen_record(wall_id: int, start: Vector2, end: Vector2, label_position: Vector2) -> Dictionary: # Declare this function.
	return {"id": wall_id, "a": start, "b": end, "label": label_position}                    # Return the compact guide record.



# _debug_slot_screen_segment: Projects one source-map diagnostic slot segment onto the player-view floor grid.
func _debug_slot_screen_segment(slot: Dictionary) -> Array[Vector2]:                       # Declare this function.
	if not slot.has("a") or not slot.has("b"):                                                # Require physical source-map endpoints.
		return []                                                                               # Return no player-view segment when geometry is incomplete.
	var local_a := _camera_local_point_from_world(slot["a"])                                   # Convert endpoint A into camera-local side/depth coordinates.
	var local_b := _camera_local_point_from_world(slot["b"])                                   # Convert endpoint B into camera-local side/depth coordinates.
	return [_screen_floor_point_for_camera_local_position(local_a), _screen_floor_point_for_camera_local_position(local_b)] # Project both endpoints through the measured floor perspective.



# _screen_floor_point_for_camera_local_position: Projects a camera-local floor point into 160x120 screen coordinates.
func _screen_floor_point_for_camera_local_position(local_position: Vector2) -> Vector2:     # Declare this function.
	var side := clampf(local_position.x, -DEBUG_VIEW_CONE_HALF_WIDTH, DEBUG_VIEW_CONE_HALF_WIDTH) # Keep debug labels inside the useful view fan.
	var depth := clampf(local_position.y, 0.04, 3.96)                                          # Keep debug labels within the measured floor depth table.
	var corridor := _corridor_projection_at_view_depth(depth)                                  # Sample the same measured floor corridor used by actor projection.
	if side >= -LOCAL_TILE_WORLD_HALF_EXTENT and side <= LOCAL_TILE_WORLD_HALF_EXTENT:         # Use the central corridor trapezoid for points inside the main cell span.
		var ratio := side + LOCAL_TILE_WORLD_HALF_EXTENT                                         # Convert side -0.5..0.5 into screen interpolation ratio 0..1.
		return Vector2(lerpf(float(corridor["left_x"]), float(corridor["right_x"]), ratio), float(corridor["feet_y"])) # Return the central corridor projection.
	var side_sign := signf(side)                                                              # Determine whether this point lies off the left or right side of the corridor.
	var side_projection := _side_entry_projection_at_view_depth(depth, side_sign)              # Sample the mirrored side-entry projection at this same depth.
	var side_travel := clampf((absf(side) - LOCAL_TILE_WORLD_HALF_EXTENT) / maxf(DEBUG_VIEW_CONE_HALF_WIDTH - LOCAL_TILE_WORLD_HALF_EXTENT, 0.001), 0.0, 1.0) # Convert side overrun into a side-wedge blend.
	var corridor_edge_x := float(corridor["right_x"]) if side_sign > 0.0 else float(corridor["left_x"]) # Pick the nearest corridor edge for the side blend.
	var screen_x := lerpf(corridor_edge_x, float(side_projection["outer_x"]), side_travel)     # Blend from the corridor edge toward the side-frame edge.
	var feet_y := lerpf(float(corridor["feet_y"]), float(side_projection["feet_y"]), side_travel) # Blend feet depth into the side-entry floor band.
	return Vector2(screen_x, feet_y)                                                          # Return the projected side-entry floor point.



# _add_view_slot_debug_line: Adds one blue line segment to the player-view slot audit overlay.
func _add_view_slot_debug_line(start: Vector2, end: Vector2, color: Color, width: float) -> void: # Declare this function.
	var line := Line2D.new()                                                                    # Create a line primitive for the player-view audit overlay.
	line.points = PackedVector2Array([start, end])                                             # Set the line endpoints in playfield pixels.
	line.width = width                                                                          # Set the debug line width.
	line.default_color = color                                                                  # Apply the requested blue line color.
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                                    # Keep the debug line crisp over pixel art.
	view_slot_overlay.add_child(line)                                                          # Add the line to the active player-view slot overlay.



# _add_view_slot_debug_label: Adds one blue two-digit slot label to the player-view slot audit overlay.
func _add_view_slot_debug_label(position: Vector2, wall_id: int, color: Color) -> void:      # Declare this function.
	var label := Label.new()                                                                   # Create a compact label for the player-view slot id.
	label.text = "%02d" % wall_id                                                              # Display the local wall-slot id as two digits.
	label.add_theme_color_override("font_color", color)                                       # Use blue so these labels differ from renderer-selected yellow wall labels.
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))            # Add black shadow for readability over the wall art.
	label.add_theme_constant_override("shadow_offset_x", 1)                                   # Offset the label shadow one pixel right.
	label.add_theme_constant_override("shadow_offset_y", 1)                                   # Offset the label shadow one pixel down.
	label.scale = Vector2(0.30, 0.30)                                                         # Keep all-slot labels small enough to coexist in the playfield.
	label.position = position + Vector2(-4.0, -4.0)                                           # Center the label around the projected slot line.
	view_slot_overlay.add_child(label)                                                        # Add the label to the active player-view slot overlay.


# _add_slot_graph_tuner_handle: Draws a clearly clickable endpoint and the selected translation gizmo.
func _add_slot_graph_tuner_handle(position: Vector2, wall_id: int, endpoint_key: String) -> void:
	var selected := not slot_graph_tuner_drag.is_empty() and int(slot_graph_tuner_drag.get("id", -1)) == wall_id and String(slot_graph_tuner_drag.get("endpoint", "")) == endpoint_key # Keep the captured handle yellow while it is being moved.
	var hovered := not slot_graph_tuner_hover.is_empty() and int(slot_graph_tuner_hover.get("id", -1)) == wall_id and String(slot_graph_tuner_hover.get("endpoint", "")) == endpoint_key # Brighten the handle directly under the mouse.
	var color := Color(1.0, 0.85, 0.05, 1.0) if selected else (Color(0.2, 1.0, 1.0, 1.0) if hovered else Color(0.1, 0.45, 1.0, 1.0)) # Distinguish selected, hover, and idle states.
	var handle := Polygon2D.new()                                                              # Use a diamond so endpoints remain visible over thin blue guide lines.
	handle.polygon = PackedVector2Array([position + Vector2(0, -3), position + Vector2(3, 0), position + Vector2(0, 3), position + Vector2(-3, 0)]) # Draw a six-pixel draggable target.
	handle.color = color                                                                       # Apply the current interaction state color.
	view_slot_overlay.add_child(handle)                                                        # Keep the handle in the same clipped player-view space as its graph.
	if selected:                                                                               # Add a simple crosshair gizmo around the actively translated point.
		_add_view_slot_debug_line(position - Vector2(10, 0), position + Vector2(10, 0), color, 1.0) # Expose horizontal translation direction.
		_add_view_slot_debug_line(position - Vector2(0, 10), position + Vector2(0, 10), color, 1.0) # Expose vertical translation direction.



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
	if TEMP_GRID_AUDIT and player_views.size() == 1:                                           # Use a clean side-by-side layout for the one-player 9x9 audit.
		var side_gutter := SIDE_BY_SIDE_GUTTER * 2.0                                               # Leave a clear gap between the player camera and source grid.
		var audit_size := Vector2(VIEWPORT_SIZE.x + side_gutter + DEBUG_MAP_PANEL_SIZE.x, DEBUG_MAP_PANEL_SIZE.y) # Fit the 160x120 view beside its 160x160 map.
		var audit_available := Vector2(viewport_size.x, maxf(viewport_size.y - status_margin, DEBUG_MAP_PANEL_SIZE.y)) # Reserve the status area before scaling the audit layout.
		var audit_scale := minf(audit_available.x / audit_size.x, audit_available.y / audit_size.y) # Scale both panels uniformly to the available window.
		var audit_origin := Vector2((viewport_size.x - audit_size.x * audit_scale) * 0.5, status_margin + (audit_available.y - audit_size.y * audit_scale) * 0.5) # Center the two-panel audit below status.
		var audit_view: Dictionary = player_views[0]                                               # Read the sole player/view bundle.
		var audit_map: Node2D = audit_view.get("debug_map_overlay", null)                        # Read the top-down grid panel.
		var audit_camera: Node2D = audit_view.get("maze_viewport", null)                         # Read the player camera panel.
		if audit_map != null:                                                                      # Position the source grid to the right of the player view.
			audit_map.visible = show_top_down_source_overlay                                           # Respect the existing map overlay toggle.
			audit_map.scale = Vector2.ONE * audit_scale                                                # Match the player-view scaling.
			audit_map.position = audit_origin + Vector2((VIEWPORT_SIZE.x + side_gutter) * audit_scale, 0.0) # Park the grid off to the side.
		if audit_camera != null:                                                                   # Center the shorter player camera vertically against the square map.
			audit_camera.scale = Vector2.ONE * audit_scale                                             # Match the source-grid scaling.
			audit_camera.position = audit_origin + Vector2(0.0, (DEBUG_MAP_PANEL_SIZE.y - VIEWPORT_SIZE.y) * 0.5 * audit_scale) # Align the camera at the map's vertical center.
		return                                                                                    # Skip the normal two-player, two-row layout.
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
		if is_instance_valid(child) and not child.is_queued_for_deletion():                       # Skip nodes already queued by an earlier redraw.
			debug_map_overlay.remove_child(child)                                                  # Detach it now so same-frame player-map redraws cannot overlap labels.
			child.queue_free()                                                                       # Queue the previous debug primitive for safe end-of-frame cleanup.
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
	_add_debug_all_wall_slot_numbers()                                                         # Draw the independent blue slot-number audit on every local slot candidate.
	_add_debug_raycast_rays()                                                                   # Draw sampled raycast lines and first-hit points so visibility can be inspected.
	_add_debug_visible_wall_slots()                                                            # Highlight the wall slots selected by the renderer on the source map.
	_add_debug_player_bounds(home_center)                                                       # Draw the playable/contact footprint inside the current cell.
	_add_debug_player_marker(home_center, Color(1.0, 1.0, 1.0, 0.35))                           # Draw a faint marker at the home center for offset comparison.
	var facing_end := player_center + _view_forward_vector() * (DEBUG_MAP_CELL_SIZE * 0.34)     # Compute the arrow tip from the actual current player position and visible camera direction.
	_add_debug_line(player_center, facing_end, player_color, 3.0)                               # Draw the player facing arrow shaft.
	_add_debug_arrow_head(facing_end, _view_forward_vector(), player_color)                     # Draw the player facing arrow head.
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



# _debug_map_camera_local_position: Converts a camera-local side/depth point into a debug overlay pixel position.
func _debug_map_camera_local_position(local_position: Vector2) -> Vector2:                   # Declare this function.
	var forward := _view_forward_vector().normalized()                                         # Use the active cardinal or 45-degree camera-forward vector.
	var right := _view_right_vector().normalized()                                             # Use the active cardinal or 45-degree camera-right vector.
	var origin := _camera_grid_origin_for_forward(forward)                                     # Rebuild the camera origin for the same basis used by visibility.
	var world_position := origin + right * local_position.x + forward * local_position.y       # Rotate the local side/depth sample into world-grid coordinates.
	return _debug_map_world_position(world_position)                                           # Convert the world-grid point into debug-map pixels.



# _debug_map_player_position: Converts the real player cell plus local offset into a top-down overlay point.
func _debug_map_player_position() -> Vector2:                                               # Declare this function.
	return _debug_map_world_position(_current_player_world_position())                         # Use the same diagonal-aware world point that movement and collision use.



# _add_debug_view_cone: Draws the cell-locked camera cone on top of the source-of-truth map.
func _add_debug_view_cone(origin: Vector2) -> void:                                        # Declare this function.
	var cone_color := Color(0.0, 0.75, 1.0, 0.22)                                            # Use translucent cyan for the cone fill.
	var cone_line_color := Color(0.0, 0.95, 1.0, 0.75)                                       # Use brighter cyan for the cone boundary lines.
	var forward := _view_forward_vector()                                                     # Convert the current visible camera-facing direction to overlay space.
	var left := _view_left_vector()                                                           # Convert the current visible camera-left direction to overlay space.
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



# _add_debug_raycast_rays: Draws the actual sampled visibility rays and where each ray first hits a wall.
func _add_debug_raycast_rays() -> void:                                                     # Declare this function.
	if not show_raycast_debug:                                                                 # Respect the inspector toggle for dense ray debugging.
		return                                                                                    # Return without drawing ray debug primitives.
	var origin_world := _camera_grid_origin()                                                  # Use the same camera origin that the renderer uses for visibility.
	var forward := _view_forward_vector().normalized()                                        # Use the active cardinal or 45-degree camera forward vector.
	var right := _view_right_vector().normalized()                                            # Use the active cardinal or 45-degree camera-right vector.
	var samples := _raycast_visibility_samples_for_basis(origin_world, forward, right)         # Build the same ray samples used by wall visibility.
	var origin := _debug_map_world_position(origin_world)                                      # Convert the camera origin to top-down overlay pixels.
	var hit_ray_color := Color(1.0, 0.85, 0.0, 0.55)                                          # Use amber for rays that hit a wall.
	var miss_ray_color := Color(0.0, 0.7, 1.0, 0.22)                                          # Use faint cyan for rays that reach max distance without a hit.
	var hit_dot_color := Color(1.0, 0.35, 0.0, 0.95)                                          # Use orange dots for exact first-hit points.
	var extra_hit_dot_color := Color(1.0, 0.05, 0.25, 0.85)                                   # Use red dots for farther 45-degree ray intersections behind the first hit.
	var stride := maxi(1, debug_raycast_stride)                                                # Clamp the stride so modulo math is always valid.
	var center_ray := int(VISIBILITY_RAY_COUNT / 2)                                           # Always draw the center ray, even if it falls between stride samples.
	var first_hit_keys := {}                                                                   # Track first-hit ray/distance pairs so all-hit debug does not duplicate them.
	for sample in samples:                                                                     # Draw each selected ray sample.
		var ray_index := int(sample["ray_index"])                                                 # Read the original ray index across the fan.
		if ray_index != 0 and ray_index != center_ray and ray_index != VISIBILITY_RAY_COUNT - 1 and ray_index % stride != 0: # Keep edges, center, and stride samples.
			continue                                                                                 # Skip this ray to reduce visual clutter.
		var hit_world: Vector2 = sample["hit_position"]                                           # Read the ray endpoint, either first hit or max distance.
		var hit_position := _debug_map_world_position(hit_world)                                  # Convert the endpoint into top-down overlay pixels.
		var ray_color := hit_ray_color if bool(sample["hit"]) else miss_ray_color                 # Color hit and miss rays differently.
		_add_debug_line(origin, hit_position, ray_color, 1.0)                                     # Draw the ray segment from camera origin to endpoint.
		if bool(sample["hit"]):                                                                   # Mark the exact wall-contact point when this ray hit something.
			first_hit_keys["%d:%.4f" % [ray_index, float(sample["distance"])]] = true                 # Remember this first-hit point before drawing farther 45-degree hit markers.
			_add_debug_raycast_hit_marker(hit_position, hit_dot_color)                               # Draw a compact first-hit marker at the endpoint.
	if _is_turn_45_view():                                                                     # The halfway-turn renderer can inspect farther wall hits beyond the first one.
		var all_hit_samples := _raycast_wall_hit_samples_for_basis(origin_world, forward, right)    # Build farther ray samples for debug markers without letting them render wall art.
		for sample in all_hit_samples:                                                            # Draw selected farther intersections for 45-degree slot debugging.
			var ray_index := int(sample["ray_index"])                                                 # Read this all-hit sample's ray index.
			if ray_index != 0 and ray_index != center_ray and ray_index != VISIBILITY_RAY_COUNT - 1 and ray_index % stride != 0: # Match the visible ray stride used above.
				continue                                                                                 # Skip this dense all-hit marker to keep the overlay readable.
			var hit_key := "%d:%.4f" % [ray_index, float(sample["distance"])]                         # Build the same key used for first-hit duplicate suppression.
			if first_hit_keys.has(hit_key):                                                           # Skip the nearest hit because it already has an orange marker.
				continue                                                                                 # Continue to the next all-hit sample.
			var hit_position := _debug_map_world_position(sample["hit_position"])                      # Convert this farther wall hit into top-down overlay pixels.
			_add_debug_raycast_hit_marker(hit_position, extra_hit_dot_color, 1.15)                     # Draw the farther hit as a smaller red marker.



# _add_debug_raycast_hit_marker: Adds a small diamond marker at one ray wall hit.
func _add_debug_raycast_hit_marker(position: Vector2, color: Color, radius := 1.8) -> void: # Declare this function.
	var marker := Polygon2D.new()                                                              # Create a filled marker for the ray hit point.
	marker.polygon = PackedVector2Array([                                                      # Define a diamond centered on the hit point.
		position + Vector2(0.0, -radius),                                                         # Add the top point.
		position + Vector2(radius, 0.0),                                                          # Add the right point.
		position + Vector2(0.0, radius),                                                          # Add the bottom point.
		position + Vector2(-radius, 0.0),                                                         # Add the left point.
	])                                                                                         # Close the marker polygon point list.
	marker.color = color                                                                       # Apply the requested marker color.
	debug_map_overlay.add_child(marker)                                                        # Add the marker to the debug map overlay.



# _add_debug_turn_45_sample_marker: Adds a square marker for the camera-local sample that chose one 45-degree wall id.
func _add_debug_turn_45_sample_marker(position: Vector2, color: Color) -> void:             # Declare this function.
	var marker := Polygon2D.new()                                                              # Create a filled marker for the footprint sample point.
	var radius := 2.6                                                                          # Make the sample marker slightly larger than a ray-hit marker.
	marker.polygon = PackedVector2Array([                                                      # Define a square centered on the footprint sample point.
		position + Vector2(-radius, -radius),                                                     # Add the top-left sample marker corner.
		position + Vector2(radius, -radius),                                                      # Add the top-right sample marker corner.
		position + Vector2(radius, radius),                                                       # Add the bottom-right sample marker corner.
		position + Vector2(-radius, radius),                                                      # Add the bottom-left sample marker corner.
	])                                                                                         # Close the sample marker polygon point list.
	marker.color = color                                                                       # Apply the requested sample marker color.
	debug_map_overlay.add_child(marker)                                                        # Add the marker to the debug map overlay.



# _add_debug_visible_wall_slots: Highlights the renderer-selected wall slots as green edge segments on the top-down map.
func _add_debug_visible_wall_slots() -> void:                                               # Declare this function.
	if not show_selected_wall_slot_debug:                                                     # Keep the selected-slot overlay hidden during the blue all-slot audit.
		return                                                                                    # Return without drawing green selected-wall lines or labels.
	var highlight_color := Color(0.0, 1.0, 0.25, 0.95)                                       # Use green to mark wall slots that the renderer currently selected.
	var sample_color := Color(1.0, 0.0, 0.85, 0.95)                                          # Use magenta for the sample point that selected the 45-degree art slot.
	var visible_slots := _build_strafe_render_list() if _is_strafe_view() else (_build_forward_render_list() if _is_forward_view() else (_build_turn_45_render_list() if _is_turn_45_view() else _build_straight_render_list())) # Rebuild the same active renderer list for all view types.
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
		if slot.has("sample_position"):                                                          # 45-degree slots preserve the exact camera-local point used by the mapper.
			var sample_position: Vector2 = slot["sample_position"]                                  # Read the sample side/depth coordinate chosen from the visible ray span.
			var sample_map_position := _debug_map_camera_local_position(sample_position)             # Convert the camera-local sample back to the top-down panel.
			_add_debug_turn_45_sample_marker(sample_map_position, sample_color)                      # Draw the mapper sample so incorrect id choices can be diagnosed.
			_add_debug_wall_slot_label(sample_map_position + Vector2(4.0, -8.0), wall_id, sample_color) # Label the sample with the selected 45-degree wall id.



# _add_debug_all_wall_slot_numbers: Draws every local slot definition in blue on the top-down source map.
func _add_debug_all_wall_slot_numbers() -> void:                                           # Declare this function.
	if not show_slot_grid_debug:                                                              # Respect the shared slot-grid diagnostic toggle.
		return                                                                                    # Return without adding any blue slot labels.
	if not _is_forward_view() and not _is_strafe_view() and not _is_turn_45_view():            # Only stable cardinal views use the established cardinal art-slot diagram.
		_add_cardinal_debug_slot_diagram()                                                         # Draw the world-space half of the same diagram used in the player view.
		return                                                                                    # Keep the old physical-edge audit isolated to the separate 45-degree guide.
	var stacked_labels := {}                                                                   # Track repeated map positions so labels do not completely overlap.
	for slot in _all_debug_wall_slot_segments():                                               # Visit every cardinal or halfway-turn local slot candidate.
		if not slot.has("a") or not slot.has("b"):                                                # Require physical source-map endpoints.
			continue                                                                                 # Continue to the next slot when geometry is incomplete.
		var wall_id := int(slot["id"])                                                            # Read the local player-view slot number.
		var start := _debug_map_world_position(slot["a"])                                         # Convert endpoint A into top-down overlay pixels.
		var end := _debug_map_world_position(slot["b"])                                           # Convert endpoint B into top-down overlay pixels.
		var color := SLOT_GRID_DEBUG_WALL_COLOR if bool(slot["has_wall"]) else SLOT_GRID_DEBUG_OPEN_COLOR # Brighten blocked edges and fade open slot locations.
		_add_debug_line(start, end, color, 1.35)                                                   # Draw the blue slot audit segment on the source map.
		var midpoint := (start + end) * 0.5                                                        # Center the label on this source-map edge.
		var stack_key := "%d,%d" % [int(round(midpoint.x)), int(round(midpoint.y))]                # Quantize the label point so repeated slots can be offset.
		var stack_index := int(stacked_labels.get(stack_key, 0))                                   # Read how many labels have already used this point.
		stacked_labels[stack_key] = stack_index + 1                                                # Record that this point now has another label.
		_add_debug_wall_slot_label(midpoint + Vector2(0.0, float(stack_index) * 5.0), wall_id, SLOT_GRID_DEBUG_LABEL_COLOR) # Label the slot with a blue two-digit id.



# _add_cardinal_debug_slot_diagram: Draws the canonical art-slot diagram around the current cell's fixed center.
func _add_cardinal_debug_slot_diagram() -> void:                                            # Declare this function.
	var active_ids := _debug_slot_has_wall_by_id()                                             # Use the renderer's final art-slot selection for the matching color state.
	var forward := Vector2(_facing_vector()).normalized()                                     # Rotate the diagram with the cardinal view direction only.
	var right := Vector2(-_left_vector()).normalized()                                        # Use a cardinal camera-right axis for the matching rotation.
	var pivot := Vector2(float(grid_position.x) + 0.5, float(grid_position.y) + 0.5)          # Anchor at the current cell's fixed grid center, never the rear camera origin.
	for slot in _cardinal_debug_slot_records():                                                # Draw every stable transparent-wall art-slot guide record.
		var local_label: Vector2 = slot["local_label"]                                           # Read the matching shared label point.
		var local_a: Vector2 = slot["map_a"]                                                      # Read the exact blue source-grid segment endpoint A for this ID.
		var local_b: Vector2 = slot["map_b"]                                                      # Read the exact blue source-grid segment endpoint B for this ID.
		var start := _debug_map_world_position(pivot + right * local_a.x * CARDINAL_SLOT_GUIDE_MAP_SCALE - forward * local_a.y * CARDINAL_SLOT_GUIDE_MAP_SCALE) # Rotate this owned source-grid segment into world space.
		var end := _debug_map_world_position(pivot + right * local_b.x * CARDINAL_SLOT_GUIDE_MAP_SCALE - forward * local_b.y * CARDINAL_SLOT_GUIDE_MAP_SCALE)     # Keep the matching segment aligned with its label.
		var label := _debug_map_world_position(pivot + right * local_label.x * CARDINAL_SLOT_GUIDE_MAP_SCALE - forward * local_label.y * CARDINAL_SLOT_GUIDE_MAP_SCALE) # Keep far art-slot labels ahead of the player inside the matching cone.
		var wall_id := int(slot["id"])                                                            # Read the stable art-slot ID.
		var color := SLOT_GRID_DEBUG_WALL_COLOR if bool(active_ids.get(wall_id, false)) else SLOT_GRID_DEBUG_OPEN_COLOR # Match player-view and world-diagram selection state.
		_add_debug_line(start, end, color, 1.0)                                                    # Draw only the blue source-grid segment owned by this ID.
		_add_debug_wall_slot_label(label, wall_id, color)                                         # Draw exactly one rotating top-down label for this art slot.



# _all_debug_wall_slot_segments: Returns the diagnostic local slot segments for the current cardinal or halfway-turn view.
func _all_debug_wall_slot_segments() -> Array:                                             # Declare this function.
	if _is_strafe_view():                                                                      # Side stages expose their own source-map topology.
		var strafe_segments := []                                                                # Build the independent source segments for this right-transition stage.
		for slot in _strafe_slot_records():                                                      # Visit every authored side-stage source edge.
			var segment := _strafe_slot_world_segment(slot)                                        # Rotate and snap this edge into the active cardinal world basis.
			strafe_segments.append({"id": int(slot["id"]), "a": segment[0], "b": segment[1], "has_wall": _segment_has_wall_for_debug(segment[0], segment[1])}) # Keep map and player-view labels paired.
		return strafe_segments                                                                   # Return before straight/forward/turn fallbacks.
	if _is_forward_view():                                                                      # Forward stages expose their own source-map topology.
		var forward_segments := []
		for slot in _forward_slot_records():
			var segment := _forward_slot_world_segment(slot)
			forward_segments.append({"id": int(slot["id"]), "a": segment[0], "b": segment[1], "has_wall": _segment_has_wall_for_debug(segment[0], segment[1])})
		return forward_segments
	if _is_turn_45_view():                                                                    # Use the 16-slot halfway-turn audit table for diagonal views.
		return _turn_debug_wall_slot_segments()                                                   # Return the active 22, 45, or 66-degree graph.
	return _straight_debug_wall_slot_segments()                                                # Return the 28 straight slot candidates.


# _turn_stage_debug_wall_slot_segments: Returns the actual ray-selected source edges for a 22 or 66-degree stage.
func _turn_stage_debug_wall_slot_segments() -> Array:
	var segments := []                                                                         # Store the current stage's physical wall-edge diagnostics.
	for slot in _build_turn_45_render_list():                                                  # Reuse the active camera basis and its visibility-selected wall slots.
		if not slot.has("segment_a") or not slot.has("segment_b"):                              # Require the concrete source-map edge attached by the renderer.
			continue                                                                                # Skip incomplete records defensively.
		segments.append({"id": int(slot["id"]), "a": slot["segment_a"], "b": slot["segment_b"], "has_wall": true}) # Keep the guide attached to the actual selected map edge.
	return segments                                                                            # Return the stage-specific selected-edge diagnostic list.



# _straight_debug_wall_slot_segments: Converts all 28 straight local slots into source-map edge segments.
func _straight_debug_wall_slot_segments() -> Array:                                        # Declare this function.
	var segments := []                                                                         # Store diagnostic straight-view slot records.
	for slot in STRAIGHT_WALL_SLOTS:                                                          # Visit every numbered straight-view slot definition.
		var physical_segment := _physical_wall_slot_segment(slot)                                 # Convert this local slot to its physical source-map edge.
		if physical_segment.size() < 2:                                                          # Skip malformed slot metadata defensively.
			continue                                                                                 # Continue to the next straight slot.
		segments.append({                                                                         # Store the independent diagnostic segment record.
			"id": int(slot["id"]),                                                                   # Preserve the local wall-slot id.
			"a": physical_segment[0],                                                               # Store physical endpoint A in world-grid coordinates.
			"b": physical_segment[1],                                                               # Store physical endpoint B in world-grid coordinates.
			"has_wall": _segment_has_wall_for_debug(physical_segment[0], physical_segment[1]),      # Record whether this source-map edge is actually blocked.
		})                                                                                        # Close this straight diagnostic slot record.
	return segments                                                                            # Return all 28 straight diagnostic slots.



# _turn_debug_wall_slot_segments: Converts the active authored turn graph into source-map edge segments.
func _turn_debug_wall_slot_segments() -> Array:
	var segments := []                                                                         # Store diagnostic halfway-turn slot records.
	for slot_edge in _active_turn_slot_edges():                                                # Visit each unique edge from the active 22, 45, or 66-degree graph.
		var wall_id := int(slot_edge["id"])                                                     # Read the local halfway-turn wall-slot id.
		var physical_segment := _turn_45_slot_edge_world_segment(slot_edge)                      # Rotate this authored local edge into the current world-grid orientation.
		if physical_segment.size() < 2:                                                         # Skip malformed snapped geometry defensively.
			continue                                                                                # Continue to the next halfway-turn slot.
		segments.append({                                                                        # Store the independent diagnostic segment record.
			"id": wall_id,                                                                          # Preserve the local halfway-turn wall-slot id.
			"a": physical_segment[0],                                                              # Store physical endpoint A in world-grid coordinates.
			"b": physical_segment[1],                                                              # Store physical endpoint B in world-grid coordinates.
			"has_wall": _segment_has_wall_for_debug(physical_segment[0], physical_segment[1]),     # Record whether this source-map edge is actually blocked.
		})                                                                                       # Close this halfway-turn diagnostic slot record.
	return segments                                                                            # Return all 16 halfway-turn diagnostic slots.


# _active_turn_slot_edges: Selects the independent authored graph for the current turn stage.
func _active_turn_slot_edges() -> Array:
	match _active_turn_visual_stage():                                                          # Keep each authored interpolation frame tied to its own source-edge graph.
		1:                                                                                       # The first stop is the 22-degree frame.
			return TURN_22_DIAGNOSTIC_SLOT_EDGES                                                   # Select the 17 edges that own the WallsTurn_22 art.
		3:                                                                                       # The last stop is the 66-degree frame.
			return TURN_66_DIAGNOSTIC_SLOT_EDGES                                                   # Select the 17 edges that own the WallsTurn_66 art.
		_:
			return TURN_45_DIAGNOSTIC_SLOT_EDGES                                                   # Preserve the established 45-degree graph at the midpoint.



# _active_turn_visual_stage: Returns the clockwise-authored art phase currently visible to the player.
func _active_turn_visual_stage() -> int:
	if turn_45_direction < 0:                                                                  # A counterclockwise turn walks the N-to-E reference art backwards.
		return 4 - turn_step                                                                     # Map input steps 1/2/3 to visual phases 66/45/22.
	return turn_step                                                                           # Keep clockwise turns in their authored 22/45/66 order.



# _turn_45_canonical_base_facing: Returns the clockwise cardinal base for the active diagonal view.
func _turn_45_canonical_base_facing() -> int:                                             # Declare this function.
	if turn_45_direction < 0:                                                               # A left turn enters the same diagonal from the clockwise base's next cardinal.
		return wrapi(facing - 1, 0, 4)                                                         # Convert S-left to E-right, E-left to N-right, and so on.
	return facing                                                                            # A right turn is already using the clockwise base cardinal.



# _turn_45_slot_edge_world_segment: Converts one corrected 45-degree u/v slot edge into a world-grid segment.
func _turn_45_slot_edge_world_segment(slot_edge: Dictionary) -> Array[Vector2]:             # Declare this function.
	var canonical_facing := _turn_45_canonical_base_facing()                                  # Normalize left/right entry routes into one diagonal-local basis.
	var canonical_forward := Vector2(_facing_vector_for_index(canonical_facing))              # Use the clockwise base cardinal as the local v axis.
	var canonical_right := Vector2(-_left_vector_for_index(canonical_facing))                 # Use the clockwise base cardinal's camera-right as the local u axis.
	var cell_center := Vector2(float(grid_position.x) + 0.5, float(grid_position.y) + 0.5)    # Compute the current cell center in world-grid units.
	var local_origin_corner := cell_center + (canonical_forward - canonical_right) * 0.5      # Anchor u/v coordinates on the canonical diagonal source corner.
	var local_a: Vector2 = slot_edge["a"]                                                     # Read endpoint A in corrected u/v coordinates.
	var local_b: Vector2 = slot_edge["b"]                                                     # Read endpoint B in corrected u/v coordinates.
	var world_a := local_origin_corner + canonical_right * local_a.x + canonical_forward * local_a.y # Rotate endpoint A into world-grid coordinates.
	var world_b := local_origin_corner + canonical_right * local_b.x + canonical_forward * local_b.y # Rotate endpoint B into world-grid coordinates.
	return [world_a, world_b]                                                                 # Return the corrected physical grid-edge segment.



# _turn_45_debug_local_tangent_for_column: Returns a camera-local tangent for one halfway-turn slot column.
func _turn_45_debug_local_tangent_for_column(column_index: int) -> Vector2:                 # Declare this function.
	if column_index < 2:                                                                       # Treat the two local-left columns as one diagonal wall family.
		return Vector2(0.45, -0.45)                                                              # Return a slash-like local tangent for that family.
	return Vector2(0.45, 0.45)                                                                 # Return a backslash-like local tangent for the two local-right columns.



# _snapped_debug_segment_from_camera_local: Converts a local diagnostic wall candidate into the nearest real grid edge.
func _snapped_debug_segment_from_camera_local(local_center: Vector2, local_tangent: Vector2) -> Array[Vector2]: # Declare this function.
	var world_center := _camera_local_to_world(local_center)                                   # Convert the local candidate center into world-grid coordinates.
	var world_tangent := _camera_local_to_world(local_center + local_tangent) - world_center   # Convert the local tangent into world-grid orientation.
	if absf(world_tangent.y) >= absf(world_tangent.x):                                        # Snap mostly vertical candidates to a north/south grid line.
		var x: float = round(world_center.x)                                                     # Snap the wall x coordinate to the nearest vertical grid line.
		var y0: float = floor(world_center.y)                                                    # Start the segment at the containing grid row.
		return [Vector2(x, y0), Vector2(x, y0 + 1.0)]                                            # Return the snapped vertical grid edge.
	var y: float = round(world_center.y)                                                      # Snap the wall y coordinate to the nearest horizontal grid line.
	var x0: float = floor(world_center.x)                                                     # Start the segment at the containing grid column.
	return [Vector2(x0, y), Vector2(x0 + 1.0, y)]                                             # Return the snapped horizontal grid edge.



# _camera_local_to_world: Converts a camera-local side/depth point into world-grid coordinates.
func _camera_local_to_world(local_position: Vector2) -> Vector2:                            # Declare this function.
	var forward := _view_forward_vector().normalized()                                        # Use the active cardinal or halfway-turn camera-forward vector.
	var right := _view_right_vector().normalized()                                            # Use the active cardinal or halfway-turn camera-right vector.
	var origin := _camera_grid_origin_for_forward(forward)                                    # Rebuild the camera origin for this basis.
	return origin + right * local_position.x + forward * local_position.y                     # Return the rotated world-grid point.



# _camera_local_point_from_world: Converts a world-grid coordinate into active camera-local side/depth coordinates.
func _camera_local_point_from_world(world_position: Vector2) -> Vector2:                    # Declare this function.
	var forward := _view_forward_vector().normalized()                                        # Use the active cardinal or halfway-turn camera-forward vector.
	var right := _view_right_vector().normalized()                                            # Use the active cardinal or halfway-turn camera-right vector.
	var origin := _camera_grid_origin_for_forward(forward)                                    # Rebuild the camera origin for this basis.
	var relative := world_position - origin                                                   # Measure this point relative to the camera origin.
	return Vector2(relative.dot(right), relative.dot(forward))                                # Return side/depth in camera-local coordinates.



# _segment_has_wall_for_debug: Reports whether a diagnostic source-map segment exactly matches a blocking wall edge.
func _segment_has_wall_for_debug(a: Vector2, b: Vector2) -> bool:                           # Declare this function.
	var key := _physical_edge_key(a, b)                                                        # Build the canonical key for this source-map segment.
	for edge in _all_physical_wall_edges():                                                    # Scan the current thin-wall map's blocking edges.
		if String(edge["key"]) == key:                                                            # Match this diagnostic segment to a real wall.
			return true                                                                              # Report that the source edge is blocked.
	return false                                                                               # Report that this local slot location is open.



# _debug_physical_wall_edge_segment: Converts a ray-hit physical wall edge into top-down overlay points.
func _debug_physical_wall_edge_segment(edge: Dictionary) -> Array[Vector2]:                 # Declare this function.
	if not edge.has("a") or not edge.has("b"):                                                # Require both physical wall endpoints.
		return []                                                                               # Return no segment when edge metadata is incomplete.
	return [_debug_map_world_position(edge["a"]), _debug_map_world_position(edge["b"])]        # Convert physical grid endpoints into debug-map pixel coordinates.



# _debug_wall_slot_segment: Converts a visible 2D wall slot into its corresponding source-map edge segment.
func _debug_wall_slot_segment(slot: Dictionary) -> Array[Vector2]:                          # Declare this function.
	if slot.has("segment_a") and slot.has("segment_b"):                                      # 45-degree slots preserve their ray-hit physical edge directly.
		return [_debug_map_world_position(slot["segment_a"]), _debug_map_world_position(slot["segment_b"])] # Convert the preserved physical segment into debug-map coordinates.
	if slot.has("a") and slot.has("b"):                                                      # Strafe render records already carry their exact selected world-edge endpoints.
		return [_debug_map_world_position(slot["a"]), _debug_map_world_position(slot["b"])]       # Convert those direct endpoints into the green selected-slot overlay segment.
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
		Vector2(DEBUG_MAP_PANEL_SIZE.x, 0.0),                                                     # Add the top-right corner.
		DEBUG_MAP_PANEL_SIZE,                                                                     # Add the bottom-right corner.
		Vector2(0.0, DEBUG_MAP_PANEL_SIZE.y),                                                     # Add the bottom-left corner.
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
		var other_forward := _view_forward_vector_for_state(other_state)                            # Read the other player's cardinal or temporary diagonal view direction.
		var facing_end := other_center + other_forward * (DEBUG_MAP_CELL_SIZE * 0.26)               # Compute the other player's facing arrow tip.
		_add_debug_line(other_center, facing_end, other_color, 2.0)                                # Draw the other player's facing arrow shaft.
		_add_debug_arrow_head(facing_end, other_forward, other_color)                              # Draw the other player's facing arrow head.
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



# _load_turn_wall_textures: Loads the transparent overlays used at each view-relative turn stage.
func _load_turn_wall_textures() -> void:                                                   # Declare this function.
	turn_22_wall_textures = _load_numbered_turn_wall_textures(WALLS_TURN_22_ROOT, "WallsTurn_22", 17) # Load the first interpolation stage.
	turn_45_wall_textures = _load_numbered_turn_wall_textures(WALLS_TURN_45_ROOT, "WallsTurn_45", 16) # Load the diagonal halfway stage.
	turn_66_wall_textures = _load_numbered_turn_wall_textures(WALLS_TURN_66_ROOT, "WallsTurn_66", 17) # Load the final interpolation stage.


# _load_forward_wall_textures: Loads the two standalone floor frames and their transparent forward wall overlays.
func _load_forward_wall_textures() -> void:
	floor_fwd_1_texture = _load_png_texture(FLOOR_FWD_1_TEXTURE)                              # Load the first forward floor independently of the turn texture strip.
	floor_fwd_2_texture = _load_png_texture(FLOOR_FWD_2_TEXTURE)                              # Load the second forward floor independently of the turn texture strip.
	fwd_1_wall_textures = _load_numbered_turn_wall_textures(WALLS_FWD_1_ROOT, "WallsFwd_1", 20) # Load every numbered first forward overlay.
	fwd_2_wall_textures = _load_numbered_turn_wall_textures(WALLS_FWD_2_ROOT, "WallsFwd_2", 26) # Load every numbered second forward overlay.


# _load_strafe_wall_textures: Loads the three standalone local-right floor frames and numbered transparent wall overlays.
func _load_strafe_wall_textures() -> void:
	floor_right_1_texture = _load_png_texture(FLOOR_RIGHT_1_TEXTURE)                          # Load the first rightward camera floor frame.
	floor_right_2_texture = _load_png_texture(FLOOR_RIGHT_2_TEXTURE)                          # Load the second rightward camera floor frame.
	floor_right_3_texture = _load_png_texture(FLOOR_RIGHT_3_TEXTURE)                          # Load the third rightward camera floor frame.
	right_1_wall_textures = _load_numbered_turn_wall_textures(WALLS_RIGHT_1_ROOT, "WallsRight_1", 24) # Load every first-stage transparent overlay.
	right_2_wall_textures = _load_numbered_turn_wall_textures(WALLS_RIGHT_2_ROOT, "WallsRight_2", 22) # Load every middle-stage transparent overlay.
	right_3_wall_textures = _load_numbered_turn_wall_textures(WALLS_RIGHT_3_ROOT, "WallsRight_3", 24) # Load every final-stage transparent overlay.



# _load_numbered_turn_wall_textures: Loads one numbered transparent wall-overlay set.
func _load_numbered_turn_wall_textures(root: String, prefix: String, count: int) -> Dictionary:
	var textures: Dictionary = {}                                                             # Store textures by their view-relative wall id.
	for wall_id in range(1, count + 1):                                                       # Visit every authored overlay in this turn stage.
		var texture := _load_png_texture("%s/%s_%02d.png" % [root, prefix, wall_id])             # Load one transparent full-screen overlay.
		if texture != null:                                                                       # Keep only successfully loaded assets.
			textures[wall_id] = texture                                                             # Cache the texture by its local slot id.
	return textures                                                                            # Return the completed texture lookup.



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
		if _is_strafe_view() and not _active_strafe_wall_textures().is_empty():                  # Keep each side camera stage on its own floor and slot grid.
			_render_strafe_wall_view()                                                              # Compose the active side floor followed by its wall overlays.
			return                                                                                    # Do not fall through to forward, cardinal, or turn rendering.
		if _is_forward_view() and not _active_forward_wall_textures().is_empty():                # Keep each forward camera stage on its own floor and slot grid.
			_render_forward_wall_view()                                                              # Compose the active forward floor followed by its wall overlays.
			return                                                                                    # Do not fall through to cardinal or turn rendering.
		if _is_turn_45_view() and not _active_turn_wall_textures().is_empty():                    # Use the active 22, 45, or 66-degree art while a turn is in progress.
			_render_turn_45_wall_view()                                                              # Compose the temporary 45-degree wall view.
			return                                                                                    # Return after rendering the halfway-turn view.
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
	if TEMP_EMPTY_GRID_AUDIT:                                                                  # Keep only the explicitly wall-free audit camera free of baked and transparent wall art.
		if floor_sprite != null:                                                                 # Use the real captured floor/ceiling strip, not a procedural substitute.
			floor_sprite.visible = true                                                              # Show the base environment frame.
			floor_sprite.texture = floor_texture                                                     # Use assets/Environment/Floor_Turn.png.
			floor_sprite.region_rect = Rect2(0.0, 0.0, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y)             # Draw only its first straight-view 160x120 frame.
			floor_sprite.position = Vector2.ZERO                                                     # Keep the frame aligned to the camera crop.
		var audit_background := environment_layer.get_node_or_null("EmptyGridAuditEnvironment") as Node2D # Find any earlier procedural placeholder from this temporary mode.
		if audit_background != null:                                                              # The captured floor frame replaces that placeholder.
			audit_background.visible = false                                                         # Hide it without deleting nodes from a live scene.
		for wall_id in straight_wall_nodes.keys():                                                 # Ensure every transparent numbered wall overlay is hidden.
			straight_wall_nodes[wall_id].visible = false                                              # Suppress wall art regardless of map/raycast state.
		last_visible_wall_ids.clear()                                                             # Report no selected wall art in the status/debug overlays.
		return                                                                                    # Skip the normal captured corridor base and wall-render list.

	if floor_sprite != null:                                                                   # Run the following block only when this condition is true.
		floor_sprite.visible = true                                                               # Update the reusable base floor sprite.
		floor_sprite.region_enabled = true                                                        # Restore turn-strip cropping after a standalone forward floor was shown.
		floor_sprite.texture = floor_texture                                                      # Update the reusable base floor sprite.
		floor_sprite.region_rect = Rect2(0.0, 0.0, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y)              # Use the first floor-strip frame for straight cardinal views.
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



# _render_empty_grid_audit_environment: Draws a wall-free floor and ceiling for the open-grid slot audit.
func _render_empty_grid_audit_environment() -> void:
	if floor_sprite != null:                                                                   # The captured base frame contains baked corridor walls, so hide it in this mode.
		floor_sprite.visible = false                                                               # Keep only the procedural, wall-free background visible.
	var root := environment_layer.get_node_or_null("EmptyGridAuditEnvironment") as Node2D     # Reuse the simple background across redraws.
	if root == null:                                                                           # Create it only once for this single-player temporary mode.
		root = Node2D.new()                                                                       # Hold the ceiling, horizon, and floor color fields.
		root.name = "EmptyGridAuditEnvironment"                                                   # Make the temporary renderer identifiable in the scene tree.
		environment_layer.add_child(root)                                                         # Place it behind player sprites and debug overlays.
		var ceiling := Polygon2D.new()                                                            # Create a flat ceiling field with no wall geometry.
		ceiling.polygon = PackedVector2Array([Vector2(0, 0), Vector2(160, 0), Vector2(160, 46), Vector2(0, 46)]) # Fill the upper camera area.
		ceiling.color = Color("a87749")                                                           # Use the existing environment's ceiling family without copying any wall pixels.
		root.add_child(ceiling)                                                                   # Add the ceiling first, behind the horizon and floor.
		var horizon := Polygon2D.new()                                                            # Create a narrow empty horizon gap between ceiling and floor.
		horizon.polygon = PackedVector2Array([Vector2(0, 46), Vector2(160, 46), Vector2(160, 54), Vector2(0, 54)]) # Keep the distance field wall-free.
		horizon.color = Color("171717")                                                           # Use a dark open-space band instead of a back wall.
		root.add_child(horizon)                                                                   # Add the empty horizon after the ceiling.
		var floor := Polygon2D.new()                                                              # Create the perspective floor field below the horizon.
		floor.polygon = PackedVector2Array([Vector2(52, 54), Vector2(108, 54), Vector2(160, 120), Vector2(0, 120)]) # Draw an open floor trapezoid with no wall surfaces.
		floor.color = Color("ffbd78")                                                             # Use the existing floor palette without wall geometry.
		root.add_child(floor)                                                                     # Add the floor below the open horizon.
		for floor_y in [66.0, 82.0, 102.0]:                                                      # Add receding cross-lines so the floor still communicates camera perspective.
			var ratio: float = (floor_y - 54.0) / 66.0                                                # Convert this depth row into a 0..1 floor interpolation.
			var left_x := lerpf(52.0, 0.0, ratio)                                                    # Expand the floor's left edge toward the near camera edge.
			var right_x := lerpf(108.0, 160.0, ratio)                                                # Expand the floor's right edge toward the near camera edge.
			_add_empty_audit_floor_line(root, Vector2(left_x, floor_y), Vector2(right_x, floor_y))   # Draw one crisp receding horizontal floor seam.
		for floor_x in [0.0, 40.0, 80.0, 120.0, 160.0]:                                          # Add floor depth lines that converge at the open horizon.
			_add_empty_audit_floor_line(root, Vector2(80.0, 54.0), Vector2(floor_x, 120.0))          # Draw one perspective ray without introducing a wall.
	root.visible = true                                                                         # Keep the procedural floor/ceiling visible on every redraw.



# _add_empty_audit_floor_line: Adds a crisp perspective seam to the procedural wall-free floor.
func _add_empty_audit_floor_line(parent: Node2D, start: Vector2, end: Vector2) -> void:
	var line := Line2D.new()                                                                    # Create one thin floor-grid seam.
	line.points = PackedVector2Array([start, end])                                             # Set its perspective endpoints.
	line.width = 1.0                                                                            # Match the pixel-art floor seam weight.
	line.default_color = Color("8b5f3c")                                                       # Use a muted brown floor-line color.
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                                    # Keep the seam crisp at scaled resolutions.
	parent.add_child(line)                                                                      # Add the seam above the flat floor polygon.



# _render_turn_45_wall_view: Composes the active 22, 45, or 66-degree turn environment from its authored floor frame and overlays.
func _render_turn_45_wall_view() -> void:                                                  # Declare this function.
	_hide_slot_nodes()                                                                         # Hide legacy coarse slot sprites before drawing full-screen wall overlays.

	if floor_sprite != null:                                                                   # Configure the base floor sprite when it exists.
		floor_sprite.visible = true                                                               # Show the floor underneath the transparent 45-degree walls.
		floor_sprite.region_enabled = true                                                        # Restore turn-strip cropping after a standalone forward floor was shown.
		floor_sprite.texture = floor_texture                                                      # Use the shared floor strip texture.
		floor_sprite.region_rect = Rect2(0.0, VIEWPORT_SIZE.y * float(_active_turn_visual_stage()), VIEWPORT_SIZE.x, VIEWPORT_SIZE.y) # Use the clockwise-authored floor frame, reversing it for counterclockwise turns.
		floor_sprite.position = Vector2.ZERO                                                      # Keep the floor aligned to the playfield origin.

	for wall_id in straight_wall_nodes.keys():                                                 # Reuse the existing numbered wall sprite nodes for this temporary renderer.
		var wall_sprite: Sprite2D = straight_wall_nodes[wall_id]                                  # Read one reusable full-screen wall sprite.
		wall_sprite.visible = false                                                               # Hide stale straight or 45-degree wall art before drawing the new list.

	var visible_slots := _build_turn_45_render_list()                                         # Build the visible 45-degree wall list from the diagonal top-down ray fan.
	last_visible_wall_ids.clear()                                                              # Reset the debug list of wall ids selected this frame.
	for visible_slot in visible_slots:                                                         # Iterate through selected slots for debug reporting.
		last_visible_wall_ids.append(int(visible_slot["id"]))                                     # Record this 45-degree wall id for the status label.

	visible_slots.sort_custom(func(a, b): return int(a["draw"]) < int(b["draw"]))              # Sort back-to-front so nearer overlays paint over farther overlays.

	for slot in visible_slots:                                                                 # Draw every selected 45-degree wall overlay.
		var wall_id := int(slot["id"])                                                            # Read the numbered halfway-turn wall id.
		var wall_sprite: Sprite2D = straight_wall_nodes.get(wall_id)                              # Reuse the matching numbered sprite node.
		var texture: Texture2D = _active_turn_wall_textures().get(wall_id)                         # Read the active turn-stage wall texture for this id.
		if wall_sprite == null or texture == null:                                                # Skip incomplete texture/node pairs defensively.
			continue                                                                                 # Continue to the next visible wall slot.
		wall_sprite.texture = texture                                                             # Draw the 45-degree full-screen overlay texture.
		wall_sprite.position = Vector2.ZERO                                                       # Keep the full-screen overlay aligned to the playfield origin.
		wall_sprite.z_index = int(slot["draw"])                                                   # Apply the diagram's back-to-front draw order.
		wall_sprite.visible = true                                                                # Show this selected 45-degree wall.
		_position_wall_debug_label(wall_id, texture)                                              # Place the yellow wall id over the visible art for validation.

	if enable_3d_diagnostic:                                                                   # Only mirror labels into the deprecated 3D diagnostic when it is active.
		_hide_3d_slot_labels()                                                                    # Hide 3D labels because the diagnostic model has no diagonal wall slots yet.


# _active_turn_wall_textures: Returns the view-relative wall art for the current interpolation stage.
func _active_turn_wall_textures() -> Dictionary:
	match _active_turn_visual_stage():
		1:
			return turn_22_wall_textures                                                          # Use 22-degree art immediately after leaving a cardinal view.
		3:
			return turn_66_wall_textures                                                          # Use 66-degree art immediately before reaching the next cardinal view.
		_:
			return turn_45_wall_textures                                                          # Use the existing 45-degree art at the diagonal midpoint.


# _is_forward_view: Reports whether a live forward camera frame is visible.
func _is_forward_view() -> bool:
	return forward_step != 0                                                                    # A manual step holds the same live stage rather than using a separate frozen debug state.


# _active_forward_visual_stage: Returns the currently visible Fwd art stage.
func _active_forward_visual_stage() -> int:
	return forward_step                                                                         # Manual mode holds this live stage until the next forward input.


# _active_forward_wall_textures: Returns the texture set paired with the active forward floor frame.
func _active_forward_wall_textures() -> Dictionary:
	return fwd_1_wall_textures if _active_forward_visual_stage() == 1 else fwd_2_wall_textures # Each stage owns a separate numbered overlay set.


# _render_forward_wall_view: Composes an authored forward floor, then transparent walls, in back-to-front order.
func _render_forward_wall_view() -> void:
	_hide_slot_nodes()                                                                         # Remove obsolete coarse environment sprites before the full-frame composition.
	if floor_sprite != null:                                                                   # Reuse the floor node that always sits beneath the wall overlay nodes.
		floor_sprite.visible = true                                                               # Keep the floor visible before drawing transparent wall layers.
		floor_sprite.region_enabled = false                                                       # Forward floors are individual 160x120 images, not frames in the turn strip.
		floor_sprite.texture = floor_fwd_1_texture if _active_forward_visual_stage() == 1 else floor_fwd_2_texture # Pair floor and wall stage exactly.
		floor_sprite.position = Vector2.ZERO                                                      # Align the standalone floor image with the playfield origin.
	for wall_id in straight_wall_nodes.keys():                                                 # Clear any previous cardinal, turn, or forward wall overlays.
		straight_wall_nodes[wall_id].visible = false                                               # Avoid stale pixels from an earlier renderer mode.
	var visible_slots := _build_forward_render_list()                                          # Resolve this stage's independent source-grid wall slots.
	last_visible_wall_ids.clear()                                                              # Keep status and selected-slot debugging tied to the active forward renderer.
	for slot in visible_slots:
		last_visible_wall_ids.append(int(slot["id"]))                                            # Record every overlay actually selected this frame.
	visible_slots.sort_custom(func(a, b): return int(a["draw"]) < int(b["draw"]))            # Paint distant overlays first so nearer walls remain in front.
	for slot in visible_slots:
		var wall_id := int(slot["id"])                                                          # Read the numbered art slot.
		var wall_sprite: Sprite2D = straight_wall_nodes.get(wall_id)                              # Reuse the matching full-frame wall node.
		var texture: Texture2D = _active_forward_wall_textures().get(wall_id)                     # Read this stage's transparent wall asset.
		if wall_sprite == null or texture == null:
			continue
		wall_sprite.texture = texture                                                             # Draw the transparent wall artwork over the floor.
		wall_sprite.position = Vector2.ZERO                                                       # Keep all overlays in the authored 160x120 coordinate system.
		wall_sprite.z_index = int(slot["draw"])                                                  # Preserve the stage grid's back-to-front visibility order.
		wall_sprite.visible = true                                                                # Reveal this selected wall overlay.
		_position_wall_debug_label(wall_id, texture)                                              # Mark the selected asset itself when Selected Slots is enabled.


# _forward_slot_records: Builds independent local/world slot graphs for the two forward frames.
func _forward_slot_records() -> Array:
	return FWD_1_DIAGNOSTIC_SLOT_EDGES if _active_forward_visual_stage() == 1 else FWD_2_DIAGNOSTIC_SLOT_EDGES # Use the authored frame-specific source map; never synthesize a generic fan.


# _forward_view_slot_screen_segments: Projects the authored Fwd source graph directly onto its painted floor perspective.
func _forward_view_slot_screen_segments() -> Array:
	var segments := []                                                                         # Store one local debug vector per numbered Fwd asset.
	for slot in _forward_slot_records():                                                       # Visit the same immutable local topology used by renderer selection and the top-down graph.
		var screen_a := _forward_authored_floor_screen_point(slot["a"])                          # Place the first source endpoint on the matching Fwd floor grid.
		var screen_b := _forward_authored_floor_screen_point(slot["b"])                          # Place the second source endpoint on that same player-local floor grid.
		var wall_id := int(slot["id"])                                                          # Keep source edge, transparent art ID, and local vector 1:1.
		segments.append(_view_slot_screen_record(wall_id, screen_a, screen_b, (screen_a + screen_b) * 0.5)) # Let the user fine-tune a coherent connected graph rather than isolated texture ticks.
	return segments                                                                             # Return the active Fwd frame's player-local slot graph.


# _forward_slot_world_segment: Rotates one forward-grid source edge into the cardinal world-map basis.
func _forward_slot_world_segment(slot: Dictionary) -> Array[Vector2]:
	var frame_offset := FWD_GRAPH_FORWARD_OFFSET if forward_transition_name != "backward" else Vector2.ZERO # Reverse playback keeps the authored Fwd graphs in place instead of backing them into the destination cell.
	var local_a: Vector2 = slot["a"] + frame_offset                                          # Read the first endpoint in the independent forward-grid basis.
	var local_b: Vector2 = slot["b"] + frame_offset                                          # Read the second endpoint in the independent forward-grid basis.
	return _snapped_debug_segment_from_camera_local((local_a + local_b) * 0.5, local_b - local_a) # Snap the authored guide edge onto its corresponding real thin-wall map edge.


# _build_forward_render_list: Selects visible blocked edges from the active forward frame's own graph.
func _build_forward_render_list() -> Array:
	var visible_edges := {}                                                                    # Index first-hit physical walls to avoid drawing geometry hidden behind nearer walls.
	if forward_transition_name != "backward":                                                 # The ordinary ray fan already describes the forward camera direction.
		for edge in _visible_physical_wall_edges():
			visible_edges[String(edge["key"])] = true
	var result := []                                                                           # Store the overlays selected by the independent forward graph.
	for slot in _forward_slot_records():
		var segment := _forward_slot_world_segment(slot)                                         # Convert the authored local graph edge to the active world orientation.
		var key := _physical_edge_key(segment[0], segment[1])                                    # Build a stable map-edge key for this slot.
		if not _segment_has_wall_for_debug(segment[0], segment[1]):
			continue
		if forward_transition_name != "backward" and not visible_edges.has(key):                # Reverse travel uses its own destination-cell graph instead of the departing-cell ray cache.
			continue
		var selected: Dictionary = slot.duplicate()                                              # Preserve guide metadata for both debug panels.
		selected["segment_a"] = segment[0]
		selected["segment_b"] = segment[1]
		result.append(selected)
	return result                                                                               # Return only real, ray-visible walls for compositing.



# _is_strafe_view: Reports whether a live three-stage local-left/local-right camera frame is visible.
func _is_strafe_view() -> bool:
	return strafe_step != 0                                                                     # A manual step holds the same live side-camera stage rather than using a separate frozen debug state.



# _strafe_camera_progress: Returns the completed fraction of the current left/right cell crossing for the displayed authored frame.
func _strafe_camera_progress() -> float:
	var chronological_stage := 4 - strafe_step if strafe_transition_name == "strafe_left" else strafe_step # Map reverse playback to the same chronological 1/2/3 camera stages.
	if chronological_stage == 3:                                                               # The third authored floor/wall frame still sits between the two stable cell views.
		return 0.75                                                                               # Leave the final quarter-cell for the stable destination view instead of placing Right 3 beyond its intended source grid.
	return float(chronological_stage) / 3.0                                                    # Preserve the calibrated first and second frame positions at one and two thirds of the crossing.



# _active_strafe_wall_textures: Returns the wall texture set paired with the active Right 1/2/3 floor.
func _active_strafe_wall_textures() -> Dictionary:
	match strafe_step:                                                                          # Match each authored side-camera stage to its own transparent wall set.
		1:
			return right_1_wall_textures                                                            # Use the first rightward stage.
		2:
			return right_2_wall_textures                                                            # Use the middle rightward stage.
		_:
			return right_3_wall_textures                                                            # Use the final rightward stage, including reverse left playback.



# _active_strafe_floor_texture: Returns the standalone floor paired with the active side-camera stage.
func _active_strafe_floor_texture() -> Texture2D:
	match strafe_step:                                                                          # Match each authored stage to its own floor frame.
		1:
			return floor_right_1_texture                                                           # Use the first rightward floor.
		2:
			return floor_right_2_texture                                                           # Use the middle rightward floor.
		_:
			return floor_right_3_texture                                                           # Use the final rightward floor, including reverse left playback.



# _render_strafe_wall_view: Composes one authored side-camera floor and its transparent walls in diagram draw order.
func _render_strafe_wall_view() -> void:
	_hide_slot_nodes()                                                                         # Remove obsolete coarse environment sprites before the full-frame composition.
	if floor_sprite != null:                                                                   # Reuse the base floor node beneath the transparent wall layers.
		floor_sprite.visible = true                                                              # Keep the floor visible before drawing walls.
		floor_sprite.region_enabled = false                                                      # Side floors are individual 160x120 images rather than frames in the turn strip.
		floor_sprite.texture = _active_strafe_floor_texture()                                    # Pair the currently active authored floor and wall stage.
		floor_sprite.position = Vector2.ZERO                                                     # Align the standalone floor image with the playfield origin.
	for wall_id in straight_wall_nodes.keys():                                                 # Clear any prior cardinal, turn, forward, or side wall overlays.
		straight_wall_nodes[wall_id].visible = false                                             # Avoid stale pixels from an earlier renderer mode.
	var visible_slots := _build_strafe_render_list()                                           # Resolve this stage's independent source-grid wall slots.
	last_visible_wall_ids.clear()                                                              # Keep status and selected-slot debugging tied to the active side renderer.
	for slot in visible_slots:                                                                 # Record every overlay actually selected this frame.
		last_visible_wall_ids.append(int(slot["id"]))                                           # Keep the local slot id available to debug UI and status text.
	visible_slots.sort_custom(func(a, b): return int(a["draw"]) < int(b["draw"]))          # Paint distant overlays first so nearer walls remain in front.
	for slot in visible_slots:                                                                 # Draw every selected transparent side-wall overlay.
		var wall_id := int(slot["id"])                                                         # Read the authored local wall id.
		var wall_sprite: Sprite2D = straight_wall_nodes.get(wall_id)                             # Reuse the matching full-screen wall node.
		var texture: Texture2D = _active_strafe_wall_textures().get(wall_id)                    # Read the currently paired transparent wall texture.
		if wall_sprite == null or texture == null:                                               # Skip incomplete asset/node pairs defensively.
			continue                                                                               # Continue drawing the rest of the valid overlays.
		wall_sprite.texture = texture                                                            # Draw the transparent wall artwork over the authored floor.
		wall_sprite.position = Vector2.ZERO                                                     # Keep all side overlays in their authored full-frame positions.
		wall_sprite.z_index = int(slot["draw"])                                                # Respect this source graph's back-to-front ordering.
		wall_sprite.visible = true                                                               # Reveal the selected overlay.
		_position_wall_debug_label(wall_id, texture)                                            # Mark the selected side-wall asset itself when Selected Slots is enabled.



# _strafe_slot_records: Builds independent stage-specific side-transition source graphs from the authored Right 1/2/3 diagrams.
func _strafe_slot_records() -> Array:
	var base: Array = []                                                                      # Start with the immutable authored graph for the visible side frame.
	if strafe_step == 1:                                                                      # Right 1 now uses the complete 24-slot topology supplied in the user's diagram.
		base = STRAFE_1_DIAGNOSTIC_SLOT_EDGES                                                    # Keep its numbered source graph independent from the later Right stages.
	elif strafe_step == 2:                                                                     # Right 2 uses its own authored 22-slot topology supplied in the user's diagram.
		base = STRAFE_2_DIAGNOSTIC_SLOT_EDGES                                                    # Keep its asymmetric final column and leaving/entering edges independent from Right 1.
	else:                                                                                       # Use Right 3's completed topology at the final strafe frame.
		base = STRAFE_3_DIAGNOSTIC_SLOT_EDGES                                                    # Keep Right 3 independent of all other frame data.
	return base                                                                                # Keep source topology immutable: it is the authoritative world-map and wall-selection graph.


# _slot_graph_records_with_overrides: Applies saved JSON endpoint edits without mutating the authored constants.
func _slot_graph_records_with_overrides(context_key: String, base: Array) -> Array:
	var result: Array = []                                                                     # Return independent dictionaries so tuning never edits a constant table.
	var context: Dictionary = slot_graph_tuner_overrides.get(context_key, {})                  # Read overrides for exactly this visible graph.
	for original in base:                                                                      # Preserve every untouched authored slot.
		var slot: Dictionary = original.duplicate()                                              # Copy its metadata and endpoints.
		var saved: Dictionary = context.get(str(int(slot["id"])), {})                           # Look up a possible edited endpoint pair.
		if not saved.is_empty():                                                                 # Replace only fields explicitly saved by the tuner.
			slot["a"] = Vector2(float(saved["a"][0]), float(saved["a"][1]))                    # Restore the first local source endpoint.
			slot["b"] = Vector2(float(saved["b"][0]), float(saved["b"][1]))                    # Restore the second local source endpoint.
		result.append(slot)                                                                      # Keep the corrected slot in the active graph.
	return result                                                                              # Return the live graph used by map selection and rendering.


# _slot_graph_tuner_context_key: Names the currently displayed local graph without encoding its world orientation.
func _slot_graph_tuner_context_key() -> String:
	if _is_strafe_view():                                                                     # Right art has three independently authored player-local graphs.
		return "strafe_%d" % strafe_step                                                        # Keep Right 1, 2, and 3 calibration independent.
	if _is_forward_view():                                                                    # Forward and backward share art but need separately reviewable camera passes.
		var travel := "backward" if forward_transition_name == "backward" else "forward"      # Preserve the direction being calibrated in the saved JSON key.
		return "%s_%d" % [travel, _active_forward_visual_stage()]                              # Keep Fwd 1 and Fwd 2 independent for each travel direction.
	if _is_turn_45_view():                                                                   # Use the authored visible turn phase, regardless of clockwise/counterclockwise playback.
		return "turn_%d" % _active_turn_visual_stage()                                         # Share the matching 22, 45, or 66 player-local guide across map rotation.
	return "idle_cardinal"                                                                   # Cardinal idle views use one camera-local graph whose world source rotates beneath it.


# _slot_graph_tuner_apply_screen_overrides: Applies only saved player-view coordinates and leaves world graph selection untouched.
func _slot_graph_tuner_apply_screen_overrides(base: Array) -> Array:
	var result: Array = []                                                                    # Return independent records so constants and source topology remain immutable.
	var context: Dictionary = slot_graph_tuner_overrides.get(_slot_graph_tuner_context_key(), {}) # Read only the graph currently visible to the player.
	for original in base:                                                                     # Preserve all untouched records exactly as authored.
		var slot: Dictionary = original.duplicate()                                             # Copy this local-screen record before adding optional display calibration.
		var original_a: Vector2 = slot["a"]                                                     # Keep the pre-tune midpoint so labels travel coherently with endpoint edits.
		var original_b: Vector2 = slot["b"]                                                     # Keep the matching second endpoint.
		var saved: Dictionary = context.get(str(int(slot["id"])), {})                           # Read the optional saved endpoints for this numbered art slot.
		if saved.has("a"):                                                                     # Override only the handle the user actually moved.
			slot["a"] = Vector2(float(saved["a"][0]), float(saved["a"][1]))                    # Restore JSON-safe player-view coordinates.
		if saved.has("b"):                                                                     # Keep the untouched endpoint at its authored location when only one handle changed.
			slot["b"] = Vector2(float(saved["b"][0]), float(saved["b"][1]))                    # Restore the second JSON-safe player-view coordinate.
		var original_mid := (original_a + original_b) * 0.5                                     # Measure where the slot was authored before local tuning.
		var tuned_mid: Vector2 = (slot["a"] + slot["b"]) * 0.5                                # Measure the new player-view centre.
		slot["label"] = slot.get("label", original_mid) + (tuned_mid - original_mid)           # Carry the numbered label with its edited local guide segment.
		result.append(slot)                                                                     # Keep the adjusted display record without touching map vectors.
	return result                                                                             # Return the current local calibration.


# _handle_slot_graph_tuner_input: Lets whichever player-local graph is currently displayed edit only its screen endpoints.
func _handle_slot_graph_tuner_input(event: InputEvent) -> bool:
	if not slot_graph_tuner_enabled or _view_slot_screen_segments().is_empty():               # Keep ordinary play untouched when no local slot graph is visible.
		return false                                                                             # Do not consume normal input.
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):                 # Ignore keyboard and controller events.
		return false                                                                             # Leave them for normal game handling.
	var screen_point: Vector2 = maze_content.get_global_transform_with_canvas().affine_inverse() * event.position # Convert window pixels into the active 160x120 player-view space.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:             # Start or stop one endpoint drag.
		if event.pressed:                                                                        # Search visible endpoint handles on press.
			var handle := _slot_graph_tuner_handle_at(screen_point)                                # Choose one logical intersection rather than the first overlapping screen primitive.
			if not handle.is_empty():                                                              # Begin a drag only when the pointer hits a visible tuner handle.
				var selected_slot := _slot_graph_tuner_slot_endpoint(int(handle["id"]), String(handle["endpoint"])) # Recover this logical endpoint's current player-local point.
				if not selected_slot.is_empty():                                                     # Protect against a stale endpoint after the graph changes.
					slot_graph_tuner_undo.append(slot_graph_tuner_overrides.duplicate(true))           # Save one complete pre-drag snapshot for Ctrl+Z.
					slot_graph_tuner_drag = _slot_graph_tuner_drag_group(selected_slot["point"], int(handle["id"]), String(handle["endpoint"])) # Capture only the authored shared intersection.
					slot_graph_tuner_hover = handle.duplicate()                                        # Keep the selected handle visibly active immediately.
					# The normal _process render immediately following this input refreshes the gizmo once; avoid a second full two-player redraw here.
					return true                                                                        # Consume this mouse press.
			return false                                                                            # Let clicks away from a handle behave normally.
		slot_graph_tuner_drag.clear()                                                            # Release the active handle.
		return true                                                                              # Consume the release following a drag.
	if event is InputEventMouseMotion and not slot_graph_tuner_drag.is_empty():                # Update the captured endpoint while the mouse moves.
		var anchor: Vector2 = slot_graph_tuner_drag["anchor"]                                  # Read the player-view position shared by the selected intersection.
		var translation := screen_point - anchor                                                 # Move every joined local projection endpoint by one identical screen offset.
		for member in slot_graph_tuner_drag["members"]:                                         # Apply the shared translation to all slots meeting at this intersection.
			_slot_graph_tuner_set_screen_endpoint(int(member["id"]), String(member["endpoint"]), member["screen"] + translation) # Preserve the intersection without changing source-map vectors.
		# The next normal frame redraws this local overlay once; do not synchronously rebuild both player views for every mouse event.
		return true                                                                              # Consume this drag motion.
	if event is InputEventMouseMotion:                                                         # Refresh the hover state even when no endpoint is currently captured.
		var hover := _slot_graph_tuner_handle_at(screen_point)                                   # Find the nearest visible endpoint under the cursor.
		if hover != slot_graph_tuner_hover:                                                      # Redraw only when the interaction state has changed.
			slot_graph_tuner_hover = hover                                                         # Store the new hover identity (or an empty dictionary).
			# The ordinary frame render updates hover color without adding an input-event redraw.
		return not hover.is_empty()                                                              # Consume motion only when it is over a graph handle.
	return false                                                                                # Leave unrelated mouse events untouched.


func _strafe_source_point_from_screen(screen_point: Vector2) -> Vector2:
	var depth: float = clampf(4.96 - (screen_point.y - 44.0) * 4.0 / 52.0, 0.96, 4.96)        # Invert the authored FloorRight depth bands approximately.
	var half_width: float = lerpf(80.0, 10.0, (depth - 0.96) / 4.0)                           # Approximate the painted FloorRight trapezoid width at this depth.
	var lateral: float = 0.5 + (screen_point.x - 80.0) / maxf(half_width, 0.001)              # Convert screen x back into the active graph's local lateral coordinate.
	return Vector2(lateral, depth)                                                             # Return a grid-valid local source point.


func _slot_graph_tuner_handle_at(screen_point: Vector2) -> Dictionary:
	if _slot_graph_tuner_context_key() != "turn_2":                                          # Only the 45-degree guide has intentionally overlapping but distinct authored intersections.
		for slot in _view_slot_screen_segments():                                                # Use the first actual handle hit for ordinary graphs; grouping is resolved later by its authored endpoint key.
			for endpoint_key in ["a", "b"]:
				if screen_point.distance_to(slot[endpoint_key]) <= 5.0:
					return {"id": int(slot["id"]), "endpoint": endpoint_key}
		return {}
	var best: Dictionary = {}                                                                 # Keep the most useful logical node under this overlapping visual point.
	var best_group_size := -1                                                                 # Prefer the largest authored intersection when several handles share screen pixels.
	for slot in _view_slot_screen_segments():                                                  # Test every endpoint visible in the active player-view graph.
		for endpoint_key in ["a", "b"]:                                                        # Check both editable ends of each vector.
			if screen_point.distance_to(slot[endpoint_key]) <= 5.0:                                # Match the visible diamond's grab radius.
				var candidate := {"id": int(slot["id"]), "endpoint": endpoint_key}              # Identify this endpoint before checking its logical intersection.
				var group_size: int = _slot_graph_tuner_drag_group(slot[endpoint_key], int(slot["id"]), endpoint_key)["members"].size() # Resolve authored grouping instead of trusting visual overlap.
				if group_size > best_group_size:                                                     # Prefer the shared node the user is most likely trying to tune.
					best = candidate                                                                  # Keep that logical handle identity.
					best_group_size = group_size                                                      # Remember its authored intersection size.
	return best                                                                                # Report no handle only when the pointer misses every endpoint.


# _slot_graph_tuner_slot_endpoint: Resolves one live local-screen endpoint by its stable slot identity.
func _slot_graph_tuner_slot_endpoint(wall_id: int, endpoint_key: String) -> Dictionary:
	for slot in _view_slot_screen_segments():                                                  # Search the graph currently displayed to the player.
		if int(slot["id"]) == wall_id:                                                          # Match the numbered transparent-wall slot.
			return {"point": slot[endpoint_key]}                                                  # Return its current display point, including any unsaved edits.
	return {}                                                                                  # Avoid creating a drag from an endpoint absent in this graph.


func _slot_graph_tuner_drag_group(screen_position: Vector2, wall_id: int, endpoint_key: String) -> Dictionary:
	var members: Array = []                                                                    # Collect every graph endpoint that visually shares this intersection.
	var group_key := _slot_graph_tuner_endpoint_group_key(wall_id, endpoint_key, screen_position) # Resolve authored connectivity before considering visual overlap.
	for slot in _view_slot_screen_segments():                                                  # Compare the visible current-frame endpoint positions.
		for candidate_key in ["a", "b"]:                                                       # Include both ends of every slot line.
			if _slot_graph_tuner_endpoint_group_key(int(slot["id"]), candidate_key, slot[candidate_key]) == group_key: # Move only endpoints which belong to this authored graph intersection.
				members.append({"id": int(slot["id"]), "endpoint": candidate_key, "screen": slot[candidate_key]}) # Keep each joined local projection endpoint and its pre-drag location.
	var anchor := screen_position                                                              # Use the clicked player-view point as the translation anchor.
	return {"id": wall_id, "endpoint": endpoint_key, "anchor": anchor, "members": members} # Preserve the whole intersection for the drag lifecycle.


# _slot_graph_tuner_endpoint_group_key: Gives a display endpoint an authored intersection identity instead of merging layers that merely overlap on screen.
func _slot_graph_tuner_endpoint_group_key(wall_id: int, endpoint_key: String, screen_position: Vector2) -> String:
	if _slot_graph_tuner_context_key() == "turn_2":                                         # The 45-degree turn guide has two distinct depth layers that intentionally cross at the same pixels.
		var key := "%02d:%s" % [wall_id, endpoint_key]                                         # Name this exact hand-authored guide endpoint.
		if key in ["12:b", "13:a", "15:b", "16:a"]:                                         # Keep the actual near-turn four-way junction joined.
			return "turn_45_near_junction"                                                        # Move 12/13/15/16 as one intersection.
		if key in ["08:b", "09:a"]:                                                           # Keep the earlier depth layer independent even though it currently projects to the same point.
			return "turn_45_middle_junction"                                                      # Move 08/09 without disturbing the nearer four-way node.
	return "%s:%.2f:%.2f" % [_slot_graph_tuner_context_key(), screen_position.x, screen_position.y] # In all other graphs, exact matching display endpoints form one intersection.


func _slot_graph_tuner_strafe_source_endpoint(wall_id: int, endpoint_key: String) -> Vector2:
	for slot in _strafe_slot_records():                                                        # Read the live graph including any earlier unsaved tuner edits.
		if int(slot["id"]) == wall_id: return slot[endpoint_key]                               # Return the requested authoritative local endpoint.
	return Vector2.ZERO                                                                         # Fall back safely only for a stale handle after a graph change.


func _slot_graph_tuner_undo_last_edit() -> bool:
	if not slot_graph_tuner_enabled or slot_graph_tuner_undo.is_empty(): return false          # Keep ordinary Ctrl+Z untouched outside an active tuner edit history.
	slot_graph_tuner_overrides = slot_graph_tuner_undo.pop_back()                              # Restore the complete source-vector state from before the drag.
	slot_graph_tuner_drag.clear()                                                              # Drop any stale captured handle after history travel.
	# The next normal frame restores the local overlay; top-down source selection never changed.
	return true                                                                                # Report that Ctrl+Z was consumed by the tuner.


func _slot_graph_tuner_set_screen_endpoint(wall_id: int, endpoint_key: String, point: Vector2) -> void:
	var context_key := _slot_graph_tuner_context_key()                                        # Keep edits isolated to the graph presently being viewed.
	var context: Dictionary = slot_graph_tuner_overrides.get(context_key, {})                  # Read or create this frame's overrides.
	var existing: Dictionary = context.get(str(wall_id), {})                                   # Preserve the opposite endpoint when changing one handle.
	if existing.is_empty():                                                                    # Seed a new override from the currently displayed player-view endpoints.
		for slot in _view_slot_screen_segments():                                                 # Find the matching visible slot.
			if int(slot["id"]) == wall_id:                                                        # Stop at the selected slot.
				existing = {"a": [slot["a"].x, slot["a"].y], "b": [slot["b"].x, slot["b"].y]} # Copy both player-local endpoints before replacing one.
				break
	existing[endpoint_key] = [point.x, point.y]                                                # Store the snapped edited endpoint as JSON-safe numbers.
	context[str(wall_id)] = existing                                                           # Write the edited slot into its frame context.
	slot_graph_tuner_overrides[context_key] = context                                          # Retain the context for live selection and later saving.


func _load_slot_graph_tuner_overrides() -> void:
	if not FileAccess.file_exists(SLOT_GRAPH_TUNER_PATH): return                               # Keep first launch clean until the user saves a guide.
	var text := FileAccess.get_file_as_string(SLOT_GRAPH_TUNER_PATH)                           # Read saved project-local tuner data.
	var parsed: Variant = JSON.parse_string(text)                                              # Decode the JSON object without relying on Variant inference.
	if parsed is Dictionary: slot_graph_tuner_overrides = parsed                               # Accept only the expected dictionary root.


func _save_slot_graph_tuner_overrides() -> void:
	var file: FileAccess = FileAccess.open(SLOT_GRAPH_TUNER_PATH, FileAccess.WRITE)            # Save to the visible project file requested by the user.
	if file != null: file.store_string(JSON.stringify(slot_graph_tuner_overrides, "\t"))       # Preserve readable indented JSON for review and Git.



# _strafe_slot_world_segment: Rotates one side-transition graph edge into the current cardinal map basis.
func _strafe_slot_world_segment(slot: Dictionary) -> Array[Vector2]:
	var authored_stage_offset := -0.5 if strafe_step >= 2 else 0.0                              # Right 2 and Right 3 are authored half a cell camera-left so their center columns remain exactly on the camera centreline.
	var side_offset := authored_stage_offset                                                      # The shared strafe camera origin supplies world travel for both left and right playback.
	var local_a: Vector2 = slot["a"] + Vector2(side_offset, 0.0)                            # Translate the first endpoint with the authored side camera.
	var local_b: Vector2 = slot["b"] + Vector2(side_offset, 0.0)                            # Translate the second endpoint with the authored side camera.
	return _snapped_debug_segment_from_camera_local((local_a + local_b) * 0.5, local_b - local_a) # Snap the authored guide edge onto a real thin-wall map edge.



# _strafe_view_slot_screen_segments: Projects the authored side-transition source graph onto its matching FloorRight floor grid.
func _strafe_view_slot_screen_segments() -> Array:
	var segments := []                                                                         # Store one fixed floor-grid record per numbered side-transition slot.
	for slot in _strafe_slot_records():                                                        # Visit every authored source edge once.
		var screen_a := _strafe_authored_floor_screen_point(slot["a"])                           # Start with the immutable authored player-local projection.
		var screen_b := _strafe_authored_floor_screen_point(slot["b"])                           # Leave source geometry untouched; the wrapper applies display-only edits.
		var wall_id := int(slot["id"])                                                        # Keep the art id, world edge, and player-view floor mark 1:1.
		var label_position := (screen_a + screen_b) * 0.5                                       # Put the number at the centre of its own authored floor-grid segment.
		segments.append(_view_slot_screen_record(wall_id, screen_a, screen_b, label_position)) # Store the floor-grid line and its paired label.
	return segments                                                                             # Return the active side-transition floor-grid graph.


func _slot_graph_tuner_screen_point(wall_id: int, endpoint_key: String, fallback: Vector2) -> Vector2:
	var context: Dictionary = slot_graph_tuner_overrides.get(_slot_graph_tuner_context_key(), {}) # Read only this frame's player-view projection edits.
	var saved: Dictionary = context.get(str(wall_id), {})                                     # Find the optional per-slot local screen coordinates.
	if saved.has(endpoint_key):                                                                # Use a direct player-view point when the tuner has supplied one.
		return Vector2(float(saved[endpoint_key][0]), float(saved[endpoint_key][1]))            # Restore JSON-safe [x, y] coordinates.
	return fallback                                                                             # Preserve the authored projection until a handle is moved.



# _forward_authored_floor_screen_point: Maps one Fwd 1/2 source-grid point onto the ordinary forward floor perspective.
func _forward_authored_floor_screen_point(local_point: Vector2) -> Vector2:
	var row_depths: Array[float] = [-0.04, 0.96, 1.96, 2.96, 3.96, 4.96]                     # Keep the entered-cell edge plus the five authored Fwd depth rows.
	var row_half_widths: Array[float] = [80.0, 53.333, 40.0, 30.0, 25.0, 10.0]              # Match the painted Fwd floor from full near width to the narrow distant corridor.
	var row_y: Array[float] = [112.0, 96.0, 70.0, 58.0, 50.0, 44.0]                         # Keep vertices on the visible floor instead of clustering them on wall art.
	var depth: float = clampf(local_point.y, row_depths[0], row_depths[row_depths.size() - 1]) # Keep malformed future entries inside the authored perspective range.
	var lower_index: int = 0                                                                  # Find the near-side row surrounding this graph point.
	for index in range(row_depths.size() - 1):                                                # Locate the adjacent pair of authored depth rows.
		if depth >= row_depths[index] and depth <= row_depths[index + 1]:                       # Stop once the point lies within this perspective band.
			lower_index = index                                                                    # Preserve its index for interpolation.
			break                                                                                  # No later band can also contain the point.
	var upper_index: int = mini(lower_index + 1, row_depths.size() - 1)                      # Clamp at the far row.
	var span: float = maxf(row_depths[upper_index] - row_depths[lower_index], 0.001)         # Guard against a malformed zero-height band.
	var blend: float = clampf((depth - row_depths[lower_index]) / span, 0.0, 1.0)            # Interpolate through the painted floor perspective between rows.
	var half_width: float = lerpf(row_half_widths[lower_index], row_half_widths[upper_index], blend) # Taper with depth while retaining the authored centerline.
	var screen_y: float = lerpf(row_y[lower_index], row_y[upper_index], blend)               # Keep the endpoint exactly on its depth band.
	return Vector2(80.0 + local_point.x * half_width, screen_y)                              # Fwd source x=0 is the camera centreline, unlike the side-transition graph's x=0.5 seam.



# _strafe_authored_floor_screen_point: Maps one Right 1/2/3 source-grid point onto the shared painted FloorRight perspective.
func _strafe_authored_floor_screen_point(local_point: Vector2) -> Vector2:
	var row_depths: Array[float] = [0.96, 1.96, 2.96, 3.96, 4.96]                            # Keep the five authored front-to-back grid rows used by every side-transition source diagram.
	var row_half_widths: Array[float] = [80.0, 40.0, 30.0, 25.0, 10.0]                       # Copy the painted FloorRight trapezoid widths: full near cell, then progressively narrower distant cells.
	var row_y: Array[float] = [96.0, 70.0, 58.0, 50.0, 44.0]                                 # Copy the visible FloorRight row heights from Walls_Right_1/2/3_Graph.png.
	var depth: float = clampf(local_point.y, row_depths[0], row_depths[row_depths.size() - 1]) # Keep malformed diagnostics inside the authored floor grid.
	var lower_index: int = 0                                                                   # Start at the nearest authored row.
	for index in range(row_depths.size() - 1):                                                 # Find the two rows bracketing this source point.
		if depth >= float(row_depths[index]) and depth <= float(row_depths[index + 1]):         # Stop at the containing row interval.
			lower_index = index                                                                     # Preserve its lower index for interpolation.
			break                                                                                   # Avoid scanning farther rows.
	var upper_index: int = min(lower_index + 1, row_depths.size() - 1)                        # Clamp the upper neighbour at the far edge.
	var span: float = maxf(row_depths[upper_index] - row_depths[lower_index], 0.001)          # Avoid division by zero if a guide table is edited later.
	var blend: float = clampf((depth - row_depths[lower_index]) / span, 0.0, 1.0)             # Convert the source depth into its fraction between authored rows.
	var half_width: float = lerpf(row_half_widths[lower_index], row_half_widths[upper_index], blend) # Taper the grid with the same floor perspective between rows.
	var screen_y: float = lerpf(row_y[lower_index], row_y[upper_index], blend)                # Keep intermediate points on the painted floor rather than in the wall-art area.
	var screen_x: float = 80.0 + (local_point.x - 0.5) * half_width                           # Centre the local x=0.5 column on the FloorRight centre seam used by the authored guides.
	return Vector2(screen_x, screen_y)                                                         # Return the stable 160x120 FloorRight coordinate.



# _build_strafe_render_list: Selects blocked source edges for the active independent side-transition graph.
func _build_strafe_render_list() -> Array:
	var result := []                                                                           # Store overlays selected by this independent stage graph.
	for slot in _strafe_slot_records():                                                        # Visit every stage-specific source edge.
		var segment := _strafe_slot_world_segment(slot)                                          # Convert the authored local edge into the active world orientation.
		if _segment_has_wall_for_debug(segment[0], segment[1]):                                 # Draw only art whose matching source-map edge is blocked.
			result.append({"id": int(slot["id"]), "draw": int(slot["draw"]), "a": segment[0], "b": segment[1]}) # Keep renderer and debug data paired.
	return result                                                                               # Return the transparent overlays this stage should paint.



# _hide_straight_wall_nodes: Hides the floor and all numbered straight-wall sprites.
func _hide_straight_wall_nodes() -> void:                                                   # Declare this function.
	if floor_sprite != null:                                                                   # Run the following block only when this condition is true.
		floor_sprite.visible = false                                                              # Update the reusable base floor sprite.
	for wall_id in straight_wall_nodes.keys():                                                 # Iterate across this collection or range.
		var wall_sprite: Sprite2D = straight_wall_nodes[wall_id]                                  # Store mutable runtime state for assets, rendering, movement, or debug output.
		wall_sprite.visible = false                                                               # Configure or update one numbered wall overlay sprite.



# _position_wall_debug_label: Moves a wall's debug number label to the center of that wall texture's opaque pixels.
func _position_wall_debug_label(wall_id: int, texture: Texture2D) -> void:                   # Declare this function.
	var wall_label: Label = straight_wall_label_nodes.get(wall_id)                              # Look up the label attached to this wall sprite.
	if wall_label == null or texture == null:                                                   # Skip when the label or texture is missing.
		return                                                                                    # Return without updating a label.
	if not DEBUG_WALL_LABELS_ENABLED and not show_selected_wall_slot_debug:                    # Only show art-bound ids for the dedicated selected-slot audit or the legacy always-on label mode.
		wall_label.visible = false                                                               # Hide any label left over from a previously enabled selected-slot audit.
		return                                                                                    # Return without positioning a disabled label.
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



# _build_turn_45_render_list: Casts a diagonal fan and maps ray-hit physical edges to 45-degree wall slots.
func _build_turn_45_render_list() -> Array:                                                # Declare this function.
	var render_list := []                                                                      # Store the visible 45-degree wall slots selected by ray hits.
	var emitted_ids := {}                                                                      # Track wall ids already added so repeated ray hits draw only once.
	var forward := _turn_45_view_forward_vector()                                             # Read the current diagonal camera-forward vector.
	var right := _turn_45_view_right_vector()                                                 # Read the current diagonal camera-right vector.
	var origin := _camera_grid_origin_for_forward(forward)                                    # Use the same rear-biased origin concept as straight view, rotated halfway.
	var physical_edges := _visible_physical_wall_edges_for_basis(origin, forward, right)       # Collect only first-visible map edges from this diagonal cone so hidden walls do not become render candidates.
	var visible_edge_keys := {}                                                                # Store the physical source edges first-hit by the diagonal ray fan.
	for edge in physical_edges:                                                                # Index every ray-visible physical edge by its canonical grid-edge key.
		visible_edge_keys[String(edge["key"])] = edge                                             # Preserve the ray-hit edge for quick slot lookup.
	for diagnostic_slot in _turn_debug_wall_slot_segments():                                   # Walk the active authored 22, 45, or 66-degree source-map graph.
		if not bool(diagnostic_slot["has_wall"]):                                                 # Skip candidate slots whose underlying map edge is open.
			continue                                                                                 # Continue to the next corrected 45-degree slot.
		var key := _physical_edge_key(diagnostic_slot["a"], diagnostic_slot["b"])                  # Build the canonical physical edge key controlled by this slot.
		if not visible_edge_keys.has(key):                                                        # Skip slots that are blocked but not first-visible from this diagonal camera.
			continue                                                                                 # Continue to the next corrected 45-degree slot.
		var wall_id := int(diagnostic_slot["id"])                                                  # Read this 45-degree slot id.
		if emitted_ids.has(wall_id):                                                              # Avoid drawing duplicate overlays for repeated ray-hit edges.
			continue                                                                                 # Continue to the next visible edge.
		var slot := _turn_wall_slot_by_id(wall_id).duplicate()                                    # Copy the active turn-stage art metadata for this authored slot id.
		slot["segment_a"] = diagnostic_slot["a"]                                                  # Preserve the controlled physical source edge for top-down selected-slot debug.
		slot["segment_b"] = diagnostic_slot["b"]                                                  # Preserve the controlled physical source edge for top-down selected-slot debug.
		render_list.append(slot)                                                                  # Add this visible 45-degree slot to the render list.
		emitted_ids[wall_id] = true                                                               # Mark the slot id as emitted.
	if turn_step == 2:                                                                          # The existing occlusion branches are authored only for the 45-degree graph.
		render_list = _prune_turn_45_occluded_slots(render_list)                                 # Remove far diagonal slots hidden by nearer 45-degree wall pieces.
	render_list.sort_custom(func(a, b): return int(a["draw"]) < int(b["draw"]))                # Sort by the 45-degree diagram's back-to-front draw order.
	return render_list                                                                         # Return the selected 45-degree wall-slot list.


# _turn_wall_slot_by_id: Returns metadata for the active authored turn-stage slot.
func _turn_wall_slot_by_id(wall_id: int) -> Dictionary:
	if turn_step == 2:                                                                          # Reuse the calibrated draw ordering for the existing 45-degree assets.
		return _turn_45_slot_by_id(wall_id)                                                       # Return its established metadata.
	return {"id": wall_id, "draw": wall_id}                                                  # Intermediate graphs have their own IDs and draw in authored numeric order.



# _visible_physical_wall_edges: Finds physical wall segments that are first-hit by rays in the current top-down view fan.
func _visible_physical_wall_edges() -> Array:                                               # Declare this function.
	var origin := _camera_grid_origin()                                                        # Use the current view camera origin.
	var forward := _view_forward_vector().normalized()                                        # Use the current view-forward vector.
	var right := _view_right_vector().normalized()                                            # Use the current view-right vector.
	return _visible_physical_wall_edges_for_basis(origin, forward, right)                      # Delegate the ray fan to the shared basis-aware helper.



# _visible_physical_wall_edges_for_basis: Finds ray-visible physical wall segments for an arbitrary 2D camera basis.
func _visible_physical_wall_edges_for_basis(origin: Vector2, forward: Vector2, right: Vector2, include_all_hits := false) -> Array: # Declare this function.
	var visible_by_key := {}                                                                   # Store the nearest-hit wall segments by canonical edge key.
	var samples := _raycast_wall_hit_samples_for_basis(origin, forward, right) if include_all_hits else _raycast_visibility_samples_for_basis(origin, forward, right) # Use all ray intersections for diagonal validation, but first hits for straight visibility.
	for sample in samples:                                                                     # Scan each sampled ray.
		if not bool(sample["hit"]):                                                               # Ignore rays that did not touch a wall edge.
			continue                                                                                 # Continue to the next ray sample.
		var edge: Dictionary = sample["edge"]                                                     # Read the closest physical wall edge hit by this ray.
		var edge_key := String(edge["key"])                                                       # Read the canonical wall-edge key for grouping ray hits.
		if not visible_by_key.has(edge_key):                                                      # Initialize aggregation the first time this physical edge is hit.
			edge["distance"] = float(sample["distance"])                                             # Seed the nearest ray distance for diagnostics and downstream sorting.
			edge["hit_count"] = 0                                                                    # Count how many rays chose this physical edge.
			edge["hit_position_sum"] = Vector2.ZERO                                                  # Accumulate exact hit positions so the mapper can use the visible wall span.
			edge["min_hit_distance"] = float(sample["distance"])                                     # Seed the closest distance hit on this edge.
			edge["max_hit_distance"] = float(sample["distance"])                                     # Seed the farthest distance hit on this edge.
			edge["min_hit_side"] = 999999.0                                                          # Seed the leftmost camera-local hit sample.
			edge["max_hit_side"] = -999999.0                                                         # Seed the rightmost camera-local hit sample.
			edge["min_hit_depth"] = 999999.0                                                         # Seed the nearest camera-local hit depth.
			edge["max_hit_depth"] = -999999.0                                                        # Seed the farthest camera-local hit depth.
			visible_by_key[edge_key] = edge                                                         # Store this aggregate edge record.
		var aggregate: Dictionary = visible_by_key[edge_key]                                      # Read the mutable aggregate for this physical edge.
		var hit_position: Vector2 = sample["hit_position"]                                        # Read the exact world-grid point where this ray hit the edge.
		var hit_relative := hit_position - origin                                                 # Convert the hit point into camera-local coordinates.
		var hit_side := hit_relative.dot(right)                                                   # Compute camera-right offset for this exact ray hit.
		var hit_depth := hit_relative.dot(forward)                                                # Compute camera-forward depth for this exact ray hit.
		aggregate["hit_count"] = int(aggregate["hit_count"]) + 1                                  # Increment the number of rays that selected this edge.
		aggregate["hit_position_sum"] = Vector2(aggregate["hit_position_sum"]) + hit_position     # Add this exact hit point to the aggregate center.
		aggregate["distance"] = minf(float(aggregate["distance"]), float(sample["distance"]))     # Keep the nearest ray distance for this edge.
		aggregate["min_hit_distance"] = minf(float(aggregate["min_hit_distance"]), float(sample["distance"])) # Track the closest ray hit distance.
		aggregate["max_hit_distance"] = maxf(float(aggregate["max_hit_distance"]), float(sample["distance"])) # Track the farthest ray hit distance.
		aggregate["min_hit_side"] = minf(float(aggregate["min_hit_side"]), hit_side)              # Track the leftmost visible hit point in camera-local space.
		aggregate["max_hit_side"] = maxf(float(aggregate["max_hit_side"]), hit_side)              # Track the rightmost visible hit point in camera-local space.
		aggregate["min_hit_depth"] = minf(float(aggregate["min_hit_depth"]), hit_depth)           # Track the nearest visible hit point in camera-local space.
		aggregate["max_hit_depth"] = maxf(float(aggregate["max_hit_depth"]), hit_depth)           # Track the farthest visible hit point in camera-local space.
		visible_by_key[edge_key] = aggregate                                                     # Store the updated aggregate back into the dictionary.
	var visible_edges := []                                                                    # Convert the keyed dictionary back into an ordered array.
	for edge in visible_by_key.values():                                                       # Iterate through unique visible physical edges.
		var hit_count := maxi(1, int(edge["hit_count"]))                                           # Avoid division by zero if a malformed aggregate slips through.
		edge["hit_center"] = Vector2(edge["hit_position_sum"]) / float(hit_count)                  # Store the center of the actually visible ray-hit span.
		edge["hit_mid_side"] = (float(edge["min_hit_side"]) + float(edge["max_hit_side"])) * 0.5   # Store the visible hit span's center side offset.
		edge["hit_mid_depth"] = (float(edge["min_hit_depth"]) + float(edge["max_hit_depth"])) * 0.5 # Store the visible hit span's center depth.
		visible_edges.append(edge)                                                               # Add the visible edge to the result array.
	return visible_edges                                                                       # Return all visible physical wall segments.



# _raycast_visibility_samples_for_basis: Casts the full view fan and records each ray's first hit or max-distance endpoint.
func _raycast_visibility_samples_for_basis(origin: Vector2, forward: Vector2, right: Vector2) -> Array: # Declare this function.
	var samples := []                                                                          # Store every ray sample for renderer visibility and debug drawing.
	var all_edges := _all_physical_wall_edges()                                                # Gather unique wall segments from the thin-wall map.
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
				best_hit = edge.duplicate()                                                            # Store a copy of the nearest hit edge so samples are independent.
		var hit_found := not best_hit.is_empty()                                                  # Record whether this ray found a blocking wall.
		var endpoint_distance := best_distance if hit_found else VISIBILITY_MAX_DISTANCE           # Use the hit distance or the cone's far limit for drawing.
		samples.append({                                                                          # Store all information needed by rendering and debug overlays.
			"ray_index": ray_index,                                                                  # Preserve the ray's index across the fan.
			"direction": ray_direction,                                                              # Preserve the normalized world-space ray direction.
			"distance": endpoint_distance,                                                           # Preserve the first-hit or max endpoint distance.
			"hit": hit_found,                                                                        # Preserve whether this ray actually hit a wall.
			"edge": best_hit,                                                                        # Preserve the closest physical edge hit by this ray.
			"hit_position": origin + ray_direction * endpoint_distance,                              # Preserve the world-grid endpoint for top-down drawing.
		})                                                                                        # Close this ray sample dictionary.
	return samples                                                                             # Return every ray sample across the fan.



# _raycast_wall_hit_samples_for_basis: Casts the full view fan and records every wall intersection along each ray.
func _raycast_wall_hit_samples_for_basis(origin: Vector2, forward: Vector2, right: Vector2) -> Array: # Declare this function.
	var samples := []                                                                          # Store every wall hit sample across the ray fan.
	var all_edges := _all_physical_wall_edges()                                                # Gather unique wall segments from the thin-wall map.
	for ray_index in range(VISIBILITY_RAY_COUNT):                                             # Cast a fixed fan of rays across the view cone.
		var ratio := 0.0 if VISIBILITY_RAY_COUNT == 1 else float(ray_index) / float(VISIBILITY_RAY_COUNT - 1) # Convert ray index to 0..1 across the fan.
		var angle := deg_to_rad(lerpf(-VISIBILITY_RAY_HALF_ANGLE_DEGREES, VISIBILITY_RAY_HALF_ANGLE_DEGREES, ratio)) # Convert this ray's fan angle to radians.
		var ray_direction := (forward * cos(angle) + right * sin(angle)).normalized()             # Rotate the ray around the forward vector inside the top-down plane.
		var ray_hits := []                                                                        # Store every segment hit by this single ray before sorting by distance.
		for edge in all_edges:                                                                    # Test this ray against every physical wall edge.
			var distance := _ray_segment_hit_distance(origin, ray_direction, edge["a"], edge["b"])   # Compute the distance to this edge if the ray intersects it.
			if distance < 0.0:                                                                       # Skip edges this ray does not touch.
				continue                                                                                 # Continue to the next edge.
			ray_hits.append({                                                                         # Store this valid wall hit for distance sorting.
				"ray_index": ray_index,                                                                  # Preserve the ray's index across the fan.
				"direction": ray_direction,                                                              # Preserve the normalized world-space ray direction.
				"distance": distance,                                                                    # Preserve this intersection distance along the ray.
				"hit": true,                                                                             # Mark this record as a real wall hit.
				"edge": edge.duplicate(),                                                                # Store a copy of the hit edge so samples are independent.
				"hit_position": origin + ray_direction * distance,                                       # Preserve the exact world-grid wall-contact point.
			})                                                                                        # Close this ray-hit dictionary.
		ray_hits.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))       # Sort this ray's hits from nearest to farthest.
		for hit_sample in ray_hits:                                                                 # Add every sorted intersection to the shared sample list.
			samples.append(hit_sample)                                                                 # Preserve this hit for edge-span grouping.
	return samples                                                                             # Return every wall-hit sample across the full fan.



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



# _turn_45_slot_for_physical_edge: Maps a diagonal ray-hit map edge into the temporary 16-slot halfway-turn art.
func _turn_45_slot_for_physical_edge(edge: Dictionary, origin: Vector2, forward: Vector2, right: Vector2) -> Dictionary: # Declare this function.
	var a: Vector2 = edge["a"]                                                                 # Read the first physical wall endpoint.
	var b: Vector2 = edge["b"]                                                                 # Read the second physical wall endpoint.
	var a_relative := a - origin                                                               # Measure endpoint A relative to the diagonal camera origin.
	var b_relative := b - origin                                                               # Measure endpoint B relative to the diagonal camera origin.
	var a_depth := a_relative.dot(forward)                                                     # Compute endpoint A's camera-forward depth.
	var b_depth := b_relative.dot(forward)                                                     # Compute endpoint B's camera-forward depth.
	var a_side := a_relative.dot(right)                                                        # Compute endpoint A's camera-right offset.
	var b_side := b_relative.dot(right)                                                        # Compute endpoint B's camera-right offset.
	var near_depth := minf(a_depth, b_depth)                                                   # Use the nearer endpoint for side-wall row selection.
	var far_depth := maxf(a_depth, b_depth)                                                    # Use the farther endpoint to choose the 45-degree art row.
	var mid_side := (a_side + b_side) * 0.5                                                     # Use the midpoint side offset to choose the 45-degree art lane.
	if far_depth < -0.05 or far_depth > VISIBILITY_MAX_DISTANCE:                              # Ignore edges behind the camera or beyond the temporary art depth.
		return {}                                                                                 # Return no 45-degree slot.
	var edge_axis := _turn_45_edge_axis(a, b)                                                  # Classify the physical source edge as vertical or horizontal in world-grid space.
	var sample := _turn_45_edge_sample_position(edge, edge_axis, near_depth, far_depth, mid_side) # Convert the visible edge into one calibrated camera-local footprint sample.
	var slot_template := _turn_45_slot_for_sample(sample, edge_axis)                           # Look up the 45-degree slot whose footprint contains this sample.
	if slot_template.is_empty():                                                               # Skip side/depth samples outside the known 45-degree slots.
		return {}                                                                                 # Return no 45-degree slot.
	var slot := slot_template.duplicate()                                                      # Copy the slot so this visible instance can carry its source-map segment.
	slot["segment_a"] = a                                                                      # Preserve the physical source edge for top-down debug highlighting.
	slot["segment_b"] = b                                                                      # Preserve the physical source edge for top-down debug highlighting.
	slot["diagonal_depth"] = sample.y                                                          # Preserve the sampled diagonal depth for future debug and occlusion checks.
	slot["diagonal_side"] = sample.x                                                           # Preserve the exact sampled diagonal side used for debug and occlusion checks.
	slot["sample_position"] = sample                                                           # Preserve the exact footprint sample used to choose this wall art slot.
	return slot                                                                                # Return the visible 45-degree wall slot.



# _prune_turn_45_occluded_slots: Removes 45-degree slots that are ray-hit but hidden behind nearer diagonal pieces.
func _prune_turn_45_occluded_slots(render_list: Array) -> Array:                           # Declare this function.
	var present_ids := {}                                                                      # Track every selected 45-degree wall id before pruning.
	for slot in render_list:                                                                   # Scan the selected halfway-turn slots.
		present_ids[int(slot["id"])] = true                                                       # Mark this wall id as selected.
	var occluded_ids := {}                                                                     # Store farther 45-degree ids hidden by nearer ids in the same art branch.
	for branch in TURN_45_OCCLUSION_BRANCHES:                                                  # Walk each data-defined art branch from near to far.
		_mark_turn_45_occluded_branch(present_ids, occluded_ids, branch)                         # Prune farther ids after the nearest visible id on that branch.
	var pruned := []                                                                          # Store the slots that survive the 45-degree occlusion pass.
	for slot in render_list:                                                                   # Scan the selected halfway-turn slots again.
		var wall_id := int(slot["id"])                                                            # Read the numbered 45-degree wall id.
		if occluded_ids.has(wall_id):                                                            # Skip farther pieces covered by a nearer piece in the same 45-degree branch.
			continue                                                                                 # Continue to the next selected slot.
		pruned.append(slot)                                                                       # Keep every other selected slot.
	return pruned                                                                             # Return the pruned 45-degree render list.



# _mark_turn_45_occluded_branch: Marks farther ids in one 45-degree art branch as hidden by the nearest selected id.
func _mark_turn_45_occluded_branch(present_ids: Dictionary, occluded_ids: Dictionary, branch: Array) -> void: # Declare this function.
	for index in range(branch.size()):                                                        # Walk the branch from nearest wall id to farthest wall id.
		var wall_id := int(branch[index])                                                         # Read the branch wall id at this depth.
		if occluded_ids.has(wall_id):                                                            # Ignore wall ids already rejected by a cross-branch occlusion rule.
			continue                                                                                 # Keep looking for a valid nearer wall in this branch.
		if not present_ids.has(wall_id):                                                          # Continue until the first visible wall in this branch is found.
			continue                                                                                 # Keep scanning this branch.
		for hidden_index in range(index + 1, branch.size()):                                      # Mark every farther branch member as hidden.
			occluded_ids[int(branch[hidden_index])] = true                                           # Store the hidden wall id.
		return                                                                                    # Stop after the nearest visible branch wall has been processed.



# _turn_45_edge_is_vertical: Returns whether a physical wall segment lies on a north-south grid line.
func _turn_45_edge_is_vertical(a: Vector2, b: Vector2) -> bool:                             # Declare this function.
	return absf(a.x - b.x) < absf(a.y - b.y)                                                  # Compare endpoint deltas to distinguish vertical wall edges.



# _turn_45_edge_axis: Returns the coarse physical orientation string used by the footprint lookup.
func _turn_45_edge_axis(a: Vector2, b: Vector2) -> String:                                  # Declare this function.
	return TURN_45_EDGE_VERTICAL if _turn_45_edge_is_vertical(a, b) else TURN_45_EDGE_HORIZONTAL # Return a stable orientation token for footprint filtering.



# _turn_45_edge_sample_position: Chooses one camera-local side/depth point that represents a visible physical edge.
func _turn_45_edge_sample_position(edge: Dictionary, edge_axis: String, near_depth: float, far_depth: float, mid_side: float) -> Vector2: # Declare this function.
	if edge.has("hit_mid_side") and edge.has("hit_mid_depth"):                                  # Prefer the actual visible ray-hit span when the edge was selected by raycasting.
		return Vector2(float(edge["hit_mid_side"]), float(edge["hit_mid_depth"]))                  # Return the center of the rays that actually hit this wall.
	var depth_sample := near_depth if edge_axis == TURN_45_EDGE_VERTICAL else far_depth        # Use side-wall leading depth, but front/back wall far depth as a fallback.
	return Vector2(mid_side, depth_sample)                                                     # Return the fallback calibrated footprint coordinate in camera-local units.



# _turn_45_slot_for_sample: Finds the 45-degree wall id whose calibrated footprint contains a sample point.
func _turn_45_slot_for_sample(sample: Vector2, edge_axis: String) -> Dictionary:             # Declare this function.
	if sample.y <= TURN_45_CLOSE_ROW_DEPTH_MAX:                                                # Keep the nearest diagram row from being stolen by the looser row-3 footprints.
		return _turn_45_slot_by_id(15 if sample.x < 0.0 else 16)                                  # Split the closest row by camera side into the 15/16 wall-art pair.
	var best_footprint := {}                                                                   # Track the closest matching footprint inside its calibrated radius.
	var best_score := 999999.0                                                                 # Start with a large score so any valid footprint can win.
	for footprint in TURN_45_SLOT_FOOTPRINTS:                                                  # Check every hand-calibrated 45-degree footprint.
		var footprint_axis := String(footprint["axis"])                                           # Read whether this footprint expects vertical, horizontal, or either edge orientation.
		var axis_mismatch := footprint_axis != TURN_45_EDGE_ANY and footprint_axis != edge_axis    # Track whether this source edge belongs to the wrong local 45-degree wall family.
		if axis_mismatch:                                                                         # Reject impossible mappings such as a horizontal map edge claiming a vertical local wall id.
			continue                                                                                 # Continue to the next footprint instead of drawing a perpendicular wall sprite.
		var center: Vector2 = footprint["center"]                                                 # Read the footprint center in camera-local side/depth coordinates.
		var radius: Vector2 = footprint["radius"]                                                 # Read the allowed half-size around that center.
		var side_delta := absf(sample.x - center.x)                                               # Measure camera-side distance from this footprint center.
		var depth_delta := absf(sample.y - center.y)                                              # Measure camera-depth distance from this footprint center.
		if side_delta > radius.x or depth_delta > radius.y:                                       # Reject samples outside this footprint's calibrated rectangle.
			continue                                                                                 # Continue to the next footprint.
		var score := pow(side_delta / maxf(radius.x, 0.001), 2.0) + pow(depth_delta / maxf(radius.y, 0.001), 2.0) # Score closer footprint centers higher without adding branch-specific rules.
		if score >= best_score:                                                                   # Keep the first or nearest footprint for this sample.
			continue                                                                                 # Continue to the next footprint.
		best_score = score                                                                        # Store this better footprint score.
		best_footprint = footprint                                                                # Store this better matching footprint.
	if best_footprint.is_empty():                                                              # If no calibrated footprint accepted the sample, this edge has no 45-degree overlay.
		return {}                                                                                 # Return no slot.
	return _turn_45_slot_by_id(int(best_footprint["id"]))                                      # Return the numbered wall slot controlled by the best footprint.



# _turn_45_slot_by_id: Returns the 45-degree slot metadata for one numbered wall-art id.
func _turn_45_slot_by_id(wall_id: int) -> Dictionary:                                      # Declare this function.
	for slot in TURN_45_WALL_SLOTS:                                                          # Scan the 16 temporary halfway-turn slot definitions.
		if int(slot["id"]) == wall_id:                                                            # Match the requested numbered wall-art id.
			return slot                                                                             # Return the matching 45-degree slot metadata.
	return {}                                                                                  # Return no slot when this 45-degree id is not defined.



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
	return _camera_grid_origin_for_forward(_view_forward_vector())                            # Return the rear-biased camera point for the current cardinal or halfway view.



# _camera_grid_origin_for_forward: Returns the fixed camera origin for a supplied world-grid forward vector.
func _camera_grid_origin_for_forward(forward: Vector2) -> Vector2:                         # Declare this function.
	var cell_center := Vector2(float(grid_position.x) + 0.5, float(grid_position.y) + 0.5)     # Compute the rotation center of the current grid cell.
	var origin := cell_center - forward.normalized() * CAMERA_REAR_OFFSET                      # Start at the normal rear-biased camera point just inside the wall behind the viewer.
	if _is_strafe_view() and pending_grid_delta != Vector2i.ZERO:                              # Keep every strafe diagnostic and visibility calculation at the same interpolated world camera position.
		origin += Vector2(pending_grid_delta) * _strafe_camera_progress()                        # Travel along the actual cardinal destination vector so local left/right rotates correctly for N, S, E, and W.
	return origin                                                                               # Return the shared camera origin used by the cone, rays, slot graph, and wall selection.



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
	_ensure_key_action(ACTION_TOGGLE_SLOT_GRID_DEBUG, [KEY_F2])                               # Bind F2 to the blue slot-grid audit overlay toggle.
	_ensure_key_action(ACTION_TOGGLE_DEBUG_MENU, [KEY_F3])                                    # Bind F3 to the grouped debug-overlay menu toggle.
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



# _primary_xbox_joypad_id: Returns the first connected controller so one plugged-in Xbox pad drives player one.
func _primary_xbox_joypad_id() -> int:                                                      # Declare this function.
	var connected_joypads := Input.get_connected_joypads()                                    # Ask Godot for the currently available gamepad device ids.
	if connected_joypads.is_empty():                                                          # Keep keyboard controls fully usable when no controller is connected.
		return -1                                                                               # Report that there is no gamepad to read.
	return int(connected_joypads[0])                                                          # Use the first connected pad as player one's controller.



# _xbox_left_stick: Reads the primary Xbox pad's movement stick as screen-local X/right and Y/down input.
func _xbox_left_stick() -> Vector2:                                                         # Declare this function.
	var device_id := _primary_xbox_joypad_id()                                                 # Find the controller that should drive player one.
	if device_id < 0:                                                                          # Return neutral input when no controller is attached.
		return Vector2.ZERO                                                                      # Keep keyboard-only use unchanged.
	var stick := Vector2(Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X), Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)) # Read the standard Xbox left-stick axes.
	if stick.length() < XBOX_STICK_DEADZONE:                                                   # Discard minor hardware drift.
		return Vector2.ZERO                                                                      # Treat the stick as centered inside the dead zone.
	return stick.limit_length(1.0)                                                            # Preserve analog strength while keeping diagonal travel bounded.



# _xbox_right_stick_turn: Converts a deliberate right-stick horizontal push into the existing one-shot turn direction.
func _xbox_right_stick_turn() -> int:                                                       # Declare this function.
	var device_id := _primary_xbox_joypad_id()                                                 # Find the controller that should drive player one.
	if device_id < 0:                                                                          # Return no turn when no controller is attached.
		return 0                                                                                 # Keep keyboard-only use unchanged.
	var horizontal := Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X)                         # Read the standard Xbox right-stick horizontal axis.
	if horizontal <= -XBOX_TURN_THRESHOLD:                                                    # Treat a strong left push as the existing left-turn action.
		return -1                                                                                # Request one left turn while the input latch handles repeats.
	if horizontal >= XBOX_TURN_THRESHOLD:                                                     # Treat a strong right push as the existing right-turn action.
		return 1                                                                                 # Request one right turn while the input latch handles repeats.
	return 0                                                                                   # Keep the stick neutral below the deliberate-turn threshold.



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
	var xbox_turn := _xbox_right_stick_turn() if active_player_index == 0 else 0               # Let player one's right stick use the same turn latch as Q/E.
	var left_pressed := _is_player_turn_left_pressed() or xbox_turn < 0                        # Read the current left-turn key or controller state for the bound player.
	var right_pressed := _is_player_turn_right_pressed() or xbox_turn > 0                      # Read the current right-turn key or controller state for the bound player.
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



# _read_toggle_slot_grid_debug: Returns true once when the blue slot-grid audit hotkey is pressed.
func _read_toggle_slot_grid_debug() -> bool:                                                # Declare this function.
	var slot_grid_pressed := Input.is_action_pressed(ACTION_TOGGLE_SLOT_GRID_DEBUG) or _is_key_down(KEY_F2) # Read the current slot-grid toggle key state.
	var slot_grid_just_pressed := slot_grid_pressed and not was_slot_grid_debug_pressed        # Detect the first frame of the slot-grid toggle key press.
	was_slot_grid_debug_pressed = slot_grid_pressed                                           # Store current toggle state for next frame.
	return slot_grid_just_pressed                                                             # Return whether the diagnostic overlay should toggle this frame.



# _read_toggle_debug_menu: Returns true once when the debug-overlay menu hotkey is pressed.
func _read_toggle_debug_menu() -> bool:
	var debug_menu_pressed := Input.is_action_pressed(ACTION_TOGGLE_DEBUG_MENU) or _is_key_down(KEY_F3) # Read the current F3 debug-menu key state.
	var debug_menu_just_pressed := debug_menu_pressed and not was_debug_menu_pressed           # Detect the first frame of the menu hotkey press.
	was_debug_menu_pressed = debug_menu_pressed                                                # Store current menu key state for next frame.
	return debug_menu_just_pressed                                                            # Return whether the debug panel should open or close this frame.



# _read_movement: Reads WASD or arrow movement input and returns a normalized local movement vector.
func _read_movement() -> Vector2:                                                           # Declare this function.
	var movement := Vector2.ZERO                                                               # Store mutable runtime state for assets, rendering, movement, or debug output.
	if active_player_index == 0:                                                               # Reserve the first connected Xbox controller for player one.
		movement += _xbox_left_stick()                                                            # Add analog left-stick travel in the same screen-local axes as WASD.
	if _is_player_move_left_pressed():                                                         # Read the bound player's local strafe-left input.
		movement.x -= 1.0                                                                         # Continue the controller logic for this section.
	if _is_player_move_right_pressed():                                                        # Read the bound player's local strafe-right input.
		movement.x += 1.0                                                                         # Continue the controller logic for this section.
	if _is_player_move_forward_pressed():                                                      # Read the bound player's local forward input.
		movement.y -= 1.0                                                                         # Continue the controller logic for this section.
	if _is_player_move_backward_pressed():                                                     # Read the bound player's local backward input.
		movement.y += 1.0                                                                         # Continue the controller logic for this section.
	return movement.limit_length(1.0)                                                          # Preserve analog stick strength while keeping keyboard diagonals at normal speed.



# _read_manual_forward_step_input: Returns one forward input edge from W/numpad 8 or the Xbox left stick.
func _read_manual_forward_step_input() -> bool:
	var forward_pressed := _is_player_move_forward_pressed()                                  # Let keyboard forward use the same diagnostic behavior as the controller.
	var backward_pressed := _is_player_move_backward_pressed()                                # Let keyboard backward advance a reverse Fwd sequence.
	if active_player_index == 0:                                                               # Player one may also use the connected Xbox left stick.
		var stick := _xbox_left_stick()                                                           # Read the same camera-local vector used by ordinary movement.
		forward_pressed = forward_pressed or (stick.y <= -XBOX_STICK_DEADZONE and absf(stick.y) > absf(stick.x)) # Require an intentional predominantly-forward push.
		backward_pressed = backward_pressed or (stick.y >= XBOX_STICK_DEADZONE and absf(stick.y) > absf(stick.x)) # Require an intentional predominantly-backward push.
	var desired_pressed := backward_pressed if forward_step != 0 and forward_transition_name == "backward" else forward_pressed # Match the held frame to its travel direction.
	var vertical_pressed := forward_pressed or backward_pressed                                # Latch either travel direction so the initial crossing press cannot skip its first frame.
	var just_pressed := desired_pressed and not was_manual_forward_step_pressed                # Advance only after the stick/key was released and pushed again.
	was_manual_forward_step_pressed = vertical_pressed                                         # Remember the current vertical input state for the next frame.
	return just_pressed                                                                         # Return exactly one pulse for this press.



# _read_manual_strafe_step_input: Returns one lateral input edge from A/D or the Xbox left stick.
func _read_manual_strafe_step_input() -> bool:
	var left_pressed := _is_player_move_left_pressed()                                         # Let keyboard local-left use the same diagnostic behavior as the controller.
	var right_pressed := _is_player_move_right_pressed()                                       # Let keyboard local-right use the same diagnostic behavior as the controller.
	if active_player_index == 0:                                                               # Player one may also use the connected Xbox left stick.
		var stick := _xbox_left_stick()                                                          # Read the same camera-local vector used by ordinary movement.
		left_pressed = left_pressed or (stick.x <= -XBOX_STICK_DEADZONE and absf(stick.x) > absf(stick.y)) # Require an intentional predominantly-left push.
		right_pressed = right_pressed or (stick.x >= XBOX_STICK_DEADZONE and absf(stick.x) > absf(stick.y)) # Require an intentional predominantly-right push.
	var desired_pressed := left_pressed if strafe_transition_name == "strafe_left" else right_pressed # Match the held frame to its travel direction.
	var lateral_pressed := left_pressed or right_pressed                                        # Latch either lateral direction so the crossing push cannot skip its first frame.
	var just_pressed := desired_pressed and not was_manual_strafe_step_pressed                 # Advance only after the key/stick was released and pushed again.
	was_manual_strafe_step_pressed = lateral_pressed                                            # Remember the current lateral input state for the next frame.
	return just_pressed                                                                         # Return exactly one pulse for this press.



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



# _move_inside_tile_diagonal: Moves through the world using the active 45-degree camera axes and real grid-edge collision.
func _move_inside_tile_diagonal(movement: Vector2, delta: float) -> void:                   # Declare this function.
	var physical_movement := Vector2(movement.x, -movement.y)                                  # Convert screen-local input into camera-right/camera-forward movement.
	var world_position := _current_player_world_position()                                     # Start from the same world point shown by the top-down diagnostic map.
	var world_delta := (_view_right_vector() * physical_movement.x + _view_forward_vector() * physical_movement.y) * LOCAL_TILE_WORLD_HALF_EXTENT * MOVE_UNITS_PER_SECOND * delta # Convert the visible diagonal input into world-grid travel.
	last_blocked_direction = ""                                                               # Clear stale feedback before applying this frame's collision checks.
	if _try_move_diagonal_corner_direct(world_position, world_delta):                          # Let a genuine diagonal crossing land in its diagonal cell without briefly visiting a side-adjacent camera cell.
		return                                                                                    # Keep the world/grid state already committed by the diagonal-corner helper.
	world_position = _move_diagonal_world_axis(world_position, world_delta.x, Vector2i(1, 0), "right", "left") # Sweep east/west first so an angled move can slide along a blocked north/south wall.
	world_position = _move_diagonal_world_axis(world_position, world_delta.y, Vector2i(0, 1), "back", "front") # Sweep north/south second using the world position produced by the first sweep.
	_set_player_world_position_for_current_view(world_position)                                # Re-express the valid world point in the current diagonal camera-local coordinates.



# _try_move_diagonal_corner_direct: Holds a slight one-axis overrun at a 45-degree corner, then commits directly to the diagonal destination.
func _try_move_diagonal_corner_direct(world_position: Vector2, world_delta: Vector2) -> bool:
	if is_zero_approx(world_delta.x) or is_zero_approx(world_delta.y):                         # Reserve this correction for actual two-axis diagonal travel, not cardinal/side movement in a diagonal view.
		return false                                                                              # Let the normal axis sweeps handle non-diagonal motion.
	var source_cell := grid_position                                                            # Keep the camera anchored to its current cell while the two boundary crossings converge.
	var x_delta := 1 if world_delta.x > 0.0 else -1                                            # Identify the intended east or west diagonal destination component.
	var y_delta := 1 if world_delta.y > 0.0 else -1                                            # Identify the intended south or north diagonal destination component.
	var candidate := world_position + world_delta                                              # Test the uninterrupted diagonal destination before modifying either coordinate.
	var crosses_x := candidate.x >= float(source_cell.x + 1) if x_delta > 0 else candidate.x < float(source_cell.x) # Detect crossing the intended source-cell X edge.
	var crosses_y := candidate.y >= float(source_cell.y + 1) if y_delta > 0 else candidate.y < float(source_cell.y) # Detect crossing the intended source-cell Y edge.
	if not crosses_x and not crosses_y:                                                        # Stay on normal movement while both coordinates remain inside the current cell.
		return false                                                                              # Let the axis sweeps keep the in-cell projection exact.
	var x_edge := Vector2i(x_delta, 0)                                                         # Represent the intended first horizontal map-edge crossing.
	var y_edge := Vector2i(0, y_delta)                                                         # Represent the intended first vertical map-edge crossing.
	if crosses_x and crosses_y:                                                                # Both sides have cleared the shared corner this update.
		if _can_cross_diagonal_corner(source_cell, x_edge, y_edge):                              # Require a complete legal route around the corner; never tunnel through two walls.
			_set_player_world_position_for_current_view(candidate)                                # Commit the camera and player directly into the diagonal destination cell.
			return true                                                                             # Prevent the old per-axis path from visiting either side cell.
		return false                                                                              # Fall back to normal independent sweeps so blocked diagonal movement can slide naturally.
	var pending_edge := x_edge if crosses_x else y_edge                                        # Identify the one edge that crossed a tiny amount ahead of the other.
	var other_boundary := float(source_cell.y + 1) if y_delta > 0 else float(source_cell.y) if crosses_x else float(source_cell.x + 1) if x_delta > 0 else float(source_cell.x) # Locate the remaining companion edge without changing camera cell yet.
	var other_coordinate := candidate.y if crosses_x else candidate.x                          # Measure the un-crossed coordinate against that companion edge.
	if absf(other_coordinate - other_boundary) > DIAGONAL_CORNER_GRACE:                        # Only forgive a few pixels of numerical/input skew, never a deliberate side-cell move.
		return false                                                                              # Let normal side crossing take over once the movement is no longer a true corner crossing.
	if not _can_cross_edge(source_cell, pending_edge) or not _can_cross_diagonal_corner(source_cell, x_edge, y_edge): # Do not hold a side overrun when no legal diagonal route exists.
		return false                                                                              # Preserve standard collision and sliding around blocked corners.
	_set_player_world_position_in_camera_cell(candidate, source_cell)                          # Keep the camera on the source diagonal cell while the second axis reaches its boundary.
	return true                                                                                 # Skip the independent sweeps that would otherwise flash the side-adjacent cell.



# _can_cross_diagonal_corner: Accepts a diagonal destination only when at least one orthogonal two-edge route is open.
func _can_cross_diagonal_corner(source_cell: Vector2i, x_edge: Vector2i, y_edge: Vector2i) -> bool:
	var x_then_y := _can_cross_edge(source_cell, x_edge) and _can_cross_edge(source_cell + x_edge, y_edge) # Test the route that enters the horizontal neighbor first.
	var y_then_x := _can_cross_edge(source_cell, y_edge) and _can_cross_edge(source_cell + y_edge, x_edge) # Test the route that enters the vertical neighbor first.
	return x_then_y or y_then_x                                                                # Permit the diagonal only when a real non-tunneling route exists.



# _move_diagonal_world_axis: Applies one world-axis motion component, stopping at blocked cell edges and allowing wall slides.
func _move_diagonal_world_axis(world_position: Vector2, distance: float, positive_delta: Vector2i, positive_label: String, negative_label: String) -> Vector2: # Declare this function.
	if is_zero_approx(distance):                                                               # Skip an axis with no requested motion.
		return world_position                                                                     # Keep the current world position unchanged.
	var axis_is_x := positive_delta.x != 0                                                     # Determine whether this sweep changes world X or world Y.
	var current_cell := Vector2i(floori(world_position.x), floori(world_position.y))           # Read the source-map cell currently containing the player.
	var candidate := world_position                                                             # Start the candidate at the current valid position.
	if axis_is_x:                                                                               # Apply an east/west movement component.
		candidate.x += distance                                                                    # Move only along X for this collision sweep.
	else:                                                                                       # Apply a north/south movement component.
		candidate.y += distance                                                                    # Move only along Y for this collision sweep.
	var current_axis := world_position.x if axis_is_x else world_position.y                    # Read the starting coordinate on the moved axis.
	var candidate_axis := candidate.x if axis_is_x else candidate.y                            # Read the proposed coordinate on the moved axis.
	var current_index := floori(current_axis)                                                  # Find the starting integer cell index along the moved axis.
	var candidate_index := floori(candidate_axis)                                              # Find the proposed integer cell index along the moved axis.
	if current_index == candidate_index:                                                       # Keep free movement that stays inside the current cell.
		return candidate                                                                          # No grid edge was crossed.
	var crossing_delta := positive_delta if distance > 0.0 else -positive_delta                # Choose the cardinal source-map edge being crossed.
	if _can_cross_edge(current_cell, crossing_delta):                                          # Allow movement through an open edge into the neighboring grid cell.
		return candidate                                                                          # The following axis sweep will use the new cell when necessary.
	var boundary := float(current_index + 1) if distance > 0.0 else float(current_index)       # Locate the blocked east/south or west/north cell edge.
	var safe_axis := boundary - 0.0001 if distance > 0.0 else boundary + 0.0001                # Stay just inside the current cell so its ownership remains stable.
	if axis_is_x:                                                                               # Clamp the rejected east/west candidate.
		candidate.x = safe_axis                                                                    # Keep the player pressed against the source-map wall.
	else:                                                                                       # Clamp the rejected north/south candidate.
		candidate.y = safe_axis                                                                    # Keep the player pressed against the source-map wall.
	last_blocked_direction = positive_label if distance > 0.0 else negative_label              # Report the screen-relative diagonal-view direction that was blocked.
	return candidate                                                                            # Return the axis-clamped world point so the other axis can still slide.



# _current_player_world_position: Converts the bound player's camera-local offset into the actual world point, including halfway turns.
func _current_player_world_position() -> Vector2:                                           # Declare this function.
	var tile_offset := _local_position_to_tile_offset(local_floor_position)                    # Convert art-space local position into signed right/forward coordinates.
	var cell_center := Vector2(float(grid_position.x) + 0.5, float(grid_position.y) + 0.5)     # Anchor the player at the center of their current source-map cell.
	return cell_center + _view_right_vector() * tile_offset.x * LOCAL_TILE_WORLD_HALF_EXTENT + _view_forward_vector() * tile_offset.y * LOCAL_TILE_WORLD_HALF_EXTENT # Rotate the offset through the exact visible camera basis.



# _set_player_world_position_for_current_view: Stores a valid world point as local coordinates under the active cardinal or halfway-turn camera.
func _set_player_world_position_for_current_view(world_position: Vector2) -> void:          # Declare this function.
	grid_position = Vector2i(floori(world_position.x), floori(world_position.y))               # Assign the source-map cell actually containing this point.
	_set_player_world_position_in_camera_cell(world_position, grid_position)                   # Re-express the point using the cell selected from its true world ownership.



# _set_player_world_position_in_camera_cell: Reprojects a world point through an explicitly retained camera cell for brief diagonal-corner grace.
func _set_player_world_position_in_camera_cell(world_position: Vector2, camera_cell: Vector2i) -> void:
	grid_position = camera_cell                                                                # Keep the requested camera/source-map cell even when the actor is a few pixels over one companion edge.
	var cell_center := Vector2(float(grid_position.x) + 0.5, float(grid_position.y) + 0.5)     # Rebuild that cell's fixed center.
	var relative := world_position - cell_center                                                # Measure the player point from its newly assigned cell center.
	var offset := Vector2(relative.dot(_view_right_vector()) / LOCAL_TILE_WORLD_HALF_EXTENT, relative.dot(_view_forward_vector()) / LOCAL_TILE_WORLD_HALF_EXTENT) # Convert world displacement back into the active camera-local right/forward units.
	local_floor_position = Vector2(_signed_unit_to_axis(offset.x, HOME_LOCAL_FLOOR_POSITION.x, STRAFE_LEFT_WALL_CONTACT_X, STRAFE_RIGHT_WALL_CONTACT_X), _signed_forward_unit_to_axis(offset.y)) # Preserve that coordinate without snapping it into another camera basis.



# _try_cross_tile: Attempts to cross a map edge, starting the matching transition if the thin wall map allows it.
func _try_cross_tile(sequence_name: String, grid_delta: Vector2i, blocked_label: String) -> void: # Declare this function.
	if _can_cross_edge(grid_position, grid_delta):                                             # Run the following block only when this condition is true.
		pending_grid_delta = grid_delta                                                           # Compute and store this value for the current step.
		last_blocked_direction = ""                                                               # Compute and store this value for the current step.
		if (sequence_name == "forward" or sequence_name == "backward") and not _is_turn_45_view(): # Use authored Fwd art only for cardinal forward/backward crossings.
			_begin_forward_passthrough(sequence_name)                                                 # Play 1 -> 2 forward or the authored reverse 2 -> 1 before committing the cell.
			return                                                                                    # Keep the old captured transition path available for strafes and diagonal motion.
		if (sequence_name == "strafe_left" or sequence_name == "strafe_right") and not _is_turn_45_view(): # Use authored Right art only for cardinal local-left/local-right crossings.
			_begin_strafe_passthrough(sequence_name)                                                  # Play Right 1 -> 2 -> 3 rightward or the authored 3 -> 2 -> 1 reverse before committing the cell.
			return                                                                                    # Keep the old captured transition path available for diagonal movement only.
		_request_transition(sequence_name)                                                         # Cross through a captured phase or immediate snap.
	else:                                                                                      # Run this fallback branch when previous conditions were not met.
		last_blocked_direction = blocked_label                                                    # Compute and store this value for the current step.



# _position_player: Projects the player local tile position into the 160x120 perspective floor trapezoid.
func _position_player() -> void:                                                            # Declare this function.
	player_sprite.visible = true                                                              # Restore the local actor after temporary 45-degree validation views hide it.
	var display_local_position := _translation_display_local_position()                         # Let the actor travel smoothly through authored forward or side camera frames without changing collision or the source-map graph.
	var depth := clampf(display_local_position.y, 0.0, 1.0)                                    # Project the visual actor from its interpolated Fwd depth or its ordinary live depth.
	var projection := _self_actor_projection_at_local_depth(depth)                              # Sample self-view feet from the true local position and scale from visible S0 space.
	var screen_ratio_x := _self_screen_side_ratio_for_projection(display_local_position.x, projection) # Clamp only the rendered feet anchor inside the visible floor polygon.
	var screen_x := lerpf(float(projection["left_x"]), float(projection["right_x"]), screen_ratio_x) # Project side movement through the measured floor-zone trapezoid.
	var actor_height := float(projection["actor_height"])                                      # Read the measured character height for this depth.
	var sprite_scale := actor_height / _sprite_body_height_to_foot(player_sprite)               # Scale the visible body span, not transparent frame padding, to the measured study.
	var screen_y := _sprite_center_y_for_feet(player_sprite, float(projection["feet_y"]), sprite_scale) # Register the art foot/shadow anchor to the measured feet line.
	player_sprite.scale = Vector2.ONE * sprite_scale                                           # Update player sprite rendering or animation state.
	player_sprite.position = Vector2(screen_x, screen_y)                                       # Update player sprite rendering or animation state.
	player_sprite.z_index = LOCAL_CHARACTER_LAYER                                              # Keep the local body above wall art; the clipped viewport trims anything outside the camera frame.



# _forward_display_local_position: Smoothly moves the rendered actor across Fwd 1 and Fwd 2 while the physical crossing remains safely edge-locked.
func _forward_display_local_position() -> Vector2:
	if forward_step == 0:                                                                      # Use the actual in-cell position outside an authored forward transition.
		return local_floor_position                                                              # Keep ordinary movement, collision, and debug behavior unchanged.
	var is_backward := forward_transition_name == "backward"                                  # Reverse the visual travel when backing into the cell behind the player.
	var first_stage := (forward_step == 2) if is_backward else (forward_step == 1)             # Fwd 2 is chronologically first during reverse playback; Fwd 1 is first when moving forward.
	var stage_fraction := 0.5 if manual_forward_step_enabled else clampf(forward_passthrough_timer / FORWARD_PASSTHROUGH_SECONDS, 0.0, 1.0) # Hold each manual debug frame at its visual midpoint, or smoothly advance timed playback.
	var travel_fraction := (0.0 if first_stage else 0.5) + stage_fraction * 0.5                # Convert the two authored frames into one continuous 0..1 visual movement.
	var start_y := BACKWARD_WALL_CONTACT_Y if is_backward else FORWARD_WALL_CONTACT_Y          # Start at the crossing edge in the source cell.
	var end_y := FORWARD_WALL_CONTACT_Y if is_backward else BACKWARD_WALL_CONTACT_Y            # End at the matching entry edge in the destination cell.
	return Vector2(local_floor_position.x, lerpf(start_y, end_y, travel_fraction))             # Preserve side position while continuously carrying the rendered body through the camera catch-up.



# _translation_display_local_position: Chooses the authored forward or side transition's visual actor travel.
func _translation_display_local_position() -> Vector2:
	if _is_strafe_view():                                                                      # Give the three Right stages priority while a side crossing is active.
		return _strafe_display_local_position()                                                   # Project the actor smoothly across the lateral camera translation.
	return _forward_display_local_position()                                                    # Preserve the proven forward/back actor interpolation outside side transitions.



# _strafe_display_local_position: Smoothly carries the rendered actor across Right 1/2/3 while collision remains edge-locked.
func _strafe_display_local_position() -> Vector2:
	var is_left := strafe_transition_name == "strafe_left"                                    # Reverse the screen-space border sequence for local-left travel.
	var chronological_stage := (4 - strafe_step) if is_left else strafe_step                  # Convert reverse 3 -> 2 -> 1 playback into chronological travel order.
	var right_stage_x := [0.72, 0.50, 0.28]                                                    # Match the painted shared border in FloorRight 1/2/3 at the actor's foot depth, with a small inward bias for rightward travel.
	var display_x := float(right_stage_x[chronological_stage - 1])                             # Place the actor near the appropriate moving border for this authored floor frame.
	if is_left:                                                                                # The same captured rightward floor frames play in reverse for a local-left crossing.
		display_x = 1.0 - display_x                                                              # Mirror each frame's inward offset so the actor remains just inside the correct side of the border.
	return Vector2(display_x, local_floor_position.y)                                          # Preserve forward depth while anchoring the body to the artwork's actual crossing line.



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
	var feet_y := float(projection["feet_y"])                                                   # Read the projected opponent foot/shadow ground coordinate.
	var actor_height := float(projection["actor_height"])                                      # Read the measured opponent body height at this depth.
	var sprite_scale := actor_height / _sprite_body_height_to_foot(opponent_sprite)             # Scale the opponent by visible body span so animation frame padding cannot change size.
	var screen_y := _sprite_center_y_for_feet(opponent_sprite, feet_y, sprite_scale)            # Register the opponent art foot/shadow anchor to the projected feet line.
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
	var state_cell: Vector2i = state.get("grid_position", Vector2i.ZERO)                       # Read the player's current cell.
	var state_local: Vector2 = state.get("local_floor_position", HOME_LOCAL_FLOOR_POSITION)    # Read the player's local position inside that cell.
	var local_offset := _local_position_to_tile_offset(state_local)                            # Convert art-space local position into right/forward tile offsets.
	var forward := _view_forward_vector_for_state(state)                                       # Use the saved visible cardinal or diagonal view direction.
	var right := Vector2(-forward.y, forward.x).normalized()                                  # Build the matching camera-right direction from that visible forward vector.
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
	var scale_view_depth := maxf(view_depth, SELF_MIN_ACTOR_SCALE_VIEW_DEPTH)                 # Keep near-camera opponents scaled like the local player body.
	var scale_projection := _corridor_projection_at_view_depth(scale_view_depth)               # Sample only actor scale from the protected near-camera depth.
	actor_height = float(scale_projection["actor_height"])                                    # Replace actor height while keeping true feet and screen-side position.
	var screen_y := feet_y - actor_height * 0.5                                                 # Keep a legacy centered y value for debugging; final sprite registration uses feet_y.
	var character_layer := _character_layer_for_view_depth(view_depth)                         # Use wall-depth buckets so same-depth side walls do not erase visible actors.
	var corridor_width := maxf(float(corridor["right_x"]) - float(corridor["left_x"]), 1.0)    # Measure how many screen pixels represent one visible tile width at this depth.
	return {"screen_x": screen_x, "screen_y": screen_y, "feet_y": feet_y, "actor_height": actor_height, "scale_view_depth": scale_view_depth, "z_index": character_layer, "corridor_width": corridor_width} # Return the projected screen coordinates, scale input, and character layer.



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
	return float(projection["actor_height"]) / _sprite_body_height_to_foot(player_sprite)      # Return the scale needed to match the visible body height.



# _sprite_center_y_for_feet: Converts a desired projected feet line into a centered AnimatedSprite2D y coordinate.
func _sprite_center_y_for_feet(sprite: AnimatedSprite2D, feet_y: float, sprite_scale: float) -> float: # Declare this function.
	var texture_height := _sprite_texture_height(sprite)                                        # Read the current frame height including transparent padding.
	var foot_anchor_y := _sprite_foot_anchor_y(sprite)                                         # Read the real foot/shadow anchor row inside the current frame pixels.
	return feet_y - (foot_anchor_y - texture_height * 0.5) * sprite_scale                       # Move the centered sprite so its foot anchor lands on the projected floor point.



# _current_player_texture_width: Returns the current player frame width so the sprite can be clamped inside the playfield.
func _current_player_texture_width() -> float:                                              # Declare this function.
	var texture := player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame) # Store mutable runtime state for assets, rendering, movement, or debug output.
	if texture == null:                                                                        # Run the following block only when this condition is true.
		return 34.0                                                                               # Return a conservative fallback width for the player sprite.
	return float(texture.get_width())                                                          # Return this computed result to the caller.



# _current_player_texture_height: Returns the current player frame height for perspective scaling.
func _current_player_texture_height() -> float:                                             # Declare this function.
	return _sprite_texture_height(player_sprite)                                               # Measure the currently bound local player sprite.



# _sprite_body_height_to_foot: Returns the visible source-pixel height from the body top to the foot anchor.
func _sprite_body_height_to_foot(sprite: AnimatedSprite2D) -> float:                       # Declare this function.
	if sprite == null or sprite.sprite_frames == null:                                        # Handle missing sprite resources defensively.
		return 41.0                                                                              # Return a conservative visible-body fallback for the known idle frame.
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)       # Read the current frame texture from this sprite.
	if texture == null:                                                                        # Handle animations that have not selected a visible frame yet.
		return 41.0                                                                              # Return a conservative visible-body fallback for the known idle frame.
	return _texture_body_height_to_foot(texture)                                               # Measure or fetch the visible body span for this texture.



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



# _sprite_foot_anchor_y: Returns the source-pixel y row that should sit on the projected floor/feet point.
func _sprite_foot_anchor_y(sprite: AnimatedSprite2D) -> float:                              # Declare this function.
	if sprite == null or sprite.sprite_frames == null:                                        # Handle missing sprite resources defensively.
		return 45.0                                                                              # Return a near-bottom fallback for the known idle frame.
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)       # Read the current frame texture from this sprite.
	if texture == null:                                                                        # Handle animations that have not selected a visible frame yet.
		return 45.0                                                                              # Return a near-bottom fallback for the known idle frame.
	return _texture_foot_anchor_y(texture)                                                    # Measure or fetch the real foot/shadow anchor for this texture.



# _texture_foot_anchor_y: Finds the bottom visible character/shadow row and anchors one pixel above it.
func _texture_foot_anchor_y(texture: Texture2D) -> float:                                  # Declare this function.
	var cache_key := texture.resource_path if texture.resource_path != "" else str(texture.get_rid()) # Build a stable key for imported and generated textures.
	if sprite_foot_anchor_cache.has(cache_key):                                                # Reuse measurements for frames already scanned.
		return float(sprite_foot_anchor_cache[cache_key])                                         # Return the cached anchor row.
	var image := texture.get_image()                                                           # Read the source pixels for alpha-bound detection.
	if image == null:                                                                          # Fall back when a texture cannot provide readable pixels.
		return maxf(float(texture.get_height()) - 1.0, 0.0)                                      # Use the texture bottom as the safest available anchor.
	var bottom_visible := image.get_height() - 1                                               # Default to the final row until a visible row is found.
	var found_visible := false                                                                 # Track whether the alpha scan found any visible pixels.
	for y in range(image.get_height() - 1, -1, -1):                                            # Search upward from the bottom of the source frame.
		for x in range(image.get_width()):                                                        # Search every pixel in this row.
			if image.get_pixel(x, y).a > 0.01:                                                       # Treat any nontransparent pixel as part of the visible body/shadow.
				bottom_visible = y                                                                     # Store the bottom visible pixel row.
				found_visible = true                                                                   # Mark the alpha scan as successful.
				break                                                                                  # Stop scanning this row.
		if found_visible:                                                                        # Stop once the lowest visible row is known.
			break                                                                                  # Exit the vertical scan.
	var anchor_y := maxf(float(bottom_visible) - 1.0, 0.0) if found_visible else maxf(float(texture.get_height()) - 1.0, 0.0) # Put the logical feet point just above the visible bottom row.
	sprite_foot_anchor_cache[cache_key] = anchor_y                                             # Cache the measured anchor for later frames.
	return anchor_y                                                                            # Return the measured foot/shadow anchor row.



# _texture_body_height_to_foot: Finds the visible body span used for perspective scaling.
func _texture_body_height_to_foot(texture: Texture2D) -> float:                            # Declare this function.
	var cache_key := texture.resource_path if texture.resource_path != "" else str(texture.get_rid()) # Build a stable key for imported and generated textures.
	if sprite_body_height_cache.has(cache_key):                                               # Reuse measurements for frames already scanned.
		return float(sprite_body_height_cache[cache_key])                                        # Return the cached visible body span.
	var image := texture.get_image()                                                           # Read the source pixels for alpha-bound detection.
	if image == null:                                                                          # Fall back when a texture cannot provide readable pixels.
		return maxf(float(texture.get_height()) - 5.0, 1.0)                                      # Use a near-full-frame visible span as the safest fallback.
	var top_visible := 0                                                                       # Default to the top row until a visible row is found.
	var found_visible := false                                                                 # Track whether the alpha scan found any visible pixels.
	for y in range(image.get_height()):                                                        # Search downward from the top of the source frame.
		for x in range(image.get_width()):                                                        # Search every pixel in this row.
			if image.get_pixel(x, y).a > 0.01:                                                       # Treat any nontransparent pixel as part of the visible body/shadow.
				top_visible = y                                                                        # Store the top visible pixel row.
				found_visible = true                                                                   # Mark the alpha scan as successful.
				break                                                                                  # Stop scanning this row.
		if found_visible:                                                                        # Stop once the highest visible row is known.
			break                                                                                  # Exit the vertical scan.
	var foot_anchor_y := _texture_foot_anchor_y(texture)                                      # Reuse the measured foot/shadow anchor row for the bottom of the body span.
	var body_height := maxf(foot_anchor_y - float(top_visible), 1.0) if found_visible else maxf(float(texture.get_height()) - 5.0, 1.0) # Convert top and feet rows into a visible body span.
	sprite_body_height_cache[cache_key] = body_height                                          # Cache the measured visible body span for later frames.
	return body_height                                                                         # Return the measured visible body span.



# _movement_to_first_player_run_dir: Maps local movement input to the first-player run animation while keeping aim camera-forward.
func _movement_to_first_player_run_dir(movement: Vector2) -> String:                        # Declare this function.
	# Analog sticks nearly always include a small off-axis value. Choose the
	# dominant input axis so a forward stick push still plays RunN_AimN rather
	# than being mistaken for a W+D diagonal input.
	if absf(movement.y) >= absf(movement.x):                                                   # Prefer forward/back when the stick is primarily vertical.
		return DIR_S if movement.y > 0.0 else DIR_N                                              # Select the matching cardinal run animation.
	return DIR_E if movement.x > 0.0 else DIR_W                                                # Select the matching cardinal left/right run animation.



# _world_movement_dir_for_local_movement: Converts camera-local movement input into a shared cardinal world direction.
func _world_movement_dir_for_local_movement(movement: Vector2, facing_index: int) -> String: # Declare this function.
	var forward := Vector2(_facing_vector_for_index(facing_index))                              # Convert the player's camera-forward direction into a Vector2.
	var right := Vector2(-_left_vector_for_index(facing_index))                                 # Convert the player's camera-right direction into a Vector2.
	var world_vector := right * movement.x + forward * -movement.y                              # Rotate local side/forward input into world grid space.
	return _direction_string_for_world_vector(world_vector)                                     # Return the cardinal direction that best describes the movement.



# _world_movement_dir_for_current_view: Converts local movement through the active cardinal or halfway-turn camera basis.
func _world_movement_dir_for_current_view(movement: Vector2) -> String:                       # Declare this function.
	var world_vector := _view_right_vector() * movement.x + _view_forward_vector() * -movement.y # Rotate local movement through the actual visible camera direction.
	return _direction_string_for_world_vector(world_vector)                                     # Use the nearest available cardinal animation direction for diagonal travel.



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



# _keep_forward_run_animating: Ensures the player visibly runs throughout the short Fwd camera catch-up.
func _keep_forward_run_animating() -> void:
	_play_best_animation(true)                                                                 # Select the same view-relative running set used during ordinary held movement.
	if not player_sprite.is_playing():                                                         # Recover if another render/state change stopped the AnimatedSprite2D at the crossing edge.
		player_sprite.play()                                                                     # Resume the current run without resetting it to frame zero.
	player_sprite.speed_scale = FORWARD_RUN_ANIMATION_SPEED                                    # Advance enough frames during Fwd 1/Fwd 2 for the body to remain visibly active.



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


# _begin_forward_passthrough: Starts the two-frame cardinal forward/backward camera transition.
func _begin_forward_passthrough(sequence_name: String) -> void:
	forward_step = 2 if sequence_name == "backward" else 1                                     # Reverse travel walks the authored camera frames backward: Fwd 2 then Fwd 1.
	forward_passthrough_timer = 0.0                                                            # Start timing from the first rendered update.
	forward_transition_name = sequence_name                                                    # Preserve whether the destination enters from its rear or front edge.
	active_sequence_name = "forward_%d" % forward_step                                        # Report the visible authored stage in the debug status.
	character_is_moving = true                                                                 # Keep the run animation alive while the camera moves through the transition frames.
	_keep_forward_run_animating()                                                              # Continue and visibly advance the current running animation instead of switching to idle.
	_show_stable()                                                                              # Render the first forward floor and its independent wall grid immediately.


# _advance_forward_passthrough: Advances one Fwd stage automatically or from one fresh manual forward input.
func _advance_forward_passthrough(delta: float, manual_step: bool = false) -> void:
	if not manual_step:                                                                        # Time stages only during normal automatic playback.
		forward_passthrough_timer += delta                                                       # Accumulate visible duration for the current authored frame.
		if forward_passthrough_timer < FORWARD_PASSTHROUGH_SECONDS:
			return
	forward_passthrough_timer = 0.0                                                            # Restart timing for the second frame or clear it before the stable result.
	if (forward_transition_name != "backward" and forward_step == 1) or (forward_transition_name == "backward" and forward_step == 2): # Advance in the authored travel order.
		forward_step = 1 if forward_transition_name == "backward" else 2                       # Use Fwd 1 -> Fwd 2 forward and Fwd 2 -> Fwd 1 backward.
		active_sequence_name = "forward_%d" % forward_step                                      # Keep the currently visible stage explicit in status/debug text.
		_show_stable()                                                                            # Render the second independent forward grid.
		return
	var sequence_name := forward_transition_name                                               # Preserve the final movement result before clearing transient state.
	forward_step = 0                                                                            # Return to stable cardinal rendering.
	forward_transition_name = ""                                                              # Clear the completed transition marker.
	_finish_snap_transition(sequence_name)                                                     # Commit the target cell and restore the ordinary stable renderer.



# _begin_strafe_passthrough: Starts the three-frame cardinal local-left/local-right camera transition.
func _begin_strafe_passthrough(sequence_name: String) -> void:
	strafe_step = 3 if sequence_name == "strafe_left" else 1                                  # Local-right walks 1 -> 2 -> 3; local-left replays the authored frames 3 -> 2 -> 1.
	strafe_passthrough_timer = 0.0                                                            # Start timing from the first rendered side-camera update.
	strafe_transition_name = sequence_name                                                    # Preserve whether the destination enters from its left or right edge.
	active_sequence_name = "strafe_%d" % strafe_step                                          # Report the visible authored stage in the debug status.
	character_is_moving = true                                                                 # Keep the run animation alive while the camera moves through the side frames.
	_keep_forward_run_animating()                                                              # Reuse the explicit continuous running animation behavior from Fwd transitions.
	_show_stable()                                                                              # Render the first side floor and its independent wall graph immediately.



# _advance_strafe_passthrough: Advances one Right stage automatically or from one fresh matching lateral input.
func _advance_strafe_passthrough(delta: float, manual_step: bool = false) -> void:
	if not manual_step:                                                                        # Time stages only during normal automatic playback.
		strafe_passthrough_timer += delta                                                        # Accumulate visible duration for the active authored side frame.
		if strafe_passthrough_timer < STRAFE_PASSTHROUGH_SECONDS:
			return                                                                                # Keep the active frame visible for its full brief duration.
	strafe_passthrough_timer = 0.0                                                            # Restart timing for the next frame or clear it before the stable result.
	if (strafe_transition_name == "strafe_right" and strafe_step < 3) or (strafe_transition_name == "strafe_left" and strafe_step > 1): # Continue in the authored travel order.
		strafe_step += -1 if strafe_transition_name == "strafe_left" else 1                    # Use Right 1 -> 2 -> 3 rightward and Right 3 -> 2 -> 1 leftward.
		active_sequence_name = "strafe_%d" % strafe_step                                        # Keep the current visible stage explicit in status/debug text.
		_show_stable()                                                                            # Render the next independent side graph.
		return                                                                                    # Wait for the next automatic duration or manual lateral push.
	var sequence_name := strafe_transition_name                                                # Preserve the final movement result before clearing transient state.
	strafe_step = 0                                                                            # Return to stable cardinal rendering.
	strafe_transition_name = ""                                                               # Clear the completed side-transition marker.
	_finish_snap_transition(sequence_name)                                                     # Commit the target side cell and restore the ordinary stable renderer.
# _request_half_turn_or_transition: Starts the authored 22-degree passthrough toward a stable diagonal view unless captured transitions are enabled.
func _request_half_turn_or_transition(sequence_name: String, half_turn_direction: int) -> void: # Declare this function.
	if use_captured_transitions:                                                               # Preserve the old full-frame captured transition path when that toggle is enabled.
		_request_transition(sequence_name)                                                        # Start or snap the existing transition sequence.
		return                                                                                    # Return after requesting the legacy transition.
	_enter_turn_45(half_turn_direction)                                                        # Start the camera-only 22-degree lead-in toward the diagonal view.



# _enter_turn_45: Starts a view-relative turn at the 22-degree interpolation view without changing the committed cardinal facing.
func _enter_turn_45(half_turn_direction: int) -> void:                                     # Declare this function.
	var preserved_world_position := _current_player_world_position()                           # Capture the player's physical map point before changing the camera basis.
	turn_45_direction = -1 if half_turn_direction < 0 else 1                                  # Store whether this halfway view is between cardinal-left or cardinal-right.
	turn_step = 1                                                                              # Begin at the 22-degree interpolation stage.
	active_sequence_name = TURN_STAGE_SEQUENCE_NAMES[_active_turn_visual_stage()]              # Label the visible 22-degree interpolation frame, including reversed turns.
	is_transitioning = false                                                                   # Ensure stable renderer mode stays active.
	active_sequence = []                                                                       # Clear any stale captured transition frames.
	phase_index = 0                                                                            # Reset captured transition frame bookkeeping.
	phase_timer = 0.0                                                                          # Reset captured transition time bookkeeping.
	character_is_moving = false                                                                # Freeze actor movement only while this brief camera interpolation plays.
	last_blocked_direction = ""                                                                # Clear movement-blocked labels because movement is disabled in this view.
	_set_player_world_position_for_current_view(preserved_world_position)                      # Re-express the same physical point in the newly active diagonal camera coordinates.
	_show_stable()                                                                             # Render the 22-degree wall view immediately.
	_begin_turn_passthrough("to_diagonal")                                                     # Continue automatically into the stable 45-degree diagonal view.



# _process_turn_45_input: Leaves a stable diagonal view through the appropriate 22 or 66-degree passthrough frame.
func _process_turn_45_input(turn_direction: int) -> void:                                  # Declare this function.
	var preserved_world_position := _current_player_world_position()                           # Keep the player fixed on the source map while committing or cancelling this camera rotation.
	if turn_direction == 0:                                                                    # Stay on the halfway view when no twist key was just pressed.
		return                                                                                    # Return without changing the halfway-turn state.
	if turn_direction == turn_45_direction:                                                    # Continue through 66 toward the next cardinal orientation.
		turn_step = 3                                                                            # Select the exit interpolation stage (reversed automatically for counterclockwise turns).
		active_sequence_name = TURN_STAGE_SEQUENCE_NAMES[_active_turn_visual_stage()]            # Label the actual visible 22 or 66-degree art stage.
		_set_player_world_position_for_current_view(preserved_world_position)                    # Preserve the same physical point under the changed camera basis.
		_show_stable()                                                                           # Render the exit interpolation wall set.
		_begin_turn_passthrough("to_next_cardinal")                                              # Finish automatically at the neighboring cardinal direction.
		return                                                                                    # Do not require an additional turn-key press.
	turn_step = 1                                                                              # Select the entry interpolation stage while backing out toward the original cardinal view.
	active_sequence_name = TURN_STAGE_SEQUENCE_NAMES[_active_turn_visual_stage()]              # Label the actual visible 22 or 66-degree art stage.
	_set_player_world_position_for_current_view(preserved_world_position)                      # Preserve the same physical point under the changed camera basis.
	_show_stable()                                                                             # Render the return interpolation wall set.
	_begin_turn_passthrough("to_previous_cardinal")                                            # Finish automatically at the original cardinal direction.



# _begin_turn_passthrough: Starts a short, camera-only 22/66-degree interpolation frame.
func _begin_turn_passthrough(target: String) -> void:
	is_turn_passthrough = true                                                                 # Block new movement and turn input until this one authored frame has displayed.
	turn_passthrough_timer = 0.0                                                               # Start timing the interpolation frame from its first rendered update.
	turn_passthrough_target = target                                                          # Remember which stable orientation follows this frame.


# _advance_turn_passthrough: Finishes a 22/66-degree interpolation and enters its stable destination view.
func _advance_turn_passthrough(delta: float, manual_step: bool = false) -> void:
	if not manual_step:                                                                        # Time stages only during normal automatic playback.
		turn_passthrough_timer += delta                                                          # Accumulate visible time for the current interpolation frame.
		if turn_passthrough_timer < TURN_PASSTHROUGH_SECONDS:                                   # Keep the authored 22/66 art on screen for its full duration.
			return                                                                                 # Wait until the frame has completed.
	var target := turn_passthrough_target                                                     # Preserve the destination before clearing transient state.
	var preserved_world_position := _current_player_world_position()                          # Capture the physical player point before changing the camera basis.
	is_turn_passthrough = false                                                               # Resume ordinary input after this function reaches a stable orientation.
	turn_passthrough_timer = 0.0                                                              # Clear elapsed interpolation time for the next turn.
	turn_passthrough_target = ""                                                              # Clear the completed destination marker.
	match target:                                                                              # Choose the stable orientation after the animated stage.
		"to_diagonal":                                                                         # Complete cardinal -> 22 -> diagonal.
			turn_step = 2                                                                          # Make the 45-degree view a stable, mobile diagonal orientation.
			active_sequence_name = "turn_45"                                                      # Keep the status/debug state explicit.
			_set_player_world_position_for_current_view(preserved_world_position)                 # Reproject the unchanged player point into the 45-degree basis.
			_show_stable()                                                                         # Draw the established 45-degree floor and wall view.
		"to_next_cardinal":                                                                    # Complete diagonal -> 66 -> neighboring cardinal.
			var sequence_name := "turn_left" if turn_45_direction < 0 else "turn_right"          # Commit the cardinal rotation in the active turn direction.
			_finish_snap_transition(sequence_name)                                                 # Apply that facing while preserving the physical player position.
		"to_previous_cardinal":                                                                # Complete diagonal -> 22 -> original cardinal.
			turn_45_direction = 0                                                                  # Clear the temporary diagonal basis without changing committed facing.
			turn_step = 0                                                                          # Restore the original cardinal renderer.
			active_sequence_name = "idle"                                                         # Return status/debug state to stable cardinal.
			_set_player_world_position_for_current_view(preserved_world_position)                 # Reproject the unchanged player point into the original cardinal basis.
			_show_stable()                                                                         # Draw the restored cardinal floor and wall view.
			_position_player()                                                                     # Refresh the local player projection immediately.
			_update_debug_map_overlay()                                                            # Refresh the top-down orientation and slot graph immediately.
			_update_status()                                                                       # Refresh the status line at the stable destination.



# _finish_snap_transition: Applies a movement or turn result immediately and redraws the stable view.
func _finish_snap_transition(sequence_name: String) -> void:                                # Declare this function.
	var preserved_world_position := _current_player_world_position()                           # Capture the pre-turn physical point before any facing basis is changed.
	is_transitioning = false                                                                   # Ensure the controller stays in stable/input mode.
	is_turn_passthrough = false                                                               # Ensure a completed cardinal snap cannot leave a stale camera interpolation active.
	turn_passthrough_timer = 0.0                                                              # Clear any previous 22/66 interpolation time.
	turn_passthrough_target = ""                                                              # Clear any previous 22/66 interpolation destination.
	if sequence_name == "turn_left" or sequence_name == "turn_right":                         # Only a completed turn leaves the halfway camera orientation.
		turn_45_direction = 0                                                                      # Return to a committed cardinal direction after the matching second twist.
		turn_step = 0                                                                              # Clear the 22/45/66 interpolation stage after reaching the new cardinal direction.
	_apply_grid_result(sequence_name)                                                          # Apply the pending cell delta or facing rotation.
	if sequence_name == "turn_left" or sequence_name == "turn_right":                         # A turn changes only camera orientation, never the physical player point.
		_set_player_world_position_for_current_view(preserved_world_position)                      # Reproject the unchanged world point through the newly committed cardinal basis.
	else:                                                                                       # Preserve the established entry-contact rules for ordinary cell movement.
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
	turn_45_direction = 0                                                                      # Clear any temporary halfway-turn view when a captured transition completes.
	turn_step = 0                                                                              # Clear any intermediate turn stage when a captured transition completes.
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



# _view_forward_vector: Returns the current visible camera direction, including temporary 45-degree stops.
func _view_forward_vector() -> Vector2:                                                     # Declare this function.
	if _is_turn_45_view():                                                                    # Use a diagonal basis while stopped on halfway-turn validation art.
		return _turn_45_view_forward_vector()                                                    # Return the current 45-degree view direction.
	return Vector2(_facing_vector()).normalized()                                             # Return the committed cardinal camera direction.



# _view_forward_vector_for_state: Returns one saved player's visible camera direction for top-down debug markers.
func _view_forward_vector_for_state(state: Dictionary) -> Vector2:                         # Declare this function.
	var state_facing := int(state.get("facing", 0))                                           # Read the saved player's committed cardinal facing.
	var state_turn_45 := int(state.get("turn_45_direction", 0))                                # Read the saved player's temporary halfway-turn direction.
	var state_turn_step := int(state.get("turn_step", 2 if state_turn_45 != 0 else 0))          # Read the saved 22/45/66 interpolation stage.
	var cardinal_forward := Vector2(_facing_vector_for_index(state_facing)).normalized()       # Convert that committed facing to a world vector.
	if state_turn_45 == 0:                                                                    # Use the cardinal direction when no halfway-turn view is active.
		return cardinal_forward                                                                  # Return the saved player's cardinal view direction.
	return cardinal_forward.rotated(deg_to_rad(22.5 * float(state_turn_step * state_turn_45))) # Return the saved player's active turn-view direction.



# _view_right_vector: Returns the current visible camera-right direction, including temporary 45-degree stops.
func _view_right_vector() -> Vector2:                                                       # Declare this function.
	if _is_turn_45_view():                                                                    # Use a diagonal basis while stopped on halfway-turn validation art.
		return _turn_45_view_right_vector()                                                      # Return the current 45-degree camera-right direction.
	return Vector2(-_left_vector()).normalized()                                              # Return the committed cardinal camera-right direction.



# _view_left_vector: Returns the current visible camera-left direction, including temporary 45-degree stops.
func _view_left_vector() -> Vector2:                                                        # Declare this function.
	return -_view_right_vector()                                                              # Return the opposite of the current camera-right vector.



# _turn_45_view_forward_vector: Returns the active 22, 45, or 66-degree turn-view direction for the current player.
func _turn_45_view_forward_vector() -> Vector2:                                            # Declare this function.
	var cardinal_forward := Vector2(_facing_vector()).normalized()                             # Start from the committed cardinal facing.
	return cardinal_forward.rotated(deg_to_rad(22.5 * float(turn_step * turn_45_direction)))   # Rotate toward the requested cardinal in authored 22-degree increments.



# _turn_45_view_right_vector: Returns the diagonal halfway-turn camera-right vector for the current player.
func _turn_45_view_right_vector() -> Vector2:                                              # Declare this function.
	var forward := _turn_45_view_forward_vector()                                             # Read the current diagonal forward vector.
	return Vector2(-forward.y, forward.x).normalized()                                       # Rotate forward clockwise in screen/map space to get camera-right.



# _is_turn_45_view: Returns whether this player is currently stopped on the halfway-turn validation view.
func _is_turn_45_view() -> bool:                                                           # Declare this function.
	return turn_45_direction != 0 and turn_step != 0                                         # Report whether any temporary 22/45/66 turn view is active.



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



# _build_empty_grid_audit_wall_edges: Builds the temporary wall-free 5x5 grid used to isolate slot-guide geometry.
func _build_empty_grid_audit_wall_edges() -> void:
	wall_edges.clear()                                                                         # Discard the saved/reference maze before creating the isolated test surface.
	for y in range(MAP_HEIGHT):                                                                # Visit every row in the temporary 5x5 grid.
		for x in range(MAP_WIDTH):                                                               # Visit every cell in the temporary 5x5 grid.
			wall_edges[Vector2i(x, y)] = {WALL_EDGE_N: false, WALL_EDGE_E: false, WALL_EDGE_S: false, WALL_EDGE_W: false} # Leave all four cell edges open for an uncluttered diagnostic map.
	grid_position = Vector2i(4, 4)                                                            # Start the sole player at the center of the 9x9 grid.
	facing = 0                                                                                 # Start facing north so cardinal turns can be audited from a known state.
	turn_45_direction = 0                                                                      # Start in a committed cardinal view, not a halfway turn.
	turn_step = 0                                                                              # Start outside any 22/45/66 interpolation stage.
	local_floor_position = HOME_LOCAL_FLOOR_POSITION                                           # Use the usual in-cell resting position.
	pending_grid_delta = Vector2i.ZERO                                                        # Clear any stale crossing request.
	last_blocked_direction = ""                                                                # Clear any stale blocked-movement diagnostic.



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
	turn_45_direction = 0                                                                      # Reset any temporary halfway-turn view when restoring the map.
	turn_step = 0                                                                              # Reset any 22/45/66 interpolation stage when restoring the map.
	local_floor_position = HOME_LOCAL_FLOOR_POSITION                                           # Reset the player to the normal local tile position.
	pending_grid_delta = Vector2i.ZERO                                                         # Clear any stale cell-crossing request.
	last_blocked_direction = ""                                                                # Clear any stale blocked-movement status.



# _regenerate_runtime_map: Rerolls the 4x4 thin-wall maze during play and redraws every dependent view.
func _regenerate_runtime_map() -> void:                                                     # Declare this function.
	held_keycodes.clear()                                                                      # Clear held-key fallback state so the reset starts from neutral input.
	was_regenerate_map_pressed = true                                                          # Keep the regenerate key from firing again until released.
	if TEMP_GRID_AUDIT:                                                                        # Keep R scoped to the single-player 9x9 audit map.
		if TEMP_RANDOM_GRID_AUDIT:                                                               # Generate another enclosed, connected random map for wall-render testing.
			_build_random_maze_wall_edges()                                                           # Preserve the generator's closed exterior boundary.
		else:                                                                                    # Retain the alternate wall-free audit behavior.
			_build_empty_grid_audit_wall_edges()                                                       # Restore the same empty 9x9 surface.
		player_states = [_make_player_state(0, Vector2i(4, 4), 0)]                               # Restore the sole centered audit player.
		_bind_player_context(0)                                                                   # Rebind the only active player view.
		_render_all_player_views()                                                                # Redraw the single audit view and source map.
		_update_status()                                                                          # Refresh the one-player status text.
		return                                                                                    # Skip the normal two-player random-maze reset.
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
	turn_45_direction = 0                                                                      # Reset any temporary halfway-turn view when generating a new map.
	turn_step = 0                                                                              # Reset any 22/45/66 interpolation stage when generating a new map.
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
	var lines: Array[String] = []                                                              # Build one compact status line per local player.
	for player_index in range(player_states.size()):                                          # Format every local player's saved state.
		var state: Dictionary = player_states[player_index]                                      # Read this player's state.
		var state_facing_name := _view_facing_name_for_state(state)                              # Format this player's cardinal or halfway-turn direction.
		var state_cell: Vector2i = state.get("grid_position", Vector2i.ZERO)                     # Read this player's current cell.
		var state_local: Vector2 = state.get("local_floor_position", HOME_LOCAL_FLOOR_POSITION)  # Read this player's local tile position.
		var state_view: Dictionary = player_views[player_index] if player_index < player_views.size() else {} # Read this player's view bundle.
		var state_sprite: AnimatedSprite2D = state_view.get("player_sprite", null)               # Read this player's sprite for animation reporting.
		var state_animation := String(state_sprite.animation) if state_sprite != null else "-"    # Format this player's current animation name.
		var phase_text := "stable"                                                               # Default this player to stable mode.
		if int(state.get("forward_step", 0)) != 0:                                               # Show which live forward interpolation floor/wall set is visible.
			phase_text = "forward %d%s" % [int(state.get("forward_step", 0)), " manual" if manual_forward_step_enabled else ""] # Identify whether the visible frame waits for a fresh forward input.
		elif int(state.get("strafe_step", 0)) != 0:                                               # Show which live side interpolation floor/wall set is visible.
			phase_text = "strafe %d%s" % [int(state.get("strafe_step", 0)), " manual" if manual_strafe_step_enabled else ""] # Identify whether the visible frame waits for a fresh lateral input.
		elif bool(state.get("is_transitioning", false)):                                        # Show captured phase progress when this player is transitioning.
			phase_text = "%s phase %d" % [String(state.get("active_sequence_name", "idle")), int(state.get("phase_index", 0)) + 1] # Format the transition status.
		lines.append("P%d %s Facing %s Cell %d,%d Local %.2f,%.2f Anim %s Walls %s%s" % [player_index + 1, phase_text, state_facing_name, state_cell.x, state_cell.y, state_local.x, state_local.y, state_animation, _visible_wall_ids_text_for_state(state), (" Blocked " + String(state.get("last_blocked_direction", ""))) if not String(state.get("last_blocked_direction", "")).is_empty() else ""]) # Add this player status line.
	status_label.text = "%s\n%s\nP1: WASD move, Q/E turn. P2: numpad 8/5/4/6 move, numpad 7/9 twist. R rerolls map. F2 slot grid. F3 %s debug menu." % [lines[0] if lines.size() > 0 else "P1 missing", lines[1] if lines.size() > 1 else "P2 missing", "closes" if debug_menu_open else "opens"] # Update the on-screen debug status label.



# _view_facing_name_for_state: Formats cardinal and halfway-turn directions for the status overlay.
func _view_facing_name_for_state(state: Dictionary) -> String:                            # Declare this function.
	var cardinal_names: Array[String] = ["N", "E", "S", "W"]                                # Track the committed facing direction names.
	var state_facing := wrapi(int(state.get("facing", 0)), 0, 4)                             # Normalize the saved cardinal facing index.
	var state_turn_45 := int(state.get("turn_45_direction", 0))                              # Read whether this player is stopped on a halfway turn.
	if state_turn_45 == 0:                                                                   # Use a plain cardinal label when no halfway turn is active.
		return cardinal_names[state_facing]                                                     # Return the committed cardinal facing name.
	var forward := _view_forward_vector_for_state(state)                                     # Compute the diagonal view vector from the saved state.
	var vertical_name := "N" if forward.y < 0.0 else "S"                                     # Choose the north/south half of the diagonal name.
	var horizontal_name := "E" if forward.x > 0.0 else "W"                                   # Choose the east/west half of the diagonal name.
	return vertical_name + horizontal_name                                                   # Return a conventional diagonal label such as NE or SW.



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
