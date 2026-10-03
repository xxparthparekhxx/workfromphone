package com.example.workfromphone.container

import android.content.Context
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.zip.GZIPInputStream

/**
 * Downloads, verifies, extracts, and patches the Debian rootfs.
 *
 * Storage: app-private `filesDir/container/` (scoped-storage safe, no
 * broad storage permissions needed):
 *   - `rootfs.tar.gz`        downloaded archive (kept for re-extract)
 *   - `rootfs/`              extracted Debian userland (proot `-r` target)
 *   - `rootfs/.installed_version`
 *   - `workspace/`           default bind-mounted workspace (`-b ...:/workspace`)
 *
 * Progress is reported through [onProgress] as 0..100. Throws on any
 * failure; callers surface the message in the setup wizard.
 */
class RootfsManager(private val context: Context) {

    val containerDir: File get() = File(context.filesDir, "container")
    val rootfsDir: File get() = File(containerDir, "rootfs")
    val archiveFile: File get() = File(containerDir, "rootfs.tar.gz")
    val versionFile: File get() = File(rootfsDir, ".installed_version")
    val workspaceDir: File get() = File(containerDir, "workspace")

    fun isInstalled(): Boolean =
        rootfsDir.isDirectory &&
            File(rootfsDir, "opt/workfromphone/launch.sh").isFile

    fun installedVersion(): String? =
        versionFile.takeIf { it.isFile }?.readText()?.trim()?.ifEmpty { null }

    fun nativeLibraryDir(): File = File(context.applicationInfo.nativeLibraryDir)

    fun resolveProotBinary(): File? {
        // Installed from jniLibs/<abi>/libproot.so into nativeLibraryDir.
        val candidates = listOf(
            File(nativeLibraryDir(), "libproot.so"),
            File(nativeLibraryDir(), "proot"),
        )
        return candidates.firstOrNull { it.isFile && it.canExecute() }
            ?: candidates.firstOrNull { it.isFile }
    }

    fun isProotRuntimeReady(): Boolean {
        if (resolveProotBinary() == null) return false
        return ProotRunner.missingRuntimeLibs(nativeLibraryDir()).isEmpty()
    }

    @Throws(Exception::class)
    fun download(url: String, expectedSha256: String, onProgress: (Int) -> Unit) {
        containerDir.mkdirs()
        val tmp = File(containerDir, "rootfs.tar.gz.part")
        var connection: HttpURLConnection? = null
        try {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.connect()
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("Download failed: HTTP ${connection.responseCode}")
            }
            val total = connection.contentLengthLong.takeIf { it > 0 }
            BufferedInputStream(connection.inputStream).use { input ->
                FileOutputStream(tmp).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var received = 0L
                    var lastReported = -1
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        received += read
                        if (total != null) {
                            val percent = ((received * 100) / total).toInt().coerceIn(0, 100)
                            if (percent != lastReported) {
                                lastReported = percent
                                onProgress(percent)
                            }
                        }
                    }
                }
            }
        } finally {
            connection?.disconnect()
        }
        verifySha256(tmp, expectedSha256)
        if (archiveFile.exists()) archiveFile.delete()
        if (!tmp.renameTo(archiveFile)) {
            tmp.copyTo(archiveFile, overwrite = true)
            tmp.delete()
        }
        onProgress(100)
    }

    @Throws(Exception::class)
    fun verifySha256(file: File, expectedHex: String) {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (!constantTimeEquals(actual.lowercase(), expectedHex.trim().lowercase())) {
            throw SecurityException(
                "Rootfs checksum mismatch: refusing to extract an untrusted archive",
            )
        }
    }

    /** Constant-time hex comparison so verification isn't oracle-shortened. */
    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].code xor b[i].code)
        return diff == 0
    }

    @Throws(Exception::class)
    fun extract(onProgress: (Int) -> Unit) {
        if (!archiveFile.isFile) throw IllegalStateException("Rootfs archive is missing")
        deleteRecursively(rootfsDir)
        rootfsDir.mkdirs()
        TarGz.extract(archiveFile, rootfsDir, onProgress)
        applyPatches()
    }

    /**
     * DNS / locale / identity patches every proot guest needs: the host's
     * network DNS isn't visible inside the container, and a missing hostname
     * breaks sudo/apt/dpkg configuration scripts.
     */
    @Throws(Exception::class)
    fun applyPatches() {
        File(rootfsDir, "etc/resolv.conf").apply {
            parentFile?.mkdirs()
            writeText("nameserver 1.1.1.1\nnameserver 8.8.8.8\n")
        }
        File(rootfsDir, "etc/hostname").apply {
            parentFile?.mkdirs()
            writeText("workfromphone\n")
        }
        File(rootfsDir, "etc/hosts").apply {
            parentFile?.mkdirs()
            if (!exists()) writeText("127.0.0.1 localhost workfromphone\n::1 localhost\n")
        }
        File(rootfsDir, "etc/default/locale").apply {
            parentFile?.mkdirs()
            writeText("LANG=C.UTF-8\nLC_ALL=C.UTF-8\n")
        }
        workspaceDir.mkdirs()
        // dpkg/status must exist for apt installs inside minimal debootstrap.
        File(rootfsDir, "var/lib/dpkg/status").apply {
            if (!exists()) {
                parentFile?.mkdirs()
                createNewFile()
            }
        }
    }

    fun markInstalled(version: String) {
        versionFile.parentFile?.mkdirs()
        versionFile.writeText(version.trim())
    }

    fun logFile(): File = File(containerDir, "backend.log")

    private fun deleteRecursively(file: File) {
        if (file.isDirectory) file.listFiles()?.forEach(::deleteRecursively)
        file.delete()
    }
}

/**
 * Minimal tar.gz extractor (directories, files, symlinks, hardlinks) so
 * setup needs no third-party archive dependency. GNU long-name (`L`/`K`)
 * entries supported. Hardlink sources may appear later in the archive, so
 * unresolvable links are deferred and retried once extraction finishes.
 */
object TarGz {

    fun extract(archive: File, destDir: File, onProgress: (Int) -> Unit) {
        val total = archive.length().coerceAtLeast(1L)
        var processed = 0L
        var lastReported = -1
        GZIPInputStream(CountingInputStream(FileInputStream(archive)) { processed = it }).use { gzip ->
            var pendingLongName: String? = null
            var pendingLongTarget: String? = null
            val pendingHardLinks = mutableListOf<Pair<File, File>>()
            while (true) {
                val header = ByteArray(512)
                if (!readFully(gzip, header)) break
                if (header.all { it == 0.toByte() }) {
                    // Two zero blocks end the archive; one is enough to stop.
                    break
                }
                val name = pendingLongName
                    ?: header.copyOfRange(0, 100).cstring()
                pendingLongName = null
                val type = header[156].toInt().toChar()
                val size = header.copyOfRange(124, 136).cstring().trim()
                    .takeIf { it.isNotEmpty() }?.toLong(8) ?: 0L
                val target = File(destDir, name).canonicalFile
                require(target.path == destDir.canonicalPath ||
                    target.path.startsWith(destDir.canonicalPath + File.separator)) {
                    "Archive entry escapes destination: $name"
                }
                when (type) {
                    'L' -> {
                        // GNU longname: the data block holds the name of the
                        // next entry; must be consumed to stay aligned.
                        pendingLongName = readSized(gzip, size).toString(Charsets.UTF_8).trimEnd('\u0000')
                        skipPadding(gzip, size)
                    }
                    'K' -> {
                        // GNU longlink: the data block holds the LINK TARGET
                        // of the next entry (symlink/hardlink whose target
                        // overflows the 100-byte header field).
                        pendingLongTarget = readSized(gzip, size).toString(Charsets.UTF_8).trimEnd('\u0000')
                        skipPadding(gzip, size)
                    }
                    '5' -> {
                        target.mkdirs()
                        setMode(target, header)
                    }
                    '2' -> {
                        val linkTarget = pendingLongTarget
                            ?: header.copyOfRange(157, 257).cstring()
                        pendingLongTarget = null
                        target.parentFile?.mkdirs()
                        target.delete()
                        java.nio.file.Files.createSymbolicLink(
                            target.toPath(),
                            java.nio.file.Paths.get(linkTarget),
                        )
                    }
                    '1' -> {
                        // Hard link: linkname holds the archive-relative path
                        // of an entry that must share the same inode
                        // (debootstrap rootfs images are full of these).
                        val linkTarget = pendingLongTarget
                            ?: header.copyOfRange(157, 257).cstring()
                        pendingLongTarget = null
                        val source = File(destDir, linkTarget).canonicalFile
                        require(source.path == destDir.canonicalPath ||
                            source.path.startsWith(destDir.canonicalPath + File.separator)) {
                            "Archive hardlink escapes destination: $name -> $linkTarget"
                        }
                        linkOrDefer(target, source, pendingHardLinks)
                    }
                    else -> {
                        target.parentFile?.mkdirs()
                        FileOutputStream(target).use { out ->
                            copySized(gzip, out, size)
                        }
                        setMode(target, header)
                    }
                }
                skipPadding(gzip, size)
                val percent = ((processed * 100) / total).toInt().coerceIn(0, 100)
                if (percent != lastReported) {
                    lastReported = percent
                    onProgress(percent)
                }
            }
            // Hardlink sources may be archived after their links; retry
            // deferred links now that every entry has been extracted.
            for ((link, source) in pendingHardLinks) {
                if (!createHardLink(link, source)) {
                    throw IllegalStateException(
                        "Unresolvable hardlink: ${link.path} -> ${source.path}",
                    )
                }
            }
        }
        onProgress(100)
    }

    private fun linkOrDefer(
        link: File,
        source: File,
        pending: MutableList<Pair<File, File>>,
    ) {
        if (!createHardLink(link, source)) pending.add(link to source)
    }

    private fun createHardLink(link: File, source: File): Boolean {
        if (!source.isFile) return false
        return runCatching {
            link.parentFile?.mkdirs()
            link.delete()
            java.nio.file.Files.createLink(link.toPath(), source.toPath())
            true
        }.getOrDefault(false)
    }

    private fun setMode(target: File, header: ByteArray) {
        val mode = header.copyOfRange(100, 108).cstring().trim()
            .takeIf { it.isNotEmpty() }?.toInt(8) ?: return
        runCatching {
            val perms = mutableSetOf<java.nio.file.attribute.PosixFilePermission>()
            val values = java.nio.file.attribute.PosixFilePermission.values()
            // Map low 9 unix bits onto PosixFilePermission entries.
            for (i in 0 until 9) {
                if (mode and (1 shl (8 - i)) != 0) perms.add(values[i])
            }
            java.nio.file.Files.setPosixFilePermissions(target.toPath(), perms)
        }
    }

    private fun ByteArray.cstring(): String {
        val end = indexOf(0.toByte()).takeIf { it >= 0 } ?: size
        return copyOfRange(0, end).toString(Charsets.UTF_8)
    }

    private fun readFully(input: java.io.InputStream, buffer: ByteArray): Boolean {
        var offset = 0
        while (offset < buffer.size) {
            val read = input.read(buffer, offset, buffer.size - offset)
            // A short read at EOF is a truncated final header block: stop
            // (normal end-of-archive is the all-zero header; extraction is
            // SHA-256-gated upstream, so stopping is safe).
            if (read < 0) return offset == 0
            offset += read
        }
        return true
    }

    private fun readSized(input: java.io.InputStream, size: Long): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        copySized(input, out, size)
        return out.toByteArray()
    }

    private fun copySized(input: java.io.InputStream, out: java.io.OutputStream, size: Long) {
        var remaining = size
        val buffer = ByteArray(32 * 1024)
        while (remaining > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (read < 0) break
            out.write(buffer, 0, read)
            remaining -= read
        }
    }

    private fun skipPadding(input: java.io.InputStream, size: Long) {
        val pad = ((512 - (size % 512)) % 512)
        var remaining = pad
        val buffer = ByteArray(512)
        while (remaining > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (read < 0) break
            remaining -= read
        }
    }

    private class CountingInputStream(
        private val wrapped: java.io.InputStream,
        private val onBytes: (Long) -> Unit,
    ) : java.io.InputStream() {
        private var count = 0L
        override fun read(): Int {
            val b = wrapped.read()
            if (b >= 0) onBytes(++count)
            return b
        }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            val read = wrapped.read(b, off, len)
            if (read > 0) onBytes(count + read)
            if (read > 0) count += read
            return read
        }
        override fun close() = wrapped.close()
    }
}
