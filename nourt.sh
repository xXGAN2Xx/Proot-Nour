#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER
#  ----------------------------------------------------------------------------
#  Usage:       sudo ./deploy.sh [GoFile_IDs/URLs] --p [PORT] --u
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] INITIAL CONFIGURATION & DEFAULTS
# ------------------------------------------------------------------------------
SERVER_PORT="${SERVER_PORT:-5520}"
UPDATE_MODE=false
INPUT_IDs=()
BYPASS_BASE="https://gf.1drv.eu.org"

# ------------------------------------------------------------------------------
# [2] ARGUMENT PARSING
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --p) SERVER_PORT="$2"; shift 2 ;;
        --u) UPDATE_MODE=true; shift ;;
        *)
            CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,')
            INPUT_IDs+=("$CLEAN_ID")
            shift
            ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="

# ------------------------------------------------------------------------------
# [3] ENVIRONMENT PREVALIDATION
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges (sudo)."
  exit 1
fi

echo " [⚡] Phase 1: Validating System Dependencies..."
apt-get update -y > /dev/null 2>&1
# jq is required for the config check logic below
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [4] SMART FILE IDENTIFICATION
# ------------------------------------------------------------------------------
echo " [⚡] Phase 2: Identifying files..."
ASSET_ID=""
JAR_ID=""

for id in "${INPUT_IDs[@]}"; do
    HEADERS=$(curl -sIL "${BYPASS_BASE}/$id")
    FNAME=$(echo "$HEADERS" | grep -i "content-disposition" | grep -o 'filename="[^"]*"' | cut -d'"' -f2 || true)
    if [ -n "$FNAME" ]; then
        if echo "$FNAME" | grep -iq "Asset"; then ASSET_ID="$id"
        elif echo "$FNAME" | grep -iq "Hytale" || echo "$FNAME" | grep -iq ".jar"; then JAR_ID="$id"; fi
    fi
done

if [ -z "$ASSET_ID" ] || [ -z "$JAR_ID" ]; then
    ASSET_ID="${INPUT_IDs[0]}"
    JAR_ID="${INPUT_IDs[1]}"
fi

# ------------------------------------------------------------------------------
# [5] CLEANUP / UPDATE LOGIC
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Update flag detected. Clearing old binaries..."
    rm -f Assets.zip HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [6] HIGH-SPEED DOWNLOADS
# ------------------------------------------------------------------------------
echo " [⚡] Phase 3: Fetching Resources..."

if [ ! -f "Assets.zip" ]; then
    aria2c -x 8 -s 8 --summary-interval=0 -o Assets.zip "${BYPASS_BASE}/${ASSET_ID}"
fi

if [ ! -f "HytaleServer.jar" ]; then
    aria2c -x 8 -s 8 --summary-interval=0 -o HytaleServer.jar "${BYPASS_BASE}/${JAR_ID}"
    chmod +x HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [7] CONFIGURATION ENFORCEMENT (Runs every time)
# ------------------------------------------------------------------------------
echo " [⚡] Phase 4: Checking Configuration..."

CONFIG_FILE="config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    # Create file if it doesn't exist
    echo '{"MaxViewRadius": 16}' > "$CONFIG_FILE"
    echo "     » config.json created with MaxViewRadius: 16"
else
    # Check current value using jq
    # If the key doesn't exist or isn't 16, update it
    CURRENT_VAL=$(jq -r '.MaxViewRadius' "$CONFIG_FILE" 2>/dev/null || echo "null")

    if [ "$CURRENT_VAL" != "16" ]; then
        echo "     » MaxViewRadius is currently ($CURRENT_VAL). Resetting to 16..."
        tmp=$(mktemp)
        jq '.MaxViewRadius = 16' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo "     » config.json updated successfully."
    else
        echo "     » config.json already optimized (MaxViewRadius: 16). Skipping edit."
    fi
fi

# ------------------------------------------------------------------------------
# [8] SERVER EXECUTION
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT SUCCESSFUL - STARTING HYTALE        "
echo "-------------------------------------------------------"

java -XX:AOTCache=HytaleServer.aot -jar HytaleServer.jar \
     --assets Assets.zip \
     --bind 0.0.0.0:${SERVER_PORT}
