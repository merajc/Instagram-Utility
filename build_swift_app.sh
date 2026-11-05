#!/bin/bash
# build_app.sh — Build a proper macOS .app bundle from the Swift package.
# Run this once; then double-click ImageProcessor.app to launch.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/ImageProcessorSwift"

echo "🔨 Building release binary…"
swift build -c release

BINARY=".build/release/ImageProcessorSwift"
APP="$DIR/ImageProcessor.app"

echo "📦 Creating app bundle at $APP …"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/ImageProcessorSwift"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>Image Processor</string>
    <key>CFBundleDisplayName</key>      <string>Image Processor</string>
    <key>CFBundleExecutable</key>       <string>ImageProcessorSwift</string>
    <key>CFBundleIdentifier</key>       <string>io.github.merajc.ImageProcessor</string>
    <key>CFBundleVersion</key>          <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>NSPrincipalClass</key>         <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>  <true/>
    <key>LSMinimumSystemVersion</key>   <string>14.0</string>
    <key>NSHumanReadableCopyright</key> <string>MIT licensed — github.com/merajc/Instagram-Utility</string>
</dict>
</plist>
PLIST

chmod +x "$APP/Contents/MacOS/ImageProcessorSwift"
echo "✅ Done — opening ImageProcessor.app"
open "$APP"
