# Your fleet manifest — the single entry point mkFleet evals. Everything
# under this directory is DATA; the schema and validators live in fleetkit
# (nix/fleet/) and the catalog (pve-community-nix/nix/fleet/).
#
# `catalog` is the pve-community-nix flake, passed in from flake.nix so
# host files can call catalog.lib.mkApp.
{ catalog }:
{ ... }:
{
  imports = [
    catalog.fleetModules.catalog
    ./settings.nix
    ./network.nix
    ./providers.nix
    ./users.nix
    ./dns.nix
    (import ./hosts/jellyfin.nix catalog)
  ];
}
