#!/bin/zsh
# Houra.app'i derler (Apple Silicon + Intel) ve simgesini üretir.
#   ./build.sh            → build/Houra.app
#   ./build.sh --install  → ayrıca ~/Applications altına kurar
#   ./build.sh --dmg      → ayrıca build/Houra-<sürüm>.dmg üretir (uv gerekir)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0"
BUILD_NUMBER="1"
MIN_MACOS="13.0"
APP="build/Houra.app"
ICONSET="build/AppIcon.iconset"
ICON_PNG="build/AppIcon-1024.png"
DMG="build/Houra-$VERSION.dmg"

should_install=false
should_make_dmg=false
for arg in "$@"; do
    case "$arg" in
        --install) should_install=true ;;
        --dmg) should_make_dmg=true ;;
        *) echo "Bilinmeyen seçenek: $arg (kullanılabilir: --install, --dmg)" >&2; exit 1 ;;
    esac
done

build_binary() {
    local slices=()
    for arch in arm64 x86_64; do
        swiftc -O -target "$arch-apple-macos$MIN_MACOS" Sources/*.swift -o "build/Houra-$arch"
        slices+=("build/Houra-$arch")
    done
    lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/Houra"
    rm -f "${slices[@]}"
}

build_icon() {
    swift scripts/make_icon.swift "$ICON_PNG"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
}

write_info_plist() {
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Houra</string>
    <key>CFBundleDisplayName</key><string>Houra</string>
    <key>CFBundleIdentifier</key><string>com.serbest.houra</string>
    <key>CFBundleExecutable</key><string>Houra</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
}

make_dmg() {
    swift scripts/make_dmg_background.swift build/dmg-background
    tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png \
        -out build/dmg-background.tiff >/dev/null
    rm -f "$DMG"
    uvx dmgbuild -s scripts/dmg_settings.py \
        -D app="$APP" \
        -D background=build/dmg-background.tiff \
        -D volume_icon="$APP/Contents/Resources/AppIcon.icns" \
        "Houra" "$DMG"
    echo "DMG: $DMG"
}

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
build_binary
build_icon
write_info_plist
codesign --force --sign - "$APP"
echo "Derlendi: $APP ($VERSION)"

if $should_install; then
    rm -rf ~/Applications/Houra.app
    cp -R "$APP" ~/Applications/
    touch ~/Applications/Houra.app   # Finder simgeyi yenilesin
    echo "Kuruldu: ~/Applications/Houra.app"
fi

if $should_make_dmg; then
    make_dmg
fi
