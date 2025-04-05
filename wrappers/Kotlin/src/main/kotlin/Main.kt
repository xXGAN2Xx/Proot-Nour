import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermission
import java.util.EnumSet
import kotlin.io.path.absolutePathString // Import for getting absolute path

// Data class to hold URL and filename pairs for better organization
data class FileInfo(val url: String, val filename: String)

fun main() {
    // List of files to download with their URLs and desired local filenames
    val filesToDownload = listOf(
        FileInfo("https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/run.sh", "run.sh"),
        FileInfo("https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/helper.sh", "helper.sh"),
        FileInfo("https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/install.sh", "install.sh"),
        FileInfo("https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/entrypoint.sh", "entrypoint.sh"),
        FileInfo("https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh", "PteroVM.sh")
    )

    // Specify which script to run after downloading all files
    val scriptToRunFilename = "PteroVM.sh"
    val scriptFileToRun = File(scriptToRunFilename)

    try {
        println("Starting download and setup process...")

        // Loop through the list, download each file, and set executable permission
        filesToDownload.forEach { fileInfo ->
            val url = URL(fileInfo.url)
            val destination = File(fileInfo.filename)

            // --- Download Step ---
            println("Downloading ${fileInfo.filename} from ${fileInfo.url}...")
            downloadFile(url, destination)
            println("Successfully downloaded ${fileInfo.filename}.")

            // --- Set Executable Permission Step ---
            println("Setting executable permission for ${fileInfo.filename}...")
            setExecutable(destination)
            println("Executable permission set for ${fileInfo.filename}.")
            println("---") // Separator for clarity
        }

        println("\nAll files downloaded and permissions set.")

        // --- Run the designated script ---
        println("Attempting to run '$scriptToRunFilename'...")
        // Use ProcessBuilder to execute the shell script
        // Using the absolute path is generally safer
        val runProcessBuilder = ProcessBuilder("sh", scriptFileToRun.absolutePath)
        // Redirect the subprocess's input, output, and error streams to the current Kotlin process
        // This allows you to see the script's output in your console
        runProcessBuilder.inheritIO()

        val process = runProcessBuilder.start() // Start the process
        val exitCode = process.waitFor() // Wait for the script to finish executing

        println("\n'$scriptToRunFilename' finished with exit code: $exitCode.")

        // --- Optional Cleanup ---
        // The original script deleted the file after running.
        // PteroVM.sh might rely on the other downloaded scripts, so deleting it
        // might cause issues if it's run again or if other scripts call it.
        // If you are sure you want to delete ONLY PteroVM.sh after it runs, uncomment the block below.
        /*
        println("Deleting '$scriptToRunFilename'...")
        if (scriptFileToRun.delete()) {
            println("'$scriptToRunFilename' deleted successfully.")
        } else {
            // Add error handling for deletion failure if needed
            System.err.println("Warning: Failed to delete '$scriptToRunFilename'. It might be in use or permissions might be insufficient.")
        }
        */

    } catch (e: Exception) {
        // Catch any general exceptions during the process (download, chmod, execution)
        System.err.println("\nAn error occurred during the process: ${e.message}")
        e.printStackTrace() // Print detailed error information
    }
}

/**
 * Downloads a file from a given URL to a destination file.
 * Replaces the destination file if it already exists.
 * Uses try-with-resources (`use`) for safe stream handling.
 *
 * @param url The URL of the file to download.
 * @param destination The File object representing the local destination path.
 * @throws Exception if any IO error occurs during download or file writing.
 */
fun downloadFile(url: URL, destination: File) {
    // Open the stream from the URL and ensure it's closed automatically
    url.openStream().use { inputStream ->
        // Copy the input stream to the destination file path, replacing the file if it exists
        Files.copy(inputStream, destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
    }
}

/**
 * Sets executable permission for the owner of the file.
 * Attempts to use Java NIO POSIX permissions first for better cross-platform compatibility.
 * Falls back to executing the external 'chmod +x' command if NIO fails or is unsupported.
 *
 * @param file The file for which to set executable permission.
 */
fun setExecutable(file: File) {
    try {
        // Define the desired POSIX permissions (Read, Write, Execute for Owner; Read for Group and Others)
        val permissions = EnumSet.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
            PosixFilePermission.OWNER_EXECUTE,
            PosixFilePermission.GROUP_READ,
            PosixFilePermission.OTHERS_READ
            // Add GROUP_EXECUTE or OTHERS_EXECUTE if needed
        )
        // Attempt to set permissions using Java NIO
        Files.setPosixFilePermissions(file.toPath(), permissions)
    } catch (e: UnsupportedOperationException) {
        // Handle cases where POSIX is not supported (e.g., some Windows versions)
        println("Warning: POSIX permissions not supported on this system for '${file.name}'. Falling back to 'chmod' command.")
        setExecutableUsingChmod(file) // Use the fallback method
    } catch (e: Exception) {
        // Handle other potential errors during NIO permission setting
        System.err.println("Warning: Failed to set permissions using Java NIO for '${file.name}': ${e.message}. Falling back to 'chmod'.")
        setExecutableUsingChmod(file) // Use the fallback method
    }
}

/**
 * Sets executable permission using the external 'chmod +x' command.
 * This is a fallback method primarily for Unix-like systems where Java NIO POSIX might fail.
 *
 * @param file The file for which to set executable permission.
 */
fun setExecutableUsingChmod(file: File) {
    try {
        // Create a process builder for the command "chmod +x filename"
        val chmodProcessBuilder = ProcessBuilder("chmod", "+x", file.absolutePath) // Use absolute path
        // Optional: Redirect error stream if you want to capture chmod errors separately
        // chmodProcessBuilder.redirectErrorStream(true)

        val chmodProcess = chmodProcessBuilder.start() // Start the chmod process
        val exitCode = chmodProcess.waitFor() // Wait for chmod to complete

        if (exitCode != 0) {
            // Report if chmod command failed
            System.err.println("Warning: 'chmod +x ${file.name}' command failed with exit code $exitCode.")
            // You could potentially read the process's error stream here for more details
            // chmodProcess.errorStream.bufferedReader().useLines { lines -> lines.forEach { System.err.println(it) } }
        }
    } catch (e: Exception) {
        // Catch errors related to starting or running the chmod process itself
        System.err.println("Error executing 'chmod' command for '${file.name}': ${e.message}")
        e.printStackTrace() // Print stack trace for debugging
    }
}
