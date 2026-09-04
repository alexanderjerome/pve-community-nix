{ lib, ... }:
# NixOS side of the catalog. `apps.base` is the always-present layer every
# mkApp host enables; each subdirectory is one `apps.<name>` module,
# inert unless enabled. Pass this file to mkFleet's globalModules.
let
  dirs = lib.filter (n: !(lib.hasPrefix "_" n))
    (lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./.)));
in
{
  imports = [ ./_base.nix ] ++ map (d: ./. + "/${d}") dirs;
}
