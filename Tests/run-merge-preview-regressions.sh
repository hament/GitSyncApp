#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitsync-merge-preview.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  GitSync/GitSync/Localization.swift \
  GitSync/GitSync/Models.swift \
  GitSync/GitSync/Git/GitClient.swift \
  GitSync/GitSync/Git/GitComparison.swift \
  GitSync/GitSync/Git/GitMergePreview.swift \
  GitSync/GitSync/Git/DiffParser.swift \
  GitSync/GitSync/Git/LogParser.swift \
  Tests/MergePreviewTests.swift \
  -o "$build_dir/merge-preview-tests"
"$build_dir/merge-preview-tests"