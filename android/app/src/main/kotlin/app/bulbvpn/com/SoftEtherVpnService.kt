package app.bulbvpn.com

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
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
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val host = intent?.getStringExtra(EXTRA_HOST) ?: ""
        val sni = intent?.getStringExtra(EXTRA_SNI) ?: host
        if (host.isEmpty()) {
            finish(false, "missing host")
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running.compareAndSet(false, true)) {
            finish(false, "already running")
            return START_NOT_STICKY
        }
        Thread {
            try {
                connectBlocking(host, sni)
            } catch (error: Throwable) {
                Log.e(TAG, "connect failed", error)
                finish(false, error.message ?: "exception")
                shutdown()
            }
        }.apply { name = "softether" }.start()
        return START_NOT_STICKY
    }

    private fun connectBlocking(host: String, sni: String) {
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
        var code = nativeConnect(created)
        if (code != 0 && running.get()) {
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
            code = nativeConnect(retry)
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
        val replacement = openTun(tunnelIp, prefix, defaultRoute = true)
        if (nativeReplaceTun(client, replacement) == 0) {
            closeTun()
            tunFd = replacement
        } else {
            ParcelFileDescriptor.adoptFd(replacement).close()
            finish(false, "route update failed")
            shutdown()
            return
        }
        finish(true, tunnelIp)
        while (running.get()) {
            Thread.sleep(400)
        }
        shutdown()
    }

    private fun openTun(address: String, prefix: Int, defaultRoute: Boolean): Int {
        val builder = Builder()
            .setSession("BULBVPN")
            .addAddress(address, prefix)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setMtu(1280)
        if (defaultRoute) {
            builder.addRoute("0.0.0.0", 0)
        }
        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.establish returned null")
        return pfd.detachFd()
    }

    fun protectFd(fd: Int): Int = if (protect(fd)) fd else -1

    private fun closeTun() {
        if (tunFd >= 0) {
            try {
                ParcelFileDescriptor.adoptFd(tunFd).close()
            } catch (_: Exception) {
            }
            tunFd = -1
        }
    }

    fun shutdown() {
        running.set(false)
        val handle = client
        if (handle != 0L) {
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
    private external fun nativeAssignedIp(client: Long): Int
    private external fun nativeAssignedMask(client: Long): Int
    private external fun nativeReplaceTun(client: Long, fd: Int): Int
    private external fun nativeStop(client: Long)
    private external fun nativeDestroy(client: Long)
    private external fun nativeBytesDown(client: Long): Long

    fun bytesReceived(): Long {
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
            instance?.shutdown()
        }

        private fun formatIp(hostOrder: Int): String {
            val value = hostOrder.toLong() and 0xffffffffL
            return "${value shr 24 and 255}.${value shr 16 and 255}.${value shr 8 and 255}.${value and 255}"
        }
    }
}
