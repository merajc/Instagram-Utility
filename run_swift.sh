#!/bin/bash
# run.sh — Build and launch the Swift image processor (dev mode, no app bundle)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/ImageProcessorSwift"
echo "🔨 Building…"
swift run ImageProcessorSwift
