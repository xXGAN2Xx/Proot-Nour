#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER (GOFILE API v3 - DYNAMIC SESSION)
# ==============================================================================
#  USAGE: ./script.sh [ASSET_ID] [JAR_ID] --p [PORT]
#  ORDER: 1st ID = Assets.zip | 2nd ID = HytaleServer.jar
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] CONFIGURATION & ARGUMENTS
# ------------------------------------------------------------------------------
PORT="5520"
UPDATE_MODE=false
GOFILE_IDS=()

# Parse flags and IDs
while [[ $# -gt 0 ]]; do
    case $1 in
        --p) PORT="$2"; shift 2 ;;
        --u) UPDATE_MODE=true; shift ;;
        *) 
            # Strip URL parts if user pasted a full link (e.g. gofile.io/d/XXXX)
            CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,')
            GOFILE_IDS+=("$CLEAN_ID")
            shift 
            ;;
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
# [2] SYSTEM DEPENDENCIES
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Please run as root (sudo)."
  exit 1
fi

echo " [⚡] Phase 1: Installing system dependencies (jq, aria2, openjdk)..."
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [3] GUEST TOKEN GENERATION
# ------------------------------------------------------------------------------
echo " [⚡] Phase 2: Creating temporary Gofile session..."

# This POST creates the account object you sent me and extracts the token
GUEST_TOKEN=$(curl -s -X POST "https://api.gofile.io/accounts" \
    -H "User-Agent: Mozilla/5.0" \
    -H "Accept: application/json" \
    -H "Origin: https://gofile.io" \
    | jq -r '.data.token')

if [ -z "$GUEST_TOKEN" ] || [ "$GUEST_TOKEN" == "null" ]; then
    echo " [!] ERROR: Failed to get API token from Gofile."
    exit 1
fi

# ------------------------------------------------------------------------------
# [4] RESOURCE RESOLUTION
# ------------------------------------------------------------------------------
if [ ${#GOFILE_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: You must provide TWO IDs (Assets ID first, then Jar ID)."
    exit 1
fi

# Function to fetch the direct link from a folder ID
fetch_link() {
    local ID=$1
    
    # Request folder content using the Bearer token
    local RESP=$(curl -s -H "Authorization: Bearer $GUEST_TOKEN" \
                        -H "User-Agent: Mozilla/5.0" \
                        "https://api.gofile.io/contents/$ID")
    
    # Check if API returned an error
    local STATUS=$(echo "$RESP" | jq -r '.status')
    if [ "$STATUS" != "ok" ]; then
        echo " [!] ERROR: Gofile API rejected ID $ID ($STATUS)" >&2
        exit 1
    fi

    # Extract the download link from the first file found in the children object
    local LINK=$(echo "$RESP" | jq -r '.data.children | to_entries[0].value.link')

    if [ -z "$LINK" ] || [ "$LINK" == "null" ]; then
        echo " [!] ERROR: Could not find a file inside ID $ID" >&2
        exit 1
    fi
    echo "$LINK"
}

echo " [⚡] Phase 3: Resolving file links from Gofile..."
ASSET_URL=$(fetch_link "${GOFILE_IDS[0]}")
JAR_URL=$(fetch_link "${GOFILE_IDS[1]}")

# ------------------------------------------------------------------------------
# [5] DOWNLOADS (ARIA2)
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Update mode: Cleaning old files..."
    rm -f Assets.zip HytaleServer.jar
fi

echo " [⚡] Phase 4: Downloading files with Aria2..."

# Download 1st ID as Assets.zip
if [ ! -f "Assets.zip" ]; then
    echo "     » Fetching Assets..."
    aria2c -x 16 -s 16 --summary-interval=0 -o Assets.zip "$ASSET_URL"
else
    echo "     » [✓] Assets.zip already exists."
fi

# Download 2nd ID as HytaleServer.jar
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Fetching HytaleServer.jar..."
    aria2c -x 16 -s 16 --summary-interval=0 -o HytaleServer.jar "$JAR_URL"
    chmod +x HytaleServer.jar
else
    echo "     » [✓] HytaleServer.jar already exists."
fi

# ------------------------------------------------------------------------------
# [6] LAUNCH
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT SUCCESSFUL - LAUNCHING SERVER       "
echo "-------------------------------------------------------"

# Launch Hytale using the resolved port
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
