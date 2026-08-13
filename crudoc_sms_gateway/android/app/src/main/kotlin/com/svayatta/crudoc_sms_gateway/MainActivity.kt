package com.svayatta.crudoc_sms_gateway

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.svayatta.crudoc_sms_gateway/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    val simSlot = call.argument<Int>("simSlot") ?: 0

                    if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Phone and message are required", null)
                        return@setMethodCallHandler
                    }

                    sendSms(phone, message, simSlot, result)
                }

                "getSimInfo" -> {
                    result.success(getSimInfo())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun sendSms(phone: String, message: String, simSlot: Int, result: MethodChannel.Result) {
        try {
            val smsManager = getSmsManager(simSlot)

            val sentAction = "SMS_SENT_${System.currentTimeMillis()}"
            val sentPI = PendingIntent.getBroadcast(
                this, 0, Intent(sentAction),
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )

            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    try { unregisterReceiver(this) } catch (_: Exception) {}

                    when (resultCode) {
                        Activity.RESULT_OK -> {
                            result.success(mapOf("status" to "sent"))
                        }
                        else -> {
                            val errorMsg = when (resultCode) {
                                SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "Generic failure"
                                SmsManager.RESULT_ERROR_NO_SERVICE -> "No service"
                                SmsManager.RESULT_ERROR_NULL_PDU -> "Null PDU"
                                SmsManager.RESULT_ERROR_RADIO_OFF -> "Radio off"
                                SmsManager.RESULT_ERROR_LIMIT_EXCEEDED -> "Limit exceeded"
                                else -> "Unknown error (code: $resultCode)"
                            }
                            result.success(mapOf("status" to "failed", "error" to errorMsg))
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, IntentFilter(sentAction), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, IntentFilter(sentAction))
            }

            // Handle multi-part (long) SMS
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                val sentIntents = ArrayList<PendingIntent>()
                sentIntents.add(sentPI)
                for (i in 1 until parts.size) {
                    sentIntents.add(PendingIntent.getBroadcast(
                        this, i, Intent(sentAction),
                        PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
                    ))
                }
                smsManager.sendMultipartTextMessage(phone, null, parts, sentIntents, null)
            } else {
                smsManager.sendTextMessage(phone, null, message, sentPI, null)
            }
        } catch (e: Exception) {
            result.success(mapOf("status" to "failed", "error" to (e.message ?: "Unknown exception")))
        }
    }

    @Suppress("DEPRECATION")
    private fun getSmsManager(simSlot: Int): SmsManager {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val subs = try { subManager?.activeSubscriptionInfoList } catch (_: SecurityException) { null }
            if (subs != null && simSlot < subs.size) {
                return getSystemService(SmsManager::class.java).createForSubscriptionId(subs[simSlot].subscriptionId)
            }
            return getSystemService(SmsManager::class.java)
        } else {
            return SmsManager.getDefault()
        }
    }

    private fun getSimInfo(): Map<String, Any?> {
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
        val sims = mutableListOf<Map<String, Any?>>()

        try {
            val subs = subManager?.activeSubscriptionInfoList
            if (subs != null) {
                for (sub in subs) {
                    sims.add(mapOf(
                        "slot" to sub.simSlotIndex,
                        "carrier" to (sub.carrierName?.toString() ?: "Unknown"),
                        "number" to (sub.number ?: ""),
                        "subscriptionId" to sub.subscriptionId,
                    ))
                }
            }
        } catch (_: SecurityException) {
            // Permission not granted
        }

        return mapOf(
            "simCount" to sims.size,
            "sims" to sims,
            "simState" to tm.simState,
            "hasIccCard" to tm.hasIccCard(),
        )
    }
}
