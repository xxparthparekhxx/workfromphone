package com.example.workfromphone.container

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * `wfp/container` platform channel: setup (download/extract), start/stop,
 * and status for the on-device Debian container. Long operations post
 * progress on the `wfp/container_progress` event channel.
 *
 * Secrets policy: ACCESS_TOKEN arrives per-`start` call from
 * FlutterSecureStorage and is kept only in [LocalContainerService]'s
 * in-process config — never written to prefs, intents, or disk.
 */
class ContainerPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "wfp/container"
        const val EVENT_CHANNEL = "wfp/container_progress"

        fun register(engine: FlutterEngine, context: Context): ContainerPlugin {
            val plugin = ContainerPlugin(context.applicationContext)
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                .setMethodCallHandler(plugin)
            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
                .setStreamHandler(plugin.progressHandler)
            return plugin
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    val progressHandler = ProgressEvents()

    /** Guards against overlapping beginSetup dispatches (download+extract). */
    @Volatile
    private var setupInProgress = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> getStatus(result)
            "beginSetup" -> beginSetup(call, result)
            "start" -> start(call, result)
            "stop" -> {
                LocalContainerService.stop(context)
                result.success(mapOf("running" to false))
            }
            "getLogs" -> getLogs(call, result)
            "isBatteryExemptionGranted" -> result.success(isBatteryExemptionGranted())
            "requestBatteryExemption" -> {
                requestBatteryExemption()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun manager() = RootfsManager(context)

    private fun getStatus(result: MethodChannel.Result) {
        // isHealthy() does a blocking HTTP probe (2 s connect + 2 s read);
        // keep the whole body off the method-channel/UI thread.
        executor.execute {
            val manager = manager()
            val proot = manager.resolveProotBinary()
            result.success(
                mapOf(
                    "installed" to manager.isInstalled(),
                    "version" to manager.installedVersion(),
                    "running" to LocalContainerService.running,
                    "port" to LocalContainerService.activePort,
                    "healthy" to (LocalContainerService.running && ProotRunner.isHealthy(
                        LocalContainerService.activePort,
                    )),
                    "prootFound" to (proot != null),
                    "prootRuntimeReady" to manager.isProotRuntimeReady(),
                    "prootPath" to (proot?.absolutePath ?: ""),
                    "workspace" to manager.workspaceDir.absolutePath,
                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
                ),
            )
        }
    }

    private fun beginSetup(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val sha256 = call.argument<String>("sha256")?.trim().orEmpty()
        val version = call.argument<String>("version")?.trim().orEmpty()
        val sha256Valid = sha256.length == 64 &&
            sha256.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
        if (url.isEmpty() || !sha256Valid || version.isEmpty()) {
            result.error("bad-args", "url, sha256 (64 hex), and version are required", null)
            return
        }
        if (url.startsWith("http://")) {
            val host = runCatching { Uri.parse(url).host.orEmpty() }.getOrDefault("")
            if (host != "127.0.0.1" && host != "localhost") {
                result.error("insecure-url", "Rootfs URL must use https", null)
                return
            }
        } else if (!url.startsWith("https://")) {
            result.error("insecure-url", "Rootfs URL must use https", null)
            return
        }
        // Method calls arrive on the UI thread, so this check-then-set is
        // atomic with respect to other beginSetup calls.
        if (setupInProgress) {
            result.error("setup-in-progress", "Rootfs setup is already in progress", null)
            return
        }
        setupInProgress = true
        executor.execute {
            val manager = manager()
            try {
                progressHandler.emit(mapOf("phase" to "download", "progress" to 0))
                manager.download(url, sha256) { percent ->
                    progressHandler.emit(mapOf("phase" to "download", "progress" to percent))
                }
                progressHandler.emit(mapOf("phase" to "extract", "progress" to 0))
                manager.extract { percent ->
                    progressHandler.emit(mapOf("phase" to "extract", "progress" to percent))
                }
                manager.markInstalled(version)
                progressHandler.emit(mapOf("phase" to "done", "progress" to 100))
            } catch (e: Exception) {
                progressHandler.emit(
                    mapOf("phase" to "error", "progress" to 0, "message" to (e.message ?: "$e")),
                )
            } finally {
                setupInProgress = false
            }
        }
        result.success(mapOf("started" to true))
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val accessToken = call.argument<String>("accessToken")?.trim().orEmpty()
        val port = (call.argument<Number>("port")?.toInt() ?: LocalContainerService.DEFAULT_PORT)
            .coerceIn(1024, 65535)
        if (accessToken.isEmpty()) {
            result.error("no-token", "ACCESS_TOKEN is required, even on loopback", null)
            return
        }
        val manager = manager()
        if (!manager.isInstalled()) {
            result.error("not-installed", "Run setup first: rootfs is not installed", null)
            return
        }
        val proot = manager.resolveProotBinary()
        if (proot == null) {
            result.error(
                "no-proot",
                "Patched proot binary is missing from nativeLibraryDir",
                null,
            )
            return
        }
        val missingRuntime = ProotRunner.missingRuntimeLibs(manager.nativeLibraryDir())
        if (missingRuntime.isNotEmpty()) {
            result.error(
                "no-proot-runtime",
                "proot cannot start: missing ${missingRuntime.joinToString()} " +
                    "in nativeLibraryDir. Rebuild after running scripts/fetch-proot.sh.",
                null,
            )
            return
        }
        val workspaceArg = call.argument<String>("workspacePath")?.trim().orEmpty()
        val workspace = if (workspaceArg.isNotEmpty()) File(workspaceArg) else manager.workspaceDir
        workspace.mkdirs()
        LocalContainerService.start(
            context,
            ProotRunner.GuestConfig(
                prootBinary = proot,
                rootfsDir = manager.rootfsDir,
                workspaceDir = workspace,
                accessToken = accessToken,
                port = port,
            ),
        )
        result.success(mapOf("starting" to true, "port" to port))
    }

    private fun getLogs(call: MethodCall, result: MethodChannel.Result) {
        val maxBytes = (call.argument<Number>("maxBytes")?.toLong() ?: 65536L)
            .coerceIn(4096L, 262144L)
        // Log reads can block on I/O; keep them off the UI thread.
        executor.execute {
            val manager = manager()
            result.success(
                mapOf(
                    "backend" to tail(manager.logFile(), maxBytes),
                    "bootstrap" to tail(
                        java.io.File(manager.containerDir, "bootstrap.log"),
                        maxBytes,
                    ),
                    "nativeLibs" to describeNativeLibs(),
                ),
            )
        }
    }

    /** Lists nativeLibraryDir with sizes + md5 so we can tell whether the
     *  extracted proot matches the APK (stale-extraction detection). */
    private fun describeNativeLibs(): String {
        val dir = java.io.File(context.applicationInfo.nativeLibraryDir)
        val names = dir.list() ?: return "(nativeLibraryDir unreadable: $dir)"
        if (names.isEmpty()) return "(nativeLibraryDir empty: $dir)"
        return names.sorted().joinToString("\n") { name ->
            val f = java.io.File(dir, name)
            if (!f.isFile) {
                "$name: (not a file)"
            } else {
                val needed = if (name == "libproot.so") " needed=${elfNeeded(f)}" else ""
                "$name size=${f.length()} md5=${md5(f)} executable=${f.canExecute()}$needed"
            }
        }
    }

    private fun elfNeeded(file: java.io.File): String {
        return try {
            val bytes = file.readBytes()
            if (bytes.size < 5 || bytes[0] != 0x7F.toByte()) return "(not ELF)"
            val text = bytes.toString(Charsets.ISO_8859_1)
            Regex("lib[A-Za-z0-9+._-]+\\.so(?:\\.\\d+)?")
                .findAll(text)
                .map { it.value }
                .distinct()
                .joinToString(",")
                .ifEmpty { "(none)" }
        } catch (_: Exception) {
            "(unreadable)"
        }
    }

    private fun md5(file: java.io.File): String {
        return try {
            val digest = java.security.MessageDigest.getInstance("MD5")
            file.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            "unreadable"
        }
    }

    private fun tail(file: java.io.File, maxBytes: Long): String {
        if (!file.isFile) return "(no log yet: ${file.name})"
        // Read only the last maxBytes: the log grows without bound.
        val length = file.length()
        val sliceSize = minOf(maxBytes, length).toInt()
        val slice = ByteArray(sliceSize)
        if (sliceSize > 0) {
            java.io.RandomAccessFile(file, "r").use { raf ->
                raf.seek(length - sliceSize)
                raf.readFully(slice)
            }
        }
        // Drop a leading partial line so the view starts clean.
        val text = slice.toString(Charsets.UTF_8)
        val firstNewline = if (length > maxBytes) text.indexOf('\n') else -1
        return if (firstNewline >= 0) text.substring(firstNewline + 1) else text
    }

    private fun isBatteryExemptionGranted(): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestBatteryExemption() {
        if (isBatteryExemptionGranted()) return
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}"),
        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        runCatching { context.startActivity(intent) }
    }

    class ProgressEvents : EventChannel.StreamHandler {
        @Volatile
        private var sink: EventChannel.EventSink? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun emit(event: Map<String, Any?>) {
            // EventSink.success must run on the UI thread; setup runs on
            // a background executor (pool-*-thread-*), which otherwise
            // crashes with "Methods marked with @UiThread must be executed
            // on the main thread" as soon as download progress fires.
            if (Looper.myLooper() == Looper.getMainLooper()) {
                sink?.success(event)
            } else {
                mainHandler.post { sink?.success(event) }
            }
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
        }

        override fun onCancel(arguments: Any?) {
            sink = null
        }
    }
}
