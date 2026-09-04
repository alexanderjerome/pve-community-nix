# Options documentation site (mdBook), same shape as fleetkit's docs/:
# one NixOS eval over fleetkit's modules + schema plus this repo's
# fleet.catalog schema and apps.* modules; only options DECLARED in this
# repo are rendered (fleetkit's own live on its site).
#
#   nix build .#docs        → static site in result/
#   nix build .#options-json

{ pkgs, nixpkgs, fleetkit, lib ? pkgs.lib }:

let
  catalogRoot = toString ../.;
  githubBase = "https://github.com/alexanderjerome/pve-community-nix/blob/main";
  fkInputs = fleetkit.inputs;

  eval = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      fkInputs.sops-nix.nixosModules.sops
      fkInputs.disko.nixosModules.disko
      fleetkit.nixosModules.default
      fleetkit.nixosModules.fleetSchema
      ../nix/fleet
      ../nix/modules/apps
      {
        fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
        boot.loader.grub.enable = false;
        system.stateVersion = "24.05";
      }
    ];
  };

  isOurs = opt:
    lib.any (d: lib.hasPrefix catalogRoot (toString d)) opt.declarations;

  optionsDoc = pkgs.nixosOptionsDoc {
    options = eval.options;
    warningsAreErrors = true;
    transformOptions = opt:
      opt
      // { visible = (opt.visible or true) && isOurs opt; }
      // {
        declarations = map (d:
          let rel = lib.removePrefix (catalogRoot + "/") (toString d);
          in if lib.hasPrefix catalogRoot (toString d)
             then { name = rel; url = "${githubBase}/${rel}"; }
             else d)
          opt.declarations;
      };
  };

  catalogJson = pkgs.writeText "catalog.json"
    (builtins.toJSON eval.config.fleet.catalog.apps);

in pkgs.stdenv.mkDerivation {
  name = "pve-community-nix-docs";
  passthru.optionsJSON = optionsDoc.optionsJSON;
  src = ./.;
  nativeBuildInputs = [ pkgs.mdbook pkgs.python3 ];
  buildPhase = ''
    python3 generate.py ${optionsDoc.optionsJSON}/share/doc/nixos/options.json ${catalogJson} src
    mdbook build
  '';
  installPhase = ''
    mv book $out
  '';
}
