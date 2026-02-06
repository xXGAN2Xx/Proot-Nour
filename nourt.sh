#!/bin/bash

# ==============================================================================
# 🎮 HYTALE SERVER AUTO-DEPLOYMENT SCRIPT (FAST ARIA2 VERSION)
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# [1] GLOBAL CONFIGURATION
# ------------------------------------------------------------------------------
PORT="5520"
UPDATE_MODE=false
PIXELDRAIN_IDS=()

# ------------------------------------------------------------------------------
# [2] ARGUMENT PROCESSING
# ------------------------------------------------------------------------------
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
            PIXELDRAIN_IDS+=("$(echo "$1" | tr -d ':,')")
            shift
            ;;
    esac
done

echo "======================================================="
echo "        HYTALE SERVER DEPLOYMENT INITIALIZED           "
echo "======================================================="
echo " [ℹ] Target Port: $PORT"
echo " [ℹ] Update Mode: $UPDATE_MODE"
echo " [ℹ] Source IDs:  ${PIXELDRAIN_IDS[*]}"
echo "-------------------------------------------------------"

# ------------------------------------------------------------------------------
# [3] ENVIRONMENT VALIDATION & DEPENDENCIES
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges."
  exit 1
fi

echo " [⚡] Phase 1: Configuring system environment..."
apt-get update -y
# ADDED: aria2 for multi-connection downloading
apt-get install -y openjdk-25-jre curl aria2

# ------------------------------------------------------------------------------
# [4] PIXELDRAIN RESOURCE IDENTIFICATION
# ------------------------------------------------------------------------------
if [ ${#PIXELDRAIN_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Two PixelDrain IDs are required."
    exit 1
fi

DETECTED_ASSETS_ID=""
DETECTED_JAR_ID=""

echo " [⚡] Phase 2: Resolving resource metadata..."
for id in "${PIXELDRAIN_IDS[@]}"; do
    FILE_INFO=$(curl -sL -A "Mozilla/5.0" "https://pixeldrain.com/api/file/${id}/info" || true)
    FILE_NAME=$(echo "$FILE_INFO" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || true)
    
    if [ -z "$FILE_NAME" ]; then
        echo " [!] ERROR: ID [$id] is invalid."
        exit 1
    fi

    echo "     » Detected: $FILE_NAME"

    if echo "$FILE_NAME" | grep -iq "Asset"; then
        DETECTED_ASSETS_ID="$id"
    else
        DETECTED_JAR_ID="$id"
    fi
done

if [ -z "$DETECTED_ASSETS_ID" ] || [ -z "$DETECTED_JAR_ID" ]; then
    echo " [!] ERROR: Resource ambiguity."
    exit 1
fi

# ------------------------------------------------------------------------------
# [5] REINSTALLATION LOGIC
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Phase 3: Update flag detected. Purging local binaries..."
    rm -f Assets.zip HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [6] DATA ACQUISITION (OPTIMIZED WITH ARIA2)
# ------------------------------------------------------------------------------
# We use aria2c with -x 16 (16 connections) and -s 16 (split into 16 parts)
# This maximizes speed without running in the background.

if [ ! -f "Assets.zip" ]; then
    echo " [⚡] Phase 4: Fetching Assets.zip (High Speed)..."
    aria2c -x 16 -s 16 -o Assets.zip "https://pixeldrain.com/api/file/${DETECTED_ASSETS_ID}"
else
    echo " [✓] Resource Assets.zip already present."
fi

if [ ! -f "HytaleServer.jar" ]; then
    echo " [⚡] Phase 5: Fetching HytaleServer.jar (High Speed)..."
    aria2c -x 16 -s 16 -o HytaleServer.jar "https://pixeldrain.com/api/file/${DETECTED_JAR_ID}"
    chmod +x HytaleServer.jar
else
    echo " [✓] Resource HytaleServer.jar already present."
fi

# ------------------------------------------------------------------------------
# [7] SERVER STARTUP
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT COMPLETE - STARTING HYTALE          "
echo "-------------------------------------------------------"
java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
