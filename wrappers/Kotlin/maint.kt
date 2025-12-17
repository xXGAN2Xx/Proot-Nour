import java.io.File
import java.io.IOException
import java.net.URI
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import kotlin.system.exitProcess

// Updated local file name to nourt.sh
const val LOCAL_SCRIPT_NAME = "nourt.sh"
const val REMOTE_SCRIPT_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh"

fun main() {
    println("Done (s)! For help, type help")

    try {
        val scriptFile = File(LOCAL_SCRIPT_NAME)

        // 1. Check if file exists
        if (scriptFile.exists()) {
            // 2a. If exists: Skip download, just run it
            println("'$LOCAL_SCRIPT_NAME' found locally. Skipping download.")
            runScript(scriptFile)
        } else {
            // 2b. If does not exist: Download -> Chmod +x -> Run
            println("'$LOCAL_SCRIPT_NAME' not found locally. Downloading...")
            val downloadedFile = downloadAndSetPermissions(REMOTE_SCRIPT_URL, LOCAL_SCRIPT_NAME)
            
            if (downloadedFile != null) {
                println("Download and permissions setup complete. Running script...")
                runScript(downloadedFile)
            } else {
                println("Failed to download or set permissions for '$LOCAL_SCRIPT_NAME'.")
            }
        }

    } catch (e: Exception) {
        println("An unexpected error occurred in main: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadAndSetPermissions(urlStr: String, fileName: String): File? {
    val url = runCatching { URI(urlStr).toURL() }.getOrNull()
    if (url == null) {
        println("Error: Invalid URL: $urlStr")
        return null
    }

    val destination = File(fileName)

    // Download
    try {
        downloadFile(url, destination)
        println("Downloaded '$fileName'.")
    } catch (e: Exception) {
        println("Error downloading '$fileName': ${e.message}")
        return null
    }

    // Chmod +x
    if (!setExecutablePermission(destination)) {
        println("Failed to set executable permissions on '$fileName'.")
        return null
    }

    return destination
}

fun setExecutablePermission(file: File): Boolean {
    println("Setting 'chmod +x' on '${file.name}'...")
    try {
        val process = ProcessBuilder("chmod", "+x", file.absolutePath).start()
        val exitCode = process.waitFor()
        return if (exitCode == 0) {
            println("Permissions set successfully.")
            true
        } else {
            println("chmod failed with exit code $exitCode.")
            false
        }
    } catch (e: Exception) {
        println("Exception running chmod: ${e.message}")
        return false
    }
}

fun runScript(file: File) {
    // Final check before execution
    if (!file.exists() || !file.canExecute()) {
        // Try to fix permissions one last time if file exists but isn't executable
        if (file.exists()) setExecutablePermission(file)
        
        if (!file.canExecute()) {
            println("Cannot run '${file.name}': File missing or not executable.")
            return
        }
    }

    println("Executing '${file.name}'...")
    try {
        val process = ProcessBuilder("bash", file.absolutePath)
            .inheritIO()
            .start()
        
        val exitCode = process.waitFor()
        println("'${file.name}' finished with exit code $exitCode.")

        if (exitCode == 0) {
            exitProcess(0)
        }
    } catch (e: Exception) {
        println("Error running script: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: java.net.URL, destination: File) {
    val tempFile = Files.createTempFile(destination.parentFile?.toPath() ?: Paths.get("."), destination.name, ".tmp").toFile()
    try {
        url.openStream().use { input ->
            Files.copy(input, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    } catch (e: Exception) {
        tempFile.delete()
        throw IOException("Download failed: ${e.message}", e)
    } finally {
        if (tempFile.exists()) tempFile.delete()
    }
}
