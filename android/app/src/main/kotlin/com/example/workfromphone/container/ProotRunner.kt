package com.example.workfromphone.container

import java.io.File

/**
 * Builds and supervises the `proot` guest process that hosts the backend.
 *
 * The proot binary must be resolved from `nativeLibraryDir`
 * (`.../lib/libproot.so`, installed from `jniLibs`): Android W^X forbids
 * executing files in app-writable directories, so a copy under `filesDir`
 * would fail with EACCES on exec. The same argv works with `proroot`
 * should the patched proot ever need replacing.
 */
object ProotRunner {

    data class GuestConfig(
        val prootBinary: File,
        val rootfsDir: File,
        val workspaceDir: File,
        val accessToken: String,
        val port: Int,
    )

    fun argv(config: GuestConfig, guestCommand: List<String>): List<String> {
        require(config.accessToken.isNotBlank()) {
            "ACCESS_TOKEN is mandatory, even on loopback"
        }
        // proot already binds /proc, /sys, and /dev from the host by
        // default; only the workspace needs an explicit bind.
        return listOf(
            config.prootBinary.absolutePath,
            "-r", config.rootfsDir.absolutePath,
            "-b", "${config.workspaceDir.absolutePath}:/workspace",
            "-0",
            "-w", "/workspace",
        ) + guestCommand
    }

    fun launchCommand(): List<String> =
        listOf("/bin/sh", "/opt/workfromphone/launch.sh")

    fun bootstrapCommand(): List<String> =
        listOf("/bin/sh", "/opt/workfromphone/bootstrap.sh")

    fun environment(config: GuestConfig): Map<String, String> = mapOf(
        "ACCESS_TOKEN" to config.accessToken,
        "PORT" to config.port.toString(),
        "HOST" to "127.0.0.1",
        "WORKSPACE" to "/workspace",
        "HOME" to "/home/coder",
        "TERM" to "xterm-256color",
    )

    fun spawn(
        config: GuestConfig,
        guestCommand: List<String>,
        logFile: File,
    ): Process {
        logFile.parentFile?.mkdirs()
        val builder = ProcessBuilder(argv(config, guestCommand))
        builder.environment().putAll(environment(config))
        // Keep the backend's stdout/stderr out of logcat and in one file
        // the Flutter UI can surface on failure.
        builder.redirectOutput(ProcessBuilder.Redirect.appendTo(logFile))
        builder.redirectError(ProcessBuilder.Redirect.appendTo(logFile))
        return builder.start()
    }

    fun stop(process: Process?) {
        if (process == null || !process.isAlive) return
        // The guest is a process group leader only inside proot's view, so
        // escalate: TERM, brief grace period, then KILL.
        process.destroy()
        try {
            Thread.sleep(1500)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        if (process.isAlive) process.destroyForcibly()
    }

    /** Polls the public health endpoint until it answers or [timeoutMs] elapses. */
    fun waitForHealth(port: Int, timeoutMs: Long = 30_000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (isHealthy(port)) return true
            try {
                Thread.sleep(500)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
        }
        return isHealthy(port)
    }

    fun isHealthy(port: Int): Boolean {
        var connection: java.net.HttpURLConnection? = null
        return try {
            val url = java.net.URL("http://127.0.0.1:$port/api/v1/health")
            connection = url.openConnection() as java.net.HttpURLConnection
            connection.connectTimeout = 2000
            connection.readTimeout = 2000
            connection.connect()
            connection.responseCode == 200
        } catch (_: Exception) {
            false
        } finally {
            connection?.disconnect()
        }
    }
}
