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
        if (handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return
        }

        if (handleScript(NOURD_SCRIPT_NAME, NOURD_URL)) {
            return
        }

        println("Neither '$NOUR_SCRIPT_NAME' nor '$NOURD_SCRIPT_NAME}' found locally, and no update check was performed. Please choose a script to download.")
        handleDownloadChoiceSetPermsAndRun()

    } catch (e: Exception) {
        println("An unexpected error occurred in main: ${e.message}")
        e.printStackTrace()
    }
}

fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)
    var fileToExecute: File? = null
    var wasSuccessfullyUpdated = false      // True if downloaded AND permissions set successfully by downloadAndSetPermissions
    var isUpToDateAndSkippingPermSet = false // True if file is up-to-date and we intend to skip explicit chmod

    if (scriptFile.exists()) {
        println("Found '${scriptFile.name}'. Checking for updates...")
        if (isFileChanged(scriptFile, scriptUrl)) { // File changed or error during check
            println("'${scriptFile.name}' has changed or an error occurred during check. Attempting to download the new version...")
            val updatedFile = downloadAndSetPermissions(scriptUrl, scriptName) // This function sets perms on success
            if (updatedFile != null) {
                fileToExecute = updatedFile
                wasSuccessfullyUpdated = true // Permissions were handled by downloadAndSetPermissions
                println("Successfully updated '${scriptFile.name}'.")
            } else {
                println("Failed to update '${scriptFile.name}'. Will attempt to run the existing local version '${scriptFile.name}'.")
                fileToExecute = scriptFile // Fallback to existing local version
                // For fallback, wasSuccessfullyUpdated and isUpToDateAndSkippingPermSet remain false,
                // leading to explicit permission setting later.
            }
        } else { // File is up to date
            println("'${scriptFile.name}' is up to date.")
            fileToExecute = scriptFile
            isUpToDateAndSkippingPermSet = true // Mark that we intend to skip explicit chmod for this up-to-date file
        }
    } else {
        // Script does not exist locally. Main will handle if both are missing.
        return false
    }

    if (fileToExecute != null) {
        var canRun = false

        if (wasSuccessfullyUpdated) {
            // Permissions were set by downloadAndSetPermissions. It must be executable.
            if (fileToExecute.canExecute()) {
                println("Permissions for updated '${fileToExecute.name}' were set during download.")
                canRun = true
            } else {
                // This should ideally not happen if downloadAndSetPermissions is correct and returns non-null only on full success.
                println("Error: Updated file '${fileToExecute.name}' is not executable despite successful update and permissioning process. Cannot run.")
            }
        } else if (isUpToDateAndSkippingPermSet) {
            println("Skipping explicit permission setting for up-to-date file '${fileToExecute.name}'.")
            if (fileToExecute.canExecute()) {
                println("'${fileToExecute.name}' is already executable.")
                canRun = true
            } else {
                // If it's up-to-date but NOT executable, and we skipped setting perms, then it cannot run.
                // This is the direct consequence of the request to skip permission setting.
                println("Warning: Up-to-date file '${fileToExecute.name}' is NOT executable. Permission setting was skipped as requested. Script will not be run.")
                canRun = false
            }
        } else {
            // This is the fallback case (e.g., scriptFile existed, update failed, fileToExecute is the original scriptFile)
            // or any other scenario where the file wasn't newly updated or confirmed up-to-date to skip permissioning.
            // We MUST try to set permissions here.
            println("Attempting to set/verify permissions for '${fileToExecute.name}' (e.g., fallback or initial run scenario)...")
            if (setExecutablePermission(fileToExecute)) {
                // setExecutablePermission returning true means chmod likely succeeded.
                // We still verify with canExecute() as a final check.
                if (fileToExecute.canExecute()) {
                    println("Permissions set successfully for '${fileToExecute.name}'.")
                    canRun = true
                } else {
                     println("Error: Setting permissions for '${fileToExecute.name}' was reported as successful, but the file is still not executable. Cannot run.")
                }
            } else {
                println("Failed to set executable permission for '${fileToExecute.name}'. Script will not be run.")
            }
        }

        if (canRun) {
            println("Preparing to run '${fileToExecute.name}'...")
            runScript(fileToExecute)
        } else {
            println("Script '${fileToExecute.name}' will not be run due to permission issues or because it was not made executable.")
        }
        return true // Script was found and an attempt was made to process it (run or not).
    }
    return false // fileToExecute was null (should only happen if scriptFile didn't exist initially)
}

fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    println("Comparing local '${localFile.name}' with remote '$remoteUrl'...")
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

fun downloadAndSetPermissions(scriptUrlString: String, scriptFileName: String): File? {
    val url = URL(scriptUrlString)
    val destinationFile = File(scriptFileName)

    println("Downloading '$scriptFileName' from $scriptUrlString...")
    try {
        downloadFile(url, destinationFile)
        println("Download completed for '$scriptFileName'.")
    } catch (e: Exception) {
        println("Error downloading '$scriptFileName': ${e.message}")
        e.printStackTrace()
        return null
    }

    // Crucially, set permissions after download.
    if (!setExecutablePermission(destinationFile)) {
        println("Download of '$scriptFileName' succeeded but setting permissions failed.")
        // If chmod fails, consider the overall operation failed for safe execution.
        return null
    }
    // If setExecutablePermission was successful, it would have printed its own success message.
    println("Successfully downloaded and ensured permissions for '$scriptFileName'.")
    return destinationFile
}

fun setExecutablePermission(file: File): Boolean {
    if (!file.exists()) {
        println("Cannot set permissions: File '${file.name}' does not exist at path '${file.absolutePath}'.")
        return false
    }
    // No need to check file.canExecute() here if we are explicitly setting it.
    // If it's already executable, "chmod +x" is harmless.
    println("Setting executable permission on '${file.name}'...")
    try {
        val chmod = ProcessBuilder("chmod", "+x", file.absolutePath)
        // chmod.inheritIO() // Can make output noisy if not needed, let's capture manually
        val chmodProcess = chmod.start()
        val chmodExitCode = chmodProcess.waitFor()

        if (chmodExitCode != 0) {
            val errorOutput = chmodProcess.errorStream.bufferedReader().readText().trim()
            val stdOutput = chmodProcess.inputStream.bufferedReader().readText().trim()
            println("Error setting executable permission for '${file.name}' (chmod exit code: $chmodExitCode).")
            if (errorOutput.isNotEmpty()) println("chmod stderr: $errorOutput")
            if (stdOutput.isNotEmpty()) println("chmod stdout: $stdOutput") // Should be empty on error
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
        Thread.currentThread().interrupt()
        return false
    }
}

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
        // downloadAndSetPermissions already sets permissions and ensures it's executable.
        println("Preparing to run downloaded '${downloadedFile.name}'...")
        runScript(downloadedFile)
    } else {
        println("Failed to download or set permissions for '$scriptFileName'. Script will not be run.")
    }
}

fun runScript(scriptFile: File) {
    if (!scriptFile.exists()) {
        println("Cannot run script: '${scriptFile.name}' does not exist at ${scriptFile.absolutePath}.")
        return
    }
    if (!scriptFile.canExecute()) {
        println("Cannot run script: '${scriptFile.name}' is not executable. Path: ${scriptFile.absolutePath}")
        return
    }

    println("Running '${scriptFile.name}' and waiting for it to complete...")
    try {
        val processBuilder = ProcessBuilder("bash", scriptFile.absolutePath)
        processBuilder.inheritIO()
        val process = processBuilder.start()
        val exitCode = process.waitFor()
        println("'${scriptFile.name}' finished with exit code $exitCode.")
    } catch (e: IOException) {
        println("IOException while trying to run script '${scriptFile.name}': ${e.message}")
        e.printStackTrace()
    } catch (e: InterruptedException) {
        println("Script execution for '${scriptFile.name}' was interrupted: ${e.message}")
        e.printStackTrace()
        Thread.currentThread().interrupt()
    }
}

fun downloadFile(url: URL, destination: File) {
    val tempFile = Files.createTempFile(destination.parentFile?.toPath() ?: Paths.get("."), destination.name, ".tmpdownload").toFile()
    try {
        url.openStream().use { inputStream ->
            Files.copy(inputStream, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        // println("Atomically moved downloaded content to '${destination.name}'.") // Covered by calling function
    } catch (e: Exception) {
        if (tempFile.exists() && !tempFile.delete()) {
            println("Warning: Failed to delete temporary file: ${tempFile.absolutePath}")
        }
        throw IOException("Failed to download or replace file '${destination.name}' from $url: ${e.message}", e)
    } finally {
        if (tempFile.exists() && tempFile.length() > 0 && !destination.exists()) {
             // If temp file still exists, has content, and destination doesn't, means move likely failed.
             // The delete in catch should have handled it, but this is a fallback.
            if (!tempFile.delete()) {
                 println("Warning: Temporary file ${tempFile.absolutePath} could not be deleted after failed operation.")
            }
        } else if (tempFile.exists() && (!destination.exists() || destination.length() != tempFile.length())) {
            // If temp file exists and destination is not what it should be (e.g. move failed or partial)
            if (!tempFile.delete()) {
                 println("Warning: Temporary file ${tempFile.absolutePath} may still exist and could not be cleaned up.")
            }
        } else if (tempFile.exists()) {
            // If temp file exists but destination seems okay, try to delete temp as it should have been moved.
            tempFile.delete() // Best effort
        }
    }
}
