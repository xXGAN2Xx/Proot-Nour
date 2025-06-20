import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.io.IOException

const val NOUR_SCRIPT_NAME = "nour.sh"
const val NOURD_SCRIPT_NAME = "nourd.sh"
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nour.sh"
const val NOURD_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nourd.sh"

fun main() {
    try {
        // Try to find, update, and run nour.sh
        if (handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return // Script was handled (found, updated if necessary, and run or attempt to run)
        }

        // If nour.sh was not handled, try nourd.sh
        if (handleScript(NOURD_SCRIPT_NAME, NOURD_URL)) {
            return // Script was handled
        }

        // If neither script was found/handled, prompt for download
        println("Neither '$NOUR_SCRIPT_NAME' nor '$NOURD_SCRIPT_NAME}' found locally, and no update check was performed. Please choose a script to download.")
        handleDownloadChoiceSetPermsAndRun()

    } catch (e: Exception) {
        println("An unexpected error occurred in main: ${e.message}")
        e.printStackTrace()
    }
}

/**
 * Handles checking, updating, setting permissions, and running a script.
 * @return true if the script was found and an attempt was made to process/run it, false otherwise (e.g., script file doesn't exist).
 */
fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)
    var fileToExecute: File? = null

    if (scriptFile.exists()) {
        println("Found '${scriptFile.name}'. Checking for updates...")
        if (isFileChanged(scriptFile, scriptUrl)) {
            println("'${scriptFile.name}' has changed or an error occurred during check. Attempting to download the new version...")
            val updatedFile = downloadAndSetPermissions(scriptUrl, scriptName)
            if (updatedFile != null) {
                fileToExecute = updatedFile
                println("Successfully updated '${scriptFile.name}'.")
            } else {
                println("Failed to update '${scriptFile.name}'. Will attempt to run the existing local version.")
                fileToExecute = scriptFile // Fallback to existing local version
            }
        } else {
            println("'${scriptFile.name}' is up to date.")
            fileToExecute = scriptFile
        }
    } else {
        return false // Script does not exist, so not "handled" in terms of finding and running.
    }

    // If we have a file to execute (either updated, existing, or fallback)
    if (fileToExecute != null) {
        // Ensure permissions are set (downloadAndSetPermissions does it, but crucial for "up to date" or "fallback" cases)
        if (setExecutablePermission(fileToExecute)) {
            println("Preparing to run '${fileToExecute.name}'...")
            runScript(fileToExecute)
        } else {
            println("Failed to set executable permission for '${fileToExecute.name}'. Script will not be run.")
            // Even if perms fail, we "handled" the script in the sense that we found it and tried.
        }
        return true // Script was found and an attempt was made to run it or update it.
    }
    return false // Should ideally not be reached if scriptFile.exists() was true.
}

/**
 * Checks if the local file content differs from the remote file content.
 * Treats network or file errors during comparison as "changed" to be safe.
 */
fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    println("Comparing local '${localFile.name}' with remote '$remoteUrl'...")
    try {
        // Consider adding connect and read timeouts for URL.openStream().readBytes().toString(Charsets.UTF_8)
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
 * Downloads a script from a URL and sets executable permissions.
 * @return The File object if successful, null otherwise.
 */
fun downloadAndSetPermissions(scriptUrlString: String, scriptFileName: String): File? {
    val url = URL(scriptUrlString)
    val destinationFile = File(scriptFileName)

    println("Downloading '$scriptFileName' from $scriptUrlString...")
    try {
        downloadFile(url, destinationFile) // Uses the improved atomic downloadFile
        println("Download completed for '$scriptFileName'.")
    } catch (e: Exception) {
        println("Error downloading '$scriptFileName': ${e.message}")
        e.printStackTrace()
        return null
    }

    if (!setExecutablePermission(destinationFile)) {
        println("Download of '$scriptFileName' succeeded but setting permissions failed.")
        // Depending on requirements, you might still return destinationFile here and let caller decide.
        // For now, if chmod fails, consider the overall operation failed for execution.
        return null
    }
    println("Successfully downloaded and set permissions for '$scriptFileName'.")
    return destinationFile
}

/**
 * Sets executable permission (+x) on the given file.
 * @return true if successful, false otherwise.
 */
fun setExecutablePermission(file: File): Boolean {
    if (!file.exists()) {
        println("Cannot set permissions: File '${file.name}' does not exist at path '${file.absolutePath}'.")
        return false
    }
    println("Setting executable permission on '${file.name}'...")
    try {
        val chmod = ProcessBuilder("chmod", "+x", file.absolutePath)
        val chmodProcess = chmod.start()
        val chmodExitCode = chmodProcess.waitFor()

        if (chmodExitCode != 0) {
            val errorOutput = chmodProcess.errorStream.bufferedReader().readText().trim()
            val stdOutput = chmodProcess.inputStream.bufferedReader().readText().trim()
            println("Error setting executable permission for '${file.name}' (exit code: $chmodExitCode).")
            if (errorOutput.isNotEmpty()) println("chmod stderr: $errorOutput")
            if (stdOutput.isNotEmpty()) println("chmod stdout: $stdOutput")
            return false
        } else {
            println("Executable permission set for '${file.name}'.")
            return true
        }
    } catch (e: IOException) {
        println("IOException while trying to run chmod for '${file.name}': ${e.message}")
        e.printStackTrace()
        return false
    } catch (e: InterruptedException) {
        println("Process 'chmod' for '${file.name}' was interrupted: ${e.message}")
        e.printStackTrace()
        Thread.currentThread().interrupt() // Restore interrupted status
        return false
    }
}

/**
 * Prompts the user to choose a script to download, then downloads, sets permissions, and runs it.
 */
fun handleDownloadChoiceSetPermsAndRun() {
    println("Choose an option to download:")
    println("0: Download $NOUR_SCRIPT_NAME")
    println("1: Download $NOURD_SCRIPT_NAME")
    print("Enter your choice (0 or 1): ")

    val choice = readlnOrNull()

    val scriptUrlString: String
    val scriptFileName: String

    when (choice) {
        "0" -> {
            scriptUrlString = NOUR_URL
            scriptFileName = NOUR_SCRIPT_NAME
        }
        "1" -> {
            scriptUrlString = NOURD_URL
            scriptFileName = NOURD_SCRIPT_NAME
        }
        else -> {
            println("Invalid choice. Please enter 0 or 1. Exiting.")
            return
        }
    }

    val downloadedFile = downloadAndSetPermissions(scriptUrlString, scriptFileName)
    if (downloadedFile != null) {
        // downloadAndSetPermissions already sets permissions.
        println("Preparing to run downloaded '${downloadedFile.name}'...")
        runScript(downloadedFile)
    } else {
        println("Failed to download or set permissions for '$scriptFileName'. Script will not be run.")
    }
}

/**
 * Runs the given script file using "bash" and waits for it to complete.
 */
fun runScript(scriptFile: File) {
    println("Running '${scriptFile.name}' and waiting for it to complete...")
    try {
        val processBuilder = ProcessBuilder("bash", scriptFile.absolutePath)
        processBuilder.inheritIO() // Shows script output/errors directly
        val process = processBuilder.start()
        val exitCode = process.waitFor()
        println("'${scriptFile.name}' finished with exit code $exitCode.")
    } catch (e: IOException) {
        println("IOException while trying to run script '${scriptFile.name}': ${e.message}")
        e.printStackTrace()
    } catch (e: InterruptedException) {
        println("Script execution for '${scriptFile.name}' was interrupted: ${e.message}")
        e.printStackTrace()
        Thread.currentThread().interrupt() // Restore interrupted status
    }
}

/**
 * Downloads a file from a URL to a destination, atomically.
 * Downloads to a temporary file first, then renames it to the destination on success.
 */
fun downloadFile(url: URL, destination: File) {
    // Create temp file in the same directory as the destination to ensure atomic move across same filesystem
    val tempFile = Files.createTempFile(destination.parentFile?.toPath() ?: Paths.get("."), destination.name, ".tmpdownload").toFile()
    try {
        url.openStream().use { inputStream ->
            Files.copy(inputStream, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        // If download is successful, move temp file to actual destination
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        println("Atomically moved downloaded content to '${destination.name}'.")
    } catch (e: Exception) {
        // If an error occurs during download or move, try to delete the temporary file
        if (tempFile.exists() && !tempFile.delete()) {
            println("Warning: Failed to delete temporary file: ${tempFile.absolutePath}")
        }
        throw IOException("Failed to download or replace file '${destination.name}' from $url: ${e.message}", e)
    } finally {
        // Ensure temp file is deleted if it somehow still exists (e.g., move failed after successful download but before exception handling)
        if (tempFile.exists() && !tempFile.delete()) {
             // This might happen if the move was successful but an error occurred afterwards in the try block
             // Or if the move failed and the delete in catch also failed.
            if (destination.exists() && destination.length() == tempFile.length()) {
                // If destination exists and has same size, assume move was successful and temp is just a leftover.
            } else {
                println("Warning: Temporary file ${tempFile.absolutePath} may still exist after download operation.")
            }
        }
    }
}
