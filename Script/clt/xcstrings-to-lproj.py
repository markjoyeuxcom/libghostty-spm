#!/usr/bin/env python3
"""Compile Localizable.xcstrings into <lang>.lproj/Localizable.strings tables.

SwiftPM's default build engine hands an .xcstrings resource to xcstringstool,
which ships only inside Xcode.app. The tables this writes need no tool:
SwiftPM copies .strings files as they are. Only plain stringUnit entries are
handled; a key with variations (plurals, devices) is refused so the omission
is loud rather than silent. The source language is written too, so a lookup
in it never falls through to the key.
"""
import json
import sys
from pathlib import Path


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main(catalog_path: str, output_root: str) -> int:
    catalog = json.loads(Path(catalog_path).read_text(encoding="utf-8"))
    source_language = catalog["sourceLanguage"]
    tables: dict[str, dict[str, str]] = {}
    for key, entry in catalog["strings"].items():
        localizations = entry.get("localizations", {})
        tables.setdefault(source_language, {})[key] = key
        for language, localization in localizations.items():
            if "stringUnit" not in localization:
                print(f"{key} ({language}): only stringUnit entries are supported", file=sys.stderr)
                return 1
            unit = localization["stringUnit"]
            if unit.get("state") != "translated":
                continue
            tables.setdefault(language, {})[key] = unit["value"]
    root = Path(output_root)
    for language, strings in sorted(tables.items()):
        directory = root / f"{language}.lproj"
        directory.mkdir(parents=True, exist_ok=True)
        lines = [f'"{escape(key)}" = "{escape(value)}";' for key, value in sorted(strings.items())]
        (directory / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {len(tables)} tables under {root}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: xcstrings-to-lproj.py <Localizable.xcstrings> <output directory>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
