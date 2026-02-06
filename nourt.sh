#!/bin/bash

# ==============================================================================
#  🎮 HYTALE SERVER AUTO-DEPLOYER (BYPASS & DIRECT VERSION)
# ==============================================================================
#  ORDER: 1st ID = Assets.zip | 2nd ID = HytaleServer.jar
#  BYPASS: Uses gf.1drv.eu.org to skip GoFile quotas/premium limits
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] CONFIGURATION
# ------------------------------------------------------------------------------
PORT="5520"
UPDATE_MODE=false
GOFILE_IDS=()
BYPASS_URL="https://gf.1drv.eu.org" # Taken from your Bypass UserScript

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

echo " [⚡] Phase 1: Installing dependencies..."
apt-get update -y > /dev/null 2>&1
apt-get install -y openjdk-25-jre curl aria2 jq > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [3] DIRECT DOWNLOADS (USING BYPASS LOGIC)
# ------------------------------------------------------------------------------
if [ ${#GOFILE_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Missing IDs. Usage: ./script.sh <AssetID> <JarID>"
    exit 1
fi

if [ "$UPDATE_MODE" = true ]; then
    rm -f Assets.zip HytaleServer.jar
fi

echo " [⚡] Phase 2: Downloading Resources..."

# --- Download Assets ---
if [ ! -f "Assets.zip" ]; then
    echo "     » Downloading Assets.zip (Bypassing Quota)..."
    # We use the Bypass URL from your script to get the direct file stream
    # This avoids "Premium Only" or "Quota Exceeded" errors
    aria2c -x 8 -s 8 --summary-interval=0 -o Assets.zip "${BYPASS_URL}/${GOFILE_IDS[0]}"
else
    echo "     » [✓] Assets.zip already present."
fi

# --- Download Jar ---
if [ ! -f "HytaleServer.jar" ]; then
    echo "     » Downloading HytaleServer.jar (Bypassing Quota)..."
    aria2c -x 8 -s 8 --summary-interval=0 -o HytaleServer.jar "${BYPASS_URL}/${GOFILE_IDS[1]}"
    chmod +x HytaleServer.jar
else
    echo "     » [✓] HytaleServer.jar already present."
fi

# ------------------------------------------------------------------------------
# [4] SERVER LAUNCH
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        SUCCESS - STARTING HYTALE SERVER               "
echo "-------------------------------------------------------"

# Launching Hytale
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
