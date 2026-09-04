{ config, lib, ... }:

# apps.base — the layer every catalog host carries (enabled by mkApp).
# Replaces what the legacy install.func did after the app installer:
# the MOTD banner (→ /etc/fleet/services.json + a login notice), the
# open port, and the PVE Notes URL. No passwords, no autologin: NixOS
# hosts are key-only and colmena-managed.

let
  cfg = config.apps.base;
  preset = config.fleet.catalog.apps.${cfg.app};
in
{
  options.apps.base = {
    enable = lib.mkEnableOption "the catalog app base layer (set by mkApp)";
    app = lib.mkOption {
      type = lib.types.str;
      example = "jellyfin";
      description = "Catalog key of the app this host runs (mkApp sets it). Drives the service registry entry and the login banner.";
    };
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = preset.port;
      defaultText = lib.literalExpression "config.fleet.catalog.apps.<app>.port";
      description = "Port registered for the app (firewall + optional Caddy vhost). Defaults to the preset's port.";
    };
    ingress = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also publish the app through the host's Caddy (infra.ingress) at <app>.<fleet.settings.domain.internal>. Requires that domain to be set.";
    };
    banner = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Print the app name and URL at login (the declarative twin of the legacy MOTD).";
    };
  };

  config = lib.mkMerge [
    # Enable the module that implements the host's app. Keys come from
    # the catalog (a different option tree), so this stays acyclic; the
    # catalog-schema check guarantees every nixModule has a module dir.
    {
      apps = lib.mkMerge (lib.mapAttrsToList
        (n: e: { ${e.nixModule}.enable = lib.mkIf (cfg.enable && cfg.app == n) true; })
        (lib.filterAttrs (_: e: e.nixModule != null) config.fleet.catalog.apps));
    }
    (lib.mkIf cfg.enable {
    assertions = [{
      assertion = !cfg.ingress || config.fleet.settings.domain.internal != null;
      message = "apps.base.ingress is set on ${cfg.app} but fleet.settings.domain.internal is null — set the internal domain or disable ingress.";
    }];

    infra.services.${cfg.app} = lib.mkIf (cfg.port != null) {
      port = cfg.port;
      extraPorts = map (p: { port = p; }) preset.extraPorts;
      description = if preset.description != "" then preset.description else preset.title;
      category = preset.category;
      tags = [ "community-catalog" ] ++ preset.tags;
      caddy.enable = cfg.ingress;
    };

    users.motd = lib.mkIf cfg.banner ''
      ${preset.title} (pve-community-nix catalog)
      ${lib.optionalString (cfg.port != null && config.infra.networking.internalIp != "") "http://${config.infra.networking.internalIp}:${toString cfg.port}"}
      upstream: ${preset.upstream.url}
    '';
  })
  ];
}
