{
  description = "Reproducible runtime for the Godot Cesium laptop preview";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.android_sdk.accept_license = true;
      };
      androidSdk = (pkgs.androidenv.composeAndroidPackages {
        platformVersions = [ "35" ];
        buildToolsVersions = [ "35.0.0" "35.0.1" ];
        includeNDK = false;
      }).androidsdk;
    in {
      devShells.${system} = {
        terrain = pkgs.mkShell {
          packages = [
            pkgs.survex
            (pkgs.python3.withPackages (pythonPackages: with pythonPackages; [
              numpy
              pyproj
              rasterio
            ]))
          ];
        };

        native = pkgs.mkShell {
          packages = [
            pkgs.cmake
            pkgs.curl
            pkgs.git
            pkgs.ninja
            pkgs.openssl
            pkgs.patchelf
            pkgs.pkg-config
            pkgs.python3
            pkgs.scons
          ];
        };
      };

      packages.${system} = {
        native-libraries = pkgs.symlinkJoin {
          name = "godot-cesium-native-libraries";
          paths = [
            (pkgs.lib.getLib pkgs.curl)
            pkgs.stdenv.cc.cc.lib
          ];
        };

        android-sdk = androidSdk;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = toString (pkgs.writeShellScript "godot-cesium-preview" ''
            exec ${pkgs.godot_4_6}/bin/godot4 "$@"
          '');
        };

        patch-plugin = {
          type = "app";
          program = "${pkgs.patchelf}/bin/patchelf";
        };
      };
    };
}
