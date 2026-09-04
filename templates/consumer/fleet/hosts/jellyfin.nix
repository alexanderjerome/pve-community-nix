# One file per app host. mkApp reads the catalog preset (cores, RAM,
# disk, privileged, device flags, port) and you supply only what is
# specific to your fleet: placement, VMID, address. Everything the
# preset set can still be overridden here.
catalog:
catalog.lib.mkApp {
  app = "jellyfin";
  # name = "media";                 # fleet.compute key + hostname (default: app)
  compute = {
    env = "home"; stack = "media";
    provider_instance = "proxmox.main";
    vm_id = 120;
    node = "pve1";
    internal_ip = "192.0.2.120";
    root_disk_datastore = "local-lvm";
    # cpu_cores = 4;                # override the preset's default
    # devices = [ … ];              # concrete /dev passthrough (see docs)
  };
  nixos = {
    time.timeZone = "Etc/UTC";      # the legacy `var_timezone`, now NixOS-side
    # apps.base.ingress = true;     # publish via Caddy at jellyfin.<internal domain>
  };
}
