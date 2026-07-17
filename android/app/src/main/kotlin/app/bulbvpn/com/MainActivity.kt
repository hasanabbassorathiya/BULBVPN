package app.bulbvpn.com

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.axevpn.flutter.openvpn.AxeVPNFlutterPlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        AxeVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == Activity.RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
    }
}
