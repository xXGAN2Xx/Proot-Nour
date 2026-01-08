import java.io.File
import kotlin.system.exitProcess

const val LOCAL_SCRIPT_NAME = "nourt.sh"



fun main() {
    val scriptFile = File(LOCAL_SCRIPT_NAME)
    println("Done (s)! For help, type help")
    try {
        if (!scriptFile.exists()) {
            println("'$LOCAL_SCRIPT_NAME' not found. Creating empty file...")
            scriptFile.createNewFile() 
            
            ProcessBuilder("chmod", "+x", scriptFile.absolutePath).start().waitFor()
        }

        executeScript(scriptFile)

    } catch (e: Exception) {
        println("Error: ${e.message}")
    }
}

fun executeScript(file: File) {
    println("Running '${file.name}'...")
    try {
        val process = ProcessBuilder("bash", file.absolutePath)
            .inheritIO()
            .start()
        
        val exitCode = process.waitFor()
        if (exitCode == 0) {
            exitProcess(0)
        }
    } catch (e: Exception) {
        println("Execution failed: ${e.message}")
    }
}
