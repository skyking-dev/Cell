#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: .release/validate_package.sh <path-to-extracted-addon>

Validates whether an extracted Cell package looks like a real installable addon
package or a source archive from GitHub.
EOF
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 2
fi

input_path="$1"

if [[ ! -d "$input_path" ]]; then
    echo "ERROR: path does not exist or is not a directory: $input_path" >&2
    exit 2
fi

addon_root="$input_path"

# GitHub source archives often unpack into a parent folder that contains the
# actual addon root as a nested "Cell" directory.
if [[ -d "$input_path/Cell" && -f "$input_path/Cell/Cell.toc" ]]; then
    addon_root="$input_path/Cell"
fi

if [[ ! -f "$addon_root/Cell.toc" ]]; then
    echo "ERROR: could not find Cell.toc under: $addon_root" >&2
    exit 2
fi

required_lib_paths=(
    "Libs/LibStub/LibStub.lua"
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.xml"
    "Libs/AceComm-3.0/AceComm-3.0.xml"
    "Libs/LibSerialize/lib.xml"
    "Libs/LibCustomGlow-1.0/LibCustomGlow-1.0.xml"
    "Libs/LibSharedMedia-3.0/lib.xml"
    "Libs/LibDeflate/lib.xml"
)

source_markers=(
    ".gitignore"
    ".gitattributes"
    ".pkgmeta"
    ".github"
    ".release"
)

missing=()
markers_found=()

for path in "${required_lib_paths[@]}"; do
    if [[ ! -e "$addon_root/$path" ]]; then
        missing+=("$path")
    fi
done

for path in "${source_markers[@]}"; do
    if [[ -e "$addon_root/$path" ]]; then
        markers_found+=("$path")
    fi
done

echo "Inspecting package root: $addon_root"
echo

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "Required embedded libraries: OK"
else
    echo "Required embedded libraries: MISSING"
    for path in "${missing[@]}"; do
        echo "  - $path"
    done
fi

echo

if [[ ${#markers_found[@]} -eq 0 ]]; then
    echo "Source archive markers: none detected"
else
    echo "Source archive markers detected:"
    for path in "${markers_found[@]}"; do
        echo "  - $path"
    done
fi

echo

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "RESULT: INVALID INSTALL PACKAGE"
    echo "This looks like a source archive or an incomplete release."
    echo "Install the packaged release asset instead of GitHub 'Source code'."
    exit 1
fi

if [[ ${#markers_found[@]} -gt 0 ]]; then
    echo "RESULT: SUSPICIOUS PACKAGE"
    echo "Libraries are present, but repository-only files were included."
    echo "Double-check which asset was uploaded or downloaded."
    exit 1
fi

echo "RESULT: PACKAGE LOOKS INSTALLABLE"
