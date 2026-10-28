package com.crudoc.app

import android.content.Intent
import android.net.Uri
import android.os.Build
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
