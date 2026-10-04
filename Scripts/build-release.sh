#!/bin/sh
# Build the release artefacts into dist/.
#
# SwiftPM only produces bare executables: a SwiftUI app needs the bundle
# around it before Finder, LaunchServices or `open` will treat it as an app.
# That is what this script assembles.
#
#   Scripts/build-release.sh                     universal, dist/ staged
#   Scripts/build-release.sh --arch arm64       one architecture, faster
#   Scripts/build-release.sh --version 1.2.3     stamp a version
#   Scripts/build-release.sh --zip              also write dist/*.zip

set -eu

cd "$(dirname "$0")/.."

ARCHES="arm64 x86_64"
VERSION=""
MAKE_ZIP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCHES="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --zip) MAKE_ZIP=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    VERSION="${VERSION#v}"
    VERSION="${VERSION:-0.0.0}"
fi

ARCH_FLAGS=""
for arch in $ARCHES; do
    ARCH_FLAGS="$ARCH_FLAGS --arch $arch"
done

echo "==> building ($ARCHES)"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS

# Where SwiftPM put the products moves between versions and between the
# open-source and Xcode toolchains, and with several --arch flags the path it
# reports can be an architecture-specific directory that does not hold the
# combined binary. Ask it, then look for the binary that is actually universal.
echo "==> locating products"
BIN=""
for dir in \
    "$(swift build -c release $ARCH_FLAGS --show-bin-path 2>/dev/null || true)" \
    .build/apple/Products/Release \
    .build/release
do
    [ -n "$dir" ] && [ -x "$dir/pdf-ocr" ] && [ -x "$dir/PDFOCR" ] && { BIN="$dir"; break; }
done
if [ -z "$BIN" ]; then
    echo "could not find the built products under .build" >&2
    exit 1
fi
echo "    $BIN"
echo "    pdf-ocr: $(lipo -archs "$BIN/pdf-ocr")"
echo "    PDFOCR:  $(lipo -archs "$BIN/PDFOCR")"

rm -rf dist
mkdir -p dist/PDFOCR.app/Contents/MacOS

cp "$BIN/pdf-ocr" dist/pdf-ocr
cp "$BIN/PDFOCR" dist/PDFOCR.app/Contents/MacOS/PDFOCR
cp Resources/Info.plist dist/PDFOCR.app/Contents/Info.plist

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" dist/PDFOCR.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" dist/PDFOCR.app/Contents/Info.plist

# Ad-hoc is enough for something built and run on the same machine. Handing the
# app to another machine needs a Developer ID and notarisation, which needs a
# paid Apple account; see the README.
echo "==> signing"
codesign --force --deep --sign - dist/PDFOCR.app

if [ "$MAKE_ZIP" = "1" ]; then
    echo "==> packaging"
    tar -czf dist/pdf-ocr-macos-universal.tar.gz -C dist pdf-ocr
    tar -czf dist/PDFOCR-macos.zip -C dist PDFOCR.app
fi

echo
echo "built, version $VERSION"
echo "    dist/pdf-ocr            $(lipo -archs dist/pdf-ocr)"
echo "    dist/PDFOCR.app         open dist/PDFOCR.app"
[ "$MAKE_ZIP" = "1" ] && ls -1 dist/*.zip dist/*.tar.gz 2>/dev/null | sed 's/^/    /'
exit 0