#!/usr/bin/env python3
"""
Generate a Midnight-aware API index from a wow-ui-source clone.

Parses every *Documentation.lua under Blizzard_APIDocumentationGenerated and
emits a markdown reference (docs/wow-api/) describing each system, its
functions, and -- critically -- which functions return Secret values and under
what condition (the SecretWhen* flags).

Usage:
    python scripts/gen_api_index.py [path-to-wow-ui-source]
Defaults to C:\\dev\\wow-ui-source when no path is given.

Read-only against wow-ui-source; only writes into docs/wow-api/.
Re-run after each game patch to refresh.
"""
import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone

# --- config -----------------------------------------------------------------
DEFAULT_SRC = r"C:\dev\wow-ui-source"
DOC_SUBPATH = Path("Interface") / "AddOns" / "Blizzard_APIDocumentationGenerated"
OUT_SUBPATH = Path("docs") / "wow-api"
REPO_ROOT = Path(__file__).resolve().parent.parent  # scripts/ -> repo root

# --- parsing -----------------------------------------------------------------
ENTRY_RE = re.compile(r'\{\s*\n\s*Name\s*=\s*"([^"]+)",\s*\n\s*Type\s*=\s*"(\w+)"')
SECRET_FLAG_RE = re.compile(r'(Secret(?:When|On|In)\w+)\s*=\s*true')
SECRET_ARGS_RE = re.compile(r'SecretArguments\s*=\s*"([^"]+)"')


def system_name(filename: str) -> str:
    base = filename[:-4] if filename.endswith(".lua") else filename
    for suffix in ("APIDocumentation", "Documentation"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    return base or filename


def parse_file(path: Path):
    """Return list of entry dicts: name, type, secret_flags, secret_args."""
    text = path.read_text(encoding="utf-8", errors="replace")
    entries = []
    matches = list(ENTRY_RE.finditer(text))
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[start:end]
        name, etype = m.group(1), m.group(2)
        flags = sorted(set(SECRET_FLAG_RE.findall(block)))
        args = SECRET_ARGS_RE.search(block)
        entries.append({
            "name": name,
            "type": etype,
            "secret_flags": flags,
            "secret_args": args.group(1) if args else None,
        })
    return entries

# --- output ------------------------------------------------------------------
def build(src_root: Path):
    doc_dir = src_root / DOC_SUBPATH
    if not doc_dir.is_dir():
        sys.exit(f"Docs dir not found: {doc_dir}")

    version_file = src_root / "version.txt"
    version = version_file.read_text(encoding="utf-8").strip() \
        if version_file.exists() else "unknown"

    systems = {}
    for lua in sorted(doc_dir.glob("*Documentation.lua")):
        entries = parse_file(lua)
        if entries:
            systems[system_name(lua.name)] = {"file": lua.name, "entries": entries}

    out_dir = REPO_ROOT / OUT_SUBPATH
    out_dir.mkdir(parents=True, exist_ok=True)

    total_fn = sum(len(s["entries"]) for s in systems.values())
    secret_entries = [
        (sys_name, e)
        for sys_name, s in systems.items()
        for e in s["entries"] if e["secret_flags"]
    ]

    (out_dir / "api-index.json").write_text(
        json.dumps({"version": version, "systems": systems}, indent=1),
        encoding="utf-8",
    )
    write_index_md(out_dir, version, systems, total_fn, secret_entries)
    write_secret_md(out_dir, version, secret_entries)

    return version, len(systems), total_fn, len(secret_entries)


def write_index_md(out_dir, version, systems, total_fn, secret_entries):
    lines = [
        f"# WoW API Index (build {version})",
        "",
        f"Generated from a `wow-ui-source` clone on "
        f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}.",
        f"Systems: {len(systems)} | Functions/events: {total_fn} | "
        f"Conditionally-secret entries: {len(secret_entries)}",
        "",
        "Regenerate with `python scripts/gen_api_index.py`.",
        "",
        "## How to use this",
        "",
        "- Find a function: search this file or `api-index.json` for its name.",
        "- The **system** maps to "
        "`Blizzard_APIDocumentationGenerated/<System>Documentation.lua` in the "
        "clone -- open that file for full Arguments/Returns signatures.",
        "- If an entry appears in `SECRET-VALUES.md`, its return becomes a "
        "Secret value under the listed condition. Guard with `issecretvalue()` "
        "before comparing, doing arithmetic, or using it as a table key.",
        "",
        "## Systems",
        "",
    ]
    for name in sorted(systems):
        s = systems[name]
        n = len(s["entries"])
        n_secret = sum(1 for e in s["entries"] if e["secret_flags"])
        flag = f" -- {n_secret} secret" if n_secret else ""
        lines.append(f"- **{name}** ({n}){flag} -- `{s['file']}`")
    (out_dir / "INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_secret_md(out_dir, version, secret_entries):
    by_cond = {}
    for sys_name, e in secret_entries:
        for flag in e["secret_flags"]:
            by_cond.setdefault(flag, []).append((sys_name, e["name"]))

    lines = [
        f"# Secret Values -- conditionally-secret API (build {version})",
        "",
        "Functions whose return value becomes a **Secret** under the given "
        "condition. In tainted addon code you must call `issecretvalue(v)` "
        "before any comparison, arithmetic, or table-index on the result -- "
        "otherwise the game raises a Lua error.",
        "",
        f"Total: {len(secret_entries)} entries across {len(by_cond)} conditions.",
        "",
    ]
    for cond in sorted(by_cond):
        items = sorted(set(by_cond[cond]))
        lines.append(f"## `{cond}` ({len(items)})")
        lines.append("")
        for sys_name, fn in items:
            lines.append(f"- `{fn}` -- {sys_name}")
        lines.append("")
    (out_dir / "SECRET-VALUES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(DEFAULT_SRC)
    v, ns_, nf, nsec = build(root)
    print(f"OK: build {v} | {ns_} systems | {nf} entries | {nsec} secret entries")
