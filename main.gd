extends Node3D

func _on_start_xr_xr_failed_to_initialize():
	$XROrigin3D/XRSimulator.enabled = true
	#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
