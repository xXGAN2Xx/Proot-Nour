import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption

fun main() {
    val url = URL("https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh")
    val destination = File("PteroVM.sh")

    try {
        downloadFile(url, destination)

        // Set executable permission on downloaded file
        val chmod = ProcessBuilder("chmod", "+x", destination.name)
        chmod.inheritIO()
        chmod.start().waitFor()

        // Run the downloaded file
        val harbor = ProcessBuilder("sh", destination.name)
        harbor.inheritIO()
        harbor.start().waitFor()

        // Remove the downloaded script after running
        destination.delete()
    } catch (e: Exception) {
        println("Error downloading or running script: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: URL, destination: File) {
    Files.copy(url.openStream(), Paths.get(destination.toURI()), StandardCopyOption.REPLACE_EXISTING)
}
