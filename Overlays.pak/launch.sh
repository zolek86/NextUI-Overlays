#!/bin/sh
# Overlays.pak - browse, preview and install community overlays for NextUI
# Source: https://github.com/LoveRetro/nextui-community-overlays
# Pak conventions: https://github.com/LoveRetro/NextUI/blob/main/PAKS.md

PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"

cd "$PAK_DIR" || exit 1

# Logging
mkdir -p "$LOGS_PATH" 2>/dev/null
LOG_FILE="${LOGS_PATH:-/tmp}/$PAK_NAME.txt"
rm -f "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1
echo "$(date) launch: $0 $*"
set -x

# Architecture (some platforms ship arm + arm64 binaries side-by-side)
ARCH="arm"
if uname -m | grep -q '64'; then
  ARCH="arm64"
fi

# Persistent storage for downloaded helpers / settings
export HOME="${SHARED_USERDATA_PATH:-/tmp}/$PAK_NAME"
mkdir -p "$HOME/bin" "$HOME/cache"

# Add bundled and persisted helper directories to PATH
export PATH="$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin/$ARCH:$PAK_DIR/bin/shared:$HOME/bin:$PATH"

# Working dir for transient artifacts (tree.json, preview images)
WORK_DIR="$(mktemp -d 2>/dev/null || echo "/tmp/${PAK_NAME}.$$")"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_USER="LoveRetro"
REPO_NAME="nextui-community-overlays"
REPO_BRANCH="main"

TREE_API="https://api.github.com/repos/${REPO_USER}/${REPO_NAME}/git/trees/${REPO_BRANCH}?recursive=1"
RAW_BASE="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${REPO_BRANCH}"

MINUI_LIST_RELEASE="https://github.com/josegonzalez/minui-list/releases/latest/download"
MINUI_PRES_RELEASE="https://github.com/josegonzalez/minui-presenter/releases/latest/download"

# Where overlays are installed for libretro cores. NextUI reads
# /Overlays/[CORE]/*.png  (some forks support /Overlays/[res]/[CORE]/*).
OVERLAYS_ROOT="${SDCARD_PATH:-/mnt/SDCARD}/Overlays"

# ---------------------------------------------------------------------------
# Platform/resolution detection
# ---------------------------------------------------------------------------

# Map NextUI's $PLATFORM (and optional $DEVICE) into:
#   - REPO_RES: which resolution folder of the overlays repo to look at
#   - MINUI_BIN_TAG: which prebuilt binary suffix to pull from josegonzalez releases
detect_platform() {
  PLAT="${PLATFORM:-}"
  DEV="${DEVICE:-}"

  case "$PLAT" in
    tg5040)
      # TrimUI Smart Pro = 720p; Brick (DEVICE=brick) = 768p
      if [ "$DEV" = "brick" ]; then
        REPO_RES="768p"
      else
        REPO_RES="720p"
      fi
      MINUI_BIN_TAG="tg5040"
      ;;
    tg3040)
      REPO_RES="768p"
      MINUI_BIN_TAG="tg5040"
      ;;
    tg5050)
      REPO_RES="768p"
      MINUI_BIN_TAG="tg5050"
      ;;
    rg35xxplus)
      case "$DEV" in
        hdmi) REPO_RES="720p" ;;
        *)    REPO_RES="480p" ;;
      esac
      MINUI_BIN_TAG="rg35xxplus"
      ;;
    rg35xx)         REPO_RES="480p"; MINUI_BIN_TAG="rg35xx" ;;
    rgb30)          REPO_RES="480p"; MINUI_BIN_TAG="rgb30" ;;
    my282|miyoomini) REPO_RES="480p"; MINUI_BIN_TAG="${PLAT}" ;;
    my355)          REPO_RES="480p"; MINUI_BIN_TAG="my355" ;;
    magicmini)      REPO_RES="480p"; MINUI_BIN_TAG="magicmini" ;;
    trimui|trimuismart) REPO_RES="480p"; MINUI_BIN_TAG="trimuismart" ;;
    zero28)         REPO_RES="480p"; MINUI_BIN_TAG="zero28" ;;
    m17)            REPO_RES="720p"; MINUI_BIN_TAG="m17" ;;
    *)
      # Unknown platform - default to 720p which has the largest catalog
      REPO_RES="720p"
      MINUI_BIN_TAG="${PLAT:-tg5040}"
      ;;
  esac

  echo "Detected PLATFORM=$PLAT DEVICE=$DEV -> resolution=$REPO_RES bin=$MINUI_BIN_TAG"
}

# ---------------------------------------------------------------------------
# Helper-binary bootstrap (minui-list, minui-presenter)
# ---------------------------------------------------------------------------

ensure_minui_binary() {
  bin_name="$1"      # minui-list or minui-presenter
  release_base="$2"  # release URL prefix

  if command -v "$bin_name" >/dev/null 2>&1; then
    return 0
  fi

  local_target="$HOME/bin/$bin_name"
  if [ -x "$local_target" ]; then
    return 0
  fi

  # Try to download a prebuilt for our platform tag
  url="${release_base}/${bin_name}-${MINUI_BIN_TAG}"
  echo "Fetching $bin_name from $url"
  if curl -fsSL --connect-timeout 10 --max-time 120 -o "$local_target.tmp" "$url"; then
    chmod +x "$local_target.tmp"
    mv "$local_target.tmp" "$local_target"
    return 0
  fi

  rm -f "$local_target.tmp"
  echo "Failed to fetch $bin_name for tag $MINUI_BIN_TAG"
  return 1
}

ensure_helpers() {
  ensure_minui_binary minui-list      "$MINUI_LIST_RELEASE" || HELPERS_OK=0
  ensure_minui_binary minui-presenter "$MINUI_PRES_RELEASE" || HELPERS_OK=0
  HELPERS_OK="${HELPERS_OK:-1}"
  return 0
}

# ---------------------------------------------------------------------------
# UI wrappers
# ---------------------------------------------------------------------------

# Show a list and return the chosen line on stdout. Sets $LIST_RC to exit code.
show_list() {
  title="$1"
  items_file="$2"
  confirm_text="${3:-SELECT}"
  cancel_text="${4:-BACK}"

  out_file="$WORK_DIR/list.out"
  : >"$out_file"

  if [ "$HELPERS_OK" = "1" ] && command -v minui-list >/dev/null 2>&1; then
    minui-list \
      --format text \
      --file "$items_file" \
      --title "$title" \
      --confirm-text "$confirm_text" \
      --cancel-text "$cancel_text" \
      --write-location "$out_file"
    LIST_RC=$?
  else
    # Plain-tty fallback so the script is at least scriptable from SSH
    echo "[$title]"
    nl -ba "$items_file"
    printf "Pick a number (empty = back): "
    read -r pick
    if [ -z "$pick" ]; then
      LIST_RC=2
    else
      sed -n "${pick}p" "$items_file" >"$out_file"
      LIST_RC=0
    fi
  fi
  cat "$out_file"
}

# Show a single message screen. $MSG_RC holds exit code.
show_message() {
  msg="$1"
  timeout="${2:-0}"
  if [ "$HELPERS_OK" = "1" ] && command -v minui-presenter >/dev/null 2>&1; then
    minui-presenter \
      --message "$msg" \
      --message-alignment middle \
      --confirm-button A --confirm-text "OK" --confirm-show \
      --timeout "$timeout"
    MSG_RC=$?
  else
    echo "[message] $msg"
    MSG_RC=0
  fi
  return 0
}

# Fullscreen preview of an image with Install / Back actions.
# Returns 4 if user pressed A (install), 2 if pressed B (back).
show_preview() {
  img_path="$1"
  caption="$2"

  if [ "$HELPERS_OK" = "1" ] && command -v minui-presenter >/dev/null 2>&1; then
    minui-presenter \
      --background-image "$img_path" \
      --message "$caption" \
      --message-alignment bottom \
      --show-pill \
      --action-button A --action-text "INSTALL" --action-show \
      --cancel-button B --cancel-text "BACK"   --cancel-show \
      --timeout 0
    PREV_RC=$?
  else
    echo "[preview] $caption -> $img_path"
    printf "Install? (y/N): "
    read -r ans
    case "$ans" in y|Y) PREV_RC=4 ;; *) PREV_RC=2 ;; esac
  fi
  return 0
}

# ---------------------------------------------------------------------------
# GitHub tree fetch + parsing
# ---------------------------------------------------------------------------

TREE_FILE="$WORK_DIR/tree.json"
PATHS_FILE="$WORK_DIR/paths.txt"

fetch_tree() {
  echo "Fetching repository tree..."
  if ! curl -fsSL --connect-timeout 15 --max-time 60 \
        -H "Accept: application/vnd.github.v3+json" \
        -o "$TREE_FILE" "$TREE_API"; then
    return 1
  fi

  # Extract every blob path. The API returns one object per node, comma-separated.
  # We split on commas and grep "path" + "blob" pairs in order, then keep blobs.
  # Simpler: just grab every path; prune obviously-not-overlay paths later.
  tr ',' '\n' <"$TREE_FILE" \
    | grep -oE '"path": *"[^"]+"' \
    | sed -E 's/"path": *"//; s/"$//' \
    > "$PATHS_FILE"

  # Sanity check
  if [ ! -s "$PATHS_FILE" ]; then
    return 1
  fi
  echo "Tree loaded: $(wc -l <"$PATHS_FILE") entries"
  return 0
}

# Print the unique systems that have at least one overlay PNG for current $REPO_RES
list_systems_for_resolution() {
  res="$1"
  grep -E "^[A-Z][A-Z0-9]+/${res}/[^/]+/.+\.(png|jpg|jpeg)$" "$PATHS_FILE" \
    | awk -F/ '{print $1}' \
    | sort -u
}

# Print path-line + display-line pairs for every overlay image of [system, res]
# Each emitted line in the items file is the human-readable label.
# We also write a parallel "lookup" file with the matching repo path.
list_overlays_for_system() {
  sys="$1"
  res="$2"
  grep -E "^${sys}/${res}/[^/]+/.+\.(png|jpg|jpeg)$" "$PATHS_FILE" \
    | sort
}

# Convert a repo path like "GB/720p/KrutzOtrem/aspect/Aspect - Vanilla.png"
# into a friendly label "KrutzOtrem / aspect / Aspect - Vanilla".
pretty_label_for_path() {
  full="$1"
  # strip CORE/RES/
  rest=$(echo "$full" | sed -E 's#^[^/]+/[^/]+/##')
  # drop extension (case-insensitive without the GNU 'I' flag for busybox compat)
  base=$(echo "$rest" | sed -E 's/\.(png|PNG|jpg|JPG|jpeg|JPEG)$//')
  echo "$base" | sed 's#/# / #g'
}

# ---------------------------------------------------------------------------
# Install routine
# ---------------------------------------------------------------------------

# Build a unique destination filename so different authors don't collide.
# "GB/720p/KrutzOtrem/aspect/Aspect - Vanilla.png" -> "KrutzOtrem_aspect_Aspect - Vanilla.png"
dest_filename_for_path() {
  full="$1"
  echo "$full" | sed -E 's#^[^/]+/[^/]+/##' | sed 's#/#_#g'
}

# Download a single repo file to a local target. $1=repo path, $2=local file.
download_repo_file() {
  src="$1"; dst="$2"
  url="${RAW_BASE}/$(echo "$src" | sed 's# #%20#g')"
  curl -fsSL --connect-timeout 15 --max-time 180 -o "$dst.tmp" "$url" || return 1
  mv "$dst.tmp" "$dst"
  return 0
}

install_overlay() {
  repo_path="$1"  # e.g. GB/720p/KrutzOtrem/aspect/Aspect - Vanilla.png
  system=$(echo "$repo_path" | awk -F/ '{print $1}')
  base=$(basename "$repo_path")
  ext="${base##*.}"
  stem="${base%.*}"

  dest_dir="$OVERLAYS_ROOT/$system"
  mkdir -p "$dest_dir"

  unique_stem=$(dest_filename_for_path "$repo_path" | sed -E 's/\.(png|PNG|jpg|JPG|jpeg|JPEG)$//')
  dest_png="$dest_dir/${unique_stem}.${ext}"

  # Download the image
  if ! download_repo_file "$repo_path" "$dest_png"; then
    return 1
  fi

  # If a sibling .cfg exists, fetch it and rewrite its overlayN_overlay reference
  cfg_repo_path=$(dirname "$repo_path")/"${stem}.cfg"
  if grep -Fxq "$cfg_repo_path" "$PATHS_FILE"; then
    dest_cfg="$dest_dir/${unique_stem}.cfg"
    if download_repo_file "$cfg_repo_path" "$dest_cfg"; then
      # Update the overlayN_overlay = ... line(s) to point at our renamed PNG.
      # Busybox sed lacks portable -i.bak, so rewrite via temp file.
      escaped_basename=$(basename "$dest_png" | sed -e 's/[\/&]/\\&/g')
      sed -E "s|^([[:space:]]*overlay[0-9]+_overlay[[:space:]]*=[[:space:]]*).*$|\1${escaped_basename}|" \
        "$dest_cfg" > "${dest_cfg}.tmp" && mv "${dest_cfg}.tmp" "$dest_cfg"
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Browse loops
# ---------------------------------------------------------------------------

browse_overlays_for_system() {
  sys="$1"
  res="$REPO_RES"

  paths_for_sys="$WORK_DIR/${sys}_paths.txt"
  labels_for_sys="$WORK_DIR/${sys}_labels.txt"
  list_overlays_for_system "$sys" "$res" > "$paths_for_sys"

  if [ ! -s "$paths_for_sys" ]; then
    show_message "No overlays for $sys at $res" 3
    return
  fi

  : > "$labels_for_sys"
  while IFS= read -r p; do
    pretty_label_for_path "$p" >> "$labels_for_sys"
  done <"$paths_for_sys"

  while :; do
    chosen_label=$(show_list "$sys ($res)  -  pick overlay" "$labels_for_sys" "PREVIEW" "BACK")
    rc=$LIST_RC
    [ $rc -ne 0 ] && return

    # Translate label back to the repo path by line index
    idx=$(awk -v sel="$chosen_label" '$0==sel{print NR; exit}' "$labels_for_sys")
    [ -z "$idx" ] && continue
    chosen_path=$(sed -n "${idx}p" "$paths_for_sys")

    preview_file="$WORK_DIR/preview_$(echo "$chosen_path" | tr '/ ' '__').png"
    if ! download_repo_file "$chosen_path" "$preview_file"; then
      show_message "Preview failed (network?)" 3
      continue
    fi

    show_preview "$preview_file" "$chosen_label"
    case $PREV_RC in
      4) # INSTALL
        if install_overlay "$chosen_path"; then
          show_message "Installed to /Overlays/$sys" 2
        else
          show_message "Install failed" 3
        fi
        ;;
      *)
        : # back to overlay list
        ;;
    esac
  done
}

RESOLUTION_SETTING_FILE="$HOME/resolution"

# All resolutions present anywhere in the repo's tree, with a non-empty author folder
available_resolutions() {
  awk -F/ '
    NF >= 4 && $1 ~ /^[A-Z][A-Z0-9]+$/ && $2 ~ /^[0-9]+p$/ {
      tolower_ext = tolower($NF);
      if (match(tolower_ext, /\.(png|jpg|jpeg)$/)) print $2;
    }
  ' "$PATHS_FILE" | sort -u
}

# Pick which resolution to browse: persisted choice -> autodetected -> any available.
choose_resolution() {
  if [ -f "$RESOLUTION_SETTING_FILE" ]; then
    REPO_RES=$(cat "$RESOLUTION_SETTING_FILE")
    return
  fi

  list=$(available_resolutions)
  if [ -z "$list" ]; then
    return  # leave REPO_RES alone; browse_systems will complain
  fi

  if echo "$list" | grep -qx "$REPO_RES"; then
    return  # autodetected works
  fi

  # Autodetected resolution has no overlays. Pick something close.
  fallback=$(echo "$list" | head -n 1)
  echo "Resolution $REPO_RES has no overlays in repo, falling back to $fallback"
  REPO_RES="$fallback"
}

# Show resolution picker (used from the systems menu via X button).
pick_resolution_interactive() {
  res_file="$WORK_DIR/resolutions.txt"
  available_resolutions > "$res_file"
  if [ ! -s "$res_file" ]; then
    show_message "No resolutions available in repo" 3
    return
  fi
  chosen=$(show_list "Choose resolution (current: $REPO_RES)" "$res_file" "USE" "BACK")
  rc=$LIST_RC
  [ $rc -ne 0 ] && return
  [ -z "$chosen" ] && return
  REPO_RES="$chosen"
  echo "$REPO_RES" > "$RESOLUTION_SETTING_FILE"
}

browse_systems() {
  while :; do
    systems_file="$WORK_DIR/systems_${REPO_RES}.txt"
    list_systems_for_resolution "$REPO_RES" > "$systems_file"

    # Always offer a way to change resolution, even if the current one is empty.
    menu_file="$WORK_DIR/menu.txt"
    if [ -s "$systems_file" ]; then
      cat "$systems_file" > "$menu_file"
    else
      : > "$menu_file"
    fi
    echo "[Change resolution: $REPO_RES]" >> "$menu_file"

    chosen=$(show_list "Pick a system  (res: $REPO_RES)" "$menu_file" "OPEN" "QUIT")
    rc=$LIST_RC
    [ $rc -ne 0 ] && return
    [ -z "$chosen" ] && return

    case "$chosen" in
      "[Change resolution:"*)
        pick_resolution_interactive
        ;;
      *)
        browse_overlays_for_system "$chosen"
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  detect_platform
  ensure_helpers

  if ! fetch_tree; then
    show_message "Could not fetch overlay index. Check Wi-Fi." 5
    return 1
  fi

  choose_resolution
  browse_systems
}

main "$@"
