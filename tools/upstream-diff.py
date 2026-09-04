#!/usr/bin/env python3
"""Diff upstream community-scripts/ProxmoxVE against this catalog and
report (or file as issues) what the Nix side has to catch up on.

  new      — upstream ct/<slug>.sh or vm/<slug>.sh with no legacy copy here
  changed  — legacy copy exists but the extracted preset metadata differs
             (cores/RAM/disk, port, privileged, device flags, OS, tags…)
  removed  — legacy copy exists, upstream script is gone

Usage:
  tools/upstream-diff.py --upstream <checkout of ProxmoxVE> [--json out.json]
  tools/upstream-diff.py --upstream … --emit-issues [--dry-run]

--emit-issues uses the `gh` CLI (GH_TOKEN) to open one issue per finding,
labelled `upstream-app` + `upstream:new|changed|removed`, skipping any
finding that already has an OPEN issue with the same title. Closed issues
do not suppress a later re-occurrence (a second upstream change after a
port gets a fresh issue).

The metadata parser is tools/extract-legacy-metadata.py, imported so both
tools agree on what "the preset" of a script is.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
UPSTREAM_REPO = "community-scripts/ProxmoxVE"
LABEL = "upstream-app"
COMPARE_FIELDS = ["title", "category", "tags", "port", "defaults", "privileged", "devices", "arch", "kind"]
LEGACY_FIELDS = ["os", "osVersion"]


def load_extractor():
    spec = importlib.util.spec_from_file_location("extract_legacy_metadata", HERE / "extract-legacy-metadata.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def preset_of(mod, tree: Path, kind: str, slug: str) -> dict | None:
    f = tree / kind / f"{slug}.sh"
    if not f.exists():
        return None
    if kind == "ct":
        _, e = mod.parse_ct(f, tree / "install")
    else:
        _, e = mod.parse_vm(f)
    return e


def compact(e: dict) -> dict:
    out = {k: e.get(k) for k in COMPARE_FIELDS if k in e}
    out["legacy"] = {k: e.get("legacy", {}).get(k) for k in LEGACY_FIELDS}
    return out


def field_diff(a: dict, b: dict, prefix: str = "") -> list[str]:
    lines = []
    for k in sorted(set(a) | set(b)):
        va, vb = a.get(k), b.get(k)
        if isinstance(va, dict) and isinstance(vb, dict):
            lines += field_diff(va, vb, f"{prefix}{k}.")
        elif va != vb:
            lines.append(f"{prefix}{k}: {json.dumps(va)} → {json.dumps(vb)}")
    return lines


def scan(mod, root: Path, upstream: Path) -> list[dict]:
    legacy = root / "legacy"
    findings = []
    for kind in ("ct", "vm"):
        up = {p.stem for p in (upstream / kind).glob("*.sh")}
        here = {p.stem for p in (legacy / kind).glob("*.sh")}
        for slug in sorted(up - here):
            e = preset_of(mod, upstream, kind, slug)
            findings.append({"type": "new", "kind": kind, "slug": slug, "preset": compact(e), "full": e})
        for slug in sorted(here - up):
            findings.append({"type": "removed", "kind": kind, "slug": slug})
        for slug in sorted(up & here):
            a = compact(preset_of(mod, legacy, kind, slug))
            b = compact(preset_of(mod, upstream, kind, slug))
            d = field_diff(a, b)
            if d:
                findings.append({"type": "changed", "kind": kind, "slug": slug, "diff": d, "preset": b})
    return findings


def upstream_sha(upstream: Path) -> str:
    try:
        return subprocess.run(["git", "-C", str(upstream), "rev-parse", "HEAD"],
                              check=True, capture_output=True, text=True).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return "main"


def issue_title(f: dict) -> str:
    return f"[upstream] {f['type']}: {f['slug']}"


def issue_body(f: dict, sha: str) -> str:
    base = f"https://github.com/{UPSTREAM_REPO}/blob/{sha}"
    ct = f"{base}/{f['kind']}/{f['slug']}.sh"
    inst = f"{base}/install/{f['slug']}-install.sh"
    head = [f"Upstream `{UPSTREAM_REPO}` @ `{sha[:12]}` — [{f['kind']}/{f['slug']}.sh]({ct})"]
    if f["kind"] == "ct":
        head.append(f"Installer: [install/{f['slug']}-install.sh]({inst})")
    body = "\n".join(head) + "\n\n"
    if f["type"] == "new":
        p = f["preset"]
        body += "Extracted preset:\n\n```json\n" + json.dumps(p, indent=2) + "\n```\n\n"
        body += ("**To port** (skill `port-upstream-app`): copy the upstream `ct/` and `install/` scripts into "
                 "`legacy/`, run `tools/extract-legacy-metadata.py`, curate `nix/catalog/<slug>.nix`, then pick the "
                 "tier — `nixos-service` if nixpkgs has a module, `package-systemd` if only a package, `oci` for "
                 "docker-based apps, `image` for appliances, or `unsupported` with a reason — and add "
                 "`nix/modules/apps/<slug>/` accordingly. `nix flake check` must pass.\n")
    elif f["type"] == "changed":
        body += "Preset metadata changed upstream:\n\n```\n" + "\n".join(f["diff"]) + "\n```\n\n"
        body += ("**To sync**: refresh the `legacy/` copies from upstream, re-run the extractor, review the "
                 "generated preset diff, and adjust the curated preset / module if the change is real "
                 "(resource defaults, port, privilege or device requirements).\n")
    else:
        body += ("The script no longer exists upstream. **To sync**: set `impl = \"unsupported\"` with "
                 "`unsupportedReason = \"removed upstream\"` in the curated preset (keep the legacy copy for "
                 "reference), or keep the entry alive deliberately if the NixOS module stands on its own.\n")
    body += "\n---\n_Filed by `.github/workflows/upstream-apps.yml` (`tools/upstream-diff.py`)._\n"
    return body


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def ensure_labels():
    for name, color, desc in [
        (LABEL, "0e8a16", "upstream community-scripts change the catalog must reflect"),
        ("upstream:new", "1d76db", "new upstream application"),
        ("upstream:changed", "fbca04", "upstream preset metadata changed"),
        ("upstream:removed", "d93f0b", "script removed upstream"),
    ]:
        subprocess.run(["gh", "label", "create", name, "--color", color, "--description", desc, "--force"],
                       check=False, capture_output=True, text=True)


def open_titles() -> set[str]:
    out = gh("issue", "list", "--label", LABEL, "--state", "open", "--limit", "1000", "--json", "title")
    return {i["title"] for i in json.loads(out)}


def emit_issues(findings: list[dict], sha: str, dry_run: bool) -> list[str]:
    created = []
    existing = set() if dry_run else open_titles()
    if not dry_run:
        ensure_labels()
    for f in findings:
        title = issue_title(f)
        if title in existing:
            continue
        if dry_run:
            created.append(f"(dry-run) {title}")
            continue
        url = gh("issue", "create", "--title", title, "--body", issue_body(f, sha),
                 "--label", LABEL, "--label", f"upstream:{f['type']}").strip()
        created.append(url)
    return created


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--upstream", required=True, help="checkout of community-scripts/ProxmoxVE")
    ap.add_argument("--root", default=str(HERE.parent))
    ap.add_argument("--json", help="write findings as JSON here")
    ap.add_argument("--emit-issues", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    mod = load_extractor()
    root, upstream = Path(a.root), Path(a.upstream)
    findings = scan(mod, root, upstream)
    sha = upstream_sha(upstream)
    counts = {t: sum(f["type"] == t for f in findings) for t in ("new", "changed", "removed")}
    summary = [f"upstream @ {sha[:12]}: {counts['new']} new, {counts['changed']} changed, {counts['removed']} removed"]
    for f in findings:
        summary.append(f"- {issue_title(f)}" + (f"  ({'; '.join(f['diff'][:3])})" if f["type"] == "changed" else ""))
    print("\n".join(summary))
    if a.json:
        Path(a.json).write_text(json.dumps({"upstream": sha, "findings": findings}, indent=2, default=str))
    if a.emit_issues:
        for line in emit_issues(findings, sha, a.dry_run):
            print(line)
    step = os.environ.get("GITHUB_STEP_SUMMARY")
    if step:
        Path(step).open("a").write("\n".join(summary) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
