extends XRToolsViewport2DIn3D

## Presents component-owned SubViewports on one controller-mounted XR panel.
##
## The components retain their UI nodes and state. This node only changes the
## viewport rendered by the XRToolsViewport2DIn3D surface and cycles that
## surface through hidden and the viewports that exist in this composition.

signal panel_changed(viewport: SubViewport)
signal panels_hidden

@export var toggle_button: StringName = &"menu_button"
@export var starts_at := -1
@export var panel_width_metres := 0.52
@export var hand_offset := Transform3D(
	Basis.IDENTITY,
	Vector3(0.0, 0.14, -0.30),
)

var _controller: XRController3D
var _panels: Array[SubViewport] = []
var _selected := -1


func _ready() -> void:
	_add_panels()

	# XRToolsViewport2DIn3D needs a valid viewport while it initializes, even
	# though the panel starts hidden. Its built-in child remains the fallback in
	# compositions which provide no component UI.
	if not _panels.is_empty():
		_select_viewport(_panels[0])

	_controller = get_node_or_null("../XROrigin3D/XRController3D_left") as XRController3D
	if not _controller:
		push_warning("ViewportUIPanels cannot find the left XR controller")
	else:
		_controller.button_pressed.connect(_on_controller_button_pressed)
		_follow_controller()

	visible = false
	super._ready()
	show_panel(starts_at)


func _physics_process(_delta: float) -> void:
	_follow_controller()


func _input(event: InputEvent) -> void:
	if visible:
		super._input(event)


func _exit_tree() -> void:
	if (
		is_instance_valid(_controller)
		and _controller.button_pressed.is_connected(_on_controller_button_pressed)
	):
		_controller.button_pressed.disconnect(_on_controller_button_pressed)


func _add_panels() -> void:
	add_hand_panel(get_node_or_null("../../XRMultiplayerSystem/Viewport") as SubViewport)
	add_hand_panel(get_node_or_null("../../WorldFrame/ControlsViewport") as SubViewport)


func add_hand_panel(panel: SubViewport) -> void:
	if panel and not _panels.has(panel):
		_panels.append(panel)


func show_panel(index: int) -> void:
	if index < 0 or index >= _panels.size():
		_selected = -1
		visible = false
		panels_hidden.emit()
		return

	_selected = index
	_select_viewport(_panels[_selected])
	visible = true
	panel_changed.emit(_panels[_selected])


func show_next_panel() -> void:
	if _panels.is_empty():
		return
	show_panel(_selected + 1 if _selected + 1 < _panels.size() else -1)


func _select_viewport(panel: SubViewport) -> void:
	_viewport = panel
	viewport_path = get_path_to(panel)
	viewport_size = Vector2(panel.size)

	var aspect := float(panel.size.y) / maxf(float(panel.size.x), 1.0)
	screen_size = Vector2(panel_width_metres, panel_width_metres * aspect)

	if not is_ready:
		return

	panel.gui_embed_subwindows = true
	_static_body.set_viewport(panel)
	_update_render()
	if _screen_material:
		viewport_texture = panel.get_texture()
		_screen_material.albedo_texture = viewport_texture


func _on_controller_button_pressed(button: StringName) -> void:
	if button == toggle_button:
		show_next_panel()


func _follow_controller() -> void:
	# This is deliberately the only mounting behaviour for now. Later modes can
	# place the same surface relative to XROrigin3D or XRCamera3D, while a
	# non-XR presenter can show the component viewport directly and use mouse UI.
	if is_instance_valid(_controller):
		global_transform = _controller.global_transform * hand_offset
