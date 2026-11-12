package com.crudoc.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Settings → Call forwarding (lib/features/settings/data/call_forwarding_platform.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crudoc/call_forwarding")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "callingSim" -> result.success(callingSim())
                    "dial" -> result.success(dial(call.argument<String>("number") ?: ""))
                    "openCallSettings" -> result.success(openCallSettings())
                    else -> result.notImplemented()
                }
            }
        // In-app updates (lib/core/update/platform/android_update_installer.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crudoc/update_installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path") ?: "", result)
                    // Processor types this phone runs, best first, so the
                    // matching per-ABI APK is downloaded.
                    "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Opens the system installer on the downloaded APK. Android makes the
     * person allow "install unknown apps" for CruDoc once: if that is off,
     * its settings page opens and the call fails with a message to try again.
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("NO_FILE", "The downloaded update could not be found.", null)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.error(
                    "NEEDS_PERMISSION",
                    "Allow CruDoc to install updates in the settings that just opened, then tap Update again.",
                    null,
                )
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message ?: "The installer could not be opened.", null)
        }
    }

    /**
     * The carrier of the SIM that makes calls, so the app can tell Jio apart.
     * Needs no permission. `sure` is false on a dual-SIM phone set to "ask
     * every time", where the answer may be the other SIM.
     */
    private fun callingSim(): Map<String, Any?>? = try {
        val base = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
        var tm = base
        var sure = false
        if (base != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val id = SubscriptionManager.getDefaultVoiceSubscriptionId()
            if (id != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                tm = base.createForSubscriptionId(id)
                sure = true
            }
        }
        val name = tm?.simOperatorName.orEmpty()
        val mccMnc = tm?.simOperator.orEmpty()
        if (name.isBlank() && mccMnc.isBlank()) null
        else mapOf("name" to name, "mccMnc" to mccMnc, "sure" to sure)
    } catch (e: Exception) {
        null
    }

    /**
     * Opens the dialler with [number] filled in (a forwarding code such as
     * **21*+91…#). The doctor presses call themselves. Uri.fromParts encodes
     * '#' so the dialler receives the whole code.
     */
    private fun dial(number: String): Boolean = try {
        val uri = if (number.isEmpty()) Uri.parse("tel:") else Uri.fromParts("tel", number, null)
        startActivity(Intent(Intent.ACTION_DIAL, uri))
        true
    } catch (e: Exception) {
        false
    }

    /** The phone's call settings, where Call forwarding lives. */
    private fun openCallSettings(): Boolean = try {
        startActivity(Intent(TelecomManager.ACTION_SHOW_CALL_SETTINGS))
        true
    } catch (e: Exception) {
        dial("")
    }
}
