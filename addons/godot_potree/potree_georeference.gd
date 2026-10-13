class_name PotreeGeoreference
extends RefCounted

const SCHEMA := "godot-potree-georeference-1"

var source_crs := ""
var origin_ecef := PackedFloat64Array([0.0, 0.0, 0.0])
var basis_ecef_from_local := Basis.IDENTITY

func parse_json_text(text: String) -> String:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "georeference sidecar is not a JSON object"
	if str(parsed.get("schema", "")) != SCHEMA:
		return "unsupported georeference sidecar schema"
	if not _is_vec3(parsed.get("origin_ecef")):
		return "origin_ecef must contain three numbers"
	var axes = parsed.get("basis_ecef_from_local")
	if typeof(axes) != TYPE_ARRAY or axes.size() != 3:
		return "basis_ecef_from_local must contain three axes"
	for axis in axes:
		if not _is_vec3(axis):
			return "every georeference basis axis must contain three numbers"
	source_crs = str(parsed.get("source_crs", ""))
	origin_ecef = PackedFloat64Array([
		float(parsed.origin_ecef[0]),
		float(parsed.origin_ecef[1]),
		float(parsed.origin_ecef[2]),
	])
	basis_ecef_from_local = Basis(_to_vec3(axes[0]), _to_vec3(axes[1]), _to_vec3(axes[2]))
	return ""

func apply_to_cesium(cloud: Node3D, cesium_georeference: Node) -> String:
	if cloud == null:
		return "point cloud node is null"
	var result := calculate_cesium_transform(cesium_georeference)
	if not result.error.is_empty():
		return result.error
	cloud.global_transform = result.transform
	return ""

func calculate_cesium_transform(cesium_georeference: Node) -> Dictionary:
	if cesium_georeference == null:
		return {"error": "Cesium georeference node is null"}
	for method in ["get_ecef_x", "get_ecef_y", "get_ecef_z"]:
		if not cesium_georeference.has_method(method):
			return {"error": "Cesium node does not expose its double-precision ECEF origin"}
	# Keep the subtraction in scalar doubles. Converting either absolute ECEF
	# position to Vector3 first loses metre-scale precision on float builds.
	var reference_x := float(cesium_georeference.call("get_ecef_x"))
	var reference_y := float(cesium_georeference.call("get_ecef_y"))
	var reference_z := float(cesium_georeference.call("get_ecef_z"))
	var relative_ecef := Vector3(
		origin_ecef[0] - reference_x,
		origin_ecef[1] - reference_y,
		origin_ecef[2] - reference_z
	)
	var up := Vector3(reference_x, reference_y, reference_z).normalized()
	var east := -up.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	if east.length_squared() < 0.5:
		return {"error": "cannot construct a local tangent frame at the ECEF pole"}
	var south := east.cross(up).normalized()
	var ecef_from_local_tangent := Basis(east, up, south)
	var ecef_to_local_tangent := ecef_from_local_tangent.inverse()
	var scale_factor := 1.0
	if cesium_georeference.has_method("get_scale_factor"):
		scale_factor = float(cesium_georeference.call("get_scale_factor"))
	return {"error": "", "transform": Transform3D(
		ecef_to_local_tangent * basis_ecef_from_local * scale_factor,
		(ecef_to_local_tangent * relative_ecef) * scale_factor
	)}

static func _is_vec3(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 3

static func _to_vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
