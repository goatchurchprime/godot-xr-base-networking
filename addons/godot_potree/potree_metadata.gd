class_name PotreeMetadata
extends RefCounted

var version := ""
var encoding := ""
var name := ""
var description := ""
var projection := ""
var points := 0
var spacing := 0.0
var scale := Vector3.ONE
var offset := Vector3.ZERO
var bounds := AABB()
var hierarchy_first_chunk_size := 0
var point_stride := 0
var position_offset := -1
var color_offset := -1
var color_size := 0
var attributes: Array = []
var density_uri := ""
var density_grid_size := 0

func parse_json_text(text: String) -> String:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "metadata is not a JSON object"
	return parse_dictionary(parsed)

func parse_dictionary(data: Dictionary) -> String:
	for key in ["boundingBox", "scale", "offset", "spacing", "hierarchy", "attributes"]:
		if not data.has(key):
			return "metadata is missing '%s'" % key
	if typeof(data.boundingBox) != TYPE_DICTIONARY or not data.boundingBox.has("min") or not data.boundingBox.has("max"):
		return "metadata.boundingBox must contain min and max"
	if not _is_vec3_array(data.scale) or not _is_vec3_array(data.offset):
		return "metadata scale and offset must contain three numbers"
	if not _is_vec3_array(data.boundingBox.min) or not _is_vec3_array(data.boundingBox.max):
		return "metadata bounding box values must contain three numbers"
	if typeof(data.hierarchy) != TYPE_DICTIONARY or not data.hierarchy.has("firstChunkSize"):
		return "metadata.hierarchy.firstChunkSize is missing"
	if typeof(data.attributes) != TYPE_ARRAY:
		return "metadata.attributes must be an array"

	version = str(data.get("version", ""))
	encoding = str(data.get("encoding", "DEFAULT")).to_upper()
	if encoding != "DEFAULT":
		return "only Potree DEFAULT encoding is currently supported (got %s)" % encoding
	name = str(data.get("name", ""))
	description = str(data.get("description", ""))
	projection = str(data.get("projection", ""))
	points = int(data.get("points", 0))
	spacing = float(data.spacing)
	scale = _to_vec3(data.scale)
	offset = _to_vec3(data.offset)
	var minimum := _to_vec3(data.boundingBox.min)
	var maximum := _to_vec3(data.boundingBox.max)
	bounds = AABB(minimum, maximum - minimum)
	hierarchy_first_chunk_size = int(data.hierarchy.firstChunkSize)
	attributes = data.attributes
	var extensions = data.get("extensions", {})
	if typeof(extensions) == TYPE_DICTIONARY and extensions.has("GODOT_node_density"):
		var density_extension = extensions.GODOT_node_density
		if typeof(density_extension) == TYPE_DICTIONARY:
			if int(density_extension.get("recordSize", 0)) == 4 and str(density_extension.get("alignment", "")) == "hierarchy-record":
				density_uri = str(density_extension.get("uri", ""))
				density_grid_size = int(density_extension.get("gridSize", 0))

	point_stride = 0
	position_offset = -1
	color_offset = -1
	color_size = 0
	for attribute in attributes:
		if typeof(attribute) != TYPE_DICTIONARY or not attribute.has("name") or not attribute.has("size"):
			return "every point attribute must have a name and size"
		var attribute_name := str(attribute.name).to_lower()
		var attribute_size := int(attribute.size)
		if attribute_name in ["position", "position_cartesian"]:
			position_offset = point_stride
			if attribute_size != 12:
				return "position attributes must contain three 32-bit values"
		elif attribute_name in ["rgb", "rgba"]:
			color_offset = point_stride
			color_size = attribute_size
		point_stride += attribute_size
	if position_offset < 0:
		return "metadata does not contain a position attribute"
	if hierarchy_first_chunk_size <= 0 or hierarchy_first_chunk_size % 22 != 0:
		return "hierarchy firstChunkSize must be a positive multiple of 22"
	if point_stride <= 0:
		return "point stride is zero"
	return ""

func local_origin() -> Vector3:
	return bounds.get_center()

static func _is_vec3_array(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 3

static func _to_vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
