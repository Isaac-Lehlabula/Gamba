package za.reclaim.reclaim_app

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import za.reclaim.reclaim_app.blocker.BlockerChannel

// FragmentActivity is required by local_auth for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private var blocker: BlockerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        blocker = BlockerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        blocker?.dispose()
        blocker = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Needed for VpnService.prepare's consent dialog result.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (blocker?.onActivityResult(requestCode, resultCode) != true) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
