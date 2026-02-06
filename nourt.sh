#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER
#  ----------------------------------------------------------------------------
#  Description: Automates the deployment, update, and launch of Hytale servers.
#               Includes a custom bypass for file acquisition and multi-threaded
#               downloading for high performance.
#
#  Usage:       sudo ./deploy.sh [GoFile_IDs/URLs] --p [PORT] --u
#  Flags:       --p : Set custom server port (Default: 5520)
#               --u : Update mode (Clears existing JAR/Assets)
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# ------------------------------------------------------------------------------
# [1] INITIAL CONFIGURATION & DEFAULTS
# ------------------------------------------------------------------------------

# Use environment variable for port, otherwise default to 5520
SERVER_PORT="${SERVER_PORT:-5520}"
UPDATE_MODE=false
INPUT_IDs=()

# The gateway used to fetch files without hitting standard API limits
BYPASS_BASE="https://gf.1drv.eu.org"

# ------------------------------------------------------------------------------
# [2] ARGUMENT PARSING
# ------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        --p)
            SERVER_PORT="$2"
            shift 2
            ;;
        --u)
            UPDATE_MODE=true
            shift
            ;;
        *)
            # Clean the input: If a full URL is provided, strip it down to the ID
            CLEAN_ID=$(echo "$1" | sed 's/.*gofile.io\/d\///' | tr -d ':,')
            INPUT_IDs+=("$CLEAN_ID")
            shift
            ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="
echo " [ℹ] Target Port: $SERVER_PORT"
echo " [ℹ] Update Mode: $UPDATE_MODE"
echo "-------------------------------------------------------"

# ------------------------------------------------------------------------------
# [3] ENVIRONMENT PREVALIDATION
# ------------------------------------------------------------------------------

# Ensure the script is running with root privileges for package installation
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges (sudo)."
  exit 1
fi

echo " [⚡] Phase 1: Validating System Dependencies..."

# Update package lists and install required tools quietly
# - openjdk-25-jre: Java Runtime
# - aria2: Multi-connection downloader
# - jq: JSON processor (if needed for metadata)
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [4] SMART FILE IDENTIFICATION
# ------------------------------------------------------------------------------
# This logic determines which ID belongs to the 'Assets' and which is the 'Jar'
# by inspecting the HTTP headers before downloading.

echo " [⚡] Phase 2: Identifying files via Bypass Gateway..."

ASSET_ID=""
JAR_ID=""

for id in "${INPUT_IDs[@]}"; do
    echo "     » Probing ID: $id..."
    
    # Fetch headers to find filename without downloading the whole file
    HEADERS=$(curl -sIL "${BYPASS_BASE}/$id")
    FNAME=$(echo "$HEADERS" | grep -i "content-disposition" | grep -o 'filename="[^"]*"' | cut -d'"' -f2 || true)

    if [ -n "$FNAME" ]; then
        echo "       Detected: $FNAME"
        # Categorize file based on naming convention
        if echo "$FNAME" | grep -iq "Asset"; then
            ASSET_ID="$id"
        elif echo "$FNAME" | grep -iq "Hytale" || echo "$FNAME" | grep -iq ".jar"; then
            JAR_ID="$id"
        fi
    fi
done

# Fallback: If probing fails, assume ID order (1st=Assets, 2nd=Jar)
if [ -z "$ASSET_ID" ] || [ -z "$JAR_ID" ]; then
    echo " [!] Identification could not confirm types. Defaulting to input order."
    ASSET_ID="${INPUT_IDs[0]}"
    JAR_ID="${INPUT_IDs[1]}"
fi

# ------------------------------------------------------------------------------
# [5] CLEANUP / UPDATE LOGIC
# ------------------------------------------------------------------------------

if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Update flag detected. Removing local binaries..."
    rm -f Assets.zip HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [6] HIGH-SPEED DOWNLOADS
# ------------------------------------------------------------------------------
# Uses aria2c with 8 concurrent connections per file for maximum speed.

echo " [⚡] Phase 3: Fetching Resources (High-Speed Mode)..."

# Fetch Assets
if [ ! -f "Assets.zip" ]; then
    echo "     » Downloading Assets.zip..."
    aria2c -x 8 -s 8 --summary-interval=0 -o Assets.zip "${BYPASS_BASE}/${ASSET_ID}"
else
    echo "     » [✓] Assets.zip exists. Skipping."
fi

# Fetch Executable Jar
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading HytaleServer.jar..."
    aria2c -x 8 -s 8 --summary-interval=0 -o HytaleServer.jar "${BYPASS_BASE}/${JAR_ID}"
    chmod +x HytaleServer.jar
else
    echo "     » [✓] HytaleServer.jar exists. Skipping."
fi

# ------------------------------------------------------------------------------
# [7] SERVER EXECUTION
# ------------------------------------------------------------------------------
# Launches the server using Ahead-of-Time (AOT) caching for optimized startup.

echo "-------------------------------------------------------"
echo "        DEPLOYMENT SUCCESSFUL - STARTING HYTALE        "
echo "-------------------------------------------------------"

# Bind to 0.0.0.0 to allow external connections on the specified port
java -XX:AOTCache=HytaleServer.aot -jar HytaleServer.jar \
     --assets Assets.zip \
     --bind 0.0.0.0:${SERVER_PORT}
