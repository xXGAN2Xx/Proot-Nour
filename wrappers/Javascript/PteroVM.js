import java.io.File
import java.io.IOException
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption

fun main() {
    val scriptUrl = "https://github.com/xXGAN2Xx/proot-nour/raw/refs/heads/main/PteroVM.sh"
    val scriptFile = File("PteroVM.sh")
    val deleteAfterRun = true

    try {
        println("📥 Downloading script from: $scriptUrl")
        downloadFile(URL(scriptUrl), scriptFile)
        println("✅ Downloaded to: ${scriptFile.absolutePath}")

        if (!scriptFile.setExecutable(true)) {
            println("⚠️ Failed to set executable permission via File API. Trying chmod...")
            if (isUnix()) {
                runCommand("chmod", "+x", scriptFile.name)
            } else {
                println("⚠️ Skipping chmod: Not a Unix-like OS.")
            }
        }

        println("🚀 Running script...")
        runCommand("sh", scriptFile.name)

        if (deleteAfterRun) {
            if (scriptFile.delete()) {
                println("🧹 Script deleted after execution.")
            } else {
                println("⚠️ Failed to delete script.")
            }
        }

    } catch (e: Exception) {
        System.err.println("❌ Error: ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: URL, destination: File) {
    url.openStream().use { input ->
        Files.copy(input, destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
    }
}

fun runCommand(vararg command: String) {
    val process = ProcessBuilder(*command)
        .inheritIO()
        .start()
    val exitCode = process.waitFor()
    if (exitCode != 0) {
        throw IOException("Command '${command.joinToString(" ")}' failed with exit code $exitCode")
    }
}

fun isUnix(): Boolean {
    val os = System.getProperty("os.name").lowercase()
    return os.contains("nix") || os.contains("nux") || os.contains("mac")
}
