@tool
class_name CaveSurveyComponent
extends Node3D

signal survey_loaded(layer: SurvexLayer)
signal survey_load_failed(message: String)

@export_file("*.json") var default_data_path := ""

@onready var layer: SurvexLayer = $SurvexLayer


func load_local_file(path := "") -> String:
	path = default_data_path if path.is_empty() else path
	var error := layer.load_local_file(path)
	_emit_load_result(error)
	return error


func load_georeferenced_file(path: String, cesium_georeference: Node) -> String:
	var error := layer.load_file(path, cesium_georeference)
	_emit_load_result(error)
	return error


func load_georeferenced_data(parsed: Variant, cesium_georeference: Node, source_name := "Survex data") -> String:
	var error := layer.load_data(parsed, cesium_georeference, source_name)
	_emit_load_result(error)
	return error


func _emit_load_result(error: String) -> void:
	if error.is_empty():
		survey_loaded.emit(layer)
	else:
		survey_load_failed.emit(error)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if default_data_path.is_empty():
		warnings.append("Assign default_data_path or load survey data through the component API.")
	return warnings
