#!/usr/bin/env kotlin

@file:DependsOn("org.jetbrains.kotlin:kotlin-script-util:1.9.22") // Or your Kotlin version

import java.io.File
import java.lang.ProcessBuilder.Redirect
import kotlin.system.exitProcess

// --- Configuration ---
val INSTALL_DIR_NAME = "debian-proot"
val ROOTFS_DIR_NAME = "debian-rootfs"
val PROOT_BIN_NAME = "proot"
val START_SCRIPT_NAME = "start-debian.sh"
val DEBIAN_VERSION = "bookworm" // Or "bullseye", "sid", etc.

// URLs - Using Termux PRoot (static) and Debian base images
// Check for latest versions if needed
val PROOT_URL_AMD64 = "https://github.com/termux/proot/releases/download/v5.4.0/proot-v5.4.0-x86_64-static"
val PROOT_URL_ARM64 = "https://github.com/termux/proot/releases/download/v5.4.0/proot-v5.4.0-aarch64-static"
// Using images.linuxcontainers.org - check for availability and structure
val ROOTFS_BASE_URL = "https://images.linuxcontainers.org/images/debian/${DEBIAN_VERSION}"
// Example: https://images.linuxcontainers.org/images/debian/bookworm/amd64/default/latest/rootfs.tar.xz

val REQUIRED_COMMANDS = listOf("wget", "tar", "chmod", "uname", "mkdir")
// --- End Configuration ---

data class ArchInfo(val kernelArch: String, val prootUrl: String, val rootfsArch: String)

/**
 * Runs a shell command and waits for it to complete.
 * Inherits IO streams for user visibility.
 * Throws RuntimeException if the command fails.
 */
fun runCommand(vararg command: String, workDir: File? = null): Int {
    println("--- Running command: ${command.joinToString(" ")} ${if (workDir != null) "in ${workDir.path}" else ""}")
    try {
        val process = ProcessBuilder(*command)
            .directory(workDir ?: File("."))
            .redirectOutput(Redirect.INHERIT)
            .redirectError(Redirect.INHERIT)
            .start()
        val exitCode = process.waitFor()
        if (exitCode != 0) {
            System.err.println("--- Command failed with exit code $exitCode: ${command.joinToString(" ")}")
        } else {
            println("--- Command finished successfully.")
        }
        return exitCode
    } catch (e: Exception) {
        System.err.println("--- Failed to execute command: ${command.joinToString(" ")}")
        e.printStackTrace()
        return -1 // Indicate failure
    }
}

/** Checks if a command exists in PATH */
fun commandExists(command: String): Boolean {
    return runCommand("which", command) == 0
}

/** Detects architecture */
fun getArchitecture(): ArchInfo? {
    println("--- Detecting system architecture...")
    val process = ProcessBuilder("uname", "-m")
        .redirectOutput(Redirect.PIPE)
        .redirectError(Redirect.PIPE)
        .start()
    val output = process.inputStream.bufferedReader().readText().trim()
    val exitCode = process.waitFor()

    if (exitCode != 0) {
        System.err.println("--- Failed to detect architecture using 'uname -m'.")
        return null
    }

    println("--- Detected kernel architecture: $output")
    return when (output) {
        "x86_64" -> ArchInfo(output, PROOT_URL_AMD64, "amd64")
        "aarch64" -> ArchInfo(output, PROOT_URL_ARM64, "arm64")
        else -> {
            System.err.println("--- Unsupported architecture: $output. Only x86_64 (amd64) and aarch64 (arm64) are directly supported by this script.")
            null
        }
    }
}

/** Downloads a file using wget */
fun downloadFile(url: String, outputFile: File): Boolean {
    println("--- Downloading $url to ${outputFile.path}")
    // Use -q for quiet, --show-progress for progress, -O for output file
    val exitCode = runCommand("wget", "-q", "--show-progress", "-O", outputFile.absolutePath, url)
    return exitCode == 0
}

/** Creates the start script */
fun createStartScript(baseDir: File, prootPath: String, rootfsPath: String) {
    val scriptFile = File(baseDir, START_SCRIPT_NAME)
    println("--- Creating start script: ${scriptFile.path}")
    val scriptContent = """
    #!/bin/bash
    # Script to start the Debian PRoot environment

    # Get the directory where the script is located
    SCRIPT_DIR="${'$'}( cd -- "$( dirname -- "${'$'}{BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

    # Define paths relative to the script directory
    PROOT_BIN="${'$'}SCRIPT_DIR/$PROOT_BIN_NAME"
    ROOTFS_DIR="${'$'}SCRIPT_DIR/$ROOTFS_DIR_NAME"

    # Ensure PRoot binary is executable
    if [ ! -x "${'$'}PROOT_BIN" ]; then
        echo "Error: PRoot binary not found or not executable at ${'$'}PROOT_BIN"
        exit 1
    fi

    # Ensure rootfs directory exists
    if [ ! -d "${'$'}ROOTFS_DIR" ]; then
        echo "Error: Debian rootfs directory not found at ${'$'}ROOTFS_DIR"
        exit 1
    fi

    echo "--- Starting Debian ($DEBIAN_VERSION) PRoot environment ---"
    echo "--- Type 'exit' to return to the Pterodactyl container shell ---"

    # Unset Pterodactyl/Wine specific variables that might interfere
    unset LD_PRELOAD LD_LIBRARY_PATH WINEPREFIX WINESERVER WINEARCH WINEDEBUG

    # Execute PRoot
    "${'$'}PROOT_BIN" \
        -0 \
        -r "${'$'}ROOTFS_DIR" \
        -b /dev \
        -b /proc \
        -b /sys \
        -b /etc/resolv.conf:/etc/resolv.conf \
        -b /etc/hosts:/etc/hosts \
        -b /tmp \
        -b "${'$'}HOME":"/root/host_home" \
        -w /root \
        /usr/bin/env -i \
        HOME=/root \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TERM="${'$'}TERM" \
        LANG=C.UTF-8 \
        /bin/bash --login

    echo "--- Exited Debian PRoot environment ---"

    """.trimIndent()

    try {
        scriptFile.writeText(scriptContent)
        if (runCommand("chmod", "+x", scriptFile.absolutePath) != 0) {
            System.err.println("--- Failed to make start script executable.")
        } else {
            println("--- Start script created and made executable.")
        }
    } catch (e: Exception) {
        System.err.println("--- Failed to write start script: ${scriptFile.path}")
        e.printStackTrace()
    }
}

// --- Main Script Logic ---
println("--- Starting Debian PRoot Setup Script ---")

// 1. Check Dependencies
println("--- Checking required commands...")
val missingCommands = REQUIRED
