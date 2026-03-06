#!/bin/bash

# Function to show error message and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# 1. Read pubspec.yaml and extract version
PUBSPEC_FILE="pubspec.yaml"
if [ ! -f "$PUBSPEC_FILE" ]; then
    error_exit "$PUBSPEC_FILE not found. Make sure you are in the root of a Flutter project."
fi

VERSION_LINE=$(grep "version:" "$PUBSPEC_FILE")
if [ -z "$VERSION_LINE" ]; then
    error_exit "Version line not found in $PUBSPEC_FILE."
fi

# Extract version and build number
VERSION=$(echo "$VERSION_LINE" | sed -n 's/version: \(.*\)+\(.*\)/\1/p')
BUILD_NUMBER=$(echo "$VERSION_LINE" | sed -n 's/version: \(.*\)+\(.*\)/\2/p')

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    error_exit "Could not parse version and build number from $PUBSPEC_FILE. Expected format: version: x.y.z+n"
fi

# 2. Increment build number
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION_STRING="version: $VERSION+$NEW_BUILD_NUMBER"

echo "Updating version from '$VERSION_LINE' to '$NEW_VERSION_STRING'"

# 3. Update pubspec.yaml
# Using sed for in-place replacement. The '' after -i is for macOS compatibility.
sed -i '' "s/$VERSION_LINE/$NEW_VERSION_STRING/" "$PUBSPEC_FILE" || error_exit "Failed to update $PUBSPEC_FILE."

# 4. Run flutter build appbundle
echo "Building App Bundle..."
flutter build appbundle || error_exit "flutter build appbundle failed."

DOWNLOADS_DIR="$HOME/Downloads"

# Move AppBundle
APPBUNDLE_DIR="build/app/outputs/bundle/release/"
APPBUNDLE_FILE=$(find "$APPBUNDLE_DIR" -name "*.aab" -print -quit)
if [ -f "$APPBUNDLE_FILE" ]; then
    echo "Moving App Bundle to $DOWNLOADS_DIR"
    mv "$APPBUNDLE_FILE" "$DOWNLOADS_DIR/" || error_exit "Failed to move App Bundle."
else
    echo "Warning: App Bundle file not found."
fi

# 5. Run flutter build ipa
echo "Building IPA..."
flutter build ipa || error_exit "flutter build ipa failed."


# Move IPA
IPA_DIR="build/ios/ipa/"
IPA_FILE=$(find "$IPA_DIR" -name "*.ipa" -print -quit)
if [ -f "$IPA_FILE" ]; then
    echo "Moving IPA to $DOWNLOADS_DIR"
    mv "$IPA_FILE" "$DOWNLOADS_DIR/" || error_exit "Failed to move IPA."
else
    echo "Warning: IPA file not found."
fi

echo "Build script finished successfully."