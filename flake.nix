{
  description = "nwww - niri-swww wallpaper wrapper with overlay blur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Pull swww directly for namespace feature
    swww = {
      url = "github:LGFae/swww";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, swww, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = { pkgs, system, ... }:
        let
          swwwPkg = swww.packages.${system}.default;
        in {
          packages.default = pkgs.stdenv.mkDerivation {
            pname = "nwww";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              mkdir -p $out/bin
              cp nwww.sh $out/bin/nwww
              chmod +x $out/bin/nwww
              wrapProgram $out/bin/nwww \
                --prefix PATH : ${pkgs.lib.makeBinPath [ swwwPkg pkgs.imagemagick pkgs.vips ]}
            '';
          };
        };
    };
}
