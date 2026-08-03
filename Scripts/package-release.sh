#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-${ROOT}/Build/Hitomi Badayo.app}"
OUTPUT_DIR="${2:-${ROOT}/Build-Package}"
APP="${APP:A}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="${OUTPUT_DIR:A}"

[[ -d "${APP}" ]] || { print -u2 -- "Missing app bundle: ${APP}"; exit 1; }
codesign --verify --deep --strict "${APP}"

STAGE="$(mktemp -d /private/tmp/HitomiBadayo-Package.XXXXXX)"
trap 'rm -rf "${STAGE}"' EXIT
SOURCE_STAGE="${STAGE}/HitomiBadayo"
APP_STAGE="${STAGE}/macOS"
APP_ARCHIVE="${OUTPUT_DIR}/Hitomi-Badayo-macOS.zip"
SOURCE_ARCHIVE="${OUTPUT_DIR}/Hitomi-Badayo-source.zip"
APP_BUNDLE_NAME="Hitomi Badayo.app"

mkdir -p "${SOURCE_STAGE}" "${APP_STAGE}"
for item in \
    .gitattributes \
    .gitignore \
    Info.plist \
    LICENSE \
    LICENSES \
    README.md \
    README.ja.md \
    README.ko.md \
    README.zh-Hans.md \
    README.zh-Hant.md \
    Resources \
    Sources \
    build.sh; do
    COPYFILE_DISABLE=1 /usr/bin/ditto "${ROOT}/${item}" "${SOURCE_STAGE}/${item}"
done
mkdir -p "${SOURCE_STAGE}/docs" "${SOURCE_STAGE}/Scripts"
for item in \
    docs/CHANGELOG.md \
    docs/INSTALLATION.md \
    docs/PRIVACY.md \
    docs/SECURITY.md \
    docs/THIRD_PARTY_NOTICES.md \
    Scripts/build-aria2.sh \
    Scripts/check-public-tree.sh \
    Scripts/package-release.sh; do
    COPYFILE_DISABLE=1 /usr/bin/ditto "${ROOT}/${item}" "${SOURCE_STAGE}/${item}"
done
COPYFILE_DISABLE=1 /usr/bin/ditto "${ROOT}/LICENSE" "${APP_STAGE}/LICENSE"
COPYFILE_DISABLE=1 /usr/bin/ditto "${APP}" "${APP_STAGE}/${APP_BUNDLE_NAME}"
COPYFILE_DISABLE=1 /usr/bin/ditto "${ROOT}/docs/INSTALLATION.md" "${APP_STAGE}/INSTALL.md"
COPYFILE_DISABLE=1 /usr/bin/ditto "${ROOT}/docs/THIRD_PARTY_NOTICES.md" "${APP_STAGE}/THIRD_PARTY_NOTICES.md"
COPYFILE_DISABLE=1 /usr/bin/ditto "${ROOT}/LICENSES" "${APP_STAGE}/LICENSES"

rm -f "${APP_ARCHIVE}" "${SOURCE_ARCHIVE}"
(
    cd "${APP_STAGE}"
    COPYFILE_DISABLE=1 /usr/bin/zip -qryX "${APP_ARCHIVE}" "${APP_BUNDLE_NAME}" LICENSE INSTALL.md \
        THIRD_PARTY_NOTICES.md LICENSES \
        -x '*/.DS_Store' '*/._*' '*/__MACOSX/*'
)
(
    cd "${STAGE}"
    COPYFILE_DISABLE=1 /usr/bin/zip -qryX "${SOURCE_ARCHIVE}" HitomiBadayo \
        -x '*/.DS_Store' '*/._*' '*/__MACOSX/*' '*/.build/*' '*/Build*/*' \
        '*/.git/*' '*/__pycache__/*' '*.pyc'
)

for archive in "${APP_ARCHIVE}" "${SOURCE_ARCHIVE}"; do
    unzip -tq "${archive}" >/dev/null
    if zipinfo -1 "${archive}" | LC_ALL=C grep -Eq '(^|/)(__MACOSX|\.DS_Store)(/|$)|(^|/)\._|(^|/)(\.build|\.git|__pycache__)(/|$)|(^|/)Build[^/]*/|\.pyc$'; then
        print -u2 -- "Release archive contains forbidden generated metadata: ${archive}"
        exit 1
    fi
done

print -- "Packaged ${APP_ARCHIVE}"
print -- "Packaged ${SOURCE_ARCHIVE}"
