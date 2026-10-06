#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM compiles a universal executable using the installed Xcode SDK.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
BUILD_FLAGS=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
if /usr/bin/xcodebuild -license check >/dev/null 2>&1; then
    swift build "${BUILD_FLAGS[@]}" -c release --arch arm64 --arch x86_64
    BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    # Use the separately installed command-line toolchain when Xcode is unavailable.
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    CLT_SWIFT="$DEVELOPER_DIR/usr/bin/swiftc"
    CLT_SDK="$DEVELOPER_DIR/SDKs/MacOSX.sdk"
    BIN_DIR="$PWD/.build/CLTRelease"
    mkdir -p "$BIN_DIR"
    for ARCH in arm64 x86_64; do
        "$CLT_SWIFT" -swift-version 5 -O -module-name Minutes2 -target "$ARCH-apple-macosx13.0" \
            -sdk "$CLT_SDK" -module-cache-path "$PWD/.build/CLTModuleCache" \
            Sources/MinutesCore/*.swift Sources/Minutes2/*.swift -o "$BIN_DIR/Minutes2-$ARCH"
    done
    /usr/bin/lipo -create "$BIN_DIR/Minutes2-arm64" "$BIN_DIR/Minutes2-x86_64" -output "$BIN_DIR/Minutes2"
fi
APP_PATH="$PWD/build/Minutes2.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/Minutes2" "$APP_PATH/Contents/MacOS/Minutes2"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/BubblePop.wav "$APP_PATH/Contents/Resources/"
mkdir -p "$APP_PATH/Contents/Resources/music"
cp music/*.mp3 "$APP_PATH/Contents/Resources/music/"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"
fi
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
/usr/bin/codesign --force --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
/usr/bin/lipo -info "$APP_PATH/Contents/MacOS/Minutes2"
printf '\n构建完成：%s\n' "$APP_PATH"
