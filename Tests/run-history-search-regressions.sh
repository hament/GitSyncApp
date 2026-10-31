#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitsync-history-search.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  GitSync/GitSync/AppModel.swift \
  GitSync/GitSync/Localization.swift \
  GitSync/GitSync/Models.swift \
  GitSync/GitSync/Git/*.swift \
  GitSync/GitSync/Store/*.swift \
  Tests/HistorySearchTests.swift \
  -o "$build_dir/history-search-tests"
"$build_dir/history-search-tests"