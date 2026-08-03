#!/bin/zsh
set -u

ROOT="${0:A:h:h}"
MODE="${1:-private}"
FAILURES=0

fail() {
    print -u2 -- "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

if [[ "${MODE}" != "private" && "${MODE}" != "--public" ]]; then
    print -u2 -- "usage: $0 [--public]"
    exit 2
fi

generated_entries="$(find "${ROOT}" -path "${ROOT}/.git" -prune -o \
    \( -name .DS_Store -o -name '._*' -o -name __pycache__ -o -name '*.pyc' \
       -o -name '*.app' -o -name '*.dmg' -o -name '*.zip' \
       -o -name '.build*' -o -name 'Build' -o -name 'Build-*' \) \
    -print 2>/dev/null)"
if [[ -n "${generated_entries}" ]]; then
    fail "generated or packaged files are present:\n${generated_entries}"
fi

sensitive_files="$(find "${ROOT}" -path "${ROOT}/.git" -prune -o -type f \
    \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.p12' \
       -o -name '*.mobileprovision' -o -name 'Cookies' -o -name 'cookies.sqlite' \
       -o -name 'Login Data' -o -name 'user-data.json' -o -name 'queue*.json' \) \
    -print 2>/dev/null)"
if [[ -n "${sensitive_files}" ]]; then
    fail "possible secret or user-data files are present:\n${sensitive_files}"
fi

private_path_pattern="/Us""ers/[[:alnum:]_.-]+/"
personal_name_pattern="mini""nimi"
private_key_pattern="BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY"

while IFS= read -r -d '' candidate; do
    mime="$(file -b --mime-type "${candidate}" 2>/dev/null || true)"
    case "${mime}" in
        text/*|application/json|application/xml|application/x-shellscript) ;;
        *) continue ;;
    esac

    if LC_ALL=C grep -En "${private_path_pattern}|${personal_name_pattern}|${private_key_pattern}" "${candidate}" >/dev/null 2>&1; then
        fail "personal path, builder name, or private key marker in ${candidate#${ROOT}/}"
    fi
done < <(find "${ROOT}" -path "${ROOT}/.git" -prune -o -type f -print0)

for forbidden in \
    ORIGINAL_REFERENCE.md \
    Scripts/audit-original-imports.py \
    Scripts/audit-original-module-deltas.py \
    Scripts/audit-original-utils.py \
    Scripts/build-icon-candidates.sh \
    Tests/OriginalImprovedBaselineCheck.sh; do
    if [[ -e "${ROOT}/${forbidden}" ]]; then
        fail "private reference audit file remains: ${forbidden}"
    fi
done

aria_source="${ROOT}/Resources/ThirdParty/aria2-1.37.0.tar.xz"
aria_license="${ROOT}/Resources/ThirdParty/aria2-COPYING.txt"
expected_aria_source="60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b"
spoofdpi_binary="${ROOT}/Resources/Tools/spoofdpi"
spoofdpi_license="${ROOT}/LICENSES/spoofdpi-Apache-2.0.txt"
expected_spoofdpi_binary="abaf22dac1a34c5a5375f6ed17f0f6b9491fbe054706989753e616778ad955c2"

if [[ ! -f "${aria_source}" || ! -f "${aria_license}" ]]; then
    fail "bundled aria2 is missing corresponding source or license text"
elif [[ "$(shasum -a 256 "${aria_source}" | awk '{print $1}')" != "${expected_aria_source}" ]]; then
    fail "bundled aria2 source checksum changed"
fi

if [[ ! -x "${spoofdpi_binary}" || ! -f "${spoofdpi_license}" ]]; then
    fail "bundled SpoofDPI is missing its executable or Apache-2.0 license"
elif [[ "$(shasum -a 256 "${spoofdpi_binary}" | awk '{print $1}')" != "${expected_spoofdpi_binary}" ]]; then
    fail "bundled SpoofDPI executable checksum changed"
fi

for license_file in \
    LICENSES/ratelimit-MIT.txt \
    LICENSES/saidbysolo-MIT.txt \
    LICENSES/spoofdpi-Apache-2.0.txt; do
    [[ -f "${ROOT}/${license_file}" ]] || fail "third-party license is missing: ${license_file}"
done

third_party_notices="${ROOT}/docs/THIRD_PARTY_NOTICES.md"
if [[ ! -f "${third_party_notices}" ]]; then
    fail "third-party notices are missing"
else
    LC_ALL=C grep -Fq 'ratelimit 2.2.1 compatibility code' "${third_party_notices}" || \
        fail "ratelimit attribution is missing from third-party notices"
    LC_ALL=C grep -Fq 'Copyright (c) 2020 SaidBySolo' "${third_party_notices}" || \
        fail "SaidBySolo attribution is missing from third-party notices"
    LC_ALL=C grep -Fq 'SpoofDPI 1.5.3' "${third_party_notices}" || \
        fail "SpoofDPI attribution is missing from third-party notices"
fi

if [[ "${MODE}" == "--public" ]]; then
    project_license="${ROOT}/LICENSE"
    if [[ ! -f "${project_license}" ]]; then
        fail "project LICENSE is missing"
    else
        LC_ALL=C grep -Fxq 'MIT License' "${project_license}" || \
            fail "project LICENSE is not the expected MIT license"
        LC_ALL=C grep -Fxq 'Copyright (c) 2026 NowonWantsThis' "${project_license}" || \
            fail "project LICENSE has the wrong copyright notice"
        LC_ALL=C grep -Fq 'Permission is hereby granted, free of charge' "${project_license}" || \
            fail "project LICENSE is missing the MIT permission grant"
    fi
fi

if (( FAILURES > 0 )); then
    print -u2 -- "Public-tree check found ${FAILURES} problem(s)."
    exit 1
fi

print -- "PASS ${MODE#--} source-tree privacy and provenance checks"
