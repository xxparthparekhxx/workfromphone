package com.example.workfromphone.container

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
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

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> getStatus(result)
            "beginSetup" -> beginSetup(call, result)
            "start" -> start(call, result)
            "stop" -> {
                LocalContainerService.stop(context)
                result.success(mapOf("running" to false))
            }
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
                "prootPath" to (proot?.absolutePath ?: ""),
                "workspace" to manager.workspaceDir.absolutePath,
                "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
            ),
        )
    }

    private fun beginSetup(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val sha256 = call.argument<String>("sha256")?.trim().orEmpty()
        val version = call.argument<String>("version")?.trim().orEmpty()
        if (url.isEmpty() || sha256.length != 64 || version.isEmpty()) {
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

        fun emit(event: Map<String, Any?>) {
            sink?.success(event)
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
        }

        override fun onCancel(arguments: Any?) {
            sink = null
        }
    }
}
