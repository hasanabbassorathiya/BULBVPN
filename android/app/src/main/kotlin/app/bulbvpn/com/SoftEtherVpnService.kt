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
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * SoftEther SSL-VPN (HTTPS on TCP 443) into a VPN Gate hub.
 * OpenVPN's own packets stall on this network; TLS to the same servers does not.
 */
class SoftEtherVpnService : VpnService() {
    private val running = AtomicBoolean(false)
    // Guards the native handle and the tun fd. The session thread, the
    // connectivity callback and a user disconnect all touch them; destroying a
    // client while the liveness probe is inside it aborts the whole process.
    private val sessionLock = Any()
    @Volatile private var client: Long = 0
    @Volatile private var tunFd: Int = -1
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile var activeHost: String = ""
    @Volatile private var tunnelUp: Boolean = false
    @Volatile private var carrier: Network? = null
    @Volatile private var carrierUp: Boolean = false
    @Volatile private var connectInFlight = false
    @Volatile private var protectedSockets = 0
    @Volatile private var stopReason: String = ""
    @Volatile private var effectiveIp: String = ""
    @Volatile private var connectedAt: Long = 0
    @Volatile private var networkGeneration: Int = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    // Small in-memory ring buffer exposed to the Dart diagnostics sheet. It
    // answers "why did this carrier fail?" without needing adb/logcat.
    private val diag = ArrayDeque<String>()
    private val diagStamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private fun note(message: String) {
        Log.i(TAG, message)
        synchronized(diag) {
            if (diag.size >= 240) diag.removeFirst()
            diag.add("${diagStamp.format(Date())} $message")
        }
    }

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

    private fun updateNotification(text: String) {
        try {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val notification = builder
                .setContentTitle("BULBVPN")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
            getSystemService(NotificationManager::class.java)
                ?.notify(NOTIFICATION_ID, notification)
        } catch (error: Throwable) {
            Log.w(TAG, "notification update failed", error)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = notificationBuilder
            .setContentTitle("BULBVPN")
            .setContentText("Connecting…")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
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
        // A previous handshake that timed out can leave the gate closed while
        // no tunnel exists. Clear that stale gate instead of rejecting the
        // next relay as "busy" forever.
        if (connectInFlight) {
            finish(false, "busy")
            return START_STICKY
        }
        if (running.get()) {
            // A live tunnel for the requested relay can be adopted. Anything
            // else means the caller wants a different exit; refusing is honest
            // and lets Dart tear the old tunnel down instead of reporting
            // success for a session it did not ask for.
            if (tunnelUp && host == activeHost) {
                finish(true, "already running")
            } else {
                finish(false, "relay_changed")
            }
            return START_STICKY
        }
        running.set(true)
        stopReason = ""
        effectiveIp = ""
        connectedAt = 0
        lastReason = ""
        activeHost = host
        note("service start host=$host sni=$sni")
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
        val generation = ++networkGeneration
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val caps = manager.getNetworkCapabilities(network) ?: return
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return
                val previous = carrier
                carrier = network
                carrierUp = true
                pinCarrier()
                // A live TCP session is bound to the old carrier. Keeping it
                // after Wi-Fi ↔ mobile-data switches is what leaves the orb on
                // "Connected" while nothing can leave the phone.
                if (tunnelUp && previous != null && previous != network) {
                    note("carrier moved $previous -> $network")
                    val oldTunnel = tunnelUp
                    tunnelUp = false
                    Thread {
                        if (oldTunnel) {
                            finish(false, "network_changed")
                            shutdown("network_changed")
                        }
                    }.apply { name = "softether-carrier-move" }.start()
                }
            }

            override fun onLost(network: Network) {
                if (network != carrier) return
                carrierUp = false
                note("underlying network lost $network")
                mainHandler.postDelayed({
                    if (generation == networkGeneration && carrier == network && !carrierUp) {
                        if (tunnelUp) {
                            tunnelUp = false
                            finish(false, "network_lost")
                            shutdown("network_lost")
                        }
                    }
                }, 1_500)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                caps: NetworkCapabilities,
            ) {
                if (network != carrier) return
                val online = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                if (!online && carrierUp) {
                    carrierUp = false
                    note("carrier lost INTERNET capability")
                } else if (online && !carrierUp) {
                    carrierUp = true
                    pinCarrier()
                }
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
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun pinCarrier() {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        val current = carrier ?: manager.allNetworks.firstOrNull { net ->
            val caps = manager.getNetworkCapabilities(net) ?: return@firstOrNull false
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } ?: return
        carrier = current
        carrierUp = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            setUnderlyingNetworks(arrayOf(current))
            note("pinned underlying $current")
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
        note("dial $host -> $address sni=$sni")
        System.loadLibrary("softether_jni")
        nativeSetProtect()
        // Always connect through the placeholder → DHCP → routed TUN swap
        // sequence. The remembered-IP shortcut (10.239.x reused before DHCP)
        // authenticated, logged "session up", and then read nothing from the
        // TUN (libsoftether DIAG nread=0, zero throughput) while the UI showed
        // Connected. The cold path takes ~12 s and actually passes traffic.
        val created = nativeCreate(address, 443, "VPNGATE", "vpn", "vpn")
        if (created == 0L) {
            finish(false, "create failed")
            running.set(false)
            stopSelf()
            return
        }
        // softether_connect() initializes the packet adapter from the fd that
        // is configured at that moment. With no fd it authenticates, then
        // fails with SOFTETHER_ERR_ADAPTER (-9) and the old retry path built a
        // second client whose teardown races the library and SIGSEGVs. Give it
        // a real placeholder interface now; replace it with the server-assigned
        // routed interface once DHCP is known.
        val initial = try {
            openTun("10.211.254.2", 24, defaultRoute = false)
        } catch (error: Throwable) {
            note("initial tun failed: ${error.message}")
            nativeDestroy(created)
            finish(false, "tun setup failed")
            running.set(false)
            stopSelf()
            return
        }
        synchronized(sessionLock) {
            if (!running.get()) {
                nativeDestroy(created)
                closeFdNow(initial)
                return
            }
            client = created
            nativeConfigure(created, sni, false)
            tunFd = initial
            nativeSetTun(created, initial)
        }
        note("connecting $address sni=$sni")
        val started = android.os.SystemClock.elapsedRealtime()
        var code = connectWithDeadline(created, 28_000)
        val fastReject = android.os.SystemClock.elapsedRealtime() - started < 15_000
        if (code == -5 && running.get() && fastReject) {
            // Only a real auth rejection earns a second handshake. -9 is an
            // adapter error, not auth. Reconnect the *same* client: destroying
            // it and creating another one races the native teardown.
            note("hashed auth rejected, retrying plain password on same client")
            synchronized(sessionLock) {
                if (client == created) {
                    nativeStop(created)
                    nativeConfigure(created, sni, true)
                    if (tunFd >= 0) nativeSetTun(created, tunFd)
                }
            }
            code = connectWithDeadline(created, 28_000)
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
            val sample = sampledAddress(client) ?: break
            ip = sample.first
            mask = sample.second
            if (ip != 0) break
            Thread.sleep(200)
        }
        if (ip == 0) {
            if (running.get()) {
                finish(false, "no dhcp address")
                shutdown()
            }
            return
        }
        val tunnelIp = formatIp(ip)
        val prefix = Integer.bitCount(mask).coerceIn(8, 32)
        note("assigned $tunnelIp/$prefix")
        // The adapter is built during connect() from the fd bound before the
        // handshake, but that fd predates DHCP and is never readable. Now that
        // the assigned address is known, recreate the VpnService interface with
        // the routed config and swap the native client onto it. This is the
        // documented purpose of softether_replace_tun_fd().
        val gateway = synchronized(sessionLock) {
            if (client == created) {
                try {
                    nativeGatewayIp(created)
                } catch (_: Throwable) {
                    0
                }
            } else {
                0
            }
        }
        val routed = openTun(tunnelIp, prefix, defaultRoute = true, dns = gateway)
        var previous = -1
        var swapped = -1
        synchronized(sessionLock) {
            if (client == created && running.get()) {
                previous = tunFd
                swapped = nativeReplaceTun(created, routed)
                if (swapped == 0) tunFd = routed
            }
        }
        if (swapped != 0) {
            note("routed tun swap failed code=$swapped")
            closeFdNow(routed)
            finish(false, "tun swap failed")
            shutdown()
            return
        }
        if (previous >= 0 && previous != routed) closeFdLater(previous)
        note("routed tun fd=$routed replaced=$previous")
        holdSession(tunnelIp)
    }

    private fun holdSession(tunnelIp: String) {
        if (!running.get()) return
        tunnelUp = true
        connectedAt = android.os.SystemClock.elapsedRealtime()
        stopReason = ""
        effectiveIp = synchronized(sessionLock) {
            val handle = client
            if (handle == 0L) {
                ""
            } else {
                try {
                    val effective = nativeEffectiveServerIp(handle)
                    if (effective != 0) formatEffectiveIp(effective) else ""
                } catch (_: Throwable) {
                    ""
                }
            }
        }
        if (effectiveIp.isNotEmpty() && effectiveIp != activeHost) {
            note("effective relay $effectiveIp (dialed $activeHost)")
        }
        note("session up tun=$tunnelIp effective=${effectiveIp.ifEmpty { "?" }}")
        if (!running.get()) {
            tunnelUp = false
            return
        }
        finish(true, tunnelIp)
        updateNotification("Connected · encrypted tunnel")
        var misses = 0
        while (running.get()) {
            Thread.sleep(1_000)
            if (!running.get()) break
            val probe = synchronized(sessionLock) {
                val handle = client
                if (handle == 0L) {
                    null
                } else {
                    val assigned = try {
                        nativeAssignedIp(handle)
                    } catch (_: Throwable) {
                        0
                    }
                    val linked = try {
                        nativeIsConnected(handle)
                    } catch (_: Throwable) {
                        false
                    }
                    assigned to linked
                }
            } ?: break
            val assigned = probe.first
            val linked = probe.second
            val online = carrierUp
            if (assigned == 0 || !linked || !online) {
                misses += 1
                // SoftEther performs its own short reconnects (the native layer
                // is configured with a 3s retry). Tearing the TUN down on the
                // first few misses turned a two-second library hiccup into a
                // full app-level disconnect. Eight seconds still surfaces a
                // genuinely dead link well before the read timeout.
                if (misses >= 8) {
                    stopReason = when {
                        !online -> "network_lost"
                        assigned == 0 -> "address_lost"
                        else -> "link_lost"
                    }
                    note(
                        "tunnel lost (reason=$stopReason assigned=$assigned linked=$linked online=$online)",
                    )
                    tunnelUp = false
                    break
                }
            } else {
                misses = 0
            }
        }
        if (running.get()) {
            shutdown(stopReason.ifEmpty { "link_lost" })
        }
    }

    private fun retireClient() {
        synchronized(sessionLock) {
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
            closeTunLocked()
        }
    }

    private fun openTun(
        address: String,
        prefix: Int,
        defaultRoute: Boolean,
        dns: Int = 0,
    ): Int {
        val builder = Builder()
            .setSession("BULBVPN")
            .addAddress(address, prefix)
        // The DHCP gateway is the resolver the hub expects; public DNS is a
        // fallback for hubs that do not answer on the gateway address.
        val gatewayDns = if (dns != 0) formatIp(dns) else ""
        if (gatewayDns.isNotEmpty() && gatewayDns != "0.0.0.0") {
            builder.addDnsServer(gatewayDns)
            note("dns gateway=$gatewayDns")
        }
        builder
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setMtu(1200)
            .allowFamily(android.system.OsConstants.AF_INET)
        if (defaultRoute) {
            builder.addRoute("0.0.0.0", 0)
            // The app must stay inside its own TUN: the in-app exit-IP lookup
            // is the only on-device proof of where traffic egresses, and an
            // excluded app would report the carrier address while every other
            // app uses the tunnel. The SoftEther session socket stays out of
            // the tunnel through protect() (nativeSetProtect → protectFd).
        }
        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.establish returned null")
        return pfd.detachFd()
    }

    fun protectFd(fd: Int): Int {
        val ok = protect(fd)
        if (ok) protectedSockets += 1
        // protect() binds the socket to the current default network. Binding
        // explicitly to the carrier is stronger: it survives a default-network
        // flip while the handshake is in progress and keeps the relay socket
        // out of the TUN we are about to install.
        carrier?.let { network ->
            // Network.bindSocket needs a FileDescriptor object and the platform
            // does not expose a public constructor. fromFd dups it; closing the
            // parcel closes only the dup, the native socket keeps its fd.
            try {
                ParcelFileDescriptor.fromFd(fd).use { dup ->
                    network.bindSocket(dup.fileDescriptor)
                }
            } catch (error: Throwable) {
                Log.w(TAG, "bindSocket fd=$fd failed: ${error.message}")
            }
        }
        Log.i(TAG, "protect fd=$fd ok=$ok")
        return if (ok) fd else -1
    }

    private fun sampledAddress(handle: Long): Pair<Int, Int>? {
        synchronized(sessionLock) {
            if (handle == 0L || client != handle) return null
            return nativeAssignedIp(handle) to nativeAssignedMask(handle)
        }
    }

    private fun closeTun() {
        synchronized(sessionLock) { closeTunLocked() }
    }

    private fun closeTunLocked() {
        val fd = tunFd
        tunFd = -1
        closeFdNow(fd)
    }

    private fun closeFdNow(fd: Int) {
        if (fd < 0) return
        try {
            // fromFd dups. A closed fd throws here instead of aborting in fdsan.
            ParcelFileDescriptor.fromFd(fd).close()
            ParcelFileDescriptor.adoptFd(fd).close()
        } catch (_: Throwable) {
        }
    }

    /**
     * replace_tun_fd() swaps the descriptor atomically, but a packet thread may
     * still be holding the previous fd for one poll cycle. Retire it shortly
     * after the swap instead of closing it under that thread.
     */
    private fun closeFdLater(fd: Int) {
        if (fd < 0) return
        Thread {
            try {
                Thread.sleep(1_500)
            } catch (_: InterruptedException) {
            }
            closeFdNow(fd)
        }.apply {
            isDaemon = true
            name = "tun-fd-retire"
        }.start()
    }

    fun isTunnelUp(): Boolean = tunnelUp && client != 0L && carrierUp

    fun statusReason(): String = stopReason
    fun isCarrierUp(): Boolean = carrierUp
    fun effectiveServerIp(): String = effectiveIp

    /// Snapshot for the in-app diagnostics sheet. Deliberately flag-based: it
    /// never calls into the native library, so it is safe during a handshake
    /// or a teardown.
    fun diagnostics(): Map<String, Any?> {
        val tail: List<String>
        synchronized(diag) { tail = diag.toList() }
        val now = SystemClock.elapsedRealtime()
        return mapOf(
            "running" to running.get(),
            "tunnelUp" to tunnelUp,
            "host" to activeHost,
            "reason" to stopReason.ifEmpty { lastReason },
            "carrierUp" to carrierUp,
            "effectiveIp" to effectiveIp,
            "protectedSockets" to protectedSockets,
            "networkGeneration" to networkGeneration,
            "connectedForMs" to if (connectedAt > 0 && tunnelUp) now - connectedAt else 0L,
            "connectInFlight" to connectInFlight,
            "clientAlive" to (client != 0L),
            "tunFd" to tunFd,
            "nativeLog" to tail,
        )
    }

    fun shutdown(reason: String = "") {
        if (reason.isNotEmpty()) {
            note("shutdown reason=$reason")
            stopReason = reason
            lastReason = reason
        }
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
        synchronized(sessionLock) {
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
            closeTunLocked()
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        // A handshake that blew its deadline is still on the native stack.
        // shutdown() must not destroy the client underneath it, but the client
        // must not be leaked either. Wait for nativeConnect to return, then
        // destroy the handle and its fds on a worker thread.
        if (connectInFlight) {
            releaseAfterHandshake()
        }
    }

    override fun onDestroy() {
        running.set(false)
        // A newer instance may already have registered itself; never clear it.
        if (instance === this) {
            instance = null
        }
        synchronized(sessionLock) {
            val handle = client
            if (handle != 0L) {
                try {
                    if (connectInFlight) {
                        nativeRequestStop(handle)
                    } else {
                        nativeStop(handle)
                        nativeDestroy(handle)
                    }
                } catch (_: Throwable) {
                }
                if (!connectInFlight) {
                    client = 0
                }
            }
            closeTunLocked()
        }
        super.onDestroy()
    }

    override fun onRevoke() {
        forgetRelay()
        finish(false, "revoked")
        shutdown("revoked")
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
        // iPhone and Mac finish this same relay in about 9s. An 8s cap
        // cancels the handshake (code -12) before DHCP returns.
        val cap = started + budgetMs
        var deadline = cap
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
                synchronized(sessionLock) {
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
                    closeTunLocked()
                }
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
    private external fun nativeGatewayIp(client: Long): Int
    private external fun nativeIsConnected(client: Long): Boolean
    private external fun nativeEffectiveServerIp(client: Long): Int
    private external fun nativeReplaceTun(client: Long, fd: Int): Int
    private external fun nativeStop(client: Long)
    private external fun nativeDestroy(client: Long)
    private external fun nativeBytesDown(client: Long): Long

    fun bytesReceived(): Long {
        // get_stats is not safe while softether_connect is on another thread.
        if (connectInFlight || !tunnelUp) return 0
        synchronized(sessionLock) {
            val handle = client
            if (handle == 0L) return 0
            return try {
                nativeBytesDown(handle)
            } catch (_: Throwable) {
                0
            }
        }
    }

    companion object {
        private const val TAG = "BulbSoftEther"
        private const val CHANNEL = "bulbvpn_ssl"
        private const val NOTIFICATION_ID = 41
        private const val PREFS = "bulb_vpn_relay"
        private const val PREF_HOST = "host"
        private const val PREF_SNI = "sni"
        const val EXTRA_HOST = "host"
        const val EXTRA_SNI = "sni"

        @Volatile
        var instance: SoftEtherVpnService? = null

        @Volatile
        var lastReason: String = ""

        @Volatile
        var onDone: ((Boolean, String) -> Unit)? = null

        fun finish(ok: Boolean, detail: String) {
            Log.i(TAG, "result ok=$ok detail=$detail")
            instance?.note("result ok=$ok detail=$detail")
            val callback = onDone
            onDone = null
            callback?.invoke(ok, detail)
        }

        fun requestStop(reason: String = "user") {
            lastReason = reason
            instance?.forgetRelay()
            instance?.shutdown(reason)
        }

        private fun formatIp(hostOrder: Int): String {
            val value = hostOrder.toLong() and 0xffffffffL
            return "${value shr 24 and 255}.${value shr 16 and 255}.${value shr 8 and 255}.${value and 255}"
        }

        /**
         * The native library exposes the server address as `struct in_addr.s_addr`
         * (network byte order). On little-endian Android that integer is
         * byte-swapped relative to the human-readable form, so 219.100.37.195
         * arrives as 195.37.100.219. Reverse the bytes before formatting.
         */
        private fun formatEffectiveIp(networkOrder: Int): String =
            formatIp(Integer.reverseBytes(networkOrder))
    }
}
