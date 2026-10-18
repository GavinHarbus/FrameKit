"""Check catalogs against the strings actually extracted by a Debug build.

Run from the repository root after xcodebuild -derivedDataPath build build/test.
"""
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "Resources/Localizable.xcstrings").read_text())
errors = []
keys = set()
extracted_files = 0
intermediates = root / "build/Build/Intermediates.noindex/FrameKit.build/Debug"
for target in ("FrameKit", "FrameKitCore"):
    for path in (intermediates / (target + ".build")).glob("Objects-normal/*/*.stringsdata"):
        extracted_files += 1
        data = json.loads(path.read_text())
        keys.update(entry["key"] for entry in data.get("tables", {}).get("Localizable", []))

if not extracted_files or not keys:
    sys.exit("Build the Debug target with -derivedDataPath build before checking localization.")

for key in sorted(keys):
    if key not in catalog["strings"]:
        errors.append(f"Missing catalog entry: {key!r}")

def values(entry):
    if "stringUnit" in entry:
        yield entry["stringUnit"]
    for variations in entry.get("variations", {}).values():
        for variant in variations.values():
            yield from values(variant)
    for substitution in entry.get("substitutions", {}).values():
        yield from values(substitution)

for path in (root / "Resources").glob("*.xcstrings"):
    data = json.loads(path.read_text())
    if data["sourceLanguage"] != "en":
        errors.append(f"{path.name}: expected English source language")
    for key, entry in data["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        for language in ("en", "zh-Hans"):
            units = list(values(entry.get("localizations", {}).get(language, {})))
            if not units or any(not u.get("value") or u.get("state") != "translated" for u in units):
                errors.append(f"{path.name}: incomplete {language} translation: {key!r}")

for path in (root / "Sources").rglob("*.swift"):
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if re.search(r"[一-鿿]", line):
            errors.append(f"{path.relative_to(root)}:{number}: Chinese text should live in the catalog")

if errors:
    sys.exit("\n".join(errors))
print(f"PASS: all {len(keys)} extracted keys are covered; English and Simplified Chinese catalogs are complete.")
