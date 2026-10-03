package com.example.workfromphone.container

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Foreground service owning the on-device Debian container.
 *
 * Holds a partial wakelock so aggressive OEM task killers don't freeze the
 * backend while the screen is off, and posts an ongoing notification with a
 * Stop action (required for foreground services; also the Play-policy
 * visible indicator). Configuration (notably ACCESS_TOKEN) is handed over
 * in-process via [ContainerHolder] and never persisted natively — the token
 * lives in FlutterSecureStorage on the Dart side.
 */
class LocalContainerService : Service() {

    companion object {
        const val ACTION_START = "com.example.workfromphone.container.START"
        const val ACTION_STOP = "com.example.workfromphone.container.STOP"
        const val CHANNEL_ID = "wfp_local_container"
        const val NOTIFICATION_ID = 4201
        const val DEFAULT_PORT = 8000

        private val configRef = AtomicReference<ProotRunner.GuestConfig?>()

        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        var activePort: Int = DEFAULT_PORT
            private set

        fun configure(config: ProotRunner.GuestConfig) {
            configRef.set(config)
        }

        fun start(context: Context, config: ProotRunner.GuestConfig) {
            configure(config)
            val intent = Intent(context, LocalContainerService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, LocalContainerService::class.java).setAction(ACTION_STOP),
            )
        }
    }

    private val binder = LocalBinder()
    private val executor = Executors.newSingleThreadExecutor()
    // Guards against a fast double Start dispatching two spawns (the second
    // dies on port bind and overwrites [guest], so shutdown would only kill
    // the last one).
    private val starting = AtomicBoolean(false)
    private var guest: Process? = null
    private var wakeLock: PowerManager.WakeLock? = null

    inner class LocalBinder : Binder() {
        fun service(): LocalContainerService = this@LocalContainerService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutdown()
                return START_NOT_STICKY
            }
            else -> {
                val config = configRef.get()
                if (config == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForeground(NOTIFICATION_ID, buildNotification(config.port))
                acquireWakeLock()
                bootGuest(config)
                return START_STICKY
            }
        }
    }

    private fun bootGuest(config: ProotRunner.GuestConfig) {
        if (running) return
        activePort = config.port
        val manager = RootfsManager(this)
        executor.execute {
            // The outer [running] check above happens before spawn; this one
            // closes the race where two Start commands both pass it and both
            // dispatch spawn lambdas.
            if (running || !starting.compareAndSet(false, true)) return@execute
            try {
                manager.logFile().writeText(
                    "[container] start ${java.util.Date()}\n" +
                        "[container] proot=${config.prootBinary}\n",
                )
                // First start ever: run the guest bootstrap one-shot so apt
                // packages, the coder user, and resolv.conf exist before the
                // backend binds its port.
                val bootstrapped = File(config.rootfsDir, "opt/workfromphone/.bootstrapped")
                if (!bootstrapped.isFile) {
                    File(manager.containerDir, "bootstrap.log").writeText(
                        "[container] bootstrap ${java.util.Date()}\n",
                    )
                    val bootstrap = ProotRunner.spawn(
                        config,
                        ProotRunner.bootstrapCommand(),
                        File(manager.containerDir, "bootstrap.log"),
                    )
                    bootstrap.waitFor()
                    manager.applyPatches()
                }
                guest = ProotRunner.spawn(
                    config,
                    ProotRunner.launchCommand(),
                    manager.logFile(),
                )
                running = true
                updateNotification(config.port)
                val healthy = ProotRunner.waitForHealth(config.port)
                if (!healthy && guest?.isAlive == true) {
                    // Keep running: the wizard surfaces log tail; the guest
                    // may just be slow on first boot (apt + venv fallback).
                }
            } catch (e: Exception) {
                runCatching {
                    File(manager.containerDir, "backend.log")
                        .appendText("\n[container] start failed: ${e.message}\n")
                }
                shutdown()
            } finally {
                // [running] was set (success) or shutdown() ran (failure).
                starting.set(false)
            }
        }
    }

    fun isBackendHealthy(): Boolean = running && ProotRunner.isHealthy(activePort)

    private fun shutdown() {
        running = false
        val work = {
            ProotRunner.stop(guest)
            guest = null
            releaseWakeLock()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        // If the executor was already torn down by onDestroy (destroyed
        // service + in-flight boot lambda failing concurrently), a queued
        // task would be rejected and the guest process would be orphaned.
        if (executor.isShutdown) work() else executor.execute(work)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "WorkFromPhone:LocalContainer",
        ).apply {
            acquire(12 * 60 * 60 * 1000L /* 12h */)
        }
    }

    private fun releaseWakeLock() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "On-device Linux container",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the on-device backend running"
            },
        )
    }

    private fun buildNotification(port: Int): Notification {
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, LocalContainerService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val openIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WorkFromPhone backend on-device")
            .setContentText("Debian container listening on 127.0.0.1:$port")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent)
            .build()
    }

    private fun updateNotification(port: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        runCatching { manager.notify(NOTIFICATION_ID, buildNotification(port)) }
    }

    override fun onDestroy() {
        // ProotRunner.stop() sleeps up to ~1.5 s for a graceful teardown;
        // never block the main thread while the system kills the service.
        val process = guest
        val stopThread = Thread({
            ProotRunner.stop(process)
            guest = null
        }, "wfp-container-stop")
        stopThread.isDaemon = true
        stopThread.start()
        running = false
        releaseWakeLock()
        executor.shutdownNow()
        super.onDestroy()
    }
}
