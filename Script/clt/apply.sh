#!/bin/sh
# Applies the Command Line Tools patch to the checkout it runs in: compiles
# the string catalog into .lproj tables with Script/clt/xcstrings-to-lproj.py
# and points the three manifests at the tables instead of the catalog, so the
# package builds without Xcode's xcstringstool. Idempotent.
set -eu
cd "$(dirname "$0")/../.."
catalog=Sources/GhosttyTerminal/Resources/Localizable.xcstrings
tables=Sources/GhosttyTerminal/Resources/Localizations
# Since 2.2.2026101301 upstream ships the catalog compiled to .lproj tables
# itself (Resources/Localization) and no manifest processes the catalog, so
# there is nothing to patch; the package already builds with the Command
# Line Tools alone.
if ! grep -qs 'Resources/Localizable.xcstrings' Package.swift Package.local.swift Package.swift.template; then
  echo "clt: nothing to patch; the manifests process no string catalog"
  exit 0
fi
rm -rf "$tables"
python3 Script/clt/xcstrings-to-lproj.py "$catalog" "$tables"
for manifest in Package.swift Package.local.swift Package.swift.template; do
  [ -f "$manifest" ] || continue
  grep -q 'Resources/Localizable.xcstrings' "$manifest" || continue
  perl -0pi -e 's|(\n(\s+)path: "Sources/GhosttyTerminal",\n)(\s+resources: \[\n(?:.*\n)*?\s+)\.process\("Resources/Localizable\.xcstrings"\),\n|$1$2exclude: ["Resources/Localizable.xcstrings"],\n$3.process("Resources/Localizations"),\n|' "$manifest"
  grep -q 'Resources/Localizations' "$manifest" || { echo "clt: could not patch $manifest" >&2; exit 1; }
done
echo "clt: patched"
