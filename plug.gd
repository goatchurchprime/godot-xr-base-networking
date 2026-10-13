@tool
extends "res://tools/compose_plug.gd"

# `base` is enough for MainSolo. `networked` includes the base peers plus the
# wider networking stack required by MainNetworking.

func _plugging() -> void:
	peer(
		"godot-xr-tools",
		"../godot-xr-base-networking/.plugged/godot-xr-tools",
		"d28eeb9e031b2296f464db8b865a4fbebf2dc444",
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
		["networked"],
	)
	peer(
		"godot-webrtc-addon",
		"../godot-xr-base-networking/.plugged/godot-webrtc-addon",
		"8876c71e929ac2b193a2f4840fd81caf5fc0c1f7",
		[mount("addons/webrtc", "addons/webrtc")],
		["networked"],
	)
	peer(
		"player-networking",
		"../godot_multiplayer_networking_workbench",
		"37a243513697d090d46b453989ab1fa9281a6bc5",
		[mount("addons/player-networking", "addons/player-networking")],
		["networked"],
	)
	peer(
		"TwoVoIP",
		"../two-voip-godot-4",
		"620771ae06fb099b0eeae4cd2598fe6c8b8e30de",
		[mount("addons/twovoip", "addons/twovoip")],
		["networked"],
	)
