class_name EptPointCloud
extends Node3D

signal loaded(metadata: EptMetadata)
signal load_failed(message: String)

@export var ept_url := ""
@export var auto_load := true
@export_range(1.0, 16.0, 0.25) var point_size := 2.0
@export var circular_points := true

var metadata: EptMetadata
var root_point_count := 0
var _reader: PotreeRangeReader
var _data_source: Node
var _decoder := EptPointDecoder.new()

func _ready() -> void:
	_reader = PotreeRangeReader.new()
	add_child(_reader)
	_data_source = _reader
	if auto_load and not ept_url.is_empty():
		load_ept.call_deferred(ept_url)

func set_data_source(data_source: Node) -> void:
	if data_source != null and data_source.has_method("read"):
		_data_source = data_source

func load_ept(source: String) -> void:
	ept_url = source
	var metadata_response: Dictionary = await _data_source.read(source)
	if not metadata_response.error.is_empty():
		_fail(metadata_response.error)
		return
	metadata = EptMetadata.new()
	var parse_error := metadata.parse_json_text(metadata_response.data.get_string_from_utf8())
	if not parse_error.is_empty():
		_fail(parse_error)
		return
	var base_url := source.get_base_dir()
	var hierarchy_response: Dictionary = await _data_source.read(base_url.path_join("ept-hierarchy/0-0-0-0.json"))
	if not hierarchy_response.error.is_empty():
		_fail(hierarchy_response.error)
		return
	var hierarchy = JSON.parse_string(hierarchy_response.data.get_string_from_utf8())
	if typeof(hierarchy) != TYPE_DICTIONARY or not hierarchy.has("0-0-0-0"):
		_fail("EPT root hierarchy entry is missing")
		return
	root_point_count = int(hierarchy["0-0-0-0"])
	if root_point_count <= 0:
		_fail("EPT root hierarchy is empty or stored in a hierarchy subtree")
		return
	var data_response: Dictionary = await _data_source.read(base_url.path_join("ept-data/0-0-0-0.bin"))
	if not data_response.error.is_empty():
		_fail(data_response.error)
		return
	var thread := Thread.new()
	var start_error := thread.start(_decoder.decode.bind(data_response.data, metadata, root_point_count))
	if start_error != OK:
		_fail("cannot start EPT decoder thread: %s" % error_string(start_error))
		return
	while thread.is_alive():
		await get_tree().process_frame
	var decoded: Dictionary = thread.wait_to_finish()
	if not decoded.error.is_empty():
		_fail(decoded.error)
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = decoded.positions
	arrays[Mesh.ARRAY_COLOR] = decoded.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var material := ShaderMaterial.new()
	material.shader = preload("res://addons/godot_potree/point_cloud.gdshader")
	material.set_shader_parameter("point_size", point_size)
	material.set_shader_parameter("circular_points", circular_points)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(metadata.bounds.position - metadata.local_origin(), metadata.bounds.size)
	add_child(instance)
	loaded.emit(metadata)

func apply_cesium_georeference(cesium_georeference: Node, sidecar_source := "") -> String:
	var source := sidecar_source
	if source.is_empty():
		source = ept_url.get_base_dir().path_join("georeference.json")
	var response: Dictionary = await _data_source.read(source)
	if not response.error.is_empty():
		return response.error
	var georeference := PotreeGeoreference.new()
	var error := georeference.parse_json_text(response.data.get_string_from_utf8())
	if error.is_empty():
		error = georeference.apply_to_cesium(self, cesium_georeference)
	return error

func _fail(message: String) -> void:
	push_error("EptPointCloud: " + message)
	load_failed.emit(message)
