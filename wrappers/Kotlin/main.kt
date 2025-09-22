import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.io.IOException

// --- Configuration ---
// Defines the name of the script to be managed.
const val NOUR_SCRIPT_NAME = "nour.sh"
// Defines the authoritative URL from which to download or update the script.
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh"

/**
 * The main entry point of the application.
 * This launcher is designed to manage and run a shell script (`nour.sh`).
 * Its primary responsibilities are:
 * 1. Check if the script exists locally.
 * 2. If it exists, check for updates from a remote URL.
 * 3. If it doesn't exist or is outdated, download the latest version.
 * 4. Ensure the script has the necessary executable permissions.
 * 5. Execute the script.
 */
fun main() {
    // Greet the user immediately upon execution.
    println("Done (s)! For help, type help")

    try {
        // Attempt to find and process the script if it already exists locally.
        // This includes checking for updates and running it.
        // If handleScript returns true, the script was found and its execution path
        // (run or not run) was handled, so we can exit.
        if (handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return
        }

        // If handleScript returns false, the script was not found locally.
        // Proceed with the download process.
        println("'$NOUR_SCRIPT_NAME' not found locally. Attempting to download...")
        val downloadedFile = downloadAndSetPermissions(NOUR_URL, NOUR_SCRIPT_NAME)

        // If the download and permission setting were successful, run the script.
        if (downloadedFile != null) {
            println("Preparing to run downloaded '${downloadedFile.name}'...")
            runScript(downloadedFile)
        } else {
            // Inform the user if the download or permission setup failed.
            println("Failed to download or set permissions for '$NOUR_SCRIPT_NAME'. Script will not be run.")
        }

    } catch (e: Exception) {
        // Catch any unexpected errors that occur during the main process.
        println("An unexpected error occurred in main: ${e.message}")
        e.printStackTrace()
    }
}

/**
 * Manages an existing local script. It checks for updates, applies them if necessary,
 * ensures permissions are correct, and then triggers execution.
 *
 * @param scriptName The local filename of the script.
 * @param scriptUrl The remote URL to check for updates.
 * @return `true` if the script was found and processed (i.e., its lifecycle for this run is complete).
 *         `false` if the script file does not exist locally.
 */
fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)

    // If the script doesn't exist, there's nothing to handle here.
    // Return false to let the main function orchestrate the download.
    if (!scriptFile.exists()) {
        return false
    }

    // A variable to hold the file that should ultimately be executed.
    val fileToExecute: File

    println("Found '${scriptFile.name}'. Checking for updates...")

    // Check if the remote version of the script is different from the local one.
    if (isFileChanged(scriptFile, scriptUrl)) {
        println("'${scriptFile.name}' has changed. Attempting to download the new version...")
        // Attempt to download the new version and set its permissions.
        val updatedFile = downloadAndSetPermissions(scriptUrl, scriptName)
        if (updatedFile != null) {
            // If the update was successful, this is the file we'll run.
            fileToExecute = updatedFile
            println("Successfully updated '${scriptFile.name}'.")
        } else {
            // If the update failed, fall back to the existing local version as a last resort.
            println("Failed to update '${scriptFile.name}'. Will attempt to run the existing local version.")
            fileToExecute = scriptFile
        }
    } else {
        // The local file is identical to the remote one.
        println("'${scriptFile.name}' is up to date.")
        fileToExecute = scriptFile
    }

    // After determining which file to use (updated or existing), ensure it can be run.
    // First, verify that the file is actually executable.
    if (!fileToExecute.canExecute()) {
        println("Warning: '${fileToExecute.name}' is not executable. Attempting to set permissions...")
        // If not, try to set the executable permission.
        if (!setExecutablePermission(fileToExecute)) {
            // If setting permissions fails, we cannot proceed with execution.
            println("Failed to set executable permission for '${fileToExecute.name}'. Script will not be run.")
            return true // Return true because we've completed the handling process.
        }
    }

    // If we've reached this point, the file should be ready to run.
    println("Preparing to run '${fileToExecute.name}'...")
    runScript(fileToExecute)

    // Return true because the script was found and its lifecycle was fully managed.
    return true
}

/**
 * Compares a local file's content with content from a remote URL.
 *
 * @param localFile The file on the local disk.
 * @param remoteUrl The URL pointing to the master version of the file.
 * @return `true` if the contents are different or if an error occurs (fail-safe).
 *         `false` if the contents are identical.
 */
fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    println("Comparing local '${localFile.name}' with remote version...")
    try {
        // Read the content from both the remote URL and the local file.
        val remoteContent = URL(remoteUrl).readText(Charsets.UTF_8)
        val localContent = localFile.readText(Charsets.UTF_8)
        // Return true if they are not the same.
        return remoteContent != localContent
    } catch (e: IOException) {
        // If any error occurs (e.g., no network), assume the file has changed
        // to be safe and trigger a download attempt.
        println("Could not compare file versions: ${e.message}. Assuming an update is needed.")
        return true
    }
}

/**
 * Downloads a file from a URL and sets executable permission on it.
 * This is a two-step process to ensure the downloaded script is ready to run.
 *
 * @param scriptUrlString The URL of the file to download.
 * @param scriptFileName The desired local filename for the downloaded file.
 * @return The `File` object if both download and permission setting were successful, otherwise `null`.
 */
fun downloadAndSetPermissions(scriptUrlString: String, scriptFileName: String): File? {
    val destinationFile = File(scriptFileName)

    println("Downloading '$scriptFileName' from $scriptUrlString...")
    try {
        // Perform the file download.
        downloadFile(URL(scriptUrlString), destinationFile)
        println("Download completed successfully.")
    } catch (e: Exception) {
        // If downloading fails, report the error and return null.
        println("Error downloading '$scriptFileName': ${e.message}")
        return null
    }

    // After a successful download, set the executable permission.
    // If permission setting fails, the whole operation is considered a failure.
    return if (setExecutablePermission(destinationFile)) {
        destinationFile
    } else {
        println("Download succeeded but setting permissions failed.")
        null
    }
}

/**
 * Sets the executable permission for a file using the `chmod +x` command.
 *
 * @param file The file on which to set the permission.
 * @return `true` if the permission was set successfully, `false` otherwise.
 */
fun setExecutablePermission(file: File): Boolean {
    // It's not possible to set permissions on a non-existent file.
    if (!file.exists()) {
        println("Cannot set permissions: File '${file.name}' does not exist.")
        return false
    }

    println("Setting executable permission on '${file.name}'...")
    try {
        // Use ProcessBuilder to execute the 'chmod +x' command.
        val processBuilder = ProcessBuilder("chmod", "+x", file.absolutePath)
        val process = processBuilder.start()
        val exitCode = process.waitFor() // Wait for the command to complete.

        // An exit code of 0 indicates success.
        return if (exitCode == 0) {
            println("Executable permission set successfully.")
            true
        } else {
            // If the command fails, log the error output for debugging.
            val errorOutput = process.errorStream.bufferedReader().readText().trim()
            println("Error setting executable permission (chmod exit code: $exitCode).")
            if (errorOutput.isNotEmpty()) println("Error details: $errorOutput")
            false
        }
    } catch (e: Exception) {
        // Catch exceptions related to starting the process (e.g., 'chmod' not found).
        println("Failed to run chmod for '${file.name}': ${e.message}")
        e.printStackTrace()
        return false
    }
}

/**
 * Executes the given shell script using `bash`.
 * The script's standard input, output, and error streams are connected to the console.
 *
 * @param scriptFile The script file to execute.
 */
fun runScript(scriptFile: File) {
    // Perform safety checks before attempting to run the script.
    if (!scriptFile.exists()) {
        println("Cannot run script: '${scriptFile.name}' does not exist.")
        return
    }
    if (!scriptFile.canExecute()) {
        println("Cannot run script: '${scriptFile.name}' is not executable.")
        return
    }

    println("Running '${scriptFile.name}'...")
    try {
        // Execute the script using 'bash'.
        val processBuilder = ProcessBuilder("bash", scriptFile.absolutePath)
        // This is crucial: it connects the script's I/O to the current console,
        // so the user can interact with it and see its output directly.
        processBuilder.inheritIO()
        val process = processBuilder.start()
        // Wait for the script to finish and get its exit code.
        val exitCode = process.waitFor()
        println("'${scriptFile.name}' finished with exit code $exitCode.")
    } catch (e: Exception) {
        // Handle errors that might occur during script execution.
        println("An error occurred while running script '${scriptFile.name}': ${e.message}")
        e.printStackTrace()
    }
}

/**
 * Downloads a file from a URL to a destination file safely.
 * It first downloads to a temporary file and then atomically moves it to the final destination.
 * This prevents file corruption if the download is interrupted.
 *
 * @param url The URL to download from.
 * @param destination The final destination file.
 * @throws IOException If the download or file move fails.
 */
fun downloadFile(url: URL, destination: File) {
    // Create a temporary file to download into.
    val tempFile = Files.createTempFile("download", ".tmp").toFile()
    try {
        // Open a stream from the URL and copy its contents to the temporary file.
        url.openStream().use { inputStream ->
            Files.copy(inputStream, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        // Once the download is complete, atomically move the temporary file to the
        // final destination. This is a very fast and safe operation.
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    } catch (e: Exception) {
        // If anything goes wrong, re-throw the exception to be handled by the caller.
        throw IOException("Failed to download file from $url: ${e.message}", e)
    } finally {
        // No matter what happens, ensure the temporary file is deleted.
        if (tempFile.exists()) {
            tempFile.delete()
        }
    }
}
