#!/usr/bin/env bash
# Apply the HStream overlay onto a Fred TV checkout, then build a release APK.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="${HSTREAM_APP:-$ROOT/app}"
TOOLS="$ROOT/tools"
NDK_VERSION="29.0.14206865"

if [[ -x "$TOOLS/flutter/bin/flutter" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$TOOLS/jdk}"
  export ANDROID_HOME="${ANDROID_HOME:-$TOOLS/android-sdk}"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  if [[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ]]; then
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/$NDK_VERSION}"
  fi
  export RUSTUP_HOME="${RUSTUP_HOME:-$TOOLS/rust/rustup}"
  export CARGO_HOME="${CARGO_HOME:-$TOOLS/rust/cargo}"
  export PATH="$TOOLS/flutter/bin:$JAVA_HOME/bin:$CARGO_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmake/3.22.1/bin:$PATH"
fi

if [[ ! -f "$HERE/files/flutter/lib/main.dart" ]]; then
  echo "[error] hstream/files missing." >&2
  exit 1
fi
if [[ ! -f "$APP/flutter/pubspec.yaml" ]]; then
  echo "[error] Fred TV source not found at $APP"
  echo "Clone it first:"
  echo "  git clone --depth 1 https://github.com/Fredolx/fred-tv-mobile.git \"$APP\""
  echo "Or run ./setup.sh"
  exit 1
fi

if [[ -f "$APP/Cargo.toml" ]] && grep -q 'native-tls-vendored' "$APP/Cargo.toml"; then
  echo "[patch] Switching Cargo TLS backend to rustls"
  tmp="$(mktemp)"
  sed 's/native-tls-vendored/rustls/g' "$APP/Cargo.toml" > "$tmp"
  mv "$tmp" "$APP/Cargo.toml"
fi

echo "Applying overlay..."
cp -R "$HERE/files/flutter/." "$APP/flutter/"
if [[ -f "$HERE/files/rust/src/sql.rs" ]]; then
  cp "$HERE/files/rust/src/sql.rs" "$APP/src/sql.rs"
  cp "$HERE/files/rust/src/lib.rs" "$APP/src/lib.rs"
  cp "$HERE/files/rust/Cargo.toml" "$APP/Cargo.toml"
fi
rm -f "$APP/flutter/lib/whats_new_modal.dart" \
      "$APP/flutter/lib/tema.dart" \
      "$APP/flutter/lib/bottom_nav.dart" \
      "$APP/flutter/lib/hstream_rail.dart" \
      "$APP/flutter/lib/tv_home.dart"

echo "[1/2] cargo ndk"
cd "$APP"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 --platform 24 \
  -o flutter/android/app/src/main/jniLibs build --release

echo "[2/2] flutter build apk"
cd "$APP/flutter"
flutter pub get
flutter build apk --release

OUT="$ROOT/output"
mkdir -p "$OUT"
cp -f "$APP/flutter/build/app/outputs/flutter-apk/app-release.apk" "$OUT/HStream.apk"
echo "APK: $OUT/HStream.apk"
