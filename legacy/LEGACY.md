# legacy/ — the original community-scripts tree

Moved here verbatim (git history preserved) when the repository was
rewritten as a declarative NixOS catalog. Nothing in this directory is
maintained, tested, or executed by CI; it exists so that app modules can
be written side by side with the installer they replace.

- `ct/*.sh` — host-side launchers: the `var_*` header is the preset
  (see `tools/extract-legacy-metadata.py`), the trailing banner is the port.
- `install/*-install.sh` — in-guest installers: the spec for tier-4
  (`package-systemd`) modules.
- `misc/*.func` — the wizard and helpers. Their configuration surface is
  mapped to fleetkit options in `PLAN.md`, Appendix A.
- `tools/pve/*.sh` — hypervisor tweaks, ported to ansible in fleetkit.
- `vm/*.sh`, `turnkey/` — appliance VMs and TurnKey (image imports / out of scope).

Upstream's `.github/` (workflows, issue templates, PocketBase bots) is not
kept: none of it applies to a Nix catalog. What replaces it is
`.github/workflows/upstream-apps.yml`, which diffs upstream against this
tree and opens issues for new, changed and removed scripts, and the
`port-upstream-app` skill that turns such an issue into a preset + module.
When a port lands, the upstream `ct/` and `install/` scripts it was ported
from are copied here so the extractor and future diffs see them — the one
sanctioned way this directory grows.

Deletion criterion: every catalog entry has `impl != "planned"` or a
documented `unsupportedReason`.
