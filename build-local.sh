#!/bin/bash
set -euo pipefail

APP_NAME="PitaMado"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DEFAULT_CODE_SIGN_IDENTITY="PitaMado Local Code Signing"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-${DEFAULT_CODE_SIGN_IDENTITY}}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp PitaMado/Info.plist "${CONTENTS_DIR}/Info.plist"
if [ -d "PitaMado/Resources" ]; then
  cp -R PitaMado/Resources/. "${RESOURCES_DIR}/"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.0" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 13.0" "${CONTENTS_DIR}/Info.plist"
xcrun swiftc -O PitaMado/*.swift -o "${MACOS_DIR}/${APP_NAME}"

SIGN_IDENTITY="-"
if security find-identity -v -p codesigning | grep -Fq "\"${CODE_SIGN_IDENTITY}\""; then
  SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"
else
  cat <<EOF >&2
warning: code signing identity "${CODE_SIGN_IDENTITY}" was not found.
warning: falling back to ad-hoc signing, which can invalidate Accessibility permission after rebuilds.
warning: create a local code signing certificate named "${DEFAULT_CODE_SIGN_IDENTITY}" to keep TCC permissions stable.
EOF
fi

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"

echo "Built ${APP_DIR}"
echo "Signed with ${SIGN_IDENTITY}"
