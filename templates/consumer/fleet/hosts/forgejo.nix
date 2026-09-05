# The LAN-only shape: one NIC on the LAN bridge (vmbr0) with a static
# address and the LAN gateway — no internal bridge at all. Pair it with
# `fleet.network.lan_gateway`. jellyfin.nix shows the internal-bridge
# shape; a fleet normally uses one or the other, set once in
# fleet/catalog.nix (hostDefaults.network_mode) rather than per host.
catalog:
catalog.lib.mkApp {
  app = "forgejo";
  compute = {
    env = "home"; stack = "apps";
    provider_instance = "proxmox.main";
    vm_id = 130;
    node = "pve1";
    network_mode = "single-external";
    ip = "192.0.2.130"; internal_ip = "";
    root_disk_datastore = "local-lvm";
  };
  nixos = {
    apps.forgejo.domain = "git.example.lan";
  };
}
