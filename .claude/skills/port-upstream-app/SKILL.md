---
name: port-upstream-app
description: Work an `upstream-app` issue — a new, changed or removed community-scripts application — into this Nix catalog (preset + module), run the checks, and open a PR that closes the issue. Use when asked to port an upstream app, sync the catalog with upstream, or process upstream-app issues.
---

# Port an upstream community-scripts app

Issues labelled `upstream-app` are filed by `.github/workflows/upstream-apps.yml`
(`tools/upstream-diff.py`). Each names one script and carries links to the
upstream `ct/<slug>.sh` and `install/<slug>-install.sh` at a pinned commit
plus the extracted preset. This skill turns one issue into a merged
change. Iron rules in `AGENTS.md` apply throughout; `CLAUDE.md` has the
validation loop.

## 0. Pick the issue

```bash
gh issue list --label upstream-app --state open --json number,title,labels
gh issue view <n>
```

One issue per PR. `upstream:removed` and `upstream:changed` issues are
usually quick; `upstream:new` is a real port.

## 1. Bring the legacy copies in

`legacy/` is read-only except for this step: mirror the upstream scripts
the issue points at, at the commit it names, so the extractor and later
diffs see them.

```bash
sha=<commit from the issue>
curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/$sha/ct/<slug>.sh -o legacy/ct/<slug>.sh
curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/$sha/install/<slug>-install.sh -o legacy/install/<slug>-install.sh   # ct only
python3 tools/extract-legacy-metadata.py      # regenerates nix/catalog/generated/
git add -N legacy nix/catalog/generated       # untracked files are invisible to flake eval
```

For `upstream:removed`: skip the copy; set `impl = "unsupported"` and
`unsupportedReason = "removed upstream <date>"` in `nix/catalog/<slug>.nix`
(create it if only a generated file exists) unless the module stands on its
own — say which in the PR.

## 2. Classify the tier

Read the installer, then check nixpkgs (the pinned rev in `flake.lock`):

| Finding | `impl` | Module shape |
|---|---|---|
| `services.<app>` exists in nixpkgs | `nixos-service` | wrap it: port, data dir, domain from `fleet.settings.domain.internal`, `apps.base.port` |
| package only (`pkgs.<app>`), no module | `package-systemd` | package + config file (`pkgs.formats.*`) + hardened systemd unit under its own user |
| installer is `docker compose` / a container image | `oci` | `virtualisation.oci-containers`, Docker backend, volumes under `/var/lib/<app>` |
| a disk image / ISO appliance (`vm/`) | `image` | preset only (`kind = "vm"`); consumer supplies `image = "import:…"` |
| cannot be a NixOS host (bare OS, PVE tooling, closed binary blob with no Linux build) | `unsupported` | preset only, with `unsupportedReason` |

Existing pilots to copy from: `jellyfin` (service), `forgejo` (service +
wiring), `rustypaste` (package-systemd), `dockge` (oci), `opnsense-vm`
(image).

## 3. Write the curated preset and the module

- `nix/catalog/<slug>.nix`: plain values override the generated
  `mkDefault`s — fix `title`, `description`, `upstream.{url,repo,license}`,
  correct extractor mistakes (a helper tool's repo picked instead of the
  app's, wrong port), set `impl`, `nixModule = "<slug>"`, `status = "ported"`.
- `nix/modules/apps/<slug>/default.nix`: `options.apps.<slug>` with
  `mkEnableOption`, a description on every option, `port` defaulting to the
  preset (`defaultText`), site values only from `fleet.settings.*`, secrets
  through sops, `apps.base.port = lib.mkDefault cfg.port`. Static option
  descriptions only (no interpolated config).
- Device needs (`/dev/dri`, TUN, USB) are preset flags, not module code —
  `mkApp` realises them.

## 4. Validate, commit, PR

```bash
nix flake check      # catalog-schema · example-consumer · tf-render · docs · ported-apps
nix build .#docs
```

`ported-apps` evaluates the new module *enabled*; a module that only
evaluates disabled cannot pass. Commit conventionally (`feat(catalog): port
<slug> (<tier>)`), push, and open a PR whose body has `Closes #<n>` plus:
which tier and why, what the legacy installer did that the module does
differently, and what needs a live PVE 9 host to verify (`status` stays
`ported` until an operator flips it to `verified`).

## Done when

The PR is green, the issue is linked with `Closes`, and
`fleet apps show <slug>` (from the consumer template) prints the entry with
its `impl` and `nixModule`.
