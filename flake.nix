{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = nixpkgs.legacyPackages;

      makePackage = system:
        let pkgs = pkgsFor.${system};
        in pkgs.stdenv.mkDerivation {
          name = "website";
          src = pkgs.lib.cleanSource ./.;
          nativeBuildInputs = [ pkgs.zig pkgs.git ];
          buildPhase = ''
            mkdir -p .cache
            zig build --global-cache-dir .cache --prefix $out
          '';
          installPhase = "true"; # nothing to do, already installed to prefix
        };
    in {
      packages = forAllSystems (system: { default = makePackage system; });

      devShells = forAllSystems (system:
        let pkgs = pkgsFor.${system};
        in { default = pkgs.mkShell { buildInputs = [ pkgs.zig ]; }; });

      nixosModule = { pkgs, config, lib, ... }: {
        options.services.website.enable = lib.mkEnableOption "Enable website";

        config = lib.mkIf config.services.website.enable {
          services.caddy = {
            enable = true;
            virtualHosts."francisco.wiki".extraConfig = ''
              root * ${self.packages.${pkgs.stdenv.hostPlatform.system}.default}
              encode
              file_server
            '';
          };

          networking.firewall.allowedTCPPorts = [ 80 443 ];
        };
      };
    };
}
