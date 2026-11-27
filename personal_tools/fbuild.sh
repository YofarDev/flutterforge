#!/bin/bash
# =============================================================================
# fbuild.sh — bump the build number, build release artifacts, collect them.
#
# Reads `version: x.y.z+n` from pubspec.yaml, increments n, builds, and moves
# the artifacts to $FBUILD_OUT_DIR (default: ~/Downloads).
#
# Usage:
#   ./fbuild.sh                            # build Android appbundle + iOS ipa
#   ./fbuild.sh --android                  # appbundle only
#   ./fbuild.sh --ios                      # ipa only
#   ./fbuild.sh --flavor prod              # build the 'prod' flavor on both platforms
#   ./fbuild.sh --android --flavor dev     # dev-flavored appbundle only
#   FBUILD_OUT_DIR=dist ./fbuild.sh
#
# With a flavor, the flavor is passed to `flutter build`, the Android bundle is
# collected from the flavored output dir, and the flavor is included in
# artifact names: <project>-<flavor>-<version>+<build>-<platform>.<ext>.
# =============================================================================

set -e

# Portable in-place sed (BSD vs GNU flag difference). An array, not a
# wrapper function — nothing to be undefined at call time.
if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(-i)
else
    SED_INPLACE=(-i '')
fi

# Set once the version is bumped: a failed build restores the original
# pubspec.yaml so the build number is not consumed by a build that produced
# nothing.
PUBSPEC_BACKUP=""

error_exit() {
    echo "Error: $1" >&2
    if [ -n "$PUBSPEC_BACKUP" ] && [ -f "$PUBSPEC_BACKUP" ]; then
        cp "$PUBSPEC_BACKUP" "$PUBSPEC_FILE" && echo "Restored $PUBSPEC_FILE (version bump undone)." >&2
        rm -f "$PUBSPEC_BACKUP"
    fi
    exit 1
}

# -- Flags --------------------------------------------------------------------
# No flag: both platforms. --android / --ios select platforms (both flags:
# both platforms). --flavor <name> (or --flavor=<name>) builds that product
# flavor on the selected platforms.
WANT_ANDROID=false
WANT_IOS=false
FLAVOR=""
while [ $# -gt 0 ]; do
    case $1 in
        --android)  WANT_ANDROID=true; shift ;;
        --ios)      WANT_IOS=true; shift ;;
        --flavor)   [ $# -ge 2 ] || error_exit "--flavor requires a value (e.g. --flavor prod)."
                    FLAVOR="$2"; shift 2 ;;
        --flavor=*) FLAVOR="${1#--flavor=}"
                    [ -n "$FLAVOR" ] || error_exit "--flavor requires a value (e.g. --flavor prod)."
                    shift ;;
        *) error_exit "Unknown argument: $1  (supported: --android, --ios, --flavor <name>)" ;;
    esac
done
if [ "$WANT_ANDROID" = false ] && [ "$WANT_IOS" = false ]; then
    WANT_ANDROID=true
    WANT_IOS=true
fi
BUILD_ANDROID=$WANT_ANDROID
BUILD_IOS=$WANT_IOS

if [ -n "$FLAVOR" ] && ! echo "$FLAVOR" | grep -qE '^[A-Za-z0-9_]+$'; then
    error_exit "Invalid flavor name: '$FLAVOR' (allowed: letters, digits, underscores)."
fi

# Passed to `flutter build` (empty when no flavor), and the suffix added to
# artifact names / the Android output dir the bundle is collected from.
FLAVOR_ARGS=()
FLAVOR_TAG=""
ANDROID_BUNDLE_DIR="build/app/outputs/bundle/release/"
if [ -n "$FLAVOR" ]; then
    FLAVOR_ARGS=(--flavor "$FLAVOR")
    FLAVOR_TAG="-$FLAVOR"
    ANDROID_BUNDLE_DIR="build/app/outputs/bundle/$FLAVOR/release/"
fi

DOWNLOADS_DIR="${FBUILD_OUT_DIR:-$HOME/Downloads}"
mkdir -p "$DOWNLOADS_DIR"

# -- 1. Read and bump version -------------------------------------------------
PUBSPEC_FILE="pubspec.yaml"
[ -f "$PUBSPEC_FILE" ] || error_exit "$PUBSPEC_FILE not found. Run from a Flutter project root."

PROJECT_NAME=$(grep -E "^name:" "$PUBSPEC_FILE" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '[:space:]')
[ -z "$PROJECT_NAME" ] && error_exit "Could not read 'name:' from $PUBSPEC_FILE."

VERSION_LINE=$(grep -E "^version:" "$PUBSPEC_FILE" | head -1)
[ -z "$VERSION_LINE" ] && error_exit "No top-level 'version:' line found in $PUBSPEC_FILE."

VERSION=$(echo "$VERSION_LINE" | sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)/\1/p')
BUILD_NUMBER=$(echo "$VERSION_LINE" | sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)/\2/p')

[ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] && \
    error_exit "Could not parse version from '$VERSION_LINE'. Expected format: version: x.y.z+n"

NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION_LINE="version: $VERSION+$NEW_BUILD_NUMBER"

echo "Bumping version: $VERSION+$BUILD_NUMBER -> $VERSION+$NEW_BUILD_NUMBER"
PUBSPEC_BACKUP="$(mktemp)"
cp "$PUBSPEC_FILE" "$PUBSPEC_BACKUP"
sed "${SED_INPLACE[@]}" "s|^version: $VERSION+$BUILD_NUMBER\$|$NEW_VERSION_LINE|" "$PUBSPEC_FILE" \
    || error_exit "Failed to update $PUBSPEC_FILE."

grep -q "^$NEW_VERSION_LINE\$" "$PUBSPEC_FILE" || \
    error_exit "Version line did not update as expected — check pubspec.yaml manually."

# -- 2. Build and collect artifacts --------------------------------------------
# Artifacts are named <project>[-<flavor>]-<version>+<build>-<platform>.<ext>.
# Existing destination files are NEVER silently overwritten — the build is
# refused.
collect_artifact() {
    local dir="$1" pattern="$2" platform="$3" ext="$4"
    local file target
    file=$(find "$dir" -name "$pattern" -print -quit 2>/dev/null || true)
    if [ -f "$file" ]; then
        target="$DOWNLOADS_DIR/${PROJECT_NAME}${FLAVOR_TAG}-${VERSION}+${NEW_BUILD_NUMBER}-${platform}.${ext}"
        if [ -e "$target" ]; then
            error_exit "Refusing to overwrite existing artifact: $target — remove or rename it first."
        fi
        echo "Moving $platform artifact to $target"
        mv "$file" "$target" || error_exit "Failed to move $platform artifact."
    else
        echo "Warning: $platform artifact not found under $dir"
    fi
}

if [ "$BUILD_ANDROID" = true ]; then
    echo "Building App Bundle${FLAVOR:+ (flavor: $FLAVOR)}..."
    flutter build appbundle "${FLAVOR_ARGS[@]}" || error_exit "flutter build appbundle failed."
    collect_artifact "$ANDROID_BUNDLE_DIR" "*.aab" android aab
fi

if [ "$BUILD_IOS" = true ]; then
    echo "Building IPA${FLAVOR:+ (flavor: $FLAVOR)}..."
    flutter build ipa "${FLAVOR_ARGS[@]}" || error_exit "flutter build ipa failed."
    collect_artifact "build/ios/ipa/" "*.ipa" ios ipa
fi

rm -f "$PUBSPEC_BACKUP"
echo "Build script finished successfully."
