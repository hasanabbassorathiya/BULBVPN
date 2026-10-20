package app.bulbvpn.com

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
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
                "connect" -> connect(call.argument<String>("host"), call.argument<String>("sni"), result)
                "disconnect" -> {
                    pendingToken++
                    val previous = pending
                    pending = null
                    previous?.success(mapOf("ok" to false, "detail" to "cancelled"))
                    SoftEtherVpnService.requestStop()
                    result.success(null)
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
                        ),
                    )
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

    private fun connect(host: String?, sni: String?, result: MethodChannel.Result) {
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
        val intent = Intent(this, SoftEtherVpnService::class.java)
            .putExtra(SoftEtherVpnService.EXTRA_HOST, host)
            .putExtra(SoftEtherVpnService.EXTRA_SNI, sni ?: host)
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

    companion object {
        private const val CHANNEL = "app.bulbvpn.com/softether"
    }
}
