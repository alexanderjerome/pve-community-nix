#!/usr/bin/env python3
"""Render this repo's options.json + catalog.json into the mdBook tree.

Pages:
  fleet/catalog.md        — the fleet.catalog.apps schema
  apps/base.md            — apps.base.* (the layer every catalog host has)
  apps/<name>.md          — one page per apps.<name> module
  catalog/index.md        — the catalog, grouped by category, with impl/status
  catalog/<category>.md   — one page per category

Hand-written pages (introduction, migration, requirements, legacy) stay
in src/. SUMMARY.md is fully generated.

Usage: generate.py <options.json> <catalog.json> <src-dir>
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path


def render_value(v) -> str:
    if v is None:
        return ""
    if isinstance(v, dict) and "_type" in v:
        return f"```nix\n{v.get('text', '')}\n```"
    return f"```nix\n{json.dumps(v, indent=2)}\n```"


def render_option(name: str, o: dict) -> str:
    parts = [f"### `{name}`\n"]
    desc = (o.get("description") or "").strip()
    if desc:
        parts.append(desc + "\n")
    parts.append(f"**Type:** `{o.get('type', '?')}`")
    if o.get("readOnly"):
        parts.append("**Read-only:** computed; not settable.")
    default = o.get("default")
    if default is not None:
        parts.append("**Default:**\n" + render_value(default))
    else:
        parts.append("**Default:** none (required when its feature is enabled)")
    example = o.get("example")
    if example is not None:
        parts.append("**Example:**\n" + render_value(example))
    links = []
    for d in o.get("declarations") or []:
        if isinstance(d, dict):
            links.append(f"[{d.get('name', 'source')}]({d.get('url', '')})")
        else:
            links.append(f"`{d}`")
    if links:
        parts.append("**Declared by:** " + ", ".join(links))
    return "\n\n".join(parts) + "\n\n---\n"


def group_of(name: str):
    parts = name.split(".")
    if parts[0] == "fleet" and len(parts) > 1 and parts[1] == "catalog":
        return ("fleet", "catalog")
    if parts[0] == "apps" and len(parts) > 1:
        return ("apps", parts[1])
    return None


def main(options_json: str, catalog_json: str, src_dir: str) -> None:
    opts = json.loads(Path(options_json).read_text())
    catalog = json.loads(Path(catalog_json).read_text())
    src = Path(src_dir)

    groups: dict[tuple[str, str], dict[str, dict]] = defaultdict(dict)
    for name, o in sorted(opts.items()):
        g = group_of(name)
        if g is None:
            continue
        groups[g][name] = o

    for (chapter, group), items in groups.items():
        d = src / chapter
        d.mkdir(parents=True, exist_ok=True)
        page = [f"# {chapter}.{group}\n", f"*{len(items)} options*\n"]
        page += [render_option(n, o) for n, o in items.items()]
        (d / f"{group}.md").write_text("\n".join(page))

    # ── Catalog pages ──
    by_cat: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    for slug, e in sorted(catalog.items()):
        by_cat[e.get("category", "misc")].append((slug, e))
    cdir = src / "catalog"
    cdir.mkdir(parents=True, exist_ok=True)
    impl_counts: dict[str, int] = defaultdict(int)
    for e in catalog.values():
        impl_counts[e.get("impl", "planned")] += 1
    idx = ["# Catalog\n",
           f"*{len(catalog)} applications in {len(by_cat)} categories.*\n",
           "| impl | count |", "|---|---|"]
    idx += [f"| `{k}` | {v} |" for k, v in sorted(impl_counts.items())]
    idx.append("")
    for cat in sorted(by_cat):
        idx.append(f"- [{cat}](./{cat}.md) — {len(by_cat[cat])} apps")
    (cdir / "index.md").write_text("\n".join(idx) + "\n")
    for cat, entries in by_cat.items():
        lines = [f"# {cat}\n",
                 "| app | title | port | impl | status | privileged | devices | upstream |",
                 "|---|---|---|---|---|---|---|---|"]
        for slug, e in entries:
            dev = ",".join(k for k, v in (e.get("devices") or {}).items() if v) or "—"
            url = (e.get("upstream") or {}).get("url", "")
            lines.append(
                f"| `{slug}` | {e.get('title', slug)} | {e.get('port') or '—'} | `{e.get('impl')}` | "
                f"`{e.get('status')}` | {'yes' if e.get('privileged') else 'no'} | {dev} | "
                f"{'[link](' + url + ')' if url else '—'} |")
            if e.get("impl") == "unsupported" and e.get("unsupportedReason"):
                lines.append(f"| | ↳ unsupported: {e['unsupportedReason']} | | | | | | |")
        (cdir / f"{cat}.md").write_text("\n".join(lines) + "\n")

    apps_groups = sorted(g for (c, g) in groups if c == "apps")
    apps_sorted = (["base"] if "base" in apps_groups else []) + [g for g in apps_groups if g != "base"]
    (src / "apps").mkdir(exist_ok=True)
    (src / "apps" / "index.md").write_text(
        "# App modules\n\nNixOS modules under `apps.<name>` — `apps.base` is the layer every "
        "catalog host carries; the rest are enabled by `mkApp` per host.\n\n"
        + "\n".join(f"- [`apps.{g}`](./{g}.md) — {len(groups[('apps', g)])} options" for g in apps_sorted) + "\n")

    summary = [
        "# Summary\n",
        "- [Introduction](./introduction.md)",
        "- [From community-scripts to the catalog](./migration.md)",
        "- [Requirements](./requirements.md)",
        "- [Catalog](./catalog/index.md)",
    ]
    summary += [f"  - [{cat}](./catalog/{cat}.md)" for cat in sorted(by_cat)]
    summary.append("- [Schema: fleet.catalog](./fleet/catalog.md)")
    summary.append("- [App modules](./apps/index.md)")
    summary += [f"  - [apps.{g}](./apps/{g}.md)" for g in apps_sorted]
    summary.append("- [Legacy scripts](./legacy.md)")
    (src / "SUMMARY.md").write_text("\n".join(summary) + "\n")
    print(f"rendered {sum(len(v) for v in groups.values())} options, {len(catalog)} catalog entries")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
