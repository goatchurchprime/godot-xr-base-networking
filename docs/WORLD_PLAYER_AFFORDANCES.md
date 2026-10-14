# World-to-player physics and affordances

Status: design reference, not yet an implemented API. Reviewed against the
official VRChat creator documentation on 2026-10-13.

## Decision in brief

TunnelXR should treat the world, XR embodiment, and networking as three
separate capabilities. That leads naturally to three small application scenes:

| Scene | Composition | Intended use |
| --- | --- | --- |
| `MainSolo` | World + minimal desktop spectator/controller | Import-safe world development without the XR or networking addon stacks |
| `MainSoloXR` | World + local XR player | Normal solo use, either with OpenXR hardware or XRSimulator on a flat screen |
| `MainNetworkingXR` | World + local XR player + network session | The same embodiment with replicated players and voice |

`MainSoloXR` is the important middle layer. It proves that falling, flying,
colliding, grabbing, and operating the world belong to the local player/XR
runtime rather than to networking. `MainSolo` remains useful as a lightweight
world viewer and authoring target even if it is not eventually a complete user
experience.

These are compositions, not three implementations. All three mount the same
`WorldFrame`; both XR scenes instantiate the same local-player scene; the
networked scene only adds session machinery. A world must not contain OpenXR,
XR Tools, MQTT, TwoVoIP, or multiplayer nodes.

World interaction also need not depend directly on XR controllers. The XR
runtime and the minimal desktop runtime can both expose semantic actions such
as `point`, `select`, `grab`, `move`, and `change_sun_angle`. The world consumes
those actions without knowing whether they came from tracked hands, a mouse,
or XRSimulator.

## What VRChat actually provides

VRChat is a useful precedent, but it does not have one declarative “world
physics settings” object. Its behavior is divided between a scene descriptor,
local-player API calls, trigger scripts, and stations.

### Settings applied by the scene

The
[VRC Scene Descriptor](https://creators.vrchat.com/worlds/components/vrc_scenedescriptor/)
defines:

- spawn transforms, radius, ordering, and room/player orientation;
- reference-camera settings, such as clipping and post-processing;
- the Y height at which players respawn;
- whether fallen pickups respawn or are destroyed;
- restrictions on free object manipulation and user-created portals;
- default voice falloff controls; and
- an interaction-passthrough layer mask.

Notably, the descriptor has no gravity, walking-speed, jump, or flight field.
Those values are set by world code after the local player exists. VRChat's
[Player Mod Setter example](https://creators.vrchat.com/worlds/examples/udon-example-scene/player-mod-setter/)
does this at world startup for jump impulse, walk speed, run speed, strafe
speed, and gravity strength.

### Runtime locomotion and physics controls

The official
[Player Forces API](https://creators.vrchat.com/worlds/udon/players/player-forces/)
allows a world to get and set these values:

| VRChat control | Meaning |
| --- | --- |
| Walk speed | Forward walking speed; prefab default 2 |
| Run speed | Forward running speed; prefab default 4 |
| Strafe speed | Sideways speed; prefab default 2 |
| Jump impulse | Initial upward jump velocity; VRCWorld prefab default 3 |
| Gravity strength | Multiplier on normal Earth gravity; default 1, zero disables gravity |
| Immobilize | Disables locomotion while leaving limited physical head movement in VR |

These setters affect only the local player. World code cannot directly change
a remote player's locomotion; it must cause the other client to apply the
change locally. This is a strong precedent for keeping local-player physics in
the player runtime and replicating its resulting placement/pose.

The
[Player Positions API](https://creators.vrchat.com/worlds/udon/players/player-positions/)
adds position, rotation, velocity, grounded state, `SetVelocity`, and
`TeleportTo`. Teleporting is also local-only. VRChat warns that stations may
prevent a teleport and that large teleports can reset remote animation/IK
unless the remote presentation is interpolated.

VRChat exposes a scalar gravity multiplier, not arbitrary gravity vectors,
buoyancy, drag, or a built-in flight mode. Worlds implement richer movement in
their own scripts.

### Runtime regions

VRChat does not document a special gravity-volume component. Its
[player collision API](https://creators.vrchat.com/worlds/udon/players/player-collisions/)
provides `OnPlayerTriggerEnter`, `Stay`, and `Exit` for a player's capsule in a
trigger collider. A world can use those events to call `SetGravityStrength(0)`
on the local player inside a volume and restore another value outside it.

This is how zero-gravity rooms and other regional effects can be constructed,
but it has an important trap: VRChat says trigger events may be skipped during
teleports or very fast movement. TunnelXR should therefore resolve the set of
currently overlapping volumes on physics ticks and use enter/exit signals only
as hints, rather than relying on a perfectly paired enter and exit.

### Stations, vehicles, and constrained poses

A
[VRC Station](https://creators.vrchat.com/worlds/components/vrc_station/)
can leave a player mobile, immobilize them, or immobilize them using behavior
optimized for a moving vehicle. It can move the player to entry and exit
transforms, prevent normal exit, override seated animation, and associate the
player with a controlled object. Stations are a modal override, distinct from
ordinary regional settings: a chair, lift, boat, or vehicle temporarily owns
the player's virtual placement while real head/hand tracking can continue.

### Avatar size, interaction, input, and audio

Other relevant world-to-player controls are:

- [Avatar scaling](https://creators.vrchat.com/worlds/udon/players/player-avatar-scaling/):
  a world may allow manual scaling, constrain minimum and maximum eye height,
  or set eye height authoritatively. Scaling the avatar does not resize its
  environment collision capsule.
- [Player API](https://creators.vrchat.com/worlds/udon/players/): a world can
  disable pickup use, inspect VR/desktop mode, trigger controller haptics, and
  enter an attached station.
- [Input events](https://creators.vrchat.com/worlds/udon/input-events/): move,
  look, jump, use, grab, and drop are platform-independent actions which honor
  user remapping. This is the right model for world-facing TunnelXR actions.
- [Player audio](https://creators.vrchat.com/worlds/udon/players/player-audio/):
  the listener can alter another player's voice gain, near/far distance,
  volumetric radius, and low-pass behavior, independently from avatar audio.
- [Pickups](https://creators.vrchat.com/worlds/components/vrc_pickup/): pickup
  affordance and network synchronization are separate concerns; local pickup
  motion is not automatically visible remotely without object sync.

For TunnelXR, voice packets remain exclusively TwoVoIP's responsibility. A
world may supply acoustic presentation policy—range, spatialization, zones, or
radio-like modes—but it must not send, receive, encode, or route voice packets.

## Proposed TunnelXR contract

The world should declare what a player may do and how virtual placement behaves.
It should not reach into the implementation of the XR rig. The player runtime
reads the declaration and applies it to its own body, locomotion providers, and
`XROrigin3D`.

### 1. Arrival profile

Each `WorldFrame` should expose one typed `WorldPlayerProfile` resource. This is
preferable to loose node metadata because it is inspectable, validated,
documented, reusable, and can grow without stringly-typed lookups.

The complete reference set is:

| Group | Candidate settings | Notes |
| --- | --- | --- |
| Spawn | spawn points, selection order, radius, player/room alignment | Placement policy, not tracking data |
| Fall/respawn | fall threshold, respawn target, retain velocity, pickup policy | Threshold may be disabled for unbounded survey spaces |
| Gravity | enabled, scale, optional direction | Start with scalar scale; add vectors only when a real use requires them |
| Ground locomotion | walk, run, strafe, acceleration, braking, slope and step limits | Player body owns the implementation |
| Jump/fall | jump enabled, impulse, terminal speed, air control | Zero gravity should normally disable jump |
| Locomotion mode | ground, fly, noclip, immobilized | `fly` and `gravity_scale = 0` are related but not synonymous |
| Collision body | enabled, capsule/radius policy, crouch behavior | Derived from embodiment where possible; never from arbitrary avatar mesh bounds |
| Scale | manual scale allowed, minimum/maximum eye height, initial scale | Keep physical tracking measurements separate |
| Turning/comfort | smooth/snap allowed, snap increment, vignette recommendation | User safety/accessibility choice should win over a mere world preference |
| Interaction | point, select, grab, use, climb, teleport, haptics, collision layers | Expose semantic capabilities, not controller buttons |
| Camera | near/far clip and presentation recommendations | Must not move the tracked head pose |
| Voice acoustics | spatial range, attenuation preset, region/broadcast policy | Consumed by TwoVoIP presentation; transport remains in TwoVoIP |

The first implementation should not implement this entire table. It only needs
the fields demanded by the current world: spawn, fall/respawn behavior,
`gravity_scale`, locomotion mode, and movement speed. The table prevents those
first fields from being placed in an abstraction that cannot grow coherently.

### 2. Regional overrides

A `WorldAffordanceVolume` should be an authored `Area3D` containing a typed,
partial profile override plus a priority. Examples include:

- zero-gravity or low-gravity chambers;
- fly/noclip regions for cave surveying;
- water, wind, conveyor, or moving-platform regions;
- areas that permit climbing or disable jumping;
- voice attenuation, echo, private-conversation, or broadcast regions;
- interaction restrictions around fragile or streamed geometry; and
- entry into a station, vehicle, or guided experience.

Volumes should not save “the old gravity” on entry and restore it on exit.
That fails when volumes overlap, are disabled while occupied, or are crossed by
teleport. Instead, the player runtime maintains active overrides by stable
source ID and recomputes one effective profile.

A deterministic initial composition rule is:

1. Begin with application-safe defaults.
2. Apply the `WorldPlayerProfile`.
3. Apply all overlapping volume patches sorted by priority and stable source ID.
4. Apply a modal station/vehicle override if present.
5. Apply transient commands such as impulses separately; do not store them as
   persistent profile values.
6. Clamp the result to platform limits and non-negotiable user safety settings.

For the small first version, the highest-priority value wins for each field.
Later, explicitly marked multipliers can compose multiplicatively. Avoid
implicit averaging and avoid ambiguous boolean merging.

### 3. Commands rather than persistent settings

Some effects are events and should not be put in the profile:

- teleport or respawn;
- add impulse or set velocity;
- attach to or detach from a station/vehicle;
- recenter virtual placement;
- begin/end a time-limited effect; and
- haptic feedback.

Commands need a source, timestamp or physics tick, and an idempotency key where
network retries are possible.

## Cave-mapping profile

Simply setting gravity to zero is insufficient. It stops falling but provides
no vertical control, and a player who enters with velocity may continue to
drift. The cave-mapping world's default should be a coherent flying profile:

```text
locomotion_mode       = FLY
gravity_scale         = 0.0
jump_enabled          = false
fall_respawn_enabled  = false
collision_enabled     = true       # choose NOCLIP explicitly when needed
initial_velocity      = zero       # on mode transition, not every frame
```

If only part of a grounded world is zero gravity, put the same patch on a
`WorldAffordanceVolume`. On leaving, recomputation naturally reveals the world
default instead of restoring a stale cached value.

`FLY` should retain collision and permit vertical semantic movement. `NOCLIP`
is a separate survey/debug mode which passes through geometry. Keeping these
separate avoids making “gravity off” accidentally mean “walls off.”

## Ownership and networking boundary

The local player owns input and locomotion simulation. World state may decide
which affordance volumes exist, but every client applies their effective
profile to its own local player. Networking publishes the result; it does not
run another user's XR body.

```text
XRServer + trackers
        |
        v
     XR-human              real observations: head, hands, trackers
        |
        v
Local NetworkPlayer        timestamped observations for replication

World profile/volumes
        |
        v
PlayerBody + locomotion    virtual physics and controls
        |
        v
     XROrigin3D            virtual placement in WorldFrame
        |
        v
Local NetworkPlayer        timestamped world placement for replication
```

World gravity, flight, teleportation, and stations act on the lower placement
path. They must never rewrite XR-human observations. A remote player/avatar can
then combine replicated physical observations with replicated virtual
placement in exactly the same way, without confusing locomotion with a real
body movement.

The same rule applies without networking: `MainSoloXR` runs both paths locally
and simply has no publisher. `MainSolo` supplies a lightweight desktop
`PlayerInterface` or spectator controller and need not instantiate XR-human.

## Minimal Godot-facing interface

Names remain provisional, but the dependency direction should look like this:

```gdscript
# Supplied by WorldFrame; contains data only.
func get_player_profile() -> WorldPlayerProfile

# Implemented by the local player runtime, not by the world.
func apply_world_profile(profile: WorldPlayerProfile) -> void
func set_affordance(source_id: StringName, patch: WorldPlayerProfilePatch) -> void
func clear_affordance(source_id: StringName) -> void
func teleport_in_world(target: Transform3D, options: Dictionary = {}) -> void
func apply_world_impulse(impulse: Vector3) -> void
```

The runtime should resolve profiles during `_physics_process`, before movement
is integrated. Volumes identify the local player's physics body, not head or
hand tracker nodes. On world unmount, the runtime clears every override from
that world and returns to application defaults.

An arrival sequence should be explicit:

1. Mount the `WorldFrame`.
2. Read and validate its arrival profile.
3. Select a spawn and establish virtual placement.
4. Apply body/locomotion settings locally.
5. Reconcile currently overlapping affordance volumes.
6. Mark the local player ready and, if networked, begin publishing placement
   and observations.

## Recommended first slice

1. Add the otherwise-trivial `MainSoloXR` composition without changing the
   existing local XR rig.
2. Add a small `WorldPlayerProfile` with only locomotion mode, gravity scale,
   speed, spawn, and fall-respawn fields.
3. Have the XR player runtime consume that resource before its first physics
   integration.
4. Give the cave world the flying profile above.
5. Add one debug `WorldAffordanceVolume` that changes gravity/mode and prove
   overlapping-volume restoration.
6. Mount exactly the same world and XR player beneath the networked shell; only
   then test that local results replicate correctly.

This establishes the seam needed now without inventing the eventual PlayerBody,
XR-human, avatar, or game-rule systems in advance.

