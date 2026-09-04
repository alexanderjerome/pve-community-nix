{
  # pve-community-nix — a declarative NixOS application catalog for
  # Proxmox VE, built on fleetkit.
  #
  # fleetkit owns the ENGINE (fleet manifest schema, terranix → OpenTofu
  # emitters for the bpg/proxmox provider, the NixOS LXC/VM images, colmena
  # deploys, SOPS, the `fleet` CLI, ansible for the hypervisors). This repo
  # owns the CATALOG: per-app presets (`fleet.catalog.apps.<name>`), the
  # `mkApp` helper that turns a preset into a fleet.compute entry plus a
  # NixOS host, the `apps.<name>` NixOS modules, PVE-host tooling, and a
  # consumer template. It replaces the bash/whiptail installers that now
  # live, unmaintained, under legacy/.
  #
  # Consumer wiring (see templates/consumer/flake.nix):
  #   fleetkit.lib.mkFleet {
  #     modules       = [ ./fleet catalog.fleetModules.catalog ];
  #     globalModules = [ catalog.nixosModules.catalog ];
  #     …
  #   }
  # and one file per app host:
  #   imports = [ (catalog.lib.mkApp { app = "jellyfin"; compute = { vm_id = 120; … }; }) ];

  inputs = {
    fleetkit.url = "git+https://github.com/alexanderjerome/fleetkit?ref=claude/proxmox-nix-rewrite-plan-qx16ru&shallow=1";
    nixpkgs.follows = "fleetkit/nixpkgs";
  };

  outputs = { self, fleetkit, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    lib = nixpkgs.lib;

    catalogLib = import ./nix/lib { inherit lib; };
  in
  {
    lib = {
      # mkApp { app; name ? app; compute; nixos ? {}; } → fleet module
      inherit (catalogLib) mkApp;
    };

    # Fleet-schema side: the catalog schema (fleet.catalog.apps.*) plus
    # every preset under nix/catalog/. Pure data — safe in fleetkit's
    # fleet eval (no pkgs, no NixOS options).
    fleetModules.catalog = ./nix/fleet;

    # NixOS side: the always-on app base layer (apps.base.*) plus every
    # app module (apps.<name>.*), inert unless enabled by mkApp.
    nixosModules.catalog = ./nix/modules/apps;

    packages.${system} = rec {
      docs = import ./docs { inherit pkgs nixpkgs fleetkit; };
      options-json = docs.passthru.optionsJSON;
      # The catalog as JSON — the eval-free surface the `fleet apps` CLI
      # extension and the docs generator read (fleetkit convention: Nix
      # data reaches the CLI through built artifacts, never `nix eval`).
      catalog-json = pkgs.writeText "catalog.json"
        (builtins.toJSON (catalogLib.evalCatalog { fleetSchema = fleetkit.nixosModules.fleetSchema; catalogModules = ./nix/fleet; }));
      default = catalog-json;
    };

    templates.consumer = {
      path = ./templates/consumer;
      description = "fleetkit consumer with the pve-community-nix catalog: one PVE provider, one app host.";
    };

    checks.${system} = import ./nix/checks.nix {
      inherit pkgs nixpkgs fleetkit self;
    };
  };
}
