#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="1.37.0"
SOURCE_NAME="aria2-${VERSION}.tar.xz"
SOURCE_URL="https://github.com/aria2/aria2/releases/download/release-${VERSION}/${SOURCE_NAME}"
SOURCE_SHA256="60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b"
PATCH_FILE="${ROOT}/Resources/ThirdParty/aria2-apple-tls-no-keychain.patch"
BUILD_ROOT="${ARIA2_BUILD_ROOT:-${ROOT}/.build/aria2-${VERSION}}"
SOURCE_ARCHIVE="${BUILD_ROOT}/${SOURCE_NAME}"
SOURCE_DIR="${BUILD_ROOT}/aria2-${VERSION}"
INSTALL_DIR="${BUILD_ROOT}/install"
JOBS="${ARIA2_JOBS:-$(sysctl -n hw.ncpu)}"

mkdir -p "${BUILD_ROOT}" "${ROOT}/Resources/Tools" "${ROOT}/Resources/ThirdParty"

if [[ ! -f "${SOURCE_ARCHIVE}" ]]; then
    curl --fail --location --retry 3 --output "${SOURCE_ARCHIVE}" "${SOURCE_URL}"
fi

ACTUAL_SHA256="$(shasum -a 256 "${SOURCE_ARCHIVE}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${SOURCE_SHA256}" ]]; then
    print -u2 "aria2 source checksum mismatch: ${ACTUAL_SHA256}"
    exit 1
fi

rm -rf "${SOURCE_DIR}" "${INSTALL_DIR}"
tar -xJf "${SOURCE_ARCHIVE}" -C "${BUILD_ROOT}"
/usr/bin/patch --batch --forward -d "${SOURCE_DIR}" -p1 < "${PATCH_FILE}"

export MACOSX_DEPLOYMENT_TARGET="14.0"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export CFLAGS="-O2 -isysroot ${SDKROOT} -mmacosx-version-min=14.0"
export CXXFLAGS="-O2 -isysroot ${SDKROOT} -mmacosx-version-min=14.0"
export LDFLAGS="-isysroot ${SDKROOT} -mmacosx-version-min=14.0"

cd "${SOURCE_DIR}"
./configure \
    --prefix="${INSTALL_DIR}" \
    --disable-dependency-tracking \
    --disable-nls \
    --disable-libaria2 \
    --without-libxml2 \
    --without-libexpat \
    --without-sqlite3 \
    --without-libssh2 \
    --without-libcares \
    --without-libgcrypt \
    --without-gnutls \
    --without-openssl \
    --with-appletls
make -j"${JOBS}"
make install

install -m 755 "${INSTALL_DIR}/bin/aria2c" "${ROOT}/Resources/Tools/aria2c"
install -m 644 "${SOURCE_DIR}/COPYING" "${ROOT}/Resources/ThirdParty/aria2-COPYING.txt"
install -m 644 "${SOURCE_ARCHIVE}" "${ROOT}/Resources/ThirdParty/${SOURCE_NAME}"

print "Built ${ROOT}/Resources/Tools/aria2c"
