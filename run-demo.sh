#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin="$project_dir/bin/libGodot3DTiles.linux.template_release.x86_64.so"
nixpkgs_ref="github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41"
terrain_pid=""
terrain_dir="${TUNNELXR_LOCAL_TERRAIN_DIR:-$project_dir/.local-terrain}"

if [[ "${TUNNELXR_USE_LOCAL_TERRAIN:-0}" == "1" && -z "${TUNNELXR_LOCAL_TERRAIN_URL:-}" && -f "$terrain_dir/tileset.json" ]]; then
	# Pick an unused loopback port by default. A stale preview used to make the
	# fixed port fail while Godot carried on with only the ion terrain visible.
	terrain_port="${TUNNELXR_TERRAIN_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
	python3 -m http.server "$terrain_port" --bind 127.0.0.1 --directory "$terrain_dir" >/tmp/tunnelxr-terrain-server.log 2>&1 &
	terrain_pid="$!"
	for _ in {1..50}; do
		if ! kill -0 "$terrain_pid" 2>/dev/null; then
			printf '%s\n' "Local terrain server failed to start:" >&2
			cat /tmp/tunnelxr-terrain-server.log >&2
			exit 1
		fi
		if python3 -c 'import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=0.2).read(1)' "http://127.0.0.1:$terrain_port/tileset.json" 2>/dev/null; then
			break
		fi
		sleep 0.1
	done
	export TUNNELXR_LOCAL_TERRAIN_URL="http://127.0.0.1:$terrain_port/tileset.json"
fi

cleanup() {
	if [[ -n "$terrain_pid" ]]; then
		kill "$terrain_pid" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

# Keep the conventional upstream binary's native dependencies local to the
# plugin. Exporting them process-wide breaks NixOS's OpenGL driver selection.
if [[ ! -e "$project_dir/.native-libraries/lib" ]]; then
	# Use the Git-filtered flake source so ignored runtime datasets such as the
	# 1.5 GB local terrain are never copied into the Nix store.
	nix build "git+file://$project_dir#native-libraries" \
		--out-link "$project_dir/.native-libraries" >/dev/null
fi
nix shell "$nixpkgs_ref#patchelf" --command patchelf \
	--set-rpath '$ORIGIN/../.native-libraries/lib' "$plugin"

# A fresh clone has no Godot import cache. Run one editor filesystem scan so
# Godot registers the GDExtension classes before main.gd is parsed.
if [[ ! -f "$project_dir/.godot/extension_list.cfg" ]]; then
	printf '%s\n' "First run: registering the Cesium GDExtension..."
	nix shell "$nixpkgs_ref#godot_4_6" --command godot4 \
		--headless --editor --path "$project_dir" --quit-after 4
fi

nix shell "$nixpkgs_ref#godot_4_6" --command godot4 --path "$project_dir" "$@"
