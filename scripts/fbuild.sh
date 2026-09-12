#!/bin/bash
# =============================================================================
# fbuild.sh — bump the build number, build release artifacts, collect them.
#
# Reads `version: x.y.z+n` from pubspec.yaml, increments n, builds, and moves
# the artifacts to $FBUILD_OUT_DIR (default: ~/Downloads).
#
# Usage:
#   ./fbuild.sh               # build Android appbundle + iOS ipa
#   ./fbuild.sh --android     # appbundle only
#   ./fbuild.sh --ios         # ipa only
#   FBUILD_OUT_DIR=dist ./fbuild.sh
# =============================================================================

set -e

# Portable in-place sed (BSD vs GNU flag difference). An array, not a
# wrapper function — nothing to be undefined at call time.
if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(-i)
else
    SED_INPLACE=(-i '')
fi

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# -- Flags --------------------------------------------------------------------
BUILD_ANDROID=true
BUILD_IOS=true
for arg in "$@"; do
    case $arg in
        --android) BUILD_ANDROID=true; BUILD_IOS=false ;;
        --ios)     BUILD_ANDROID=false; BUILD_IOS=true ;;
        *) error_exit "Unknown argument: $arg  (supported: --android, --ios)" ;;
    esac
done

DOWNLOADS_DIR="${FBUILD_OUT_DIR:-$HOME/Downloads}"
mkdir -p "$DOWNLOADS_DIR"

# -- 1. Read and bump version -------------------------------------------------
PUBSPEC_FILE="pubspec.yaml"
[ -f "$PUBSPEC_FILE" ] || error_exit "$PUBSPEC_FILE not found. Run from a Flutter project root."

VERSION_LINE=$(grep -E "^version:" "$PUBSPEC_FILE" | head -1)
[ -z "$VERSION_LINE" ] && error_exit "No top-level 'version:' line found in $PUBSPEC_FILE."

VERSION=$(echo "$VERSION_LINE" | sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)/\1/p')
BUILD_NUMBER=$(echo "$VERSION_LINE" | sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)/\2/p')

[ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] && \
    error_exit "Could not parse version from '$VERSION_LINE'. Expected format: version: x.y.z+n"

NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION_LINE="version: $VERSION+$NEW_BUILD_NUMBER"

echo "Bumping version: $VERSION+$BUILD_NUMBER -> $VERSION+$NEW_BUILD_NUMBER"
sed "${SED_INPLACE[@]}" "s|^version: $VERSION+$BUILD_NUMBER\$|$NEW_VERSION_LINE|" "$PUBSPEC_FILE" \
    || error_exit "Failed to update $PUBSPEC_FILE."

grep -q "^$NEW_VERSION_LINE\$" "$PUBSPEC_FILE" || \
    error_exit "Version line did not update as expected — check pubspec.yaml manually."

# -- 2. Build and collect artifacts --------------------------------------------
collect_artifact() {
    local dir="$1" pattern="$2" label="$3"
    local file
    file=$(find "$dir" -name "$pattern" -print -quit 2>/dev/null || true)
    if [ -f "$file" ]; then
        echo "Moving $label to $DOWNLOADS_DIR/"
        mv "$file" "$DOWNLOADS_DIR/" || error_exit "Failed to move $label."
    else
        echo "Warning: $label not found under $dir"
    fi
}

if [ "$BUILD_ANDROID" = true ]; then
    echo "Building App Bundle..."
    flutter build appbundle || error_exit "flutter build appbundle failed."
    collect_artifact "build/app/outputs/bundle/release/" "*.aab" "App Bundle"
fi

if [ "$BUILD_IOS" = true ]; then
    echo "Building IPA..."
    flutter build ipa || error_exit "flutter build ipa failed."
    collect_artifact "build/ios/ipa/" "*.ipa" "IPA"
fi

echo "Build script finished successfully."
