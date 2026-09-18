#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/Build"

APP_PATH="${1:-${BUILD_DIR}/Newer.app}"
OUTPUT_PATH="${2:-}"

usage() {
    cat <<'USAGE'
usage: Scripts/dmg.sh [App.app] [Output.dmg]

Packages a signed and notarized app into a compressed DMG with an Applications
shortcut. Defaults to Build/Newer.app and Build/Newer-v<version>.dmg.
USAGE
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing command: $1" >&2
        exit 1
    fi
}

absolute_path() {
    local path="$1"

    if [[ "${path}" == /* ]]; then
        printf '%s\n' "${path}"
    else
        printf '%s\n' "${PROJECT_DIR}/${path}"
    fi
}

read_plist_value() {
    local plist_path="$1"
    local key_path="$2"

    /usr/libexec/PlistBuddy -c "Print :${key_path}" "${plist_path}" 2>/dev/null || true
}

if [[ "${APP_PATH}" == "-h" || "${APP_PATH}" == "--help" ]]; then
    usage
    exit 0
fi

require_command codesign
require_command diskutil
require_command ditto
require_command hdiutil
require_command osascript
require_command shasum
require_command spctl
require_command xcrun

run_quietly() {
    local output

    if ! output="$("$@" 2>&1)"; then
        printf '%s\n' "${output}" >&2
        return 1
    fi
}

APP_PATH="$(absolute_path "${APP_PATH}")"
if [[ ! -d "${APP_PATH}" || "${APP_PATH}" != *.app ]]; then
    echo "error: invalid app path: ${APP_PATH}" >&2
    exit 1
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
if [[ ! -f "${INFO_PLIST}" ]]; then
    echo "error: app Info.plist is missing: ${INFO_PLIST}" >&2
    exit 1
fi

APP_NAME="$(read_plist_value "${INFO_PLIST}" CFBundleDisplayName)"
VERSION="$(read_plist_value "${INFO_PLIST}" CFBundleShortVersionString)"
BUILD="$(read_plist_value "${INFO_PLIST}" CFBundleVersion)"

if [[ -z "${APP_NAME}" || -z "${VERSION}" || -z "${BUILD}" ]]; then
    echo "error: app name, version or build number is missing" >&2
    exit 1
fi

if [[ -z "${OUTPUT_PATH}" ]]; then
    OUTPUT_PATH="${BUILD_DIR}/${APP_NAME}-v${VERSION}.dmg"
else
    OUTPUT_PATH="$(absolute_path "${OUTPUT_PATH}")"
fi
if [[ "${OUTPUT_PATH}" != *.dmg ]]; then
    echo "error: output path must end with .dmg: ${OUTPUT_PATH}" >&2
    exit 1
fi

echo "==> Validating signed and notarized app"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
TEMP_ROOT="$(mktemp -d "/private/tmp/NewerDMG.XXXXXX")"
STAGING_DIR="${TEMP_ROOT}/staging"
MOUNT_POINT="${TEMP_ROOT}/mount"
RW_DMG="${TEMP_ROOT}/${APP_NAME}-layout.dmg"
TEMP_DMG="${TEMP_ROOT}/${APP_NAME}.dmg"
MOUNTED="0"

cleanup() {
    if [[ "${MOUNTED}" == "1" ]]; then
        diskutil eject "${MOUNT_POINT}" >/dev/null 2>&1 || true
    fi
    rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${STAGING_DIR}" "${MOUNT_POINT}" "${OUTPUT_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"

echo "==> Creating writable DMG"
run_quietly diskutil image create from \
    --format RAW \
    --volumeName "${APP_NAME}" \
    "${STAGING_DIR}" \
    "${RW_DMG}"

echo "==> Writing Finder layout"
run_quietly diskutil image attach \
    --mountPoint "${MOUNT_POINT}" \
    "${RW_DMG}"
MOUNTED="1"

osascript - "${MOUNT_POINT}" "${APP_NAME}" <<'APPLESCRIPT'
on run argv
    set mountPath to item 1 of argv
    set appName to item 2 of argv
    set mountFolder to POSIX file mountPath as alias
    set applicationsFolder to POSIX file "/Applications" as alias

    tell application "Finder"
        open mountFolder
        delay 1
        if exists item "Applications" of mountFolder then
            delete item "Applications" of mountFolder
        end if
        make new alias file to applicationsFolder at mountFolder with properties {name:"Applications"}
        set targetWindow to front window
        set current view of targetWindow to icon view
        set toolbar visible of targetWindow to false
        set statusbar visible of targetWindow to false
        set bounds of targetWindow to {120, 120, 640, 420}
        set viewOptions to icon view options of targetWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set position of item (appName & ".app") of mountFolder to {170, 80}
        set position of item "Applications" of mountFolder to {350, 80}
        update mountFolder without registering applications
        delay 2
        close targetWindow
    end tell
end run
APPLESCRIPT

sync
run_quietly diskutil eject "${MOUNT_POINT}"
MOUNTED="0"

echo "==> Creating compressed DMG"
run_quietly diskutil image create from \
    --format UDZO \
    "${RW_DMG}" \
    "${TEMP_DMG}"

hdiutil verify "${TEMP_DMG}" >/dev/null
rm -f "${OUTPUT_PATH}"
mv "${TEMP_DMG}" "${OUTPUT_PATH}"

CHECKSUM="$(shasum -a 256 "${OUTPUT_PATH}" | awk '{print $1}')"
echo "==> Created ${OUTPUT_PATH}"
echo "    Version: ${VERSION} (${BUILD})"
echo "    SHA-256: ${CHECKSUM}"
