extends Node3D

func _on_start_xr_xr_failed_to_initialize():
	$XROrigin3D/XRSimulator.enabled = true
	#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ready():
	await get_tree().create_timer(0.5).timeout
	$NetworkGatewayViewport/Viewport/NetworkGateway.simple_webrtc_connect("lylylyl")

var fadetween = null
func Dset_fade(p_value : float):
	XRToolsFade.set_fade("spawnpoint", Color(0.3, 0, 0, p_value))

func _process(delta):
	if $XROrigin3D.position.y < -50 and not fadetween:
		fadetween = get_tree().create_tween()
		fadetween.tween_method(Dset_fade, 0.0, 1.0, 0.34)
		await fadetween.finished
		$XROrigin3D.position = Vector3(0,1,0)
		$XROrigin3D/PlayerBody.velocity = Vector3(0,0,0)
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
