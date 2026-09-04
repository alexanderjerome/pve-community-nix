{ ... }:
{
  fleet.catalog.apps.jellyfin = {
    title = "Jellyfin";
    description = "Free Software Media System";
    category = "media";
    upstream = { url = "https://jellyfin.org/"; repo = "jellyfin/jellyfin"; license = "GPL-2.0"; };
    port = 8096;
    defaults = { cpu_cores = 2; memory_mb = 2048; root_disk_gb = 16; };
    devices.gpu = true;
    arch = [ "x86_64" "aarch64" ];
    impl = "planned";
    legacy = { ct = "legacy/ct/jellyfin.sh"; install = "legacy/install/jellyfin-install.sh"; os = "ubuntu"; osVersion = "24.04"; };
  };
}
