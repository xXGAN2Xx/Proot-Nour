import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption

const val NOUR_SCRIPT_NAME = "nour.sh"
const val NOURD_SCRIPT_NAME = "nourd.sh"
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nour.sh"
const val NOURD_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nourd.sh"

fun main() {
    val nourFile = File(NOUR_SCRIPT_NAME)
    val nourdFile = File(NOURD_SCRIPT_NAME)

    try {
        if (nourFile.exists()) {
            println("Found '${nourFile.name}'. Preparing to run...")
            runScript(nourFile) // Permissions are assumed to be set
        } else if (nourdFile.exists()) {
            println("Found '${nourdFile.name}'. Preparing to run...")
            runScript(nourdFile) // Permissions are assumed to be set
        } else {
            println("Neither '${nourFile.name}' nor '${nourdFile.name}' found. Please choose a script to download.")
            handleDownloadChoiceSetPermsAndRun()
        }
    } catch (e: Exception) {
        println("An error occurred: ${e.message}")
        e.printStackTrace()
    }
}

fun handleDownloadChoiceSetPermsAndRun() {
    println("Choose an option to download:")
    println("0: Download $NOUR_SCRIPT_NAME")
    println("1: Download $NOURD_SCRIPT_NAME")
    print("Enter your choice (0 or 1): ")

    val choice = readlnOrNull()

    val scriptUrlString: String
    val scriptFileName: String

    when (choice) {
        "0" -> {
            scriptUrlString = NOUR_URL
            scriptFileName = NOUR_SCRIPT_NAME
        }
        "1" -> {
            scriptUrlString = NOURD_URL
            scriptFileName = NOURD_SCRIPT_NAME
        }
        else -> {
            println("Invalid choice. Please enter 0 or 1. Exiting.")
            return
        }
    }

    val url = URL(scriptUrlString)
    val destinationFile = File(scriptFileName)

    println("Downloading '$scriptFileName' from $scriptUrlString...")
    downloadFile(url, destinationFile)
    println("Download completed.")

    // Set executable permission ONLY after download
    println("Setting executable permission on '${destinationFile.name}'...")
    val chmod = ProcessBuilder("chmod", "+x", destinationFile.name)
    chmod.inheritIO()
    val chmodProcess = chmod.start()
    val chmodExitCode = chmodProcess.waitFor() // Wait for chmod to complete

    if (chmodExitCode != 0) {
        println("Error setting executable permission for '${destinationFile.name}' (exit code: $chmodExitCode). Script will not be run.")
        return
    } else {
        println("Executable permission set for '${destinationFile.name}'.")
    }

    runScript(destinationFile) // Now run the script
}

fun runScript(scriptFile: File) {
    println("Running '${scriptFile.name}' and waiting for it to complete...") // Updated message
    val harbor = ProcessBuilder("bash", scriptFile.name)
    harbor.inheritIO()
    val harborProcess = harbor.start() // Assign the process
    val harborExitCode = harborProcess.waitFor() // Wait for the script to finish
    println("Script '${scriptFile.name}' finished with exit code $harborExitCode.") // Updated message
}

fun downloadFile(url: URL, destination: File) {
    url.openStream().use { inputStream ->
        Files.copy(inputStream, Paths.get(destination.toURI()), StandardCopyOption.REPLACE_EXISTING)
    }
}
