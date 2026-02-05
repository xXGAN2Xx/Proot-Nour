#!/bin/bash
set -e

# -------------------------------------------------------------------------
# ARGUMENT PARSING
# Usage: ./script.sh ID1 ID2
# -------------------------------------------------------------------------

# Capture ALL arguments
INPUT_IDS="$@"

# Patcher URL
PATCHER_URL="https://patcher.authbp.xyz/download/patched_release"

echo "-----------------------------------------"
echo "   Hytale Server Manager (Debian Mode)   "
echo "   Source: PixelDrain                    "
echo "   Input: $INPUT_IDS                     "
echo "   Target: $(pwd)                        "
echo "-----------------------------------------"

# Check if HytaleServer.jar already exists
if [ -f "HytaleServer.jar" ] && [ -f "start.sh" ]; then
    echo "[!] HytaleServer.jar found. Skipping installation steps..."
else
    echo "[+] Installation required. Starting setup..."

    if [ -z "$INPUT_IDS" ]; then
        echo "Error: No PixelDrain IDs provided."
        echo "Usage: ./script.sh <AssetsID> <ServerID>"
        exit 1
    fi

    # Install dependencies (Debian/Ubuntu specific)
    echo "Installing dependencies..."
    apt-get update -y
    # Note: If openjdk-25-jre is not found, try changing it to openjdk-17-jre or default-jre
    apt-get install -y wget unzip ca-certificates openjdk-25-jre uuid-runtime curl

    # -----------------------------------------------------------------
    # ID IDENTIFICATION LOGIC
    # -----------------------------------------------------------------
    echo "Resolving PixelDrain IDs..."

    # Normalize input: replace colons/commas with spaces
    CLEAN_INPUT="${INPUT_IDS//[:]/ }"
    CLEAN_INPUT="${CLEAN_INPUT//[,]/ }"
    
    # Convert string to array
    read -ra ID_LIST <<< "$CLEAN_INPUT"

    # Initialize variables as empty
    DETECTED_ASSETS_ID=""
    DETECTED_SERVER_ID=""

    for id in "${ID_LIST[@]}"; do
        # Fetch file info from API to check the name
        # We use a User-Agent to ensure the API responds correctly
        FILE_NAME=$(wget -qO- --user-agent="Mozilla/5.0" "https://pixeldrain.com/api/file/${id}/info" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        
        echo " -> ID: $id | Name: $FILE_NAME"

        # Case-insensitive check for "Asset" in the filename
        if echo "$FILE_NAME" | grep -iq "Asset"; then
            DETECTED_ASSETS_ID="$id"
        else
            # Assume anything else is the server files
            DETECTED_SERVER_ID="$id"
        fi
    done

    # -----------------------------------------------------------------
    # VALIDATION (Exit if empty)
    # -----------------------------------------------------------------
    if [ -z "$DETECTED_ASSETS_ID" ]; then
        echo "Error: Could not identify an Assets ID from the provided arguments."
        exit 1
    fi

    if [ -z "$DETECTED_SERVER_ID" ]; then
        echo "Error: Could not identify a Server Files ID from the provided arguments."
        exit 1
    fi

    echo " -> Selected Assets ID: $DETECTED_ASSETS_ID"
    echo " -> Selected Server ID: $DETECTED_SERVER_ID"

    # -----------------------------------------------------------------
    # DOWNLOAD ASSETS
    # -----------------------------------------------------------------
    echo "Downloading Assets.zip ($DETECTED_ASSETS_ID)..."
    rm -f Assets.zip
    wget -O Assets.zip "https://pixeldrain.com/api/file/${DETECTED_ASSETS_ID}"
    
    if [ ! -s Assets.zip ]; then
        echo "Error: Assets.zip download failed or file is empty."
        exit 1
    fi

    # -----------------------------------------------------------------
    # DOWNLOAD SERVER FILES
    # -----------------------------------------------------------------
    echo "Downloading ServerFiles.zip ($DETECTED_SERVER_ID)..."
    rm -f ServerFiles.zip
    wget -O ServerFiles.zip "https://pixeldrain.com/api/file/${DETECTED_SERVER_ID}"

    if [ ! -s ServerFiles.zip ]; then
        echo "Error: ServerFiles.zip download failed or file is empty."
        exit 1
    fi

    # Test integrity and extract
    echo "Extracting ServerFiles.zip..."
    unzip -o ServerFiles.zip -d .

    # Flatten top-level folder if exists
    TOP_DIR=$(unzip -Z1 ServerFiles.zip | head -n1 | cut -d/ -f1)
    if [ -n "$TOP_DIR" ] && [ -d "$TOP_DIR" ] && [ "$TOP_DIR" != "." ]; then
        echo "Flattening directory structure from $TOP_DIR..."
        mv "$TOP_DIR"/* . 2>/dev/null || true
        mv "$TOP_DIR"/.* . 2>/dev/null || true
        rm -rf "$TOP_DIR"
    fi
    rm -f ServerFiles.zip

    # -----------------------------------------------------------------
    # DOWNLOAD JAR (Patcher)
    # -----------------------------------------------------------------
    echo "Downloading HytaleServer.jar..."
    mkdir -p Server
    wget -O Server/HytaleServer.jar "${PATCHER_URL}"

    echo "Finalizing HytaleServer.jar location..."
    rm -f HytaleServer.jar
    if [ -f "Server/HytaleServer.jar" ]; then
        mv Server/HytaleServer.jar .
    else
        echo "Error: HytaleServer.jar download failed."
        exit 1
    fi

    # Create the start_server.sh script
    echo "Creating start_server.sh..."
    cat << 'EOF' > start.sh
#!/bin/bash
set -e

# Configuration
HYTALE_AUTH_DOMAIN="${HYTALE_AUTH_DOMAIN:-auth.sanasol.ws}"
AUTH_SERVER="${AUTH_SERVER:-https://${HYTALE_AUTH_DOMAIN}}"
SERVER_NAME="${SERVER_NAME:-My Hytale Server}"
ASSETS_PATH="${ASSETS_PATH:-./Assets.zip}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0:5520}"
AUTH_MODE="${AUTH_MODE:-authenticated}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [ ! -f "HytaleServer.jar" ]; then
    error "HytaleServer.jar not found!"; exit 1
fi

if [ ! -f "${ASSETS_PATH}" ]; then
    error "Assets.zip not found at: ${ASSETS_PATH}"; exit 1
fi

# Generate or load server ID
SERVER_ID_FILE=".server-id"
if [ -f "${SERVER_ID_FILE}" ]; then
    SERVER_ID=$(cat "${SERVER_ID_FILE}")
    log "Using existing server ID: ${SERVER_ID}"
else
    SERVER_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "server-$(date +%s)")
    echo -n "${SERVER_ID}" > "${SERVER_ID_FILE}"
    log "Generated new server ID: ${SERVER_ID}"
fi

log "Fetching server tokens from ${AUTH_SERVER}..."
RESPONSE=$(curl -s -X POST "${AUTH_SERVER}/server/auto-auth" \
    -H "Content-Type: application/json" \
    -d "{\"server_id\": \"${SERVER_ID}\", \"server_name\": \"${SERVER_NAME}\"}" \
    --connect-timeout 10 \
    --max-time 30) || {
    error "Failed to connect to auth server"; exit 1
}

if ! echo "${RESPONSE}" | grep -q "sessionToken"; then
    error "Invalid response from auth server"; echo "${RESPONSE}"; exit 1
fi

SESSION_TOKEN=$(echo "${RESPONSE}" | sed -n 's/.*"sessionToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
IDENTITY_TOKEN=$(echo "${RESPONSE}" | sed -n 's/.*"identityToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

log "Starting Hytale Server..."
exec java -jar HytaleServer.jar \
    --assets "${ASSETS_PATH}" \
    --bind "${BIND_ADDRESS}" \
    --auth-mode "${AUTH_MODE}" \
    --session-token "${SESSION_TOKEN}" \
    --identity-token "${IDENTITY_TOKEN}" \
    "$@"
EOF

    chmod -R +x .
    echo "-----------------------------------------"
    echo "           Install Complete              "
    echo "-----------------------------------------"
fi

echo "[>] Launching start_server.sh..."
./start.sh
