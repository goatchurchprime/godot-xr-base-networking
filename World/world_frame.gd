@tool
class_name WorldFrame3D
extends Node3D

## A unit-scale presentation root for one shared world.
##
## Children store transforms in stable site coordinates. This node maps those
## coordinates into the local Godot render/physics frame. It is deliberately
## rigid: player embodiment scale belongs to XRServer.world_scale and entity
## presentation scale belongs to the entity, never to this node.

signal frame_rebased(context: Dictionary)

enum CoordinateKind {
	EUCLIDEAN,
	GEOGRAPHIC_ECEF,
}

@export var world_id := ""
@export var coordinate_kind := CoordinateKind.EUCLIDEAN
@export var site_origin := Vector3.ZERO
@export var site_orientation := Quaternion.IDENTITY
@export var frame_epoch := 0


func get_frame_context() -> Dictionary:
	return {
		"world_id": world_id,
		"coordinate_kind": coordinate_kind,
		"site_origin": site_origin,
		"site_orientation": site_orientation,
		"frame_epoch": frame_epoch,
		"render_from_site": global_transform,
		"site_from_render": global_transform.affine_inverse(),
		"render_units_per_site_metre": 1.0,
	}


func site_to_render(site_transform: Transform3D) -> Transform3D:
	return global_transform * site_transform


func render_to_site(render_transform: Transform3D) -> Transform3D:
	return global_transform.affine_inverse() * render_transform


func apply_rebase(new_site_origin: Vector3, new_site_orientation := Quaternion.IDENTITY) -> void:
	# Rebasing is an explicit teleport/transition operation. Callers are
	# responsible for pausing active physics before invoking it.
	site_origin = new_site_origin
	site_orientation = new_site_orientation.normalized()
	frame_epoch += 1
	var frame_basis := Basis(site_orientation)
	transform = Transform3D(frame_basis, -(frame_basis * site_origin))
	var context := get_frame_context()
	_notify_frame_aware_descendants(self, context)
	frame_rebased.emit(context)


func update_view_context(view_context: Dictionary) -> void:
	# Cesium, Potree and similar components need the camera in their private
	# coordinate system for LoD. Ordinary child nodes need no callback because
	# they inherit this node's forward transform through the scene tree.
	_notify_view_aware_descendants(self, view_context)


func _notify_frame_aware_descendants(parent: Node, context: Dictionary) -> void:
	for child in parent.get_children():
		if child.has_method("set_world_frame_context"):
			child.call("set_world_frame_context", context)
		_notify_frame_aware_descendants(child, context)


func _notify_view_aware_descendants(parent: Node, context: Dictionary) -> void:
	for child in parent.get_children():
		if child.has_method("set_world_view_context"):
			child.call("set_world_view_context", context)
		_notify_view_aware_descendants(child, context)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not scale.is_equal_approx(Vector3.ONE):
		warnings.append(
			"WorldFrame3D must remain at unit scale so physics keeps one metre per Godot unit. "
			+ "Use XRServer.world_scale for local embodiment scale."
		)
	if world_id.is_empty():
		warnings.append("Assign a stable world_id before this world is used over the network.")
	return warnings
