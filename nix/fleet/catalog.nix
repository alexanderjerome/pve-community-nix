{ lib, ... }:

# Schema for fleet.catalog.apps — one entry per application the catalog
# knows how to deploy. Entries are DATA: what the legacy `ct/<app>.sh`
# header (`var_*` block) and its `install/<app>-install.sh` encoded as
# shell defaults, made declarative. mkApp (nix/lib/mkApp.nix) reads an
# entry to seed a fleet.compute host; the app's NixOS module reads it for
# its port and identity; `fleet apps` and the docs read the JSON export.
#
# Every field carries a description (docs check) and RFC5737/example.com
# values in examples. No site values — those live in the consumer's
# fleet.settings / fleet.compute overrides.

let
  inherit (lib) mkOption types;

  upstreamOpts = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        example = "https://jellyfin.org/";
        description = "Project homepage (rendered in the PVE Notes panel and the docs).";
      };
      repo = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "jellyfin/jellyfin";
        description = "Source repository as \"owner/repo\" (GitHub unless `repoHost` says otherwise). null when the project publishes no repository.";
      };
      repoHost = mkOption {
        type = types.enum [ "github" "gitlab" "codeberg" "other" ];
        default = "github";
        description = "Forge hosting `repo`. Mirrors the legacy fetch_and_deploy_{gh,gl,codeberg}_release split.";
      };
      license = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "GPL-2.0";
        description = "SPDX identifier of the upstream project's license (informational; the catalog entry itself is MIT like the rest of this repo).";
      };
    };
  };

  defaultsOpts = types.submodule {
    options = {
      cpu_cores = mkOption { type = types.int; default = 2; description = "Default vCPU count for a host running this app (legacy `var_cpu`)."; };
      memory_mb = mkOption { type = types.int; default = 2048; description = "Default RAM in MiB (legacy `var_ram`)."; };
      swap_mb = mkOption { type = types.int; default = 512; description = "Default swap in MiB (LXC only; the legacy scripts never set swap, PVE defaulted to 512)."; };
      root_disk_gb = mkOption { type = types.int; default = 4; description = "Default root disk in GiB (legacy `var_disk`)."; };
    };
  };

  devicesOpts = types.submodule {
    options = {
      gpu = mkOption { type = types.bool; default = false; description = "App benefits from /dev/dri (and /dev/kfd, /dev/nvidia*) passthrough — legacy `var_gpu=yes`. mkApp turns this into the host's device list once the consumer picks a vendor preset."; };
      tun = mkOption { type = types.bool; default = false; description = "App needs /dev/net/tun (VPN / mesh software) — legacy `var_tun=yes`."; };
      fuse = mkOption { type = types.bool; default = false; description = "App needs FUSE mounts inside the container — legacy `var_fuse=yes`."; };
      usbSerial = mkOption { type = types.bool; default = false; description = "App talks to USB serial adapters (Zigbee/Z-Wave sticks); legacy scripts bind /dev/ttyUSB*, /dev/ttyACM*, /dev/serial/by-id on privileged CTs."; };
      coral = mkOption { type = types.bool; default = false; description = "App can use a Coral TPU (/dev/apex_0) when the host has one."; };
    };
  };

  legacyOpts = types.submodule {
    options = {
      ct = mkOption { type = types.nullOr types.str; default = null; example = "legacy/ct/jellyfin.sh"; description = "Path of the host-side installer this entry was extracted from (repo-relative, under legacy/)."; };
      install = mkOption { type = types.nullOr types.str; default = null; example = "legacy/install/jellyfin-install.sh"; description = "Path of the in-guest installer (the de-facto spec for a tier-4 module)."; };
      os = mkOption { type = types.nullOr types.str; default = null; example = "debian"; description = "Guest OS the legacy installer targeted (`var_os`). Informational: every catalog host is NixOS."; };
      osVersion = mkOption { type = types.nullOr types.str; default = null; example = "13"; description = "Guest OS version the legacy installer targeted (`var_version`)."; };
      updateable = mkOption { type = types.bool; default = true; description = "Whether the legacy script had a real in-place `update_script`. false = the app was updated through its own UI or not at all. Informational: NixOS hosts update through colmena."; };
    };
  };

  appType = types.submodule ({ name, ... }: {
    options = {
      title = mkOption {
        type = types.str;
        default = name;
        defaultText = lib.literalExpression "<attribute name>";
        example = "Jellyfin";
        description = "Human-readable application name (legacy `APP=`).";
      };
      description = mkOption {
        type = types.str;
        default = "";
        example = "Free software media system";
        description = "One-line description shown by `fleet apps list` and in the docs.";
      };
      category = mkOption {
        type = types.str;
        default = "misc";
        example = "media";
        description = "Primary category (first legacy `var_tags` entry): media, monitoring, network, arr, automation, database, …";
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "media" "streaming" ];
        description = "Additional tags (remaining legacy `var_tags` entries). Added to the PVE tags of every host mkApp creates.";
      };
      upstream = mkOption {
        type = upstreamOpts;
        description = "Where the software comes from.";
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        example = 8096;
        description = "Primary web/API port (from the legacy success banner `http://<IP>:<port>`). null = no listening service (CLI tools, bare OS).";
      };
      extraPorts = mkOption {
        type = types.listOf types.port;
        default = [];
        example = [ 8920 ];
        description = "Additional ports the app listens on that hosts should open.";
      };
      defaults = mkOption {
        type = defaultsOpts;
        default = {};
        description = "Resource defaults mkApp seeds fleet.compute with (all overridable per host).";
      };
      kind = mkOption {
        type = types.enum [ "container" "vm" ];
        default = "container";
        description = "Guest type mkApp creates: an LXC container (every legacy `ct/` app) or a KVM VM (the legacy `vm/` appliances and anything that needs its own kernel).";
      };
      privileged = mkOption {
        type = types.bool;
        default = false;
        description = "Legacy `var_unprivileged=0`: the app needs a privileged LXC (hardware access, kernel features). mkApp seeds `privileged` and clears keyctl accordingly.";
      };
      devices = mkOption {
        type = devicesOpts;
        default = {};
        description = "Device passthrough the app can use. Each flag becomes concrete `/dev` entries through the vendor presets in nix/lib/devices.nix.";
      };
      arch = mkOption {
        type = types.listOf (types.enum [ "x86_64" "aarch64" ]);
        default = [ "x86_64" ];
        example = [ "x86_64" "aarch64" ];
        description = "CPU architectures the app supports (legacy `var_arm64=yes` ⇒ both).";
      };
      impl = mkOption {
        type = types.enum [ "planned" "nixos-service" "package-systemd" "oci" "image" "unsupported" ];
        default = "planned";
        description = ''
          How the app is (or will be) realised on NixOS:
          - planned: preset only, no module yet (mkApp deploys the base host)
          - nixos-service: wraps an upstream `services.*` NixOS module
          - package-systemd: a nixpkgs/catalog package + systemd unit
          - oci: `virtualisation.oci-containers` (Docker-only upstreams)
          - image: an appliance VM image (no NixOS inside; provisioning only)
          - unsupported: cannot be a NixOS host (closed source with no Linux
            build, PVE-ecosystem tooling, bare-OS templates); mkApp refuses it
        '';
      };
      unsupportedReason = mkOption {
        type = types.str;
        default = "";
        example = "bare Debian template — declare a plain fleet.compute host instead";
        description = "Why `impl = \"unsupported\"` (rendered in the error mkApp raises and in the docs).";
      };
      nixModule = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "jellyfin";
        description = "Name of the `apps.<name>` NixOS module that implements this app (a directory under nix/modules/apps/). null until the module exists; mkApp enables `apps.<nixModule>` when set.";
      };
      status = mkOption {
        type = types.enum [ "planned" "ported" "verified" ];
        default = "planned";
        description = "planned = data only; ported = module exists and evaluates in CI; verified = deployed and exercised on a real PVE 9 node.";
      };
      legacy = mkOption {
        type = legacyOpts;
        default = {};
        description = "Traceability back to the shell scripts this entry replaces.";
      };
    };
  });
in
{
  options.fleet.catalog.apps = mkOption {
    type = types.attrsOf appType;
    default = {};
    example = lib.literalExpression ''
      {
        jellyfin = {
          title = "Jellyfin"; category = "media"; port = 8096;
          upstream = { url = "https://jellyfin.org/"; repo = "jellyfin/jellyfin"; license = "GPL-2.0"; };
          defaults = { cpu_cores = 2; memory_mb = 2048; root_disk_gb = 8; };
          devices.gpu = true;
          impl = "nixos-service"; nixModule = "jellyfin"; status = "ported";
        };
      }
    '';
    description = "The application catalog: one preset per app, keyed by the app slug. Populated by nix/catalog/*.nix; consumers may add or override entries in their own fleet modules.";
  };
}
