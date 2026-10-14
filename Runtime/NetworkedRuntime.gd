extends Node3D

@export_range(1.0, 20.0, 0.1) var flight_boost_multiplier := 6.0

@onready var xr_system := $XRSystem
@onready var movement_flight: XRToolsMovementFlight = xr_system.origin.get_node("MovementFlight") as XRToolsMovementFlight
@onready var right_controller: XRController3D = xr_system.right_controller

var cruise_flight_speed := 5.0
var flight_boost_active := false


# this gets called before ready
func _on_start_xr_xr_failed_to_initialize():
	$XRSystem/XROrigin3D/XRSimulator.enabled = true
	#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	movement_flight.set_flying(true)
	cruise_flight_speed = movement_flight.speed_scale

var fadetween = null
func Dset_fade(p_value : float):
	XRToolsFade.set_fade("spawnpoint", Color(0.3, 0, 0, p_value))

func _process(delta):
	var boosting := Input.is_key_pressed(KEY_SHIFT) or right_controller.is_button_pressed(&"by_button")
	if boosting != flight_boost_active:
		flight_boost_active = boosting
		movement_flight.speed_scale = cruise_flight_speed * (flight_boost_multiplier if boosting else 1.0)
	if xr_system.origin.position.y < -50 and not fadetween:
		fadetween = get_tree().create_tween()
		fadetween.tween_method(Dset_fade, 0.0, 1.0, 0.34)
		await fadetween.finished
		xr_system.origin.position = Vector3(0,1,0)
		xr_system.origin.get_node("PlayerBody").velocity = Vector3(0,0,0)
		fadetween = get_tree().create_tween()
		fadetween.tween_method(Dset_fade, 1.0, 0.0, 0.34)
		await fadetween.finished
		fadetween = null
		
		
#	var tween = get_tree().create_tween()
#	tween.tween_method(set_fade, 0.0, 1.0, 0.34)
#	await tween.finished
#	arvrorigin.transform = sfd["spawnpointtransform"]
#	tween = get_tree().create_tween()
#	tween.tween_method(set_fade, 1.0, 0.0, 0.34)
#	PlayerConnection.spawninfoforclientprocessed()
#	await tween.finished
#
#a		$PlayerBody.position = Vector3(0,0,5)
