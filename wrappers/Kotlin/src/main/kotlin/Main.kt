import java.io.File
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.charset.Charsets // Added for specifying charset

const val NOUR_SCRIPT_NAME = "nour.sh"
const val NOURD_SCRIPT_NAME = "nourd.sh"
const val NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nour.sh"
const val NOURD_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/nourd.sh"

fun main() {
    val nourFile = File(NOUR_SCRIPT_NAME)
    val nourdFile = File(NOURD_SCRIPT_NAME)

    // Attempt to ensure both scripts are up-to-date or downloaded and executable
    val nourReady = checkAndUpdateScript(NOUR_SCRIPT_NAME, NOUR_URL)
    val nourdReady = checkAndUpdateScript(NOURD_SCRIPT_NAME, NOURD_URL)

    try {
        if (nourReady && nourFile.exists()) {
            println("Found and prepared '${nourFile.name}'. Preparing to run...")
            runScript(nourFile)
        } else if (nourdReady && nourdFile.exists()) {
            println("Found and prepared '${nourdFile.name}'. Preparing to run...")
            runScript(nourdFile)
        } else {
            println("Automatic preparation failed for one or both scripts, or they don't exist after attempts.")
            println("Please choose a script to download and run manually.")
            handleDownloadChoiceSetPermsAndRun() // Fallback to manual choice
        }
    } catch (e: Exception) {
        println("An error occurred in the main execution flow: ${e.message}")
        e.printStackTrace()
    }
}

/**
 * Checks if the script is up-to-date, downloads/updates if necessary, and sets executable permissions.
 * @return true if the script is ready to be run, false otherwise.
 */
fun checkAndUpdateScript(fileName: String, fileUrlString: String): Boolean {
    val localFile = File(fileName)
    val scriptUrl = URL(fileUrlString)

    try {
        println("Checking $fileName...")
        val remoteContent: String
        try {
            // Fetch remote content to compare
            remoteContent = scriptUrl.readText(Charsets.UTF_8)
        } catch (e: java.io.IOException) {
            println("Error fetching remote content for $fileName from $fileUrlString: ${e.message}")
            return false // Cannot proceed without remote content
        } catch (e: Exception) {
            println("Unexpected error fetching remote content for $fileName: ${e.message}")
            return false
        }

        if (localFile.exists()) {
            val localContent: String
            try {
                localContent = localFile.readText(Charsets.UTF_8)
            } catch (e: Exception) {
                println("Error reading local file $fileName: ${e.message}. Attempting to re-download.")
                // If local file can't be read, force download.
                println("Downloading $fileName due to local read error...")
                return try {
                    downloadFile(scriptUrl, localFile) // downloadFile overwrites
                    println("Download completed for $fileName.")
                    setExecutable(localFile)
                } catch (dlEx: Exception) {
                    println("Failed to download $fileName after read error: ${dlEx.message}")
                    false
                }
            }

            if (localContent == remoteContent) {
                println("$fileName is up to date.")
                // Ensure permissions are set, even if up-to-date, in case they were lost
                return if (setExecutable(localFile)) {
                    true
                } else {
                    println("Failed to ensure executable permission for up-to-date $fileName. Considering it not ready.")
                    false
                }
            } else {
                println("$fileName has changed. Downloading new version...")
                return try {
                    downloadFile(scriptUrl, localFile) // downloadFile overwrites
                    println("Download completed for $fileName.")
                    setExecutable(localFile)
                } catch (e: Exception) {
                    println("Error downloading updated $fileName: ${e.message}")
                    false
                }
            }
        } else { // File does not exist
            println("$fileName not found locally. Downloading...")
            return try {
                downloadFile(scriptUrl, localFile)
                println("Download completed for $fileName.")
                setExecutable(localFile)
            } catch (e: Exception) {
                println("Error downloading new $fileName: ${e.message}")
                false
            }
        }
    } catch (e: Exception) { // Catch other potential errors
        println("An unexpected error occurred while processing $fileName: ${e.message}")
        // e.printStackTrace() // Optional: for more detailed debugging
        return false
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

    try {
        println("Downloading '$scriptFileName' from $scriptUrlString...")
        downloadFile(url, destinationFile)
        println("Download completed.")

        if (setExecutable(destinationFile)) {
            runScript(destinationFile)
        } else {
            println("Script '${destinationFile.name}' will not be run due to permission setting failure.")
        }
    } catch (e: Exception) {
        println("An error occurred during manual download/run of $scriptFileName: ${e.message}")
        e.printStackTrace()
    }
}

fun runScript(scriptFile: File) {
    println("Running '${scriptFile.name}' and waiting for it to complete...")
    try {
        val processBuilder = ProcessBuilder("bash", scriptFile.path) // Use .path
        processBuilder.inheritIO()
        val process = processBuilder.start()
        val exitCode = process.waitFor()
        if (exitCode != 0) {
            println("'${scriptFile.name}' exited with code $exitCode.")
        } else {
            println("'${scriptFile.name}' completed successfully.")
        }
    } catch (e: Exception) {
        println("Failed to run script '${scriptFile.name}': ${e.message}")
        e.printStackTrace()
    }
}

fun downloadFile(url: URL, destination: File) {
    // This will throw an IOException if the download fails, which will be caught by the calling function.
    url.openStream().use { inputStream ->
        Files.copy(inputStream, Paths.get(destination.toURI()), StandardCopyOption.REPLACE_EXISTING)
    }
}

/**
 * Sets executable permission for the given file.
 * @return true if permission was set successfully, false otherwise.
 */
fun setExecutable(scriptFile: File): Boolean {
    // Check if the file exists before trying to set permissions
    if (!scriptFile.exists()) {
        println("Cannot set executable permission: File '${scriptFile.name}' does not exist.")
        return false
    }
    try {
        println("Setting executable permission on '${scriptFile.name}'...")
        val chmod = ProcessBuilder("chmod", "+x", scriptFile.path) // Use .path for reliability
        // chmod.inheritIO() // Optional: Show chmod output/errors, can be noisy if successful
        val chmodProcess = chmod.start()
        val chmodExitCode = chmodProcess.waitFor()

        if (chmodExitCode == 0) {
            println("Executable permission set for '${scriptFile.name}'.")
            return true
        } else {
            System.err.println("Error setting executable permission for '${scriptFile.name}' (exit code: $chmodExitCode). Check chmod output if inheritIO is enabled.")
            // Attempt to capture chmod error stream if not inheriting IO
            // val errorOutput = chmodProcess.errorStream.bufferedReader().readText()
            // if (errorOutput.isNotBlank()) System.err.println("chmod error: $errorOutput")
            return false
        }
    } catch (e: Exception) {
        println("Exception while setting executable permission for '${scriptFile.name}': ${e.message}")
        // e.printStackTrace() // For debugging
        return false
    }
}
