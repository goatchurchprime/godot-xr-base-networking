# TunnelXR

TunnelXR is a Godot project composed directly from independent XR, multiplayer,
and geospatial world scenes.

```text
MainSolo.tscn       -> XRSystem + WorldFrame
MainNetworking.tscn -> XRSystem + XRMultiplayerSystem + WorldFrame
```

There is no inherited runtime shell between these application scenes and their
components. The default scene is `MainSolo.tscn`. Install the restricted base
addon set before importing the project:

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
three-component composition, is documented in
`docs/WORLD_PLAYER_AFFORDANCES.md`.
