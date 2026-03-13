@tool
extends "res://addons/gd-plug/plug.gd"

# from clean clone run 
#   godot4 --headless --xr-mode off -s plug.gd update debug
# To export to android you will also need to install openxrvendorsplugin (v 4.0.0) from the assetlib

func _plugging():
	plug("GodotVR/godot-xr-tools", {"tag": "4.5.1"})
	plug("goatchurchprime/godot-vr-simulator", {"branch": "compatxrtools45"})
	plug("goatchurchprime/godot-mqtt", {"branch": "main"})
	plug("goatchurchprime/godot_multiplayer_networking_workbench", {"include": ["addons/player-networking"], "branch":"main"})
	plug("goatchurchprime/two-voip-addon", {"branch": "v4.1"})
	plug("goatchurchprime/godot-webrtc-addon", {"branch": "v1.1.0"})

	plug("goatchurchprime/godot-fluid-simulation", {"branch": "main"})
