#!/bin/bash
# Run after Copy Bundle Resources, before code signing, for Debug and Release.
set -euo pipefail
cd "${SRCROOT:?}"
source_packages="${LICENSE_PLIST_PACKAGE_SOURCES_PATH:-$(dirname "$(dirname "${BUILD_DIR:?}")")/SourcePackages}"
mkdir -p "${DERIVED_FILE_DIR:?}"
staging="$(mktemp -d "$DERIVED_FILE_DIR/Licenses.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
Scripts/generate-licenses.sh "$source_packages" "$staging"
destination="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/Licenses"
mkdir -p "$destination"
# Remove notices for deleted dependencies as well as adding updated notices.
rsync -a --delete "$staging/" "$destination/"
echo "Synchronized OSS licenses into $destination"
