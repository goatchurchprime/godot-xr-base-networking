# TunnelXR world composition

The top-level application is deliberately a small composition of authored
scenes. Open the `.tscn` files in Godot to see what the application intends to
run; scripts configure data sources and behaviour, but do not secretly assemble
the main scene tree.

## Scene layout

```text
GodotCesiumXR or TunnelXRQuestCave       application shell
├── CaveCesiumWorld or CaveLocalWorld   shared WorldFrame3D
│   ├── Environment
│   │   └── CaveEnvironment             sky, ambient light, directional sun
│   ├── Geospatial                      Cesium and other Earth data
│   ├── Survey
│   │   └── CaveSurveyComponent
│   │       └── SurvexLayer             survey geometry and station API
│   ├── PointClouds                     Potree components
│   ├── SharedPlaces                    networked world entities
│   ├── Avatars                         world-space avatar presentations
│   ├── PhysicsDomain                   unit-scale physics entities
│   └── Debug
├── LocalPlayer
│   └── XRPlayerRig                     camera, tracked hands, selection laser
└── ApplicationSystems                  orchestration which is not world content
```

`CaveCesiumWorld` is the desktop/Steam Frame world. `CaveLocalWorld` is the
offline Android/Quest world and intentionally contains no Cesium native types.
Both use the same survey component and the same stable child categories.

## WorldFrame contract

`WorldFrame3D` maps stable site coordinates into the current local Godot
render/physics frame.

- It always has scale `(1, 1, 1)`. One site metre remains one physics metre.
- Its transform changes only as an explicit, atomic rebase operation, normally
  during a teleport or leave-and-return transition.
- Ordinary world children inherit the transform through Godot's scene tree.
- Streaming components receive view context through
  `set_world_view_context(context)` when they need a camera expressed in their
  private coordinate system for culling or level-of-detail selection.
- Frame-aware components may implement `set_world_frame_context(context)` and
  receive a new context after a rebase.
- `XRServer.world_scale` changes the local player's perceived embodiment scale;
  it does not scale WorldFrame or the physics simulation.

The frame context contains a stable `world_id`, coordinate kind, frame epoch,
site origin/orientation, and both directions of the site/render transform. The
epoch lets networking and asynchronous streamers reject results prepared for an
obsolete frame.

## Player and network boundary

The local XR rig is a sibling of WorldFrame, not a child. Raw tracking data is
real playspace data. Joystick locomotion and virtual placement describe the
relationship between that playspace and a shared world.

A future networked player component can therefore publish two explicit groups:

1. real observations: head/hands, voice, optional bounds and room scan;
2. virtual placement: world id, site-space pose, embodiment scale and frame
   epoch.

World-space avatars are presentations driven from those groups and live under
`WorldFrame/Avatars`. They may use a specialised high-rate replication path,
but remain architecturally shared world entities.

## Component rule

A reusable component should be a complete scene with a narrow script API. Its
important nodes and resources belong in the scene, where a human can inspect
them. Runtime construction is reserved for genuinely dynamic payloads such as
streamed Cesium tiles, generated Survex meshes and Potree batches.

Current component APIs include:

- `CaveSurveyComponent.load_local_file()` for an offline/local frame;
- `CaveSurveyComponent.load_georeferenced_file()` for a Cesium-aligned frame;
- `XRPlayerRig.set_pointer_segment()` and `hide_pointer()`;
- `WorldFrame3D.apply_rebase()`, coordinate conversion, and view-context
  notification.

Cesium and Potree still need further extraction: their static configuration and
public API should become authored component scenes, while only downloaded tile
and point nodes remain runtime-created.
