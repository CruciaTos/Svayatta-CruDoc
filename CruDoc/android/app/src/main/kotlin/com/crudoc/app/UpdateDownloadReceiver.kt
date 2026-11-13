package com.crudoc.app

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.File

/**
 * Hears from the system DownloadManager: the update APK finished (or
 * failed) while CruDoc may not be running, or the person tapped the
 * running-download notification.
 */
class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            DownloadManager.ACTION_DOWNLOAD_COMPLETE -> {
                val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                if (id == -1L || id != UpdateDownloads.storedId(context)) return
                val info = UpdateDownloads.query(context)
                when (info["status"]) {
                    "successful" -> {
                        val path = info["path"] as? String
                        if (path != null) UpdateDownloads.postReadyNotification(context, File(path))
                    }
                    "failed" -> UpdateDownloads.postFailedNotification(context)
                }
            }
            DownloadManager.ACTION_NOTIFICATION_CLICKED -> {
                try {
                    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    if (launch != null) {
                        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(launch)
                    }
                } catch (e: Exception) {
                }
            }
        }
    }
}
