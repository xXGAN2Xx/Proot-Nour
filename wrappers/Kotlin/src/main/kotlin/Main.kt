import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption

fun main() {
    val url = URL("https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh")
    val destination = File("PteroVM.sh")

    try {
        println("Downloading script from $url...")
        downloadFile(url, destination)
        println("Download complete: ${destination.absolutePath}")

        // Set executable permission on downloaded file
        val chmod = ProcessBuilder("chmod", "+x", destination.absolutePath)
        chmod.inheritIO()
        val chmodExit = chmod.start().waitFor()
        if (chmodExit != 0) {
            println("Failed to set executable permissions.")
            return
        }

        // Execute the script
        println("Executing script...")
        val process = ProcessBuilder("/bin/sh", destination.absolutePath)
        process.inheritIO()
        val exitCode = process.start().waitFor()
        println("Script exited with code $exitCode")

    } catch (e: Exception) {
        println("Error downloading or running script: ${e.message}")
        e.printStackTrace()
    } finally {
        // Ensure the script file is deleted even if an error happens
        if (destination.exists()) {
            println("Cleaning up script file...")
            destination.delete()
        }
    }
}

fun downloadFile(url: URL, destination: File) {
    url.openStream().use { inputStream ->
        Files.copy(inputStream, destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
    }
}
