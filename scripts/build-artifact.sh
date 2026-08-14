#!/bin/bash

set -euo pipefail

buffer_script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
buffer_repository_root="$(cd "${buffer_script_directory}/.." && pwd)"
buffer_dist_directory="${buffer_repository_root}/dist"
buffer_dist_app="${buffer_dist_directory}/Buffer.app"
buffer_new_app="${buffer_dist_directory}/.Buffer.app.new"
buffer_temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/buffer-build.XXXXXX")"

cleanup_buffer_build() {
    rm -rf "${buffer_temporary_directory}" "${buffer_new_app}"
}
trap cleanup_buffer_build EXIT

mkdir -p "${buffer_dist_directory}"
cd "${buffer_repository_root}"

echo "Building Buffer.app..."
xcodebuild build \
    -quiet \
    -scheme Buffer \
    -project Buffer.xcodeproj \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${buffer_temporary_directory}/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO

buffer_built_app="${buffer_temporary_directory}/DerivedData/Build/Products/Release/Buffer.app"
/usr/bin/ditto "${buffer_built_app}" "${buffer_new_app}"

echo "Signing Buffer.app..."
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --entitlements Buffer.entitlements \
    --options runtime \
    "${buffer_new_app}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${buffer_new_app}"

rm -rf "${buffer_dist_app}"
mv "${buffer_new_app}" "${buffer_dist_app}"

echo
echo "Created ${buffer_dist_app}"
echo "Architectures: $(/usr/bin/lipo -archs "${buffer_dist_app}/Contents/MacOS/Buffer")"
