class_name PotreePointCloud
extends Node3D

signal load_started(source: String)
signal loaded(metadata: PotreeMetadata)
signal load_failed(message: String)
signal georeference_loaded(georeference: PotreeGeoreference)
signal streaming_stats_changed(visible_points: int, loaded_points: int, loaded_nodes: int)

enum State { EMPTY, LOADING, READY, FAILED }

@export var metadata_url := ""
@export var auto_load := true
@export var camera_path: NodePath
@export_range(1000, 10000000, 1000) var point_budget := 500000
@export_range(1000, 20000000, 1000) var cache_point_budget := 1000000
@export_range(0.25, 32.0, 0.25) var minimum_node_pixel_spacing := 2.0
@export_range(1.0, 16.0, 0.25) var point_size := 2.0:
	set(value):
		point_size = value
		_set_all_material_parameter("point_size", point_size)
@export var adaptive_point_size := true:
	set(value):
		adaptive_point_size = value
		_set_all_material_parameter("adaptive_point_size", adaptive_point_size)
@export_range(1.0, 1000.0, 1.0) var point_size_factor := 200.0:
	set(value):
		point_size_factor = value
		_set_all_material_parameter("point_size_factor", point_size_factor)
@export_range(1.01, 2.0, 0.01) var point_spacing_divisor := 1.55
@export_range(1.0, 256.0, 1.0) var maximum_point_size := 64.0:
	set(value):
		maximum_point_size = value
		_set_all_material_parameter("maximum_point_size", maximum_point_size)
@export var hierarchy_handoff := true
@export var circular_points := false:
	set(value):
		circular_points = value
		_set_all_material_parameter("circular_points", circular_points)
@export var near_fragmentation := true:
	set(value):
		near_fragmentation = value
		_set_all_material_parameter("near_fragmentation", near_fragmentation)
@export_range(0.05, 5.0, 0.05) var near_fragment_distance := 0.8:
	set(value):
		near_fragment_distance = value
		_set_all_material_parameter("near_fragment_distance", near_fragment_distance)
@export var distance_shading := true:
	set(value):
		distance_shading = value
		_set_all_material_parameter("distance_shading", distance_shading)
@export var distance_close_color := Color.RED:
	set(value):
		distance_close_color = value
		_set_all_material_parameter("distance_close_color", distance_close_color)
@export var distance_far_color := Color.BLUE:
	set(value):
		distance_far_color = value
		_set_all_material_parameter("distance_far_color", distance_far_color)
@export_range(0.0, 1.0, 0.01) var distance_color_mix := 0.5:
	set(value):
		distance_color_mix = value
		_set_all_material_parameter("distance_color_mix", distance_color_mix)
@export_range(0.1, 10000.0, 0.1, "or_greater") var distance_far := 30.0:
	set(value):
		distance_far = value
		_set_all_material_parameter("distance_far", distance_far)
@export_range(0.1, 10000.0, 0.1, "or_greater") var distance_taper := 20.0:
	set(value):
		distance_taper = value
		_set_all_material_parameter("distance_taper", distance_taper)
@export_range(0.05, 2.0, 0.05) var update_interval := 0.25

var state := State.EMPTY
var metadata: PotreeMetadata
var root: PotreeOctreeNode
var visible_point_count := 0
var loaded_point_count := 0

var _reader: PotreeRangeReader
var _data_source: Node
var _hierarchy := PotreeHierarchy.new()
var _decoder := PotreePointDecoder.new()
var _native_decoder: Object
var _material: ShaderMaterial
var _hierarchy_url := ""
var _octree_url := ""
var _density_url := ""
var _density_available = null
var _update_elapsed := 0.0
var _streaming := false
var _generation := 0
var _frame_counter := 0

func _ready() -> void:
	_reader = PotreeRangeReader.new()
	_reader.name = "RangeReader"
	add_child(_reader)
	_data_source = _reader
	if ClassDB.class_exists("PotreeNativeDecoder"):
		_native_decoder = ClassDB.instantiate("PotreeNativeDecoder")
	_material = ShaderMaterial.new()
	_material.shader = preload("res://addons/godot_potree/point_cloud.gdshader")
	_material.set_shader_parameter("point_size", point_size)
	_material.set_shader_parameter("adaptive_point_size", adaptive_point_size)
	_material.set_shader_parameter("point_size_factor", point_size_factor)
	_material.set_shader_parameter("maximum_point_size", maximum_point_size)
	_material.set_shader_parameter("circular_points", circular_points)
	_material.set_shader_parameter("near_fragmentation", near_fragmentation)
	_material.set_shader_parameter("near_fragment_distance", near_fragment_distance)
	_material.set_shader_parameter("distance_shading", distance_shading)
	_material.set_shader_parameter("distance_close_color", distance_close_color)
	_material.set_shader_parameter("distance_far_color", distance_far_color)
	_material.set_shader_parameter("distance_color_mix", distance_color_mix)
	_material.set_shader_parameter("distance_far", distance_far)
	_material.set_shader_parameter("distance_taper", distance_taper)
	if auto_load and not metadata_url.is_empty():
		load_cloud.call_deferred(metadata_url)

func _process(delta: float) -> void:
	if state != State.READY or _streaming:
		return
	_update_elapsed += delta
	if _update_elapsed >= update_interval:
		_update_elapsed = 0.0
		_update_streaming()

func load_cloud(source: String) -> void:
	_generation += 1
	var generation := _generation
	clear()
	metadata_url = source
	state = State.LOADING
	load_started.emit(source)
	var response: Dictionary = await _data_source.read(source)
	if generation != _generation:
		return
	if not response.error.is_empty():
		_fail(response.error)
		return
	var parsed_metadata := PotreeMetadata.new()
	var parse_error := parsed_metadata.parse_json_text(response.data.get_string_from_utf8())
	if not parse_error.is_empty():
		_fail("invalid Potree metadata: " + parse_error)
		return
	metadata = parsed_metadata
	var base_url := source.get_base_dir()
	_hierarchy_url = base_url.path_join("hierarchy.bin")
	_octree_url = base_url.path_join("octree.bin")
	_density_url = base_url.path_join(metadata.density_uri) if not metadata.density_uri.is_empty() else ""
	_density_available = not _density_url.is_empty()
	root = PotreeOctreeNode.new()
	root.bounds = metadata.bounds
	root.spacing = metadata.spacing
	root.hierarchy_byte_offset = 0
	root.hierarchy_byte_size = metadata.hierarchy_first_chunk_size
	if not await _load_hierarchy(root, generation):
		return
	if not await _load_node_points(root, generation):
		return
	state = State.READY
	loaded.emit(metadata)
	_update_streaming()

func clear() -> void:
	state = State.EMPTY
	metadata = null
	root = null
	visible_point_count = 0
	loaded_point_count = 0
	_streaming = false
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()

func set_camera(camera: Camera3D) -> void:
	camera_path = get_path_to(camera) if camera != null else NodePath()

func set_data_source(data_source: Node) -> void:
	if data_source == null or not data_source.has_method("read"):
		push_error("Potree data sources must implement read(source, byte_offset, byte_size)")
		return
	_data_source = data_source

func get_data_origin() -> Vector3:
	return metadata.local_origin() if metadata != null else Vector3.ZERO

func _set_all_material_parameter(parameter: StringName, value: Variant) -> void:
	if _material != null:
		_material.set_shader_parameter(parameter, value)
	if root == null:
		return
	for node in _walk_nodes():
		if node.mesh_instance != null:
			var material := node.mesh_instance.mesh.surface_get_material(0) as ShaderMaterial
			if material != null:
				material.set_shader_parameter(parameter, value)

func apply_cesium_georeference(cesium_georeference: Node, sidecar_source := "") -> String:
	if metadata == null:
		return "load the point cloud before applying its georeference"
	var source := sidecar_source
	if source.is_empty():
		source = metadata_url.get_base_dir().path_join("georeference.json")
	var response: Dictionary = await _data_source.read(source)
	if not response.error.is_empty():
		return response.error
	var georeference := PotreeGeoreference.new()
	var parse_error := georeference.parse_json_text(response.data.get_string_from_utf8())
	if not parse_error.is_empty():
		return parse_error
	var apply_error := georeference.apply_to_cesium(self, cesium_georeference)
	if apply_error.is_empty():
		georeference_loaded.emit(georeference)
	return apply_error

func _load_hierarchy(node: PotreeOctreeNode, generation: int) -> bool:
	if node.hierarchy_loaded:
		return true
	var response: Dictionary = await _data_source.read(_hierarchy_url, node.hierarchy_byte_offset, node.hierarchy_byte_size)
	if generation != _generation:
		return false
	if not response.error.is_empty():
		_fail(response.error)
		return false
	var density_data := PackedByteArray()
	if _density_available != false:
		var density_offset := int(node.hierarchy_byte_offset / PotreeHierarchy.RECORD_SIZE) * 4
		var density_size := int(node.hierarchy_byte_size / PotreeHierarchy.RECORD_SIZE) * 4
		var density_response: Dictionary = await _data_source.read(_density_url, density_offset, density_size)
		if density_response.error.is_empty():
			density_data = density_response.data
			_density_available = true
		else:
			_density_available = false
	var parse_error := _hierarchy.parse_chunk(response.data, node, node.hierarchy_byte_offset, density_data)
	if not parse_error.is_empty():
		_fail("invalid Potree hierarchy: " + parse_error)
		return false
	return true

func _load_node_points(node: PotreeOctreeNode, generation: int) -> bool:
	if node.mesh_instance != null:
		return true
	if node.loading or node.byte_size <= 0 or node.num_points <= 0:
		return false
	node.loading = true
	var response: Dictionary = await _data_source.read(_octree_url, node.byte_offset, node.byte_size)
	node.loading = false
	if generation != _generation:
		return false
	if not response.error.is_empty():
		_fail(response.error)
		return false
	var decoded: Dictionary
	if _native_decoder != null:
		var decode_thread := Thread.new()
		var start_error := decode_thread.start(Callable(_native_decoder, "decode_points").bind(
			response.data,
			metadata.point_stride,
			metadata.position_offset,
			metadata.color_offset,
			metadata.color_size,
			node.num_points,
			metadata.scale,
			metadata.offset,
			metadata.local_origin(),
			node.bounds.position,
			node.bounds.size,
			node.density <= 0.0
		))
		if start_error != OK:
			_fail("cannot start decoder thread for node %s: %s" % [node.node_name, error_string(start_error)])
			return false
		while decode_thread.is_alive():
			await get_tree().process_frame
		decoded = decode_thread.wait_to_finish()
		if decoded.is_empty():
			_fail("cannot decode node %s: %s" % [node.node_name, _native_decoder.call("get_last_error")])
			return false
	else:
		var decode_thread := Thread.new()
		var start_error := decode_thread.start(_decoder.decode.bind(response.data, metadata, node.num_points, node.bounds, node.density <= 0.0))
		if start_error != OK:
			_fail("cannot start decoder thread for node %s: %s" % [node.node_name, error_string(start_error)])
			return false
		while decode_thread.is_alive():
			await get_tree().process_frame
		decoded = decode_thread.wait_to_finish()
		if not decoded.error.is_empty():
			_fail("cannot decode node %s: %s" % [node.node_name, decoded.error])
			return false
	if node.density <= 0.0:
		node.density = float(decoded.density)
	_inherit_parent_points(node, decoded)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = decoded.positions
	arrays[Mesh.ARRAY_COLOR] = decoded.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var node_material := _material.duplicate() as ShaderMaterial
	# TunnelVR used 1.55 rather than the octree's geometric factor of 2.0;
	# it better represents the visible Poisson sample-spacing change per level.
	var render_spacing := metadata.spacing / pow(point_spacing_divisor, node.depth)
	node_material.set_shader_parameter("node_spacing", render_spacing)
	node_material.set_shader_parameter("node_center", node.bounds.get_center() - metadata.local_origin())
	node_material.set_shader_parameter("visible_child_mask", node.visible_child_mask)
	mesh.surface_set_material(0, node_material)
	var instance := MeshInstance3D.new()
	instance.name = "PotreeNode_%s" % node.node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var local_bounds := node.bounds
	local_bounds.position -= metadata.local_origin()
	instance.custom_aabb = local_bounds
	add_child(instance)
	node.mesh_instance = instance
	node.render_point_count = decoded.positions.size()
	loaded_point_count += node.render_point_count
	return true

func _inherit_parent_points(node: PotreeOctreeNode, decoded: Dictionary) -> void:
	node.carried_point_count = 0
	var parent := node.parent_node()
	if not hierarchy_handoff or parent == null or parent.mesh_instance == null:
		return
	var parent_arrays := parent.mesh_instance.mesh.surface_get_arrays(0)
	var parent_positions: PackedVector3Array = parent_arrays[Mesh.ARRAY_VERTEX]
	var parent_colors: PackedColorArray = parent_arrays[Mesh.ARRAY_COLOR]
	var positions: PackedVector3Array = decoded.positions
	var colors: PackedColorArray = decoded.colors
	var inherited_positions := PackedVector3Array()
	var inherited_colors := PackedColorArray()
	var parent_center := parent.bounds.get_center() - metadata.local_origin()
	for index in range(parent_positions.size()):
		var position := parent_positions[index]
		var octant := (4 if position.x > parent_center.x else 0) \
			+ (2 if position.y > parent_center.y else 0) \
			+ (1 if position.z > parent_center.z else 0)
		if octant == node.child_index:
			inherited_positions.append(position)
			inherited_colors.append(parent_colors[index])
	var original_size := positions.size()
	positions.resize(original_size + inherited_positions.size())
	colors.resize(original_size + inherited_colors.size())
	for inherited_index in range(inherited_positions.size()):
		positions[original_size + inherited_index] = inherited_positions[inherited_index]
		colors[original_size + inherited_index] = inherited_colors[inherited_index]
	node.carried_point_count = inherited_positions.size()
	decoded.positions = positions
	decoded.colors = colors

func _update_streaming() -> void:
	if _streaming or root == null:
		return
	_streaming = true
	_frame_counter += 1
	var camera := _get_camera()
	if camera == null:
		if root.mesh_instance != null:
			root.mesh_instance.visible = true
			visible_point_count = root.num_points
		_streaming = false
		return
	var desired: Dictionary = {}
	var queue: Array[PotreeOctreeNode] = [root]
	var selected_points := 0
	var proxy_to_expand: PotreeOctreeNode
	while not queue.is_empty():
		var node := queue.pop_front()
		if selected_points + node.num_points > point_budget and node != root:
			continue
		desired[node] = true
		selected_points += node.num_points
		node.last_used_frame = _frame_counter
		if _projected_spacing(node, camera) >= minimum_node_pixel_spacing:
			if node.is_proxy():
				if proxy_to_expand == null:
					proxy_to_expand = node
			else:
				for child in node.children:
					queue.append(child)
	if proxy_to_expand != null:
		await _load_hierarchy(proxy_to_expand, _generation)
	var load_candidate: PotreeOctreeNode
	visible_point_count = 0
	var loaded_nodes := 0
	for node in _walk_nodes():
		if node.mesh_instance != null:
			loaded_nodes += 1
			var should_show := desired.has(node)
			node.mesh_instance.visible = should_show
			if should_show:
				visible_point_count += node.num_points
		elif desired.has(node) and not node.is_proxy() and load_candidate == null:
			load_candidate = node
	if load_candidate != null:
		await _load_node_points(load_candidate, _generation)
	_evict_cache(desired)
	_update_handoff_masks()
	streaming_stats_changed.emit(visible_point_count, loaded_point_count, loaded_nodes)
	_streaming = false

func _update_handoff_masks() -> void:
	for node in _walk_nodes():
		var mask := 0
		if hierarchy_handoff:
			for child in node.children:
				if child.mesh_instance != null and child.mesh_instance.visible:
					mask |= 1 << child.child_index
		node.visible_child_mask = mask
		if node.mesh_instance != null:
			var material := node.mesh_instance.mesh.surface_get_material(0) as ShaderMaterial
			if material != null:
				material.set_shader_parameter("visible_child_mask", mask)

func _projected_spacing(node: PotreeOctreeNode, camera: Camera3D) -> float:
	var local_center := node.bounds.get_center() - metadata.local_origin()
	var world_center := to_global(local_center)
	var distance := max(camera.global_position.distance_to(world_center), 0.01)
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var pixels_per_meter: float = viewport_height / (2.0 * tan(deg_to_rad(camera.fov) * 0.5) * distance)
	return node.spacing * global_basis.get_scale().length() / sqrt(3.0) * pixels_per_meter

func _get_camera() -> Camera3D:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as Camera3D
	return get_viewport().get_camera_3d()

func _walk_nodes() -> Array[PotreeOctreeNode]:
	var result: Array[PotreeOctreeNode] = []
	if root == null:
		return result
	var queue: Array[PotreeOctreeNode] = [root]
	while not queue.is_empty():
		var node := queue.pop_front()
		result.append(node)
		queue.append_array(node.children)
	return result

func _evict_cache(desired: Dictionary) -> void:
	if loaded_point_count <= cache_point_budget:
		return
	var candidates: Array[PotreeOctreeNode] = []
	for node in _walk_nodes():
		if node != root and node.mesh_instance != null and not desired.has(node):
			candidates.append(node)
	candidates.sort_custom(func(a: PotreeOctreeNode, b: PotreeOctreeNode) -> bool: return a.last_used_frame < b.last_used_frame)
	for node in candidates:
		if loaded_point_count <= cache_point_budget:
			break
		loaded_point_count -= node.render_point_count
		node.mesh_instance.queue_free()
		node.mesh_instance = null
		node.render_point_count = 0
		node.carried_point_count = 0

func _fail(message: String) -> void:
	state = State.FAILED
	_streaming = false
	push_error("PotreePointCloud: " + message)
	load_failed.emit(message)
