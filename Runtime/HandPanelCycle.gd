extends Node

## Small composition-level switcher for independently-owned UI panels.
## Each panel remains a separate Viewport2DIn3D with its own physical and
## render sizes; this node only decides which one is visible.

@export var controller_path: NodePath
@export var toggle_button: StringName = &"menu_button"
@export var panel_paths: Array[NodePath] = []
@export var starts_at := -1

var _controller: XRController3D
var _panels: Array[Node3D] = []
var _selected := -1


func _ready() -> void:
	for panel_path in panel_paths:
		var panel := get_node_or_null(panel_path) as Node3D
		if panel:
			_panels.append(panel)
		else:
			push_warning("HandPanelCycle cannot find panel at %s" % panel_path)

	_controller = get_node_or_null(controller_path) as XRController3D
	if not _controller:
		push_warning("HandPanelCycle cannot find its controller at %s" % controller_path)
	else:
		_controller.button_pressed.connect(_on_controller_button_pressed)

	show_panel(starts_at)


func _exit_tree() -> void:
	if (
		is_instance_valid(_controller)
		and _controller.button_pressed.is_connected(_on_controller_button_pressed)
	):
		_controller.button_pressed.disconnect(_on_controller_button_pressed)


func show_panel(index: int) -> void:
	_selected = index if index >= 0 and index < _panels.size() else -1
	for panel_index in _panels.size():
		_panels[panel_index].visible = panel_index == _selected


func show_next_panel() -> void:
	if _panels.is_empty():
		return
	show_panel(_selected + 1 if _selected + 1 < _panels.size() else -1)


func _on_controller_button_pressed(button: StringName) -> void:
	if button == toggle_button:
		show_next_panel()
