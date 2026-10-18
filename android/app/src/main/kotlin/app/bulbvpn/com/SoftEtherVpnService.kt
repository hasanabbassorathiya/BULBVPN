package app.bulbvpn.com

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

/**
 * SoftEther SSL-VPN (HTTPS on TCP 443) into a VPN Gate hub.
 * OpenVPN's own packets stall on this network; TLS to the same servers does not.
 */
class SoftEtherVpnService : VpnService() {
    private val running = AtomicBoolean(false)
    private var client: Long = 0
    private var tunFd: Int = -1
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile var activeHost: String = ""
    @Volatile private var tunnelUp: Boolean = false
    @Volatile private var carrier: Network? = null
    @Volatile private var connectInFlight = false
    @Volatile private var protectedSockets = 0

    override fun onCreate() {
        super.onCreate()
        instance = this
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL,
                "BULBVPN",
                NotificationManager.IMPORTANCE_LOW,
            )
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = Notification.Builder(this, CHANNEL)
            .setContentTitle("BULBVPN")
            .setContentText("Opening SSL tunnel")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        var host = intent?.getStringExtra(EXTRA_HOST) ?: ""
        var sni = intent?.getStringExtra(EXTRA_SNI) ?: host
        if (host.isEmpty()) {
            val saved = savedRelay()
            host = saved.first
            sni = saved.second.ifEmpty { host }
        }
        if (host.isEmpty()) {
            if (tunnelUp) return START_STICKY
            finish(false, "missing host")
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running.compareAndSet(false, true)) {
            finish(tunnelUp, if (tunnelUp) "already running" else "busy")
            return START_STICKY
        }
        activeHost = host
        rememberRelay(host, sni)
        watchDefaultNetwork()
        Thread {
            try {
                connectBlocking(host, sni)
            } catch (error: Throwable) {
                Log.e(TAG, "connect failed", error)
                if (!tunnelUp) forgetRelay()
                finish(false, error.message ?: "exception")
                shutdown()
            }
        }.apply { name = "softether" }.start()
        return START_STICKY
    }

    private fun watchDefaultNetwork() {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        networkCallback?.let {
            try {
                manager.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val caps = manager.getNetworkCapabilities(network) ?: return
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return
                carrier = network
                pinCarrier()
            }
        }
        networkCallback = callback
        try {
            manager.registerDefaultNetworkCallback(callback)
        } catch (error: Exception) {
            Log.w(TAG, "network callback failed", error)
        }
    }

    private fun savedRelay(): Pair<String, String> {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return (prefs.getString(PREF_HOST, "") ?: "") to (prefs.getString(PREF_SNI, "") ?: "")
    }

    private fun rememberRelay(host: String, sni: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_HOST, host)
            .putString(PREF_SNI, sni)
            .apply()
    }

    private fun forgetRelay() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tunIp = prefs.getString(PREF_TUN_IP, "")
        val tunHost = prefs.getString(PREF_TUN_HOST, "")
        prefs.edit().clear().apply()
        if (!tunIp.isNullOrEmpty()) {
            prefs.edit()
                .putString(PREF_TUN_IP, tunIp)
                .putString(PREF_TUN_HOST, tunHost)
                .apply()
        }
    }

    private fun pinCarrier() {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        val current = carrier ?: manager.allNetworks.firstOrNull { net ->
            val caps = manager.getNetworkCapabilities(net) ?: return@firstOrNull false
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } ?: return
        carrier = current
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            setUnderlyingNetworks(arrayOf(current))
            Log.i(TAG, "pinned underlying $current")
        }
    }

    private fun connectBlocking(host: String, sni: String) {
        pinCarrier()
        val address = if (host.matches(Regex("""^\d+\.\d+\.\d+\.\d+$"""))) {
            host
        } else {
            InetAddress.getAllByName(host)
                .firstOrNull { it is Inet4Address }
                ?.hostAddress
                ?: host
        }
        Log.i(TAG, "dial $host -> $address sni=$sni")
        System.loadLibrary("softether_jni")
        nativeSetProtect()
        val relayPrefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val remembered = relayPrefs.getString(PREF_TUN_IP, "").orEmpty()
        val rememberedHost = relayPrefs.getString(PREF_TUN_HOST, "").orEmpty()
        if (remembered.isNotEmpty() && rememberedHost == address) {
            Log.i(TAG, "fast path $remembered")
            var handle = connectOnRoutedTun(address, sni, remembered, 16)
            if (handle != 0L) {
                val got = nativeAssignedIp(handle)
                if (got != 0 && formatIp(got) != remembered) {
                    val movedIp = formatIp(got)
                    val movedPrefix = Integer.bitCount(nativeAssignedMask(handle)).coerceIn(8, 32)
                    Log.i(TAG, "address moved to $movedIp/$movedPrefix")
                    retireClient()
                    handle = connectOnRoutedTun(address, sni, movedIp, movedPrefix)
                }
                if (handle != 0L) {
                    val shown = nativeAssignedIp(handle)
                    holdSession(if (shown != 0) formatIp(shown) else remembered)
                    return
                }
            }
            if (connectInFlight) {
                finish(false, "connect code -100")
                releaseAfterHandshake()
                return
            }
            retireClient()
            Log.i(TAG, "fast path missed, probing")
        }
        val created = nativeCreate(address, 443, "VPNGATE", "vpn", "vpn")
        if (created == 0L) {
            finish(false, "create failed")
            running.set(false)
            stopSelf()
            return
        }
        client = created
        nativeConfigure(created, sni, false)
        tunFd = openTun("10.211.254.2", 24, defaultRoute = false)
        nativeSetTun(created, tunFd)
        Log.i(TAG, "connecting $address sni=$sni")
        val started = android.os.SystemClock.elapsedRealtime()
        var code = connectWithDeadline(created, 28_000)
        val fastReject = android.os.SystemClock.elapsedRealtime() - started < 15_000
        if (code != 0 && code != -100 && running.get() && fastReject) {
            Log.w(TAG, "hashed auth failed code=$code, retrying plain password")
            nativeStop(created)
            nativeDestroy(created)
            closeTun()
            val retry = nativeCreate(address, 443, "VPNGATE", "vpn", "vpn")
            client = retry
            if (retry == 0L) {
                finish(false, "create failed")
                running.set(false)
                stopSelf()
                return
            }
            nativeConfigure(retry, sni, true)
            tunFd = openTun("10.211.254.2", 24, defaultRoute = false)
            nativeSetTun(retry, tunFd)
            code = connectWithDeadline(retry, 28_000)
        }
        if (code != 0 || !running.get()) {
            finish(false, "connect code $code")
            shutdown()
            return
        }
        var ip = 0
        var mask = 0
        val deadline = android.os.SystemClock.elapsedRealtime() + 20_000
        while (android.os.SystemClock.elapsedRealtime() < deadline && running.get()) {
            ip = nativeAssignedIp(client)
            mask = nativeAssignedMask(client)
            if (ip != 0) break
            Thread.sleep(200)
        }
        if (ip == 0) {
            finish(false, "no dhcp address")
            shutdown()
            return
        }
        val tunnelIp = formatIp(ip)
        val prefix = Integer.bitCount(mask).coerceIn(8, 32)
        Log.i(TAG, "assigned $tunnelIp/$prefix")
        // The data loop keeps the fd from before connect. Swapping it after
        // the fact leaves the routed interface unread, so traffic never leaves
        // the phone. Start a new session on the routed fd instead.
        retireClient()
        var handle = connectOnRoutedTun(address, sni, tunnelIp, prefix)
        if (handle == 0L) {
            finish(false, "routed connect failed")
            shutdown()
            return
        }
        val moved = nativeAssignedIp(handle)
        val movedMask = nativeAssignedMask(handle)
        if (moved != 0 && moved != ip) {
            val movedIp = formatIp(moved)
            val movedPrefix = Integer.bitCount(movedMask).coerceIn(8, 32)
            Log.i(TAG, "address moved to $movedIp/$movedPrefix")
            retireClient()
            handle = connectOnRoutedTun(address, sni, movedIp, movedPrefix)
            if (handle == 0L) {
                finish(false, "routed connect failed")
                shutdown()
                return
            }
        }
        val shown = nativeAssignedIp(handle)
        holdSession(if (shown != 0) formatIp(shown) else tunnelIp)
    }

    private fun holdSession(tunnelIp: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_TUN_IP, tunnelIp)
            .putString(PREF_TUN_HOST, activeHost)
            .apply()
        tunnelUp = true
        finish(true, tunnelIp)
        var misses = 0
        while (running.get()) {
            Thread.sleep(1000)
            val assigned = try {
                nativeAssignedIp(client)
            } catch (_: Throwable) {
                0
            }
            if (assigned == 0) {
                misses += 1
                if (misses >= 3) {
                    Log.w(TAG, "tunnel lost its address")
                    tunnelUp = false
                    break
                }
            } else {
                misses = 0
            }
        }
        if (running.get()) {
            shutdown()
        }
    }

    private fun retireClient() {
        val handle = client
        client = 0
        if (handle != 0L) {
            try {
                nativeStop(handle)
            } catch (_: Throwable) {
            }
            try {
                nativeDestroy(handle)
            } catch (_: Throwable) {
            }
        }
        closeTun()
    }

    private fun connectOnRoutedTun(
        address: String,
        sni: String,
        tunnelIp: String,
        prefix: Int,
    ): Long {
        pinCarrier()
        val routed = openTun(tunnelIp, prefix, defaultRoute = true)
        val handle = nativeCreate(address, 443, "VPNGATE", "vpn", "vpn")
        if (handle == 0L) {
            ParcelFileDescriptor.adoptFd(routed).close()
            return 0
        }
        client = handle
        nativeConfigure(handle, sni, false)
        tunFd = routed
        nativeSetTun(handle, routed)
        Log.i(TAG, "routed session $tunnelIp/$prefix")
        val code = connectWithDeadline(handle, 28_000)
        if (code != 0 || !running.get()) {
            Log.w(TAG, "routed session failed code=$code")
            return 0
        }
        return handle
    }

    private fun openTun(address: String, prefix: Int, defaultRoute: Boolean): Int {
        val builder = Builder()
            .setSession("BULBVPN")
            .addAddress(address, prefix)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setMtu(1200)
            .allowFamily(android.system.OsConstants.AF_INET)
        if (defaultRoute) {
            builder.addRoute("0.0.0.0", 0)
            // The process that owns the tunnel cannot send its own TLS through
            // that tunnel. Leaving this app on the carrier keeps the session
            // socket alive once the default route is installed.
            try {
                builder.addDisallowedApplication(packageName)
            } catch (error: Exception) {
                Log.w(TAG, "could not exclude tunnel process", error)
            }
        }
        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.establish returned null")
        return pfd.detachFd()
    }

    fun protectFd(fd: Int): Int {
        val ok = protect(fd)
        if (ok) protectedSockets += 1
        Log.i(TAG, "protect fd=$fd ok=$ok")
        return if (ok) fd else -1
    }

    private fun closeTun() {
        if (tunFd >= 0) {
            try {
                ParcelFileDescriptor.adoptFd(tunFd).close()
            } catch (_: Exception) {
            }
            tunFd = -1
        }
    }

    fun isTunnelUp(): Boolean = tunnelUp && client != 0L

    fun shutdown() {
        running.set(false)
        tunnelUp = false
        activeHost = ""
        val manager = getSystemService(ConnectivityManager::class.java)
        networkCallback?.let {
            try {
                manager?.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        networkCallback = null
        val handle = client
        if (handle != 0L && !connectInFlight) {
            try {
                nativeStop(handle)
            } catch (_: Throwable) {
            }
            try {
                nativeDestroy(handle)
            } catch (_: Throwable) {
            }
            client = 0
        } else if (handle != 0L) {
            try {
                nativeRequestStop(handle)
            } catch (_: Throwable) {
            }
        }
        closeTun()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        running.set(false)
        instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        forgetRelay()
        finish(false, "revoked")
        shutdown()
        super.onRevoke()
    }

    private external fun nativeSetProtect()
    private external fun nativeCreate(
        host: String,
        port: Int,
        hub: String,
        user: String,
        pass: String,
    ): Long
    private external fun nativeConfigure(client: Long, sni: String, plain: Boolean)
    private external fun nativeSetTun(client: Long, fd: Int)
    private external fun nativeConnect(client: Long): Int
    private external fun nativeRequestStop(client: Long)

    /// Caps a handshake that mobile networks black-hole. `request_stop` asks
    /// the library to return; tearing the client down from another thread
    /// crashes the process.
    private fun connectWithDeadline(handle: Long, budgetMs: Long): Int {
        val result = intArrayOf(-100)
        connectInFlight = true
        val worker = Thread {
            try {
                result[0] = nativeConnect(handle)
            } finally {
                connectInFlight = false
            }
        }.apply {
            name = "softether-connect"
            start()
        }
        protectedSockets = 0
        val started = android.os.SystemClock.elapsedRealtime()
        val cap = started + minOf(budgetMs, 8_000)
        var deadline = started + 8_000
        while (worker.isAlive && android.os.SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(200)
            val now = android.os.SystemClock.elapsedRealtime()
            val assigned = try {
                nativeAssignedIp(handle)
            } catch (_: Throwable) {
                0
            }
            if (assigned != 0) {
                deadline = minOf(cap, now + 3_000)
            }
        }
        if (!worker.isAlive) return result[0]
        Log.w(TAG, "connect exceeded ${android.os.SystemClock.elapsedRealtime() - started}ms, requesting stop")
        try {
            nativeRequestStop(handle)
        } catch (_: Throwable) {
        }
        worker.join(1_500)
        return if (worker.isAlive) -100 else result[0]
    }

    /// The handshake thread can outlive the deadline. Drop the service gate
    /// only after it returns, so the next relay is not rejected as busy and
    /// a second client is not created while nativeConnect is still on the stack.
    private fun releaseAfterHandshake() {
        Thread {
            val deadline = android.os.SystemClock.elapsedRealtime() + 12_000
            while (connectInFlight && android.os.SystemClock.elapsedRealtime() < deadline) {
                try {
                    Thread.sleep(200)
                } catch (_: InterruptedException) {
                }
            }
            if (!tunnelUp) {
                running.set(false)
                try {
                    stopSelf()
                } catch (_: Throwable) {
                }
            }
        }.apply {
            name = "softether-release"
            start()
        }
    }
    private external fun nativeAssignedIp(client: Long): Int
    private external fun nativeAssignedMask(client: Long): Int
    private external fun nativeReplaceTun(client: Long, fd: Int): Int
    private external fun nativeStop(client: Long)
    private external fun nativeDestroy(client: Long)
    private external fun nativeBytesDown(client: Long): Long

    fun bytesReceived(): Long {
        // get_stats is not safe while softether_connect is on another thread.
        if (connectInFlight || !tunnelUp) return 0
        val handle = client
        if (handle == 0L) return 0
        return try {
            nativeBytesDown(handle)
        } catch (_: Throwable) {
            0
        }
    }

    companion object {
        private const val TAG = "BulbSoftEther"
        private const val CHANNEL = "bulbvpn_ssl"
        private const val NOTIFICATION_ID = 41
        private const val PREFS = "bulb_vpn_relay"
        private const val PREF_HOST = "host"
        private const val PREF_SNI = "sni"
        private const val PREF_TUN_IP = "tun_ip"
        private const val PREF_TUN_HOST = "tun_host"
        const val EXTRA_HOST = "host"
        const val EXTRA_SNI = "sni"

        @Volatile
        var instance: SoftEtherVpnService? = null

        var onDone: ((Boolean, String) -> Unit)? = null

        fun finish(ok: Boolean, detail: String) {
            Log.i(TAG, "result ok=$ok detail=$detail")
            val callback = onDone
            onDone = null
            callback?.invoke(ok, detail)
        }

        fun requestStop() {
            instance?.forgetRelay()
            instance?.shutdown()
        }

        private fun formatIp(hostOrder: Int): String {
            val value = hostOrder.toLong() and 0xffffffffL
            return "${value shr 24 and 255}.${value shr 16 and 255}.${value shr 8 and 255}.${value and 255}"
        }
    }
}
