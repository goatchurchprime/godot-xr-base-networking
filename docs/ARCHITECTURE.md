# TunnelXR world composition

The top-level application is deliberately a small composition of authored
scenes. Open the `.tscn` files in Godot to see what the application intends to
run; scripts configure data sources and behaviour, but do not secretly assemble
the main scene tree.

## Scene layout

```text
MainSolo
├── XRSystem                            local rig, locomotion, hands and XR UI
└── WorldFrame                          shared geospatial presentation

MainNetworking
├── XRSystem                            the same local XR component
├── XRMultiplayerSystem                 gateway, voice and replicated avatars
└── WorldFrame                          the same world component
```

`WorldFrame` owns the stable Environment, Geospatial, Terrain, Survey,
PointClouds, SharedPlaces, Avatars, PhysicsDomain and Debug categories. Cesium
is optional and disabled by default; local terrain and survey data therefore
use this same scene on desktop, Steam Frame and Quest.

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
- `XRSystem` exposes its origin, camera and controllers to the world;
- `ViewportUIPanels` presents component-owned UI viewports in XR;
- `WorldFrame3D.apply_rebase()`, coordinate conversion, and view-context
  notification.

Cesium and Potree still need further extraction: their static configuration and
public API should become authored component scenes, while only downloaded tile
and point nodes remain runtime-created.
