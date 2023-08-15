{
  description = "A https://flakehub.com/ pusher.";

  inputs = {
    nixpkgs.url = "https://api.flakehub.com/f/NixOS/nixpkgs/0.1.514192.tar.gz";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = forSystems supportedSystems;
      forDockerSystems = forSystems [ "x86_64-linux" ];

      forSystems = s: f: inputs.nixpkgs.lib.genAttrs s (system: f rec {
        inherit system;
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.self.overlays.default
            inputs.rust-overlay.overlays.default
          ];
        };
        lib = pkgs.lib;
      });
    in
    {
      overlays.default = final: prev: {
        flakehub-push = inputs.self.packages.${final.stdenv.system}.flakehub-push;
      };


      packages = forAllSystems ({ system, pkgs, lib, ... }:
        let
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            targets = [ "x86_64-unknown-linux-musl" ];
          };
        in
        rec {
          default = flakehub-push;

          flakehub-push = craneLib.buildPackage {
            pname = "flakehub-push";
            version = "0.1.0";
            src = craneLib.path ./.;

            CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
            CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
          };
        });

      devShells = forAllSystems ({ system, pkgs, ... }: {
        default = pkgs.mkShell {
          name = "dev";
          buildInputs = with pkgs; [
            nixpkgs-fmt
            rustfmt
            cargo-outdated
            cargo-watch
            rust-analyzer
            rustc
            cargo
          ]
          ++ inputs.self.packages.${system}.flakehub-push.buildInputs;

          nativeBuildInputs = with pkgs; [
          ]
          ++ inputs.self.packages.${system}.flakehub-push.nativeBuildInputs;
        };
      });


      dockerImages = forDockerSystems ({ system, pkgs, ... }: {
        default = pkgs.dockerTools.buildLayeredImage {
          name = pkgs.flakehub-push.name;
          contents = [ pkgs.cacert ];
          config = {
            #ExposedPorts."8080/tcp" = { };
            Cmd = [ "${pkgs.flakehub-push}/bin/flakehub-push" ];
            Env = [
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      });
    };
}
