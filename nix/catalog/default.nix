{ lib, ... }:
# Auto-import every preset. Two layers, both pure data:
#   generated/<app>.nix — written by tools/extract-legacy-metadata.py from
#                         the legacy shell headers; every value is
#                         lib.mkDefault so it never fights curation.
#                         Regenerate freely.
#   <app>.nix           — hand-curated additions/overrides (module name,
#                         impl, status, description, corrections).
let
  nixFiles = dir: map (f: dir + "/${f}")
    (lib.filter (f: f != "default.nix" && lib.hasSuffix ".nix" f)
      (lib.attrNames (builtins.readDir dir)));
in
{
  imports = nixFiles ./. ++ nixFiles ./generated;
}
