#!/bin/bash
# A fixed, checksum-verified tool shared by local builds and CI.
set -euo pipefail
version=3.28.3
checksum=5b5be263636889415b0dceca736f9ca8cf8f3ed23f80ed675a52c7ddd4842f06
if [[ -n "${LICENSE_PLIST_BIN:-}" ]]; then
    [[ -x "$LICENSE_PLIST_BIN" ]] || { echo 'error: LICENSE_PLIST_BIN must be executable.' >&2; exit 1; }
    printf '%s\n' "$LICENSE_PLIST_BIN"
    exit 0
fi
cache="${LICENSE_PLIST_CACHE:-${HOME}/Library/Caches/PocketIELTS/LicensePlist}/$version"
if [[ ! -x "$cache/license-plist" ]]; then
    mkdir -p "$cache"
    staging="$(mktemp -d "$cache/download.XXXXXX")"
    trap 'rm -rf "$staging"' EXIT
    echo "Installing LicensePlist $version (first build only)…" >&2
    curl --fail --location --retry 3 "https://github.com/mono0926/LicensePlist/releases/download/$version/license-plist.zip" -o "$staging/tool.zip" >&2
    echo "$checksum  $staging/tool.zip" | shasum -a 256 -c - >&2
    unzip -q "$staging/tool.zip" -d "$staging/unpacked"
    chmod +x "$staging/unpacked/license-plist"
    mv "$staging/unpacked/license-plist" "$cache/license-plist"
fi
printf '%s\n' "$cache/license-plist"
