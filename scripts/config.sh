#!/usr/bin/env bash

# Application Configuration
# These variables configure your application name, bundle ID, and build options.
# You can override them via environment variables or modify this file directly.

export APP_NAME="${APP_NAME:-Recall}"
export BUNDLE_ID="${BUNDLE_ID:-com.recall.app}"
export MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-12.3}"
export COPYRIGHT="${COPYRIGHT:-Copyright © $(date +%Y). All rights reserved.}"
export LS_UI_ELEMENT="${LS_UI_ELEMENT:-true}" # Set to "true" for menu-bar-only / agent apps

# Resolve Version from VERSION file if present
version_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION"
if [[ -f "$version_file" ]]; then
    IFS= read -r file_version <"$version_file"
    file_version="${file_version//[[:space:]]/}"
    if [[ -n "$file_version" ]]; then
        export VERSION="${VERSION:-$file_version}"
    fi
fi
export VERSION="${VERSION:-1.0.2}"
