# From community-scripts to the catalog

## What a script did, and what replaces it

| community-scripts | pve-community-nix |
|---|---|
| `bash -c "$(curl -fsSL …/ct/<app>.sh)"` on the PVE shell | one `fleet/hosts/<app>.nix` file calling `catalog.lib.mkApp`, then `fleet deploy tf apply` + `fleet deploy nixos apply` |
| Default / Advanced whiptail wizard, `default.vars`, `<app>.vars`, `var_*` env | `fleet.compute.<host>` options (see fleetkit's *compute surface* page); presets in `fleet.catalog.apps.<app>` |
| `pveam` template download + `pct create` | fleetkit's NixOS LXC template + the bpg/proxmox Terraform provider |
| `install/<app>-install.sh` inside a Debian/Alpine guest | `apps.<app>` NixOS module (tiers below) |
| `/usr/bin/update` + `update_script()` | `fleet deploy nixos apply host <name>` (colmena) |
| `tools/pve/*.sh` host tweaks | `fleet.settings.providers.proxmox.hostTweaks` → `fleet ansible run pve` |
| `tools/addon/*.sh` | ordinary catalog apps or fleetkit `infra.*` modules |
| `vm/*.sh` appliance VMs | `impl = "image"` presets: a `download` resource + `image = "import:…"` |
| telemetry, PocketBase status guard | none |

## Wizard steps → options

| Step | Option |
|---|---|
| Container type (privileged) | `compute.privileged` (preset `privileged`) |
| Root password / autologin / SSH root | not applicable — key-only NixOS hosts (`fleet.network.sysadmin_ssh_key`) |
| Container ID | `compute.vm_id` |
| Hostname | `name` (mkApp) |
| Disk / cores / RAM | `compute.root_disk_gb` / `cpu_cores` / `memory_mb` (preset defaults) |
| Bridge or SDN vnet | `compute.interfaces[].bridge` / `.vnet` with `network_mode = "declared"` |
| IPv4 dhcp / static, gateway | `interfaces[].ipv4`, `.gateway` (or `internal_ip` in the default single-internal mode) |
| IPv6 | `interfaces[].ipv6.method` |
| MTU / DNS search / DNS server / MAC / VLAN | `interfaces[].mtu`, `compute.dns.domain`, `compute.dns.servers`, `interfaces[].mac`, `interfaces[].vlan` |
| Tags | `compute.tags` (preset adds category + `community-catalog`) |
| FUSE / TUN / nesting / GPU / keyctl / mknod / mount fs | `features.*` and `devices` (preset flags + `mkApp { gpu; coral; usbSerial }`) |
| APT cacher / HTTP proxy / host CA | NixOS `nix.settings.substituters`, `networking.proxy`, `security.pki` in `nixos = { … }` |
| Timezone | `nixos.time.timeZone` |
| Protection | `compute.protection` |
| Post-install hook | `compute.hook_script` or NixOS activation |
| Verbose | not applicable |

## Implementation tiers

| `impl` | Meaning | Pilot |
|---|---|---|
| `nixos-service` | wraps an upstream `services.*` module | `jellyfin` |
| `package-systemd` | nixpkgs package + a systemd unit written here | `rustypaste` |
| `oci` | `virtualisation.oci-containers` on a Docker-enabled NixOS host | `dockge` |
| `image` | appliance VM image, no NixOS inside | `opnsense-vm` |
| `planned` | preset only; mkApp deploys the base host | most entries |
| `unsupported` | cannot be a NixOS host (with a reason) | bare OS templates, PVE tooling |

`forgejo` is the second `nixos-service` pilot, on the tier-2 list of apps
whose upstream module needs more wiring (database, domain, secrets).
