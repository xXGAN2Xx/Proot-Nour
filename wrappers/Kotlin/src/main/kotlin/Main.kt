import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import kotlin.system.exitProcess // Required for exitProcess

// List of files to download: Pair(URL String, Destination Filename)
val filesToDownload = listOf(
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/run.sh" to "run.sh",
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/helper.sh" to "helper.sh",
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/install.sh" to "install.sh",
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/entrypoint.sh" to "entrypoint.sh",
    "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh" to "PteroVM.sh"
)

// The specific script to run after downloading and setting permissions
const val scriptToRun = "PteroVM.sh"

fun main() {
    println("Starting script download and execution...")

    try {
        // 1. Download all files
        println("Downloading files...")
        filesToDownload.forEach { (urlString, filename) ->
            println("  Downloading $filename from $urlString...")
            try {
                val url = URL(urlString)
                val destination = File(filename)
                downloadFile(url, destination)
                println("  Successfully downloaded $filename.")
            } catch (e: Exception) {
                System.err.println("  ERROR downloading $filename: ${e.message}")
                // Treat download failure as critical
                throw RuntimeException("Failed to download required file: $filename", e)
            }
        }
        println("All files downloaded successfully.")

        // 2. Set executable permission on all downloaded files
        println("Setting executable permissions...")
        filesToDownload.forEach { (_, filename) ->
            val destination = File(filename)
            println("  Setting +x permission for ${destination.name}...")
            try {
                // Use File#setExecutable for better platform independence (owner only)
                if (!destination.setExecutable(true, false)) {
                     System.err.println("    WARN: setExecutable(true) returned false for ${destination.name}. Attempting chmod as fallback.")
                     // Fallback using chmod (requires 'chmod' command to be available)
                     val chmod = ProcessBuilder("chmod", "+x", destination.absolutePath)
                     chmod.inheritIO() // Show chmod output/errors
                     val process = chmod.start()
                     val exitCode = process.waitFor()
                     if (exitCode != 0) {
                         throw RuntimeException("chmod +x ${destination.name} failed with exit code $exitCode")
                     }
                }
                 // Verify if executable (optional but recommended)
                 if (!destination.canExecute()) {
                     System.err.println("  ERROR: Could not set or verify executable permission for ${destination.name}.")
                     // Treat permission failure as critical
                     throw RuntimeException("Failed to make file executable: ${destination.name}")
                 } else {
                    println("  Successfully set +x for ${destination.name}.")
                 }
            } catch (e: Exception) {
                // Includes InterruptedException, IOException from ProcessBuilder/waitFor
                System.err.println("  ERROR setting executable permission for ${destination.name}: ${e.message}")
                throw RuntimeException("Failed to set executable permission for: ${destination.name}", e)
            }
        }
        println("Executable permissions set for all downloaded files.")

        // 3. Run the specific downloaded file (PteroVM.sh)
        println("Running $scriptToRun...")
        try {
            val scriptFile = File(scriptToRun)
             if (!scriptFile.exists()) {
                throw RuntimeException("Script to run ($scriptToRun) does not exist.")
             }
             if (!scriptFile.canExecute()) {
                 // This shouldn't happen if the previous step succeeded, but check anyway
                 throw RuntimeException("Script to run ($scriptToRun) is not executable.")
             }

            // Use "sh" or potentially "./" depending on how the script should be run
            // Using "sh" is generally safer if the script doesn't have a shebang or might not be in PATH
            val runProcess = ProcessBuilder("sh", scriptFile.absolutePath)
            runProcess.inheritIO() // Show script's output/errors in the console
            val process = runProcess.start()
            val exitCode = process.waitFor() // Wait for the script to finish

            println("$scriptToRun finished with exit code $exitCode.")
            if (exitCode != 0) {
                // Log non-zero exit code but don't necessarily throw an exception,
                // as the script itself might indicate issues via exit code.
                System.err.println("Warning: $scriptToRun exited with non-zero status ($exitCode).")
            }
        } catch (e: Exception) {
            System.err.println("ERROR running script $scriptToRun: ${e.message}")
            throw RuntimeException("Failed to execute script: $scriptToRun", e)
        }

        // 4. Cleanup - Removed file deletion
        println("Script execution process completed. Downloaded files remain in the current directory.")

    } catch (e: Exception) {
        // Catch errors from any stage (download, chmod, run)
        System.err.println("\n--- SCRIPT FAILED ---")
        System.err.println("An error occurred during the process: ${e.message}")
        // e.printStackTrace() // Uncomment for full stack trace if needed for debugging
        exitProcess(1) // Exit with a non-zero status to indicate failure
    }
}

// Re-usable download function using try-with-resources (.use) and absolute path
fun downloadFile(url: URL, destination: File) {
    url.openStream().use { input ->
        Files.copy(input, Paths.get(destination.absolutePath), StandardCopyOption.REPLACE_EXISTING)
    }
}
