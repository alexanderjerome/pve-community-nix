# pve-community-nix

**A declarative NixOS application catalog for Proxmox VE, built on
[fleetkit](https://github.com/alexanderjerome/fleetkit).**

This repository started as a fork of
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE):
~590 bash installers driven by whiptail prompts, creating Debian and
Alpine containers with `pct create` on the hypervisor. It is being
rewritten so that the same knowledge is *data* and every guest is NixOS:

| community-scripts                            | pve-community-nix                                             |
|----------------------------------------------|---------------------------------------------------------------|
| `bash -c "$(curl …/ct/jellyfin.sh)"`         | `catalog.lib.mkApp { app = "jellyfin"; compute = { … }; }`     |
| whiptail wizard, `default.vars`, `var_*` env  | `fleet.compute.<host>` options (fleetkit schema)               |
| `pct create` on the PVE shell                 | terranix → OpenTofu, bpg/proxmox provider                     |
| Debian/Alpine template + `install/*.sh`       | NixOS LXC template + `apps.<name>` NixOS module (colmena)      |
| `tools/pve/*.sh` host tweaks                  | ansible roles (fleetkit `proxmox/*`) driven by fleet settings  |
| `/usr/bin/update` in every container          | `fleet deploy nixos apply`                                     |

## Layout

```
flake.nix               inputs.fleetkit; lib.mkApp; fleetModules.catalog; nixosModules.catalog
nix/fleet/              fleet.catalog.apps schema (+ loads nix/catalog/)
nix/catalog/<app>.nix   one preset per application — pure data
nix/lib/                mkApp, device presets, evalCatalog
nix/modules/apps/       apps.base (always on) + apps.<name> modules
templates/consumer/     a complete consumer fleet with one mkApp host
docs/                   mdBook options + catalog reference
tools/                  extract-legacy-metadata.py (legacy headers → presets)
legacy/                 the original bash tree — unmaintained, no CI, read-only
PLAN.md                 the rewrite plan and its phases
```

## Getting started

```sh
nix flake init -t github:alexanderjerome/pve-community-nix#consumer
# edit fleet/*.nix (providers, network, settings) and fleet/hosts/*.nix
fleet deploy tf apply home-media        # provision the container(s)
fleet deploy nixos apply host jellyfin  # deploy NixOS onto it
```

Requires **Proxmox VE 9.x** (the NixOS LXC setup plugin makes first boot
zero-touch) and the fleetkit toolchain (`nix develop`).

## Validation

```sh
nix flake check     # catalog-schema · example-consumer · tf-render · docs
nix build .#docs    # options + catalog site
nix build .#catalog-json
```

## License

MIT, as upstream. Each catalog entry records the upstream project's own
license in `upstream.license`.
