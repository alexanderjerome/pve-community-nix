{ ... }:
# Fleet-schema side of the catalog: the `fleet.catalog.apps` option
# schema plus every preset under nix/catalog/. Pure data — evaluated by
# fleetkit's fleet eval AND by every NixOS host eval, so nothing here may
# reference pkgs or NixOS options.
{
  imports = [ ./catalog.nix ../catalog ];
}
