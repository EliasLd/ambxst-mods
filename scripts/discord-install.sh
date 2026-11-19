#!/bin/sh
# Installs the AmbxstDiscord companion Vencord build for Vesktop.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/EliasLd/ambxst-mods/main/scripts/discord-install.sh | sh
#
# Flags:
#   --latest     skip the pinned Vencord ref, install the rolling build
#   --uninstall  remove the vencordDir override and the files
#   --dir <path> override the data directory
#   --build      build the plugin locally first (needs git, node, pnpm)
#
# The script downloads only this repo's release assets, verifies SHA256SUMS,
# writes the four Vencord files into the data dir and a single "vencordDir"
# key into Vesktop's state.json (python3 when present). It never kills or
# writes into other apps, and never touches anything beyond those two
# locations.

set -eu

REPO="EliasLd/ambxst-mods"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
DL_BASE="https://github.com/$REPO/releases/download"

REF_FILE_PATH="packages/discord-voice/vesktop-plugin/VENCORD_REF"
ZIP_ASSET="discord-vencord-files.zip"
SUMS_ASSET="SHA256SUMS"
ROLLING_TAG="discord-latest"

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
DEFAULT_DATA_DIR="$XDG_DATA_HOME/ambxst-discord"

LATEST=false
UNINSTALL=false
BUILD=false
DATA_DIR=""

usage() {
    echo "usage: sh discord-install.sh [--latest] [--uninstall] [--dir <path>] [--build]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --latest) LATEST=true; shift ;;
        --uninstall) UNINSTALL=true; shift ;;
        --build) BUILD=true; shift ;;
        --dir)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            DATA_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

DATA_DIR=${DATA_DIR:-$DEFAULT_DATA_DIR}
VENCORD_DIR="$DATA_DIR/vencord"

# --- requirements ------------------------------------------------------------

requirements_ok() {
    missing=""
    for tool in curl sha256sum unzip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing="$missing $tool"
        fi
    done
    if [ -n "$missing" ]; then
        echo "missing requirement(s):$missing" >&2
        echo "install them with your package manager and re-run this script" >&2
        return 1
    fi
}
requirements_ok || exit 1

# --- refuse to run while Vesktop is up ----------------------------------------
#
# Vesktop keeps state.json loaded in memory and rewrites the whole file on
# exit, so a change written while it runs is silently undone the moment it
# quits. Installing (or uninstalling) therefore has to happen while Vesktop
# is closed.

# pgrep scans command lines, so it also matches processes that merely carry
# the word: this script's own launcher chain, or a grep inside a compound
# command. Filter those scanner lines; real Vesktop argv never contains any
# of them.
if pgrep -af "[Vv]esktop" 2>/dev/null | grep -Ev "discord-install|grep|pgrep" >/dev/null 2>&1; then
    echo "Vesktop is currently running, and it must be closed for this step:"
    echo "Vesktop rewrites its state.json from memory on exit, which would"
    echo "undo the vencordDir change this script makes."
    echo ""
    echo "Close Vesktop completely and re-run the exact same command."
    exit 1
fi

# --- locate Vesktop's config dir ----------------------------------------------

# Native installs keep state.json in the config dir (lowercase on Linux).
find_state_dir() {
    config_base=${XDG_CONFIG_HOME:-$HOME/.config}
    if [ -d "$config_base/vesktop" ]; then
        printf '%s\n' "$config_base/vesktop"
        return 0
    fi
    if [ -d "$config_base/Vesktop" ]; then
        printf '%s\n' "$config_base/Vesktop"
        return 0
    fi
    return 1
}

STATE_DIR=""
STATE_DIR=$(find_state_dir) || true

if [ -z "$STATE_DIR" ]; then
    if [ -d "$HOME/.var/app/dev.vencord.Vesktop" ]; then
        echo "Flatpak Vesktop is not supported: its state.json lives inside the sandbox." >&2
    else
        echo "no native Vesktop config dir found (looked under ~/.config/vesktop)" >&2
        echo "install Vesktop first: https://vesktop.dev/install" >&2
    fi
    exit 1
fi

STATE_FILE="$STATE_DIR/state.json"

# --- state.json edit ----------------------------------------------------------
#
# state.json holds other Vesktop state, so the edit merges one key with
# python3 (parse, set, atomic replace). Without python3 the files are still
# installed and the exact manual edit is printed instead - the script never
# edits JSON with sed.

state_add() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$STATE_FILE" "$1" <<'PYEOF'
import json, os, sys, tempfile

path, vencord_dir = sys.argv[1], sys.argv[2]
content = ""
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
data = json.loads(content) if content.strip() else {}
data["vencordDir"] = vencord_dir
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
print("state.json: vencordDir ->", vencord_dir)
PYEOF
    else
        echo ""
        echo "NOTE: python3 is missing, so state.json was not edited. Add this key"
        echo "to $STATE_FILE with a text editor (top-level, mind the commas):"
        echo "    \"vencordDir\": \"$1\""
        echo ""
    fi
}

state_remove() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$STATE_FILE" <<'PYEOF'
import json, os, sys, tempfile

path = sys.argv[1]
content = ""
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
data = json.loads(content) if content.strip() else {}
if "vencordDir" in data:
    del data["vencordDir"]
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    os.replace(tmp, path)
    print("state.json: removed vencordDir")
else:
    print("state.json: no vencordDir key, nothing to remove")
PYEOF
    else
        echo "NOTE: python3 is missing; remove the \"vencordDir\" key from"
        echo "$STATE_FILE with a text editor."
    fi
}

# --- uninstall ----------------------------------------------------------------

if [ "$UNINSTALL" = true ]; then
    state_remove
    if [ -d "$DATA_DIR" ]; then
        rm -rf "$DATA_DIR"
        echo "removed $DATA_DIR"
    else
        echo "no data directory at $DATA_DIR, nothing to remove"
    fi
    echo ""
    echo "Done. The next Vesktop start re-downloads its official Vencord build."
    exit 0
fi

# --- local build mode ---------------------------------------------------------

if [ "$BUILD" = true ]; then
    for tool in git node pnpm; do
        command -v "$tool" >/dev/null 2>&1 || { echo "--build needs $tool" >&2; exit 1; }
    done
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    sh "$SCRIPT_DIR/discord-plugin-build.sh"
    BUILD_DIST="${TMPDIR:-/tmp}/ambxst-discord-vencord/dist"
fi

# --- place the files ----------------------------------------------------------

if [ "$BUILD" = true ]; then
    echo "Using the local build: $BUILD_DIST"
    mkdir -p "$VENCORD_DIR"
    for f in vencordDesktopMain.js vencordDesktopPreload.js vencordDesktopRenderer.js vencordDesktopRenderer.css; do
        cp "$BUILD_DIST/$f" "$VENCORD_DIR/$f"
    done
else
    TAG="$ROLLING_TAG"
    if [ "$LATEST" = false ]; then
        # The pin lives in the repo; a missing pin keeps the rolling tag.
        PIN=""
        RAW=""
        if RAW=$(curl -fsSL "$RAW_BASE/$REF_FILE_PATH"); then
            PIN=$(printf '%s' "$RAW" | tr -d '[:space:]')
        else
            echo "NOTE: could not read the pinned Vencord ref from the repo ($RAW_BASE/$REF_FILE_PATH)."
            echo "Falling back to the rolling release $ROLLING_TAG."
            PIN=""
        fi
        [ -n "$PIN" ] && TAG="discord-vencord-$PIN"
    fi

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ambxst-discord-install.XXXXXX")
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "Resolving build: $TAG"
    if ! curl -fsSL -o "$TMP_DIR/$ZIP_ASSET" "$DL_BASE/$TAG/$ZIP_ASSET"; then
        if [ "$TAG" != "$ROLLING_TAG" ]; then
            echo ""
            echo "NOTE: release $TAG does not exist yet (CI has not published it)."
            echo "Falling back to the rolling release $ROLLING_TAG."
            TAG="$ROLLING_TAG"
            curl -fsSL -o "$TMP_DIR/$ZIP_ASSET" "$DL_BASE/$TAG/$ZIP_ASSET"
        fi
    fi

    curl -fsSL -o "$TMP_DIR/$SUMS_ASSET" "$DL_BASE/$TAG/$SUMS_ASSET"
    (cd "$TMP_DIR" && sha256sum -c "$SUMS_ASSET")
    echo "Checksums verified."

    mkdir -p "$VENCORD_DIR"
    unzip -oq "$TMP_DIR/$ZIP_ASSET" -d "$VENCORD_DIR"
fi

printf '%s\n' '{}' > "$VENCORD_DIR/package.json"

for f in vencordDesktopMain.js vencordDesktopPreload.js vencordDesktopRenderer.js vencordDesktopRenderer.css; do
    [ -f "$VENCORD_DIR/$f" ] || { echo "install incomplete: $f missing in $VENCORD_DIR" >&2; exit 1; }
done

state_add "$VENCORD_DIR"

# --- summary ------------------------------------------------------------------

echo ""
echo "All set. Three steps:"
echo "  1. Relaunch Vesktop."
echo "  2. In Vesktop: Settings -> Plugins -> enable AmbxstDiscord."
echo "  3. Restart Ambxst, then open the dashboard (or bind: \$mainMod+V -> ambxst run discord)."
