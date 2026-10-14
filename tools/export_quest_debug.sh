#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
nixpkgs_ref="github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41"
android_sdk="${TUNNELXR_ANDROID_SDK:-}"
config_root="$project_dir/.quest-godot-config"
data_root="$project_dir/.quest-godot-data"
keystore="$config_root/debug.keystore"
output="$project_dir/exports/quest3/TunnelXR-HTerrain-debug.apk"
openxr_vendors_version="5.1.0-stable"
openxr_vendors_sha256="6a838dbdf4115549e4511ebee0da9a5dcc8f9f6258d4cc2f2ee57a907a3e2911"
openxr_vendors_dir="$project_dir/addons/godotopenxrvendors"

templates="$(nix build --no-link --print-out-paths "$nixpkgs_ref#godot_4_6-export-templates-bin")"
jdk="$(nix build --no-link --print-out-paths "$nixpkgs_ref#jdk17")"
jdk_home="$jdk/lib/openjdk"
if [[ -z "$android_sdk" ]]; then
	android_sdk_package="$(nix build --no-link --print-out-paths "git+file://$project_dir#android-sdk")"
	for candidate in \
		"$android_sdk_package/libexec/android-sdk" \
		"$android_sdk_package/share/android-sdk" \
		"$android_sdk_package"; do
		if [[ -d "$candidate/platform-tools" && -d "$candidate/build-tools" ]]; then
			android_sdk="$candidate"
			break
		fi
	done
fi
if [[ ! -d "$android_sdk/platform-tools" || ! -d "$android_sdk/build-tools" ]]; then
	printf 'Android SDK root is invalid: %s\n' "$android_sdk" >&2
	exit 1
fi
template_dir="$templates/share/godot/export_templates/4.6.stable"
android_source="$template_dir/android_source.zip"

if [[ ! -f "$openxr_vendors_dir/plugin.gdextension" ]]; then
	archive="$(mktemp --suffix=.zip)"
	staging="$(mktemp -d)"
	trap 'rm -rf -- "$archive" "$staging"' EXIT
	curl -fL \
		"https://github.com/GodotVR/godot_openxr_vendors/releases/download/$openxr_vendors_version/godotopenxrvendorsaddon.zip" \
		-o "$archive"
	printf '%s  %s\n' "$openxr_vendors_sha256" "$archive" | sha256sum --check --status
	(cd "$staging" && "$jdk_home/bin/jar" xf "$archive")
	mkdir -p "$project_dir/addons"
	cp -a "$staging/asset/addons/godotopenxrvendors" "$project_dir/addons/"
fi

if [[ ! -f "$project_dir/android/build/build.gradle" ]]; then
	mkdir -p "$project_dir/android/build"
	(cd "$project_dir/android/build" && "$jdk_home/bin/jar" xf "$android_source")
	printf '4.6.stable\n' >"$project_dir/android/.build_version"
elif [[ "$(cat "$project_dir/android/.build_version" 2>/dev/null)" != "4.6.stable" ]]; then
	printf 'The generated Android build template does not match Godot 4.6.stable.\n' >&2
	exit 1
fi

aapt2_override="android.aapt2FromMavenOverride=$android_sdk/build-tools/35.0.1/aapt2"
if grep -q '^android\.aapt2FromMavenOverride=' "$project_dir/android/build/gradle.properties"; then
	sed -i "s|^android\.aapt2FromMavenOverride=.*|$aapt2_override|" "$project_dir/android/build/gradle.properties"
else
	printf '\n# Use the Nix-linked binary instead of Gradle\x27s generic Linux executable.\n%s\n' \
		"$aapt2_override" >>"$project_dir/android/build/gradle.properties"
fi

mkdir -p "$config_root/godot" "$data_root/godot/export_templates" "$(dirname -- "$output")"
ln -sfn "$template_dir" "$data_root/godot/export_templates/4.6.stable"

if [[ ! -f "$keystore" ]]; then
	"$jdk_home/bin/keytool" -genkeypair -keystore "$keystore" -storepass android \
		-alias androiddebugkey -keypass android -dname "CN=Android Debug,O=TunnelXR,C=GB" \
		-keyalg RSA -keysize 2048 -validity 10000 >/dev/null
fi

sed \
	-e "s|@ANDROID_SDK@|$android_sdk|g" \
	-e "s|@JAVA_SDK@|$jdk_home|g" \
	-e "s|@DEBUG_KEYSTORE@|$keystore|g" \
	"$project_dir/tools/quest_editor_settings.tres.in" \
	>"$config_root/godot/editor_settings-4.6.tres"

ANDROID_HOME="$android_sdk" ANDROID_SDK_ROOT="$android_sdk" JAVA_HOME="$jdk_home" \
	XDG_CONFIG_HOME="$config_root" XDG_DATA_HOME="$data_root" \
nix shell "$nixpkgs_ref#godot_4_6" --command godot4 --headless \
	--path "$project_dir" --export-debug "Quest 3 Debug" "$output"

printf 'Quest debug APK: %s\n' "$output"
