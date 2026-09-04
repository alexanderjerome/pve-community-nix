{ config, lib, pkgs, ... }:

# apps.rustypaste — tier 4 (package-systemd): nixpkgs packages rustypaste
# but ships no NixOS module, so this module is the declarative form of
# legacy/install/rustypaste-install.sh: the binary, a config.toml with
# the listen address, a state directory, and a hardened systemd unit
# under a dedicated user (the legacy unit ran as root from /opt).

let
  cfg = config.apps.rustypaste;
  preset = config.fleet.catalog.apps.rustypaste;
  settingsFormat = pkgs.formats.toml { };
  configFile = settingsFormat.generate "rustypaste-config.toml" cfg.settings;
in
{
  options.apps.rustypaste = {
    enable = lib.mkEnableOption "rustypaste minimal pastebin (catalog app)";
    package = lib.mkPackageOption pkgs "rustypaste" { };
    port = lib.mkOption {
      type = lib.types.port;
      default = preset.port;
      defaultText = lib.literalExpression "config.fleet.catalog.apps.rustypaste.port";
      description = "HTTP port rustypaste listens on.";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/rustypaste";
      description = "Upload storage directory.";
    };
    settings = lib.mkOption {
      type = settingsFormat.type;
      default = { };
      example = lib.literalExpression ''{ paste.default_expiry = "24h"; server.max_content_length = "100MB"; }'';
      description = "rustypaste config.toml contents (merged over the catalog defaults: listen address, upload path). See https://github.com/orhun/rustypaste/blob/master/config.toml.";
    };
  };

  config = lib.mkIf cfg.enable {
    apps.base.port = lib.mkDefault cfg.port;

    apps.rustypaste.settings = {
      server = {
        address = lib.mkDefault "0.0.0.0:${toString cfg.port}";
        upload_path = lib.mkDefault cfg.dataDir;
        max_content_length = lib.mkDefault "10MB";
      };
      paste = {
        random_url = lib.mkDefault { type = "petname"; words = 2; separator = "-"; };
        default_extension = lib.mkDefault "txt";
        duplicate_files = lib.mkDefault true;
      };
    };

    users.users.rustypaste = { isSystemUser = true; group = "rustypaste"; home = cfg.dataDir; };
    users.groups.rustypaste = { };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 rustypaste rustypaste -" ];

    systemd.services.rustypaste = {
      description = "rustypaste pastebin";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment.CONFIG = configFile;
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package}";
        User = "rustypaste";
        Group = "rustypaste";
        WorkingDirectory = cfg.dataDir;
        Restart = "always";
        # Hardening (none of this existed in the legacy unit).
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };
  };
}
