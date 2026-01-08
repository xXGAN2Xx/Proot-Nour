import java.io.File
import java.io.IOException
import java.net.URI
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.util.Scanner
import kotlin.system.exitProcess

// All scripts will be saved as this filename locally
const val TARGET_SCRIPT_NAME = "start.sh"

// --- Custom Configuration ---
val SET_VM_MEMORY = System.getenv("SERVER_MEMORY")
val SET_OTHER_PORT = System.getenv("SERVER_PORT")
val SET_RDP_PORT = System.getenv("SERVER_PORT") 
// ----------------------------

data class ScriptOption(
    val name: String,
    val url: String
)

fun main() {
    val scanner = Scanner(System.`in`)
    
    val options = listOf(
        ScriptOption("Windows 10", "https://raw.githubusercontent.com/mrbeeenopro/lemem-10/refs/heads/main/start10.sh"),
        ScriptOption("Windows 11", "https://raw.githubusercontent.com/mrbeeenopro/lemem_windows/refs/heads/main/start.sh"),
        ScriptOption("Windows Server 2016", "https://raw.githubusercontent.com/mrbeeenopro/lemembox-windows-server-2016/refs/heads/main/start.sh"),
        ScriptOption("Tiny 10", "https://raw.githubusercontent.com/mrbeeenopro/lemem-box/refs/heads/main/tiny10.sh"),
        ScriptOption("Windows XP", "https://raw.githubusercontent.com/mrbeeenopro/lemem-box/refs/heads/main/xp.sh")
    )

    println("==========================================")
    println("   Select a version to install/run:")
    println("   (All will be saved as $TARGET_SCRIPT_NAME)")
    println("==========================================")
    
    options.forEachIndexed { index, option ->
        println("${index + 1}. ${option.name}")
    }
    println("==========================================")
    print("Enter number (1-${options.size}): ")

    var selectedOption: ScriptOption? = null

    while (selectedOption == null) {
        if (scanner.hasNextInt()) {
            val choice = scanner.nextInt()
            if (choice in 1..options.size) {
                selectedOption = options[choice - 1]
            } else {
                print("Invalid selection. Enter 1-${options.size}: ")
            }
        } else {
            scanner.next() 
            print("Invalid input. Please enter a number: ")
        }
    }

    val scriptUrl = selectedOption.url

    println("\nSelected: ${selectedOption.name}")

    try {
        // handleScript checks if start.sh exists and if it matches the selected URL
        // If it's different (e.g. you switched from Win10 to Win11), it will re-download.
        if (handleScript(TARGET_SCRIPT_NAME, scriptUrl)) {
            return
        }

        // Fallback if file didn't exist at all
        println("'$TARGET_SCRIPT_NAME' not found. Downloading...")
        val downloadedFile = downloadAndSetPermissions(scriptUrl, TARGET_SCRIPT_NAME)
        if (downloadedFile != null) {
            runScript(downloadedFile)
        } else {
            println("Failed to prepare '$TARGET_SCRIPT_NAME'.")
        }

    } catch (e: Exception) {
        println("An error occurred: ${e.message}")
        e.printStackTrace()
    }
}

fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)
    val fileToExecute: File
    val wasSuccessfullyUpdated: Boolean
    val isUpToDateAndSkippingPermSet: Boolean

    if (scriptFile.exists()) {
        println("Checking if existing '$scriptName' matches selection...")
        if (isFileChanged(scriptFile, scriptUrl)) {
            println("Local file differs from selection. Downloading correct version...")
            val updatedFile = downloadAndSetPermissions(scriptUrl, scriptName)
            if (updatedFile != null) {
                fileToExecute = updatedFile
                wasSuccessfullyUpdated = true
                isUpToDateAndSkippingPermSet = false
            } else {
                println("Update failed. Trying to run existing file anyway...")
                fileToExecute = scriptFile
                wasSuccessfullyUpdated = false
                isUpToDateAndSkippingPermSet = false
            }
        } else {
            println("Existing '$scriptName' is already the correct version.")
            fileToExecute = scriptFile
            wasSuccessfullyUpdated = false
            isUpToDateAndSkippingPermSet = true
        }
    } else {
        return false
    }

    var canRun = false
    if (wasSuccessfullyUpdated) {
        canRun = fileToExecute.canExecute()
    } else if (isUpToDateAndSkippingPermSet) {
        if (fileToExecute.canExecute()) {
            canRun = true
        } else {
            canRun = setExecutablePermission(fileToExecute)
        }
    } else {
        canRun = setExecutablePermission(fileToExecute)
    }

    if (canRun) {
        runScript(fileToExecute)
    } else {
        println("Error: Cannot execute '$scriptName'. Check permissions.")
    }
    return true
}

fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    try {
        val remoteContent = URI(remoteUrl).toURL().readText(Charsets.UTF_8)
        val localContent = localFile.readText(Charsets.UTF_8)
        return remoteContent.trim() != localContent.trim()
    } catch (e: Exception) {
        return true // Assume changed if we can't check
    }
}

fun downloadAndSetPermissions(scriptUrlString: String, scriptFileName: String): File? {
    val url = runCatching { URI(scriptUrlString).toURL() }.getOrNull() ?: return null
    val destinationFile = File(scriptFileName)

    try {
        downloadFile(url, destinationFile)
        setExecutablePermission(destinationFile)
        return destinationFile
    } catch (e: Exception) {
        println("Download error: ${e.message}")
        return null
    }
}

fun setExecutablePermission(file: File): Boolean {
    return try {
        val process = ProcessBuilder("chmod", "+x", file.absolutePath).start()
        process.waitFor() == 0
    } catch (e: Exception) {
        false
    }
}

fun runScript(scriptFile: File) {
    println("Starting execution of ${scriptFile.name}...")
    try {
        val processBuilder = ProcessBuilder("bash", scriptFile.absolutePath)
        val env = processBuilder.environment()
        
        if (SET_VM_MEMORY != null) env["VM_MEMORY"] = SET_VM_MEMORY
        if (SET_OTHER_PORT != null) env["OTHER_PORT"] = SET_OTHER_PORT
        if (SET_RDP_PORT != null) env["RDP_PORT"] = SET_RDP_PORT
        
        processBuilder.inheritIO()
        val process = processBuilder.start()
        val exitCode = process.waitFor()
        
        if (exitCode == 0) exitProcess(0)
    } catch (e: Exception) {
        println("Execution error: ${e.message}")
    }
}

fun downloadFile(url: java.net.URL, destination: File) {
    url.openStream().use { inputStream ->
        Files.copy(inputStream, destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
    }
}
