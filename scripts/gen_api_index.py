#!/usr/bin/env python3
"""
Generate a Midnight-aware API index from a wow-ui-source clone.

Parses every *Documentation.lua under Blizzard_APIDocumentationGenerated and
emits a markdown reference (docs/wow-api/) describing each system, its
functions, and -- critically -- which functions return Secret values and under
what condition (the SecretWhen* flags).

Also emits predicate Documentation, addon restriction enums, and function
signatures (Arguments/Returns) into the digest.

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

RELATED_SECRET_CONDITIONS = {
    "SecretWhenUnitStatsRestricted": ["SecretWhenUnitAuraRestricted"],
}

# --- parsing -----------------------------------------------------------------
ENTRY_RE = re.compile(r'\{\s*\n\s*Name\s*=\s*"([^"]+)",\s*\n\s*Type\s*=\s*"(\w+)"')
SECRET_FLAG_RE = re.compile(r'(Secret(?:When|On|In)\w+)\s*=\s*true')
SECRET_ARGS_RE = re.compile(r'SecretArguments\s*=\s*"([^"]+)"')
LITERAL_NAME_RE = re.compile(r'LiteralName\s*=\s*"([^"]+)"')
DOC_STRINGS_RE = re.compile(r'Documentation\s*=\s*\{([^}]*)\}', re.DOTALL)
DOC_TEXT_RE = re.compile(r'"([^"]*)"')
SIG_ENTRY_RE = re.compile(
    r'\{\s*Name\s*=\s*"([^"]+)",\s*Type\s*=\s*"([^"]+)",\s*Nilable\s*=\s*(\w+)\s*\}'
)
ENUM_FIELD_RE = re.compile(
    r'\{\s*Name\s*=\s*"([^"]+)",\s*Type\s*=\s*"[^"]+",\s*EnumValue\s*=\s*(\d+)'
    r'(?:,\s*Documentation\s*=\s*\{\s*"([^"]*)"\s*\})?\s*\}'
)


def system_name(filename: str) -> str:
    base = filename[:-4] if filename.endswith(".lua") else filename
    for suffix in ("APIDocumentation", "Documentation"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    return base or filename


def parse_documentation(block: str) -> str | None:
    match = DOC_STRINGS_RE.search(block)
    if not match:
        return None
    parts = DOC_TEXT_RE.findall(match.group(1))
    if not parts:
        return None
    return " ".join(parts)


def extract_braced_section(block: str, key: str) -> str:
    match = re.search(rf'{key}\s*=\s*\{{', block)
    if not match:
        return ""
    start = match.end() - 1
    depth = 0
    for index in range(start, len(block)):
        char = block[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return block[start:index + 1]
    return ""


def parse_signature_section(block: str, key: str) -> list[dict]:
    section = extract_braced_section(block, key)
    if not section:
        return []
    return [
        {"name": name, "type": typ, "nilable": nilable == "true"}
        for name, typ, nilable in SIG_ENTRY_RE.findall(section)
    ]


def parse_file(path: Path):
    """Return list of entry dicts with secret flags, docs, and signatures."""
    text = path.read_text(encoding="utf-8", errors="replace")
    entries = []
    matches = list(ENTRY_RE.finditer(text))
    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[start:end]
        name, etype = match.group(1), match.group(2)
        flags = sorted(set(SECRET_FLAG_RE.findall(block)))
        args = SECRET_ARGS_RE.search(block)
        literal = LITERAL_NAME_RE.search(block)
        entries.append({
            "name": name,
            "type": etype,
            "literal_name": literal.group(1) if literal else None,
            "secret_flags": flags,
            "secret_args": args.group(1) if args else None,
            "documentation": parse_documentation(block),
            "arguments": parse_signature_section(block, "Arguments"),
            "returns": parse_signature_section(block, "Returns"),
            "payload": parse_signature_section(block, "Payload"),
        })
    return entries


def parse_secret_predicates(path: Path) -> dict:
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    predicates = {}
    for match in ENTRY_RE.finditer(text):
        start = match.start()
        next_match = next(ENTRY_RE.finditer(text, match.end()), None)
        end = next_match.start() if next_match else len(text)
        block = text[start:end]
        name, ptype = match.group(1), match.group(2)
        predicates[name] = {
            "type": ptype,
            "documentation": parse_documentation(block),
        }
    return predicates


def parse_addon_restrictions(path: Path) -> dict:
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    enums = {}
    for table_match in re.finditer(
        r'Name = "([^"]+)",\s*\n\s*Type = "Enumeration".*?Fields\s*=\s*\{(.*?)\n\s*\},',
        text,
        re.DOTALL,
    ):
        enum_name = table_match.group(1)
        fields = []
        for field_match in ENUM_FIELD_RE.finditer(table_match.group(2)):
            fields.append({
                "name": field_match.group(1),
                "enum_value": int(field_match.group(2)),
                "documentation": field_match.group(3) or None,
            })
        fields.sort(key=lambda item: item["enum_value"])
        enums[enum_name] = fields
    return enums


def pick_restricted_actions_notes(systems: dict) -> dict:
    """Surface key restriction helpers/events from the parsed API tables."""
    restricted = systems.get("RestrictedActions", {}).get("entries", [])
    picked = {}
    wanted = {
        "GetAddOnRestrictionState",
        "IsAddOnRestrictionActive",
        "AddonRestrictionStateChanged",
    }
    for entry in restricted:
        if entry["name"] not in wanted:
            continue
        picked[entry["name"]] = {
            "type": entry["type"],
            "literal_name": entry.get("literal_name"),
            "documentation": entry.get("documentation"),
            "arguments": entry.get("arguments") or [],
            "returns": entry.get("returns") or [],
            "payload": entry.get("payload") or [],
            "secret_args": entry.get("secret_args"),
        }
    return picked


# --- output ------------------------------------------------------------------
def build(src_root: Path):
    doc_dir = src_root / DOC_SUBPATH
    if not doc_dir.is_dir():
        sys.exit(f"Docs dir not found: {doc_dir}")

    version_file = src_root / "version.txt"
    version = version_file.read_text(encoding="utf-8").strip() \
        if version_file.exists() else "unknown"

    secret_predicates = parse_secret_predicates(doc_dir / "SecretPredicatesDocumentation.lua")
    addon_restrictions = parse_addon_restrictions(
        doc_dir / "RestrictedActionsConstantsDocumentation.lua"
    )

    systems = {}
    for lua in sorted(doc_dir.glob("*Documentation.lua")):
        entries = parse_file(lua)
        if entries:
            systems[system_name(lua.name)] = {"file": lua.name, "entries": entries}

    restriction_helpers = pick_restricted_actions_notes(systems)

    out_dir = REPO_ROOT / OUT_SUBPATH
    out_dir.mkdir(parents=True, exist_ok=True)

    total_fn = sum(len(s["entries"]) for s in systems.values())
    secret_entries = [
        (sys_name, e)
        for sys_name, s in systems.items()
        for e in s["entries"] if e["secret_flags"]
    ]

    digest = {
        "version": version,
        "secret_predicates": secret_predicates,
        "addon_restrictions": addon_restrictions,
        "restriction_helpers": restriction_helpers,
        "systems": systems,
    }
    (out_dir / "api-index.json").write_text(
        json.dumps(digest, indent=1),
        encoding="utf-8",
    )
    write_index_md(out_dir, version, systems, total_fn, secret_entries)
    write_secret_md(out_dir, version, secret_entries, secret_predicates)
    write_addon_restrictions_md(
        out_dir, version, addon_restrictions, restriction_helpers
    )

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
        "clone -- open that file only when you need more than the digest provides.",
        "- **`SECRET-VALUES.md`** -- functions whose return becomes Secret, "
        "grouped by condition, with Blizzard predicate descriptions.",
        "- **`ADDON-RESTRICTIONS.md`** -- `AddOnRestrictionType` / "
        "`AddOnRestrictionState` enums and key restriction events/APIs.",
        "- **`api-index.json`** -- machine-readable digest including predicate "
        "docs, restriction enums, and Arguments/Returns signatures.",
        "- If an entry appears in `SECRET-VALUES.md`, guard with "
        "`issecretvalue()` before comparing, doing arithmetic, or using it as "
        "a table key.",
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


def format_signature(entries: list[dict]) -> str:
    if not entries:
        return ""
    parts = []
    for entry in entries:
        nilable = ", nilable" if entry.get("nilable") else ""
        parts.append(f"`{entry['name']}`: {entry['type']}{nilable}")
    return ", ".join(parts)


def write_secret_md(out_dir, version, secret_entries, secret_predicates):
    by_cond = {}
    entry_meta = {}
    for sys_name, entry in secret_entries:
        for flag in entry["secret_flags"]:
            by_cond.setdefault(flag, []).append((sys_name, entry["name"]))
            entry_meta[(flag, sys_name, entry["name"])] = entry

    lines = [
        f"# Secret Values -- conditionally-secret API (build {version})",
        "",
        "Functions whose return value becomes a **Secret** under the given "
        "condition. In tainted addon code you must call `issecretvalue(v)` "
        "before any comparison, arithmetic, or table-index on the result -- "
        "otherwise the game raises a Lua error.",
        "",
        "Predicate descriptions come from `SecretPredicatesDocumentation.lua`. "
        "See also `ADDON-RESTRICTIONS.md` for restriction types such as "
        "Challenge Mode (Mythic+).",
        "",
        f"Total: {len(secret_entries)} entries across {len(by_cond)} conditions.",
        "",
    ]
    for cond in sorted(by_cond):
        items = sorted(set(by_cond[cond]))
        lines.append(f"## `{cond}` ({len(items)})")
        lines.append("")
        predicate = secret_predicates.get(cond, {})
        if predicate.get("documentation"):
            lines.append(f"> {predicate['documentation']}")
            lines.append("")
        related = RELATED_SECRET_CONDITIONS.get(cond, [])
        related_docs = [
            f"`{name}`: {secret_predicates[name]['documentation']}"
            for name in related
            if secret_predicates.get(name, {}).get("documentation")
        ]
        if related_docs:
            lines.append("> **Related:** " + " ".join(related_docs))
            lines.append("")
        for sys_name, fn in items:
            meta = entry_meta.get((cond, sys_name, fn), {})
            suffix = f" -- {sys_name}"
            if meta.get("secret_args"):
                suffix += f" (`SecretArguments`: {meta['secret_args']})"
            lines.append(f"- `{fn}`{suffix}")
        lines.append("")
    (out_dir / "SECRET-VALUES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_addon_restrictions_md(out_dir, version, addon_restrictions, restriction_helpers):
    lines = [
        f"# Addon Restrictions (build {version})",
        "",
        "Generated from `RestrictedActionsConstantsDocumentation.lua` and "
        "selected entries in `RestrictedActionsDocumentation.lua`.",
        "",
        "Use this to interpret `ADDON_RESTRICTION_STATE_CHANGED`, "
        "`GetAddOnRestrictionState`, and `IsAddOnRestrictionActive`.",
        "",
    ]

    for enum_name in sorted(addon_restrictions):
        fields = addon_restrictions[enum_name]
        lines.append(f"## `{enum_name}`")
        lines.append("")
        for field in fields:
            doc = field.get("documentation")
            doc_suffix = f" -- {doc}" if doc else ""
            lines.append(
                f"- **`{field['name']}`** = `{field['enum_value']}`{doc_suffix}"
            )
        lines.append("")

    if restriction_helpers:
        lines.append("## Key APIs and events")
        lines.append("")
        for name in sorted(restriction_helpers):
            entry = restriction_helpers[name]
            title = f"`{name}`"
            if entry.get("literal_name"):
                title += f" / `{entry['literal_name']}`"
            lines.append(f"### {title} ({entry['type']})")
            lines.append("")
            if entry.get("documentation"):
                lines.append(entry["documentation"])
                lines.append("")
            if entry.get("arguments"):
                lines.append(f"- **Arguments:** {format_signature(entry['arguments'])}")
            if entry.get("returns"):
                lines.append(f"- **Returns:** {format_signature(entry['returns'])}")
            if entry.get("payload"):
                lines.append(f"- **Payload:** {format_signature(entry['payload'])}")
            if entry.get("secret_args"):
                lines.append(f"- **SecretArguments:** `{entry['secret_args']}`")
            lines.append("")

    (out_dir / "ADDON-RESTRICTIONS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(DEFAULT_SRC)
    v, ns_, nf, nsec = build(root)
    print(f"OK: build {v} | {ns_} systems | {nf} entries | {nsec} secret entries")
