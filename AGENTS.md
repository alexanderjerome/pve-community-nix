# AGENTS.md — operating manual for AI agents

This repo is a **fleetkit consumer-side catalog**. fleetkit's
[AGENTS.md](https://github.com/alexanderjerome/fleetkit/blob/main/AGENTS.md)
iron rules apply verbatim; these are the additions.

## What this is

Per-application presets (`fleet.catalog.apps.<name>`), the `mkApp`
helper, NixOS app modules (`apps.<name>`), PVE-host tooling, a consumer
template, and docs. The provisioning engine, fleet schema, images, CLI
and ansible layer live in fleetkit — fix engine gaps *there*, never by
vendoring.

## Iron rules (additions)

1. **Presets are data.** `nix/catalog/*.nix` may not reference `pkgs`,
   NixOS options, or `config` beyond `fleet.catalog`. They are evaluated
   by fleetkit's plain fleet eval as well as by every NixOS host.
2. **No site values.** RFC5737 addresses and `example.*` domains in every
   example and in the template. Timezone, ports, datastores, bridges are
   options or consumer overrides.
3. **`impl` is honest.** An entry is `nixos-service` / `package-systemd` /
   `oci` / `image` only when `nix/modules/apps/<nixModule>/` exists and
   evaluates; `status = "verified"` only after a real PVE 9 deploy.
   Anything that cannot be a NixOS host is `unsupported` with a reason.
4. **Attribution travels.** Every entry keeps `upstream.{url,repo,license}`
   and `legacy.{ct,install}` back-references.
5. **`nix flake check` is the acceptance gate**: `catalog-schema`,
   `example-consumer`, `tf-render`, `docs`, `ported-apps` (every module with
   status ported evaluates enabled).
6. **`legacy/` is read-only.** Never fix or extend the bash tree.

## Discovering the API

- `nix build .#docs` → options + catalog site.
- `nix build .#catalog-json` → the catalog as JSON (what `fleet apps` reads).
- `templates/consumer/` → a complete working consumer.
- `PLAN.md` → phases, decisions, and the fleetkit gap-fill design.

## Contribution shape

Small verified steps: change → `nix flake check` → conventional commit.
Ask "would this hold for a two-host homelab on one PVE node?".
