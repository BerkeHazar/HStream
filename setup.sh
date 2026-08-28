#!/usr/bin/env bash
# Portable toolchain (JDK 17, Flutter, Android SDK/NDK, Rust) under tools/.
# Nothing is installed system-wide. Output: output/HStream.apk
set -euo pipefail

FLUTTER_VERSION="3.47.0"
NDK_VERSION="29.0.14206865"
CMDTOOLS_BUILD="14742923"
KAYNAK_ZIP="https://github.com/Fredolx/fred-tv-mobile/archive/refs/heads/main.zip"
KAYNAK_GIT="https://github.com/Fredolx/fred-tv-mobile.git"

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$ROOT/tools"
DL="$ROOT/downloads"
APP="$ROOT/app"
OUT="$ROOT/output"
JAVA_DIR="$TOOLS/jdk"
FLUTTER_DIR="$TOOLS/flutter"
ANDROID_DIR="$TOOLS/android-sdk"
export RUSTUP_HOME="$TOOLS/rust/rustup"
export CARGO_HOME="$TOOLS/rust/cargo"

OS_RAW="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_RAW="$(uname -m)"
case "$OS_RAW" in
  linux)  OS_KEY=linux ;;
  darwin) OS_KEY=mac ;;
  *) echo "[error] Unsupported OS: $OS_RAW" >&2; exit 1 ;;
esac
case "$ARCH_RAW" in
  x86_64|amd64) ARCH_KEY=x64 ;;
  aarch64|arm64) ARCH_KEY=aarch64 ;;
  *) echo "[error] Unsupported arch: $ARCH_RAW" >&2; exit 1 ;;
esac

if [[ "$OS_KEY" == linux ]]; then
  PT_OS=linux
  CT_OS=linux
  if [[ "$ARCH_KEY" == x64 ]]; then
    RUST_HOST=x86_64-unknown-linux-gnu
    FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    FLUTTER_ARCHIVE="flutter.tar.xz"
  else
    echo "[error] Linux builds need x86_64. This machine is $ARCH_RAW." >&2
    exit 1
  fi
else
  PT_OS=darwin
  CT_OS=mac
  if [[ "$ARCH_KEY" == x64 ]]; then
    RUST_HOST=x86_64-apple-darwin
    FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_${FLUTTER_VERSION}-stable.zip"
  else
    RUST_HOST=aarch64-apple-darwin
    FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${FLUTTER_VERSION}-stable.zip"
  fi
  FLUTTER_ARCHIVE="flutter.zip"
fi

JDK_URL="https://api.adoptium.net/v3/binary/latest/17/ga/${OS_KEY}/${ARCH_KEY}/jdk/hotspot/normal/eclipse"
CT_URL="https://dl.google.com/android/repository/commandlinetools-${CT_OS}-${CMDTOOLS_BUILD}_latest.zip"
PT_URL="https://dl.google.com/android/repository/platform-tools-latest-${PT_OS}.zip"
RUSTUP_URL="https://static.rust-lang.org/rustup/dist/${RUST_HOST}/rustup-init"

download() {
  echo "[download] $(basename "$2")"
  curl -L --progress-bar --retry 3 --retry-delay 2 -o "$2" "$1"
}

extract_zip() {
  mkdir -p "$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$1" -d "$2"
  else
    python3 -m zipfile -e "$1" "$2"
  fi
}

need_curl() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "[error] curl not found." >&2
    return 1
  fi
}

hazirlik() {
  echo "[setup] Folders"
  mkdir -p "$TOOLS" "$DL" "$OUT"
  need_curl
}

jdk_kur() {
  if [[ -x "$JAVA_DIR/bin/java" ]]; then
    echo "[ok] JDK"
    return 0
  fi
  echo "[setup] JDK 17"
  download "$JDK_URL" "$DL/jdk17.tgz"
  mkdir -p "$TOOLS/_jdk_tmp"
  tar -xf "$DL/jdk17.tgz" -C "$TOOLS/_jdk_tmp"
  local found
  found="$(find "$TOOLS/_jdk_tmp" -maxdepth 2 -type d -name 'jdk-*' | head -n 1)"
  if [[ -z "$found" ]]; then
    echo "[error] JDK extract failed." >&2
    return 1
  fi
  rm -rf "$JAVA_DIR"
  mv "$found" "$JAVA_DIR"
  rm -rf "$TOOLS/_jdk_tmp"
  echo "[ok] JDK"
}

flutter_kur() {
  if [[ -x "$FLUTTER_DIR/bin/flutter" ]]; then
    echo "[ok] Flutter"
    return 0
  fi
  echo "[setup] Flutter $FLUTTER_VERSION"
  download "$FLUTTER_URL" "$DL/$FLUTTER_ARCHIVE"
  if [[ "$FLUTTER_ARCHIVE" == *.tar.xz ]]; then
    tar -xf "$DL/$FLUTTER_ARCHIVE" -C "$TOOLS"
  else
    extract_zip "$DL/$FLUTTER_ARCHIVE" "$TOOLS"
  fi
  if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
    echo "[error] Flutter extract failed." >&2
    return 1
  fi
  echo "[ok] Flutter"
}

android_kur() {
  if [[ -x "$ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then
    echo "[ok] Android cmdline-tools"
    return 0
  fi
  echo "[setup] Android cmdline-tools"
  download "$CT_URL" "$DL/cmdline-tools.zip"
  mkdir -p "$ANDROID_DIR"
  extract_zip "$DL/cmdline-tools.zip" "$ANDROID_DIR"
  if [[ -d "$ANDROID_DIR/cmdline-tools" && ! -d "$ANDROID_DIR/cmdline-tools/latest" ]]; then
    mv "$ANDROID_DIR/cmdline-tools" "$ANDROID_DIR/ct-tmp"
    mkdir -p "$ANDROID_DIR/cmdline-tools"
    mv "$ANDROID_DIR/ct-tmp" "$ANDROID_DIR/cmdline-tools/latest"
  fi
  echo "[setup] platform-tools"
  download "$PT_URL" "$DL/platform-tools.zip"
  extract_zip "$DL/platform-tools.zip" "$ANDROID_DIR"
  echo "[ok] Android SDK tools"
}

sdk_paket() {
  echo "[setup] Android SDK / NDK $NDK_VERSION"
  echo "        This step may take several minutes."
  export JAVA_HOME="$JAVA_DIR"
  export PATH="$JAVA_DIR/bin:$PATH"
  local sdk="$ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager"
  yes | "$sdk" --sdk_root="$ANDROID_DIR" --licenses >/dev/null 2>&1 || true
  "$sdk" --sdk_root="$ANDROID_DIR" "platform-tools" "ndk;$NDK_VERSION" "cmake;3.22.1"
  echo "[ok] SDK / NDK"
}

rust_kur() {
  if [[ -x "$CARGO_HOME/bin/cargo" && -x "$CARGO_HOME/bin/cargo-ndk" ]]; then
    echo "[ok] Rust / cargo-ndk"
    return 0
  fi
  export PATH="$CARGO_HOME/bin:$PATH"
  if [[ ! -x "$CARGO_HOME/bin/cargo" ]]; then
    echo "[setup] Rust"
    download "$RUSTUP_URL" "$DL/rustup-init"
    chmod +x "$DL/rustup-init"
    "$DL/rustup-init" -y --default-host "$RUST_HOST" --default-toolchain stable --profile minimal --no-modify-path
  fi
  echo "[setup] Rust Android targets"
  "$CARGO_HOME/bin/rustup" target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
  if [[ ! -x "$CARGO_HOME/bin/cargo-ndk" ]]; then
    echo "[setup] cargo-ndk"
    "$CARGO_HOME/bin/cargo" install cargo-ndk --locked
  fi
  echo "[ok] Rust / cargo-ndk"
}

kaynak_indir() {
  if [[ -f "$APP/flutter/pubspec.yaml" ]]; then
    echo "[ok] Source"
    return 0
  fi
  kaynak_yenile_inner
}

kaynak_yenile_inner() {
  echo "[source] Fred TV"
  rm -rf "$APP"
  mkdir -p "$DL"
  if download "$KAYNAK_ZIP" "$DL/fred-tv.zip" && extract_zip "$DL/fred-tv.zip" "$ROOT"; then
    local d
    for d in "$ROOT"/fred-tv-mobile-*; do
      if [[ -d "$d" ]]; then
        mv "$d" "$APP"
        break
      fi
    done
  fi
  if [[ ! -f "$APP/flutter/pubspec.yaml" ]]; then
    echo "[source] Zip failed, trying git clone"
    rm -rf "$APP" "$ROOT/fred-tv-mobile-main"
    if ! command -v git >/dev/null 2>&1; then
      echo "[error] git not found and zip extract failed." >&2
      return 1
    fi
    git clone --depth 1 "$KAYNAK_GIT" "$APP"
  fi
  if [[ ! -f "$APP/flutter/pubspec.yaml" ]]; then
    echo "[error] Source extract failed." >&2
    return 1
  fi
  echo "[ok] Source"
}

export_tools() {
  export JAVA_HOME="$JAVA_DIR"
  export ANDROID_HOME="$ANDROID_DIR"
  export ANDROID_SDK_ROOT="$ANDROID_DIR"
  export ANDROID_NDK_HOME="$ANDROID_DIR/ndk/$NDK_VERSION"
  export RUSTUP_HOME="$TOOLS/rust/rustup"
  export CARGO_HOME="$TOOLS/rust/cargo"
  export PATH="$FLUTTER_DIR/bin:$JAVA_DIR/bin:$CARGO_HOME/bin:$ANDROID_DIR/cmdline-tools/latest/bin:$ANDROID_DIR/platform-tools:$ANDROID_DIR/cmake/3.22.1/bin:$PATH"
}

tls_patch() {
  if [[ ! -f "$APP/Cargo.toml" ]]; then
    return 0
  fi
  echo "[patch] TLS backend"
  if grep -q 'native-tls-vendored' "$APP/Cargo.toml"; then
    echo "[patch] Switching Cargo TLS backend to rustls"
    local tmp
    tmp="$(mktemp)"
    sed 's/native-tls-vendored/rustls/g' "$APP/Cargo.toml" > "$tmp"
    mv "$tmp" "$APP/Cargo.toml"
  fi
  echo "[ok] TLS backend"
}

derle() {
  echo "Building..."
  if [[ ! -f "$APP/flutter/pubspec.yaml" ]]; then
    echo "[error] No source. Run [1] first." >&2
    return 1
  fi
  if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
    echo "[error] Toolchain missing. Run [1] first." >&2
    return 1
  fi
  export_tools
  tls_patch
  local build="$ROOT/hstream/build.sh"
  if [[ ! -f "$build" ]]; then
    echo "[error] hstream/build.sh missing." >&2
    return 1
  fi
  chmod +x "$build" "$ROOT/hstream/build.sh" 2>/dev/null || true
  bash "$build"
}

full_setup() {
  hazirlik
  jdk_kur
  flutter_kur
  android_kur
  rust_kur
  kaynak_indir
  sdk_paket
  derle
}

refresh() {
  hazirlik
  rm -rf "$APP"
  kaynak_yenile_inner
  echo "Source refreshed. Choose [2] to build."
}

menu() {
  while true; do
    echo
    echo " HStream"
    echo " $ROOT"
    echo
    echo "  [1]  Setup and build"
    echo "  [2]  Build"
    echo "  [3]  Refresh source"
    echo "  [4]  Exit"
    echo
    local sec=""
    read -r -p "> " sec || exit 0
    case "$sec" in
      1) full_setup || echo "[error] Setup stopped. Check the message above and retry." ;;
      2) derle || true ;;
      3) refresh || true ;;
      4) exit 0 ;;
      *) ;;
    esac
  done
}

run_choice() {
  case "$1" in
    1|setup) full_setup ;;
    2|build) derle ;;
    3|refresh) refresh ;;
    4|exit) exit 0 ;;
    *) echo "[error] Usage: $0 [setup|build|refresh]"; exit 1 ;;
  esac
}

if [[ $# -ge 1 ]]; then
  run_choice "$1"
elif [[ -t 0 ]]; then
  menu
else
  full_setup
fi
