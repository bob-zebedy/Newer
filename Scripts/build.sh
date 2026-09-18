#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

XCODE_PROJECT="${PROJECT_DIR}/Newer.xcodeproj"
XCODE_SCHEME="Newer"
APP_TARGET="Newer"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/Build"
VERSION_CONFIG="${PROJECT_DIR}/Config/Version.xcconfig"
NOTARY_PROFILE="${NEWER_NOTARY_PROFILE:-apple-notary}"
ALLOW_PROVISIONING_UPDATES="1"

usage() {
    cat <<'USAGE'
usage: Scripts/build.sh [options]

Builds and exports Newer with Developer ID, submits it to Apple notarization,
staples the ticket, validates the app and writes Build/Newer.app.

Options:
  --notary-profile PROFILE       notarytool Keychain profile
                                 Default: NEWER_NOTARY_PROFILE or apple-notary
  --no-provisioning-updates      Do not pass -allowProvisioningUpdates to Xcode
  -h, --help                     Show this help

Configure the Keychain profile once:
  xcrun notarytool store-credentials "apple-notary" \
    --apple-id "<Apple ID>" --team-id "<Team ID>" --sync
USAGE
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --notary-profile)
                if [[ "$#" -lt 2 || -z "$2" ]]; then
                    echo "error: --notary-profile requires a value" >&2
                    exit 1
                fi
                NOTARY_PROFILE="$2"
                shift 2
            ;;
            --notary-profile=*)
                NOTARY_PROFILE="${1#*=}"
                if [[ -z "${NOTARY_PROFILE}" ]]; then
                    echo "error: --notary-profile requires a value" >&2
                    exit 1
                fi
                shift
            ;;
            --no-provisioning-updates)
                ALLOW_PROVISIONING_UPDATES="0"
                shift
            ;;
            -h|--help)
                usage
                exit 0
            ;;
            *)
                echo "error: unknown option: $1" >&2
                usage >&2
                exit 1
            ;;
        esac
    done
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing command: $1" >&2
        exit 1
    fi
}

read_build_setting() {
    local name="$1"

    printf '%s\n' "${BUILD_SETTINGS}" |
        awk -F= -v key="${name}" '
          $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
          }
        '
}

read_version_setting() {
    local name="$1"

    awk -F= -v key="${name}" '
      $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
        value = $2
        gsub(/^[[:space:]]+|[[:space:];]+$/, "", value)
        print value
        exit
      }
    ' "${VERSION_CONFIG}"
}

read_plist_value() {
    local plist_path="$1"
    local key_path="$2"

    /usr/libexec/PlistBuddy -c "Print :${key_path}" "${plist_path}" 2>/dev/null || true
}

read_plist_values() {
    local plist_path="$1"
    local key_path="$2"
    local raw_value=""

    if ! raw_value="$(/usr/libexec/PlistBuddy -c "Print :${key_path}" "${plist_path}" 2>/dev/null)"; then
        return 0
    fi

    printf '%s\n' "${raw_value}" |
        awk '
          /^[[:space:]]*(Array|Dict) \{$/ || /^[[:space:]]*\}$/ { next }
          {
            value = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value != "") print value
          }
        ' |
        sort
}

write_export_options() {
    local path="$1"

    cat > "${path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST
}

validate_signature() {
    local bundle_path="$1"
    local bundle_name="$2"
    local signature_details=""

    codesign --verify --deep --strict --verbose=2 "${bundle_path}"
    signature_details="$(codesign --display --verbose=4 "${bundle_path}" 2>&1)"

    if ! grep -q '^Authority=Developer ID Application:' <<< "${signature_details}"; then
        echo "error: ${bundle_name} is not signed with Developer ID Application" >&2
        exit 1
    fi
    if ! grep -q "^TeamIdentifier=${TEAM_ID}$" <<< "${signature_details}"; then
        echo "error: ${bundle_name} is not signed by team ${TEAM_ID}" >&2
        exit 1
    fi
    if ! grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' <<< "${signature_details}"; then
        echo "error: ${bundle_name} does not enable Hardened Runtime" >&2
        exit 1
    fi
}

extract_entitlements() {
    local bundle_path="$1"
    local output_path="$2"

    if ! codesign --display --entitlements="${output_path}" --xml "${bundle_path}" >/dev/null 2>&1; then
        echo "error: unable to read entitlements from ${bundle_path}" >&2
        exit 1
    fi
    if [[ ! -s "${output_path}" ]]; then
        echo "error: empty entitlements for ${bundle_path}" >&2
        exit 1
    fi
}

validate_app() {
    local app_path="$1"
    local info_plist="${app_path}/Contents/Info.plist"
    local plugins_path="${app_path}/Contents/PlugIns"
    local extension_path=""
    local extension_info_plist=""
    local app_bundle_identifier=""
    local extension_bundle_identifier=""
    local app_version=""
    local app_build=""
    local extension_version=""
    local extension_build=""
    local app_entitlements="${TEMP_ROOT}/app-entitlements.plist"
    local extension_entitlements="${TEMP_ROOT}/extension-entitlements.plist"
    local app_groups=""
    local extension_groups=""
    local app_sandbox=""
    local extension_sandbox=""
    local app_debugger=""
    local extension_debugger=""
    local -a extensions=()

    if [[ ! -d "${app_path}" || ! -f "${info_plist}" ]]; then
        echo "error: invalid app bundle: ${app_path}" >&2
        exit 1
    fi

    while IFS= read -r extension; do
        extensions+=("${extension}")
    done < <(find "${plugins_path}" -maxdepth 1 -type d -name '*.appex' | sort)

    if [[ "${#extensions[@]}" -ne 1 ]]; then
        echo "error: expected one embedded extension, found ${#extensions[@]}" >&2
        exit 1
    fi

    extension_path="${extensions[0]}"
    extension_info_plist="${extension_path}/Contents/Info.plist"
    if [[ ! -f "${extension_info_plist}" ]]; then
        echo "error: extension Info.plist is missing: ${extension_info_plist}" >&2
        exit 1
    fi

    app_bundle_identifier="$(read_plist_value "${info_plist}" CFBundleIdentifier)"
    extension_bundle_identifier="$(read_plist_value "${extension_info_plist}" CFBundleIdentifier)"
    app_version="$(read_plist_value "${info_plist}" CFBundleShortVersionString)"
    app_build="$(read_plist_value "${info_plist}" CFBundleVersion)"
    extension_version="$(read_plist_value "${extension_info_plist}" CFBundleShortVersionString)"
    extension_build="$(read_plist_value "${extension_info_plist}" CFBundleVersion)"

    if [[ -z "${app_bundle_identifier}" || -z "${extension_bundle_identifier}" ]]; then
        echo "error: app or extension bundle identifier is missing" >&2
        exit 1
    fi
    if [[ "${app_bundle_identifier}" != "${EXPECTED_BUNDLE_IDENTIFIER}" ]]; then
        echo "error: expected app identifier ${EXPECTED_BUNDLE_IDENTIFIER}, got ${app_bundle_identifier}" >&2
        exit 1
    fi
    if [[ "${extension_bundle_identifier}" == "${app_bundle_identifier}" ]]; then
        echo "error: app and extension bundle identifiers must be different" >&2
        exit 1
    fi
    if [[ "${extension_bundle_identifier}" != "${app_bundle_identifier}."* ]]; then
        echo "error: extension identifier is outside the app namespace: ${extension_bundle_identifier}" >&2
        exit 1
    fi
    if [[ "${app_version}" != "${EXPECTED_VERSION}" || "${app_build}" != "${EXPECTED_BUILD}" ]]; then
        echo "error: app version ${app_version} (${app_build}) does not match ${EXPECTED_VERSION} (${EXPECTED_BUILD})" >&2
        exit 1
    fi
    if [[ "${extension_version}" != "${app_version}" || "${extension_build}" != "${app_build}" ]]; then
        echo "error: app and extension versions do not match" >&2
        exit 1
    fi

    validate_signature "${extension_path}" "Finder extension"
    validate_signature "${app_path}" "App"
    extract_entitlements "${app_path}" "${app_entitlements}"
    extract_entitlements "${extension_path}" "${extension_entitlements}"

    app_groups="$(read_plist_values "${app_entitlements}" com.apple.security.application-groups)"
    extension_groups="$(read_plist_values "${extension_entitlements}" com.apple.security.application-groups)"
    app_sandbox="$(read_plist_value "${app_entitlements}" com.apple.security.app-sandbox)"
    extension_sandbox="$(read_plist_value "${extension_entitlements}" com.apple.security.app-sandbox)"
    app_debugger="$(read_plist_value "${app_entitlements}" com.apple.security.get-task-allow)"
    extension_debugger="$(read_plist_value "${extension_entitlements}" com.apple.security.get-task-allow)"

    if [[ -z "${app_groups}" || "${app_groups}" != "${extension_groups}" ]]; then
        echo "error: app and extension App Group entitlements do not match" >&2
        exit 1
    fi
    if [[ "${app_sandbox}" != "true" || "${extension_sandbox}" != "true" ]]; then
        echo "error: app and extension must enable App Sandbox" >&2
        exit 1
    fi
    if [[ "${app_debugger}" == "true" || "${extension_debugger}" == "true" ]]; then
        echo "error: Release app must not contain get-task-allow" >&2
        exit 1
    fi

    printf '    App:       %s %s (%s)\n' "${app_bundle_identifier}" "${app_version}" "${app_build}"
    printf '    Extension: %s\n' "${extension_bundle_identifier}"
    printf '    App Group: %s\n' "$(tr '\n' ',' <<< "${app_groups}" | sed 's/,$//')"
}

parse_args "$@"

require_command awk
require_command codesign
require_command ditto
require_command find
require_command grep
require_command sed
require_command sort
require_command spctl
require_command xcodebuild
require_command xcrun

if [[ ! -d "${XCODE_PROJECT}" ]]; then
    echo "error: Xcode project not found: ${XCODE_PROJECT}" >&2
    exit 1
fi
if [[ ! -f "${VERSION_CONFIG}" ]]; then
    echo "error: version configuration not found: ${VERSION_CONFIG}" >&2
    exit 1
fi

echo "==> Reading build settings"
BUILD_SETTINGS="$(
    xcodebuild \
        -project "${XCODE_PROJECT}" \
        -target "${APP_TARGET}" \
        -configuration "${CONFIGURATION}" \
        -showBuildSettings
)"

TEAM_ID="$(read_build_setting DEVELOPMENT_TEAM)"
EXPECTED_BUNDLE_IDENTIFIER="$(read_build_setting PRODUCT_BUNDLE_IDENTIFIER)"
EXPECTED_VERSION="$(read_version_setting MARKETING_VERSION)"
EXPECTED_BUILD="$(read_version_setting CURRENT_PROJECT_VERSION)"
FULL_PRODUCT_NAME="$(read_build_setting FULL_PRODUCT_NAME)"

if [[ -z "${TEAM_ID}" || -z "${EXPECTED_BUNDLE_IDENTIFIER}" ]]; then
    echo "error: DEVELOPMENT_TEAM or PRODUCT_BUNDLE_IDENTIFIER is missing" >&2
    exit 1
fi
if [[ -z "${EXPECTED_VERSION}" || -z "${EXPECTED_BUILD}" ]]; then
    echo "error: version configuration is incomplete" >&2
    exit 1
fi
if [[ -z "${FULL_PRODUCT_NAME}" || "${FULL_PRODUCT_NAME}" == *'$('* ]]; then
    FULL_PRODUCT_NAME="${APP_TARGET}.app"
fi

TEMP_ROOT="$(mktemp -d "/private/tmp/NewerRelease.XXXXXX")"
DERIVED_DATA_PATH="${TEMP_ROOT}/DerivedData"
ARCHIVE_PATH="${TEMP_ROOT}/${XCODE_SCHEME}.xcarchive"
EXPORT_PATH="${TEMP_ROOT}/Export"
EXPORT_OPTIONS_PLIST="${TEMP_ROOT}/ExportOptions.plist"
NOTARY_ARCHIVE="${TEMP_ROOT}/${APP_TARGET}-notary.zip"
OUTPUT_APP_PATH="${BUILD_DIR}/${FULL_PRODUCT_NAME}"

cleanup() {
    rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT

write_export_options "${EXPORT_OPTIONS_PLIST}"
mkdir -p "${BUILD_DIR}" "${EXPORT_PATH}"

PROVISIONING_FLAGS=()
if [[ "${ALLOW_PROVISIONING_UPDATES}" == "1" ]]; then
    PROVISIONING_FLAGS=(-allowProvisioningUpdates)
fi

echo "==> Archiving ${XCODE_SCHEME} ${EXPECTED_VERSION} (${EXPECTED_BUILD})"
xcodebuild \
    -project "${XCODE_PROJECT}" \
    -scheme "${XCODE_SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -archivePath "${ARCHIVE_PATH}" \
    "${PROVISIONING_FLAGS[@]+"${PROVISIONING_FLAGS[@]}"}" \
    archive

echo "==> Exporting Developer ID app"
xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    "${PROVISIONING_FLAGS[@]+"${PROVISIONING_FLAGS[@]}"}"

EXPORTED_APP_PATH="${EXPORT_PATH}/${FULL_PRODUCT_NAME}"
if [[ ! -d "${EXPORTED_APP_PATH}" ]]; then
    echo "error: exported app not found: ${EXPORTED_APP_PATH}" >&2
    exit 1
fi

echo "==> Validating exported app"
validate_app "${EXPORTED_APP_PATH}"

echo "==> Preparing notarization archive"
ditto -c -k --keepParent "${EXPORTED_APP_PATH}" "${NOTARY_ARCHIVE}"

echo "==> Submitting to Apple notarization"
xcrun notarytool submit \
    "${NOTARY_ARCHIVE}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${EXPORTED_APP_PATH}"
xcrun stapler validate "${EXPORTED_APP_PATH}"

rm -rf "${OUTPUT_APP_PATH}"
ditto "${EXPORTED_APP_PATH}" "${OUTPUT_APP_PATH}"

echo "==> Validating final app"
validate_app "${OUTPUT_APP_PATH}"
xcrun stapler validate "${OUTPUT_APP_PATH}"
spctl --assess --type execute --verbose=4 "${OUTPUT_APP_PATH}"

echo "==> Built and notarized ${OUTPUT_APP_PATH}"
echo "==> Next: Scripts/dmg.sh"
