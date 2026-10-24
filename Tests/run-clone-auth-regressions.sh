#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitsync-clone-auth.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -swift-version 6 \
  GitSync/GitSync/Git/CloneAuthenticationGuide.swift \
  Tests/CloneAuthenticationGuideTests.swift \
  -o "$build_dir/guide-tests"
"$build_dir/guide-tests"

xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  GitSync/GitSync/AppModel.swift \
  GitSync/GitSync/Localization.swift \
  GitSync/GitSync/Models.swift \
  GitSync/GitSync/Git/*.swift \
  GitSync/GitSync/Store/*.swift \
  Tests/CloneAuthenticationFlowTests.swift \
  -o "$build_dir/flow-tests"
"$build_dir/flow-tests"
