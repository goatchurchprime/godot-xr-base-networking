class_name SunDirectionController
extends Node

@export var degrees_per_second := 45.0
@export var minimum_elevation := 1.0
@export var maximum_elevation := 89.0

var sun: DirectionalLight3D
var view_camera: Camera3D
var left_controller: XRController3D
var right_controller: XRController3D
var azimuth_degrees := -35.0
var elevation_degrees := 65.0
var _xr_adjusting := false
var _gimbal: MeshInstance3D
var _readout: Label3D


func configure(
	light: DirectionalLight3D,
	camera: Camera3D,
	left_hand: XRController3D = null,
	right_hand: XRController3D = null
) -> void:
	sun = light
	view_camera = camera
	left_controller = left_hand
	right_controller = right_hand
	azimuth_degrees = sun.rotation_degrees.y
	elevation_degrees = clampf(-sun.rotation_degrees.x, minimum_elevation, maximum_elevation)
	_create_gimbal()
	_apply_angles()


func is_xr_adjusting() -> bool:
	return _xr_adjusting


func _process(delta: float) -> void:
	if sun == null:
		return
	var adjustment := Vector2.ZERO
	if left_controller != null and right_controller != null and left_controller.get_is_active():
		_xr_adjusting = left_controller.get_float("grip") > 0.65
		if _xr_adjusting and right_controller.get_is_active():
			adjustment = right_controller.get_vector2("primary")
			if adjustment.length() < 0.15:
				adjustment = Vector2.ZERO
	else:
		_xr_adjusting = false
		adjustment.x = float(Input.is_key_pressed(KEY_L)) - float(Input.is_key_pressed(KEY_J))
		adjustment.y = float(Input.is_key_pressed(KEY_I)) - float(Input.is_key_pressed(KEY_K))
	if adjustment != Vector2.ZERO:
		azimuth_degrees = wrapf(azimuth_degrees + adjustment.x * degrees_per_second * delta, -180.0, 180.0)
		elevation_degrees = clampf(
			elevation_degrees + adjustment.y * degrees_per_second * delta,
			minimum_elevation,
			maximum_elevation
		)
		_apply_angles()
	if _gimbal != null:
		_gimbal.visible = left_controller == null or _xr_adjusting
		_update_gimbal()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_U and sun != null:
		azimuth_degrees = -35.0
		elevation_degrees = 65.0
		_apply_angles()


func _apply_angles() -> void:
	sun.rotation_degrees = Vector3(-elevation_degrees, azimuth_degrees, 0.0)
	if _readout != null:
		_readout.text = "SUN  az %+.0f°  el %.0f°\nJ/L azimuth  I/K elevation  U reset" % [azimuth_degrees, elevation_degrees]


func _create_gimbal() -> void:
	_gimbal = MeshInstance3D.new()
	_gimbal.name = "SunDirectionGimbal"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_gimbal.material_override = material
	var parent: Node3D = left_controller if left_controller != null else view_camera
	parent.add_child(_gimbal)
	_gimbal.position = Vector3(0.0, 0.10, -0.16) if left_controller != null else Vector3(0.52, -0.32, -1.25)
	_gimbal.scale = Vector3.ONE * (0.45 if left_controller != null else 1.0)
	_readout = Label3D.new()
	_readout.name = "SunAngleReadout"
	_readout.position = Vector3(0.0, 0.16, 0.0)
	_readout.font_size = 28
	_readout.pixel_size = 0.0016
	_readout.outline_size = 8
	_readout.no_depth_test = true
	_readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gimbal.add_child(_readout)


func _update_gimbal() -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	_add_line(immediate, Vector3.ZERO, Vector3.RIGHT * 0.11, Color(1.0, 0.2, 0.2))
	_add_line(immediate, Vector3.ZERO, Vector3.UP * 0.11, Color(0.2, 1.0, 0.25))
	_add_line(immediate, Vector3.ZERO, Vector3.BACK * 0.11, Color(0.25, 0.5, 1.0))
	var parent_3d := _gimbal.get_parent_node_3d()
	var toward_sun_world := sun.global_basis.z.normalized()
	var toward_sun_local := parent_3d.global_basis.inverse() * toward_sun_world
	var tip := toward_sun_local.normalized() * 0.22
	_add_line(immediate, Vector3.ZERO, tip, Color(1.0, 0.88, 0.12))
	var side := tip.cross(Vector3.UP).normalized() * 0.025
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT * 0.025
	_add_line(immediate, tip, tip * 0.76 + side, Color(1.0, 0.88, 0.12))
	_add_line(immediate, tip, tip * 0.76 - side, Color(1.0, 0.88, 0.12))
	immediate.surface_end()
	_gimbal.mesh = immediate


func _add_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, colour: Color) -> void:
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(to)
