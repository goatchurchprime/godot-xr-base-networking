class_name SurvexLayer
extends Node3D

signal station_selected(station: Dictionary)

const SCHEMA := "tunnelxr-survex-1"
const PASSAGE_SHADER := preload("res://addons/survex/survex_passage_depth_lit.gdshader")
const CENTRELINE_SHADER := preload("res://addons/survex/survex_centreline_depth_lit.gdshader")
const DEPTH_SHADING := preload("res://addons/survex/cave_depthshading.tres")
const LIMESTONE_FLOOR_SHADER := preload("res://addons/survex/limestone_floor.gdshader")
const PLAN_GEOREF_PATH := "res://World/survey_data/204allupperB.georef.json"
const PLAN_TEXTURE := preload("res://World/survey_data/204allupperB_preview.png")
const PLAN_SHADER := preload("res://World/survey_data/georeferenced_plan_sheet.gdshader")

@export var station_radius := 0.16
@export var pick_radius := 0.35
@export var pick_cell_size := 5.0
@export var passages_visible := true
@export var stations_visible := true
@export var limestone_floor_visible := true
@export var georeferenced_plan_visible := true

var title := ""
var source_crs := ""
var stations: Array[Dictionary] = []
var legs: Array[Dictionary] = []
var tubes: Array = []
var selected_station := -1
var _source_origin := PackedFloat64Array()
var _station_positions := PackedVector3Array()
var _visible_station_indices := PackedInt32Array()
var _station_grid: Dictionary = {}
var _pick_stamps := PackedInt32Array()
var _pick_serial := 0
var _passage_material: ShaderMaterial
var _centreline_material: ShaderMaterial
var _selection_marker: MeshInstance3D
var _selection_label: Label3D


func load_file(path: String, cesium_georeference: Node) -> String:
	if not FileAccess.file_exists(path):
		return "Survex layer does not exist: " + path
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_data(parsed, cesium_georeference, path)


func load_local_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "Survex layer does not exist: " + path
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_local_data(parsed, path)


func load_data(parsed: Variant, cesium_georeference: Node, source_name := "Survex data") -> String:
	var validation_error := _validate_data(parsed, source_name)
	if not validation_error.is_empty():
		return validation_error
	var registration = parsed.get("registration", {})
	var registration_error := _apply_registration(registration, cesium_georeference)
	if not registration_error.is_empty():
		return registration_error
	_populate_data(parsed, source_name)
	return ""


func load_local_data(parsed: Variant, source_name := "Survex data") -> String:
	## Load survey coordinates directly into the parent WorldFrame.
	##
	## This is intentionally separate from load_data(): a local/offline world
	## must not need a Cesium object merely to construct the same cave geometry.
	var validation_error := _validate_data(parsed, source_name)
	if not validation_error.is_empty():
		return validation_error
	transform = Transform3D.IDENTITY
	_populate_data(parsed, source_name)
	return ""


func _validate_data(parsed: Variant, source_name: String) -> String:
	if typeof(parsed) != TYPE_DICTIONARY:
		return "Survex layer is not a JSON object: " + source_name
	if str(parsed.get("schema", "")) != SCHEMA:
		return "unsupported Survex layer schema in " + source_name
	return ""


func _populate_data(parsed: Dictionary, source_name: String) -> void:
	var registration: Dictionary = parsed.get("registration", {})
	title = str(parsed.get("title", source_name.get_file()))
	source_crs = str(parsed.get("source_crs", ""))
	var source_origin = registration.get("source_origin", [])
	if typeof(source_origin) == TYPE_ARRAY and source_origin.size() == 3:
		_source_origin = PackedFloat64Array([
			float(source_origin[0]), float(source_origin[1]), float(source_origin[2])
		])
	else:
		_source_origin = PackedFloat64Array()
	stations.assign(parsed.get("stations", []))
	legs.assign(parsed.get("legs", []))
	tubes = parsed.get("tubes", [])
	_build_geometry(float(parsed.get("altitude_origin", 0.0)))


func pick_station(ray_origin_global: Vector3, ray_direction_global: Vector3, max_distance := 500.0) -> Dictionary:
	if _station_positions.is_empty():
		return {}
	var inverse := global_transform.affine_inverse()
	var origin := inverse * ray_origin_global
	var direction := (inverse.basis * ray_direction_global).normalized()
	var closest_index := -1
	var closest_t := max_distance
	_pick_serial += 1
	if _pick_serial >= 2147483647:
		_pick_stamps.fill(0)
		_pick_serial = 1
	var sample_step := pick_cell_size * 0.5
	var sample_count := ceili(max_distance / sample_step)
	for sample_index in sample_count + 1:
		var sample_t := minf(sample_index * sample_step, max_distance)
		if sample_t > closest_t + pick_cell_size * 2.0:
			break
		var cell := _station_cell(origin + direction * sample_t)
		var cell_radius := maxi(1, ceili((pick_radius + sample_t * 0.003) / pick_cell_size))
		for x in range(cell.x - cell_radius, cell.x + cell_radius + 1):
			for y in range(cell.y - cell_radius, cell.y + cell_radius + 1):
				for z in range(cell.z - cell_radius, cell.z + cell_radius + 1):
					var bucket: PackedInt32Array = _station_grid.get(Vector3i(x, y, z), PackedInt32Array())
					for index in bucket:
						if _pick_stamps[index] == _pick_serial:
							continue
						_pick_stamps[index] = _pick_serial
						var offset := _station_positions[index] - origin
						var t := offset.dot(direction)
						if t < 0.0 or t > closest_t:
							continue
						var tolerance := pick_radius + t * 0.003
						if (offset - direction * t).length_squared() <= tolerance * tolerance:
							closest_index = index
							closest_t = t
	if closest_index < 0:
		return {}
	return {
		"index": closest_index,
		"distance": closest_t,
		"position": global_transform * _station_positions[closest_index],
		"station": stations[closest_index],
	}


func select_station(index: int) -> void:
	if index < 0 or index >= stations.size():
		selected_station = -1
		_selection_marker.visible = false
		_selection_label.visible = false
		_passage_material.set_shader_parameter("selection_enabled", false)
		return
	selected_station = index
	var position := _station_positions[index]
	_selection_marker.position = position
	_selection_marker.visible = true
	_selection_label.position = position + Vector3(0.0, station_radius * 2.5, 0.0)
	_selection_label.text = str(stations[index].get("name", "unnamed station"))
	_selection_label.visible = true
	_passage_material.set_shader_parameter("selection_position", position)
	_passage_material.set_shader_parameter("selection_enabled", true)
	station_selected.emit(stations[index])


func set_passages_visible(value: bool) -> void:
	passages_visible = value
	var node := get_node_or_null("Passages")
	if node != null:
		node.visible = value


func get_local_bounds() -> AABB:
	if _station_positions.is_empty():
		return AABB()
	var bounds := AABB(_station_positions[0], Vector3.ZERO)
	for index in range(1, _station_positions.size()):
		bounds = bounds.expand(_station_positions[index])
	return bounds


func get_focus_bounds(lower_percentile := 0.05, upper_percentile := 0.95) -> AABB:
	# Passage tubes are deliberately generated from a smaller, useful working
	# area than the full federated centreline. Prefer their extent for the
	# opening view so remote surface/control stations do not make the cave tiny.
	var passage_bounds := _get_passage_bounds()
	if passage_bounds.size.length_squared() > 0.0:
		return passage_bounds

	# Very large federated cave projects often contain remote boundary and
	# surface stations. Use robust bounds for the opening camera without hiding
	# or discarding any of those stations from the actual layer.
	if _station_positions.is_empty():
		return AABB()
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	xs.resize(_station_positions.size())
	ys.resize(_station_positions.size())
	zs.resize(_station_positions.size())
	for index in _station_positions.size():
		xs[index] = _station_positions[index].x
		ys[index] = _station_positions[index].y
		zs[index] = _station_positions[index].z
	xs.sort()
	ys.sort()
	zs.sort()
	var last := _station_positions.size() - 1
	var lower := clampi(int(floor(last * lower_percentile)), 0, last)
	var upper := clampi(int(ceil(last * upper_percentile)), lower, last)
	var minimum := Vector3(xs[lower], ys[lower], zs[lower])
	var maximum := Vector3(xs[upper], ys[upper], zs[upper])
	return AABB(minimum, maximum - minimum)


func _get_passage_bounds() -> AABB:
	var found := false
	var bounds := AABB()
	for tube in tubes:
		if typeof(tube) != TYPE_DICTIONARY:
			continue
		var cross_sections = tube.get("cross_sections", [])
		if typeof(cross_sections) != TYPE_ARRAY:
			continue
		for cross_section in cross_sections:
			if typeof(cross_section) != TYPE_DICTIONARY:
				continue
			var position_value = cross_section.get("position", [])
			if typeof(position_value) != TYPE_ARRAY or position_value.size() != 3:
				continue
			var position := _vec3(position_value)
			if found:
				bounds = bounds.expand(position)
			else:
				bounds = AABB(position, Vector3.ZERO)
				found = true
	return bounds


func _apply_registration(registration: Variant, cesium_georeference: Node) -> String:
	if typeof(registration) != TYPE_DICTIONARY:
		return "Survex registration is missing"
	var origin = registration.get("origin_ecef", [])
	var axes = registration.get("basis_ecef_from_local", [])
	if typeof(origin) != TYPE_ARRAY or origin.size() != 3:
		return "Survex registration origin_ecef must contain three numbers"
	if typeof(axes) != TYPE_ARRAY or axes.size() != 3:
		return "Survex registration basis_ecef_from_local must contain three axes"
	if cesium_georeference == null:
		return "Cesium georeference is null"
	for method in ["get_ecef_x", "get_ecef_y", "get_ecef_z"]:
		if not cesium_georeference.has_method(method):
			return "Cesium georeference does not expose its ECEF origin"
	var reference_x := float(cesium_georeference.call("get_ecef_x"))
	var reference_y := float(cesium_georeference.call("get_ecef_y"))
	var reference_z := float(cesium_georeference.call("get_ecef_z"))
	var up := Vector3(reference_x, reference_y, reference_z).normalized()
	var east := -up.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	if east.length_squared() < 0.5:
		return "cannot construct a local tangent frame at the ECEF pole"
	var south := east.cross(up).normalized()
	var ecef_to_scene := Basis(east, up, south).inverse()
	var source_basis := Basis(_vec3(axes[0]), _vec3(axes[1]), _vec3(axes[2]))
	var scale_factor := 1.0
	if cesium_georeference.has_method("get_scale_factor"):
		scale_factor = float(cesium_georeference.call("get_scale_factor"))
	global_transform = Transform3D(
		ecef_to_scene * source_basis * scale_factor,
		(ecef_to_scene * Vector3(
			float(origin[0]) - reference_x,
			float(origin[1]) - reference_y,
			float(origin[2]) - reference_z
		)) * scale_factor
	)
	return ""


func _build_geometry(altitude_origin: float) -> void:
	for child in get_children():
		child.queue_free()
	_station_positions.clear()
	_visible_station_indices.clear()
	_station_grid.clear()
	for station in stations:
		_station_positions.append(_vec3(station.get("position", [0.0, 0.0, 0.0])))
	_pick_stamps.resize(_station_positions.size())
	_pick_stamps.fill(0)
	for index in _station_positions.size():
		if not _station_has_visible_marker(stations[index]):
			continue
		_visible_station_indices.append(index)
		var cell := _station_cell(_station_positions[index])
		var bucket: PackedInt32Array = _station_grid.get(cell, PackedInt32Array())
		bucket.append(index)
		_station_grid[cell] = bucket

	_passage_material = ShaderMaterial.new()
	_passage_material.shader = PASSAGE_SHADER
	_passage_material.set_shader_parameter("altitude_origin", altitude_origin)
	_passage_material.set_shader_parameter("gray_colour", Color(0.035, 0.050, 0.065))
	_passage_material.set_shader_parameter("depthshading", DEPTH_SHADING)
	_centreline_material = ShaderMaterial.new()
	_centreline_material.shader = CENTRELINE_SHADER
	_centreline_material.set_shader_parameter("altitude_origin", altitude_origin)
	_centreline_material.set_shader_parameter("gray_colour", Color(0.035, 0.050, 0.065))
	_centreline_material.set_shader_parameter("depthshading", DEPTH_SHADING)
	print("Survex passage shader: ", PASSAGE_SHADER.resource_path)
	print("Survex centreline shader: ", CENTRELINE_SHADER.resource_path)

	var passages := MeshInstance3D.new()
	passages.name = "Passages"
	passages.mesh = _make_passage_mesh()
	passages.material_override = _passage_material
	passages.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	passages.visible = passages_visible
	add_child(passages)

	var centrelines := MeshInstance3D.new()
	centrelines.name = "Centrelines"
	centrelines.mesh = _make_centreline_mesh()
	centrelines.material_override = _centreline_material
	centrelines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(centrelines)

	var limestone_floor := _make_limestone_floor()
	limestone_floor.visible = limestone_floor_visible
	add_child(limestone_floor)

	var georeferenced_plan := _make_georeferenced_plan(altitude_origin)
	if georeferenced_plan != null:
		georeferenced_plan.visible = georeferenced_plan_visible
		add_child(georeferenced_plan)

	var station_instances := MultiMeshInstance3D.new()
	station_instances.name = "Stations"
	station_instances.multimesh = _make_station_multimesh()
	station_instances.visible = stations_visible
	add_child(station_instances)

	_selection_marker = MeshInstance3D.new()
	_selection_marker.name = "SelectedStation"
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = station_radius * 1.8
	marker_mesh.height = station_radius * 3.6
	marker_mesh.radial_segments = 12
	marker_mesh.rings = 6
	_selection_marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.0, 1.0, 1.0)
	marker_material.emission_enabled = true
	marker_material.emission = Color(0.0, 0.8, 1.0)
	marker_material.emission_energy_multiplier = 3.0
	_selection_marker.material_override = marker_material
	_selection_marker.visible = false
	add_child(_selection_marker)

	_selection_label = Label3D.new()
	_selection_label.name = "StationLabel"
	_selection_label.font_size = 48
	_selection_label.outline_size = 10
	_selection_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_selection_label.fixed_size = true
	_selection_label.no_depth_test = true
	_selection_label.visible = false
	add_child(_selection_label)


func _make_centreline_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for leg in legs:
		if "SURFACE" in leg.get("flags", []):
			continue
		var from := _vec3(leg.get("from", [0.0, 0.0, 0.0]))
		var to := _vec3(leg.get("to", [0.0, 0.0, 0.0]))
		var edge := to - from
		var edge_length := edge.length()
		if edge_length < 0.000001:
			continue
		var direction := edge / edge_length
		# Project world-up onto the plane perpendicular to this edge. The result
		# lies in the vertical plane containing the edge and points as far upward
		# as a perpendicular vector can. Thus horizontal edges receive UP normals.
		var normal := Vector3.UP - direction * Vector3.UP.dot(direction)
		if normal.length_squared() < 0.000001:
			# A perfectly vertical edge has no unique upward perpendicular. Choose a
			# stable horizontal normal while remaining perpendicular to the edge.
			var reference := Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			normal = reference - direction * reference.dot(direction)
		normal = normal.normalized()
		var horizontal := Vector2(to.x - from.x, to.z - from.z).length()
		var slope_light := horizontal / edge_length
		var encoded := Color(slope_light, 0.0, 0.0, 1.0)
		vertices.append_array(PackedVector3Array([from, to]))
		normals.append_array(PackedVector3Array([normal, normal]))
		colors.append_array(PackedColorArray([encoded, encoded]))
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _make_limestone_floor() -> MeshInstance3D:
	var bounds := get_local_bounds()
	var floor := MeshInstance3D.new()
	floor.name = "LowerLimestoneDatumGrid"
	floor.position = Vector3(bounds.get_center().x, bounds.position.y - 80.0, bounds.get_center().z)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(maxf(bounds.size.x + 1000.0, 2500.0), maxf(bounds.size.z + 1000.0, 2500.0))
	floor.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = LIMESTONE_FLOOR_SHADER
	floor.material_override = material
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return floor


func _make_georeferenced_plan(altitude_origin: float) -> MeshInstance3D:
	# This provisional drawing is UTM zone 33N. Only attach it to survey data
	# carrying the same coordinate system and a source-space registration.
	if source_crs != "EPSG:32633" or _source_origin.size() != 3:
		return null
	if not FileAccess.file_exists(PLAN_GEOREF_PATH):
		return null
	var georef = JSON.parse_string(FileAccess.get_file_as_string(PLAN_GEOREF_PATH))
	if typeof(georef) != TYPE_DICTIONARY or str(georef.get("crs", "")) != source_crs:
		return null

	var west := float(georef.get("west", 0.0))
	var east := float(georef.get("east", 0.0))
	var south := float(georef.get("south", 0.0))
	var north := float(georef.get("north", 0.0))
	var centre_east := (west + east) * 0.5
	var centre_north := (south + north) * 0.5
	var drawing_altitude := float(georef.get("drawing_altitude_metres", altitude_origin))

	var plan := MeshInstance3D.new()
	plan.name = "GeoreferencedPlan_204allupperB"
	plan.position = Vector3(
		centre_east - _source_origin[0],
		drawing_altitude - _source_origin[2],
		_source_origin[1] - centre_north
	)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(east - west, north - south)
	plan.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = PLAN_SHADER
	material.set_shader_parameter("plan_texture", PLAN_TEXTURE)
	plan.material_override = material
	plan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return plan


func _make_passage_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_geometry := false
	for tube_value in tubes:
		if typeof(tube_value) != TYPE_ARRAY or tube_value.size() < 2:
			continue
		has_geometry = true
		var sections: Array[PackedVector3Array] = []
		var last_right := Vector3.RIGHT
		for index in tube_value.size():
			var section: Dictionary = tube_value[index]
			var point := _vec3(section.get("position", [0.0, 0.0, 0.0]))
			var direction: Vector3
			if index == 0:
				direction = _vec3(tube_value[1].position) - point
			elif index == tube_value.size() - 1:
				direction = point - _vec3(tube_value[index - 1].position)
			else:
				var before := (point - _vec3(tube_value[index - 1].position)).normalized()
				var after := (_vec3(tube_value[index + 1].position) - point).normalized()
				direction = before + after
			var right := direction.cross(Vector3.UP)
			if right.length_squared() < 0.000001:
				right = last_right
			else:
				right = right.normalized()
				last_right = right
			var left_distance := absf(float(section.get("left", 0.0)))
			var right_distance := absf(float(section.get("right", 0.0)))
			var up_distance := absf(float(section.get("up", 0.0)))
			var down_distance := absf(float(section.get("down", 0.0)))
			sections.append(PackedVector3Array([
				point - right * left_distance + Vector3.UP * up_distance,
				point + right * right_distance + Vector3.UP * up_distance,
				point + right * right_distance - Vector3.UP * down_distance,
				point - right * left_distance - Vector3.UP * down_distance,
			]))
		_add_quad(surface, sections[0][3], sections[0][2], sections[0][1], sections[0][0])
		for index in range(1, sections.size()):
			for side in 4:
				var next_side := (side + 1) % 4
				_add_quad(surface, sections[index - 1][side], sections[index - 1][next_side], sections[index][next_side], sections[index][side])
		var last := sections[-1]
		_add_quad(surface, last[0], last[1], last[2], last[3])
	if not has_geometry:
		return ArrayMesh.new()
	# Each triangle receives its geometric normal explicitly in _add_triangle().
	# Do not rely on generate_normals(): editor scenes embed this ArrayMesh, and
	# an older generated scene silently ended up with no ARRAY_NORMAL channel.
	# Indexing can merge coplanar vertices, but vertices at a hard LRUD edge have
	# different normals and therefore remain separate.
	surface.index()
	return surface.commit()


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000000000001:
		return
	normal = normal.normalized()
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)


func _make_station_multimesh() -> MultiMesh:
	# A billboard is two triangles per station; the previous low-poly spheres
	# became several million triangles on the 90k-station Loser dataset.
	var marker := QuadMesh.new()
	marker.size = Vector2(station_radius * 2.0, station_radius * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.82, 0.16)
	material.emission_enabled = true
	material.emission = Color(0.45, 0.20, 0.01)
	material.emission_energy_multiplier = 1.5
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = marker
	multimesh.instance_count = _visible_station_indices.size()
	for instance_index in _visible_station_indices.size():
		var station_index := _visible_station_indices[instance_index]
		multimesh.set_instance_transform(instance_index, Transform3D(Basis.IDENTITY, _station_positions[station_index]))
	return multimesh


static func _station_has_visible_marker(station: Dictionary) -> bool:
	var flags: Array = station.get("flags", [])
	# Survex represents splay endpoints as anonymous stations. Keep their SPLAY
	# legs in the centreline mesh, but omit the endpoint billboards and picking
	# targets. Surface stations are similarly unhelpful without surface legs.
	return "ANON" not in flags and "SURFACE" not in flags


func _station_cell(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / pick_cell_size),
		floori(position.y / pick_cell_size),
		floori(position.z / pick_cell_size)
	)


static func _vec3(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
