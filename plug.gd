@tool
extends "res://addons/gd-plug/plug.gd"

# from clean clone run 
#   godot4 --headless --xr-mode off -s plug.gd update debug
# To export to android you will also need to install openxrvendorsplugin (v 4.0.0) from the assetlib

func _plugging():
	# Downloaded, pinned dependencies.
	# Fork branch: fix/desktop-start-xr-lookup
	plug("goatchurchprime/godot-xr-tools", {"commit": "d28eeb9e031b2296f464db8b865a4fbebf2dc444"})
	plug("goatchurchprime/godot-vr-simulator", {"branch": "main"})
	plug("goatchurchprime/godot-mqtt", {"branch": "codex/simulated-broker-design"})
	plug("goatchurchprime/godot-webrtc-addon", {"branch": "v1.1.0"})

	# TwoVoIP and player-networking are developed alongside this project and are
	# intentionally not managed by gd-plug. Their addon directories are linked:
	#   addons/twovoip -> ../../two-voip-godot-4/addons/twovoip
	#   addons/player-networking -> ../../godot_multiplayer_networking_workbench/addons/player-networking
