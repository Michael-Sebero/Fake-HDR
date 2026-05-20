#!/bin/bash

# =============================================================================
# HDR METADATA SETTINGS - Edit these to customize your HDR output
# =============================================================================
MAX_CONTENT_BOOST=6.25    # Max brightness multiplier on HDR displays (e.g. 6.25 = 625% peak)
MIN_CONTENT_BOOST=1.0     # Min brightness multiplier (1.0 = no boost floor)
GAMMA=1.0                 # Gainmap gamma curve (1.0 = linear)
OFFSET_SDR=0.015625       # SDR noise floor offset (1/64, prevents divide-by-zero)
OFFSET_HDR=0.015625       # HDR noise floor offset (1/64, prevents divide-by-zero)
HDR_CAPACITY_MIN=1.0      # Minimum HDR headroom (1.0 = no headroom at minimum)
HDR_CAPACITY_MAX=6.25     # Maximum HDR headroom (should match maxContentBoost)
USE_BASE_COLOR_SPACE=1    # 1 = gainmap in SDR color space, 0 = HDR color space
# =============================================================================

# Exit if no argument provided
if [ -z "$1" ]; then
    echo "Usage: $0 <image_or_directory>"
    exit 0
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Detect package manager
if command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
elif command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
else
    PKG_MANAGER="unknown"
fi

check_dep() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' is required but is not installed."
        case "$PKG_MANAGER" in
            pacman) echo "Run: sudo pacman -S base-devel cmake git libjpeg-turbo" ;;
            apt)    echo "Run: sudo apt install build-essential cmake git libjpeg-dev" ;;
            dnf)    echo "Run: sudo dnf install gcc gcc-c++ cmake git libjpeg-turbo-devel" ;;
            *)      echo "Please install '$cmd' using your package manager." ;;
        esac
        exit 1
    fi
}

check_libjpeg() {
    case "$PKG_MANAGER" in
        pacman)
            if ! pacman -Q libjpeg-turbo &> /dev/null; then
                echo "Error: 'libjpeg-turbo' is required but is not installed."
                echo "Run: sudo pacman -S libjpeg-turbo"
                exit 1
            fi
            ;;
        apt)
            if ! dpkg -s libjpeg-dev &> /dev/null 2>&1; then
                echo "Error: 'libjpeg-dev' is required but is not installed."
                echo "Run: sudo apt install libjpeg-dev"
                exit 1
            fi
            ;;
        dnf)
            if ! rpm -q libjpeg-turbo-devel &> /dev/null 2>&1; then
                echo "Error: 'libjpeg-turbo-devel' is required but is not installed."
                echo "Run: sudo dnf install libjpeg-turbo-devel"
                exit 1
            fi
            ;;
    esac
}

# Check for ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed or not in PATH."
    case "$PKG_MANAGER" in
        pacman) echo "Run: sudo pacman -S ffmpeg" ;;
        apt)    echo "Run: sudo apt install ffmpeg" ;;
        dnf)    echo "Run: sudo dnf install ffmpeg" ;;
    esac
    exit 1
fi

# Build ultrahdr_app if not found
if [ ! -f "$SCRIPT_DIR/ultrahdr_app" ]; then
    echo "ultrahdr_app not found. Building from source..."

    check_dep cmake
    check_dep make
    check_dep git
    check_libjpeg

    BUILD_TMP="$(mktemp -d)"
    echo "Cloning libultrahdr into $BUILD_TMP..."
    git clone --depth=1 https://github.com/google/libultrahdr.git "$BUILD_TMP/libultrahdr"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone libultrahdr. Check your internet connection."
        rm -rf "$BUILD_TMP"
        exit 1
    fi

    echo "Building... (this may take a minute)"
    cmake -S "$BUILD_TMP/libultrahdr" -B "$BUILD_TMP/build" -DUHDR_BUILD_APPS=ON -DCMAKE_BUILD_TYPE=Release > /dev/null
    make -C "$BUILD_TMP/build" -j$(nproc)

    if [ $? -ne 0 ]; then
        echo "Error: Build failed."
        rm -rf "$BUILD_TMP"
        exit 1
    fi

    cp "$BUILD_TMP/build/ultrahdr_app" "$SCRIPT_DIR/ultrahdr_app"
    chmod +x "$SCRIPT_DIR/ultrahdr_app"
    rm -rf "$BUILD_TMP"
    echo "ultrahdr_app built and saved to $SCRIPT_DIR"
    echo ""
fi

# Write metadata.cfg from the settings at the top of this script
cat > "$SCRIPT_DIR/metadata.cfg" << EOF
--maxContentBoost $MAX_CONTENT_BOOST
--minContentBoost $MIN_CONTENT_BOOST
--gamma $GAMMA
--offsetSdr $OFFSET_SDR
--offsetHdr $OFFSET_HDR
--hdrCapacityMin $HDR_CAPACITY_MIN
--hdrCapacityMax $HDR_CAPACITY_MAX
--useBaseColorSpace $USE_BASE_COLOR_SPACE
EOF

process_image() {
    local input_image="$1"
    local output_dir="$2"
    local filename="$(basename "$input_image")"
    local name="${filename%.*}"
    local ext="${filename##*.}"
    ext="${ext,,}"  # lowercase

    local sdr_tmp="/tmp/sdr_${name}.jpg"
    local hdr_tmp="/tmp/hdr_${name}.jpg"

    echo "Processing: $filename"

    # If not a jpg/jpeg, convert first
    if [[ "$ext" != "jpg" && "$ext" != "jpeg" ]]; then
        ffmpeg -y -i "$input_image" -vf "[0:v]split=2[bg][fg];[bg]drawbox=c=black:t=fill[bg];[bg][fg]overlay=format=auto" -q:v 1 -qmin 1 "$sdr_tmp" -loglevel error
        if [ $? -ne 0 ]; then
            echo "  Skipped: failed to convert $filename (corrupt or unsupported file)"
            rm -f "$sdr_tmp"
            return
        fi
        input_image="$sdr_tmp"
    fi

    # Generate gainmap
    ffmpeg -y -i "$input_image" -vf "gradfun=strength=5:radius=8, curves=all='0/0 0.50/0.95 1/1', format=gray" -q:v 1 -qmin 1 -pix_fmt rgb48le "$hdr_tmp" -loglevel error
    if [ $? -ne 0 ]; then
        echo "  Skipped: failed to generate gainmap for $filename"
        rm -f "$sdr_tmp" "$hdr_tmp"
        return
    fi

    # Assemble Ultra HDR JPEG
    "$SCRIPT_DIR/ultrahdr_app" -m 0 -i "$input_image" -g "$hdr_tmp" -f "$SCRIPT_DIR/metadata.cfg" -M 1 -s 1 -q 100 -Q 100 -D 1 -z "$output_dir/${name}_hdr.jpg"

    # Clean up temp files
    rm -f "$sdr_tmp" "$hdr_tmp"
}

# --- Directory mode ---
if [ -d "$1" ]; then
    input_dir="$(realpath "$1")"
    output_dir="$input_dir/HDR"
    mkdir -p "$output_dir"
    echo "Output directory: $output_dir"
    echo ""

    found=0
    for img in "$input_dir"/*.{jpg,jpeg,png,webp,tiff,tif,bmp}; do
        [ -f "$img" ] || continue
        process_image "$img" "$output_dir"
        found=1
    done

    if [ "$found" -eq 0 ]; then
        echo "No supported images found in: $input_dir"
    else
        echo ""
        echo "Done. HDR images saved to: $output_dir"
    fi

# --- Single file mode ---
elif [ -f "$1" ]; then
    output_dir="$(dirname "$(realpath "$1")")"
    process_image "$(realpath "$1")" "$output_dir"
    echo "Done."

else
    echo "Error: '$1' is not a valid file or directory."
    exit 1
fi
