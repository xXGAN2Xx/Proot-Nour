#!/usr/bin/env kotlin

@file:DependsOn("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3") // Example dependency if needed, remove if not

import java.io.File
import java.io.IOException
import java.net.URL
import java.util.concurrent.TimeUnit
import kotlin.system.exitProcess

// --- Configuration ---
val INSTALL_DIR = File(System.getProperty("user.home"), ".debian-proot")
val ROOTFS_DIR = File(INSTALL_DIR, "rootfs")
val PROOT_BIN_DIR = File(INSTALL_DIR, "bin")
val PROOT_BINARY = File(PROOT_BIN_DIR, "proot")
val START_SCRIPT = File(System.getProperty("user.home"), "start-debian.sh") // Convenience script

// Termux provides static PRoot binaries and rootfs
const val PROOT_BASE_URL = "https://github.com/termux/proot/releases/download/v5.4.0/" // Check for latest version
const val ROOTFS_BASE_URL = "https://github.com/termux/proot-distro/releases/download/v3.16.0/" // Check for latest version
const val DEBIAN_ROOTFS_FILENAME_PATTERN = "debian-%s-pd-v%s.tar.xz"
const val DEBIAN_ROOTFS_VERSION = "3.16.0" // Match proot-distro release

// --- Helper Functions ---

/** Executes a shell command and waits for it to complete. */
fun runCommand(vararg command: String, workingDir: File? = null, inheritIO: Boolean = true): Int {
    println("Executing: ${command.joinToString(" ")}")
    try {
        val processBuilder = ProcessBuilder(*command)
            .directory(workingDir ?: File("."))
        if (inheritIO) {
            processBuilder.inheritIO()
        } else {
            processBuilder.redirectErrorStream(true) // Merge stdout and stderr
            // If not inheriting IO, you might want to capture output here
        }

        val process = processBuilder.start()
        val exited = process.waitFor(10, TimeUnit.MINUTES) // Set a timeout (e.g., 10 minutes)

        if (!exited) {
            println("Warning: Command '${command.first()}' timed out. Attempting to destroy...")
            process.destroyForcibly()
            return -1 // Indicate timeout
        }
        val exitCode = process.exitValue()
        println("Command finished with exit code: $exitCode")
        return exitCode
    } catch (e: IOException) {
        println("Error executing command: ${command.joinToString(" ")}")
        e.printStackTrace()
        return -1
    } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
        println("Command execution interrupted: ${command.joinToString(" ")}")
        e.printStackTrace()
        return -1
    }
}

/** Downloads a file from a URL to a destination file. */
fun downloadFile(url: String, destination: File) {
    println("Downloading $url to ${destination.absolutePath}")
    destination.parentFile?.mkdirs()
    // Use curl or wget as they handle redirects and are common
    val command = if (isCommandAvailable("curl")) {
        arrayOf("curl", "-L", "-o", destination.absolutePath, url)
    } else if (isCommandAvailable("wget")) {
        arrayOf("wget", "-O", destination.absolutePath, url)
    } else {
        println("Error: Neither curl nor wget found. Cannot download files.")
        exitProcess(1)
    }

    if (runCommand(*command, inheritIO = false) != 0) { // Don't inherit IO for cleaner download output
        println("Error: Failed to download $url")
        destination.delete() // Clean up partial download
        exitProcess(1)
    }
    println("Download complete.")
}

/** Checks if a command exists in the system PATH. */
fun isCommandAvailable(command: String): Boolean {
    return runCommand("sh", "-c", "command -v $command", inheritIO = false) == 0
}

/** Detects the system architecture. */
fun getArch(): String {
    val process = ProcessBuilder("uname", "-m").start()
    val arch = process.inputStream.bufferedReader().readText().trim()
    process.waitFor()
    return when (arch) {
        "x86_64" -> "x86_64"
        "aarch64" -> "aarch64"
        "armv7l", "armv8l", "arm" -> "arm" // Termux often uses 'arm' for 32-bit ARM
        else -> {
            println("Error: Unsupported architecture '$arch'.")
            exitProcess(1)
            "" // Should not be reached
        }
    }
}

/** Creates the convenience start script. */
fun createStartScript(arch: String) {
    val scriptContent = """
    #!/bin/bash

    # Pterodactyl environment variables might be useful inside
    # Add more ENV_VAR_NAME=${'$'}ENV_VAR_NAME if needed
    PASS_ENV_VARS=""
    # Example: uncomment the following line to pass server IP and port
    # PASS_ENV_VARS="-e SERVER_IP=${'$'}SERVER_IP -e SERVER_PORT=${'$'}SERVER_PORT"

    # Uncomment variables you want to pass to proot
