#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTOMATED DEPLOYMENT SYSTEM (GOFILE EDITION)
# ==============================================================================
#
#  DESCRIPTION:
#    This script automates the deployment of a Hytale game server.
#    It handles dependency installation, secure API authentication with GoFile,
#    smart resource detection (Assets vs Server Jar), and high-speed downloading.
#
#  PREREQUISITES:
#    - Root privileges (sudo)
#    - Ubuntu/Debian based system (uses apt-get)
#
# ==============================================================================

set -e  # Exit immediately if a command exits with a non-zero status.

# ------------------------------------------------------------------------------
# [1] GLOBAL CONFIGURATION & CREDENTIALS
# ------------------------------------------------------------------------------
PORT="5520"           # Default port for the Hytale server
UPDATE_MODE=false     # Toggle to force re-download of files
GOFILE_IDS=()         # Array to store input Folder IDs

# --- 🔐 SECURITY CREDENTIALS ---
# API Token required for authenticated access (Bypasses guest rate limits)
ACCOUNT_TOKEN="0d9inKerBo60GLQKkxltBzIOIvBUpa3Y"

# Account UUID (kept for logging/reference purposes)
ACCOUNT_ID="c8b17e80-cff6-4d53-b3e2-8df18a61c49e"

# ------------------------------------------------------------------------------
# [2] COMMAND LINE ARGUMENT PARSING
# ------------------------------------------------------------------------------
# We loop through all arguments passed to the script to find flags or IDs.
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
            # Assume any other argument is a GoFile Folder ID or URL
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
echo " [ℹ] Source IDs:  ${GOFILE_IDS[*]}"
echo "-------------------------------------------------------"

# ------------------------------------------------------------------------------
# [3] ENVIRONMENT CHECK & DEPENDENCY INSTALLATION
# ------------------------------------------------------------------------------
# Ensure the script is run as root to allow package installation
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges."
  exit 1
fi

echo " [⚡] Phase 1: Configuring system environment..."

# Silently update package lists
apt-get update -y > /dev/null 2>&1

# Install required tools:
# - openjdk-25-jre: The Java runtime for the server
# - curl: For making API requests
# - aria2: For multi-connection high-speed file downloading
# - jq: For parsing the JSON response from GoFile API
apt-get install -y openjdk-25-jre curl aria2 jq

# ------------------------------------------------------------------------------
# [4] GOFILE RESOURCE RESOLUTION
# ------------------------------------------------------------------------------
# We need exactly two IDs: one for the JAR folder, one for the ASSETS folder.
if [ ${#GOFILE_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Two Gofile IDs (Folder codes) are required."
    echo "     Usage: ./script.sh <AssetFolderID> <JarFolderID>"
    exit 1
fi

DETECTED_ASSETS_URL=""
DETECTED_JAR_URL=""

echo " [⚡] Phase 2: Resolving resource metadata from Gofile..."

# Iterate through provided IDs to figure out which is which
for id in "${GOFILE_IDS[@]}"; do
    
    # 1. API Call: Fetch folder contents using the Account Token
    #    We use -H "Authorization" to authenticate.
    RESPONSE=$(curl -s -H "Authorization: Bearer ${ACCOUNT_TOKEN}" \
                       -H "User-Agent: Mozilla/5.0" \
                       "https://api.gofile.io/contents/${id}")
    
    # 2. Validation: Check if the API returned "status": "ok"
    STATUS=$(echo "$RESPONSE" | jq -r '.status')
    
    if [ "$STATUS" != "ok" ]; then
        echo " [!] ERROR: Failed to fetch info for ID [$id]."
        echo "     API Response: $STATUS"
        echo "     (Verify Folder ID and Account Token validity)"
        exit 1
    fi

    # 3. Extraction: Parse the JSON to find the file inside the folder
    #    We assume the folder contains one main file. We extract Name and Direct Link.
    FILE_DATA=$(echo "$RESPONSE" | jq -r '.data.children | to_entries[] | .value | select(.type=="file") | "\(.name)|\(.link)"' | head -n 1)
    
    FILE_NAME=$(echo "$FILE_DATA" | cut -d'|' -f1)
    FILE_LINK=$(echo "$FILE_DATA" | cut -d'|' -f2)

    # 4. Integrity Check: Ensure we actually found a file
    if [ -z "$FILE_NAME" ] || [ "$FILE_LINK" == "null" ] || [ -z "$FILE_LINK" ]; then
        echo " [!] ERROR: No file found inside Gofile ID [$id] or link is expired."
        exit 1
    fi

    echo "     » Detected: $FILE_NAME"

    # 5. Classification: Decide if it is the Asset Zip or the Server Jar
    if echo "$FILE_NAME" | grep -iq "Asset"; then
        DETECTED_ASSETS_URL="$FILE_LINK"
    elif echo "$FILE_NAME" | grep -iq "Hytale" || echo "$FILE_NAME" | grep -iq ".jar"; then
        DETECTED_JAR_URL="$FILE_LINK"
    else
        # Fallback logic if naming is ambiguous
        echo "     [?] Warning: Unrecognized file '$FILE_NAME'. Assuming JAR if JAR missing."
        if [ -z "$DETECTED_JAR_URL" ]; then
            DETECTED_JAR_URL="$FILE_LINK"
        fi
    fi
done

# Final check to ensure we have both components
if [ -z "$DETECTED_ASSETS_URL" ] || [ -z "$DETECTED_JAR_URL" ]; then
    echo " [!] ERROR: Resource ambiguity. Could not distinguish Jar from Assets."
    echo "     Make sure files are named 'Assets.zip' and 'HytaleServer.jar' (or similar)."
    exit 1
fi

# ------------------------------------------------------------------------------
# [5] CLEANUP & PREPARATION
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Phase 3: Update flag detected. Purging local binaries..."
    # Remove existing files to force aria2 to download fresh copies
    rm -f Assets.zip HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [6] HIGH-SPEED DOWNLOAD (ARIA2)
# ------------------------------------------------------------------------------
echo " [⚡] Phase 4: Downloading Resources..."

# Download Assets.zip
# -x 16: Use 16 connections
# -s 16: Split file into 16 pieces
if [ ! -f "Assets.zip" ]; then
    echo "     » Fetching Assets.zip..."
    aria2c -x 16 -s 16 -o Assets.zip "$DETECTED_ASSETS_URL"
else
    echo "     » [✓] Assets.zip already present."
fi

# Download HytaleServer.jar
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Fetching HytaleServer.jar..."
    aria2c -x 16 -s 16 -o HytaleServer.jar "$DETECTED_JAR_URL"
    # Make the jar executable (good practice, though java -jar handles it)
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

# Launch the Java server
# --assets: Points to the resource pack
# --bind: Binds to all IPs (0.0.0.0) on the specified port
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
