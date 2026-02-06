#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER (PREMIUM BYPASS EDITION)
# ==============================================================================
#  - Bypasses 'error-notPremium' by avoiding the official Gofile API.
#  - Detects file types via Bypass Headers.
#  - Uses gf.1drv.eu.org for unlimited downloading.
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] CONFIGURATION
# ------------------------------------------------------------------------------
PORT="5520"
UPDATE_MODE=false
INPUT_IDs=()
BYPASS_BASE="https://gf.1drv.eu.org"

while [[ $# -gt 0 ]]; do
    case $1 in
        --p) PORT="$2"; shift 2 ;;
        --u) UPDATE_MODE=true; shift ;;
        *) CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,'); INPUT_IDs+=("$CLEAN_ID"); shift ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="

# ------------------------------------------------------------------------------
# [2] SYSTEM SETUP
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Please run as root (sudo)."
  exit 1
fi

echo " [⚡] Phase 1: Installing dependencies..."
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [3] STEALTH IDENTIFICATION (BYPASSING GOFILE API)
# ------------------------------------------------------------------------------
echo " [⚡] Phase 2: Identifying files via Bypass Gateway..."

ASSET_ID=""
JAR_ID=""

for id in "${INPUT_IDs[@]}"; do
    echo "     » Checking ID: $id..."
    
    # We check the headers of the bypass link to find the filename
    # This avoids the 'error-notPremium' API block entirely.
    HEADERS=$(curl -sIL "${BYPASS_BASE}/$id")
    FNAME=$(echo "$HEADERS" | grep -i "content-disposition" | grep -o 'filename="[^"]*"' | cut -d'"' -f2 || true)

    if [ -n "$FNAME" ]; then
        echo "       Detected: $FNAME"
        if echo "$FNAME" | grep -iq "Asset"; then
            ASSET_ID="$id"
        elif echo "$FNAME" | grep -iq "Hytale" || echo "$FNAME" | grep -iq ".jar"; then
            JAR_ID="$id"
        fi
    else
        echo "       Warning: Could not detect filename for $id (Bypass is masked)."
    fi
done

# --- FALLBACK LOGIC ---
# If identification failed (bypass masked headers), we use the order provided.
if [ -z "$ASSET_ID" ] || [ -z "$JAR_ID" ]; then
    echo " [!] Identification failed. Falling back to strict order:"
    echo "     1st ID -> Assets.zip"
    echo "     2nd ID -> HytaleServer.jar"
    ASSET_ID="${INPUT_IDs[0]}"
    JAR_ID="${INPUT_IDs[1]}"
fi

# ------------------------------------------------------------------------------
# [4] DOWNLOADS (USING BYPASS GATEWAY)
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    rm -f Assets.zip HytaleServer.jar
fi

echo " [⚡] Phase 3: Downloading Resources..."

# Download Assets
if [ ! -f "Assets.zip" ]; then
    echo "     » Downloading Assets.zip..."
    aria2c -x 8 -s 8 --summary-interval=0 -o Assets.zip "${BYPASS_BASE}/${ASSET_ID}"
else
    echo "     » [✓] Assets.zip already exists."
fi

# Download Jar
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading HytaleServer.jar..."
    aria2c -x 8 -s 8 --summary-interval=0 -o HytaleServer.jar "${BYPASS_BASE}/${JAR_ID}"
    chmod +x HytaleServer.jar
else
    echo "     » [✓] HytaleServer.jar already exists."
fi

# ------------------------------------------------------------------------------
# [5] LAUNCH
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT SUCCESSFUL - STARTING HYTALE        "
echo "-------------------------------------------------------"

java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
