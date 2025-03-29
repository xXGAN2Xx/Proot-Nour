#!/bin/bash

# Variables
IMAGE_NAME="custom/debian12"
IMAGE_VERSION="latest"
FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_VERSION"
DOCKERFILE_DIR="./debian12_container"

echo "[*] Creating Dockerfile for Debian 12..."

# Create Dockerfile directory
mkdir -p "$DOCKERFILE_DIR"

# Create Dockerfile
cat > "$DOCKERFILE_DIR/Dockerfile" <<EOF
FROM debian:12

LABEL maintainer="Your Name <you@example.com>"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \\
    apt install -y curl nano iproute2 iputils-ping net-tools && \\
    apt clean

CMD ["/bin/bash"]
EOF

echo "[+] Dockerfile created at $DOCKERFILE_DIR/Dockerfile"

# Build Docker image
echo "[*] Building Docker image: $FULL_IMAGE_NAME"
docker build -t "$FULL_IMAGE_NAME" "$DOCKERFILE_DIR"

if [ $? -ne 0 ]; then
  echo "[!] Docker build failed!"
  exit 1
fi

echo "[+] Docker image $FULL_IMAGE_NAME built successfully."

# Ask user if they want to push to Docker Hub
read -p "Do you want to push this image to Docker Hub? (y/n): " push_confirm

if [[ "$push_confirm" == "y" ]]; then
  read -p "Enter your Docker Hub username: " docker_user
  docker tag "$FULL_IMAGE_NAME" "$docker_user/debian12-ptero:latest"
  docker push "$docker_user/debian12-ptero:latest"
  echo "[+] Image pushed as $docker_user/debian12-ptero:latest"
  IMAGE_FOR_PANEL="$docker_user/debian12-ptero:latest"
else
  echo "[!] Skipping push. You will need to load this image directly into the Pterodactyl daemon."
  IMAGE_FOR_PANEL="$FULL_IMAGE_NAME"
fi

echo ""
echo "======================================================"
echo "✅ Done! Next Steps for Pterodactyl Setup:"
echo "1. Go to your Pterodactyl Admin Panel."
echo "2. Create a new Egg or modify an existing one."
echo "3. In Docker Image field, use: $IMAGE_FOR_PANEL"
echo "4. Set startup command: /bin/bash or any server you want."
echo "5. Allocate ports if needed and assign to a node."
echo "6. Done!"
echo "======================================================"
