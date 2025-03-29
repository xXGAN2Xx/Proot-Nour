import java.io.File
import java.io.IOException

fun main() {
    val scriptName = "install-debian.sh"

    // Bash script content
    val bashScript = """
        #!/bin/bash
        
        DEBIAN_ROOT=debian-fs
        DEBIAN_TARBALL=debian-rootfs.tar.gz
        ARCHITECTURE=$(uname -m)

        case "$ARCHITECTURE" in
            x86_64)
                ARCH="amd64"
                ;;
            aarch64)
                ARCH="arm64"
                ;;
            *)
                echo "Unsupported architecture: $ARCHITECTURE"
                exit 1
                ;;
        esac

        if ! command -v proot &> /dev/null; then
            echo "[INFO] Installing proot..."
            apt update && apt install -y proot
            if [ $? -ne 0 ]; then
                echo "[ERROR] Failed to install proot. Make sure you have network access and permissions."
                exit 1
            fi
        fi

        if [ ! -d "$DEBIAN_ROOT" ]; then
            echo "[INFO] Downloading Debian root filesystem for $ARCH..."
            wget https://raw.githubusercontent.com/proot-me/proot-distro/master/assets/debian/rootfs/${ARCH}/debian-rootfs.tar.gz -O $DEBIAN_TARBALL

            if [ $? -ne 0 ]; then
                echo "[ERROR] Failed to download Debian rootfs"
                exit 1
            fi

            echo "[INFO] Extracting root filesystem..."
            mkdir -p "$DEBIAN_ROOT"
            tar -xf "$DEBIAN_TARBALL" -C "$DEBIAN_ROOT"

            echo "[INFO] Cleaning up tarball..."
            rm -f "$DEBIAN_TARBALL"
        fi

        cat > start-debian.sh <<- EOM
        #!/bin/bash
        echo "[INFO] Entering Debian via proot..."
        proot \\
          --link2symlink \\
          -0 \\
          -r $DEBIAN_ROOT \\
          -b /dev \\
          -b /proc \\
          -b /sys \\
          -b /etc/resolv.conf \\
          -w /root \\
          /bin/bash --login
        EOM

        chmod +x start-debian.sh

        echo "[INFO] Setup complete."
        echo "Run ./start-debian.sh to enter the Debian environment."
    """.trimIndent()

    try {
        // Write script to file
        File(scriptName).writeText(bashScript)
        println("[Kotlin] Bash script '$scriptName' written successfully.")

        // Make it executable
        ProcessBuilder("chmod", "+x", scriptName)
            .inheritIO()
            .start()
            .waitFor()

        println("[Kotlin] Script made executable.")

        // Run the bash script
        val process = ProcessBuilder("./$scriptName")
            .inheritIO()  // Redirect output to console
            .start()

        val exitCode = process.waitFor()
        println("[Kotlin] Script finished with exit code $exitCode.")

    } catch (e: IOException) {
        e.printStackTrace()
    } catch (e: InterruptedException) {
        e.printStackTrace()
    }
}
