# pve-community-nix

A declarative NixOS application catalog for Proxmox VE, built on
[fleetkit](https://github.com/alexanderjerome/fleetkit).

The community-scripts installers asked questions in a terminal and ran
`pct create` by hand. Here the same knowledge is data:

- **`fleet.catalog.apps.<name>`** — one preset per application: cores,
  RAM, disk, privileged, device flags, port, upstream, and how it is
  realised on NixOS (`impl`).
- **`mkApp`** — turns a preset plus your placement (VMID, node, IP) into a
  `fleet.compute` entry (provisioned by terranix → OpenTofu through
  fleetkit's bpg/proxmox emitter) and a NixOS host (deployed by colmena).
- **`apps.<name>`** — the NixOS module that runs the application, enabled
  per host by `mkApp`; `apps.base` is the layer every catalog host has.

Every guest is NixOS. There are no prompts, no `.vars` files, and no
runtime downloads from `main`.

Start from the consumer template:

```sh
nix flake init -t github:alexanderjerome/pve-community-nix#consumer
```
