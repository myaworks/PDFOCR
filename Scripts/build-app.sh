#!/bin/sh
# Assemble a double-clickable PDFOCR.app out of the SwiftPM build.
#
# SwiftPM only produces a bare executable; a SwiftUI app needs the bundle around
# it before Finder, LaunchServices or `open` will treat it as an app. This is the
# same thing the release workflow runs, so there is one definition of the bundle.
#
#   Scripts/build-app.sh                 universal app in dist/
#   Scripts/build-app.sh --arch arm64    one architecture only, faster locally
#   Scripts/build-app.sh --version 1.2.3 stamp a specific version

set -eu

cd "$(dirname "$0")/.."

ARCHES="arm64 x86_64"
VERSION="1.0.0"

while [ $# -gt 0 ]; do
    case "$1" in
        --arch)
            ARCHES="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
done

if [ -z "$(git describe --tags --abbrev=0 2>/dev/null)" ]; then
    :
elif [ "$VERSION" = "1.0.0" ]; then
    VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')"
fi

ARCH_FLAGS=""
for arch in $ARCHES; do
    ARCH_FLAGS="$ARCH_FLAGS --arch $arch"
done

echo "==> building ($ARCHES)"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS

BIN="$(swift build -c release --show-bin-path)"
APP="dist/PDFOCR.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/PDFOCR" "$APP/Contents/MacOS/PDFOCR"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> stamping version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# Ad-hoc is enough for something built and run on the same machine. Handing the
# app to someone else needs a Developer ID and notarisation, which needs a paid
# Apple account; see the README.
echo "==> signing"
codesign --force --deep --sign - "$APP"

echo "==> verifying"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
plutil -lint "$APP/Contents/Info.plist" | sed 's/^/    /'
lipo -archs "$APP/Contents/MacOS/PDFOCR" | sed 's/^/    arches: /'

echo
echo "built $APP"
echo "run it with:  open $APP"