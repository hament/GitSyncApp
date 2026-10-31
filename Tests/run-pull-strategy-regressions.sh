#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitsync-pull-strategy.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  GitSync/GitSync/AppModel.swift \
  GitSync/GitSync/Localization.swift \
  GitSync/GitSync/Models.swift \
  GitSync/GitSync/Git/*.swift \
  GitSync/GitSync/Store/*.swift \
  Tests/PullStrategyTests.swift \
  -o "$build_dir/pull-strategy-tests"
"$build_dir/pull-strategy-tests"