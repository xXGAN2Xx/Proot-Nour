#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER
#  ----------------------------------------------------------------------------
#  Usage:       sudo ./deploy.sh [GoFile_IDs/URLs] --p [PORT] --u
#  Flags:       --p : Set custom server port (Default: 5520)
#               --u : Update mode (Clears existing JAR/Assets)
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] INITIAL CONFIGURATION & DEFAULTS
# ------------------------------------------------------------------------------
SERVER_PORT="${SERVER_PORT:-5520}"
UPDATE_MODE=false
NEEDS_CONFIG_PATCH=false
INPUT_IDs=()
BYPASS_BASE="https://gf.1drv.eu.org"

# ------------------------------------------------------------------------------
# [2] ARGUMENT PARSING
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --p) SERVER_PORT="$2"; shift 2 ;;
        --u) UPDATE_MODE=true; NEEDS_CONFIG_PATCH=true; shift ;;
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
    echo "     » Downloading Assets.zip..."
    aria2c -x 8 -s 8 --summary-interval=0 -o Assets.zip "${BYPASS_BASE}/${ASSET_ID}"
    NEEDS_CONFIG_PATCH=true
fi

if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading HytaleServer.jar..."
    aria2c -x 8 -s 8 --summary-interval=0 -o HytaleServer.jar "${BYPASS_BASE}/${JAR_ID}"
    chmod +x HytaleServer.jar
    NEEDS_CONFIG_PATCH=true
fi

# ------------------------------------------------------------------------------
# [7] CONFIGURATION TUNING (Run only on Install or Update)
# ------------------------------------------------------------------------------
if [ "$NEEDS_CONFIG_PATCH" = true ]; then
    echo " [⚡] Phase 4: Applying Configuration Tweaks (Install/Update detected)..."
    
    # Create a default config if it doesn't exist, or update existing
    if [ ! -f "config.json" ]; then
        echo '{"MaxViewRadius": 16}' > config.json
        echo "     » Created new config.json with MaxViewRadius: 16"
    else
        # Use jq to update the value safely
        tmp=$(mktemp)
        jq '.MaxViewRadius = 16' config.json > "$tmp" && mv "$tmp" config.json
        echo "     » Updated existing config.json: MaxViewRadius set to 16"
    fi
else
    echo " [⚡] Phase 4: Skipping Config Tweak (No install/update required)."
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
