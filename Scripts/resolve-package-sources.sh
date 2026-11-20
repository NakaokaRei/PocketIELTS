#!/bin/bash
# BUILD_DIR is nested more deeply during Archive than during a normal build.
set -euo pipefail
if [[ -n "${LICENSE_PLIST_PACKAGE_SOURCES_PATH:-}" ]]; then
    candidate="$LICENSE_PLIST_PACKAGE_SOURCES_PATH"
    [[ -d "$candidate/checkouts" ]] || { echo "error: Missing package checkouts at configured path: $candidate" >&2; exit 1; }
    printf '%s\n' "$candidate"
    exit 0
fi
ancestor="${1:?Usage: resolve-package-sources.sh BUILD_DIR}"
while [[ "$ancestor" != / && "$ancestor" != . ]]; do
    if [[ -d "$ancestor/SourcePackages/checkouts" ]]; then
        printf '%s\n' "$ancestor/SourcePackages"
        exit 0
    fi
    ancestor="$(dirname "$ancestor")"
done
echo 'error: Cannot locate SourcePackages/checkouts. Resolve Swift packages or set LICENSE_PLIST_PACKAGE_SOURCES_PATH for a custom checkout directory.' >&2
exit 1
