# Plan: rewrite Proxmox community-scripts as a declarative Nix catalog on fleetkit

## Context

`pve-community-nix` is a fork of community-scripts/ProxmoxVE: ~590 bash
LXC installers (`ct/*.sh` + `install/*-install.sh`), 17 VM scripts, 35
PVE-host tools, a 7 300-line `build.func` whiptail wizard, and unpinned
runtime fetches of everything from `raw.githubusercontent.com/…/main`.
Every guest is Debian/Alpine and every setting is a prompt or a `var_*`
env override.

The goal is to replace that with a fully declarative system: every
knob the wizard asks for becomes a Nix option, every guest is NixOS,
provisioning is terranix → OpenTofu, host management is ansible, and
"install Jellyfin" becomes one attrset in a fleet manifest. `fleetkit`
already contains the engine (bpg/proxmox emitters, NixOS LXC template
with zero-touch `ostype=nixos` first boot, colmena, SOPS, `fleet` CLI,
ansible roles for PVE). This plan wires the two together and settles
**all configuration surface first**; application modules are the last
phase and are deliberately not designed here beyond their contract.

### Decisions already made (user)

| Decision | Choice |
|---|---|
| Repo relationship | `pve-community-nix` is a **fleetkit consumer/catalog flake**; engine gaps are fixed **in fleetkit** (both repos, branch `claude/proxmox-nix-rewrite-plan-qx16ru`) |
| Old bash tree | moved to `legacy/` (no CI, read-only reference) until parity, then deleted |
| PVE floor | **9.x only** (relies on `PVE::LXC::Setup::NixOS` writing `eth0.network`) |
| Non-NixOS entries | appliance VMs (OPNsense, OpenWrt, TrueNAS, HAOS, RouterOS, Umbrel) = image-import compute entries; Docker-orchestrator apps = NixOS + `virtualisation.oci-containers`; both late phases |
| Dropped outright | telemetry (`api.func`, PocketBase status guard), root password/autologin, apt-cacher/HTTP-proxy/mirror rotation, `pveam` template logic, all whiptail |

### Key facts from exploration that shape the design

- fleetkit's `fleet.compute` (`nix/fleet/compute.nix`) already covers
  ~70 % of the wizard: vm_id, node, cores/RAM/swap/disk/datastore,
  mount points, nesting/fuse/keyctl, privileged, tags, pool, protect,
  ignore_changes, cloneFrom, image, notes. The zero-touch LXC path is
  `nix/lib/tf/proxmox.nix` `mkContainer` (:234-337) with `ostype="nixos"`.
- Missing from `fleet.compute` (from `misc/build.func` base_settings
  :1032-1202, wizard :2021-3262, build_container :4332-4423, lxc.conf
  edits :4593-4809): per-NIC bridge/SDN vnet, VLAN, MTU, MAC, DHCP,
  prefix length (hardcoded `/24`), IPv6 method, per-host DNS/search
  domain/gateway; timezone, PVE `protection`, arch, startup order,
  onboot, `mknod`, `mount` feature list; device passthrough (TUN, GPU
  `/dev/dri`+`/dev/kfd`+`/dev/nvidia*`, USB serial, Coral `/dev/apex_0`).
  VM side: machine type, bios/efidisk, cpu type, disk cache, scsihw,
  start-on-create; `mkVm` still has site literals (`BC:24:11:5B:EA:26`,
  `"local-storage"`, name-prefix branches).
- The catalog metadata is fully recoverable from the `var_*` block at
  the top of each `ct/*.sh` (cpu/ram/disk/os/version/unprivileged/tags/
  gpu/tun/fuse) plus the trailing `echo … http://${IP}:PORT` banner. No
  JSON catalog exists in the repo (`json/` is gitignored; canonical
  store is upstream PocketBase).
- App mix: ~150-200 of ~570 apps have a nixpkgs `services.*` module;
  389 installers are `fetch_and_deploy_gh_release` + systemd heredoc
  (mechanically translatable to a package + `systemd.services`); only 8
  use Docker; 20 are privileged (hardware); 12 are bare-OS templates.
- `tools/pve/*.sh` ≈ fleetkit `ansible/roles/proxmox/{base,pve}`:
  no-sub-repos, subscription-nag, apt-update, fstrim-timer, nfs-storage
  already exist. Gaps: microcode, kernel-clean/pin, scaling-governor,
  nic-offloading-fix, disk-health, iptag, monitor-all, post-pbs/pmg/pdm.
- Extension seams fleetkit already offers a consumer: `mkFleet {
  modules, globalModules, hostExtraModules, secretsFile }`
  (`flake.nix:63-183`), `cli-ext/*.py` with `COMMANDS`
  (`config.py:155-183`), `ANSIBLE_ROLES_PATH` consumer-first,
  `infra.services.<name>` registry (`nix/modules/infra/services.nix`)
  → firewall + Caddy vhost + `/etc/fleet/services.json`.

## Target architecture

```
fleetkit (engine)                         pve-community-nix (catalog)
──────────────────                         ──────────────────────────
fleet.compute schema  ←gap-fill (Ph.1)     flake.nix  inputs.fleetkit
nix/lib/tf/proxmox.nix emitters            nix/catalog/   app metadata (data only)
fleet.resources kinds ←new kinds (Ph.2)    nix/lib/mkApp.nix  preset → compute+host
infra.* base strata                        nix/modules/apps/<name>/  (Ph.6, last)
ansible/roles/proxmox/* ←new tasks (Ph.2)  ansible/roles/pve-tools/*  host tools
docs generator (group_of) ←"apps" group    cli-ext/apps.py  `fleet apps …`
checks: example-fleet/tf-render/docs       checks: catalog-schema, example-consumer,
                                                   tf-golden, docs
                                           legacy/  (old bash tree, no CI)
```

Consumer experience at the end (one file per app host, like
`templates/minimal/fleet/hosts/example.nix`):

```nix
{ catalog, ... }: {
  imports = [ (catalog.mkApp "jellyfin" {
    vm_id = 120; node = "pve1"; internal_ip = "192.0.2.120";
    provider_instance = "proxmox.main"; env = "home"; stack = "media";
    devices.gpu = true;   # from preset var_gpu=yes, overridable
  }) ];
}
```

`mkApp` expands a catalog preset (`cpu/ram/disk/privileged/devices/
port/tags/category`) into `fleet.compute.<name>` + `fleet.hostsRegistry.
<name>` with `apps.<name>.enable = true`. Everything is overridable; no
prompts, no `.vars` files, no env precedence ladder.

## Phases

Ordering follows the user's rule: every configuration surface is
settled (Phases 0-5) before any application module is written (Phase 6).
Each phase ends with `nix flake check` green in both repos and one or
more conventional commits.

### Phase 0 — repo skeleton (pve-community-nix)

1. `git mv` the bash tree into `legacy/` (`ct install misc tools vm
   turnkey` and their CI workflows under `legacy/.github/`); drop the
   upstream workflows from `.github/` so nothing runs against the old
   tree. Keep `LICENSE`, rewrite `README.md`, add `AGENTS.md`/`CLAUDE.md`
   mirroring fleetkit's iron rules (extend rule 4: catalog entries carry
   upstream attribution and license, RFC5737 examples only).
2. New `flake.nix`: inputs `fleetkit` (path/GitHub ref), `nixpkgs.follows
   = "fleetkit/nixpkgs"`. Outputs: `lib.mkApp`, `nixosModules.catalog`,
   `fleetModules.catalog` (adds `fleet.catalog.*`), `packages.{docs,
   catalog-json}`, `checks.*`, `templates.consumer`.
3. `templates/consumer/` = a copy of fleetkit's `templates/minimal`
   plus one `mkApp` host. This is the catalog's `example-fleet`
   equivalent and the only place a full fleet is evaluated in CI.
4. Checks (`nix/checks.nix`): `example-consumer` (evaluates the template
   through `fleetkit.lib.mkFleet`, forces `toplevel`), `tf-render`
   (every `tf-*` package is valid TF JSON, same jq test as fleetkit
   `nix/checks.nix:47-58`), `docs` (reuse fleetkit `docs/default.nix`
   pattern with `warningsAreErrors`, grouping extended for `apps.*` and
   `fleet.catalog.*`), `catalog-schema` (Phase 4).
5. `legacy/README.md`: why it exists, "do not edit", deletion criterion.

Verification: `nix flake check` passes with zero apps declared;
`nix flake init -t .#consumer` yields a fleet that evaluates.

### Phase 1 — guest configuration surface (fleetkit: `fleet.compute` + emitters)

The heart of the plan: every wizard prompt becomes an option on
`fleet.compute`, generically, with existing consumers' emitted TF
byte-identical. Full option/emitter/validator design is in
**Appendix A**. Summary:

- **Golden harness first** (commit 1): a fixture fleet exercising every
  legacy mode + a committed golden TF JSON per stack, diffed in a new
  `compute-surface-golden` check. Every later commit proves legacy
  output unchanged by construction.
- **Network**: `network_mode = "declared"` + `interfaces = [ { name,
  bridge | vnet, ipv4 = "dhcp"|"a.b.c.d/nn"|"manual", gateway, ipv6 =
  { method, address, gateway }, vlan, mtu, mac, firewall, model } ]`.
  Prefix length becomes explicit in declared mode; legacy modes read
  `fleet.network.internal_prefix_len` / `lan_prefix_len` (default 24,
  derived from the CIDRs) instead of the hardcoded `/24` (emitter and
  `fleet-member.nix`). Per-host `dns = { servers, domain }` override.
- **Container**: `protection`, `onboot`, `start_on_create`, `startup`,
  `arch`, `features.{mknod,mount}`, `devices = [ { path, uid, gid,
  mode, deny_write } ]` → bpg `device_passthrough` (TUN, GPU nodes,
  Coral), `hook_script`, and `lxc_extra_conf` (marker-block raw lines
  via `terraform_data` local-exec, the only route for USB wildcard
  cgroup rules). Rule: emit only when non-default.
- **Not on compute** (by design): timezone (bpg has no LXC timezone
  argument → catalog sets `time.timeZone` in `hostsRegistry`), root
  password/autologin/SSH-root (NixOS image is key-only), apt-cacher /
  proxy / host-CA (NixOS-side options), keyctl default (unchanged;
  catalog sets `keyctl = !privileged` on privileged apps).
- **VM**: new `vm.*` submodule (`machine`, `bios` + `efi`, `cpu_type`,
  `scsi_hardware`, `root_disk.{interface,cache,discard,iothread,ssd}`,
  `serial_console`, `agent`, `boot_order`, `tablet`), `cloud_init.
  {enable,datastore}`, and `image = "import:<datastore>:import/<file>"`
  → `disk[0].import_from` (appliance images). Declared mode bypasses
  the name-prefix dispatch entirely.
- **Site-literal removal, migration-safe**: `fleet.settings.providers.
  proxmox.defaultDatastore` (Phase 1 default `"local-storage"`, flips
  to `"local-lvm"` next major) replaces six literals; the netgate /
  headscale-router / dept / dev branches and the `custom-*` / `lxc-
  router` modes become expressible in declared mode, get `lib.warn`
  deprecation after the consumer migrates, then are removed.
- **Resources**: `sdn-zone`, `sdn-vnet`, `sdn-subnet` (+ auto
  `sdn_applier`), `linux-vlan`, `storage-nfs`, `storage-dir`.
- **Validators** (10, Appendix A §4) in `nix/fleet/default.nix`.

Verification: fleetkit `nix flake check` (four existing + golden);
consumer-side `nix build .#tf-<slug>` before/after with
`--override-input fleetkit` and `jq -S | diff` empty for untouched
hosts; one-time provider-behaviour checks on a dev node (empty
`ip_config`, `device_passthrough` gid on unprivileged CT,
`import_from`, `proxmox_sdn_*` names at the pinned provider).

### Phase 2 — Proxmox host configuration surface (fleetkit resources + ansible)

Maps `tools/pve/*.sh` and the wizard's host-side assumptions to
declarative form. Nothing here runs a whiptail.

1. `fleet.resources` new kinds (Nix, `nix/fleet/resources.nix` +
   `nix/tf/resources/proxmox.nix`): `sdn-zone`/`sdn-vnet` (bpg SDN
   resources), `linux-vlan`, `storage-dir`/`storage-nfs`/`storage-cifs`
   (bpg storage resources; replaces `storage-share-helper.sh`),
   `download` already exists (cloud images, appliance ISOs/qcow2).
   The NixOS LXC template becomes a declared `file` resource with
   `source = "nixos-lxc-image"` in the consumer template so a fresh
   single-node homelab needs no NFS `nix-store` SR (the `nix-store:`
   literal in `nix/lib/tf/proxmox.nix:205` becomes
   `fleet.settings.providers.proxmox.lxcTemplateDatastore`, default
   `"local"`).
2. Ansible tasks added to `ansible/roles/proxmox/base` and `…/pve`
   (all feature-gated by variables named after settings, soft-skip
   when unset): `microcode`, `kernel-clean`, `kernel-pin`,
   `scaling-governor`, `nic-offloading-fix`, `disk-health`
   (smartmontools timer), `iptag` (systemd service), `monitor-all`
   (ping-instances), `post-pbs/pmg/pdm-install` repo fixes (pbs role
   gets the same `no-sub-repos` treatment). Each is one task file,
   one `pve_*` variable block, one row in `ansible/README.md`.
3. `fleet.settings.providers.proxmox.hostTweaks = { microcode,
   kernelPin, governor, nicOffloadingFix, ipTag, monitorAll }` (all
   `nullOr`/bool default false) so the Nix manifest is the source and
   `settings-json` → ansible extra-vars carries them (extend the
   existing `fleet ansible inventory` var derivation rather than a
   second config file).
4. Explicitly not ported: `clean-lxcs`, `update-lxcs`, `update-apps`,
   `execute`, `lxc-delete`, `pve-privilege-converter`, `copy-data/*`
   (imperative fleet ops; NixOS guests are updated by colmena; the CLI
   already has `fleet remote`).

Verification: `example-tf-render` covers the new resource kinds via
the fixture; `ansible-lint` + `ansible-playbook --syntax-check` added
to the fleetkit `launcher` check's shell (no live host in CI).

### Phase 3 — image and first-boot contract (fleetkit + catalog base module)

1. LXC template: keep `nix/images/by-platform/proxmox.nix`. Add the
   GPU/TUN guest side to the platform module
   (`nix/modules/infra/base/platform/pve/lxc.nix`): `hardware.graphics`
   enable when `devices.gpu`, `users.groups.{video,render}` gids pinned
   to match the host-side `device_passthrough.gid` (replaces
   `fix_gpu_gids()` stop/restart dance), `boot.kernel.sysctl` no-ops
   suppressed. Expose the chosen gids as `infra.platform.pve.lxc.
   deviceGids` so emitter and guest agree from one value (hostsJson
   carries it). `time.timeZone` is set here from the preset/override
   (the community `var_timezone`), since PVE has no LXC timezone knob
   the provider can drive.
2. VM image: `type = "vm"` path already works; add `arch` awareness
   (aarch64 template build for arm64 nodes, `var_arm64` equivalent) as
   a build matrix, not a runtime branch.
3. Catalog base NixOS module (`nix/modules/apps/_base.nix`, always
   imported by `mkApp`): `infra.services` registration from preset
   port, MOTD replaced by `/etc/fleet/services.json` + a small
   `apps-motd` unit printing the URLs (parity with `motd_ssh`),
   `system.stateVersion` pinned, `networking.firewall` from the
   registry, optional `infra.ingress` vhost. No secrets, no
   credentials: apps that need an admin password declare it via
   `sopsLib.mkSecret` and the module renders it.
4. PVE version assertion: `fleet.providers.proxmox.<inst>.minVersion`
   default `"9.0"` checked by `fleet pve status` (CLI, eval-free) and
   documented as the floor.

Verification: `nix build .#lxc-template` in the catalog repo; a
`nixosConfigurations.<mkApp host>` toplevel builds in CI.

### Phase 4 — catalog schema and metadata extraction (catalog repo, data only)

1. Schema `fleet.catalog.apps.<name>` (submodule, every field
   documented): `title`, `description`, `upstream = { url, repo,
   license }`, `category` (from `var_tags`), `port` + `extraPorts`,
   `defaults = { cpu_cores, memory_mb, root_disk_gb }`, `privileged`,
   `devices = { gpu, tun, fuse }`, `arch = [ "x86_64" "aarch64" ]`,
   `impl = nixos-service | package-systemd | oci | image | unsupported`
   (Phase 6 tier), `nixModule` (path or null until Phase 6),
   `legacy = { ct, install }` (paths under `legacy/` for traceability),
   `status = planned | ported | verified`.
2. `tools/extract-legacy-metadata.py`: parses `legacy/ct/*.sh` `var_*`
   lines and the `http://${IP}:PORT` banner, writes
   `nix/catalog/<name>.nix` (one file per app, pure data). Run once,
   commit output, keep the script for re-sync. Tombstones, redirect
   stubs, bare-OS templates and Proxmox-ecosystem entries are written
   with `impl = "unsupported"` and a reason.
3. `nix/lib/mkApp.nix`: preset + overrides → `fleet.compute` entry
   (kind from preset; `devices` expanded from catalog-side presets
   `nix/lib/devices.nix` — `tun`, `gpu.intel`/`amd`/`nvidia` node
   lists with `gid`, `coral`, `usbSerial` → `lxc_extra_conf`; `tags =
   [ category "community-catalog" ]`; `features.keyctl = !privileged`) + `fleet.hostsRegistry` entry importing
   `_base.nix` and, when `nixModule != null`, the app module with
   `apps.<name>.enable = true`. `mkApp` refuses (assertion with
   actionable message) presets with `impl = "unsupported"`.
4. `packages.catalog-json` (built artifact, eval-free consumption by
   the CLI, per fleetkit convention) and `cli-ext/apps.py`: `fleet apps
   list [--category] [--status]`, `fleet apps show <name>`, `fleet apps
   scaffold <name>` (writes a host file from the preset).
5. Check `catalog-schema`: every `nix/catalog/*.nix` evaluates against
   the submodule; every `ported` entry's `nixModule` exists and its
   options doc builds; port uniqueness is **not** enforced (different
   hosts).

Verification: `nix flake check`; `fleet apps list` runs in the
`launcher`-style check; `mkApp "jellyfin"` in the consumer template
renders TF and a NixOS toplevel with `impl = "planned"` (base module
only, no app service yet).

### Phase 5 — docs, migration guide, CI

1. mdBook: chapters `fleet/catalog`, `apps/<category>` (generated from
   `catalog-json` + options.json), a hand-written "From community-
   scripts to catalog" page mapping each wizard step to its option
   (table generated from Appendix A), and the PVE-9 requirement page.
2. GitHub Actions: `nix flake check` on PR for both repos; Pages deploy
   for the catalog docs.
3. `legacy/` deletion criterion recorded: when every `status != planned`
   entry has `impl != unsupported` or a documented reason.

### Phase 6 — application modules (last; only the contract is fixed here)

Not started until Phases 0-5 are merged. Contract for
`nix/modules/apps/<name>/default.nix`:

- `options.apps.<name>` with `enable`, `port` (default from preset via
  `config.fleet.catalog.apps.<name>.port`, `defaultText`), `dataDir`,
  `openFirewall`, `ingress.enable`; every option documented.
- `config = mkIf cfg.enable { … ; infra.services.<name> = { port;
  description; category; }; }` — mirrors
  `nix/modules/infra/data/rabbitmq/default.nix` seven-part shape.
- Tiers, in order of work: **T1** nixpkgs `services.*` 1:1 (~55, e.g.
  jellyfin, vaultwarden, adguardhome, postgresql, grafana, gitea,
  navidrome, immich, paperless); **T2** further nixpkgs modules (~65);
  **T3** Docker apps via `virtualisation.oci-containers` (nesting on,
  `features.keyctl`, unprivileged); **T4** long-tail
  `fetch_and_deploy_gh_release` apps needing a package + systemd unit
  (the legacy install script is the spec: binary, port, user, unit);
  **T5** appliance VMs (`impl = image`, no NixOS, `image =
  "import:…"` from a `download` resource); privileged/closed-source entries stay
  `unsupported` unless a real need appears.
- Pilot: one app per tier (jellyfin, forgejo, dockge, wakapi, opnsense)
  proves the contract end-to-end on a real PVE 9 node before batching.

## Verification (end-to-end, after Phase 4)

1. Both repos: `nix flake check` green (fleetkit 5 checks incl.
   `tf-golden`; catalog 4 checks).
2. Golden diff: render the fleetkit production-style fixture before
   and after Phase 1; untouched hosts' TF JSON is byte-identical.
3. Live smoke on a PVE 9 node (operator-run, not CI): `fleet deploy tf
   apply <stack>` for the consumer template's `mkApp` host → container
   boots on its declared IP with GPU/TUN nodes present (`ls /dev/dri`,
   `/dev/net/tun`), `fleet deploy nixos apply host <name>` converges,
   `/etc/fleet/services.json` lists the preset port.
4. `fleet apps list` shows ~570 entries with correct `impl` tiers and
   counts matching the extraction statistics (516 debian/23 ubuntu/9
   alpine sources, 20 privileged, 37 gpu, 7 tun, 5 fuse).

## Explicitly out of scope

- PVE 8.x support, telemetry, apt-cacher/proxy/mirror logic, root
  passwords/autologin, `update_script` in-place upgrades (colmena
  replaces them), TurnKey appliances, `tools/addon/*` (become ordinary
  catalog apps or `infra.*` modules later), `copy-data/*`.
- Writing any app module beyond the pilot contract (Phase 6 is a
  separate planning round per tier).

## Appendix A — `fleet.compute` gap-fill design (fleetkit)

### A.0 Ground truth

- Site literals today: bridge names, `/24`, hostname `"netgate"`, MACs
  `BC:24:11:5B:EA:26` / `BC:24:11:D0:E9:C0` (`nix/lib/tf/proxmox.nix:87-173,
  362-366, 424-435, 463-529`); `"local-storage"` 6× in `mkVm` and as
  option defaults (`compute.nix:147,337`); `/24` again on the NixOS side
  (`nix/modules/infra/base/fleet-member.nix:100,119,155`).
- Latent bug: `mkNetwork` reads `meta.internal_bridge` (`proxmox.nix:83`)
  but `compute.nix` never declares it.
- bpg container resource supports: `device_passthrough { path deny_write
  gid mode uid }`, `features { nesting fuse keyctl mknod mount(nfs|cifs) }`,
  `startup { order up_delay down_delay }`, `protection`,
  `hook_script_file_id`, `cpu.architecture`, `network_interface { name
  bridge enabled firewall host_managed mac_address mtu rate_limit
  vlan_id }`, `ip_config.{ipv4,ipv6} { address (cidr|dhcp|auto) gateway }`.
  **No `timezone` argument.**
- bpg VM resource supports: `machine (pc|q35)`, `bios (seabios|ovmf)` +
  `efi_disk`, `cpu.type`, `disk { cache discard ssd iothread file_id
  import_from }`, `scsi_hardware`, `serial_device`, `agent`, `on_boot`,
  `startup`, `protection`, `boot_order`, `tablet_device`, `network_device
  { bridge model mac_address mtu vlan_id firewall }`.
- bpg also has `proxmox_sdn_{zone_simple,zone_vlan,vnet,subnet,applier}`,
  `proxmox_virtual_environment_network_linux_vlan`,
  `proxmox_storage_{nfs,directory,cifs,…}`, hardware mappings. Confirm the
  `proxmox_sdn_*` names exist at the pinned `~> 0.103` with
  `tofu providers schema` before relying on them.
- Local-exec precedent: `nix/lib/tf/xen-orchestra.nix:196-220`
  (`terraform_data` + `triggers_replace` + `local-exec`; note it uses the
  forbidden `nix-shell -p`, new code must use `nix shell nixpkgs#…`).

Rule for every new option: **emit only when it differs from the
provider default / today's literal**, so an unchanged manifest renders
byte-identical JSON.

### A.1 Option set

**`fleet.network`** (`nix/fleet/network/default.nix`)
| option | type / default | notes |
|---|---|---|
| `internal_prefix_len` | int, `mkDefault` from `internal_cidr` else 24, `defaultText` | replaces hardcoded `/24` for `internal_ip` (emitter + fleet-member.nix) |
| `lan_prefix_len` | same, from `lan_cidr` | for `ip` in external/dual/custom modes |

**`fleet.compute.<name>`** — network
| option | type / default | LXC/VM | maps to |
|---|---|---|---|
| `network_mode` | + enum value `"declared"` | both | dispatch |
| `interfaces` | listOf interfaceOpts, `[]` | both | index i → net`i` / eth`i` |
| `interfaces.*.name` | nullOr str, null → `eth${i}` | lxc | `network_interface.name` |
| `interfaces.*.bridge` | str, `"vmbr0"` (PVE stock default) | both | `bridge` |
| `interfaces.*.vnet` | nullOr str, null | both | written into `bridge`; refs an `sdn-vnet` resource |
| `interfaces.*.ipv4` | nullOr (enum dhcp/manual ∪ cidr regex), `"dhcp"` | both | `ip_config.ipv4.address`; **prefix mandatory in declared mode** |
| `interfaces.*.gateway` | nullOr str | both | `ip_config.ipv4.gateway` |
| `interfaces.*.ipv6` | `{ method = none/auto/dhcp/static; address; gateway }` | both | `ip_config.ipv6` (community "disable" ≡ none) |
| `interfaces.*.vlan` | nullOr ints 1..4094 | both | `vlan_id` |
| `interfaces.*.mtu` | nullOr int | both | `mtu` |
| `interfaces.*.mac` | nullOr MAC regex (uppercase) | both | `mac_address` |
| `interfaces.*.firewall` | bool false | both | `firewall` (LXC: only when true) |
| `interfaces.*.model` | enum virtio/e1000/e1000e/rtl8139/vmxnet3, virtio | vm | `network_device.model` |
| `interfaces.*.rate_limit_mbps` | nullOr int | both | optional; drop if trimming |
| `dns` | `{ servers = nullOr listOf str; domain = nullOr str }` | both | `initialization.dns`; null = inherit `fleet.network.*`; `domain = ""` = none |
| `internal_bridge` | nullOr str | lxc | declare the option the emitter already reads |
| `internal_ip` | unchanged; in declared mode validator ties it to a static ipv4; optional derived default with `defaultText` | both | hostsJson / colmena target |

**Container / lifecycle**
| option | type / default | LXC/VM | maps to |
|---|---|---|---|
| `protection` | bool false | both | `protection` (only true); distinct from `protect` = tofu `prevent_destroy` |
| `onboot` | bool true | both | `start_on_boot` (replaces literal `:312`) / `on_boot` (only false) |
| `start_on_create` | bool true | both | `started` (replaces literals `:311`, `:403`) |
| `startup` | nullOr `{ order; up_delay; down_delay }` | both | `startup { }` (LXC ints, VM strings) |
| `arch` | enum amd64/arm64/armhf/i386, amd64 | lxc | `cpu.architecture` (only ≠ amd64); community `var_arm64` is catalog metadata, not compute |
| `features.mknod` | bool false | lxc | `features.mknod` (only true) |
| `features.mount` | listOf enum nfs/cifs, `[]` | lxc | `features.mount` (only non-empty); "fuse" in community list ≡ `features.fuse` |
| `devices` | listOf `{ path (/dev/…); uid; gid; mode (0NNN); deny_write }`, `[]` | lxc | `device_passthrough = [ … ]` — TUN `/dev/net/tun`, GPU `/dev/dri/*` gid 44, `/dev/kfd`, `/dev/nvidia*`, Coral `/dev/apex_0`. Vendor presets live in the catalog (`nix/lib/devices.nix`), not the framework |
| `hook_script` | nullOr str | lxc | `hook_script_file_id` (snippets `kind = "file"` resource) |
| `lxc_extra_conf` | listOf str, `[]` | lxc | marker-block lines in `/etc/pve/lxc/<vmid>.conf` via `mkLxcExtraConf` (USB `c 188:*` wildcards, `optional` mounts, autodev hooks) |

**VM-only `vm.*` submodule** (precedent: `xoa` at `compute.nix:428-522`)
| option | type / default | maps to |
|---|---|---|
| `vm.machine` | nullOr enum pc/q35 | `machine` (community i440fx ≡ pc) |
| `vm.bios` | nullOr enum seabios/ovmf | `bios`; ovmf ⇒ `efi_disk { datastore_id file_format="raw" type pre_enrolled_keys }` |
| `vm.efi` | `{ datastore = nullOr str; type = enum 2m/4m, 4m; pre_enrolled_keys = bool false }` | `efi_disk` |
| `vm.cpu_type` | str `"host"` (today's literal `:405`) | `cpu.type` |
| `vm.scsi_hardware` | nullOr enum | `scsi_hardware` |
| `vm.root_disk` | `{ interface = "virtio0"; cache; discard; iothread; ssd }` | `disk[0].*` |
| `vm.serial_console` | bool true | `serial_device` (today unconditional `:541`) |
| `vm.agent` | nullOr bool | `agent.enabled` (null keeps today's computed value `:535`) |
| `vm.boot_order` | nullOr listOf str | `boot_order` |
| `vm.tablet` | nullOr bool | `tablet_device` |
| `cloud_init.enable` | bool true | false omits `initialization` |
| `cloud_init.datastore` | nullOr str | `initialization.datastore_id` (today literal `:438`) |
| `image` | + `"import:<datastore>:import/<file>"` | `disk[0].import_from` (PVE ≥ 8.4; `file:` / `clone:` unchanged) |

**Site-literal removal (migration-safe)**
- `fleet.settings.providers.proxmox.defaultDatastore` : str, Phase-1
  default `"local-storage"` (documented as legacy default; flips to
  `"local-lvm"` next major). Threaded into all six `mkVm` literals,
  `dataDiskOpts.datastore_id`, `root_disk_datastore`, `vm.efi.datastore`,
  `cloud_init.datastore` (all `defaultText`). Emitted JSON unchanged.
- `fleet.providers.proxmox.<inst>.cluster.node_addresses` : attrsOf str,
  `{}` — node → SSH host for the escape hatch; falls back to node name.
- Legacy name-prefix VM branches (`isNetgate/isHeadscaleRouter/isDept/
  isDev`, both MACs, `staticWanCidrs`, clone 9000, `legacyDevDataDisk`,
  `vm_template`) and modes `custom-netgate` / `custom-btc-testnet` /
  `lxc-router`: all expressible in declared mode. Path: consumer
  rewrites entries → tf-diff proves identity → `lib.warn` deprecation →
  removal next major. No `mkRenamedOptionModule` fits submodule-internal
  options; the golden check is the migration guard.

Deliberately **not** on compute: timezone (→ `time.timeZone` in
`hostsRegistry`), root password / autologin / SSH-root / authorized key
(image is key-only, `proxmox.nix:41-53`), apt-cacher / proxy / host CA
(NixOS options), keyctl default (framework keeps `true`; catalog sets
`keyctl = !privileged`).

### A.2 Emitter changes — `nix/lib/tf/proxmox.nix`

New `let` helpers: `dnsFor meta` (replaces `dnsConfig` `:58-59` and the
VM copy `:440-441`; identical output when `meta.dns` is null),
`ipv4Cidr ip len` (replaces every `"${…}/24"` at `:93,109,121,133,135,
145,168,169,453,459,467,468,497,507,514,526`), `ifName i nic`,
`nicCommon nic` (vlan/mtu/mac/rate), `ipConfigFor nic` (v4 + v6 blocks;
NIC with neither yields `{}` to keep `ip_config` positional — verify
provider accepts empty block, else emit `ipv4.address = "manual"`),
`bridgeFor nic` (vnet wins).

- **`mkNetwork` (`:54-173`)**: add `"declared"` branch before the
  `throw`: `network_interface = imap0 …`, `initialization = { hostname;
  dns = dnsFor; ip_config = map ipConfigFor interfaces }`. Legacy
  branches only get the prefix-len and `dnsFor` substitutions.
- **`mkContainer` (`:234-337`)**: `started` ← `start_on_create`,
  `start_on_boot` ← `onboot`, `protection`, `startup`, `cpu.architecture`,
  `features.mknod/mount`, `device_passthrough`, `hook_script_file_id`
  (all conditional on non-default).
- **`mkLxcExtraConf`** (new; emitted from `nix/tf/compute/proxmox.nix`
  as a third `mkIf`): `resource.terraform_data."<name>-lxc-conf"` with
  `triggers_replace = [ container id, sha256 of lines ]`,
  `provisioner.local-exec` = `nix shell nixpkgs#openssh --command ssh
  root@<node_addresses.node or node> '<idempotent marker-block rewrite;
  pct reboot only if running>'`. Same root-over-SSH channel the provider
  already needs (`nix/tf/providers/proxmox/default.nix`). Mirrors
  `ansible/roles/proxmox/pve/tasks/dev-lxc-tun.yml`. Hook-script
  pre-start self-rewrite is unverified, so local-exec is the route.
- **`mkVm` (`:340-552`)**: declared mode → `network_device = map (nic:
  nicDefaults // {bridge; model; firewall} // mac/vlan/mtu)` (keep
  `nicDefaults` `:385-396` for drift semantics), `initialization.
  ip_config = map ipConfigFor`; `machine`, `bios` + `efi_disk`,
  `cpu.type`, `scsi_hardware`, `disk[0].{interface,cache,discard,
  iothread,ssd,import_from}`, `defaultDatastore` into every datastore
  field, `serial_device` conditional, `agent.enabled` override,
  `boot_order`, `tablet_device`, `on_boot`/`started`/`protection`/
  `startup`, `cloud_init.enable=false` ⇒ no `initialization`. Declared
  hosts take the `newStyle` cloud-init path (`:448-462`) and bypass
  name-prefix dispatch entirely.
- **NixOS side (same commit as prefix-len)**: `fleet-member.nix:100,119,
  155` read `fleet.network.*_prefix_len`. `hostsJson` (`nix/fleet/
  default.nix:262-299`) gains `network_mode` + rendered `interfaces` so
  `infra.networking` can later drive networkd from declared NICs
  (follow-up; until then a declared NixOS host with non-eth0/eth1 or
  DHCP layouts is overridden by fleet-member's `10-eth0`/`10-eth1`
  units on first deploy — document it).

### A.3 New `fleet.resources` kinds (`nix/fleet/resources.nix:36-50` + `nix/tf/resources/proxmox.nix:28-74`)

| kind | fields | bpg resource |
|---|---|---|
| `sdn-zone` | `zone_id`, `zone_type = simple|vlan`, `bridge`, `nodes`, `mtu`, `dns_zone`, `ipam` | `proxmox_sdn_zone_simple` / `_vlan` |
| `sdn-vnet` | `vnet_id`, `zone`, `tag`, `vlan_aware`, `alias`, `isolate_ports` | `proxmox_sdn_vnet` |
| `sdn-subnet` | `vnet`, `cidr`, `gateway`, `snat`, `dhcp_range` | `proxmox_sdn_subnet` |
| (auto) | one `proxmox_sdn_applier."finalizer"` per stack when any `sdn-*` exists, `depends_on` all, `replace_triggered_by` their ids | `proxmox_sdn_applier` |
| `linux-vlan` | `name`, `interface`, `vlan`, `address`, `gateway`, `mtu`, `comment` | `proxmox_virtual_environment_network_linux_vlan` (node-scoped → `nodeScopedResourceKinds`, `default.nix:121`) |
| `storage-nfs` | `storage_id`, `server`, `export`, `content`, `nodes`, `options` | `proxmox_storage_nfs` (declarative twin of `nfs-storage.yml`; keep ansible for pre-token bootstrap) |
| `storage-dir` | `storage_id`, `path`, `content`, `nodes` | `proxmox_storage_directory` |
| later | `storage-cifs`, `hardware-mapping-{dir,pci,usb}` | as named |

### A.4 Validators (`nix/fleet/default.nix`, extend throw chain `:144-194`)

1. `network_mode == "declared"` ⇔ `interfaces != []`.
2. Per interface: `vnet != null` ⇒ `bridge` is the default; `gateway`
   ⇒ static ipv4 CIDR; `ipv6.method == "static"` ⇔ `ipv6.address != null`;
   `ipv6.gateway` only with static; names unique, LXC names match
   `^eth[0-9]+$`; at most one v4 gateway and one v6 gateway per host.
3. Declared mode: `internal_ip` / `ip` host parts match a static ipv4.
4. `vnet` resolves to an `sdn-vnet` on the same `provider_instance`;
   `sdn-vnet.zone` resolves to an `sdn-zone` there (pattern:
   `poolRefViolations` `:103-111`).
5. LXC-only options non-default on `kind = "vm"` → error; `vm.*`
   non-default on `kind = "container"` → error (new options only).
6. `devices`: absolute `/dev/` path, unique, uid/gid 0..65535, mode
   4-digit octal; description notes unprivileged CTs need mapped gid.
7. `lxc_extra_conf != []` ⇒ resolvable node (explicit or
   `cluster.primary_node`).
8. `dns.servers` non-empty when non-null; `startup.order ≥ 0`.
9. `image = "import:…"` contains `:import/`; `vm.bios == "ovmf"` with
   null efi datastore resolves to `defaultDatastore`.
10. `*_prefix_len` in 0..32 and consistent with `internal_cidr` /
    `lan_cidr` when those are set.

Messages follow the existing style: name the entry, the field, the fix.

### A.5 Verification

- Existing gates: `docs` (descriptions + `defaultText` for every derived
  default), `example-fleet` (template evaluates with none of the new
  options set), `example-tf-render`.
- **New check `compute-surface-golden`** (`nix/checks.nix`): fixture
  consumer at `nix/checks/fixtures/compute-surface/` (RFC5737 values,
  `backend.bucket = "golden-tofu"`) with one host per legacy mode
  (`single-internal`, `single-external`, `dual`, `custom-netgate`,
  `custom-btc-testnet`, `lxc-router` + `mac_address_eth0`, `host_managed`)
  and per legacy VM class (`netgate`, `headscale-router` +
  `staticWanCidrs`, `dept-x`, `dev-x`, `vm_template = "nixos"`,
  `clone:`, `file:`), plus new-surface hosts (declared LXC with 2 NICs:
  static+gw+vlan+mtu+mac+ipv6 static / dhcp+vnet+ipv6 auto; devices;
  mknod/mount; startup; protection; arm64; hook_script; lxc_extra_conf;
  dns override; declared VM q35/ovmf/efi/cpu_type/scsi/cache/discard/
  import; `cloud_init.enable = false`; resources sdn-zone/vnet/subnet,
  linux-vlan, storage-nfs/dir, bridge, pool). Hosts split across ≥ 2
  stacks. Goldens at `nix/checks/golden/compute-surface/tf-<slug>.json`;
  derivation does `jq -S` both sides and `diff -u`. Regeneration via
  `nix/checks/update-golden.sh` (documented in the checks.nix header;
  must be `git add`ed). Determinism: fixture avoids store-path-embedding
  paths (`source = "nixos-lxc-image"`, Debian-image containers,
  `pve-host` VMs) or normalises `/nix/store/<hash>-` before diffing.
  **Lands before any option change** so it captures today's output.
- Consumer-side proof: per stack `nix build .#tf-<slug>
  --override-input fleetkit path:…` before/after, `jq -S` + `diff`;
  optionally `fleet deploy tf preview` shows no changes.
- One-time provider checks on a dev node: empty `ip_config` acceptance,
  `device_passthrough` gid on unprivileged CT, `import_from`, the
  `proxmox_sdn_*` names at `~> 0.103`.

### A.6 Commit sequence (each leaves `nix flake check` green)

1. `test(checks): compute-surface golden render check + fixture fleet`
2. `fix(compute): declare internal_bridge option read by mkNetwork`
3. `feat(network): internal_prefix_len / lan_prefix_len through mkNetwork, mkVm, fleet-member.nix`
4. `feat(compute): protection, onboot, start_on_create, startup, dns override`
5. `feat(compute): features.mknod/mount, arch, hook_script, devices (device_passthrough)`
6. `feat(compute): interfaces + network_mode "declared" (LXC), hostsJson interfaces`
7. `feat(compute): vm.* submodule, declared VMs, cloud_init.enable/datastore, image "import:"`
8. `refactor(settings): providers.proxmox.defaultDatastore replaces "local-storage" literals`
9. `feat(resources): sdn-zone/vnet/subnet (+applier), linux-vlan, storage-nfs/dir`
10. `feat(compute): lxc_extra_conf escape hatch (terraform_data local-exec) + cluster.node_addresses`
11. `docs: networking-modes page + community-scripts → fleet.compute mapping table`
12. *(consumer repo)* migrate netgate / headscale-router / dept-* / dev-* / custom-* to declared mode; tf-diff proves identity
13. `chore(compute): deprecate legacy modes, name-prefix VM dispatch, vm_template, staticWanCidrs, singleBridgeInstances` → next major: remove, regenerate golden, flip `defaultDatastore` to `local-lvm`

### A.7 Critical files

- `nix/fleet/compute.nix`, `nix/lib/tf/proxmox.nix`, `nix/fleet/default.nix`
- `nix/checks.nix` + new `nix/checks/fixtures/compute-surface/`, `nix/checks/golden/compute-surface/`
- `nix/tf/resources/proxmox.nix`, `nix/fleet/resources.nix`
- `nix/fleet/network/default.nix`, `nix/modules/infra/base/fleet-member.nix`
- `nix/fleet/settings.nix`, `nix/fleet/providers/default.nix`, `nix/tf/compute/proxmox.nix`
