#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT_DIR="${1:-${ROOT}/Build}"
APP="${OUTPUT_DIR}/Hitomi Badayo.app"
CONTENTS="${APP}/Contents"
ARCH="${HITOMI_BADAYO_ARCH:-${HITOMI_NATIVE_ARCH:-arm64}}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
source_files=("${ROOT}"/Sources/**/*.swift(N.))

if (( ${#source_files[@]} == 0 )); then
    print -u2 -- "No Swift sources found under ${ROOT}/Sources."
    exit 1
fi

rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

swiftc -O -parse-as-library \
    -sdk "${SDKROOT}" \
    -target "${ARCH}-apple-macos${DEPLOYMENT_TARGET}" \
    "${source_files[@]}" \
    -o "${CONTENTS}/MacOS/HitomiBadayo"

install -m 644 "${ROOT}/Info.plist" "${CONTENTS}/Info.plist"
/usr/bin/ditto "${ROOT}/Resources" "${CONTENTS}/Resources"
install -m 644 "${ROOT}/LICENSE" "${CONTENTS}/Resources/LICENSE"
install -m 644 "${ROOT}/docs/THIRD_PARTY_NOTICES.md" "${CONTENTS}/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "${ROOT}/LICENSES" "${CONTENTS}/Resources/LICENSES"
install -m 755 "${ROOT}/Scripts/build-aria2.sh" "${CONTENTS}/Resources/ThirdParty/build-aria2.sh"
find "${CONTENTS}/Resources" -name .DS_Store -delete

autofill_guard="$(/usr/libexec/PlistBuddy -c 'Print :NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac' "${CONTENTS}/Info.plist" 2>/dev/null || true)"
if [[ "${autofill_guard}" != "true" ]]; then
    print -u2 -- "Refusing to package without the macOS one-time-code AutoFill guard."
    exit 1
fi

for bundled_tool in aria2c spoofdpi; do
    bundled_tool_path="${CONTENTS}/Resources/Tools/${bundled_tool}"
    if [[ -f "${bundled_tool_path}" ]]; then
        chmod 755 "${bundled_tool_path}"
        codesign --force --sign - "${bundled_tool_path}"
    fi
done

while IFS= read -r -d '' candidate; do
    /usr/bin/file -b "${candidate}" | grep -Fq 'Mach-O' || continue
    undefined_symbols="$(nm -u "${candidate}" 2>/dev/null || true)"
    for forbidden_pattern in \
        '_SecItem' \
        '_SecKeychain' \
        '_OBJC_CLASS_$_LAContext' \
        '_AuthorizationCreate' \
        '_AuthorizationCopyRights' \
        '_AuthorizationExecuteWithPrivileges'; do
        if print -r -- "${undefined_symbols}" | grep -Fq "${forbidden_pattern}"; then
            print -u2 -- "Refusing to package ${candidate#${APP}/} with authentication symbol: ${forbidden_pattern}"
            exit 1
        fi
    done
done < <(find "${CONTENTS}" -type f -perm -111 -print0)

codesign --force --sign - "${APP}"
echo "Built ${APP}"
