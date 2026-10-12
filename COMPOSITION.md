# TunnelXR

This is the thin networked TunnelXR assembly. `MainNetworking.tscn` combines
the reusable networking/XR shell with the independently runnable TunnelXR
WorldFrame. The world and networking peers remain separately editable.

Create the development workspace links with:

```sh
godot4 --headless --path . --script plug.gd status
godot4 --headless --path . --script plug.gd link
godot4 --headless --path . --script plug.gd status strict
godot4 --headless --import --xr-mode off --path .
godot4 --headless --path . --script plug.gd unlink
```

`link` warns when a peer is dirty or differs from its declared commit. Adding
`strict` prevents link creation when a revision differs. Generated links are
ignored by Git. On Windows the same command creates directory junctions.

Run the initial imports serially when composing more than one project. Godot
may write `.import` and `.uid` sidecars beside resources reached through a
link. That makes links excellent for scripts and scenes under active tandem
development, but risky for shared binary assets or generated plugin caches:
two projects can disagree about those sidecars. The first-look composer leaves
this visible instead of silently overwriting or cleaning either peer. A mature
composer should support a per-mount `link` or `copy` policy.

Editor plugins are disabled in the assembly. The previous gd-plug UI expects
the original gd-plug API and is intentionally not enabled by this composer.
