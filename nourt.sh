#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTOMATED DEPLOYMENT SYSTEM (GOFILE EDITION)
# ==============================================================================
#
#  DESCRIPTION:
#    This script automates the deployment of a Hytale game server using GoFile.
#    It strictly enforces the order of input IDs to identify resources.
#
#  USAGE:
#    ./script.sh <ASSET_FOLDER_ID> <JAR_FOLDER_ID>
#
#  PREREQUISITES:
#    - Root privileges (sudo)
#    - Ubuntu/Debian based system
#
# ==============================================================================

set -e  # Exit immediately on error

# ------------------------------------------------------------------------------
# [1] GLOBAL CONFIGURATION
# ------------------------------------------------------------------------------
PORT="5520"           # Default port for the Hytale server
UPDATE_MODE=false     # Toggle to force re-download of files
GOFILE_IDS=()         # Array to store input Folder IDs

# ------------------------------------------------------------------------------
# [2] COMMAND LINE ARGUMENT PARSING
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --p)
            # Custom Port Flag
            PORT="$2"
            shift 2
            ;;
        --u)
            # Update Mode Flag
            UPDATE_MODE=true
            shift
            ;;
        *)
            # Sanitize input: Remove 'https://gofile.io/d/', colons, and commas
            CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,')
            GOFILE_IDS+=("$CLEAN_ID")
            shift
            ;;
    esac
done

# --- 🖥️ DISPLAY STARTUP BANNER ---
echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="
echo " [ℹ] Target Port: $PORT"
echo " [ℹ] Update Mode: $UPDATE_MODE"
echo " [ℹ] Asset ID:    ${GOFILE_IDS[0]} (First Input)"
echo " [ℹ] Jar ID:      ${GOFILE_IDS[1]} (Second Input)"
echo "-------------------------------------------------------"

# ------------------------------------------------------------------------------
# [3] ENVIRONMENT CHECK & DEPENDENCY INSTALLATION
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges."
  exit 1
fi

echo " [⚡] Phase 1: Configuring system environment..."

# Silently update package lists and install dependencies
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq

# ------------------------------------------------------------------------------
# [4] HELPER FUNCTION: GET LINK
# ------------------------------------------------------------------------------
# Inputs: $1 = GoFile Folder ID
# Outputs: Echoes the direct download link
get_gofile_link() {
    local FOLDER_ID=$1
    # Generic Website Token (often required for public API access)
    local WT="4fd6sg89d7s6" 

    # 1. Fetch Folder JSON
    local RESPONSE=$(curl -s -H "User-Agent: Mozilla/5.0" "https://api.gofile.io/contents/${FOLDER_ID}?wt=${WT}")
    
    # 2. Check Status
    local STATUS=$(echo "$RESPONSE" | jq -r '.status')
    if [ "$STATUS" != "ok" ]; then
        echo "ERROR: API returned status '$STATUS' for ID $FOLDER_ID" >&2
        return 1
    fi

    # 3. Extract First File Link
    local LINK=$(echo "$RESPONSE" | jq -r '.data.children | to_entries[] | .value | select(.type=="file") | .link' | head -n 1)

    if [ "$LINK" == "null" ] || [ -z "$LINK" ]; then
        echo "ERROR: No file found in folder $FOLDER_ID" >&2
        return 1
    fi

    echo "$LINK"
}

# ------------------------------------------------------------------------------
# [5] RESOURCE RESOLUTION
# ------------------------------------------------------------------------------
if [ ${#GOFILE_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Two Gofile IDs are required."
    echo "     Usage: ./script.sh <ASSET_ID> <JAR_ID>"
    exit 1
fi

echo " [⚡] Phase 2: Resolving download links..."

# --- RESOLVE ASSETS (FIRST ID) ---
ASSET_ID="${GOFILE_IDS[0]}"
echo "     » Resolving Assets from ID: $ASSET_ID..."
DETECTED_ASSETS_URL=$(get_gofile_link "$ASSET_ID")

# --- RESOLVE JAR (SECOND ID) ---
JAR_ID="${GOFILE_IDS[1]}"
echo "     » Resolving Jar from ID:    $JAR_ID..."
DETECTED_JAR_URL=$(get_gofile_link "$JAR_ID")

# ------------------------------------------------------------------------------
# [6] CLEANUP & DOWNLOAD
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Phase 3: Update flag detected. Purging local binaries..."
    rm -f Assets.zip HytaleServer.jar
fi

echo " [⚡] Phase 4: Downloading Resources..."

# --- DOWNLOAD ASSETS ---
if [ ! -f "Assets.zip" ]; then
    echo "     » Fetching Assets.zip (Source: First ID)..."
    aria2c -x 16 -s 16 -o Assets.zip "$DETECTED_ASSETS_URL"
else
    echo "     » [✓] Assets.zip already present."
fi

# --- DOWNLOAD JAR ---
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Fetching HytaleServer.jar (Source: Second ID)..."
    aria2c -x 16 -s 16 -o HytaleServer.jar "$DETECTED_JAR_URL"
    chmod +x HytaleServer.jar
else
    echo "     » [✓] HytaleServer.jar already present."
fi

# ------------------------------------------------------------------------------
# [7] SERVER EXECUTION
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT COMPLETE - STARTING HYTALE          "
echo "-------------------------------------------------------"
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
