# Fleet-wide facts every mkApp host inherits (preset < hostDefaults <
# per-host compute). Keep it empty until a fact is true for ALL app hosts.
{ ... }:
{
  config.fleet.catalog.hostDefaults = {
    # # Every app container on the LAN bridge with a static address
    # # (then each host sets `ip`, not `internal_ip`):
    # network_mode = "single-external";

    # # systemd >= 260 fails its per-service credentials tmpfs inside an
    # # unprivileged user namespace (status=243/CREDENTIALS); until PVE and
    # # NixOS settle that, a fleet can run its app containers privileged:
    # privileged = true;

    # # Your own NixOS LXC template and the pool it lives on:
    # image = "local:vztmpl/my-nixos-lxc.tar.xz";
    # root_disk_datastore = "local-lvm";
  };
}
