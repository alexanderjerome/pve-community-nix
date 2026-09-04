{ ... }:
{
  fleet.catalog.apps.jellyfin = {
    title = "Jellyfin";
    description = "Free Software Media System";
    upstream = { url = "https://jellyfin.org/"; repo = "jellyfin/jellyfin"; license = "GPL-2.0"; };
    impl = "nixos-service";
    nixModule = "jellyfin";
    status = "ported";
  };
}
