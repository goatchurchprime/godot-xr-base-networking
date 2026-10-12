@tool
extends "res://tools/compose_plug.gd"

# The assembly owns only MainNetworking and application configuration. World
# content and actively developed networking layers remain in their own repos.

func _plugging() -> void:
	peer(
		"TunnelXR_World",
		"../TunnelXR_World",
		"ee889c0546270ce07520a18acedf31d8618d29a9",
		[
			mount("worlds", "worlds"),
			mount("components", "components"),
			mount("Shaders", "Shaders"),
			mount("editor_lab", "editor_lab"),
			mount("reference_tiles", "reference_tiles"),
			mount("bin", "bin"),
			mount("addons/cesium_godot", "addons/cesium_godot"),
			mount("addons/godot_potree", "addons/godot_potree"),
			mount("addons/survex", "addons/survex"),
		],
	)
	peer(
		"godot-xr-tools",
		"../godot-xr-base-networking/.plugged/godot-xr-tools",
		"6fc5361db295c12b5e51ee5b9fee09751a4458e7",
		[mount("addons/godot-xr-tools", "addons/godot-xr-tools")],
	)
	peer(
		"godot-vr-simulator",
		"../godot-xr-base-networking/.plugged/godot-vr-simulator",
		"3b669da81f66f2667052dbb7f57d6986c40fb36c",
		[mount("addons/xr-simulator", "addons/xr-simulator")],
	)
	peer(
		"godot-mqtt",
		"../godot-mqtt",
		"21e94568bd80a84b59f7b9e485e581736eacfe59",
		[mount("addons/mqtt", "addons/mqtt")],
	)
	peer(
		"godot-webrtc-addon",
		"../godot-xr-base-networking/.plugged/godot-webrtc-addon",
		"8876c71e929ac2b193a2f4840fd81caf5fc0c1f7",
		[mount("addons/webrtc", "addons/webrtc")],
	)
	peer(
		"player-networking",
		"../godot_multiplayer_networking_workbench",
		"37a243513697d090d46b453989ab1fa9281a6bc5",
		[mount("addons/player-networking", "addons/player-networking")],
	)
	peer(
		"TwoVoIP",
		"../two-voip-godot-4",
		"7b5d7516a50caa30f2cff21f6b1bb6087a10835d",
		[mount("addons/twovoip", "addons/twovoip")],
	)
