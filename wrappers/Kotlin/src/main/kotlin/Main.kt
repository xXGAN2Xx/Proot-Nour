import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import kotlin.system.exitProcess // Required for exitProcess

// List of files to check/download: Pair(URL String, Destination Filename)
val filesToProcess = listOf(
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/run.sh" to "run.sh",
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/helper.sh" to "helper.sh",
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/install.sh" to "install.sh",
    "https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/entrypoint.sh" to "entrypoint.sh",
    "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh" to "PteroVM.sh"
)

// The specific script to run after checking/downloading and setting permissions
const val scriptToRun = "PteroVM.sh"

fun main() {
    println("Starting script setup...")

    try {
        // 1. Check for existing files and download if missing
        println("Checking/Downloading required script files...")
        filesToProcess.forEach { (urlString, filename) ->
            val destination = File(filename)
            if (destination.exists()) {
                // File exists, skip download
                println("  [EXISTS] '$filename'")
            } else {
                // File does not exist, download it
                println("  [MISSING] '$filename' - Downloading from $urlString...")
                try {
                    val url = URL(urlString)
                    downloadFile(url, destination)
                    println("      -> Downloaded '$filename' successfully.")
                } catch (e: Exception) {
                    System.err.println("      -> ERROR downloading '$filename': ${e.message}")
                    // If a required file is missing and download fails, it's critical
                    throw RuntimeException("Failed to download required file: '$filename'", e)
                }
            }
            // Minimal check after potential download (or if it existed)
            if (!destination.exists()) {
                 throw RuntimeException("Required file '$filename' is missing after check/download attempt.")
            }
        }
        println("File check/download process complete.")

        // 2. Set executable permission on all required files (whether they existed or were just downloaded)
        println("Ensuring executable permissions...")
        filesToProcess.forEach { (_, filename) ->
            val destination = File(filename)
             // Check existence again just to be safe before setting permissions
             if (!destination.exists()){
                 System.err.println("  ERROR: File '$filename' not found before setting permissions. This shouldn't happen.")
                 throw RuntimeException("File '$filename' missing unexpectedly.")
             }
            println("  Setting +x permission for '${destination.name}'...")
            try {
                // Use File#setExecutable for better platform independence (owner only)
                if (!destination.setExecutable(true, false)) {
                     System.err.println("    WARN: setExecutable(true) returned false for '${destination.name}'. Attempting chmod as fallback.")
                     // Fallback using chmod (requires 'chmod' command to be available)
                     val chmod = ProcessBuilder("chmod", "+x", destination.absolutePath)
                     chmod.inheritIO() // Show chmod output/errors
                     val process = chmod.start()
                     val exitCode = process.waitFor()
                     if (exitCode != 0) {
                         throw RuntimeException("chmod +x '${destination.name}' failed with exit code $exitCode")
                     }
                }
                 // Verify if executable (optional but recommended)
                 if (!destination.canExecute()) {
                     System.err.println("  ERROR: Could not set or verify executable permission for '${destination.name}'.")
                     // Treat permission failure as critical
                     throw RuntimeException("Failed to make file executable: '${destination.name}'")
                 } else {
                    println("  Successfully ensured +x for '${destination.name}'.")
                 }
            } catch (e: Exception) {
                // Includes InterruptedException, IOException from ProcessBuilder/waitFor
                System.err.println("  ERROR setting executable permission for '${destination.name}': ${e.message}")
                throw RuntimeException("Failed to set executable permission for: '${destination.name}'", e)
            }
        }
        println("Executable permissions set for all required files.")

        // 3. Run the specific downloaded file (PteroVM.sh)
        println("Attempting to run '$scriptToRun'...")
        try {
            val scriptFile = File(scriptToRun)
             if (!scriptFile.exists()) {
                // This check is slightly redundant given previous steps, but good for safety
                throw RuntimeException("Script to run ('$scriptToRun') does not exist.")
             }
             if (!scriptFile.canExecute()) {
                 // This shouldn't happen if the previous step succeeded, but check anyway
                 System.err.println("Error: Script '$scriptToRun' is not executable despite permission setting attempt.")
                 throw RuntimeException("Script to run ('$scriptToRun') is not executable.")
             }

            val runProcess = ProcessBuilder("sh", scriptFile.absolutePath)
            runProcess.inheritIO() // Show script's output/errors in the console
            val process = runProcess.start()
            val exitCode = process.waitFor() // Wait for the script to finish

            println("'$scriptToRun' finished with exit code $exitCode.")
            if (exitCode != 0) {
                System.err.println("Warning: '$scriptToRun' exited with non-zero status ($exitCode).")
            }
        } catch (e: Exception) {
            System.err.println("ERROR running script '$scriptToRun': ${e.message}")
            throw RuntimeException("Failed to execute script: '$scriptToRun'", e)
        }

        // 4. Cleanup - Files remain
        println("Script execution process completed. Files remain in the current directory.")

    } catch (e: Exception) {
        // Catch errors from any stage
        System.err.println("\n--- SCRIPT FAILED ---")
        System.err.println("An error occurred during the process: ${e.message}")
        // e.printStackTrace() // Uncomment for full stack trace if needed for debugging
        exitProcess(1) // Exit with a non-zero status to indicate failure
    }
}

// Re-usable download function using try-with-resources (.use) and absolute path
// (No changes needed here)
fun downloadFile(url: URL, destination: File) {
    url.openStream().use { input ->
        Files.copy(input, Paths.get(destination.absolutePath), StandardCopyOption.REPLACE_EXISTING)
    }
}
