#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
derived_data_path="${repository_root}/.derivedData/search-benchmark"
benchmark_temporary_directory=$(mktemp -d)
benchmark_result_bundle="${benchmark_temporary_directory}/SearchBenchmark.xcresult"

trap 'rm -rf -- "${benchmark_temporary_directory}"' EXIT

cd "${repository_root}"

/usr/bin/time -l xcodebuild test \
    -quiet \
    -project Buffer.xcodeproj \
    -scheme Buffer \
    -configuration Release \
    -enableCodeCoverage NO \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "${derived_data_path}" \
    -resultBundlePath "${benchmark_result_bundle}" \
    -test-timeouts-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_TESTABILITY=YES \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) BUFFER_SEARCH_BENCHMARK' \
    -only-testing:BufferTests/ClipboardSearchTests/testOptInPersistentSearchBenchmark

xcrun xcresulttool get test-results activities \
    --path "${benchmark_result_bundle}" \
    --test-id 'ClipboardSearchTests/testOptInPersistentSearchBenchmark()' \
    --compact \
    | rg -o 'BUFFER_SEARCH_BENCHMARK[^"\\]*'
