package com.example.workfromphone.container

import android.system.Os
import java.io.File

/**
 * Builds and supervises the `proot` guest process that hosts the backend.
 *
 * The proot binary must be resolved from `nativeLibraryDir`
 * (`.../lib/libproot.so`, installed from `jniLibs`): Android W^X forbids
 * executing files in app-writable directories, so a copy under `filesDir`
 * would fail with EACCES on exec.
 *
 * Termux's proot is a dynamic PIE that NEEDs `libtalloc.so.2` and
 * `libandroid-shmem.so`. AGP only packages `lib*.so`, and app processes
 * ignore LD_LIBRARY_PATH, so `scripts/patch-proot-dtneeded.py` rewrites
 * the talloc DT_NEEDED to `libtalloc.so` (shipped beside proot). The
 * loader lives as `libproot-loader.so` (PROOT_LOADER).
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
        // --kill-on-exit reaps the guest when the service stops;
        // --link2symlink is required on Android filesystems that reject
        // guest hardlinks (dpkg/apt inside Debian).
        // ACCESS_TOKEN stays in the process environment (not argv); the
        // inner `env -i` copies named vars so host linker paths do not
        // leak into Debian.
        val guestKeys = guestEnvironment(config).keys.joinToString(" ") { key ->
            "$key=\"\$$key\""
        }
        val quotedCommand = guestCommand.joinToString(" ") { shellQuote(it) }
        return listOf(
            config.prootBinary.absolutePath,
            "--kill-on-exit",
            "--link2symlink",
            "-0",
            "-r", config.rootfsDir.absolutePath,
            "-b", "${config.workspaceDir.absolutePath}:/workspace",
            "-w", "/workspace",
            "/bin/sh", "-c",
            "exec /usr/bin/env -i $guestKeys $quotedCommand",
        )
    }

    fun launchCommand(): List<String> =
        listOf("/bin/sh", "/opt/workfromphone/launch.sh")

    fun bootstrapCommand(): List<String> =
        listOf("/bin/sh", "/opt/workfromphone/bootstrap.sh")

    /** Guest-only environment. Host linker vars stay on ProcessBuilder. */
    fun guestEnvironment(config: GuestConfig): Map<String, String> = mapOf(
        "ACCESS_TOKEN" to config.accessToken,
        "PORT" to config.port.toString(),
        "HOST" to "127.0.0.1",
        "WORKSPACE" to "/workspace",
        "HOME" to "/home/coder",
        "TERM" to "xterm-256color",
        "LANG" to "C.UTF-8",
        "LC_ALL" to "C.UTF-8",
        "DEBIAN_FRONTEND" to "noninteractive",
        "PATH" to "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    )

    fun spawn(
        config: GuestConfig,
        guestCommand: List<String>,
        logFile: File,
    ): Process {
        logFile.parentFile?.mkdirs()
        val nativeDir = config.prootBinary.parentFile
            ?: throw IllegalStateException("proot binary has no parent directory")
        val missing = missingRuntimeLibs(nativeDir)
        if (missing.isNotEmpty()) {
            val message =
                "proot runtime is incomplete in $nativeDir (missing: " +
                    "${missing.joinToString()}). Rebuild after running " +
                    "scripts/fetch-proot.sh."
            logFile.appendText("\n[container] $message\n")
            throw IllegalStateException(message)
        }
        val aliasDir = nativeAliasDir(config)
        val tmpDir = tmpDir(config)
        aliasDir.mkdirs()
        tmpDir.mkdirs()
        // Harmless fallback if an old APK still NEEDs libtalloc.so.2; the
        // packaged binary is rewritten to libtalloc.so at fetch time.
        prepareTallocAlias(nativeDir, aliasDir)

        val builder = ProcessBuilder(argv(config, guestCommand))
        val env = builder.environment()
        env.putAll(guestEnvironment(config))
        // Host-only: stripped from the guest by `/usr/bin/env -i` above.
        env["LD_LIBRARY_PATH"] = listOf(
            aliasDir.absolutePath,
            nativeDir.absolutePath,
            env["LD_LIBRARY_PATH"].orEmpty(),
        ).filter { it.isNotEmpty() }.joinToString(":")
        env["PROOT_LOADER"] = File(nativeDir, "libproot-loader.so").absolutePath
        val loader32 = File(nativeDir, "libproot-loader32.so")
        if (loader32.isFile) {
            env["PROOT_LOADER_32"] = loader32.absolutePath
        }
        env["PROOT_TMP_DIR"] = tmpDir.absolutePath
        env["TMPDIR"] = tmpDir.absolutePath
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

    fun runtimeLibNames(): List<String> = listOf(
        "libtalloc.so",
        "libandroid-shmem.so",
        "libproot-loader.so",
    )

    fun missingRuntimeLibs(nativeDir: File): List<String> =
        runtimeLibNames().filter { !File(nativeDir, it).isFile }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"

    private fun containerDir(config: GuestConfig): File = config.rootfsDir.parentFile
        ?: throw IllegalStateException("rootfs has no parent directory")

    private fun nativeAliasDir(config: GuestConfig): File =
        File(containerDir(config), "native-aliases")

    private fun tmpDir(config: GuestConfig): File =
        File(containerDir(config), "tmp")

    /**
     * AGP will not package `libtalloc.so.2` (name does not end in `.so`).
     * Point a filesDir symlink at the real library in nativeLibraryDir so
     * the bionic linker can resolve DT_NEEDED without copying a writable
     * (and therefore non-executable) .so.
     */
    private fun prepareTallocAlias(nativeDir: File, aliasDir: File) {
        val target = File(nativeDir, "libtalloc.so")
        val link = File(aliasDir, "libtalloc.so.2")
        val linkPath = link.toPath()
        // nativeLibraryDir changes on every APK install (the ~~hash==/ path),
        // so a leftover dangling symlink would make Os.symlink fail with EEXIST.
        if (java.nio.file.Files.exists(
                linkPath,
                java.nio.file.LinkOption.NOFOLLOW_LINKS,
            )
        ) {
            java.nio.file.Files.delete(linkPath)
        }
        Os.symlink(target.absolutePath, link.absolutePath)
    }
}
