#!/usr/bin/env bash
# Exit immediately on error
set -e

echo "==> Checking for Flutter SDK on Render..."
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "==> Installing Flutter SDK (stable branch)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi

export PATH="$PATH:$FLUTTER_DIR/bin"

echo "==> Verifying Flutter version..."
flutter --version

echo "==> Building Flutter Web Release..."
cd frontend
flutter config --enable-web
flutter build web --release

echo "==> Web Build complete! Artifacts are in frontend/build/web"
