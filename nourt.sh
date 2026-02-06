#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER (GOFILE DYNAMIC TOKEN VERSION)
# ==============================================================================
#  1st ID = Assets.zip | 2nd ID = HytaleServer.jar
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] CONFIGURATION & ARGUMENTS
# ------------------------------------------------------------------------------
PORT="5520"
UPDATE_MODE=false
GOFILE_IDS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --p) PORT="$2"; shift 2 ;;
        --u) UPDATE_MODE=true; shift ;;
        *) CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,'); GOFILE_IDS+=("$CLEAN_ID"); shift ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="
echo " [ℹ] Target Port: $PORT"
echo " [ℹ] Asset ID (1st): ${GOFILE_IDS[0]}"
echo " [ℹ] Jar ID   (2nd): ${GOFILE_IDS[1]}"
echo "-------------------------------------------------------"

# ------------------------------------------------------------------------------
# [2] SYSTEM SETUP
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Please run as root (sudo)."
  exit 1
fi

echo " [⚡] Phase 1: Installing dependencies (jq, aria2, curl)..."
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [3] DYNAMIC TOKEN GENERATION (FIXES ERROR-TOKEN)
# ------------------------------------------------------------------------------
echo " [⚡] Phase 2: Generating dynamic Gofile Guest Token..."
# This creates a temporary guest account session to authorize downloads
GUEST_TOKEN=$(curl -s -X POST https://api.gofile.io/accounts | jq -r '.data.token')

if [ -z "$GUEST_TOKEN" ] || [ "$GUEST_TOKEN" == "null" ]; then
    echo " [!] ERROR: Could not generate Gofile session token. API might be down."
    exit 1
fi

# ------------------------------------------------------------------------------
# [4] LINK RESOLUTION
# ------------------------------------------------------------------------------
if [ ${#GOFILE_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Missing IDs. Usage: ./script.sh <AssetID> <JarID>"
    exit 1
fi

resolve_link() {
    local ID=$1
    local RESP=$(curl -s -H "Authorization: Bearer $GUEST_TOKEN" "https://api.gofile.io/contents/$ID")
    local LINK=$(echo "$RESP" | jq -r '.data.children | to_entries[] | .value | select(.type=="file") | .link' | head -n 1)
    
    if [ -z "$LINK" ] || [ "$LINK" == "null" ]; then
        echo " [!] ERROR: Failed to resolve ID $ID (Check if folder is public)" >&2
        exit 1
    fi
    echo "$LINK"
}

echo " [⚡] Phase 3: Resolving download links..."
ASSET_URL=$(resolve_link "${GOFILE_IDS[0]}")
JAR_URL=$(resolve_link "${GOFILE_IDS[1]}")

# ------------------------------------------------------------------------------
# [5] DOWNLOAD & EXECUTE
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    rm -f Assets.zip HytaleServer.jar
fi

echo " [⚡] Phase 4: Downloading Files..."

# Download Assets (1st ID)
if [ ! -f "Assets.zip" ]; then
    echo "     » Downloading Assets.zip..."
    aria2c -x 16 -s 16 -o Assets.zip "$ASSET_URL"
fi

# Download Jar (2nd ID)
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading HytaleServer.jar..."
    aria2c -x 16 -s 16 -o HytaleServer.jar "$JAR_URL"
    chmod +x HytaleServer.jar
fi

echo "-------------------------------------------------------"
echo "        SUCCESS - STARTING HYTALE SERVER               "
echo "-------------------------------------------------------"
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
