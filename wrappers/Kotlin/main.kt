import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.io.IOException

// Define constants for the nour script
const val NOUR_SCRIPT_NAME = "nour.sh"
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nour.sh"

fun main() {
    // Message to show immediately when the JAR is executed
    println("Done (s)! For help, type help")

    try {
        // Try to handle the script if it exists locally.
        // handleScript returns true if the file was found, false otherwise.
        val wasHandled = handleScript(NOUR_SCRIPT_NAME, NOUR_URL)

        // If the script was not found locally, download it.
        if (!wasHandled) {
            println("'$NOUR_SCRIPT_NAME' not found locally. Attempting to download...")
            val downloadedFile = downloadAndSetPermissions(NOUR_URL, NOUR_SCRIPT_NAME)

            if (downloadedFile != null) {
                // If download and permissions were successful, run the script.
                println("Preparing to run downloaded '${downloadedFile.name}'...")
                runScript(downloadedFile)
            } else {
                // Handle the case where the download or permission setting failed.
                println("Failed to download or set permissions for '$NOUR_SCRIPT_NAME'. The script cannot be run.")
            }
        }

    } catch (e: Exception) {
        println("An unexpected error occurred in main: ${e.message}")
        e.printStackTrace()
    }
}

/**
 * Handles an existing script file: checks for updates, sets permissions, and runs it.
 * Returns true if the script file existed, false otherwise.
 */
fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)
    if (!scriptFile.exists()) {
        // If the script doesn't exist, report back to main so it can be downloaded.
        return false
    }

    var fileToExecute: File? = null
    var wasSuccessfullyUpdated = false      // True if downloaded AND permissions set successfully
    var isUpToDateAndSkippingPermSet = false // True if file is up-to-date and we can skip chmod

    println("Found '${scriptFile.name}'. Checking for updates...")
    if (isFileChanged(scriptFile, scriptUrl)) { // File changed or error during check
        println("'${scriptFile.name}' has changed. Attempting to download the new version...")
        val updatedFile = downloadAndSetPermissions(scriptUrl, scriptName)
        if (updatedFile != null) {
            fileToExecute = updatedFile
            wasSuccessfullyUpdated = true // Permissions handled by download function
            println("Successfully updated '${scriptFile.name}'.")
        } else {
            println("Failed to update '${scriptFile.name}'. Will attempt to run the existing local version.")
            fileToExecute = scriptFile // Fallback to existing local version
        }
    } else { // File is up to date
        println("'${scriptFile.name}' is up to date.")
        fileToExecute = scriptFile
        isUpToDateAndSkippingPermSet = true // Mark to skip explicit chmod
    }

    if (fileToExecute != null) {
        var canRun = false

        if (wasSuccessfullyUpdated) {
            // Permissions were set by downloadAndSetPermissions.
            if (fileToExecute.canExecute()) {
                println("Permissions for updated '${fileToExecute.name}' were set during download.")
                canRun = true
            } else {
                println("Error: Updated file '${fileToExecute.name}' is not executable despite successful update.")
            }
        } else if (isUpToDateAndSkippingPermSet) {
            // For up-to-date files, check if already executable.
            if (fileToExecute.canExecute()) {
                println("'${fileToExecute.name}' is already executable.")
                canRun = true
            } else {
                println("Warning: Up-to-date file '${fileToExecute.name}' is NOT executable. Attempting to set permissions...")
                if (setExecutablePermission(fileToExecute) && fileToExecute.canExecute()) {
                    canRun = true
                } else {
                    println("Failed to make the up-to-date file executable. Script will not be run.")
                }
            }
        } else {
            // Fallback case (e.g., update failed). We must try to set permissions.
            println("Attempting to set/verify permissions for '${fileToExecute.name}'...")
            if (setExecutablePermission(fileToExecute) && fileToExecute.canExecute()) {
                println("Permissions set successfully for '${fileToExecute.name}'.")
                canRun = true
            } else {
                println("Failed to set executable permission for '${fileToExecute.name}'.")
            }
        }

        if (canRun) {
            println("Preparing to run '${fileToExecute.name}'...")
            runScript(fileToExecute)
        } else {
            println("Script '${fileToExecute.name}' will not be run due to permission issues.")
        }
    }
    // Return true because the script file was found and processed.
    return true
}

/**
 * Compares the content of a local file with a remote URL.
 */
fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    println("Comparing local '${localFile.name}' with remote content...")
    try {
        val remoteContent = URL(remoteUrl).readText(Charsets.UTF_8)
        val localContent = localFile.readText(Charsets.UTF_8)
        val changed = remoteContent != localContent
        if (changed) {
            println("Contents differ for '${localFile.name}'.")
        } else {
            println("Contents are the same for '${localFile.name}'.")
        }
        return changed
    } catch (e: IOException) {
        println("IOException during comparison for '${localFile.name}': ${e.message}. Assuming it has changed to be safe.")
        return true
    } catch (e: Exception) {
        println("Unexpected error comparing file '${localFile.name}' with remote: ${e.message}. Assuming it has changed.")
        e.printStackTrace()
        return true
    }
}

/**
 * Downloads a file from a URL and sets executable permission.
 * Returns the File object on success, or null on failure.
 */
fun downloadAndSetPermissions(scriptUrlString: String, scriptFileName: String): File? {
    val destinationFile = File(scriptFileName)

    println("Downloading '$scriptFileName' from $scriptUrlString...")
    try {
        downloadFile(URL(scriptUrlString), destinationFile)
        println("Download completed for '$scriptFileName'.")
    } catch (e: Exception) {
        println("Error downloading '$scriptFileName': ${e.message}")
        e.printStackTrace()
        return null
    }

    // Set permissions after a successful download.
    if (!setExecutablePermission(destinationFile)) {
        println("Download of '$scriptFileName' succeeded but setting permissions failed.")
        return null // Overall operation failed if chmod fails.
    }
    
    println("Successfully downloaded and set permissions for '$scriptFileName'.")
    return destinationFile
}

/**
 * Sets executable permission (+x) on a given file using chmod.
 */
fun setExecutablePermission(file: File): Boolean {
    if (!file.exists()) {
        println("Cannot set permissions: File '${file.name}' does not exist.")
        return false
    }
    
    println("Setting executable permission on '${file.name}'...")
    try {
        val chmod = ProcessBuilder("chmod", "+x", file.absolutePath)
        val chmodProcess = chmod.start()
        val chmodExitCode = chmodProcess.waitFor()

        if (chmodExitCode != 0) {
            val errorOutput = chmodProcess.errorStream.bufferedReader().readText().trim()
            println("Error setting executable permission for '${file.name}' (chmod exit code: $chmodExitCode).")
            if (errorOutput.isNotEmpty()) println("chmod stderr: $errorOutput")
            return false
        } else {
            println("Executable permission set successfully for '${file.name}'.")
            return true
        }
    } catch (e: IOException) {
        println("IOException while trying to run chmod for '${file.name}': ${e.message}")
        e.printStackTrace()
        return false
    } catch (e: InterruptedException) {
        println("Process 'chmod' for '${file.name}' was interrupted: ${e.message}")
        Thread.currentThread().interrupt()
        return false
    }
}


/**
 * Runs a given script file using bash.
 */
fun runScript(scriptFile: File) {
    if (!scriptFile.exists()) {
        println("Cannot run script: '${scriptFile.name}' does not exist.")
        return
    }
    if (!scriptFile.canExecute()) {
        println("Cannot run script: '${scriptFile.name}' is not executable.")
        return
    }

    println("Running '${scriptFile.name}' and waiting for it to complete...")
    try {
        val processBuilder = ProcessBuilder("bash", scriptFile.absolutePath).inheritIO()
        val process = processBuilder.start()
        val exitCode = process.waitFor()
        println("'${scriptFile.name}' finished with exit code $exitCode.")
    } catch (e: IOException) {
        println("IOException while trying to run script '${scriptFile.name}': ${e.message}")
        e.printStackTrace()
    } catch (e: InterruptedException) {
        println("Script execution for '${scriptFile.name}' was interrupted: ${e.message}")
        Thread.currentThread().interrupt()
    }
}

/**
 * Downloads content from a URL to a destination file atomically.
 */
fun downloadFile(url: URL, destination: File) {
    val tempFile = Files.createTempFile(destination.parentFile?.toPath() ?: Paths.get("."), destination.name, ".tmp").toFile()
    try {
        url.openStream().use { inputStream ->
            Files.copy(inputStream, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    } catch (e: Exception) {
        // Clean up the temporary file on failure.
        if (tempFile.exists()) {
            tempFile.delete()
        }
        throw IOException("Failed to download or replace file '${destination.name}' from $url: ${e.message}", e)
    }
}
