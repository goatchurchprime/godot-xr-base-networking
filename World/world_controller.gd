extends Node3D

# Cesium's official 3D Tiles sample is retained as an offline-configuration
# fallback. The normal preview uses Cesium ion World Terrain and Bing imagery.
const PUBLIC_TILESET := "https://raw.githubusercontent.com/CesiumGS/cesium/main/Apps/SampleData/Cesium3DTiles/Batched/BatchedColors/tileset.json"
const WORLD_TERRAIN_ASSET_ID := 1
const BING_AERIAL_ASSET_ID := 2
const OSM_BUILDINGS_ASSET_ID := 96188
const PREVIEW_LATITUDE := 51.454969107393154
const PREVIEW_LONGITUDE := -2.627806814816458
# Approximate WGS84 ellipsoid height of the bridge deck. This is deliberately
# easy to tune after the first visual comparison with Cesium terrain.
const PREVIEW_ALTITUDE := 132.0
const REFERENCE_MIN_VISIBLE_TILES := 8
const REFERENCE_TARGET_TILE_DIAGONAL_METRES := 25000.0
const REFERENCE_MAX_TILE_DIAGONAL_METRES := 500000.0
const REFERENCE_MIN_STREAM_MSEC := 15000
const REFERENCE_MAX_STREAM_MSEC := 240000
# Battle Road's dynamic camera uses this planetary-scale far plane each frame.
const BATTLE_ROAD_FAR_PLANE := 35358652.0
# The smoothed Styrian LiDAR crop covers this local East-Up-South rectangle.
# World Terrain leaves whose centres fall inside it are suppressed once they
# are small enough, leaving Cesium available outside the accurate local patch.
const LOCAL_TERRAIN_CLIP_RECT := Rect2(-2243.0, -2037.0, 4152.0, 4165.0)
const LOCAL_TERRAIN_CLIP_MAX_TILE_DIAGONAL := 8000.0
const XR_VERTICAL_DEAD_ZONE := 0.72

## The WorldFrame owns the geospatial presentation, not the player. Assembly
## scenes inject their player rig through these relative paths. An empty camera
## path selects the small built-in solo desktop/OpenXR bridge.
@export_node_path("Node3D") var player_root_path := NodePath("PlayerSocket")
@export_node_path("Camera3D") var camera_path := NodePath()
@export_node_path("XROrigin3D") var xr_origin_path := NodePath()
@export_node_path("XRController3D") var left_controller_path := NodePath()
@export_node_path("XRController3D") var right_controller_path := NodePath()
@export var host_manages_locomotion := false

@onready var status_label: Label = $Interface/Panel/Status
@onready var world_frame: WorldFrame3D = $Frame
@onready var geospatial_root: Node3D = $Frame/Geospatial
@onready var survey_root: Node3D = $Frame/Survey
@onready var cave_component: CaveSurveyComponent = $Frame/Survey/CaveSurvey
@onready var point_cloud_root: Node3D = $Frame/PointClouds
@onready var world_debug_root: Node3D = $Frame/Debug
@onready var local_player_root: Node3D = get_node(player_root_path)
@onready var world_environment: WorldEnvironment = $Frame/Environment/CaveEnvironment/WorldEnvironment
@onready var sun: DirectionalLight3D = $Frame/Environment/CaveEnvironment/Sun
@onready var sun_direction_controller: SunDirectionController = $ApplicationSystems/SunDirectionController

var globe: CesiumGeoreference
var tileset: Cesium3DTileset
var local_terrain_tileset: Cesium3DTileset
var local_terrain_material: ShaderMaterial
var local_terrain_uses_aerial_imagery := false
var world_terrain_enabled := true
var buildings_tileset: Cesium3DTileset
var buildings_material: ShaderMaterial
var point_cloud: PotreePointCloud
var point_cloud_directory := ""
var survex_layer: Node3D
var survex_pointer: MeshInstance3D
var camera: Camera3D
var xr_origin: XROrigin3D
var left_controller: XRController3D
var right_controller: XRController3D
var xr_mode := false
var using_world_terrain := false
var announced_first_tile := false
var local_terrain_ready := false
var local_terrain_clip_enabled := false
var clipped_world_terrain_tiles: Array[MeshInstance3D] = []
var view_framed := false
var fly_speed := 50.0
var xr_fly_speed := 35.0
var xr_snap_turn_ready := true
var xr_station_select_ready := true
var capture_started_msec := -1
var bake_started_msec := -1
var bake_last_reported_second := -1
var local_to_ecef := Transform3D.IDENTITY
var startup_survex_path := ""
var startup_survex_data: Dictionary = {}


func _ready() -> void:
	# CesiumGDConfig creates its singleton node on first access. Defer setup so
	# the scene root is no longer in its child-initialisation phase.
	_initialize_cesium.call_deferred()


func _initialize_cesium() -> void:
	xr_mode = OS.has_feature("steam_frame") or "--xr" in OS.get_cmdline_user_args()
	startup_survex_path = find_survex_layer_file()
	startup_survex_data = read_survex_data(startup_survex_path)
	globe = CesiumGeoreference.new()
	globe.name = "CesiumGeoreference"
	globe.origin_type = 0 # Cartographic origin: keep local Godot coordinates small.
	# Clifton Suspension Bridge, with the Godot origin close to the deck centre.
	var survex_origin := read_survex_cartographic_origin(startup_survex_data)
	if survex_origin.is_empty():
		globe.latitude = PREVIEW_LATITUDE
		globe.longitude = PREVIEW_LONGITUDE
		globe.altitude = PREVIEW_ALTITUDE
	else:
		globe.longitude = float(survex_origin[0])
		globe.latitude = float(survex_origin[1])
		globe.altitude = float(survex_origin[2])
	globe.rotation_degrees.x = -90.0
	geospatial_root.add_child(globe)

	tileset = Cesium3DTileset.new()
	var config := CesiumGDConfig.get_singleton(self)
	# Never bundle the token into the exported PCK. Development clones use an
	# ignored file at the project root; deployed builds use an adjacent file.
	# CESIUM_ION_TOKEN takes precedence over both.
	var environment_token := OS.get_environment("CESIUM_ION_TOKEN")
	if environment_token.is_empty():
		var development_token_path := ProjectSettings.globalize_path("res://cesium-ion-token.local")
		if FileAccess.file_exists(development_token_path):
			environment_token = FileAccess.get_file_as_string(development_token_path).strip_edges()
	if environment_token.is_empty():
		var token_path := OS.get_executable_path().get_base_dir().path_join("cesium-ion-token")
		if FileAccess.file_exists(token_path):
			environment_token = FileAccess.get_file_as_string(token_path).strip_edges()
	# The explicit deployment token is authoritative. CesiumGDConfig restores a
	# cached ion_session.dat first, which may contain a revoked older token.
	if not environment_token.is_empty():
		config.accessToken = environment_token
	using_world_terrain = not config.accessToken.is_empty()
	if using_world_terrain:
		tileset.name = "CesiumWorldTerrain"
		tileset.data_source = 0 # Cesium ion.
		tileset.ion_asset_id = WORLD_TERRAIN_ASSET_ID

		var imagery := CesiumIonRasterOverlay.new()
		imagery.name = "BingMapsAerial"
		imagery.asset_id = BING_AERIAL_ASSET_ID
		tileset.add_child(imagery)
	else:
		tileset.name = "PublicCesiumSample"
		tileset.data_source = 1 # Direct URL; useful before an ion token is set.
		tileset.url = PUBLIC_TILESET
		if startup_survex_path.is_empty():
			globe.latitude = 40.0425
			globe.longitude = -75.6121
			globe.altitude = 160.0
	# Desktop can afford much finer refinement than a standalone headset. This
	# only selects the best level present in the terrain source; it cannot add
	# detail that the source dataset does not contain.
	var terrain_sse := 6.0 if xr_mode else 1.0
	var configured_sse := OS.get_environment("TUNNELXR_TERRAIN_SSE")
	if configured_sse.is_valid_float():
		terrain_sse = maxf(configured_sse.to_float(), 0.25)
	tileset.maximum_screen_space_error = terrain_sse
	tileset.maximum_simultaneous_tile_loads = 8 if xr_mode else 12
	tileset.maximum_cached_bytes = 96 * 1024 * 1024 if xr_mode else 128 * 1024 * 1024
	tileset.preload_ancestors = true
	tileset.preload_siblings = false
	tileset.forbid_holes = true
	tileset.create_physics_meshes = false
	tileset.rotation_degrees.x = 90.0
	globe.add_child(tileset)
	tileset.child_entered_tree.connect(_on_world_terrain_tile_added)

	# Tile vertices arrive in the plugin's fixed, Earth-centred engine frame.
	# Rotate that frame into local East-Up-South so the WGS84 surface normal is
	# exactly Godot +Y and local -Z is true north.
	var ecef := Vector3(globe.ecefX, globe.ecefY, globe.ecefZ)
	var surface_up := ecef.normalized()
	var east := -surface_up.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	var south := east.cross(surface_up).normalized()
	var local_to_ecef_basis := Basis(east, surface_up, south)
	local_to_ecef = Transform3D(local_to_ecef_basis, ecef)
	var fixed_engine_to_ecef := Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0))
	var ecef_engine_to_local := local_to_ecef_basis.inverse() * fixed_engine_to_ecef
	tileset.global_basis = ecef_engine_to_local
	var local_terrain_url := OS.get_environment("TUNNELXR_LOCAL_TERRAIN_URL")
	# Two independently refined terrain surfaces cannot safely overlap. Until
	# the native plugin exposes a geographic tile excluder, prefer the accurate
	# local surface alone. TUNNELXR_KEEP_WORLD_TERRAIN=1 is an explicit diagnostic
	# escape hatch, not the normal mode.
	var local_terrain_only := OS.get_environment("TUNNELXR_LOCAL_TERRAIN_ONLY") == "1" or (
		not local_terrain_url.is_empty() and OS.get_environment("TUNNELXR_KEEP_WORLD_TERRAIN") != "1"
	)
	world_terrain_enabled = not local_terrain_only
	local_terrain_clip_enabled = not local_terrain_url.is_empty() and world_terrain_enabled
	if local_terrain_only:
		tileset.visible = false
	# A small, high-resolution terrain crop can sit over World Terrain while the
	# global source continues to provide the horizon and planetary context.
	if not local_terrain_url.is_empty():
		# Cesium World Terrain only reaches level 13 at the Styrian cave (roughly
		# 20--40 m samples), while its aerial imagery refines much further. Use the
		# 1 m ALS geometry in the foreground and drape the same imagery over it.
		var local_terrain_sse := 10.0 if xr_mode else 6.0
		var configured_local_sse := OS.get_environment("TUNNELXR_LOCAL_TERRAIN_SSE")
		if configured_local_sse.is_valid_float():
			local_terrain_sse = maxf(configured_local_sse.to_float(), 0.25)
		local_terrain_material = ShaderMaterial.new()
		local_terrain_material.shader = load("res://World/shaders/local_terrain.gdshader")
		local_terrain_tileset = Cesium3DTileset.new()
		local_terrain_tileset.name = "LocalHighResolutionTerrain"
		local_terrain_tileset.data_source = 1
		local_terrain_tileset.url = local_terrain_url
		local_terrain_tileset.maximum_screen_space_error = local_terrain_sse
		local_terrain_tileset.maximum_simultaneous_tile_loads = 6 if xr_mode else 10
		local_terrain_tileset.maximum_cached_bytes = 192 * 1024 * 1024 if xr_mode else 384 * 1024 * 1024
		local_terrain_tileset.preload_ancestors = true
		local_terrain_tileset.preload_siblings = false
		# This foreground detail layer overlaps World Terrain. Let a missing local
		# child be temporarily blank (with the global terrain beneath it) instead of
		# keeping its coarse olive parent over already-loaded detailed children.
		local_terrain_tileset.forbid_holes = false
		local_terrain_tileset.create_physics_meshes = false
		local_terrain_tileset.rotation_degrees.x = 90.0
		if using_world_terrain:
			var local_imagery := CesiumIonRasterOverlay.new()
			local_imagery.name = "BingMapsAerial"
			local_imagery.asset_id = BING_AERIAL_ASSET_ID
			local_terrain_tileset.add_child(local_imagery)
			local_terrain_uses_aerial_imagery = true
		globe.add_child(local_terrain_tileset)
		local_terrain_tileset.global_basis = ecef_engine_to_local
		local_terrain_tileset.child_entered_tree.connect(_on_local_terrain_tile_added)
		print("Local high-resolution terrain: ", local_terrain_url)

	if using_world_terrain and not local_terrain_only and "--bake-reference" not in OS.get_cmdline_user_args():
		buildings_material = ShaderMaterial.new()
		buildings_material.shader = load("res://World/shaders/osm_buildings.gdshader")
		buildings_tileset = Cesium3DTileset.new()
		buildings_tileset.name = "CesiumOSMBuildings"
		buildings_tileset.data_source = 0
		buildings_tileset.ion_asset_id = OSM_BUILDINGS_ASSET_ID
		# Buildings are secondary context in this mobile XR preview. A coarser
		# budget avoids competing too aggressively with terrain and imagery.
		buildings_tileset.maximum_screen_space_error = 24.0
		buildings_tileset.maximum_simultaneous_tile_loads = 4 if xr_mode else 8
		buildings_tileset.maximum_cached_bytes = 48 * 1024 * 1024 if xr_mode else 64 * 1024 * 1024
		buildings_tileset.preload_ancestors = true
		buildings_tileset.preload_siblings = false
		buildings_tileset.forbid_holes = false
		buildings_tileset.create_physics_meshes = false
		buildings_tileset.rotation_degrees.x = 90.0
		globe.add_child(buildings_tileset)
		buildings_tileset.global_basis = ecef_engine_to_local
		buildings_tileset.child_entered_tree.connect(_on_building_tile_added)
	add_north_marker()

	if not bind_host_player():
		if xr_mode:
			setup_xr_camera()
		else:
			setup_desktop_camera()
	setup_sun_controls()
	if startup_survex_path.is_empty() and "--bake-reference" not in OS.get_cmdline_user_args():
		setup_clifton_point_cloud()
	setup_survex_layer(startup_survex_path)
	if "--bake-reference" in OS.get_cmdline_user_args() and not xr_mode:
		# Request detailed terrain around the survey origin instead of the very
		# broad initial survey overview. The baked meshes keep these local EUS
		# transforms, so they line up with cave data placed at the same origin.
		camera.set_process(false)
		camera.set_physics_process(false)
		camera.global_position = Vector3(450.0, 550.0, 700.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
		# Coarse Cesium ancestors span continental distances. Keep them visible in
		# the baked editor scene so its Camera3D can be used to tune horizon depth.
		camera.far = 3000000.0
		view_framed = true
		tileset.maximum_screen_space_error = 16.0
		tileset.maximum_simultaneous_tile_loads = 8
		tileset.preload_siblings = false
		status_label.text = "Streaming Cesium terrain for the offline editor reference…"

	if using_world_terrain:
		if survex_layer != null:
			status_label.text = "Loading terrain and OSM buildings around the Survex survey…"
			print("Godot Cesium %s preview ready; requesting terrain around the Survex survey" % ["XR" if xr_mode else "desktop"])
		else:
			status_label.text = "Loading Clifton terrain, point cloud, and OSM buildings…"
			print("Godot Cesium %s preview ready; requesting Clifton terrain and point cloud" % ["XR" if xr_mode else "desktop"])
	else:
		status_label.text = "No ion token found; loading the public 3D Tiles sample…"
		print("No ion token found; requesting public sample: ", PUBLIC_TILESET)


func setup_clifton_point_cloud() -> void:
	point_cloud_directory = find_clifton_point_cloud_directory()
	if point_cloud_directory.is_empty():
		push_warning("Clifton Potree dataset not found; set TUNNELXR_POINTCLOUD_DIR or install pointcloud/clifton-potree beside the executable")
		return
	point_cloud = PotreePointCloud.new()
	point_cloud.name = "CliftonSuspensionBridgePointCloud"
	point_cloud.auto_load = false
	point_cloud.point_budget = 650000 if xr_mode else 1000000
	point_cloud.cache_point_budget = 1300000 if xr_mode else 2000000
	point_cloud.minimum_node_pixel_spacing = 2.5 if xr_mode else 2.0
	point_cloud.point_size = 2.0
	point_cloud.adaptive_point_size = true
	point_cloud.hierarchy_handoff = true
	point_cloud.near_fragmentation = true
	point_cloud.near_fragment_distance = 0.8
	point_cloud.loaded.connect(_on_point_cloud_loaded)
	point_cloud.load_failed.connect(_on_point_cloud_failed)
	point_cloud_root.add_child(point_cloud)
	point_cloud.set_camera(camera)
	point_cloud.load_cloud(point_cloud_directory.path_join("metadata.json"))


func find_clifton_point_cloud_directory() -> String:
	var candidates: Array[String] = []
	var configured := OS.get_environment("TUNNELXR_POINTCLOUD_DIR")
	if not configured.is_empty():
		candidates.append(configured)
	candidates.append(OS.get_executable_path().get_base_dir().path_join("pointcloud/clifton-potree"))
	# Development checkout: godot-potree is a sibling of this Cesium project.
	candidates.append(ProjectSettings.globalize_path("res://../godot-potree/test-data/clifton-potree"))
	for candidate in candidates:
		if FileAccess.file_exists(candidate.path_join("metadata.json")):
			return candidate
	return ""


func setup_survex_layer(path := "") -> void:
	if path.is_empty():
		path = find_survex_layer_file()
	if path.is_empty():
		print("No Survex layer configured; set TUNNELXR_SURVEX_FILE or install data/survex/*.survex.json")
		return
	survex_layer = cave_component.layer
	var error: String
	if not startup_survex_data.is_empty() and path == startup_survex_path:
		error = cave_component.load_georeferenced_data(startup_survex_data, globe, path)
		startup_survex_data = {}
	else:
		error = cave_component.load_georeferenced_file(path, globe)
	if not error.is_empty():
		push_error(error)
		survex_layer = null
		return
	survex_layer.station_selected.connect(_on_survex_station_selected)
	setup_survex_pointer()
	frame_survex_layer()
	print("Survex layer loaded: %s (%d stations, %d legs, %d LRUD tubes)" % [
		survex_layer.title,
		survex_layer.stations.size(),
		survex_layer.legs.size(),
		survex_layer.tubes.size(),
	])


func find_survex_layer_file() -> String:
	var configured := OS.get_environment("TUNNELXR_SURVEX_FILE")
	if not configured.is_empty() and FileAccess.file_exists(configured):
		return configured
	var bundled := "res://World/survey_data/204allupperB_cave_subset.survex.json"
	if FileAccess.file_exists(bundled):
		return bundled
	var directory_path := OS.get_executable_path().get_base_dir().path_join("data/survex")
	if not DirAccess.dir_exists_absolute(directory_path):
		return ""
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return ""
	var files := directory.get_files()
	files.sort()
	for file in files:
		if file.ends_with(".survex.json"):
			return directory_path.path_join(file)
	return ""


func read_survex_data(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func read_survex_cartographic_origin(parsed: Dictionary) -> Array:
	if parsed.is_empty():
		return []
	var registration = parsed.get("registration", {})
	if typeof(registration) != TYPE_DICTIONARY:
		return []
	var cartographic = registration.get("origin_cartographic", [])
	if typeof(cartographic) != TYPE_ARRAY or cartographic.size() != 3:
		return []
	return cartographic


func frame_survex_layer() -> void:
	if survex_layer == null or camera == null:
		return
	var bounds: AABB = survex_layer.get_focus_bounds()
	if bounds.size.length_squared() <= 0.0:
		return
	var target := survex_layer.global_transform * bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 50.0)
	if xr_mode and xr_origin != null:
		xr_origin.global_position = target + Vector3(radius * 0.25, radius * 0.25, radius * 0.75)
	else:
		camera.set_process(false)
		camera.set_physics_process(false)
		camera.global_position = target + Vector3(radius * 0.35, radius * 0.45, radius * 1.1)
		camera.look_at(target, Vector3.UP)
		camera.far = BATTLE_ROAD_FAR_PLANE
		view_framed = true


func setup_survex_pointer() -> void:
	survex_pointer = MeshInstance3D.new()
	survex_pointer.name = "SurvexPointer"
	var pointer_mesh := BoxMesh.new()
	pointer_mesh.size = Vector3(0.012, 0.012, 1.0)
	var pointer_material := StandardMaterial3D.new()
	pointer_material.albedo_color = Color(0.0, 0.9, 1.0)
	pointer_material.emission_enabled = true
	pointer_material.emission = Color(0.0, 0.65, 1.0)
	pointer_material.emission_energy_multiplier = 2.0
	pointer_mesh.material = pointer_material
	survex_pointer.mesh = pointer_mesh
	survex_pointer.visible = false
	survey_root.add_child(survex_pointer)


func _on_survex_station_selected(station: Dictionary) -> void:
	status_label.text = "Survex station • %s • %s" % [
		str(station.get("name", "unnamed")),
		", ".join(station.get("flags", [])),
	]


func _on_point_cloud_loaded(_metadata: PotreeMetadata) -> void:
	var error := await point_cloud.apply_cesium_georeference(
		globe,
		point_cloud_directory.path_join("georeference.json")
	)
	if not error.is_empty():
		_on_point_cloud_failed("georeference: " + error)
		return
	print("Clifton point cloud loaded and registered at %.7f, %.7f" % [PREVIEW_LATITUDE, PREVIEW_LONGITUDE])
	status_label.text = "Clifton point cloud loaded • trial height %.0f m ellipsoid" % PREVIEW_ALTITUDE
	if not xr_mode:
		# Start above and south-east of the bridge deck. The normal fly controls
		# remain active after disabling Cesium's globe-orbit controller.
		camera.set_process(false)
		camera.set_physics_process(false)
		camera.global_position = Vector3(100.0, 55.0, 145.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
		camera.far = 10000.0
		view_framed = true


func _on_point_cloud_failed(message: String) -> void:
	push_error("Clifton point cloud: " + message)
	status_label.text = "Point cloud failed: " + message


func setup_sun_controls() -> void:
	if camera == null:
		return
	sun_direction_controller.configure(sun, camera, left_controller, right_controller)


func bind_host_player() -> bool:
	if camera_path.is_empty():
		return false
	camera = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		push_error("WorldFrame camera_path does not resolve to a Camera3D: %s" % camera_path)
		return false
	xr_origin = get_node_or_null(xr_origin_path) as XROrigin3D
	left_controller = get_node_or_null(left_controller_path) as XRController3D
	right_controller = get_node_or_null(right_controller_path) as XRController3D
	xr_mode = camera is XRCamera3D
	return true


func add_north_marker() -> void:
	var marker := Label3D.new()
	marker.name = "TrueNorthMarker"
	marker.text = "NORTH"
	marker.position = Vector3(0.0, 350.0, -2500.0)
	marker.font_size = 32
	marker.outline_size = 6
	marker.pixel_size = 0.5
	marker.modulate = Color(1.0, 0.18, 0.12, 0.72)
	marker.outline_modulate = Color(0.08, 0.01, 0.01, 0.72)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = false
	marker.no_depth_test = false
	world_debug_root.add_child(marker)


func _on_building_tile_added(node: Node) -> void:
	if node is MeshInstance3D and buildings_material != null:
		# OSM Buildings geometry is useful even where façade imagery is absent.
		# Give every streamed tile the same inexpensive, sunlight-aware material.
		node.material_override = buildings_material


func use_crisp_imagery_filter(node: Node) -> void:
	if not node is MeshInstance3D or node.mesh == null:
		return
	for surface_index in range(node.mesh.get_surface_count()):
		var material: Material = node.mesh.surface_get_material(surface_index)
		if material is BaseMaterial3D:
			# Nearest texels retain the source imagery's character at close range;
			# mipmaps still suppress shimmer on oblique and horizon tiles.
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS


func _on_world_terrain_tile_added(node: Node) -> void:
	use_crisp_imagery_filter(node)
	if local_terrain_clip_enabled and node is MeshInstance3D:
		_apply_world_terrain_clip.call_deferred(node)


func _apply_world_terrain_clip(node: MeshInstance3D) -> void:
	if not is_instance_valid(node) or node.mesh == null:
		return
	var world_bounds := node.global_transform * node.get_aabb()
	var centre := world_bounds.get_center()
	var horizontal_diagonal := Vector2(world_bounds.size.x, world_bounds.size.z).length()
	if (
		LOCAL_TERRAIN_CLIP_RECT.has_point(Vector2(centre.x, centre.z))
		and horizontal_diagonal <= LOCAL_TERRAIN_CLIP_MAX_TILE_DIAGONAL
	):
		node.visible = false
		clipped_world_terrain_tiles.append(node)


func enforce_world_terrain_clip() -> void:
	# Cesium may update a tile's visibility during refinement. Reassert the local
	# exclusion after tile selection so hidden World Terrain never z-fights the
	# LiDAR surface. Remove retired leaf nodes from the small tracking array.
	for index in range(clipped_world_terrain_tiles.size() - 1, -1, -1):
		var node := clipped_world_terrain_tiles[index]
		if not is_instance_valid(node):
			clipped_world_terrain_tiles.remove_at(index)
		else:
			node.visible = false


func _on_local_terrain_tile_added(node: Node) -> void:
	if node is MeshInstance3D:
		# With an ion token the raster overlay supplies the material asynchronously.
		# Retain the sunlight-aware fallback only for tokenless/local-only use.
		if not local_terrain_uses_aerial_imagery:
			node.material_override = local_terrain_material
		local_terrain_ready = true


func setup_desktop_camera() -> void:
	camera = Camera3D.new()
	camera.name = "CesiumCamera"
	camera.set_script(load("res://addons/cesium_godot/scripts/georeference_camera_controller.gd"))
	camera.set("globe_node", globe)
	var desktop_tilesets: Array[Cesium3DTileset] = []
	if world_terrain_enabled:
		desktop_tilesets.append(tileset)
	if local_terrain_tileset != null:
		desktop_tilesets.append(local_terrain_tileset)
	if buildings_tileset != null:
		desktop_tilesets.append(buildings_tileset)
	camera.set("tilesets", desktop_tilesets)
	camera.set("move_speed", 40.0)
	camera.set("curr_pitch", 0.15)
	camera.near = 0.1
	camera.far = BATTLE_ROAD_FAR_PLANE
	camera.fov = 60.0
	camera.current = true
	local_player_root.add_child(camera)


func setup_xr_camera() -> void:
	var interface := XRServer.find_interface("OpenXR")
	if interface == null or (not interface.is_initialized() and not interface.initialize()):
		push_error("Steam Frame XR: OpenXR failed to initialize")
		status_label.text = "OpenXR failed to initialize; launch through SteamVR"
		return

	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin3D"
	# OpenXR tracking space stays in the local East-Up-South scene frame. Cesium
	# receives a separate ECEF transform for tile selection in _process().
	local_player_root.add_child(xr_origin)

	var xr_camera := XRCamera3D.new()
	xr_camera.name = "XRCamera3D"
	xr_camera.near = 0.1
	# Stay below the Steam Frame projection's failure threshold while allowing a
	# substantially wider landscape than the stock 4 km OpenXR range.
	xr_camera.far = 30000.0
	xr_camera.current = true
	xr_origin.add_child(xr_camera)
	camera = xr_camera

	for hand in ["left_hand", "right_hand"]:
		var controller := XRController3D.new()
		controller.name = "LeftController" if hand == "left_hand" else "RightController"
		controller.tracker = hand
		xr_origin.add_child(controller)
		if hand == "left_hand":
			left_controller = controller
		else:
			right_controller = controller

	get_viewport().use_xr = true
	# A light hardware resolve for distant rooflines; the façade shader handles
	# its own sub-pixel filtering so 4x MSAA is unnecessary on the mobile GPU.
	get_viewport().msaa_3d = Viewport.MSAA_2X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("Steam Frame XR: OpenXR initialized; left stick head-flight, right stick vertical flight plus 30-degree snap turn")


func _process(delta: float) -> void:
	if tileset == null or globe == null or camera == null:
		return
	world_frame.update_view_context({
		"frame_epoch": world_frame.frame_epoch,
		"camera_transform_render": camera.global_transform,
		"camera_transform_site": world_frame.render_to_site(camera.global_transform),
		"camera_fov_degrees": camera.fov,
		"camera_far_metres": camera.far,
		"viewport_size": get_viewport().get_visible_rect().size,
		"embodiment_world_scale": XRServer.world_scale,
	})
	# The stock desktop controller normally drives tile selection. Once a custom
	# dataset frames the view we disable that controller, so both that view and
	# XR must explicitly pass the current local East-Up-South camera to Cesium.
	if xr_mode or view_framed:
		# Tile selection consumes real ECEF direction vectors. The plugin's
		# get_tx_engine_to_ecef() only contains its fixed 90-degree rendering-axis
		# conversion, not this origin's EUS tangent basis.
		var camera_ecef_transform := local_to_ecef * camera.global_transform
		if world_terrain_enabled:
			tileset.update_tileset(camera_ecef_transform)
		if local_terrain_tileset != null:
			local_terrain_tileset.update_tileset(camera_ecef_transform)
		if buildings_tileset != null:
			buildings_tileset.update_tileset(camera_ecef_transform)
	if local_terrain_clip_enabled:
		enforce_world_terrain_clip()
	if not host_manages_locomotion:
		update_xr_locomotion(delta)
	update_survex_xr_interaction()
	var first_mesh: MeshInstance3D = null
	for child in tileset.get_children():
		if child is MeshInstance3D:
			first_mesh = child
			break
	# If a local LiDAR tileset is configured, do not let the hidden ion terrain
	# claim success first. This made server failures look like successful local
	# terrain loads and produced blank/highly incomplete diagnostic captures.
	var requested_terrain_ready := local_terrain_ready if local_terrain_tileset != null else first_mesh != null
	if requested_terrain_ready:
		status_label.text = "Tiles loaded • latitude %.5f, longitude %.5f, altitude %.0f m" % [
			globe.latitude, globe.longitude, globe.altitude
		]
		if not announced_first_tile:
			announced_first_tile = true
			print("Cesium preview: first terrain tile rendered successfully")
			if "--capture" in OS.get_cmdline_user_args():
				capture_started_msec = Time.get_ticks_msec()
			if "--bake-reference" in OS.get_cmdline_user_args():
				# The first rendered mesh is a coarse globe ancestor. Keep streaming
				# until Cesium replaces it with several visible leaves near the survey;
				# copying every loaded child would make hidden ancestors visible again.
				bake_started_msec = Time.get_ticks_msec()
			if using_world_terrain:
				# Continue streaming after the coarse globe tile so Cesium can refine
				# it into local terrain around the selected cartographic origin.
				status_label.text = "Terrain streaming • right-drag look • WASD + Q/E fly • Shift boost • +/- speed"
			elif not xr_mode and first_mesh != null and startup_survex_path.is_empty():
				frame_tile(first_mesh)
	if view_framed:
		update_fly_camera(delta)
	if bake_started_msec >= 0:
		bake_reference_when_ready()
	if capture_started_msec >= 0:
		if Time.get_ticks_msec() - capture_started_msec > 15000:
			get_viewport().get_texture().get_image().save_png("/tmp/godot-cesium-terrain.png")
			capture_started_msec = -1
			print("Saved diagnostic terrain screenshot")
			get_tree().quit()


func distance_from_origin_to_aabb(bounds: AABB) -> float:
	var end := bounds.end
	var closest := Vector3(
		clampf(0.0, bounds.position.x, end.x),
		clampf(0.0, bounds.position.y, end.y),
		clampf(0.0, bounds.position.z, end.z)
	)
	return closest.length()


func visible_reference_candidates() -> Array[MeshInstance3D]:
	var candidates: Array[MeshInstance3D] = []
	for child in tileset.get_children():
		# Cesium keeps replacement ancestors as hidden children. They overlap their
		# descendants and have origins hundreds of kilometres away, so only capture
		# the leaf set that actually forms the displayed surface.
		if (
			child is MeshInstance3D
			and child.mesh != null
			and child.visible
			and child.get_aabb().size.length() <= REFERENCE_MAX_TILE_DIAGONAL_METRES
		):
			candidates.append(child)
	candidates.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		var a_bounds := a.global_transform * a.get_aabb()
		var b_bounds := b.global_transform * b.get_aabb()
		return distance_from_origin_to_aabb(a_bounds) < distance_from_origin_to_aabb(b_bounds)
	)
	return candidates


func bake_reference_when_ready() -> void:
	var candidates := visible_reference_candidates()
	var elapsed := Time.get_ticks_msec() - bake_started_msec
	var smallest_diagonal := INF
	for candidate in candidates:
		smallest_diagonal = minf(smallest_diagonal, candidate.get_aabb().size.length())
	var refined_enough := (
		elapsed >= REFERENCE_MIN_STREAM_MSEC
		and candidates.size() >= REFERENCE_MIN_VISIBLE_TILES
		and smallest_diagonal <= REFERENCE_TARGET_TILE_DIAGONAL_METRES
	)
	var timed_out := elapsed >= REFERENCE_MAX_STREAM_MSEC
	var elapsed_second := elapsed / 1000
	if elapsed_second != bake_last_reported_second and elapsed_second % 5 == 0:
		bake_last_reported_second = elapsed_second
		print("Reference terrain streaming: %d visible leaves, finest diagonal %.0f m, %d s" % [
			candidates.size(), smallest_diagonal, elapsed_second
		])
	if not refined_enough and not timed_out:
		return
	if timed_out:
		print("Reference terrain reached its streaming time limit; saving the best visible leaf set")
	set_process(false)
	bake_started_msec = -1
	bake_cesium_reference_scene.call_deferred(candidates)


func bake_cesium_reference_scene(candidates: Array[MeshInstance3D]) -> void:
	if candidates.is_empty():
		push_error("No visible Cesium terrain leaf meshes were available to bake")
		get_tree().quit(1)
		return

	var output_root := Node3D.new()
	output_root.name = "CesiumTerrainLightingReference"
	var terrain_root := Node3D.new()
	terrain_root.name = "TerrainTiles"
	output_root.add_child(terrain_root)
	terrain_root.owner = output_root
	# Keep a representative transect of the coherent visible leaf set: six near
	# the survey, six spread through the range, and six at the horizon.
	var selected_indices: Dictionary = {}
	for index in range(mini(candidates.size(), 6)):
		selected_indices[index] = true
	for step in range(1, 7):
		selected_indices[roundi(float(candidates.size() - 1) * float(step) / 7.0)] = true
	for index in range(maxi(candidates.size() - 6, 0), candidates.size()):
		selected_indices[index] = true
	var selected: Array[MeshInstance3D] = []
	for index in selected_indices.keys():
		selected.append(candidates[int(index)])
	selected.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		var a_bounds := a.global_transform * a.get_aabb()
		var b_bounds := b.global_transform * b.get_aabb()
		return distance_from_origin_to_aabb(a_bounds) < distance_from_origin_to_aabb(b_bounds)
	)
	var tile_count := selected.size()
	for index in range(tile_count):
		var source := selected[index]
		var copy := MeshInstance3D.new()
		var world_bounds := source.global_transform * source.get_aabb()
		copy.name = "TerrainTile_%02d_%05dm" % [index, roundi(distance_from_origin_to_aabb(world_bounds))]
		copy.transform = source.global_transform
		copy.mesh = source.mesh.duplicate(true)
		use_crisp_imagery_filter(copy)
		if source.material_override != null:
			copy.material_override = source.material_override.duplicate(true)
		terrain_root.add_child(copy)
		copy.owner = output_root

	var environment_copy := WorldEnvironment.new()
	environment_copy.name = "WorldEnvironment"
	environment_copy.environment = world_environment.environment.duplicate(true)
	output_root.add_child(environment_copy)
	environment_copy.owner = output_root

	var sun_copy := DirectionalLight3D.new()
	sun_copy.name = "Sun"
	sun_copy.transform = sun.transform
	sun_copy.light_color = sun.light_color
	sun_copy.light_energy = sun.light_energy
	sun_copy.shadow_enabled = true
	output_root.add_child(sun_copy)
	sun_copy.owner = output_root

	var camera_copy := Camera3D.new()
	camera_copy.name = "Camera3D"
	camera_copy.transform = camera.global_transform
	camera_copy.current = true
	camera_copy.near = camera.near
	# Keep the horizon samples visible even if another optional layer adjusted
	# the live preview camera after reference streaming began.
	camera_copy.far = maxf(camera.far, 3000000.0)
	camera_copy.fov = camera.fov
	output_root.add_child(camera_copy)
	camera_copy.owner = output_root

	var output_directory := ProjectSettings.globalize_path("res://World/reference_tiles")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var packed := PackedScene.new()
	var pack_error := packed.pack(output_root)
	if pack_error != OK:
		push_error("Could not pack Cesium reference scene: %s" % error_string(pack_error))
		output_root.free()
		get_tree().quit(1)
		return
	var output_path := output_directory.path_join("cesium_terrain_reference.tscn")
	var save_error := ResourceSaver.save(packed, output_path, ResourceSaver.FLAG_BUNDLE_RESOURCES)
	output_root.free()
	if save_error != OK:
		push_error("Could not save Cesium reference scene: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	print("Saved %d Cesium terrain tiles for editor lighting work: %s" % [tile_count, output_path])
	get_tree().quit()


func update_xr_locomotion(delta: float) -> void:
	if not xr_mode or xr_origin == null or camera == null:
		return
	var move_stick := Vector2.ZERO
	var turn_stick := Vector2.ZERO
	if left_controller != null and left_controller.get_is_active():
		move_stick = left_controller.get_vector2("primary")
	if right_controller != null and right_controller.get_is_active():
		turn_stick = right_controller.get_vector2("primary")
	# Left grip deliberately turns the right stick into a temporary sun-angle
	# control. Suppress snap turning until the grip is released.
	if sun_direction_controller != null and sun_direction_controller.is_xr_adjusting():
		turn_stick = Vector2.ZERO
		xr_snap_turn_ready = true
	if move_stick.length() < 0.15:
		move_stick = Vector2.ZERO
	if turn_stick.length() < 0.15:
		turn_stick = Vector2.ZERO
	var vertical_axis := 0.0
	if absf(turn_stick.y) > XR_VERTICAL_DEAD_ZONE:
		vertical_axis = signf(turn_stick.y) * (
			(absf(turn_stick.y) - XR_VERTICAL_DEAD_ZONE) / (1.0 - XR_VERTICAL_DEAD_ZONE)
		)

	# Flight follows the complete headset direction, including pitch. This makes
	# the left stick sufficient for both horizontal and vertical travel.
	var head_forward := -camera.global_basis.z.normalized()
	var head_right := camera.global_basis.x.normalized()
	var motion := head_forward * move_stick.y + head_right * move_stick.x
	motion += Vector3.UP * vertical_axis
	if motion.length_squared() > 0.0:
		var speed_multiplier := 6.0 if (
			right_controller != null and right_controller.get_float("trigger") > 0.5
		) else 1.0
		xr_origin.global_position += motion.normalized() * xr_fly_speed * speed_multiplier * delta

	# One 30-degree turn per stick deflection is more comfortable than smooth
	# yaw in a flying scene. Return the stick near centre to arm the next turn.
	if absf(turn_stick.x) < 0.3:
		xr_snap_turn_ready = true
	elif xr_snap_turn_ready and absf(turn_stick.x) > 0.7:
		xr_snap_turn_ready = false
		var angle := deg_to_rad(-30.0 * signf(turn_stick.x))
		var head_position := camera.global_position
		var origin_offset := xr_origin.global_position - head_position
		xr_origin.rotate_y(angle)
		xr_origin.global_position = head_position + origin_offset.rotated(Vector3.UP, angle)


func update_survex_xr_interaction() -> void:
	if not xr_mode or survex_layer == null or right_controller == null or not right_controller.get_is_active():
		if survex_pointer != null:
			survex_pointer.visible = false
		return
	var ray_origin := right_controller.global_position
	var ray_direction := -right_controller.global_basis.z.normalized()
	var hit: Dictionary = survex_layer.pick_station(ray_origin, ray_direction)
	var pointer_end := ray_origin + ray_direction * 20.0
	if not hit.is_empty():
		pointer_end = hit.position
	set_survex_pointer(ray_origin, pointer_end)
	var grip_pressed := right_controller.get_float("grip") > 0.65
	if not grip_pressed:
		xr_station_select_ready = true
	elif xr_station_select_ready:
		xr_station_select_ready = false
		if not hit.is_empty():
			survex_layer.select_station(int(hit.index))
			right_controller.trigger_haptic_pulse("haptic", 60.0, 0.45, 0.08, 0.0)


func set_survex_pointer(from: Vector3, to: Vector3) -> void:
	if survex_pointer == null:
		return
	var length := from.distance_to(to)
	if length < 0.001:
		survex_pointer.visible = false
		return
	var box := survex_pointer.mesh as BoxMesh
	box.size.z = length
	survex_pointer.global_position = (from + to) * 0.5
	survex_pointer.look_at(to, Vector3.UP)
	survex_pointer.visible = true


func frame_tile(tile: MeshInstance3D) -> void:
	# The upstream camera controller correctly drives geospatial streaming but
	# does not automatically point at a newly loaded URL tileset. Once the first
	# tile exists, freeze that controller and frame the tile's real world bounds.
	camera.set_process(false)
	camera.set_physics_process(false)
	var bounds := tile.get_aabb()
	var target := tile.global_transform * bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 20.0)
	camera.global_position = target + Vector3(radius * 0.35, radius * 0.55, radius * 1.35)
	camera.look_at(target, Vector3.UP)
	camera.near = 0.1
	camera.far = radius * 10.0
	view_framed = true
	status_label.text = "Tiles loaded • right-drag look • WASD + Q/E fly • Shift boost • +/- speed"
	print("Framed tile at ", target, " from camera position ", camera.global_position)


func update_fly_camera(delta: float) -> void:
	var motion := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		motion -= camera.global_basis.z
	if Input.is_key_pressed(KEY_S):
		motion += camera.global_basis.z
	if Input.is_key_pressed(KEY_A):
		motion -= camera.global_basis.x
	if Input.is_key_pressed(KEY_D):
		motion += camera.global_basis.x
	if Input.is_key_pressed(KEY_Q):
		motion -= Vector3.UP
	if Input.is_key_pressed(KEY_E):
		motion += Vector3.UP
	if motion != Vector3.ZERO:
		# The combined Loser survey spans kilometres. Keep normal flight precise,
		# but make Shift a true traverse mode rather than a modest sprint.
		var speed_multiplier := 50.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		camera.global_position += motion.normalized() * fly_speed * speed_multiplier * delta

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.keycode in [KEY_PLUS, KEY_KP_ADD]:
		fly_speed *= 1.5
	elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		fly_speed = maxf(fly_speed / 1.5, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and survex_layer != null and camera != null:
		var ray_origin := camera.project_ray_origin(event.position)
		var hit: Dictionary = survex_layer.pick_station(ray_origin, camera.project_ray_normal(event.position))
		if not hit.is_empty():
			survex_layer.select_station(int(hit.index))
			get_viewport().set_input_as_handled()
			return
	if not view_framed:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera.rotate_y(-event.relative.x * 0.003)
		camera.rotate_object_local(Vector3.RIGHT, -event.relative.y * 0.003)
