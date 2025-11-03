#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
NAME="${2:-}"
PATCH_SRC="${3:-}"

REPO_DIR="$(pwd)"

echo "===== [ Args ] ====="
echo "VERSION (commit): ${VERSION:-<default>}"
echo "NAME: ${NAME:-<none>}"
echo "PATCH: ${PATCH_SRC:-<none>}"

sudo apt-get install -y \
    pkg-config \
    git \
    subversion \
    curl \
    wget \
    build-essential \
    python3 \
    xz-utils \
    zip

git config --global user.name "V8 Linux Builder"
git config --global user.email "v8.linux.builder@localhost"
git config --global core.autocrlf false
git config --global core.filemode false
git config --global color.ui true


cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH=$(pwd)/depot_tools:$PATH
gclient


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['linux']" >> .gclient
cd ~/v8/v8
echo "[*] install deps"
./build/install-build-deps.sh
if [[ -n "${VERSION}" ]]; then
    echo "[*] checkout ${VERSION}"
    git checkout "${VERSION}"
else
    echo "[*] checkout latest from origin (main/master)"
    git fetch --all --tags --prune
    if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
        git checkout -B main origin/main
    elif git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
        git checkout -B master origin/master
    else
        echo "Could not find origin/main or origin/master; staying on current branch"
    fi
fi

if [[ -n "${PATCH_SRC}" ]]; then
    echo "=====[ Applying Patch ]====="
    PATCH_FILE=""
    if [[ "${PATCH_SRC}" == http://* || "${PATCH_SRC}" == https://* ]]; then
        echo "Downloading patch from URL: ${PATCH_SRC}"
        curl -fsSL "${PATCH_SRC}" -o /tmp/v8.patch
        PATCH_FILE="/tmp/v8.patch"
    elif [[ -f "${REPO_DIR}/${PATCH_SRC}" ]]; then
        PATCH_FILE="${REPO_DIR}/${PATCH_SRC}"
    elif [[ -f "${PATCH_SRC}" ]]; then
        PATCH_FILE="${PATCH_SRC}"
    elif [[ -f "${REPO_DIR}/patch.diff" && "${PATCH_SRC}" == "patch.diff" ]]; then
        PATCH_FILE="${REPO_DIR}/patch.diff"
    fi

    if [[ -n "${PATCH_FILE}" && -s "${PATCH_FILE}" ]]; then
        echo "Applying patch file: ${PATCH_FILE}"
        # Try git apply first; fall back to patch if needed
        if ! git apply --index --reject --whitespace=fix "${PATCH_FILE}"; then
            echo "git apply failed, trying 'patch' utility"
            patch -p1 -t -N < "${PATCH_FILE}" || { echo "Patch failed"; exit 1; }
        fi
        echo "Patch applied successfully."
    else
        echo "Patch specified but not found: ${PATCH_SRC} (looked for ${PATCH_FILE:-<none>})"
    fi
else
    echo "No patch specified; skipping patch step."
fi

gclient sync


echo "=====[ Building V8 ]====="
python3 ./tools/dev/v8gen.py x64.release -vv -- '
symbol_level=0
blink_symbol_level=0
is_debug = true
enable_nacl = false
dcheck_always_on = false
v8_enable_sandbox = true
'
ninja -C out.gn/x64.release -t clean
ninja -j8 -C out.gn/x64.release d8
