#!/bin/bash
set -e

# -------------------------------------------------------------------------
# ARGUMENT PARSING
# Usage: ./script.sh [ID1] [ID2] [--bind IP:PORT] [--name "Server Name"]
# -------------------------------------------------------------------------

# Defaults
BIND_ARG="0.0.0.0:5520"
SERVER_NAME_ARG="My Hytale Server"
PIXELDRAIN_IDS=()

# Loop through all arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bind)
            BIND_ARG="$2"
            shift 2
            ;;
        --name)
            SERVER_NAME_ARG="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1"
            exit 1
            ;;
        *)
            # If it's not a flag, it's a PixelDrain ID
            PIXELDRAIN_IDS+=("$1")
            shift
            ;;
    esac
done

# Patcher URL
PATCHER_URL="https://patcher.authbp.xyz/download/patched_release"

echo "-----------------------------------------"
echo "   Hytale Server Manager (Debian Mode)   "
echo "   Source: PixelDrain                    "
echo "   Bind Address: $BIND_ARG               "
echo "   Server Name:  $SERVER_NAME_ARG        "
echo "   Input IDs:    ${PIXELDRAIN_IDS[*]}    "
echo "   Target: $(pwd)                        "
echo "-----------------------------------------"

# Check if HytaleServer.jar already exists
if [ -f "HytaleServer.jar" ] && [ -f "start.sh" ]; then
    echo "[!] HytaleServer.jar found. Skipping installation steps..."
else
    echo "[+] Installation required. Starting setup..."

    # Check if we have at least 1 ID (We need 2, but logic below handles detection)
    if [ ${#PIXELDRAIN_IDS[@]} -eq 0 ]; then
        echo "Error: No PixelDrain IDs provided."
        echo "Usage: curl ... | bash -s -- <AssetsID> <ServerID> --bind 0.0.0.0:3090"
        exit 1
    fi

    # Install dependencies
    echo "Installing dependencies..."
    apt-get update -y
    apt-get install -y wget unzip ca-certificates openjdk-25-jre uuid-runtime curl

    # -----------------------------------------------------------------
    # ID IDENTIFICATION LOGIC
    # -----------------------------------------------------------------
    echo "Resolving PixelDrain IDs..."

    DETECTED_ASSETS_ID=""
    DETECTED_SERVER_ID=""

    for id in "${PIXELDRAIN_IDS[@]}"; do
        # Clean ID (remove colons/commas if user pasted them weirdly)
        clean_id=$(echo "$id" | tr -d ':,')
        
        # Fetch file info from API
        FILE_NAME=$(wget -qO- --user-agent="Mozilla/5.0" "https://pixeldrain.com/api/file/${clean_id}/info" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        
        echo " -> ID: $clean_id | Name: $FILE_NAME"

        if echo "$FILE_NAME" | grep -iq "Asset"; then
            DETECTED_ASSETS_ID="$clean_id"
        else
            DETECTED_SERVER_ID="$clean_id"
        fi
    done

    # -----------------------------------------------------------------
    # VALIDATION
    # -----------------------------------------------------------------
    if [ -z "$DETECTED_ASSETS_ID" ]; then
        echo "Error: Could not identify an Assets ID."
        exit 1
    fi

    if [ -z "$DETECTED_SERVER_ID" ]; then
        echo "Error: Could not identify a Server Files ID."
        exit 1
    fi

    echo " -> Selected Assets ID: $DETECTED_ASSETS_ID"
    echo " -> Selected Server ID: $DETECTED_SERVER_ID"

    # -----------------------------------------------------------------
    # DOWNLOAD ASSETS
    # -----------------------------------------------------------------
    echo "Downloading Assets.zip..."
    rm -f Assets.zip
    wget -O Assets.zip "https://pixeldrain.com/api/file/${DETECTED_ASSETS_ID}"
    
    if [ ! -s Assets.zip ]; then
        echo "Error: Assets.zip download failed."
        exit 1
    fi

    # -----------------------------------------------------------------
    # DOWNLOAD SERVER FILES
    # -----------------------------------------------------------------
    echo "Downloading ServerFiles.zip..."
    rm -f ServerFiles.zip
    wget -O ServerFiles.zip "https://pixeldrain.com/api/file/${DETECTED_SERVER_ID}"

    if [ ! -s ServerFiles.zip ]; then
        echo "Error: ServerFiles.zip download failed."
        exit 1
    fi

    # Extract
    echo "Extracting ServerFiles.zip..."
    unzip -o ServerFiles.zip -d .

    # Flatten top-level folder
    TOP_DIR=$(unzip -Z1 ServerFiles.zip | head -n1 | cut -d/ -f1)
    if [ -n "$TOP_DIR" ] && [ -d "$TOP_DIR" ] && [ "$TOP_DIR" != "." ]; then
        echo "Flattening directory structure from $TOP_DIR..."
        mv "$TOP_DIR"/* . 2>/dev/null || true
        mv "$TOP_DIR"/.* . 2>/dev/null || true
        rm -rf "$TOP_DIR"
    fi
    rm -f ServerFiles.zip

    # -----------------------------------------------------------------
    # DOWNLOAD JAR
    # -----------------------------------------------------------------
    echo "Downloading HytaleServer.jar..."
    mkdir -p Server
    wget -O Server/HytaleServer.jar "${PATCHER_URL}"

    rm -f HytaleServer.jar
    if [ -f "Server/HytaleServer.jar" ]; then
        mv Server/HytaleServer.jar .
    else
        echo "Error: HytaleServer.jar download failed."
        exit 1
    fi

    # Create start.sh with the CUSTOM BIND ADDRESS
    echo "Creating start_server.sh..."
    
    # We use the variables captured at the top of the script here
    cat << EOF > start.sh
#!/bin/bash
set -e

# Configuration
HYTALE_AUTH_DOMAIN="\${HYTALE_AUTH_DOMAIN:-auth.sanasol.ws}"
AUTH_SERVER="\${AUTH_SERVER:-https://\${HYTALE_AUTH_DOMAIN}}"
SERVER_NAME="${SERVER_NAME_ARG}"
ASSETS_PATH="\${ASSETS_PATH:-./Assets.zip}"
BIND_ADDRESS="${BIND_ARG}"
AUTH_MODE="\${AUTH_MODE:-authenticated}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "\${GREEN}[INFO]\${NC} \$*"; }
error() { echo -e "\${RED}[ERROR]\${NC} \$*" >&2; }

if [ ! -f "HytaleServer.jar" ]; then
    error "HytaleServer.jar not found!"; exit 1
fi

# Generate or load server ID
SERVER_ID_FILE=".server-id"
if [ -f "\${SERVER_ID_FILE}" ]; then
    SERVER_ID=\$(cat "\${SERVER_ID_FILE}")
    log "Using existing server ID: \${SERVER_ID}"
else
    SERVER_ID=\$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "server-\$(date +%s)")
    echo -n "\${SERVER_ID}" > "\${SERVER_ID_FILE}"
    log "Generated new server ID: \${SERVER_ID}"
fi

log "Fetching server tokens from \${AUTH_SERVER}..."
RESPONSE=\$(curl -s -X POST "\${AUTH_SERVER}/server/auto-auth" \
    -H "Content-Type: application/json" \
    -d "{\"server_id\": \"\${SERVER_ID}\", \"server_name\": \"\${SERVER_NAME}\"}" \
    --connect-timeout 10 \
    --max-time 30) || {
    error "Failed to connect to auth server"; exit 1
}

if ! echo "\${RESPONSE}" | grep -q "sessionToken"; then
    error "Invalid response from auth server"; echo "\${RESPONSE}"; exit 1
fi

SESSION_TOKEN=\$(echo "\${RESPONSE}" | sed -n 's/.*"sessionToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
IDENTITY_TOKEN=\$(echo "\${RESPONSE}" | sed -n 's/.*"identityToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

log "Starting Hytale Server on ${BIND_ARG}..."
exec java -jar HytaleServer.jar \
    --assets "\${ASSETS_PATH}" \
    --bind "\${BIND_ADDRESS}" \
    --auth-mode "\${AUTH_MODE}" \
    --session-token "\${SESSION_TOKEN}" \
    --identity-token "\${IDENTITY_TOKEN}" \
    "\$@"
EOF

    chmod -R +x .
    echo "-----------------------------------------"
    echo "           Install Complete              "
    echo "-----------------------------------------"
fi

echo "[>] Launching start_server.sh..."
./start.sh
