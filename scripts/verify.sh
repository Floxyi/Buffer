#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
derived_data_path="${repository_root}/.derivedData/verify"

cd "${repository_root}"

xcrun swift-format lint --strict -r \
    AppDelegate.swift \
    BufferApp.swift \
    Models \
    Services \
    Support \
    Views \
    BufferTests

xcodebuild test \
    -quiet \
    -project Buffer.xcodeproj \
    -scheme Buffer \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "${derived_data_path}" \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

xcodebuild analyze \
    -quiet \
    -project Buffer.xcodeproj \
    -scheme Buffer \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "${derived_data_path}" \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
