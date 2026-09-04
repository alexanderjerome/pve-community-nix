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

Deletion criterion: every catalog entry has `impl != "planned"` or a
documented `unsupportedReason`.
