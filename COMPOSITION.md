# TunnelXR project composition

TunnelXR is one Godot project with one world and two small application scenes:

- `MainSolo.tscn` mounts `World/WorldFrame.tscn` in the solo runtime.
- `MainNetworking.tscn` mounts the same WorldFrame in the multiplayer runtime.

The world, its shaders, and its runtime data live together under `World/`.
Cesium, Potree, and Survex are the restricted world dependency set currently
checked into `addons/`. No world-content symlinks are required.

The local development composer has two addon profiles:

```sh
# XR Tools and desktop XR simulator; sufficient for MainSolo.
godot4 --headless --path . --script plug.gd link base

# Base plus MQTT, WebRTC, player-networking, and TwoVoIP.
godot4 --headless --path . --script plug.gd link networked

godot4 --headless --path . --script plug.gd status networked strict
godot4 --headless --import --xr-mode off --path .
godot4 --headless --path . --script plug.gd unlink networked
```

`strict` requires every selected peer to be at its declared Git commit. A dirty
peer at that commit is reported but remains usable for tandem development.
Generated addon links are ignored by Git. Unix uses directory symlinks and
Windows uses directory junctions.

Godot can write `.import` and `.uid` sidecars through a linked addon. Initial
imports should therefore be run serially when several composed projects share
the same editable peer.
