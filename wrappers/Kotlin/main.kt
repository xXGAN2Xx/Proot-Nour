import java.io.File
import java.io.IOException
import java.net.URI
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import kotlin.system.exitProcess

const val NOUR_SCRIPT_NAME = "nour.sh"
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh"

fun main() {
    println("Done (s)! For help, type help")

    try {
        if (handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return
        }

        println("'$NOUR_SCRIPT_NAME' not found locally. Attempting to download...")
        val downloadedFile = downloadAndSetPermissions(NOUR_URL, NOUR_SCRIPT_NAME)
        if (downloadedFile != null) {
            println("Preparing to run downloaded '${downloadedFile.name}'...")
            runScript(downloadedFile)
        } else {
            println("Failed to download or set permissions for '$NOUR_SCRIPT_NAME'. Script will not be run.")
        }

    } catch (e: Exception) {
        println("An unexpected error occurred in main: ${e.message}")
        e.printStackTrace()
    }
}


fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)
    val fileToExecute: File
    val wasSuccessfullyUpdated: Boolean
    val isUpToDateAndSkippingPermSet: Boolean

    if (scriptFile.exists()) {
        println("Found '${scriptFile.name}'. Checking for updates...")
        if (isFileChanged(scriptFile, scriptUrl)) {
            println("'${scriptFile.name}' has changed or an error occurred during check. Attempting to download the new version...")
            val updatedFile = downloadAndSetPermissions(scriptUrl, scriptName)
            if (updatedFile != null) {
                fileToExecute = updatedFile
                wasSuccessfullyUpdated = true
                isUpToDateAndSkippingPermSet = false
                println("Successfully updated '${scriptFile.name}'.")
            } else {
                println("Failed to update '${scriptFile.name}'. Will attempt to run the existing local version '${scriptFile.name}'.")
                fileToExecute = scriptFile
                wasSuccessfullyUpdated = false
                isUpToDateAndSkippingPermSet = false
            }
        } else {
            println("'${scriptFile.name}' is up to date.")
            fileToExecute = scriptFile
            wasSuccessfullyUpdated = false
            isUpToDateAndSkippingPermSet = true
        }
    } else {
        return false
    }

    
    var canRun = false

    if (wasSuccessfullyUpdated) {
        if (fileToExecute.canExecute()) {
            println("Permissions for updated '${fileToExecute.name}' were set during download.")
            canRun = true
        } else {
            println("Error: Updated file '${fileToExecute.name}' is not executable despite successful update and permissioning process. Cannot run.")
        }
    } else if (isUpToDateAndSkippingPermSet) {
        println("Skipping explicit permission setting for up-to-date file '${fileToExecute.name}'.")
        if (fileToExecute.canExecute()) {
            println("'${fileToExecute.name}' is already executable.")
            canRun = true
        } else {
            println("Warning: Up-to-date file '${fileToExecute.name}' is NOT executable. Permission setting was skipped as requested. Script will not be run.")
            canRun = false
        }
    } else {
        println("Attempting to set/verify permissions for '${fileToExecute.name}' (e.g., fallback or initial run scenario)...")
        if (setExecutablePermission(fileToExecute)) {
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
    return true
}

fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    println("Comparing local '${localFile.name}' with remote '$remoteUrl'...")
    try {
        val remoteContent = URI(remoteUrl).toURL().readText(Charsets.UTF_8)
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
    val url = runCatching { URI(scriptUrlString).toURL() }.getOrNull()
    
    if (url == null) {
        println("Error: Invalid URL format: $scriptUrlString")
        return null
    }

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

    if (!setExecutablePermission(destinationFile)) {
        println("Download of '$scriptFileName' succeeded but setting permissions failed.")
        return null
    }
    println("Successfully downloaded and ensured permissions for '$scriptFileName'.")
    return destinationFile
}

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
            println("Error setting executable permission for '${file.name}' (chmod exit code: $chmodExitCode).")
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
        Thread.currentThread().interrupt()
        return false
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
        
        if (exitCode == 0) {
            println("Script completed successfully. Exiting program...")
            exitProcess(0)
        }
    } catch (e: IOException) {
        println("IOException while trying to run script '${scriptFile.name}': ${e.message}")
        e.printStackTrace()
    } catch (e: InterruptedException) {
        println("Script execution for '${scriptFile.name}' was interrupted: ${e.message}")
        e.printStackTrace()
        Thread.currentThread().interrupt()
    }
}

fun downloadFile(url: java.net.URL, destination: File) {
    val tempFile = Files.createTempFile(destination.parentFile?.toPath() ?: Paths.get("."), destination.name, ".tmpdownload").toFile()
    try {
        url.openStream().use { inputStream ->
            Files.copy(inputStream, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        Files.move(tempFile.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    } catch (e: Exception) {
        if (tempFile.exists() && !tempFile.delete()) {
            println("Warning: Failed to delete temporary file: ${tempFile.absolutePath}")
        }
        throw IOException("Failed to download or replace file '${destination.name}' from $url: ${e.message}", e)
    } finally {
        if (tempFile.exists() && tempFile.length() > 0 && !destination.exists()) {
            if (!tempFile.delete()) {
                 println("Warning: Temporary file ${tempFile.absolutePath} could not be deleted after failed operation.")
            }
        } else if (tempFile.exists() && (!destination.exists() || destination.length() != tempFile.length())) {
            if (!tempFile.delete()) {
                 println("Warning: Temporary file ${tempFile.absolutePath} may still exist and could not be cleaned up.")
            }
        } else if (tempFile.exists()) {
            tempFile.delete()
        }
    }
}
