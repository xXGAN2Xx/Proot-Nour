#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER (ID ARGUMENT VERSION)
# ==============================================================================
#  USAGE: ./script.sh [ASSET_ID] [JAR_ID] --p [PORT]
#  EXAMPLE: ./script.sh 7a4581d3-d335... 3655393e-dc75...
# ==============================================================================

set -e
set -o pipefail

# ------------------------------------------------------------------------------
# [1] CONFIGURATION
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
            # Strip URL parts if user pasted a full link, keep only the ID
            CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,')
            # Also strip download/web/ if present (from direct links)
            CLEAN_ID=$(echo "$CLEAN_ID" | sed 's/.*download\/web\///')
            GOFILE_IDS+=("$CLEAN_ID")
            shift 
            ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="
echo " [ℹ] Target Port: $PORT"
echo " [ℹ] Asset ID:    ${GOFILE_IDS[0]}"
echo " [ℹ] Jar ID:      ${GOFILE_IDS[1]}"
echo "-------------------------------------------------------"

# ------------------------------------------------------------------------------
# [2] DEPENDENCIES
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Please run as root (sudo)."
  exit 1
fi

echo " [⚡] Phase 1: Installing dependencies..."
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-21-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [3] DYNAMIC TOKEN GENERATION
# ------------------------------------------------------------------------------
echo " [⚡] Phase 2: Generating Gofile Session..."

# 1. Get the best available server (as requested)
SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name')

# Fallback if server fetch fails
if [ -z "$SERVER" ] || [ "$SERVER" == "null" ]; then
    SERVER="store1"
fi

echo "     » Selected Server: $SERVER"

# 2. Create Account on that server
GUEST_TOKEN=$(curl -s -X POST "https://${SERVER}.gofile.io/accounts" \
    -H "User-Agent: Mozilla/5.0" \
    -H "Accept: application/json" \
    -H "Origin: https://gofile.io" \
    | jq -r '.data.token')

if [ -z "$GUEST_TOKEN" ] || [ "$GUEST_TOKEN" == "null" ]; then
    echo " [!] ERROR: Failed to generate token. Gofile API may be blocking requests."
    exit 1
fi

echo "     » Token Acquired: ${GUEST_TOKEN:0:10}..."

# ------------------------------------------------------------------------------
# [4] RESOLVE LINKS
# ------------------------------------------------------------------------------
if [ ${#GOFILE_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: You must provide TWO IDs (Assets ID first, then Jar ID)."
    exit 1
fi

fetch_link() {
    local ID=$1
    
    # API Call to list folder contents
    local RESP=$(curl -s -H "Authorization: Bearer $GUEST_TOKEN" \
                        -H "User-Agent: Mozilla/5.0" \
                        "https://api.gofile.io/contents/$ID")
    
    # Error Handling
    local STATUS=$(echo "$RESP" | jq -r '.status')
    
    if [ "$STATUS" == "error-notPremium" ]; then
        echo "ERROR_PREMIUM"
        return
    fi
    
    if [ "$STATUS" != "ok" ]; then
        echo "ERROR_API"
        return
    fi

    # Extract Link
    local LINK=$(echo "$RESP" | jq -r '.data.children | to_entries[0].value.link')
    echo "$LINK"
}

echo " [⚡] Phase 3: Resolving File URLs..."

# Resolve Assets
ASSET_URL=$(fetch_link "${GOFILE_IDS[0]}")
if [ "$ASSET_URL" == "ERROR_PREMIUM" ]; then
    echo " [!] CRITICAL: Gofile requires a Premium account to list folder ID: ${GOFILE_IDS[0]}"
    echo "     Please use the Direct Link version of this script instead."
    exit 1
elif [ -z "$ASSET_URL" ] || [ "$ASSET_URL" == "ERROR_API" ]; then
    echo " [!] Failed to resolve Asset URL."
    exit 1
fi

# Resolve Jar
JAR_URL=$(fetch_link "${GOFILE_IDS[1]}")
if [ "$JAR_URL" == "ERROR_PREMIUM" ]; then
    echo " [!] CRITICAL: Gofile requires a Premium account to list folder ID: ${GOFILE_IDS[1]}"
    exit 1
elif [ -z "$JAR_URL" ] || [ "$JAR_URL" == "ERROR_API" ]; then
    echo " [!] Failed to resolve Jar URL."
    exit 1
fi

# ------------------------------------------------------------------------------
# [5] DOWNLOAD & LAUNCH
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    rm -f Assets.zip HytaleServer.jar
fi

echo " [⚡] Phase 4: Downloading..."

if [ ! -f "Assets.zip" ]; then
    echo "     » Downloading Assets..."
    aria2c -x 16 -s 16 --summary-interval=0 -o Assets.zip "$ASSET_URL"
fi

if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading Server Jar..."
    aria2c -x 16 -s 16 --summary-interval=0 -o HytaleServer.jar "$JAR_URL"
    chmod +x HytaleServer.jar
fi

echo "-------------------------------------------------------"
echo "        LAUNCHING SERVER ON PORT $PORT                 "
echo "-------------------------------------------------------"
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
