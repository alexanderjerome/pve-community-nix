{ config, lib, ... }:

# apps.jellyfin — tier 1 (nixos-service): wraps upstream services.jellyfin.
# The legacy install/jellyfin-install.sh added the Jellyfin apt repo,
# jellyfin-ffmpeg, and Intel/AMD hwaccel userland; on NixOS the package
# ships its ffmpeg and infra.platform.pve.lxc.gpu.enable brings the
# graphics userland when the host passes /dev/dri through.

let
  cfg = config.apps.jellyfin;
  preset = config.fleet.catalog.apps.jellyfin;
in
{
  options.apps.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server (catalog app)";
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/jellyfin";
      description = "Jellyfin state directory (library database, metadata, plugins).";
    };
    hardwareAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = config.infra.platform.pve.lxc.gpu.enable;
      defaultText = lib.literalExpression "config.infra.platform.pve.lxc.gpu.enable";
      description = "Add the jellyfin user to the video/render groups so /dev/dri passthrough (mkApp { gpu = …; }) is usable for transcoding. Defaults to on whenever the host has GPU passthrough.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      # Jellyfin's HTTP port is fixed by its own config; the catalog port
      # is what apps.base registers, so they must agree.
      assertion = config.apps.base.port == preset.port;
      message = "apps.jellyfin: apps.base.port must stay ${toString preset.port} (Jellyfin's HTTP port is configured inside its own settings).";
    }];

    services.jellyfin = {
      enable = true;
      dataDir = cfg.dataDir;
      openFirewall = false;   # apps.base opens the registered port
    };

    users.users.jellyfin.extraGroups = lib.mkIf cfg.hardwareAcceleration [ "video" "render" ];
  };
}
