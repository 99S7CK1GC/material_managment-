# Build all release artifacts for Wameedh.
#
# This script is intended to be used on a machine with Flutter installed
# and the Android SDK configured. It builds the Android APK/AAB and, when
# the host OS supports it, also builds the Linux and Windows desktop bundles.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/wameedh_app"
ARTIFACT_DIR="${ROOT_DIR}/release-artifacts"

mkdir -p "${ARTIFACT_DIR}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found in PATH. Install Flutter first."
  exit 1
fi

cd "${APP_DIR}"

flutter clean
flutter pub get

echo "==> Building Android APK"
flutter build apk --release
cp "build/app/outputs/flutter-apk/app-release.apk" "${ARTIFACT_DIR}/wameedh-android.apk"

echo "==> Building Android App Bundle"
flutter build appbundle --release
cp "build/app/outputs/bundle/release/app-release.aab" "${ARTIFACT_DIR}/wameedh-android.aab"

case "$(uname -s)" in
  Linux)
    echo "==> Building Linux desktop bundle"
    flutter build linux --release
    tar -C "build/linux/x64/release" -czf "${ARTIFACT_DIR}/wameedh-linux-x64.tar.gz" bundle
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    echo "==> Building Windows desktop bundle"
    flutter build windows --release
    powershell -NoProfile -Command "Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath '${ARTIFACT_DIR}/wameedh-windows-x64.zip' -Force"
    ;;
  *)
    echo "==> Skipping Linux/Windows build because this host is not Linux or Windows."
    ;;
 esac

echo "Release artifacts created in ${ARTIFACT_DIR}"
