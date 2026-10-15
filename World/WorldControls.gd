extends PanelContainer

@onready var sun_energy: HSlider = $Margin/VBox/SunEnergy
@onready var sun_value: Label = $Margin/VBox/SunRow/SunValue
@onready var terrain_visible: CheckButton = $Margin/VBox/TerrainVisible
@onready var cave_visible: CheckButton = $Margin/VBox/CaveVisible

var _sun: DirectionalLight3D
var _terrain_root: Node3D
var _survey_root: Node3D


func _ready() -> void:
	var world := get_parent().get_parent()
	if not world:
		return
	_sun = world.get_node_or_null("Frame/Environment/CaveEnvironment/Sun") as DirectionalLight3D
	_terrain_root = world.get_node_or_null("Frame/Terrain") as Node3D
	_survey_root = world.get_node_or_null("Frame/Survey") as Node3D

	if is_instance_valid(_sun):
		sun_energy.value = _sun.light_energy
	_update_sun_value(sun_energy.value)
	terrain_visible.button_pressed = _terrain_root.visible if _terrain_root else false
	cave_visible.button_pressed = _survey_root.visible if _survey_root else false

	sun_energy.value_changed.connect(_on_sun_energy_changed)
	terrain_visible.toggled.connect(_on_terrain_visible_toggled)
	cave_visible.toggled.connect(_on_cave_visible_toggled)


func _on_sun_energy_changed(value: float) -> void:
	if is_instance_valid(_sun):
		_sun.light_energy = value
	_update_sun_value(value)


func _on_terrain_visible_toggled(enabled: bool) -> void:
	if is_instance_valid(_terrain_root):
		_terrain_root.visible = enabled


func _on_cave_visible_toggled(enabled: bool) -> void:
	if is_instance_valid(_survey_root):
		_survey_root.visible = enabled


func _update_sun_value(value: float) -> void:
	sun_value.text = "%.1f" % value
