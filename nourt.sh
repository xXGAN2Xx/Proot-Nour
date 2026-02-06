#!/bin/bash

# ==============================================================================
# 🎮 HYTALE SERVER AUTO-DEPLOYMENT SCRIPT (FAST VERSION)
# ==============================================================================
# AUTHOR:  Nour (Optimized)
# PLATFORM: Debian / Ubuntu
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] GLOBAL CONFIGURATION
# ------------------------------------------------------------------------------
PORT="5520"
UPDATE_MODE=false
PIXELDRAIN_IDS=()

# ------------------------------------------------------------------------------
# [2] ARGUMENT PROCESSING
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --p) PORT="$2"; shift 2 ;;
        --u) UPDATE_MODE=true; shift ;;
        *) PIXELDRAIN_IDS+=("$(echo "$1" | tr -d ':,')"); shift ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT (ACCELERATED)         "
echo "======================================================="

# ------------------------------------------------------------------------------
# [3] ENVIRONMENT & DEPENDENCIES (Optimized)
#    Only updates/installs if aria2 or java is missing.
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Root privileges required."
  exit 1
fi

echo " [⚡] Phase 1: Checking system requirements..."

# Check if we need to install anything
NEEDS_INSTALL=false
if ! command -v aria2c &> /dev/null; then NEEDS_INSTALL=true; fi
if ! command -v java &> /dev/null; then NEEDS_INSTALL=true; fi

if [ "$NEEDS_INSTALL" = true ]; then
    echo "     » Installing dependencies (aria2, openjdk)..."
    apt-get update -y -q
    # Removed curl (replaced by aria2), keeping openjdk
    apt-get install -y -q aria2 openjdk-25-jre
else
    echo "     » Dependencies already installed. Skipping apt update."
fi

# ------------------------------------------------------------------------------
# [4] PIXELDRAIN RESOURCE IDENTIFICATION
# ------------------------------------------------------------------------------
if [ ${#PIXELDRAIN_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Two PixelDrain IDs are required."
    exit 1
fi

DETECTED_ASSETS_ID=""
DETECTED_JAR_ID=""

echo " [⚡] Phase 2: Resolving resource metadata..."

for id in "${PIXELDRAIN_IDS[@]}"; do
    FILE_INFO=$(curl -sL -A "Mozilla/5.0" "https://pixeldrain.com/api/file/${id}/info" || true)
    FILE_NAME=$(echo "$FILE_INFO" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || true)
    
    if [ -z "$FILE_NAME" ]; then
        echo " [!] ERROR: ID [$id] is invalid."
        exit 1
    fi

    echo "     » Detected: $FILE_NAME"

    if echo "$FILE_NAME" | grep -iq "Asset"; then
        DETECTED_ASSETS_ID="$id"
    else
        DETECTED_JAR_ID="$id"
    fi
done

if [ -z "$DETECTED_ASSETS_ID" ] || [ -z "$DETECTED_JAR_ID" ]; then
    echo " [!] ERROR: Could not distinguish Assets from Jar."
    exit 1
fi

# ------------------------------------------------------------------------------
# [5] REINSTALLATION LOGIC
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Phase 3: Update flag detected. Purging local binaries..."
    rm -f Assets.zip HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [6] PARALLEL DATA ACQUISITION (ARIA2)
#    Uses aria2c with 16 connections per file, running both downloads at once.
# ------------------------------------------------------------------------------
echo " [⚡] Phase 4: Downloading files in parallel..."

# Function to download Assets
download_assets() {
    if [ ! -f "Assets.zip" ]; then
        echo "     » Starting download: Assets.zip"
        # -x 16: 16 connections, -s 16: 16 splits, -j 1: concurrent downloads (controlled by bash)
        aria2c -x 16 -s 16 -j 1 -o "Assets.zip" "https://pixeldrain.com/api/file/${DETECTED_ASSETS_ID}" -q --console-log-level=error
        echo "     ✓ Assets.zip download complete."
    else
        echo "     ✓ Assets.zip already exists."
    fi
}

# Function to download Jar
download_jar() {
    if [ ! -f "HytaleServer.jar" ]; then
        echo "     » Starting download: HytaleServer.jar"
        aria2c -x 16 -s 16 -j 1 -o "HytaleServer.jar" "https://pixeldrain.com/api/file/${DETECTED_JAR_ID}" -q --console-log-level=error
        chmod +x HytaleServer.jar
        echo "     ✓ HytaleServer.jar download complete."
    else
        echo "     ✓ HytaleServer.jar already exists."
    fi
}

# Run both functions in background simultaneously
download_assets &
PID_ASSETS=$!

download_jar &
PID_JAR=$!

# Wait for both downloads to finish before proceeding
wait $PID_ASSETS
wait $PID_JAR

# ------------------------------------------------------------------------------
# [7] SERVER STARTUP
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT COMPLETE - STARTING HYTALE          "
echo "-------------------------------------------------------"
echo " [>] Network Bind: 0.0.0.0:$PORT"

java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
