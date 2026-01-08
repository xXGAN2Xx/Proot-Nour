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
    // Print requested help message at start
    println("Done (s)! For help, type help")

    val scanner = Scanner(System.`in`)
    
    val options = listOf(
        ScriptOption("Windows 10", "https://raw.githubusercontent.com/mrbeeenopro/lemem-10/refs/heads/main/start10.sh"),
        ScriptOption("Windows 11", "https://raw.githubusercontent.com/mrbeeenopro/lemem_windows/refs/heads/main/start.sh"),
        ScriptOption("Windows Server 2016", "https://raw.githubusercontent.com/mrbeeenopro/lemembox-windows-server-2016/refs/heads/main/start.sh"),
        ScriptOption("Tiny 10", "https://raw.githubusercontent.com/mrbeeenopro/lemem-box/refs/heads/main/tiny10.sh"),
        ScriptOption("Windows XP", "https://raw.githubusercontent.com/mrbeeenopro/lemem-box/refs/heads/main/xp.sh")
    )

    var selectedOption: ScriptOption? = loadSavedChoice(options)

    // If a choice was saved, give a brief moment to change it
    if (selectedOption != null) {
        println("==========================================")
        println("Saved Choice: ${selectedOption.name}")
        println("Starting... (To change, type 'help' or 'change')")
        println("==========================================")
        
        // Non-blocking check for input
        if (System.`in`.available() > 0) {
            val input = scanner.next().lowercase()
            if (input == "help" || input == "change") {
                selectedOption = null
            }
        } else {
            // Half-second pause to allow user to interrupt
            Thread.sleep(500) 
        }
    }

    // Menu logic if no choice is saved or user wants to change
    if (selectedOption == null) {
        showMenu(options)
        
        var tempOption: ScriptOption? = null
        while (tempOption == null) {
            print("Enter choice (1-${options.size}): ")
            val input = scanner.next()

            if (input.lowercase() == "help") {
                showMenu(options)
                continue
            }

            val choice = input.toIntOrNull()
            if (choice != null && choice in 1..options.size) {
                tempOption = options[choice - 1]
                saveChoice(tempOption)
            } else {
                println("Invalid input. Type a number (1-${options.size}) or 'help'.")
            }
        }
        selectedOption = tempOption
    }

    // Fixed: The compiler knows selectedOption is not null here, so no !! or ?: needed.
    val scriptUrl = selectedOption.url
    println("\nSelected: ${selectedOption.name}")

    try {
        if (handleScript(TARGET_SCRIPT_NAME, scriptUrl)) {
            return
        }

        println("'$TARGET_SCRIPT_NAME' not found. Downloading...")
        val downloadedFile = downloadAndSetPermissions(scriptUrl, TARGET_SCRIPT_NAME)
        if (downloadedFile != null) {
            runScript(downloadedFile)
        }
    } catch (e: Exception) {
        println("An error occurred: ${e.message}")
    }
}

fun showMenu(options: List<ScriptOption>) {
    println("==========================================")
    println("   Select a version to install/run:")
    println("==========================================")
    options.forEachIndexed { index, option ->
        println("${index + 1}. ${option.name}")
    }
    println("==========================================")
}

// --- Persistence Logic ---

fun saveChoice(option: ScriptOption) {
    try {
        File(CONFIG_FILE).writeText("${option.name}\n${option.url}")
    } catch (e: Exception) {
        // Silently fail if we can't save
    }
}

fun loadSavedChoice(options: List<ScriptOption>): ScriptOption? {
    val file = File(CONFIG_FILE)
    if (!file.exists()) return null
    return try {
        val lines = file.readLines()
        if (lines.size >= 2) ScriptOption(lines[0], lines[1]) else null
    } catch (e: Exception) {
        null
    }
}

// --- Script Handling Logic ---

fun handleScript(scriptName: String, scriptUrl: String): Boolean {
    val scriptFile = File(scriptName)
    if (scriptFile.exists()) {
        println("Checking if existing '$scriptName' matches selection...")
        val fileToExecute: File
        if (isFileChanged(scriptFile, scriptUrl)) {
            println("Version changed. Downloading update...")
            fileToExecute = downloadAndSetPermissions(scriptUrl, scriptName) ?: scriptFile
        } else {
            println("Existing version is up to date.")
            fileToExecute = scriptFile
        }
        
        setExecutablePermission(fileToExecute)
        runScript(fileToExecute)
        return true
    }
    return false
}

fun isFileChanged(localFile: File, remoteUrl: String): Boolean {
    return try {
        val remoteContent = URI(remoteUrl).toURL().readText(Charsets.UTF_8).trim()
        val localContent = localFile.readText(Charsets.UTF_8).trim()
        remoteContent != localContent
    } catch (e: Exception) {
        true 
    }
}

fun downloadAndSetPermissions(scriptUrlString: String, scriptFileName: String): File? {
    return try {
        val url = URI(scriptUrlString).toURL()
        val destination = File(scriptFileName)
        url.openStream().use { inputStream ->
            Files.copy(inputStream, destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        setExecutablePermission(destination)
        destination
    } catch (e: Exception) {
        println("Download error: ${e.message}")
        null
    }
}

fun setExecutablePermission(file: File): Boolean {
    return try {
        ProcessBuilder("chmod", "+x", file.absolutePath).start().waitFor() == 0
    } catch (e: Exception) {
        false
    }
}

fun runScript(scriptFile: File) {
    println("Starting execution of ${scriptFile.name}...")
    try {
        val processBuilder = ProcessBuilder("bash", scriptFile.absolutePath)
        val env = processBuilder.environment()
        VM_MEMORY?.let { env["VM_MEMORY"] = it }
        OTHER_PORT?.let { env["OTHER_PORT"] = it }
        RDP_PORT?.let { env["RDP_PORT"] = it }
        
        processBuilder.inheritIO()
        val process = processBuilder.start()
        val exitCode = process.waitFor()
        if (exitCode == 0) exitProcess(0)
    } catch (e: Exception) {
        println("Execution error: ${e.message}")
    }
}
