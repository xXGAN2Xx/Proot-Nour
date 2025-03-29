import java.io.File
import java.io.IOException
import java.net.URL
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import kotlin.system.exitProcess

fun main() {
    val scriptUrl = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh"
    val scriptFile = File("PteroVM.sh")

    try {
        log("🔽 Downloading script from $scriptUrl")
        downloadFile(URL(scriptUrl), scriptFile.toPath())

        log("🔐 Making script executable")
        makeExecutable(scriptFile)

        log("🚀 Executing script")
        runScript(scriptFile)

        log("🧹 Cleaning up script file")
        deleteFile(scriptFile)

        log("✅ Script executed successfully.")
    } catch (e: Exception) {
        error("❌ Error: ${e.message}")
        e.printStackTrace()
        exitProcess(1)
    }
}

fun downloadFile(url: URL, destination: Path) {
    try {
        url.openStream().use { input ->
            Files.copy(input, destination, StandardCopyOption.REPLACE_EXISTING)
        }
    } catch (e: IOException) {
        throw IOException("Failed to download file from $url", e)
    }
}

fun makeExecutable(file: File) {
    if (!file.setExecutable(true)) {
        throw IOException("Unable to set executable permission on ${file.absolutePath}")
    }
}

fun runScript(file: File) {
    val process = ProcessBuilder("sh", file.absolutePath)
        .redirectErrorStream(true)
        .inheritIO()
        .start()

    val exitCode = process.waitFor()
    if (exitCode != 0) {
        throw RuntimeException("Script exited with non-zero code: $exitCode")
    }
}

fun deleteFile(file: File) {
    if (file.exists() && !file.delete()) {
        log("⚠️ Warning: Could not delete file ${file.absolutePath}")
    }
}

fun log(message: String) = println("[INFO] $message")
fun error(message: String) = System.err.println("[ERROR] $message")
