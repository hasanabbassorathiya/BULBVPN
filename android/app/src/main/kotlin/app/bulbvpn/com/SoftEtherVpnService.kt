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
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * SoftEther SSL-VPN over TLS into a VPN Gate hub.
 *
 * The hub is dialled on 443 by default; relays also answer the same TLS
 * handshake on 992/1194, which keeps a session possible when a network
 * filters the HTTPS port to VPN endpoints. OpenVPN's own packets stall on
 * these networks; TLS to the same servers does not.
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
    // "all" | "bypass" | "allow". Copied from the start intent, or from the
    // saved preference when Android recreates the service with a null intent.
    @Volatile private var routeMode: String = "all"
    @Volatile private var routeApps: Set<String> = emptySet()
    // Kill switch: a second, route-less TUN that swallows every packet after an
    // unexpected drop, so nothing leaves the phone in the clear while the app
    // reconnects. Only engaged when the user opted in.
    @Volatile private var lockdown: ParcelFileDescriptor? = null
    @Volatile private var lockdownThread: Thread? = null
    // shutdown() runs on several threads at once (connect worker, connectivity
    // callback, main). Two concurrent engages each established a TUN; the
    // loser's descriptor was overwritten and never closed, leaving a dead
    // interface behind. The whole lifecycle is serialised instead.
    private val lockdownLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    // request_stop/disconnect/destroy can block for seconds while the library
    // joins its own threads. Running them on the UI thread blocked input
    // dispatch long enough for Android to kill the app (ANR on AHS).
    private val stopExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "softether-stop").apply { isDaemon = true }
    }

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
        val blocking = intent?.action == ACTION_LOCKDOWN
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = notificationBuilder
            .setContentTitle("BULBVPN")
            .setContentText(if (blocking) "Traffic blocked — reconnect or disconnect" else "Connecting…")
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

        if (blocking) {
            if (engageLockdown()) return START_STICKY
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }


        var host = intent?.getStringExtra(EXTRA_HOST) ?: ""
        var sni = intent?.getStringExtra(EXTRA_SNI) ?: host
        var port = intent?.getIntExtra(EXTRA_PORT, 0) ?: 0
        if (host.isEmpty()) {
            val saved = savedRelay()
            host = saved.first
            sni = saved.second.ifEmpty { host }
            if (port == 0) port = saved.third
        }
        if (port !in 1..65535) port = DEFAULT_PORT
        if (host.isEmpty()) {
            if (tunnelUp) return START_STICKY
            if (wantsLockdown()) {
                // Android recreated the service after a drop; keep the block on
                // instead of silently restoring untunnelled traffic.
                if (engageLockdown()) return START_STICKY
                finish(false, "lockdown_failed")
                stopSelf()
                return START_NOT_STICKY
            }
            finish(false, "missing host")
            stopSelf()
            return START_NOT_STICKY
        }
        // A fresh connect replaces the block; if this attempt fails, shutdown()
        // puts the block back before the caller hears about the failure.
        disengageLockdown()
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
        applyRequestedRouting(intent)
        note("service start host=$host port=$port sni=$sni mode=$routeMode apps=${routeApps.size}")
        rememberRelay(host, sni, port)
        watchDefaultNetwork()
        Thread {
            try {
                connectBlocking(host, sni, port)
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

    private fun savedRelay(): Triple<String, String, Int> {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val port = prefs.getInt(PREF_PORT, DEFAULT_PORT)
        return Triple(
            prefs.getString(PREF_HOST, "") ?: "",
            prefs.getString(PREF_SNI, "") ?: "",
            if (port in 1..65535) port else DEFAULT_PORT,
        )
    }

    private fun savedRouteMode(): String {
        val saved = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PREF_MODE, "all")
        return if (saved == "bypass" || saved == "allow") saved else "all"
    }

    private fun savedRouteApps(): Set<String> {
        val saved = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(PREF_APPS, emptySet())
        return saved?.toSet() ?: emptySet()
    }

    /**
     * A start intent always carries the user's current choice. A null intent
     * (system restart, START_STICKY) reuses the saved one so a per-app tunnel
     * never silently widens to the whole device.
     */
    private fun applyRequestedRouting(intent: Intent?) {
        val requestedMode = intent?.getStringExtra(EXTRA_ROUTE_MODE)
        val requestedApps = intent?.getStringArrayListExtra(EXTRA_ROUTE_APPS)
        routeMode = when (requestedMode) {
            "bypass", "allow" -> requestedMode
            "all" -> "all"
            else -> savedRouteMode()
        }
        routeApps = when {
            requestedApps != null -> requestedApps.toSet()
            requestedMode == null -> savedRouteApps()
            else -> emptySet()
        }
        if (routeMode == "all") routeApps = emptySet()
    }

    private fun rememberRelay(host: String, sni: String, port: Int) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_HOST, host)
            .putString(PREF_SNI, sni)
            .putInt(PREF_PORT, port)
            .putString(PREF_MODE, routeMode)
            .putStringSet(PREF_APPS, routeApps)
            .apply()
    }

    private fun forgetRelay() {
        // Routing is a user preference, not session state: keep it when the
        // relay is forgotten after a failed dial.
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(PREF_HOST)
            .remove(PREF_SNI)
            .remove(PREF_PORT)
            .apply()
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

    private fun connectBlocking(host: String, sni: String, port: Int) {
        pinCarrier()
        val address = if (host.matches(Regex("""^\d+\.\d+\.\d+\.\d+$"""))) {
            host
        } else {
            InetAddress.getAllByName(host)
                .firstOrNull { it is Inet4Address }
                ?.hostAddress
                ?: host
        }
        note("dial $host:$port -> $address sni=$sni")
        System.loadLibrary("softether_jni")
        nativeSetProtect()
        // Always connect through the placeholder → DHCP → routed TUN swap
        // sequence. The remembered-IP shortcut (10.239.x reused before DHCP)
        // authenticated, logged "session up", and then read nothing from the
        // TUN (libsoftether DIAG nread=0, zero throughput) while the UI showed
        // Connected. The cold path takes ~12 s and actually passes traffic.
        val created = nativeCreate(address, port, "VPNGATE", "vpn", "vpn")
        if (created == 0L) {
            finish(false, "create failed")
            shutdown()
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
            Log.e(TAG, "initial tun failed", error)
            note("initial tun failed: ${error.message}")
            nativeDestroy(created)
            finish(false, "tun setup failed")
            shutdown()
            return
        }
        synchronized(sessionLock) {
            if (!running.get()) {
                nativeDestroy(created)
                closeFdNow(initial)
                return
            }
            client = created
            // Claim the handle before the handshake starts. shutdown() on
            // another thread must never destroy a client that nativeConnect is
            // about to use; the worker clears the claim when it returns.
            connectInFlight = true
            nativeConfigure(created, sni, false)
            tunFd = initial
            nativeSetTun(created, initial)
        }
        note("connecting $address:$port sni=$sni")
        val started = android.os.SystemClock.elapsedRealtime()
        var code = connectWithDeadline(created, 28_000)
        val fastReject = android.os.SystemClock.elapsedRealtime() - started < 15_000
        if (code == -5 && running.get() && fastReject) {
            // Only a real auth rejection earns a second handshake. -9 is an
            // adapter error, not auth. Reconnect the *same* client: destroying
            // it and creating another one races the native teardown.
            note("hashed auth rejected, retrying plain password on same client")
            var retry = false
            synchronized(sessionLock) {
                if (client == created && running.get()) {
                    connectInFlight = true
                    retry = true
                    nativeStop(created)
                    nativeConfigure(created, sni, true)
                    if (tunFd >= 0) nativeSetTun(created, tunFd)
                }
            }
            if (retry) code = connectWithDeadline(created, 28_000)
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
            // IPv6 refuses to live on a link below its 1280-byte minimum MTU,
            // and without a v6 address on the interface the ::/0 route is
            // rejected too, leaving v6 to leak around the tunnel. 1280 keeps
            // both families possible; the engine inside carries the frames.
            .setMtu(1280)
        if (defaultRoute) {
            builder.addRoute("0.0.0.0", 0)
            builder.addAddress(TUNNEL_IPV6, 128)
            // The engine is IPv4-only. Without a captured ::/0 route, dual-stack
            // carriers hand apps a direct IPv6 path around the tunnel. These
            // packets arrive here with no v6 session behind them and are
            // dropped, so apps fall back to IPv4 inside the tunnel.
            builder.addRoute("::", 0)
            // The app must stay inside its own TUN: the in-app exit-IP lookup
            // is the only on-device proof of where traffic egresses, and an
            // excluded app would report the carrier address while every other
            // app uses the tunnel. The SoftEther session socket stays out of
            // the tunnel through protect() (nativeSetProtect → protectFd).
            applyAppRouting(builder)
        }
        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.establish returned null")
        return pfd.detachFd()
    }

    /**
     * Per-app split routing. `allowed` and `disallowed` lists cannot be mixed
     * on one Builder, so exactly one branch adds entries. Unknown packages
     * (uninstalled since the choice was saved) are skipped instead of failing
     * the whole establish().
     */
    private fun applyAppRouting(builder: Builder) {
        when (routeMode) {
            "allow" -> {
                // BULBVPN stays inside its own tunnel so the exit-IP check
                // keeps reporting the real egress.
                var added = 0
                var skipped = 0
                for (pkg in routeApps + packageName) {
                    if (addAllowed(builder, pkg)) added += 1 else skipped += 1
                }
                note("routing allow-only added=$added skipped=$skipped")
            }
            "bypass" -> {
                var added = 0
                var skipped = 0
                for (pkg in routeApps) {
                    if (pkg == packageName) continue
                    if (addDisallowed(builder, pkg)) added += 1 else skipped += 1
                }
                note("routing bypass added=$added skipped=$skipped")
            }
            else -> note("routing full tunnel")
        }
    }

    private fun addAllowed(builder: Builder, pkg: String): Boolean {
        return try {
            builder.addAllowedApplication(pkg)
            true
        } catch (error: Throwable) {
            note("allowed app $pkg skipped: ${error.javaClass.simpleName}")
            false
        }
    }

    private fun addDisallowed(builder: Builder, pkg: String): Boolean {
        return try {
            builder.addDisallowedApplication(pkg)
            true
        } catch (error: Throwable) {
            note("bypassed app $pkg skipped: ${error.javaClass.simpleName}")
            false
        }
    }

    private fun wantsLockdown(): Boolean =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(PREF_KILL_SWITCH, false)

    fun isLockedDown(): Boolean = lockdown != null

    /**
     * Re-blocks traffic from outside shutdown(), e.g. when Dart arms the
     * switch after a failed connect while no service instance was alive.
     * No-op when the user has the kill switch off, so callers may invoke it
     * unconditionally.
     */
    fun lockdownNow(): Boolean = wantsLockdown() && engageLockdown()

    /** Lifts an active block; without a tunnel there is nothing left to serve. */
    fun releaseLockdown() {
        if (lockdown == null) return
        disengageLockdown()
        if (!tunnelUp) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    /**
     * Installs a catch-all TUN with no relay behind it. Every packet the phone
     * sends is routed in here and dropped, so a dead tunnel cannot silently fall
     * back to the carrier. IPv6 is covered too; the SoftEther session itself is
     * IPv4-only, so without this a lost IPv4 tunnel leaves v6 wide open.
     */
    private fun engageLockdown(): Boolean = synchronized(lockdownLock) {
        if (lockdown != null) return true
        try {
            val builder = Builder()
                .setSession("BULBVPN kill switch")
                .addAddress(LOCKDOWN_IPV4, 32)
                .addRoute("0.0.0.0", 0)
                .addAddress(LOCKDOWN_IPV6, 128)
                .addRoute("::", 0)
                .setMtu(1400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            val pfd = builder.establish()
                ?: throw IllegalStateException("establish returned null")
            lockdown = pfd
            note("kill switch engaged")
            updateNotification("Traffic blocked — reconnect or disconnect")
            val fd = pfd.fileDescriptor
            lockdownThread = Thread {
                val buffer = ByteArray(32767)
                val fds = arrayOf(StructPollfd().apply {
                    this.fd = fd
                    events = OsConstants.POLLIN.toShort()
                })
                // Closing an fd from another thread does not wake a blocked
                // read/poll on Linux, and a thread parked in Os.read keeps the
                // file description alive, leaking the interface. Polling with a
                // timeout guarantees the thread notices the release.
                while (true) {
                    try {
                        if (Os.poll(fds, 250) > 0) {
                            if (lockdown !== pfd) break
                            if (fds[0].revents.toInt() and OsConstants.POLLNVAL != 0) break
                            if (Os.read(fd, buffer, 0, buffer.size) < 0) break
                        } else if (lockdown !== pfd) {
                            break
                        }
                    } catch (_: Throwable) {
                        break
                    }
                }
            }.apply {
                name = "bulb-lockdown"
                isDaemon = true
            }.also { it.start() }
            return true
        } catch (error: Throwable) {
            Log.e(TAG, "kill switch failed", error)
            note("kill switch failed: ${error.javaClass.simpleName}")
            return false
        }
    }

    private fun disengageLockdown() {
        synchronized(lockdownLock) {
            val pfd = lockdown ?: return
            lockdown = null
            lockdownThread?.interrupt()
            lockdownThread = null
            try {
                pfd.close()
            } catch (_: Throwable) {
            }
            note("kill switch released")
        }
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
    fun routeModeName(): String = routeMode
    fun routeAppCount(): Int = if (routeMode == "all") 0 else routeApps.size

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
            "routeMode" to routeMode,
            "routeApps" to routeApps.sorted(),
            "lockedDown" to (lockdown != null),
            "nativeLog" to tail,
        )
    }

    fun shutdown(reason: String = "") {
        // Native teardown blocks for seconds and the liveness loop reads the
        // session under sessionLock. Both must stay off the UI thread: run the
        // whole shutdown on the stop worker instead of blocking input dispatch
        // (the search for that ANR is in docs/connection-solutions.md §11).
        if (Looper.myLooper() == Looper.getMainLooper()) {
            stopExecutor.execute { shutdown(reason) }
            return
        }
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
        var deferred = 0L
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
                deferred = handle
            }
            closeTunLocked()
        }
        // A handshake that blew its deadline is still on the native stack.
        // shutdown() must not destroy the client underneath it.
        if (deferred != 0L) releaseAfterHandshake(deferred)
        // A user-initiated stop must never block the phone. Every other exit —
        // link loss, revoked consent, failed handshake — is a drop, and a drop
        // with the kill switch on keeps the service alive behind a blocking TUN.
        if (reason != "user" && reason != "revoked" && wantsLockdown()) {
            if (engageLockdown()) return
        }
        disengageLockdown()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        running.set(false)
        // A newer instance may already have registered itself; never clear it.
        if (instance === this) {
            instance = null
        }
        // onDestroy always arrives on the main thread; hand the native work
        // to the stop worker and return immediately.
        stopExecutor.execute {
            releaseSession()
            disengageLockdown()
        }
        super.onDestroy()
    }

    /** Lock-protected teardown. Must never run on the main thread. */
    private fun releaseSession() {
        var deferred = 0L
        synchronized(sessionLock) {
            val handle = client
            if (handle != 0L) {
                if (connectInFlight) {
                    try {
                        nativeRequestStop(handle)
                    } catch (_: Throwable) {
                    }
                    deferred = handle
                } else {
                    try {
                        nativeStop(handle)
                    } catch (_: Throwable) {
                    }
                    try {
                        nativeDestroy(handle)
                    } catch (_: Throwable) {
                    }
                    client = 0
                }
            }
            closeTunLocked()
        }
        if (deferred != 0L) releaseAfterHandshake(deferred)
    }

    override fun onRevoke() {
        forgetRelay()
        finish(false, "revoked")
        // Revocation is delivered on the main thread; teardown is not.
        stopOffMain("revoked")
        super.onRevoke()
    }

    private fun stopOffMain(reason: String) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            stopExecutor.execute { shutdown(reason) }
        } else {
            shutdown(reason)
        }
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
    /// crashes the process. Querying the client while nativeConnect is on the
    /// stack is just as unsafe: softether_get_assigned_ip() dereferences
    /// session state the handshake is still building (SIGSEGV on AHS).
    private fun connectWithDeadline(handle: Long, budgetMs: Long): Int {
        val result = intArrayOf(-100)
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
        val deadline = started + budgetMs
        while (worker.isAlive && android.os.SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(200)
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

    /// The handshake thread can outlive the deadline. Free the client this
    /// service abandoned only after nativeConnect returns, and only if no
    /// newer attempt has claimed the slot. Destroying whatever `client`
    /// happens to hold freed a live relay under its own handshake on AHS and
    /// aborted the whole process.
    private fun releaseAfterHandshake(stale: Long) {
        if (stale == 0L) return
        Thread {
            val deadline = android.os.SystemClock.elapsedRealtime() + 20_000
            while (connectInFlight && android.os.SystemClock.elapsedRealtime() < deadline) {
                try {
                    Thread.sleep(200)
                } catch (_: InterruptedException) {
                }
            }
            var owned = false
            synchronized(sessionLock) {
                if (client == stale) {
                    // Even past the deadline the worker may still be on the
                    // native stack; request_stop is safe, destroy is not.
                    // Leaking one client is better than killing the process.
                    val stillHandshaking = connectInFlight
                    client = 0
                    owned = true
                    if (!stillHandshaking) {
                        try {
                            nativeStop(stale)
                        } catch (_: Throwable) {
                        }
                        try {
                            nativeDestroy(stale)
                        } catch (_: Throwable) {
                        }
                    }
                    closeTunLocked()
                }
            }
            if (owned && !tunnelUp) {
                running.set(false)
                // The kill switch keeps the service alive with no tunnel.
                if (lockdown == null) {
                    try {
                        stopSelf()
                    } catch (_: Throwable) {
                    }
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
        private const val PREF_PORT = "port"
        private const val PREF_MODE = "route_mode"
        private const val PREF_APPS = "route_apps"
        private const val PREF_KILL_SWITCH = "kill_switch"
        private const val LOCKDOWN_IPV4 = "198.18.0.2"
        private const val LOCKDOWN_IPV6 = "fd00:0:0:2::2"
        private const val TUNNEL_IPV6 = "fd00:0:0:1::2"
        const val ACTION_LOCKDOWN = "app.bulbvpn.com.LOCKDOWN"
        const val EXTRA_HOST = "host"
        const val EXTRA_SNI = "sni"
        const val EXTRA_PORT = "port"
        const val EXTRA_ROUTE_MODE = "route_mode"
        const val EXTRA_ROUTE_APPS = "route_apps"
        const val DEFAULT_PORT = 443

        @Volatile
        var instance: SoftEtherVpnService? = null

        @Volatile
        var lastReason: String = ""

        @Volatile
        var onDone: ((Boolean, String) -> Unit)? = null

        /** Mirrors the Dart toggle into the prefs the service reads on a drop. */
        fun setKillSwitch(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREF_KILL_SWITCH, enabled)
                .apply()
            // Turning the switch off must hand the network back immediately,
            // not on the next connect or disconnect.
            if (!enabled) instance?.releaseLockdown()
        }

        /**
         * Installs the block even when no instance is alive. A failed connect
         * must fail closed: the tunnel's service may already have stopped, and
         * `instance?.lockdownNow()` would then silently do nothing while the
         * phone falls back to the carrier. No-op when the switch is off.
         */
        fun armLockdown(context: Context): Boolean {
            val wanted = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(PREF_KILL_SWITCH, false)
            if (!wanted) return false
            instance?.let { return it.lockdownNow() }
            return try {
                val intent = Intent(context, SoftEtherVpnService::class.java)
                    .setAction(ACTION_LOCKDOWN)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (error: Throwable) {
                Log.e(TAG, "lockdown arm failed", error)
                false
            }
        }

        fun finish(ok: Boolean, detail: String) {
            Log.i(TAG, "result ok=$ok detail=$detail")
            instance?.note("result ok=$ok detail=$detail")
            val callback = onDone
            onDone = null
            callback?.invoke(ok, detail)
        }

        fun requestStop(reason: String = "user") {
            lastReason = reason
            val service = instance ?: return
            service.forgetRelay()
            // Callers include the Dart disconnect handler and the connect
            // timeout, both on the main thread. shutdown() is not theirs to
            // block on.
            service.stopOffMain(reason)
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
