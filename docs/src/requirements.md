# Requirements

- **Proxmox VE 9.x.** First boot of a NixOS container is zero-touch only
  because PVE 9 ships `PVE::LXC::Setup::NixOS`, which writes the guest's
  `eth0.network` from the container's `net0 ip=/gw=` at create time.
  PVE 8 is not supported.
- **fleetkit** as the engine (pinned as a flake input).
- An S3-compatible bucket for OpenTofu state and an age key for SOPS —
  see fleetkit's documentation.
