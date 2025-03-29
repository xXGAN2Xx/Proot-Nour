#!/usr/bin/env kotlin

import java.io.File
import java.io.IOException

val scriptUrl = "https://github.com/xXGAN2Xx/proot-nour/raw/refs/heads/main/PteroVM.sh"
val scriptName = "PteroVM.sh"

fun runCommand(command: String): String {
    println("Running: $command")
    return try {
        val process = ProcessBuilder("/bin/bash", "-c", command)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        process.waitFor()
        println(output)
        output
    } catch (e: IOException) {
        println("Error running command: $e")
        ""
    }
}

// Step 1: Download the script
println("Downloading $scriptUrl...")
runCommand("curl -L -o $scriptName $scriptUrl")

// Step 2: Make it executable
println("Making $scriptName executable...")
runCommand("chmod +x $scriptName")

// Step 3: Run the script
println("Running $scriptName...")
runCommand("./$scriptName")
