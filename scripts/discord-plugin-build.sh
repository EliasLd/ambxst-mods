#!/bin/sh
# Builds the AmbxstDiscord companion Vencord bundle.
#
# Clones Vencord at the ref pinned in packages/discord-voice/vesktop-plugin/
# VENCORD_REF, injects the plugin sources as src/userplugins/ambxst-discord,
# and runs the Vencord build. The four artifacts Vesktop loads land in
# <build-dir>/dist/.
#
# Used by CI (.github/workflows/discord-build.yml) and by `discord-install.sh
# --build`. Requires: git, pnpm, node. Never a default path of the installer.

set -eu

REF_FILE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/packages/discord-voice/vesktop-plugin/VENCORD_REF"

VENCORD_REF=""
BUILD_DIR=""
OUT_DIR=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ref)
            [ $# -ge 2 ] || { echo "--ref needs an argument" >&2; exit 2; }
            VENCORD_REF="$2"; shift 2 ;;
        --dir)
            [ $# -ge 2 ] || { echo "--dir needs an argument" >&2; exit 2; }
            BUILD_DIR="$2"; shift 2 ;;
        --out)
            [ $# -ge 2 ] || { echo "--out needs an argument" >&2; exit 2; }
            OUT_DIR="$2"; shift 2 ;;
        *)
            echo "usage: $0 [--ref <vencord ref>] [--dir <build dir>] [--out <artifact dir>]" >&2
            exit 2 ;;
    esac
done

[ -f "$REF_FILE" ] || { echo "missing $REF_FILE" >&2; exit 1; }
READ_REF=$(cat "$REF_FILE")
VENCORD_REF=${VENCORD_REF:-$READ_REF}

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v pnpm >/dev/null || { echo "pnpm is required" >&2; exit 1; }
command -v node >/dev/null || { echo "node is required" >&2; exit 1; }

BUILD_DIR=${BUILD_DIR:-"${TMPDIR:-/tmp}/ambxst-discord-vencord"}
SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/packages/discord-voice/vesktop-plugin"

# A previous interrupted build has a detached checkout; remove it fresh.
rm -rf "$BUILD_DIR"

git clone --depth 1 --branch "$VENCORD_REF" https://github.com/Vencord/Vencord "$BUILD_DIR"

rm -rf "$BUILD_DIR/src/userplugins/ambxst-discord"
mkdir -p "$BUILD_DIR/src/userplugins/ambxst-discord"
cp "$SRC_DIR"/index.tsx "$SRC_DIR"/native.ts "$BUILD_DIR/src/userplugins/ambxst-discord/"

cd "$BUILD_DIR"
pnpm install --frozen-lockfile
pnpm build

for f in \
    vencordDesktopMain.js \
    vencordDesktopPreload.js \
    vencordDesktopRenderer.js \
    vencordDesktopRenderer.css
do
    [ -f "dist/$f" ] || { echo "build did not produce dist/$f" >&2; exit 1; }
done

if [ -n "$OUT_DIR" ]; then
    mkdir -p "$OUT_DIR"
    for f in \
        vencordDesktopMain.js \
        vencordDesktopPreload.js \
        vencordDesktopRenderer.js \
        vencordDesktopRenderer.css
    do
        cp "dist/$f" "$OUT_DIR/$f"
    done
fi

echo "Build complete: $BUILD_DIR/dist"
