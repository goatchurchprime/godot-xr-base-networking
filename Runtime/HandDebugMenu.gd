extends XRToolsViewport2DIn3D

## Temporary wrist-mounted shell for the networking workbench UI.
##
## The NetworkGateway remains a normal child of this viewport. Keeping this
## node at the runtime root also preserves the paths used by the current
## networking prototype while its presentation follows the left controller.

signal menu_opened
signal menu_closed

@export var controller_path: NodePath
@export var toggle_button: StringName = &"menu_button"
@export var starts_open := false
@export var hand_offset := Transform3D(
	Basis.IDENTITY,
	Vector3(0.0, 0.14, -0.30),
)

var _controller: XRController3D


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as XRController3D
	if not _controller:
		push_warning("HandDebugMenu cannot find its controller at %s" % controller_path)
	else:
		_controller.button_pressed.connect(_on_controller_button_pressed)
		_follow_controller()

	visible = starts_open
	super._ready()


func _physics_process(_delta: float) -> void:
	_follow_controller()


func _input(event: InputEvent) -> void:
	# Keep the workbench's editable fields usable from a development keyboard,
	# but do not let a closed menu consume ordinary application input.
	if visible:
		super._input(event)


func _exit_tree() -> void:
	if (
		is_instance_valid(_controller)
		and _controller.button_pressed.is_connected(_on_controller_button_pressed)
	):
		_controller.button_pressed.disconnect(_on_controller_button_pressed)


func set_menu_open(open: bool) -> void:
	if visible == open:
		return

	visible = open
	if open:
		menu_opened.emit()
	else:
		menu_closed.emit()


func toggle_menu() -> void:
	set_menu_open(not visible)


func _on_controller_button_pressed(button: StringName) -> void:
	if button == toggle_button:
		toggle_menu()


func _follow_controller() -> void:
	if is_instance_valid(_controller):
		global_transform = _controller.global_transform * hand_offset
