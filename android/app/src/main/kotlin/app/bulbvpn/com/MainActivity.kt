package app.bulbvpn.com

import android.app.ActivityManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    // Native teardown and TUN establish block the caller. Keeping them off the
    // UI thread is what stops Android from dispatching an ANR under load.
    private val workExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "bulb-platform-work").apply { isDaemon = true }
    }
    private var pendingToken = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> connect(
                    call.argument<String>("host"),
                    call.argument<String>("sni"),
                    call.argument<Int>("port") ?: 443,
                    call.argument<String>("mode"),
                    call.argument<List<String>>("apps"),
                    result,
                )
                "disconnect" -> {
                    pendingToken++
                    val previous = pending
                    pending = null
                    previous?.success(mapOf("ok" to false, "detail" to "cancelled"))
                    val reason = call.argument<String>("reason") ?: "user"
                    // Reply only after the tunnel is really down, so a
                    // disconnect followed by a connect cannot race the old
                    // session, but never wait for it on the main thread.
                    workExecutor.execute {
                        try {
                            SoftEtherVpnService.requestStop(reason)
                        } catch (_: Throwable) {
                        }
                        mainHandler.post { result.success(null) }
                    }
                }
                "engageLockdown" -> {
                    workExecutor.execute {
                        val armed = try {
                            SoftEtherVpnService.armLockdown(this)
                        } catch (_: Throwable) {
                            false
                        }
                        mainHandler.post { result.success(armed) }
                    }
                }
                "bytesDown" -> {
                    result.success(SoftEtherVpnService.instance?.bytesReceived() ?: 0L)
                }
                "status" -> {
                    val service = SoftEtherVpnService.instance
                    result.success(
                        mapOf(
                            "running" to (service?.isTunnelUp() == true),
                            "host" to (service?.activeHost ?: ""),
                            "reason" to (service?.statusReason()?.ifEmpty {
                                SoftEtherVpnService.lastReason
                            } ?: SoftEtherVpnService.lastReason),
                            "carrierUp" to (service?.isCarrierUp() ?: false),
                            "effectiveIp" to (service?.effectiveServerIp() ?: ""),
                            "routeMode" to (service?.routeModeName() ?: "all"),
                            "routeAppCount" to (service?.routeAppCount() ?: 0),
                            "lockedDown" to (service?.isLockedDown() ?: false),
                        ),
                    )
                }
                "setKillSwitch" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    // Releasing the switch closes the blocking TUN; do not let
                    // that happen on the input thread.
                    workExecutor.execute {
                        SoftEtherVpnService.setKillSwitch(this, enabled)
                        mainHandler.post { result.success(null) }
                    }
                }
                "installedApps" -> installedApps(result)
                "systemState" -> {
                    // Two binder round-trips; keep them off the input thread so
                    // a resume that asks "does the OS still hold my tunnel"
                    // cannot stall the frame.
                    workExecutor.execute {
                        val state = mapOf(
                            "vpnNetworkUp" to vpnNetworkActive(),
                            "realityDaemonUp" to realityDaemonAlive(),
                        )
                        mainHandler.post { result.success(state) }
                    }
                }
                "diagnostics" -> {
                    result.success(
                        SoftEtherVpnService.instance?.diagnostics() ?: mapOf(
                            "running" to false,
                            "nativeLog" to emptyList<String>(),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun connect(
        host: String?,
        sni: String?,
        port: Int,
        mode: String?,
        apps: List<String>?,
        result: MethodChannel.Result,
    ) {
        if (host.isNullOrEmpty()) {
            result.success(mapOf("ok" to false, "detail" to "missing host"))
            return
        }
        if (VpnService.prepare(this) != null) {
            result.success(mapOf("ok" to false, "detail" to "vpn permission"))
            return
        }
        if (pending != null) {
            result.success(mapOf("ok" to false, "detail" to "busy"))
            return
        }
        pending = result
        val token = ++pendingToken
        mainHandler.postDelayed({
            if (token == pendingToken && pending === result) {
                pending = null
                // Never leave a dial running after the caller has given up:
                // a late handshake would install a tunnel that Dart already
                // counts as failed.
                SoftEtherVpnService.requestStop("timeout")
                result.success(mapOf("ok" to false, "detail" to "timeout"))
            }
        }, 45_000)
        SoftEtherVpnService.onDone = { ok, detail ->
            runOnUiThread {
                if (pending === result) {
                    pending = null
                    result.success(mapOf("ok" to ok, "detail" to detail))
                }
            }
        }
        val routeMode = if (mode == "bypass" || mode == "allow") mode else "all"
        val routeApps = apps
            ?.filter { it.isNotBlank() }
            ?.distinct()
            ?: emptyList()
        val intent = Intent(this, SoftEtherVpnService::class.java)
            .putExtra(SoftEtherVpnService.EXTRA_HOST, host)
            .putExtra(SoftEtherVpnService.EXTRA_SNI, sni ?: host)
            .putExtra(SoftEtherVpnService.EXTRA_PORT, port)
            .putExtra(SoftEtherVpnService.EXTRA_ROUTE_MODE, routeMode)
            .putStringArrayListExtra(
                SoftEtherVpnService.EXTRA_ROUTE_APPS,
                ArrayList(routeApps),
            )
        try {
            startForegroundService(intent)
        } catch (error: Throwable) {
            if (pending === result) {
                pending = null
                result.success(
                    mapOf(
                        "ok" to false,
                        "detail" to (error.message ?: "service start failed"),
                    ),
                )
            }
        }
    }

    /**
     * True while any VPN network is up on this device. Android allows only one
     * tunnel at a time, so combined with [realityDaemonAlive] it identifies a
     * tunnel this app started but this process no longer remembers.
     */
    private fun vpnNetworkActive(): Boolean = try {
        val cm = getSystemService(ConnectivityManager::class.java)
        // A VPN network is only listed while its tunnel holds one, so the
        // transport alone answers "is something still capturing traffic".
        cm?.allNetworks?.any { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        } == true
    } catch (error: Throwable) {
        Log.w(TAG, "vpnNetworkActive failed", error)
        false
    }

    /**
     * True while the plugin's Xray service process is alive. It runs under
     * `android:process=":RunSoLibXrayDaemon"`, so it outlives the UI process
     * that started it; getRunningAppProcesses() is scoped to our own UID,
     * which is exactly the attribution the UI needs before claiming Connected.
     */
    private fun realityDaemonAlive(): Boolean = try {
        val marker = "$packageName:RunSoLibXrayDaemon"
        getSystemService(ActivityManager::class.java)
            ?.runningAppProcesses
            ?.any { it.processName == marker } == true
    } catch (error: Throwable) {
        Log.w(TAG, "realityDaemonAlive failed", error)
        false
    }

    /**
     * Launchable apps for the routing picker. Uses a `<queries>` intent filter
     * instead of QUERY_ALL_PACKAGES, so Play's package-visibility policy is
     * not triggered; apps without a launcher entry are intentionally absent.
     */
    private fun installedApps(result: MethodChannel.Result) {
        Thread {
            val apps = try {
                queryLaunchableApps()
            } catch (error: Throwable) {
                Log.w(TAG, "installedApps failed", error)
                emptyList<Map<String, String>>()
            }
            runOnUiThread { result.success(apps) }
        }.apply {
            name = "installed-apps"
            isDaemon = true
        }.start()
    }

    private fun queryLaunchableApps(): List<Map<String, String>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val seen = HashSet<String>()
        return resolved.asSequence()
            .mapNotNull { it.activityInfo?.applicationInfo }
            .filter { it.packageName != packageName && seen.add(it.packageName) }
            .map { info ->
                mapOf(
                    "package" to info.packageName,
                    "label" to runCatching {
                        pm.getApplicationLabel(info).toString()
                    }.getOrDefault(info.packageName),
                )
            }
            .sortedBy { (it["label"] ?: "").lowercase(Locale.ROOT) }
            .toList()
    }

    companion object {
        private const val CHANNEL = "app.bulbvpn.com/softether"
        private const val TAG = "BulbMain"
    }
}
