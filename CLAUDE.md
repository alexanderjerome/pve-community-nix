# CLAUDE.md — pve-community-nix development

Read [AGENTS.md](./AGENTS.md) first, then fleetkit's CLAUDE.md gotchas
(untracked files are invisible to flake eval; option descriptions are
static strings; derived defaults need `defaultText`; feature-gate new
required settings).

## Validation loop

```bash
nix flake check                 # catalog-schema · example-consumer · tf-render · docs
nix build .#docs
nix build .#catalog-json
```

Iterate against a local fleetkit with
`--override-input fleetkit path:/path/to/fleetkit`.

## Adding an app

1. Preset: `nix/catalog/<app>.nix` (or regenerate from legacy headers with
   `tools/extract-legacy-metadata.py`).
2. Module: `nix/modules/apps/<app>/default.nix` following the seven-part
   shape of fleetkit's infra modules (`options.apps.<app>`, `mkEnableOption`,
   descriptions everywhere, site values from `fleet.settings.*`,
   assertions, `sopsLib.mkSecret` for secrets, `infra.services` registration).
3. Set `impl` + `nixModule` + `status = "ported"` in the preset.
4. `git add -N` new files, `nix flake check`, commit.

## Conventions

- Option namespace mirrors the tree: `apps.<name>` ↔ `nix/modules/apps/<name>/`.
- Hosts are created only through `mkApp`; the template shows the shape.
- Docs: `docs/generate.py` renders options + catalog; hand-written pages
  in `docs/src/`.
