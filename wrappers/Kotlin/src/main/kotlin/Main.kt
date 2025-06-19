import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption

fun main() {
    val url = URL("https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nour.sh")
    val destination = File("nour.sh")
    
    try {
        // Check if the file already exists
        if (!destination.exists()) {
            println("File does not exist. Downloading...")
            downloadFile(url, destination)
            println("Download completed.")
        } else {
            println("File already exists. Skipping download.")
        }
        
        // Set executable permission on the file
        val chmod = ProcessBuilder("chmod", "+x", destination.name)
        chmod.inheritIO()
        chmod.start().waitFor()
        
        // Run the file
        val harbor = ProcessBuilder("bash", destination.name)
        harbor.inheritIO()
        harbor.start().waitFor()
                
    } catch (e: Exception) {
        println("Error downloading or running script: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: URL, destination: File) {
    Files.copy(url.openStream(), Paths.get(destination.toURI()), StandardCopyOption.REPLACE_EXISTING)
}
