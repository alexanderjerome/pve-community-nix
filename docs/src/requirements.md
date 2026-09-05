# Requirements

- **Proxmox VE 9.x.** First boot of a NixOS container is zero-touch only
  because PVE 9 ships `PVE::LXC::Setup::NixOS`, which writes the guest's
  `eth0.network` from the container's `net0 ip=/gw=` at create time.
  PVE 8 is not supported.
- **fleetkit** as the engine (pinned as a flake input).
- An S3-compatible bucket for OpenTofu state and an age key for SOPS —
  see fleetkit's documentation.

## Known constraint: privileged containers

NixOS guests on current nixos-unstable ship systemd 260, which fails to
set up its per-service credentials tmpfs inside an unprivileged user
namespace (`status=243/CREDENTIALS`, breaking journald, networkd and
logind). Until PVE or NixOS resolves it, run app containers privileged
fleet-wide with `fleet.catalog.hostDefaults.privileged = true` (see the
consumer template's `fleet/catalog.nix`). Presets keep their upstream
`privileged` value for the day it is no longer needed.
