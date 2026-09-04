{ config, lib, ... }:

# apps.dockge — tier 3 (oci): the app IS a Docker orchestrator, so it runs
# as an OCI container on a NixOS host with Docker (the legacy
# tools/addon/dockge.sh ran `docker compose up` from upstream's
# compose.yaml). Needs an LXC with nesting (mkApp's default).
#
# The image is pulled at activation time by tag — the one impure step of
# this tier; pin `image` to a digest for reproducible hosts.

let
  cfg = config.apps.dockge;
  preset = config.fleet.catalog.apps.dockge;
in
{
  options.apps.dockge = {
    enable = lib.mkEnableOption "Dockge compose stack manager (catalog app, OCI)";
    image = lib.mkOption {
      type = lib.types.str;
      default = "louislam/dockge:1";
      description = "Container image (tag or digest).";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = preset.port;
      defaultText = lib.literalExpression "config.fleet.catalog.apps.dockge.port";
      description = "Host port the web UI is published on.";
    };
    stacksDir = lib.mkOption {
      type = lib.types.path;
      default = "/opt/stacks";
      description = "Directory holding the compose stacks Dockge manages (must be the same path inside and outside the container).";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/dockge";
      description = "Dockge's own state (users, settings).";
    };
  };

  config = lib.mkIf cfg.enable {
    apps.base.port = lib.mkDefault cfg.port;

    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.dockge = {
      image = cfg.image;
      ports = [ "${toString cfg.port}:5001" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "${cfg.dataDir}:/app/data"
        "${cfg.stacksDir}:${cfg.stacksDir}"
      ];
      environment.DOCKGE_STACKS_DIR = cfg.stacksDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.stacksDir} 0755 root root -"
    ];
  };
}
