package app.bulbvpn.com

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

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
                    SoftEtherVpnService.requestStop()
                    result.success(null)
                }
                "bytesDown" -> {
                    result.success(SoftEtherVpnService.instance?.bytesReceived() ?: 0L)
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
        SoftEtherVpnService.onDone = { ok, detail ->
            runOnUiThread {
                pending?.success(mapOf("ok" to ok, "detail" to detail))
                pending = null
            }
        }
        val intent = Intent(this, SoftEtherVpnService::class.java)
            .putExtra(SoftEtherVpnService.EXTRA_HOST, host)
            .putExtra(SoftEtherVpnService.EXTRA_SNI, sni ?: host)
        startForegroundService(intent)
    }

    companion object {
        private const val CHANNEL = "app.bulbvpn.com/softether"
    }
}
