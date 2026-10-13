class_name EptMetadata
extends RefCounted

var version := ""
var data_type := ""
var hierarchy_type := ""
var points := 0
var span := 0
var bounds := AABB()
var conforming_bounds := AABB()
var schema: Array = []
var point_stride := 0
var position_offsets := PackedInt32Array([-1, -1, -1])
var position_scales := Vector3.ONE
var position_origins := Vector3.ZERO
var color_offsets := PackedInt32Array([-1, -1, -1])
var srs: Dictionary = {}

func parse_json_text(text: String) -> String:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "ept.json is not a JSON object"
	return parse_dictionary(parsed)

func parse_dictionary(data: Dictionary) -> String:
	for key in ["bounds", "dataType", "hierarchyType", "schema", "span"]:
		if not data.has(key):
			return "ept.json is missing '%s'" % key
	if not _is_bounds(data.bounds):
		return "EPT bounds must contain six numbers"
	data_type = str(data.dataType).to_lower()
	if data_type != "binary":
		return "the trial EPT loader supports binary nodes only (got %s)" % data_type
	hierarchy_type = str(data.hierarchyType).to_lower()
	if hierarchy_type != "json":
		return "the trial EPT loader supports JSON hierarchy only"
	version = str(data.get("version", ""))
	points = int(data.get("points", 0))
	span = int(data.span)
	schema = data.schema
	srs = data.get("srs", {})
	bounds = _to_aabb(data.bounds)
	conforming_bounds = _to_aabb(data.get("boundsConforming", data.bounds))
	point_stride = 0
	position_offsets = PackedInt32Array([-1, -1, -1])
	color_offsets = PackedInt32Array([-1, -1, -1])
	for dimension in schema:
		if typeof(dimension) != TYPE_DICTIONARY:
			return "EPT schema entries must be objects"
		var name := str(dimension.get("name", ""))
		var size := int(dimension.get("size", 0))
		if size <= 0:
			return "EPT dimension %s has an invalid size" % name
		var position_index := ["X", "Y", "Z"].find(name)
		if position_index >= 0:
			if str(dimension.get("type", "")) != "signed" or size != 4:
				return "trial EPT positions must be signed int32"
			position_offsets[position_index] = point_stride
			position_scales[position_index] = float(dimension.get("scale", 1.0))
			position_origins[position_index] = float(dimension.get("offset", 0.0))
		var color_index := ["Red", "Green", "Blue"].find(name)
		if color_index >= 0:
			if str(dimension.get("type", "")) != "unsigned" or size != 2:
				return "trial EPT colors must be unsigned uint16"
			color_offsets[color_index] = point_stride
		point_stride += size
	if -1 in position_offsets:
		return "EPT schema must contain X, Y, and Z"
	return ""

func local_origin() -> Vector3:
	return bounds.get_center()

static func _is_bounds(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 6

static func _to_aabb(value: Array) -> AABB:
	var minimum := Vector3(float(value[0]), float(value[1]), float(value[2]))
	var maximum := Vector3(float(value[3]), float(value[4]), float(value[5]))
	return AABB(minimum, maximum - minimum)
