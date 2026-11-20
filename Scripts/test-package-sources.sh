#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
unset LICENSE_PLIST_PACKAGE_SOURCES_PATH
mkdir -p "$fixture/Derived Data/SourcePackages/checkouts" "$fixture/Custom/checkouts"
expected="$fixture/Derived Data/SourcePackages"
[[ "$(bash Scripts/resolve-package-sources.sh "$fixture/Derived Data/Build/Products")" == "$expected" ]]
[[ "$(bash Scripts/resolve-package-sources.sh "$fixture/Derived Data/Build/Intermediates.noindex/ArchiveIntermediates/PocketIELTS/BuildProductsPath")" == "$expected" ]]
[[ "$(LICENSE_PLIST_PACKAGE_SOURCES_PATH="$fixture/Custom" bash Scripts/resolve-package-sources.sh "$fixture/Elsewhere")" == "$fixture/Custom" ]]
if LICENSE_PLIST_PACKAGE_SOURCES_PATH="$fixture/Missing" bash Scripts/resolve-package-sources.sh "$fixture/Derived Data/Build/Products" 2>/dev/null; then exit 1; fi
if bash Scripts/resolve-package-sources.sh "$fixture/Missing" 2>/dev/null; then exit 1; fi
echo 'Package source lookup passed: Build, Archive, custom path, and missing checkout errors.'
