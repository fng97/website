{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zls-overlay.url = "github:zigtools/zls?ref=0.15.0";
    zls-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      zig-overlay,
      zls-overlay,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forSupportedSystems = nixpkgs.lib.genAttrs supportedSystems;
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            zig-overlay.overlays.default
            (final: prev: {
              zig = final.zigpkgs."0.15.1";
              zls = zls-overlay.packages.${system}.default;
            })
          ];
        };
    in
    {
      devShells = forSupportedSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              zig
              zls
              pandoc
              validator-nu
            ];
          };
        }
      );
    };
}
