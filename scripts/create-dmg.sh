#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/TeamsAutoRecorder.xcodeproj"
SCHEME="TeamsAutoRecorder"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
APP_PATH=""
OUTPUT_DIR="$ROOT_DIR/build"
VOLUME_NAME="TeamsAutoRecorder"
DMG_NAME_PREFIX="TeamsAutoRecorder"
VERSION_OVERRIDE=""
NO_BUILD="0"

# Notarization options
SIGN_IDENTITY=""       # e.g. "Developer ID Application: Your Name (TEAMID)"
NOTARIZE="0"
KEYCHAIN_PROFILE=""    # xcrun notarytool store-credentials で事前登録したプロファイル名
ENTITLEMENTS_PATH="$ROOT_DIR/TeamsAutoRecorder/TeamsAutoRecorder.entitlements"

usage() {
  cat <<'EOF'
Usage: scripts/create-dmg.sh [options]

Options:
  --version <x.y.z>          DMG filename version override
  --app-path <path>          Use existing .app path
  --output-dir <path>        DMG output directory (default: build)
  --volume-name <name>       DMG volume name (default: TeamsAutoRecorder)
  --dmg-name-prefix <name>   DMG filename prefix (default: TeamsAutoRecorder)
  --entitlements <path>      Entitlements file path used for codesigning
  --no-build                 Skip xcodebuild and package existing app
  --sign <identity>          Developer ID Application identity for codesigning
  --notarize                 Submit DMG to Apple's notary service and staple
  --keychain-profile <name>  Keychain profile for notarytool credentials
                             (create with: xcrun notarytool store-credentials <name>)
  -h, --help                 Show this help

Examples:
  # Build, sign, notarize
  scripts/create-dmg.sh \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    --notarize \
    --keychain-profile "teams-auto-recorder-notary"

  # Package existing app without notarization
  scripts/create-dmg.sh --app-path /path/to/TeamsAutoRecorder.app --no-build
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION_OVERRIDE="${2:-}"
      shift 2
      ;;
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="${2:-}"
      shift 2
      ;;
    --dmg-name-prefix)
      DMG_NAME_PREFIX="${2:-}"
      shift 2
      ;;
    --entitlements)
      ENTITLEMENTS_PATH="${2:-}"
      shift 2
      ;;
    --no-build)
      NO_BUILD="1"
      shift
      ;;
    --sign)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --notarize)
      NOTARIZE="1"
      shift
      ;;
    --keychain-profile)
      KEYCHAIN_PROFILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Validate notarization prerequisites
if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "Error: --sign is required when --notarize is specified." >&2
    exit 1
  fi
  if [[ -z "$KEYCHAIN_PROFILE" ]]; then
    echo "Error: --keychain-profile is required when --notarize is specified." >&2
    echo "Create one with: xcrun notarytool store-credentials <profile-name>" >&2
    exit 1
  fi
fi

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"
fi

# --- Build ---
if [[ "$NO_BUILD" != "1" ]]; then
  build_args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    clean build
  )
  if [[ -n "$SIGN_IDENTITY" ]]; then
    build_args+=(
      CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
      CODE_SIGN_STYLE="Manual"
      OTHER_CODE_SIGN_FLAGS="--options=runtime"
    )
  fi
  xcodebuild "${build_args[@]}"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

# --- Determine version ---
version="$VERSION_OVERRIDE"
if [[ -z "$version" ]]; then
  info_plist="$APP_PATH/Contents/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    echo "Info.plist not found: $info_plist" >&2
    exit 1
  fi
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
fi

if [[ -z "$version" ]]; then
  echo "Failed to determine version. Pass --version explicitly." >&2
  exit 1
fi

# --- ヘルパー CLI ビルド & バンドル ---
echo "Building TeamsAutoRecorderMCP helper..."
swift build -c release --target TeamsAutoRecorderMCP
HELPER_SRC="$ROOT_DIR/.build/release/TeamsAutoRecorderMCP"
HELPER_DST="$APP_PATH/Contents/MacOS/TeamsAutoRecorderMCP"
cp "$HELPER_SRC" "$HELPER_DST"
echo "Helper bundled: $HELPER_DST"

# --- Codesign .app (--sign 指定時、--no-build でも再署名) ---
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing $APP_PATH ..."
  codesign \
    --deep \
    --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
  echo "App signed successfully."
fi

# --- Create DMG ---
staging_dir="$ROOT_DIR/build/dmg-root"
rm -rf "$staging_dir"
mkdir -p "$staging_dir"
cp -R "$APP_PATH" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

mkdir -p "$OUTPUT_DIR"
dmg_path="$OUTPUT_DIR/$DMG_NAME_PREFIX-$version.dmg"
rm -f "$dmg_path"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

echo "DMG created: $dmg_path"

# --- Sign DMG ---
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing DMG ..."
  codesign \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$dmg_path"
  echo "DMG signed."
fi

# --- Notarize & Staple ---
if [[ "$NOTARIZE" == "1" ]]; then
  echo "Submitting to Apple notary service (this may take several minutes) ..."
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

  echo "Stapling notarization ticket ..."
  xcrun stapler staple "$dmg_path"

  echo "Notarization complete. Verifying ..."
  spctl --assess --type open --context context:primary-signature -v "$dmg_path"
fi

echo "Done: $dmg_path"
