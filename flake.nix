{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    zig.url = "github:mitchellh/zig-overlay";
    zls-master = {
      url = "github:zigtools/zls";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, flake-utils, nixpkgs, zig, zls-master }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = (import nixpkgs) {
          inherit system;
        };
      in {
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            pkg-config gtk4
            #zig
            zig.packages.${system}.master
            librsvg zls-master.packages.${system}.default
          ];
        };
      }
    );
}
