import java.io.File
import java.io.IOException
import java.net.URI
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.util.Scanner
import kotlin.system.exitProcess

// All scripts will be saved as this filename locally
const val TARGET_SCRIPT_NAME = "nourwin.sh"
// The file that stores your choice
const val CONFIG_FILE = "selected_version.txt"

// --- Custom Configuration ---
val VM_MEMORY = System.getenv("SERVER_MEMORY")
val OTHER_PORT = System.getenv("SERVER_PORT")
val RDP_PORT = System.getenv("SERVER_PORT") 
// ----------------------------

data class ScriptOption(
    val name: String,
    val url: String
)

fun main() {
    val scanner = Scanner(System.`in`)
    println("Done (s)! For help, type help")
    val options = listOf(
        ScriptOption("Windows 10", "https://raw.githubusercontent.com/mrbeeenopro/lemem-10/refs/heads/main/start10.sh"),
        ScriptOption("Windows 11", "https://raw.githubusercontent.com/mrbeeenopro/lemem_windows/refs/heads/main/start.sh"),
        ScriptOption("Windows Server 2016", "https://raw.githubusercontent.com/mrbeeenopro/lemembox-windows-server-2016/refs/heads/main/start.sh"),
        ScriptOption("Tiny 10", "https://raw.githubusercontent.com/mrbeeenopro/lemem-box/refs/heads/main/tiny10.sh"),
        ScriptOption("Windows XP", "https://raw.githubusercontent.com/mrbeeenopro/lemem-box/refs/heads/main/xp.sh")
    )

    var selectedOption: ScriptOption? = loadSavedChoice(options)

    // If a choice was saved, give the user a moment to change it if they want
    if (selectedOption != null) {
        println("==========================================")
        println("Saved Choice: ${selectedOption.name}")
        println("Starting in 3 seconds... (Press 'c' and Enter to change version)")
        println("==========================================")
        
        // Non-blocking way to check for input (simplistic for script)
        val input = System.`in`.available()
        if (input > 0) {
            val next = scanner.next()
            if (next.lowercase() == "c") {
                selectedOption = null // Force menu
            }
        } else {
            // Wait a bit for user input
            Thread.sleep(1000) 
        }
    }

    // If no choice saved or user wants to change
    if (selectedOption == null) {
        println("==========================================")
        println("   Select a version to install/run:")
        println("==========================================")
        
        options.forEachIndexed { index, option ->
            println("${index + 1}. ${option.name}")
        }
        println("==========================================")
        print("Enter number (1-${options.size}): ")

        while (selectedOption == null) {
            if (scanner.hasNextInt()) {
                val choice = scanner.nextInt()
                if (choice in 1..options.size) {
                    selectedOption = options[choice - 1]
                    saveChoice(selectedOption!!)
                } else {
                    print("Invalid selection. Enter 1-${options.size}: ")
                }
            } else {
                scanner.next() 
                print("Invalid input. Please enter a number: ")
            }
        }
    }

    val scriptUrl = selectedOption!!.url
    println("\nSelected: ${selectedOption!!.name}")

    try {
        if (handleScript(TARGET_SCRIPT_NAME, scriptUrl)) {
            return
        }

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

// --- Persistence Logic ---

fun saveChoice(option: ScriptOption) {
    try {
        File(CONFIG_FILE).writeText("${option.name}\n${option.url}")
    } catch (e: Exception) {
        println("Warning: Could not save choice to disk.")
    }
}

fun loadSavedChoice(options: List<ScriptOption>): ScriptOption? {
    val file = File(CONFIG_FILE)
    if (!file.exists()) return null
    
    return try {
        val lines = file.readLines()
        if (lines.size >= 2) {
            // We return a new ScriptOption based on what's in the file
            ScriptOption(lines[0], lines[1])
        } else null
    } catch (e: Exception) {
        null
    }
}

// --- Existing Logic ---

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
        return true 
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
        
        if (VM_MEMORY != null) env["VM_MEMORY"] = VM_MEMORY
        if (OTHER_PORT != null) env["OTHER_PORT"] = OTHER_PORT
        if (RDP_PORT != null) env["RDP_PORT"] = RDP_PORT
        
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
