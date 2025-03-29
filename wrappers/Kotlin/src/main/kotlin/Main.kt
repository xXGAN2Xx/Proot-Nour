import java.io.File

fun runCommand(command: List<String>, workingDir: File = File(".")) {
    println("Running: ${command.joinToString(" ")}")
    val process = ProcessBuilder(command)
        .directory(workingDir)
        .redirectErrorStream(true)
        .start()

    process.inputStream.bufferedReader().use { reader ->
        reader.lines().forEach { println(it) }
    }

    val exitCode = process.waitFor()
    if (exitCode != 0) {
        throw RuntimeException("Command failed: ${command.joinToString(" ")} (Exit code: $exitCode)")
    }
}

fun main() {
    val rootFsDir = File("debian-fs")
    val prootFile = File("proot")

    if (!prootFile.exists()) {
        println("Downloading PRoot...")
        runCommand(listOf("wget", "https://github.com/proot-me/proot/releases/download/v5.1.0/proot-static-x86_64"), File("."))
        prootFile.renameTo(File("proot"))
        runCommand(listOf("chmod", "+x", "proot"), File("."))
    }

    if (!rootFsDir.exists()) {
        println("Creating Debian filesystem...")
        rootFsDir.mkdir()
        // Download Debian rootfs - ensure architecture is correct (e.g., amd64)
        runCommand(listOf("wget", "https://deb.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/netboot.tar.gz"), rootFsDir)
        println("Downloading rootfs using debootstrap or rootfs tarball...")

        // Quick method: Use prebuilt rootfs tarball
        runCommand(listOf("wget", "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-amd64/bookworm/slim/rootfs.tar.xz"), File("."))
        println("Extracting rootfs...")
        runCommand(listOf("tar", "-xJf", "rootfs.tar.xz", "-C", rootFsDir.absolutePath))
    }

    // Create start script
    val startScript = File("start-debian.sh")
    startScript.writeText(
        """
        #!/bin/bash
        unset LD_PRELOAD
        ./proot -0 -r debian-fs -b /dev -b /proc -b /sys -w /root /bin/bash
        """.trimIndent()
    )
    runCommand(listOf("chmod", "+x", "start-debian.sh"))

    println("Setup complete! Run ./start-debian.sh to enter Debian environment.")
}
