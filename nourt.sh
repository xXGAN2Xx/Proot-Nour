#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER (BYPASS + SMART UPDATE)
# ==============================================================================

set -e

# [1] CONFIGURATION
PORT="5520"
UPDATE_MODE=false
INPUT_IDs=()
BYPASS_BASE="https://gf.1drv.eu.org"

# Process Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --p)
            PORT="$2"
            shift 2
            ;;
        --u)
            UPDATE_MODE=true
            shift
            ;;
        *)
            # Extract ID from full URL if provided
            CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,')
            INPUT_IDs+=("$CLEAN_ID")
            shift
            ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="
echo " [ℹ] Target Port: $PORT"
echo " [ℹ] Update Mode: $UPDATE_MODE"
echo "-------------------------------------------------------"

# [2] SYSTEM SETUP
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges."
  exit 1
fi

echo " [⚡] Phase 1: Checking dependencies..."
# Ensure dependencies are installed
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# [3] STEALTH IDENTIFICATION
echo " [⚡] Phase 2: Identifying files via Bypass Gateway..."

ASSET_ID=""
JAR_ID=""

for id in "${INPUT_IDs[@]}"; do
    echo "     » Checking ID: $id..."
    
    # Check headers to find filename without using official GoFile API
    HEADERS=$(curl -sIL "${BYPASS_BASE}/$id")
    FNAME=$(echo "$HEADERS" | grep -i "content-disposition" | grep -o 'filename="[^"]*"' | cut -d'"' -f2 || true)

    if [ -n "$FNAME" ]; then
        echo "       Detected: $FNAME"
        if echo "$FNAME" | grep -iq "Asset"; then
            ASSET_ID="$id"
        elif echo "$FNAME" | grep -iq "Hytale" || echo "$FNAME" | grep -iq ".jar"; then
            JAR_ID="$id"
        fi
    fi
done

# FALLBACK LOGIC
if [ -z "$ASSET_ID" ] || [ -z "$JAR_ID" ]; then
    echo " [!] Identification could not confirm file types. Using input order:"
    ASSET_ID="${INPUT_IDs[0]}"
    JAR_ID="${INPUT_IDs[1]}"
fi

# [4] UPDATE / PURGE LOGIC
# If --u is used, we delete existing files so aria2 can redownload them fresh.
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Update flag (--u) detected. Purging local files for re-download..."
    rm -f Assets.zip HytaleServer.jar
fi

# [5] DOWNLOADS (USING 8 CONNECTIONS)
echo " [⚡] Phase 3: Fetching Resources (8-Connection Mode)..."

# Download Assets
if [ ! -f "Assets.zip" ]; then
    echo "     » Downloading Assets.zip..."
    aria2c -x 8 -s 8 --summary-interval=0 -o Assets.zip "${BYPASS_BASE}/${ASSET_ID}"
else
    echo "     » [✓] Assets.zip already exists. (Use --u to force update)"
fi

# Download Jar
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading HytaleServer.jar..."
    aria2c -x 8 -s 8 --summary-interval=0 -o HytaleServer.jar "${BYPASS_BASE}/${JAR_ID}"
    chmod +x HytaleServer.jar
else
    echo "     » [✓] HytaleServer.jar already exists. (Use --u to force update)"
fi

# [6] SERVER STARTUP
echo "-------------------------------------------------------"
echo "        DEPLOYMENT SUCCESSFUL - STARTING HYTALE        "
echo "-------------------------------------------------------"

java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
