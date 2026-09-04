#!/usr/bin/env python3
"""Mine the legacy community-scripts tree into catalog presets.

Reads legacy/ct/*.sh (and legacy/vm/*.sh) and writes one
nix/catalog/generated/<slug>.nix per app with every value wrapped in
lib.mkDefault, so hand-curated nix/catalog/<slug>.nix files override it.

What is extracted (and from where):
  title            APP="…"
  category, tags   var_tags (first entry = category)
  defaults         var_cpu / var_ram / var_disk
  legacy.os/…      var_os / var_version
  arch             var_arm64=yes ⇒ x86_64 + aarch64
  privileged       var_unprivileged=0
  devices          var_gpu / var_tun / var_fuse
  upstream.url     "# Source: <url>" header comment
  upstream.repo    first fetch_and_deploy_{gh,gl,codeberg}_release /
                   get_latest_github_release "<owner/repo>" in the installer
  port             the success banner `http://${IP}:<port>`
  legacy.updateable  false when update_script only says "no update"
  impl/unsupportedReason  bare-OS templates, PVE-ecosystem tooling,
                   removed/redirected apps, Alpine flavours of an app
                   that also has a Debian entry

Idempotent: run it again after upstream syncs; commit the diff.
Usage: tools/extract-legacy-metadata.py [--root .]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

BARE_OS = {"debian", "ubuntu", "alpine", "fedora", "archlinux", "almalinux",
           "rockylinux", "centos", "gentoo", "devuan", "opensuse", "openeuler"}
PVE_ECOSYSTEM = {"proxmox-backup-server", "proxmox-datacenter-manager",
                 "proxmox-mail-gateway", "pve-scripts-local", "pve-ups"}
NO_UPDATE_RE = re.compile(
    r"No Update function|can only be updated|Repository is archived|"
    r"updated via the (user )?interface|is gone|has been (merged|renamed|archived)", re.I)
REDIRECT_RE = re.compile(r"bash -c \"\$\(curl[^\n]*?/ct/([a-z0-9-]+)\.sh\)\"")
REPO_RE = re.compile(
    r'(?:fetch_and_deploy_(?P<h1>gh|gl|codeberg)_(?:release|tag)|check_for_(?P<h2>gh|gl|codeberg)_(?:release|tag))'
    r'\s+"(?P<app>[^"]*)"\s+"(?P<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"'
    r'|get_latest_(?P<h3>github|gitlab|codeberg)_release\s+"(?P<repo2>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"')
HOSTS = {"gh": "github", "github": "github", "gl": "gitlab", "gitlab": "gitlab", "codeberg": "codeberg"}


def find_repo(slug: str, *texts: str):
    """Best (host, owner/repo) for the app itself — installers also fetch
    helper tools (Intel GPU runtime, yq, …) so prefer a call whose app
    argument or repo name matches the slug; else the first call."""
    cands = []
    for t in texts:
        for m in REPO_RE.finditer(t):
            g = m.groupdict()
            host = HOSTS[g["h1"] or g["h2"] or g["h3"]]
            cands.append((host, g["app"] or "", g["repo"] or g["repo2"]))
    if not cands:
        return None
    key = slug.replace("alpine-", "")
    for host, appname, repo in cands:
        if appname == key or key in repo.lower().split("/")[-1]:
            return host, repo
    return cands[0][0], cands[0][2]


def nix_str(s: str) -> str:
    return json.dumps(s)  # JSON string literals are valid Nix strings


def nix_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return nix_str(v)
    if isinstance(v, list):
        return "[ " + " ".join(nix_val(x) for x in v) + " ]"
    if v is None:
        return "null"
    raise TypeError(v)


def var(text: str, name: str):
    m = re.search(r'^\s*%s="\$\{%s:-([^}]*)\}"' % (re.escape(name), re.escape(name)), text, re.M)
    if m:
        return m.group(1).strip()
    m = re.search(r'^\s*%s="?([^"\n]*)"?' % re.escape(name), text, re.M)
    return m.group(1).strip() if m else None


def to_int(v, default):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def parse_ct(path: Path, install_dir: Path):
    text = path.read_text(errors="ignore")
    slug = path.stem
    app = re.search(r'^APP="([^"]*)"', text, re.M)
    title = app.group(1) if app else slug
    tags = [t for t in (var(text, "var_tags") or "").split(";") if t and t != "community-script"]
    src = re.search(r"^# Source:\s*(\S+)", text, re.M)
    port = re.search(r"https?://\$\{IP\}:(\d+)", text)
    upd = re.search(r"function update_script\(\)\s*\{(.*?)\n\}", text, re.S)
    entry = {
        "title": title,
        "category": tags[0] if tags else "misc",
        "tags": tags[1:],
        "upstream": {"url": src.group(1) if src else f"https://community-scripts.org/scripts/{slug}"},
        "port": int(port.group(1)) if port else None,
        "defaults": {
            "cpu_cores": to_int(var(text, "var_cpu"), 1),
            "memory_mb": to_int(var(text, "var_ram"), 1024),
            "root_disk_gb": to_int(var(text, "var_disk"), 4),
        },
        "privileged": var(text, "var_unprivileged") == "0",
        "devices": {
            "gpu": var(text, "var_gpu") == "yes",
            "tun": var(text, "var_tun") == "yes",
            "fuse": var(text, "var_fuse") == "yes",
        },
        "arch": ["x86_64", "aarch64"] if var(text, "var_arm64") == "yes" else ["x86_64"],
        "legacy": {
            "ct": f"legacy/ct/{path.name}",
            "os": var(text, "var_os"),
            "osVersion": var(text, "var_version"),
            "updateable": bool(upd) and not NO_UPDATE_RE.search(upd.group(1)),
        },
    }
    inst = install_dir / f"{slug}-install.sh"
    if inst.exists():
        entry["legacy"]["install"] = f"legacy/install/{inst.name}"
        itext = inst.read_text(errors="ignore")
        found = find_repo(slug, itext, text)
        if found:
            entry["upstream"]["repoHost"], entry["upstream"]["repo"] = found
        if entry["port"] is None:
            p2 = re.search(r"https?://\$\{?(?:IP|LOCAL_IP)\}?:(\d+)", itext)
            if p2:
                entry["port"] = int(p2.group(1))
    # ── impl classification ──
    reason = None
    if slug in BARE_OS:
        reason = "bare OS template — declare a plain fleet.compute host instead"
    elif slug in PVE_ECOSYSTEM:
        reason = "Proxmox host tooling — belongs to the hypervisor layer (ansible), not a guest"
    elif not upd:
        reason = "removed upstream (tombstone script)"
    else:
        r = REDIRECT_RE.search(text)
        if r and r.group(1) != slug:
            reason = f"redirect stub — use the `{r.group(1)}` entry"
    entry["impl"] = "unsupported" if reason else "planned"
    if reason:
        entry["unsupportedReason"] = reason
    return slug, entry


def parse_vm(path: Path):
    text = path.read_text(errors="ignore")
    slug = path.stem
    app = re.search(r'^\s*APP="([^"]*)"', text, re.M)
    src = re.search(r"^# Source:\s*(\S+)", text, re.M)

    def num(name, default):
        m = re.search(r'^\s*%s="?(\d+)' % name, text, re.M)
        return int(m.group(1)) if m else default
    return slug, {
        "title": app.group(1) if app else slug.replace("-vm", "").replace("-", " ").title(),
        "category": "vm",
        "tags": ["appliance"],
        "kind": "vm",
        "upstream": {"url": src.group(1) if src else f"https://community-scripts.org/scripts/{slug}"},
        "defaults": {"cpu_cores": num("CORE_COUNT", 2), "memory_mb": num("RAM_SIZE", 2048),
                     "root_disk_gb": num("DISK_SIZE", 8)},
        "legacy": {"ct": f"legacy/vm/{path.name}", "updateable": False},
        "impl": "planned",
    }


def render(slug: str, e: dict) -> str:
    def walk(d, indent):
        out = []
        for k, v in d.items():
            key = k if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_'-]*", k) else nix_str(k)
            if isinstance(v, dict):
                out.append(f"{indent}{key} = {{\n{walk(v, indent + '  ')}{indent}}};\n")
            elif v is None:
                continue
            else:
                out.append(f"{indent}{key} = lib.mkDefault {nix_val(v)};\n")
        return "".join(out)
    key = slug if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_-]*", slug) else nix_str(slug)
    return ("# GENERATED by tools/extract-legacy-metadata.py — do not edit; put\n"
            "# curation in nix/catalog/%s.nix (plain values override these mkDefaults).\n"
            "{ lib, ... }:\n{\n  fleet.catalog.apps.%s = {\n%s  };\n}\n" % (slug, key, walk(e, "    ")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    root = Path(a.root)
    legacy = root / "legacy"
    out = root / "nix" / "catalog" / "generated"
    out.mkdir(parents=True, exist_ok=True)
    entries: dict[str, dict] = {}
    for f in sorted((legacy / "ct").glob("*.sh")):
        slug, e = parse_ct(f, legacy / "install")
        entries[slug] = e
    # Alpine flavours: when a Debian entry exists it covers the app on
    # NixOS; when the Alpine script is the only one, it IS the app — key
    # it by the base name (legacy paths keep pointing at alpine-<app>).
    for slug in list(entries):
        if slug.startswith("alpine-") and slug != "alpine":
            base = slug[len("alpine-"):]
            if base in entries:
                entries[slug]["impl"] = "unsupported"
                entries[slug]["unsupportedReason"] = f"Alpine flavour of `{base}` — that entry covers it on NixOS"
            else:
                e = entries.pop(slug)
                e["tags"] = sorted(set(e["tags"]) - {"alpine"})
                entries[base] = e
    for f in sorted((legacy / "vm").glob("*.sh")):
        slug, e = parse_vm(f)
        entries.setdefault(slug, e)
    for old in out.glob("*.nix"):
        old.unlink()
    for slug, e in entries.items():
        (out / f"{slug}.nix").write_text(render(slug, e))
    stats = {
        "entries": len(entries),
        "unsupported": sum(e["impl"] == "unsupported" for e in entries.values()),
        "privileged": sum(e.get("privileged", False) for e in entries.values()),
        "gpu": sum(e.get("devices", {}).get("gpu", False) for e in entries.values()),
        "tun": sum(e.get("devices", {}).get("tun", False) for e in entries.values()),
        "fuse": sum(e.get("devices", {}).get("fuse", False) for e in entries.values()),
        "with_port": sum(e.get("port") is not None for e in entries.values()),
        "with_repo": sum("repo" in e.get("upstream", {}) for e in entries.values()),
        "vm": sum(e.get("kind") == "vm" for e in entries.values()),
    }
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
