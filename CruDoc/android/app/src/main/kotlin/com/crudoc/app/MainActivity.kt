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
        // The screen's rounded-corner radius in pixels, so the phone island
        // never gets cut by the display corners (lib/features/mobile/display_corners.dart).
        // -1 when the phone can't say (Android 11 and older).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crudoc/display")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cornerRadius" -> result.success(topCornerRadius())
                    // The phone island owns the top strip: hide the status
                    // bar the modern way, so it survives focus changes
                    // (speech recognizer, dialogs) and a swipe only peeks it.
                    "hideStatusBar" -> {
                        wantBarHidden = true
                        watchStatusBar()
                        hideBar()
                        result.success(null)
                    }
                    "showStatusBar" -> {
                        wantBarHidden = false
                        barHandler.removeCallbacks(rehideBar)
                        insetsController().show(androidx.core.view.WindowInsetsCompat.Type.statusBars())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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
                    // Background download through the system DownloadManager.
                    "startApkDownload" -> try {
                        result.success(
                            UpdateDownloads.start(
                                this,
                                call.argument<String>("url") ?: "",
                                call.argument<String>("fileName") ?: "update.apk",
                                call.argument<String>("title") ?: "CruDoc update",
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: "The download could not start.", null)
                    }
                    "queryApkDownload" -> result.success(UpdateDownloads.query(this))
                    "cancelApkDownload" -> {
                        UpdateDownloads.cancel(this)
                        result.success(null)
                    }
                    "canInstallPackages" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls(),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Opens the system installer on the downloaded APK. Android makes the
     * person allow "install unknown apps" for CruDoc once: if that is off,
     * its settings page opens and the call fails with a message to try again.
     */
    // The phone island hides the status bar so it owns the top strip. A
    // "transient" swipe-peek would get Android's dark see-through scrim, so
    // the default behaviour is used instead: a swipe shows the bar for real
    // (clear, just the clock and icons, as when it was always on), and it is
    // hidden again a few seconds later.
    private var wantBarHidden = false
    private var barWatcher: android.view.View? = null
    private val barHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val rehideBar = Runnable { if (wantBarHidden) hideBar() }

    private fun insetsController() =
        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)

    private fun hideBar() {
        insetsController().apply {
            systemBarsBehavior =
                androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            hide(androidx.core.view.WindowInsetsCompat.Type.statusBars())
        }
    }

    /** A zero-size view beside Flutter's that hears every insets change. */
    private fun watchStatusBar() {
        if (barWatcher != null) return
        val root = findViewById<android.view.ViewGroup>(android.R.id.content) ?: return
        val v = android.view.View(this)
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(v) { _, insets ->
            val visible = insets.isVisible(androidx.core.view.WindowInsetsCompat.Type.statusBars())
            if (visible && wantBarHidden) {
                barHandler.removeCallbacks(rehideBar)
                barHandler.postDelayed(rehideBar, 3000)
            }
            insets
        }
        root.addView(v, android.view.ViewGroup.LayoutParams(0, 0))
        barWatcher = v
    }

    /** Larger of the two top display-corner radii, px; -1 when unknown. */
    private fun topCornerRadius(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return -1
        val insets = window?.decorView?.rootWindowInsets ?: return -1
        val left = insets.getRoundedCorner(android.view.RoundedCorner.POSITION_TOP_LEFT)?.radius ?: 0
        val right = insets.getRoundedCorner(android.view.RoundedCorner.POSITION_TOP_RIGHT)?.radius ?: 0
        return maxOf(left, right)
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("NO_FILE", "The downloaded update could not be found.", null)
                return
            }
            UpdateDownloads.cancelReadyNotification(this)
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
                    "Allow CruDoc to install updates, then come back — the update continues by itself.",
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
