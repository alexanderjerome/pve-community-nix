{ lib }:
# Catalog library — pure functions over the fleet schema.
{
  mkApp = import ./mkApp.nix { inherit lib; };

  # Evaluate the catalog schema + data on its own (no hosts, no
  # providers) and return fleet.catalog.apps as a plain attrset. Used by
  # packages.catalog-json and the catalog-schema check.
  evalCatalog = { fleetSchema, catalogModules }:
    (lib.evalModules {
      modules = [ fleetSchema catalogModules ];
    }).config.fleet.catalog.apps;
}
