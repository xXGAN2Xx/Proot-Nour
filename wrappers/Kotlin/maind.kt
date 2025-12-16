import java.io.File
import java.io.IOException
import java.io.BufferedWriter
import java.io.OutputStreamWriter
import java.lang.ProcessBuilder
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
            println("Error: Updated file '${fileToExecute.name}' is not executable despite successful update. Cannot run.")
        }
    } else if (isUpToDateAndSkippingPermSet) {
        println("Skipping explicit permission setting for up-to-date file '${fileToExecute.name}'.")
        if (fileToExecute.canExecute()) {
            println("'${fileToExecute.name}' is already executable.")
            canRun = true
        } else {
            println("Warning: Up-to-date file '${fileToExecute.name}' is NOT executable. Script will not be run.")
            canRun = false
        }
    } else {
        println("Attempting to set/verify permissions for '${fileToExecute.name}'...")
        if (setExecutablePermission(fileToExecute)) {
            if (fileToExecute.canExecute()) {
                println("Permissions set successfully for '${fileToExecute.name}'.")
                canRun = true
            } else {
                println("Error: permissions set but file is not executable. Cannot run.")
            }
        } else {
            println("Failed to set executable permission for '${fileToExecute.name}'. Script will not be run.")
        }
    }

    if (canRun) {
        println("Preparing to run '${fileToExecute.name}' with Auto-Input...")
        runScript(fileToExecute)
    } else {
        println("Script '${fileToExecute.name}' will not be run due to permission issues.")
    }
    return true
}

fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    println("Comparing local '${localFile.name}' with remote '$remoteUrl'...")
    try {
        val remoteContent = URI(remoteUrl).toURL().readText(Charsets.UTF_8)
        val localContent = localFile.readText(Charsets.UTF_8)
        val changed = remoteContent != localContent
        if (changed) println("Contents differ for '${localFile.name}'.")
        else println("Contents are the same for '${localFile.name}'.")
        return changed
    } catch (e: Exception) {
        println("Error during comparison: ${e.message}. Assuming file changed.")
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
        println("Download succeeded but setting permissions failed.")
        return null
    }
    println("Successfully downloaded and ensured permissions for '$scriptFileName'.")
    return destinationFile
}

fun setExecutablePermission(file: File): Boolean {
    if (!file.exists()) return false
    println("Setting executable permission on '${file.name}'...")
    try {
        val chmod = ProcessBuilder("chmod", "+x", file.absolutePath)
        val chmodExitCode = chmod.start().waitFor()
        return chmodExitCode == 0
    } catch (e: Exception) {
        e.printStackTrace()
        return false
    }
}

fun runScript(scriptFile: File) {
    if (!scriptFile.canExecute()) {
        println("Cannot run script: '${scriptFile.name}' is not executable.")
        return
    }

    println("Running '${scriptFile.name}' and waiting for it to complete...")
    try {
        val pb = ProcessBuilder("bash", scriptFile.absolutePath)
        
        // redirectOutput(INHERIT) lets you see the logs in real-time.
        pb.redirectOutput(ProcessBuilder.Redirect.INHERIT)
        pb.redirectErrorStream(true)

        val process = pb.start()

        // 1. AUTO-INPUT LOGIC
        val writer = BufferedWriter(OutputStreamWriter(process.outputStream))
        
        // --- FIRST INPUT (1) ---
        writer.write("1")
        writer.newLine()
        writer.flush()

        // --- SECOND INPUT (1) ---
        writer.write("1")
        writer.newLine()
        writer.flush()

        // --- THIRD INPUT (enable xray) ---
        writer.write("systemctl enable xray && systemctl start xray")
        writer.newLine()
        writer.flush()
        // 2. INPUT BRIDGE (To restore console interactivity)
        // This ensures you can still type commands manually if the script asks for more later.
        Thread {
            try {
                val buffer = ByteArray(1024)
                var length: Int
                while (System.`in`.read(buffer).also { length = it } != -1) {
                    process.outputStream.write(buffer, 0, length)
                    process.outputStream.flush()
                }
            } catch (e: Exception) {
                // Ignore errors when stream closes
            }
        }.start()

        val exitCode = process.waitFor()
        println("'${scriptFile.name}' finished with exit code $exitCode.")

        // Exit the program if script completed successfully
        if (exitCode == 0) {
            println("Script completed successfully. Exiting program...")
            exitProcess(0)
        }

    } catch (e: IOException) {
        println("IOException running script: ${e.message}")
        e.printStackTrace()
    } catch (e: InterruptedException) {
        println("Script execution interrupted.")
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
        if (tempFile.exists()) tempFile.delete()
        throw IOException("Failed to download file", e)
    } finally {
        if (tempFile.exists()) tempFile.delete()
    }
}
