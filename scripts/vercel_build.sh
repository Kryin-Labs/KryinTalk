#!/usr/bin/env bash
set -euo pipefail
FLUTTER_VERSION=3.44.9
FLUTTER_SDK="${TMPDIR:-/tmp}/kryintalk-flutter-${FLUTTER_VERSION}"
if [[ ! -x "$FLUTTER_SDK/bin/flutter" ]]; then
  mkdir -p "$FLUTTER_SDK"
  archive="${FLUTTER_SDK}.tar.xz"
  curl --fail --location --retry 3 "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o "$archive"
  echo "a9120fa4a01048bdef438ddc3a2d4b7389662ea98a95db86eeaf10382bc4efcb  $archive" | sha256sum --check
  tar -xJ --strip-components=1 -f "$archive" -C "$FLUTTER_SDK"
fi
export PATH="$FLUTTER_SDK/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_SDK"
cd clients/web
flutter pub get
flutter build web --release \
  --dart-define="AUTH_CALLBACK_ORIGIN=${AUTH_CALLBACK_ORIGIN:-https://kryintalks.vercel.app}" \
  --dart-define="KRYINTALK_ADMIN_CONTACT_EMAIL=${KRYINTALK_ADMIN_CONTACT_EMAIL:-}"
