# TunnelXR

TunnelXR is a single Godot project that combines one geospatial WorldFrame with
either a solo XR/desktop runtime or the reusable multiplayer runtime.

```text
MainSolo.tscn       -> solo runtime       + World/WorldFrame.tscn
MainNetworking.tscn -> networking runtime + World/WorldFrame.tscn
```

The default scene is `MainSolo.tscn`. Install the restricted base addon set
before importing the project:

```sh
godot4 --headless --xr-mode off --path . --script plug.gd link base
godot4 --headless --import --xr-mode off --path .
godot4 --path .
```

The base composition includes [Zylann's HTerrain](https://github.com/Zylann/godot_heightmap_plugin)
for bounded, local heightfield terrain with quadtree LOD. It is linked from the
neighbouring `godot_heightmap_plugin` checkout and remains an independently
versioned MIT-licensed addon.

For multiplayer development, compose the wider addon set and select
`MainNetworking.tscn`:

```sh
godot4 --headless --xr-mode off --path . --script plug.gd link networked
godot4 --editor --path . MainNetworking.tscn
```

See `COMPOSITION.md` for peer revision checks and unlinking. The proposed
world-to-player physics boundary, including zero-gravity regions and the
three-scene composition, is documented in
`docs/WORLD_PLAYER_AFFORDANCES.md`.
