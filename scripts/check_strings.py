#!/usr/bin/env python3
"""Fail if any exported string lacks a translation in a shipping language.

Usage: python3 scripts/check_strings.py <dir with exported *.xcloc>

Reads the XLIFF files Xcode wrote with `-exportLocalizations` and lists every
<trans-unit> without a <target> (or whose target state is "new").
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def main(root: Path) -> int:
    missing: dict[str, set[str]] = {}
    for xliff in sorted(root.rglob("*.xliff")):
        lang = xliff.stem
        for file in ET.parse(xliff).getroot().findall("x:file", NS):
            for unit in file.iter(f"{{{NS['x']}}}trans-unit"):
                if unit.get("translate") == "no":
                    continue
                target = unit.find("x:target", NS)
                if target is None or not (target.text or "").strip() or target.get("state") == "new":
                    source = unit.find("x:source", NS)
                    missing.setdefault(lang, set()).add(f"{file.get('original')}: {source.text if source is not None else unit.get('id')}")
    for lang, items in sorted(missing.items()):
        print(f"::error::{lang}: {len(items)} untranslated strings")
        for item in sorted(items)[:400]:
            print("  ", item)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
