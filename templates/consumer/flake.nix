{
  # pve-community-nix consumer. Copy with:
  #   nix flake init -t github:alexanderjerome/pve-community-nix/nix#consumer
  #
  # Layout:
  #   flake.nix        — this file: mkFleet wiring + output re-export
  #   fleet/           — YOUR manifest: settings, providers, network,
  #                      users, dns data, and one mkApp file per host
  #   fleet.toml       — CLI-side settings (bucket, domains, key paths)
  #   cli-ext/         — `fleet apps …` (reads the catalog JSON)
  #   nix/secrets/     — SOPS store (create with `fleet secrets init`)

  inputs = {
    catalog.url = "github:alexanderjerome/pve-community-nix/nix";
    fleetkit.follows = "catalog/fleetkit";
    nixpkgs.follows = "fleetkit/nixpkgs";
  };

  outputs = { self, catalog, fleetkit, nixpkgs }:
  let
    fleet = fleetkit.lib.mkFleet {
      # Manifest modules — the catalog schema + presets come in through
      # fleet/default.nix.
      modules = [ (import ./fleet { inherit catalog; }) ];
      backend = {
        bucket = "REPLACE-ME-tofu";     # S3(-compatible) tofu state bucket
        # region = "us-east-1";
      };
      # NixOS modules applied to every host: the catalog's apps.* modules
      # (inert until mkApp enables one) plus your own.
      globalModules = [ catalog.nixosModules.catalog ];
      hostExtraModules = { };
      # secretsFile = ./nix/secrets/secrets.yaml;
    };
  in
  {
    inherit (fleet) colmena nixosConfigurations fleetManifest fleetAccess;

    packages.x86_64-linux = fleet.packages // {
      fleet = fleetkit.packages.x86_64-linux.fleet;
      default = fleetkit.packages.x86_64-linux.fleet;
      catalog-json = catalog.packages.x86_64-linux.catalog-json;
    };

    devShells.x86_64-linux.default = fleetkit.devShells.x86_64-linux.default;
  };
}
