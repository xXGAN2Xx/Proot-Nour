import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption

fun main() {
    println("Choose an option to download:")
    println("0: Download nour.sh")
    println("1: Download nourd.sh")
    print("Enter your choice (0 or 1): ")

    val choice = readlnOrNull() // Use readlnOrNull for safety, it returns null on EOF

    val scriptUrlString: String
    val scriptFileName: String

    when (choice) {
        "0" -> {
            scriptUrlString = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nour.sh"
            scriptFileName = "nour.sh"
        }
        "1" -> {
            scriptUrlString = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nourd.sh"
            scriptFileName = "nourd.sh"
        }
        else -> {
            println("Invalid choice. Please enter 0 or 1.")
            return // Exit if choice is invalid
        }
    }

    val url = URL(scriptUrlString)
    val destination = File(scriptFileName)

    try {
        // Check if the file already exists
        if (!destination.exists()) {
            println("File '$scriptFileName' does not exist. Downloading from $scriptUrlString...")
            downloadFile(url, destination)
            println("Download completed.")
        } else {
            println("File '$scriptFileName' already exists. Skipping download.")
        }

        // Set executable permission on the file
        println("Setting executable permission on '$scriptFileName'...")
        val chmod = ProcessBuilder("chmod", "+x", destination.name)
        chmod.inheritIO() // Show output/errors from chmod
        val chmodProcess = chmod.start()
        val chmodExitCode = chmodProcess.waitFor() // Still wait for chmod, as this is a quick operation
        if (chmodExitCode != 0) {
            println("Error setting executable permission for '$scriptFileName' (exit code: $chmodExitCode).")
            // Optionally, you might want to stop here if chmod fails
            return // Stop if chmod fails, as running the script might not work
        } else {
            println("Executable permission set for '$scriptFileName'.")
        }


        // Run the file
        println("Starting '$scriptFileName'...") // Changed message
        val harbor = ProcessBuilder("bash", destination.name)
        harbor.inheritIO() // Show output/errors from the script
        harbor.start() // Start the process but don't wait for it
        // harborProcess.waitFor() has been removed
        println("Script '$scriptFileName' has been started.") // Changed message

    } catch (e: Exception) {
        println("Error during script processing: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: URL, destination: File) {
    // Using .use ensures the stream is closed automatically
    url.openStream().use { inputStream ->
        Files.copy(inputStream, Paths.get(destination.toURI()), StandardCopyOption.REPLACE_EXISTING)
    }
}
