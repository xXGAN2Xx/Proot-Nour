import java.io.File
import java.io.IOException
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption

const val NOUR_SCRIPT_NAME = "nour.sh"
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh"

fun main() {
    println("Done (s)! For help, type help")
    try {
        val scriptFile = File(NOUR_SCRIPT_NAME)
        var fileToRun: File? = scriptFile

        // Decide if a download is necessary: if the file doesn't exist OR it has changed remotely.
        val needsDownload = !scriptFile.exists() || isFileChanged(scriptFile, NOUR_URL)

        if (needsDownload) {
            println("Attempting to download '$NOUR_SCRIPT_NAME'...")
            if (!downloadFile(NOUR_URL, scriptFile)) { // If download fails
                println("Download failed.")
                // If the download failed and there was no pre-existing file, we can't run anything.
                if (!scriptFile.exists()) fileToRun = null
            }
        } else {
            println("'$NOUR_SCRIPT_NAME' is up to date.")
        }

        // Use let for a null-safe execution block
        fileToRun?.let { file ->
            // Ensure the file is executable before running
            if (setExecutablePermission(file)) {
                runScript(file)
            } else {
                println("Error: Could not make '${file.name}' executable. Script cannot be run.")
            }
        } ?: println("Error: No script file available to run.") // This runs if fileToRun is null

    } catch (e: Exception) {
        println("An unexpected error occurred: ${e.message}")
        e.printStackTrace()
    }
}

/**
 * Checks if a local file's content differs from a remote URL's content.
 * Assumes the file needs updating if any error occurs during the check.
 */
fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    print("Checking for updates for '${localFile.name}'...")
    return try {
        val remoteContent = URL(remoteUrl).readText()
        println(" Done.")
        remoteContent != localFile.readText()
    } catch (e: Exception) {
        println(" Error during check, assuming an update is needed.")
        true // Be safe and assume it changed on error
    }
}

/**
 * Downloads a file from a URL, replacing the destination file atomically.
 * Returns true on success, false on failure.
 */
fun downloadFile(urlString: String, destination: File): Boolean {
    return try {
        // Download to a temporary file first to prevent corruption
        val tempFile = Files.createTempFile(destination.parentFile.toPath(), "nour-", ".tmp").toFile()
        URL(urlString).openStream().use { input ->
            Files.copy(input, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        // Atomically move the temporary file to the final destination
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
        println("Download successful.")
        true
    } catch (e: Exception) {
        // Error is logged by the caller
        false
    }
}

/**
 * A general-purpose function to run an external command.
 * Returns true if the command exits with 0, false otherwise.
 */
private fun runCommand(vararg command: String): Boolean {
    return try {
        val process = ProcessBuilder(*command).inheritIO().start()
        process.waitFor() == 0 // Return true if exit code is 0
    } catch (e: IOException) {
        // Fail silently here; the calling function will print a more user-friendly error.
        false
    } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
        false
    }
}

/**
 * Sets the executable permission (+x) on a file.
 * We also check canExecute() before trying, though chmod is generally safe to run regardless.
 */
fun setExecutablePermission(file: File): Boolean {
    if (file.canExecute()) return true // Already executable
    println("Setting executable permission for '${file.name}'...")
    return runCommand("chmod", "+x", file.absolutePath)
}

/**
 * Runs the specified script file using "bash".
 */
fun runScript(scriptFile: File) {
    println("Running '${scriptFile.name}'...")
    runCommand("bash", scriptFile.absolutePath)
}
