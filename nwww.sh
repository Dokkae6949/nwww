#!/usr/bin/env bash
set -euo pipefail

# Defaults
VERBOSE=0
BLUR=20
DARKEN=0
IMAGE=""
SCALE=1
CLEAR_CACHE=0

show_help() {
    cat <<EOF
nwww - niri-swww wallpaper manager

Usage:
  nwww [options] /path/to/wallpaper.png

Description:
  Sets wallpaper for two swww namespaces:
    - default   → original image (shown instantly)
    - overview  → blurred and optionally darkened copy

Options:
  -h, --help            Show this help and exit
  -v, --verbose         Enable logging (silent by default)
  -b, --blur <radius>   Blur radius (default: 20)
  -d, --darken <pct>    Darken blurred image by percentage (0-100, default: 0)
  -s, --scale <factor>  Downscale factor for overview (0 < factor <= 1, default: 1)
  --clear-cache         Clears all cached images
EOF
}

log() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$@"
    fi
}

# ------------------------------
# Parse arguments
# ------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -b|--blur) BLUR="$2"; shift 2 ;;
        -d|--darken) DARKEN="$2"; shift 2 ;;
        -s|--scale) SCALE="$2"; shift 2 ;;
        --clear-cache) CLEAR_CACHE=1; shift ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) IMAGE="$1"; shift ;;
    esac
done

if [ -z "$IMAGE" ]; then
    echo "Error: missing wallpaper path" >&2
    exit 1
fi

# Validate SCALE
awk "BEGIN{exit !($SCALE > 0 && $SCALE <= 1)}" || { echo "Scale must be between 0 and 1"; exit 1; }

# ------------------------------
# Setup cache
# ------------------------------
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nwww"
mkdir -p "$CACHE_DIR"

if [ "$CLEAR_CACHE" -eq 1 ]; then
    log "Clearing image cache at $CACHE_DIR"
    find "$CACHE_DIR" -maxdepth 1 -type f -exec rm -f {} +
fi

EXT="${IMAGE##*.}"
BASENAME="$(basename "$IMAGE" ."$EXT")"
SCALED="$CACHE_DIR/${BASENAME}_scaled_${SCALE}.$EXT"
BLURRED="$CACHE_DIR/${BASENAME}_blurred_${BLUR}.$EXT"
DARKENED="$CACHE_DIR/${BASENAME}_darkened_${DARKEN}.$EXT"
OVERVIEW="$CACHE_DIR/${BASENAME}_overview_b${BLUR}_d${DARKEN}_s${SCALE}.$EXT"

# ------------------------------
# Ensure swww daemons
# ------------------------------
for ns in default overview; do
    if ! swww query --namespace "$ns" >/dev/null 2>&1; then
        log "Starting swww-daemon for namespace: $ns"
        swww-daemon --namespace "$ns" &
        until swww query --namespace "$ns" >/dev/null 2>&1; do
            sleep 0.05
        done
    fi
done

# ------------------------------
# Set default wallpaper instantly
# ------------------------------
log "Setting default wallpaper to $IMAGE"
swww img "$IMAGE" --namespace default --transition-duration 1 --transition-fps 165 --transition-step 16 -t wave

# ------------------------------
# Generate overview wallpaper synchronously
# ------------------------------
if [ -f "$OVERVIEW" ]; then
    log "Using cached overview wallpaper: $OVERVIEW"
else
    log "Creating overview wallpaper (vips)..."

    SCALED="$CACHE_DIR/${BASENAME}_scaled_${SCALE}.$EXT"
    BLURRED="$CACHE_DIR/${BASENAME}_blurred_${BLUR}.$EXT"
    DARKENED="$CACHE_DIR/${BASENAME}_darkened_${DARKEN}.$EXT"

    # Downscale
    vips scale "$IMAGE" "$SCALED" --exp "$SCALE"

    # Gaussian blur → BLURRED
    vips gaussblur "$SCALED" "$BLURRED" "$BLUR"

    # Darken (optional) → DARKENED
    if [ "$DARKEN" -gt 0 ]; then
        FACTOR=$(awk "BEGIN{print (100-$DARKEN)/100}")
        vips linear "$BLURRED" "$DARKENED" "$FACTOR" 0
        cp "$DARKENED" "$OVERVIEW"
    else
        cp "$BLURRED" "$OVERVIEW"
    fi

    # Cleanup intermediate files safely
    rm -f "$SCALED" "$DARKENED" "$BLURRED"
fi

# Set overview wallpaper
log "Setting overview wallpaper to $OVERVIEW"
swww img "$OVERVIEW" --namespace overview --transition-duration 2 -t center --transition-fps 165 --transition-step 16
