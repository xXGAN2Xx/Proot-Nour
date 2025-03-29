import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption

fun main() {
    val scriptUrl = URL("https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/PteroVM.sh")
    val scriptFile = File("PteroVM.sh")

    try {
        println("🔽 Downloading script...")
        downloadFile(scriptUrl, scriptFile.toPath())

        println("🔐 Setting executable permissions...")
        makeExecutable(scriptFile)

        println("🚀 Running script...")
        runScript(scriptFile)

        println("🧹 Cleaning up...")
        deleteFile(scriptFile)

        println("✅ Done.")
    } catch (e: Exception) {
        System.err.println("❌ Error during script execution: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: URL, destination: Path) {
    url.openStream().use { input ->
        Files.copy(input, destination, StandardCopyOption.REPLACE_EXISTING)
    }
}

fun makeExecutable(file: File) {
    if (!file.setExecutable(true)) {
        throw RuntimeException("Failed to set script as executable")
    }
}

fun runScript(file: File) {
    val process = ProcessBuilder("sh", file.name)
        .inheritIO()
        .start()
    val exitCode = process.waitFor()
    if (exitCode != 0) {
        throw RuntimeException("Script exited with code $exitCode")
    }
}

fun deleteFile(file: File) {
    if (file.exists() && !file.delete()) {
        println("⚠️ Warning: Failed to delete script file: ${file.absolutePath}")
    }
}
