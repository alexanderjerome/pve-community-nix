# Flake checks — the catalog's acceptance gates (mirrors fleetkit's
# philosophy: every check proves an end-to-end contract).
#
#   * catalog-schema   — every preset under nix/catalog/ evaluates against
#                        the fleet.catalog.apps schema; every entry that
#                        names a nixModule has a directory under
#                        nix/modules/apps/ and vice versa; the JSON export builds.
#   * example-consumer — fleetkit.lib.mkFleet over templates/consumer/fleet
#                        (an mkApp host on one PVE provider) assembles a
#                        deployable host: hostsJson, stack ids, and the
#                        NixOS toplevel derivation of every host (evaluated,
#                        not built). A preset or module that grows a new
#                        required setting fails here.
#   * tf-render        — every leaf stack of the example consumer renders
#                        to valid Terraform JSON.
#   * docs             — the options site builds with warningsAreErrors:
#                        every option this repo declares has a description.
#   * ported-apps      — one mkApp host per catalog entry with a nixModule
#                        (status ported/verified), all on the template's
#                        provider: every app module's ENABLED config path
#                        evaluates to a NixOS toplevel and renders Terraform.
#                        A module that only evaluates while disabled cannot
#                        pass this.

{ pkgs, nixpkgs, fleetkit, self }:

let
  lib = pkgs.lib;
  catalog = self;

  example = fleetkit.lib.mkFleet {
    modules = [ (import ../templates/consumer/fleet { inherit catalog; }) ];
    globalModules = [ catalog.nixosModules.catalog ];
    backend = { bucket = "example-tofu"; };
  };

  catalogJson = self.packages.${pkgs.system}.catalog-json;

  # Every ported entry as an mkApp host (deterministic VMIDs/IPs).
  catalogData = (import ../nix/lib { inherit lib; }).evalCatalog {
    fleetSchema = fleetkit.nixosModules.fleetSchema; catalogModules = ../nix/fleet;
  };
  ported = lib.attrNames (lib.filterAttrs (_: e: e.nixModule != null || e.impl == "image") catalogData);
  portedHosts = lib.imap0 (i: app: catalog.lib.mkApp {
    inherit app;
    name = "pilot-${app}";
    compute = {
      env = "pilot"; stack = "apps"; provider_instance = "proxmox.main";
      vm_id = 900 + i; node = "pve1"; internal_ip = "192.0.2.${toString (150 + i)}";
      root_disk_datastore = "local-lvm";
    } // lib.optionalAttrs (catalogData.${app}.impl == "image") {
      image = "import:local:import/${app}.img";
    };
    gpu = if catalogData.${app}.devices.gpu then "intel" else null;
  }) ported;
  pilots = fleetkit.lib.mkFleet {
    modules = [ (import ../templates/consumer/fleet { inherit catalog; }) ] ++ portedHosts;
    globalModules = [ catalog.nixosModules.catalog ];
    backend = { bucket = "example-tofu"; };
  };
  appsDir = ../nix/modules/apps;
  moduleDirs = lib.attrNames
    (lib.filterAttrs (n: t: t == "directory" && !(lib.hasPrefix "_" n)) (builtins.readDir appsDir));

in {
  catalog-schema = pkgs.runCommand "catalog-schema-check" {
    nativeBuildInputs = [ pkgs.jq ];
    inherit catalogJson;
    moduleDirs = lib.concatStringsSep " " moduleDirs;
  } ''
    test -s "$catalogJson"
    echo "catalog entries: $(jq 'length' "$catalogJson")"
    for m in $(jq -r 'to_entries[] | select(.value.nixModule != null) | .value.nixModule' "$catalogJson"); do
      case " $moduleDirs " in
        *" $m "*) ;;
        *) echo "catalog entry references nixModule \"$m\" but nix/modules/apps/$m/ does not exist"; exit 1 ;;
      esac
    done
    for d in $moduleDirs; do
      jq -e --arg d "$d" 'to_entries | any(.value.nixModule == $d)' "$catalogJson" > /dev/null \
        || { echo "nix/modules/apps/$d/ exists but no catalog entry sets nixModule = \"$d\""; exit 1; }
    done
    touch $out
  '';

  # The toplevel drvPaths are passed through unsafeDiscardOutputDependency
  # so the check EVALUATES every host (the whole module stack must close)
  # without BUILDING the systems — a fully built NixOS closure per app is
  # not what this gate proves and would dwarf the rest of CI.
  example-consumer = pkgs.runCommand "catalog-example-consumer-check" {
    hostsJson = example.packages.hostsJson;
    stackIds = example.packages.tf-stack-ids;
    toplevels = lib.concatStringsSep "\n"
      (lib.mapAttrsToList
        (n: c: "${n} ${builtins.unsafeDiscardOutputDependency c.config.system.build.toplevel.drvPath}")
        example.nixosConfigurations);
  } ''
    test -s "$hostsJson"
    test -s "$stackIds"
    echo "$toplevels"
    touch $out
  '';

  tf-render = pkgs.runCommand "catalog-example-tf-render" {
    nativeBuildInputs = [ pkgs.jq ];
    renders = lib.attrValues
      (lib.filterAttrs (n: _: lib.hasPrefix "tf-" n && n != "tf-stack-ids") example.packages);
  } ''
    for r in $renders; do
      jq -e 'has("resource") or has("data") or has("provider")' "$r" > /dev/null \
        || { echo "render $r is not Terraform JSON"; exit 1; }
    done
    touch $out
  '';

  docs = self.packages.${pkgs.system}.docs;

  ported-apps = pkgs.runCommand "catalog-ported-apps-check" {
    nativeBuildInputs = [ pkgs.jq ];
    apps = lib.concatStringsSep " " ported;
    hostsJson = pilots.packages.hostsJson;
    renders = lib.attrValues
      (lib.filterAttrs (n: _: lib.hasPrefix "tf-" n && n != "tf-stack-ids") pilots.packages);
    toplevels = lib.concatStringsSep "\n"
      (lib.mapAttrsToList
        (n: c: "${n} ${builtins.unsafeDiscardOutputDependency c.config.system.build.toplevel.drvPath}")
        pilots.nixosConfigurations);
  } ''
    echo "ported apps: $apps"
    for r in $renders; do
      jq -e 'has("resource")' "$r" > /dev/null || { echo "render $r is not Terraform JSON"; exit 1; }
    done
    echo "$toplevels"
    touch $out
  '';
}
