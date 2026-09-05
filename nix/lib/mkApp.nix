{ lib }:
# mkApp — expand a catalog preset into one app host.
#
#   imports = [ (catalog.lib.mkApp {
#     app     = "jellyfin";                # key into fleet.catalog.apps
#     name    = "media";                   # fleet.compute key + hostname (default: app)
#     compute = { vm_id = 120; node = "pve1"; internal_ip = "192.0.2.120";
#                 provider_instance = "proxmox.main"; env = "home"; stack = "media"; };
#     nixos   = { time.timeZone = "Europe/Berlin"; };   # extra NixOS config
#     gpu     = "intel";                   # intel | amd | nvidia — realises the preset's
#                                          # devices.gpu flag as /dev entries (null = no GPU)
#     coral   = false;                     # pass /dev/apex_0 when the preset can use it
#     usbSerial = false;                   # pass /dev/ttyUSB*/ttyACM* when the preset can use them
#   }) ];
#
# Produces:
#   fleet.compute.<name>       — kind/cores/RAM/disk/privileged/features from
#                                the preset, then fleet.catalog.hostDefaults
#                                (fleet-wide facts), then `compute` (per host)
#   fleet.hostsRegistry.<name> — apps.base.app = <app>; apps.<app>.enable = true
#                                (only when the preset carries a NixOS module)
#
# Everything the preset provides is overridable; nothing is prompted.
{ app, name ? app, compute, nixos ? {}, gpu ? null, coral ? false, usbSerial ? false }:
{ config, lib, ... }:
let
  devices = import ./devices.nix { inherit lib; };
  presets = config.fleet.catalog.apps;
  preset = presets.${app} or (throw
    "mkApp: no catalog entry \"${app}\" (known: ${lib.concatStringsSep ", " (lib.attrNames presets)})");
  unsupported = preset.impl == "unsupported";
in
{
  # `throw` on the compute VALUE, not `assertions` (this module is also
  # evaluated by fleetkit's plain fleet eval, which has no `assertions`
  # option) and not around the whole `config` (attribute names of a
  # module's config may never depend on config — infinite recursion).
  config = {
    fleet.compute.${name} = lib.throwIf unsupported
      "mkApp \"${app}\": catalog entry is impl = \"unsupported\" (${preset.unsupportedReason}). It cannot be deployed as a NixOS host."
    ({
      kind = lib.mkDefault preset.kind;
      cpu_cores = lib.mkDefault preset.defaults.cpu_cores;
      memory_mb = lib.mkDefault preset.defaults.memory_mb;
      swap_mb = lib.mkDefault preset.defaults.swap_mb;
      root_disk_gb = lib.mkDefault preset.defaults.root_disk_gb;
      privileged = lib.mkDefault preset.privileged;
      # Community rule: keyctl only on unprivileged CTs (build.func:4394).
      features = {
        nesting = lib.mkDefault true;
        fuse = lib.mkDefault preset.devices.fuse;
        keyctl = lib.mkDefault (!preset.privileged);
      };
      tags = lib.mkDefault ([ "community-catalog" preset.category ] ++ preset.tags);
      devices = lib.mkDefault (devices.forPreset { inherit preset coral; gpuVendor = gpu; usbSerial' = usbSerial; });
      notes = lib.mkDefault "${preset.title} — from the pve-community-nix catalog (upstream: ${preset.upstream.url})";
    } // compute);

    # The app's own module is switched on by apps.base (static keys there;
    # `apps.${preset.nixModule}` here would make this attrset's names
    # depend on config).
    # Appliance images (impl = "image") carry no NixOS: no host registry
    # entry, so colmena never targets them.
    fleet.hostsRegistry = lib.optionalAttrs (preset.impl != "image") {
      ${name} = { ... }: {
        imports = [ nixos ];
        apps.base.app = app;
        apps.base.enable = true;
        infra.platform.pve.lxc.gpu.enable = lib.mkIf (gpu != null && preset.devices.gpu) true;
      };
    };
  };
}
