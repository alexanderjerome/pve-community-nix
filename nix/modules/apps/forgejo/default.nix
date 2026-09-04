{ config, lib, ... }:

# apps.forgejo — tier 2 (nixos-service with wiring): wraps upstream
# services.forgejo. The legacy installer fetched the binary from Codeberg
# and wrote an app.ini with sqlite; here the upstream module owns the
# unit, the state dir and the database, and the catalog supplies the
# port, domain and root URL from fleet data.

let
  cfg = config.apps.forgejo;
  preset = config.fleet.catalog.apps.forgejo;
  domain = config.fleet.settings.domain.internal;
  hostName = config.networking.hostName;
  fqdn = if cfg.domain != null then cfg.domain
         else if domain != null then "${hostName}.${domain}"
         else hostName;
in
{
  options.apps.forgejo = {
    enable = lib.mkEnableOption "Forgejo git forge (catalog app)";
    port = lib.mkOption {
      type = lib.types.port;
      default = preset.port;
      defaultText = lib.literalExpression "config.fleet.catalog.apps.forgejo.port";
      description = "HTTP port Forgejo listens on.";
    };
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "git.example.internal";
      description = "Public name Forgejo advertises (server.DOMAIN / ROOT_URL). null = <hostname>.<fleet.settings.domain.internal>, or the bare hostname when no internal domain is set.";
    };
    database = lib.mkOption {
      type = lib.types.enum [ "sqlite3" "postgres" ];
      default = "sqlite3";
      description = "Database backend. sqlite3 matches the legacy installer; postgres uses the host-local PostgreSQL the upstream module provisions.";
    };
    lfs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Git LFS.";
    };
  };

  config = lib.mkIf cfg.enable {
    apps.base.port = lib.mkDefault cfg.port;

    services.forgejo = {
      enable = true;
      database.type = cfg.database;
      lfs.enable = cfg.lfs;
      settings = {
        server = {
          DOMAIN = fqdn;
          HTTP_PORT = cfg.port;
          HTTP_ADDR = "0.0.0.0";
          ROOT_URL = if config.apps.base.ingress then "https://${fqdn}/" else "http://${fqdn}:${toString cfg.port}/";
        };
        service.DISABLE_REGISTRATION = true;
      };
    };
  };
}
