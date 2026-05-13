"""
map_codebase.py
Scans every .dart (lib/) and .py (python-backend/app/) file in MarketCoach,
parses imports, and writes one Obsidian note per file to:
  ObsidianVaults/Marketcoachvault/CodeMap/

Run:  python docs/map_codebase.py
Re-run any time to refresh the graph.
"""

import os
import re
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
# Auto-detects whether running on Windows or Linux (Claude sandbox).
import sys
if sys.platform == "win32":
    MARKET_COACH = Path(r"C:\Users\sandi\market_coach")
    VAULT_CODEMAP = Path(r"C:\Users\sandi\ObsidianVaults\Marketcoachvault\CodeMap")
else:
    _MNT = Path("/sessions/optimistic-sharp-planck/mnt")
    MARKET_COACH  = _MNT / "market_coach"
    VAULT_CODEMAP = _MNT / "ObsidianVaults" / "Marketcoachvault" / "CodeMap"

DART_ROOT  = MARKET_COACH / "lib"
PY_ROOT    = MARKET_COACH / "python-backend" / "app"

# Layer labels for grouping nodes in the graph
DART_LAYERS = {
    "app":        "🏠 Shell",
    "config":     "⚙️ Config",
    "core":       "🔩 Core",
    "data":       "🗄️ Data",
    "features":   "✨ Feature",
    "models":     "📦 Model",
    "providers":  "🔌 Provider",
    "screens":    "🖥️ Screen",
    "services":   "🌐 Service",
    "theme":      "🎨 Theme",
    "utils":      "🛠️ Util",
    "widgets":    "🧩 Widget",
}
PY_LAYERS = {
    "routers":       "🛣️ Router",
    "services":      "⚙️ Service",
    "agents":        "🤖 Agent",
    "orchestrator":  "🧠 Orchestrator",
    "workers":       "👷 Worker",
    "repositories":  "🗄️ Repository",
    "models":        "📦 Model",
    "utils":         "🛠️ Util",
    "core":          "🔩 Core",
}


# ── Helpers ───────────────────────────────────────────────────────────────────

def note_name(rel_path: str) -> str:
    """Convert a relative path to a flat note name without extension."""
    return rel_path.replace("\\", "/").replace(".dart", "").replace(".py", "")


def safe_name(note: str) -> str:
    """Last component of path — used as display text in links."""
    return note.split("/")[-1]


def layer_tag(rel_path: str, layer_map: dict) -> str:
    top = rel_path.replace("\\", "/").split("/")[0]
    return layer_map.get(top, "📄 Other")


def extract_dart_imports(src: str, file_rel: str) -> list[str]:
    """Return note names for every local lib/ import in a Dart file."""
    results = []
    for line in src.splitlines():
        m = re.match(r"""^\s*import\s+['"](.+?)['"]\s*;""", line)
        if not m:
            continue
        raw = m.group(1)

        # package:market_coach/xxx  →  xxx
        if raw.startswith("package:market_coach/"):
            rel = raw.replace("package:market_coach/", "")
            results.append(note_name(rel))

        # relative  ../../services/foo.dart  →  resolve from file_rel
        elif raw.startswith("."):
            base = Path(file_rel).parent
            resolved = (base / raw).resolve()
            try:
                rel = resolved.relative_to(Path("lib"))
                results.append(note_name(str(rel)))
            except ValueError:
                pass  # outside lib/

        # dart: / flutter: / package: (external) — skip
    return results


def extract_python_imports(src: str, file_rel: str) -> list[str]:
    """Return note names for every local app/ import in a Python file."""
    results = []
    for line in src.splitlines():
        # from app.xxx.yyy import ...
        m = re.match(r"^\s*from\s+(app(?:\.\w+)+)\s+import", line)
        if m:
            mod = m.group(1).replace(".", "/")
            # try with .py suffix first, then __init__
            results.append(mod)
            continue

        # from .xxx import ...   (relative)
        m = re.match(r"^\s*from\s+(\.\w+)\s+import", line)
        if m:
            rel_mod = m.group(1).lstrip(".")
            base = Path(file_rel).parent
            results.append(note_name(str(base / rel_mod)))
            continue

        # import app.xxx
        m = re.match(r"^\s*import\s+(app(?:\.\w+)+)", line)
        if m:
            mod = m.group(1).replace(".", "/")
            results.append(mod)

    return results


def extract_dart_symbols(src: str) -> list[str]:
    """Pull class, mixin, extension, provider names from Dart source."""
    symbols = []
    for line in src.splitlines():
        m = re.match(r"^\s*(?:abstract\s+)?(?:class|mixin|extension|enum)\s+(\w+)", line)
        if m:
            symbols.append(m.group(1))
        # Riverpod providers  final xyzProvider = ...
        m = re.match(r"^\s*final\s+(\w+Provider)\s*=", line)
        if m and m.group(1) not in symbols:
            symbols.append(m.group(1))
    return symbols[:12]   # cap at 12 so notes don't get huge


def extract_python_symbols(src: str) -> list[str]:
    """Pull class and top-level def names from Python source."""
    symbols = []
    for line in src.splitlines():
        m = re.match(r"^class\s+(\w+)", line)
        if m:
            symbols.append("class " + m.group(1))
        m = re.match(r"^(?:async\s+)?def\s+(\w+)", line)
        if m:
            symbols.append("def " + m.group(1))
    return symbols[:12]


def write_note(note_path: Path, title: str, tag: str,
               rel_path: str, symbols: list[str], deps: list[str],
               lang: str):
    note_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"# {title}",
        f"> {tag} · `{rel_path}`",
        "",
    ]

    if symbols:
        lines += ["## Symbols", ""]
        for s in symbols:
            lines.append(f"- `{s}`")
        lines.append("")

    if deps:
        lines += ["## Imports", ""]
        seen = set()
        for d in deps:
            if d in seen:
                continue
            seen.add(d)
            display = safe_name(d)
            # Note: wiki-link uses just the last path component so Obsidian
            # resolves it uniquely within the vault's flat search.
            lines.append(f"- [[{display}]]")
        lines.append("")

    lines += [
        "## Used By",
        "",
        "> _Backlinks appear here automatically in Obsidian._",
        "",
    ]

    note_path.write_text("\n".join(lines), encoding="utf-8")


# ── Main ──────────────────────────────────────────────────────────────────────

def map_dart():
    count = 0
    for dart_file in sorted(DART_ROOT.rglob("*.dart")):
        try:
            src = dart_file.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue

        rel = dart_file.relative_to(DART_ROOT)
        rel_str = str(rel)
        nname = note_name(rel_str)           # e.g. "services/backend_service"
        title = safe_name(nname)             # e.g. "backend_service"
        tag   = layer_tag(rel_str, DART_LAYERS)
        deps  = extract_dart_imports(src, rel_str)
        syms  = extract_dart_symbols(src)

        out = VAULT_CODEMAP / "flutter" / (nname + ".md")
        write_note(out, title, tag, "lib/" + rel_str, syms, deps, "dart")
        count += 1

    print(f"  Flutter: {count} notes")


def map_python():
    count = 0
    for py_file in sorted(PY_ROOT.rglob("*.py")):
        if py_file.name == "__init__.py":
            continue
        try:
            src = py_file.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue

        rel = py_file.relative_to(PY_ROOT)
        rel_str = str(rel)
        nname = note_name(rel_str)
        title = safe_name(nname)
        tag   = layer_tag(rel_str, PY_LAYERS)
        deps  = extract_python_imports(src, rel_str)
        syms  = extract_python_symbols(src)

        out = VAULT_CODEMAP / "backend" / (nname + ".md")
        write_note(out, title, tag, "python-backend/app/" + rel_str, syms, deps, "python")
        count += 1

    print(f"  Backend: {count} notes")


def write_index(dart_count: int, py_count: int):
    """Write the CodeMap index note with links to every layer."""
    lines = [
        "# CodeMap — Index",
        "> Auto-generated by `docs/map_codebase.py`. Re-run to refresh.",
        "> See also [[Analyst_Logic_Master]] · [[Active_Context]]",
        "",
        "## Flutter (`lib/`)",
        "",
    ]
    dart_layers_seen = set()
    for dart_file in sorted((VAULT_CODEMAP / "flutter").rglob("*.md")):
        rel = dart_file.relative_to(VAULT_CODEMAP / "flutter")
        top = str(rel).replace("\\", "/").split("/")[0]
        if top not in dart_layers_seen:
            tag = DART_LAYERS.get(top, "📄 Other")
            lines.append(f"### {tag} `{top}/`")
            lines.append("")
            dart_layers_seen.add(top)
        name = dart_file.stem
        lines.append(f"- [[{name}]]")
    lines.append("")
    lines += ["## Backend (`python-backend/app/`)", ""]
    py_layers_seen = set()
    for py_file in sorted((VAULT_CODEMAP / "backend").rglob("*.md")):
        rel = py_file.relative_to(VAULT_CODEMAP / "backend")
        top = str(rel).replace("\\", "/").split("/")[0]
        if top not in py_layers_seen:
            tag = PY_LAYERS.get(top, "📄 Other")
            lines.append(f"### {tag} `{top}/`")
            lines.append("")
            py_layers_seen.add(top)
        name = py_file.stem
        lines.append(f"- [[{name}]]")

    idx = VAULT_CODEMAP / "CodeMap_Index.md"
    idx.write_text("\n".join(lines), encoding="utf-8")
    print(f"  Index:   {idx}")


if __name__ == "__main__":
    print("MarketCoach → Obsidian CodeMap")
    print(f"  Output: {VAULT_CODEMAP}")
    VAULT_CODEMAP.mkdir(parents=True, exist_ok=True)

    map_dart()
    map_python()

    # Count generated notes for the index
    dart_count = len(list((VAULT_CODEMAP / "flutter").rglob("*.md")))
    py_count   = len(list((VAULT_CODEMAP / "backend").rglob("*.md")))
    write_index(dart_count, py_count)

    print(f"\nDone — {dart_count + py_count} notes written.")
    print("Open Obsidian, switch to Marketcoachvault, press Ctrl+G to see the graph.")
