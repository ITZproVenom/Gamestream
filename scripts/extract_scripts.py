#!/usr/bin/env python3
"""Pulls the page scripts out of the Swift source, so they can be tested.

The scripts the app runs in the web page live inside the Swift files as
raw strings. Testing them means testing what the app actually runs, not a
copy that can drift away from it, so they are taken straight out of the
source here.

    python3 scripts/extract_scripts.py [outdir]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "GameStream", "Core", "WebScripts.swift")
RUMBLE = os.path.join(ROOT, "GameStream", "Services", "Rumble.swift")

WANTED = ["touchInputJS", "cloudServersJS", "gamepadBridgeJS", "streamChromeJS",
          "streamCommandsJS", "xboxSearchResultsJS", "cloudCatalogueJS",
          "autoStartJS", "captureJS", "clipJS", "pageSignalsJS", "streamStateJS"]


def extract(path):
    """The raw strings in a Swift file, by the name they are given."""
    if not os.path.exists(path):
        return {}
    text = open(path, encoding="utf-8").read()
    found = {}
    for m in re.finditer(r'static let (\w+) = #"""\n(.*?)\n    """#', text, re.S):
        found[m.group(1)] = m.group(2)
    for m in re.finditer(r'static let (\w+) = #"""\n(.*?)\n"""#', text, re.S):
        found.setdefault(m.group(1), m.group(2))
    return found


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gamestream-scripts"
    os.makedirs(outdir, exist_ok=True)
    scripts = extract(SOURCE)
    scripts.update(extract(RUMBLE))
    written = []
    for name in WANTED:
        if name not in scripts:
            print(f"  missing: {name}", file=sys.stderr)
            continue
        path = os.path.join(outdir, name + ".js")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(scripts[name])
        written.append(path)
    print(f"extracted {len(written)} scripts into {outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
