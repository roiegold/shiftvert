#!/bin/bash
# Builds dist/Shiftvert.app (Apple Silicon + Intel, ad-hoc signed), dist/Shiftvert.zip to share and its SHA-256.
# ./build.sh demo builds dist/demo/Shiftvert.app with the product-video recorder (Demo.swift), which releases leave out.
set -euo pipefail
cd "$(dirname "$0")"
export TZ=UTC  # zip timestamps
APP=Shiftvert

# Bundles a binary: debug symbols go (they hold this Mac's home-folder path), then it's ad-hoc signed.
bundle() {
  local bin=$1 out=$2
  rm -rf "$out"
  mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
  cp "$bin" "$out/Contents/MacOS/$APP"
  strip -S -x "$out/Contents/MacOS/$APP"
  cp Resources/Info.plist "$out/Contents/"
  cp Resources/AppIcon.icns "$out/Contents/Resources/"
  xattr -cr "$out"
  codesign --force --options runtime --sign - "$out"
  if LC_ALL=C grep -a -q -F "$HOME" "$out/Contents/MacOS/$APP"; then echo "error: $out contains this Mac's home-folder path" >&2; exit 1; fi
}

if [ "${1:-}" = demo ]; then
  swift build -c release -Xswiftc -DSHIFTVERT_DEMO --scratch-path .build/demo
  bundle ".build/demo/release/$APP" "dist/demo/$APP.app"
  echo "Built dist/demo/$APP.app"
  exit
fi

# Build each architecture separately (multi-arch builds need full Xcode) and merge them.
for arch in arm64 x86_64; do swift build -c release --triple $arch-apple-macosx14.0; done
mkdir -p dist
BIN="dist/$APP-universal"
lipo -create -output "$BIN" .build/arm64-apple-macosx/release/$APP .build/x86_64-apple-macosx/release/$APP

if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    [ $s = 512 ] || sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

OUT="dist/$APP.app"
rm -f "dist/$APP.zip" "dist/$APP.zip.sha256"
bundle "$BIN" "$OUT"
rm "$BIN"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$OUT" "dist/$APP.zip"
(cd dist && shasum -a 256 "$APP.zip" > "$APP.zip.sha256")
echo "Built $OUT and dist/$APP.zip ($(cut -d' ' -f1 "dist/$APP.zip.sha256"))"
