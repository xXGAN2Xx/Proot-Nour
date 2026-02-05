#!/bin/bash
set -e

# Define URLs
ASSETS_URL="https://craftbytehosting.xyz/Assets.zip"
SERVER_URL="https://craftbytehosting.xyz/ServerFiles.zip"
PATCHER_URL="https://patcher.authbp.xyz/download/patched_release"

echo "-----------------------------------------"
echo "   Hytale Server Manager (Debian Mode)   "
echo "   Target: $(pwd)   "
echo "-----------------------------------------"

# Check if HytaleServer.jar already exists
if [ -f "HytaleServer.jar" ] && [ -f "start.sh" ]; then
    echo "[!] HytaleServer.jar found. Skipping installation steps..."
else
    echo "[+] Installation required. Starting setup..."

    # Install dependencies (Debian/Ubuntu)
    echo "Installing dependencies..."
    apt-get update -y
    apt-get install -y wget unzip ca-certificates openjdk-25-jre uuid-runtime curl

    # Download Assets.zip (do not extract)
    echo "Downloading Assets.zip..."
    rm -f Assets.zip
    wget -O Assets.zip "${ASSETS_URL}"
    echo "Assets.zip downloaded."

    # Download ServerFiles.zip (extract this one)
    echo "Downloading ServerFiles.zip..."
    rm -f ServerFiles.zip
    wget -O ServerFiles.zip "${SERVER_URL}"

    # Test integrity and extract
    echo "Extracting ServerFiles.zip..."
    unzip -o ServerFiles.zip -d .

    # Flatten top-level folder if the zip contains a single root folder
    TOP_DIR=$(unzip -Z1 ServerFiles.zip | head -n1 | cut -d/ -f1)
    if [ -n "$TOP_DIR" ] && [ -d "$TOP_DIR" ] && [ "$TOP_DIR" != "." ]; then
        echo "Flattening directory structure from $TOP_DIR..."
        mv "$TOP_DIR"/* . 2>/dev/null || true
        mv "$TOP_DIR"/.* . 2>/dev/null || true
        rm -rf "$TOP_DIR"
    fi
    rm -f ServerFiles.zip

    # Download HytaleServer.jar into the Server folder temporarily
    echo "Downloading HytaleServer.jar..."
    mkdir -p Server
    wget -O Server/HytaleServer.jar "${PATCHER_URL}"

    # Move HytaleServer.jar to root and cleanup
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
# Standalone script to fetch F2P server tokens and start Hytale server
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
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
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

    # Set permissions
    echo "Setting executable permissions (chmod +x)..."
    chmod -R +x .
    echo "-----------------------------------------"
    echo "           Install Complete              "
    echo "-----------------------------------------"
fi

# Always attempt to start the server at the end
echo "[>] Launching start_server.sh..."
./start.sh
