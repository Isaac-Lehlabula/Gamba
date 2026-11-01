package za.reclaim.reclaim_app.blocker

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Flutter's view of the blocker (channel "za.reclaim/blocker"). See
 * mobile/lib/features/blocker/data/blocker_platform.dart for the Dart side.
 */
class BlockerChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, NAME).also { it.setMethodCallHandler(this) }
    private var pendingPermission: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(true)
            "isRunning" -> result.success(ReclaimVpnService.active)
            "requestPermission" -> requestPermission(result)
            "start" -> {
                if (VpnService.prepare(activity) != null) return result.success(false)
                activity.startForegroundService(Intent(activity, ReclaimVpnService::class.java).setAction(ReclaimVpnService.ACTION_START))
                result.success(true)
            }
            "stop" -> {
                if (ReclaimVpnService.active) {
                    activity.startService(Intent(activity, ReclaimVpnService::class.java).setAction(ReclaimVpnService.ACTION_STOP))
                }
                result.success(null)
            }
            "setBlocklist" -> {
                val domains = call.argument<List<String>>("domains").orEmpty()
                File(activity.filesDir, ReclaimVpnService.BLOCKLIST_FILE).writeText(domains.joinToString("\n"))
                if (ReclaimVpnService.active) {
                    activity.startService(Intent(activity, ReclaimVpnService::class.java).setAction(ReclaimVpnService.ACTION_RELOAD))
                }
                result.success(null)
            }
            "blockedLog" -> result.success(ReclaimVpnService.readBlockedLog(activity))
            "clearBlockedLog" -> {
                ReclaimVpnService.clearBlockedLog(activity)
                result.success(null)
            }
            "openVpnSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Shows Android's one-time VPN consent dialog if it hasn't been granted. */
    private fun requestPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity) ?: return result.success(true)
        pendingPermission?.success(false)
        pendingPermission = result
        @Suppress("DEPRECATION") // FlutterFragmentActivity routes this back through onActivityResult.
        activity.startActivityForResult(intent, REQUEST_VPN)
    }

    /** Call from the activity's onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) return false
        pendingPermission?.success(resultCode == Activity.RESULT_OK)
        pendingPermission = null
        return true
    }

    fun dispose() = channel.setMethodCallHandler(null)

    companion object {
        const val NAME = "za.reclaim/blocker"
        private const val REQUEST_VPN = 0x52C1
    }
}
