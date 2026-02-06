#!/bin/bash

# ==============================================================================
# 🎮 HYTALE SERVER AUTO-DEPLOYMENT SCRIPT (PIXELDRAIN VERSION)
# ==============================================================================
# AUTHOR:  Nour
# PLATFORM: Debian / Ubuntu
# 
# DESCRIPTION:
#   A streamlined deployment utility that retrieves Hytale server components
#   from PixelDrain, automatically identifies file types via API metadata,
#   handles system dependencies, and launches the server instance.
#
# USAGE:
#   curl -sL <URL> | bash -s -- <ID_1> <ID_2> [--p <PORT>] [--u]
#   curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- 1 2 --p 5520
# ARGUMENTS:
#   <ID_1/2> : PixelDrain unique file identifiers.
#   --p      : Overrides the default port (5520).
#   --u      : Update Mode. Forces re-download of existing assets/jar.
# ==============================================================================

set -e # Terminate script on any command failure

# ------------------------------------------------------------------------------
# [1] GLOBAL CONFIGURATION & DEFAULTS
# ------------------------------------------------------------------------------
PORT="5520"           # Default Hytale communication port
UPDATE_MODE=false     # Boolean flag for forced reinstallation
PIXELDRAIN_IDS=()     # Array to store positional file IDs

# ------------------------------------------------------------------------------
# [2] ARGUMENT PROCESSING
#    Iterates through input to separate command flags from positional IDs.
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
            # Sanitize input: Remove colons or commas if pasted from URLs
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
#    Ensures administrative privileges and presence of the Java Runtime.
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
  echo " [!] CRITICAL: Deployment requires root privileges for 'apt-get'."
  exit 1
fi

echo " [⚡] Phase 1: Configuring system environment..."
apt-get update -y
# Removed wget, ensured curl is installed
apt-get install -y openjdk-25-jre curl

# ------------------------------------------------------------------------------
# [4] PIXELDRAIN RESOURCE IDENTIFICATION
#    Connects to PixelDrain API to determine which ID is 'Assets' and which
#    is the 'Server Jar' by inspecting the internal filename metadata.
# ------------------------------------------------------------------------------
if [ ${#PIXELDRAIN_IDS[@]} -lt 2 ]; then
    echo " [!] ERROR: Identification failed. Two PixelDrain IDs are required."
    exit 1
fi

DETECTED_ASSETS_ID=""
DETECTED_JAR_ID=""

echo " [⚡] Phase 2: Resolving resource metadata from API..."
for id in "${PIXELDRAIN_IDS[@]}"; do
    # Fetch JSON metadata using curl
    # -s: Silent, -L: Follow redirects, -A: User Agent
    FILE_INFO=$(curl -sL -A "Mozilla/5.0" "https://pixeldrain.com/api/file/${id}/info" || true)
    
    # Parse filename from JSON response
    FILE_NAME=$(echo "$FILE_INFO" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || true)
    
    if [ -z "$FILE_NAME" ]; then
        echo " [!] ERROR: ID [$id] is invalid or file is private."
        exit 1
    fi

    echo "     » Detected: $FILE_NAME"

    # Sorting Logic: Filenames containing "Asset" (case-insensitive) = Assets.zip
    if echo "$FILE_NAME" | grep -iq "Asset"; then
        DETECTED_ASSETS_ID="$id"
    else
        DETECTED_JAR_ID="$id"
    fi
done

# Verify that logic successfully assigned both mandatory IDs
if [ -z "$DETECTED_ASSETS_ID" ] || [ -z "$DETECTED_JAR_ID" ]; then
    echo " [!] ERROR: Resource ambiguity. One file MUST contain 'Asset' in its name."
    exit 1
fi

# ------------------------------------------------------------------------------
# [5] REINSTALLATION LOGIC (UPDATE MODE)
#    If the --u flag is active, wipe existing local copies to ensure fresh data.
# ------------------------------------------------------------------------------
if [ "$UPDATE_MODE" = true ]; then
    echo " [⚡] Phase 3: Update flag detected. Purging local binaries..."
    rm -f Assets.zip HytaleServer.jar
fi

# ------------------------------------------------------------------------------
# [6] DATA ACQUISITION
#    Retrieves the binary files from PixelDrain if not present locally.
# ------------------------------------------------------------------------------
if [ ! -f "Assets.zip" ]; then
    echo " [⚡] Phase 4: Fetching Assets.zip..."
    # -L: Follow redirects (crucial for PD), -o: Output file
    curl -L -o Assets.zip "https://pixeldrain.com/api/file/${DETECTED_ASSETS_ID}"
else
    echo " [✓] Resource Assets.zip already present. Skipping download."
fi

if [ ! -f "HytaleServer.jar" ]; then
    echo " [⚡] Phase 5: Fetching HytaleServer.jar..."
    curl -L -o HytaleServer.jar "https://pixeldrain.com/api/file/${DETECTED_JAR_ID}"
    chmod +x HytaleServer.jar
else
    echo " [✓] Resource HytaleServer.jar already present. Skipping download."
fi

# ------------------------------------------------------------------------------
# [7] SERVER STARTUP
#    Executes the Java Virtual Machine with defined assets and network binding.
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------"
echo "        DEPLOYMENT COMPLETE - STARTING HYTALE          "
echo "-------------------------------------------------------"
echo " [>] Network Bind: 0.0.0.0:$PORT"
echo "-------------------------------------------------------"

java -jar HytaleServer.jar --assets Assets.zip --bind 0.0.0.0:$PORT
