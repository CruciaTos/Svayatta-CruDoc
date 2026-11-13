package com.crudoc.app

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.io.File

/**
 * App-update APK download through Android's own DownloadManager, so it keeps
 * going when the app is closed, shows its own progress notification and
 * waits for the network by itself. Shared by MainActivity (the Flutter
 * bridge) and UpdateDownloadReceiver (the "download finished" broadcast).
 */
object UpdateDownloads {
    private const val PREFS = "crudoc_update"
    private const val KEY_ID = "id"
    private const val KEY_FILE = "fileName"
    private const val CHANNEL_ID = "app_updates"
    private const val NOTIFICATION_ID = 4711
    private const val APK_MIME = "application/vnd.android.package-archive"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun manager(ctx: Context) = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    fun storedId(ctx: Context): Long = prefs(ctx).getLong(KEY_ID, -1L)

    private fun storedFileName(ctx: Context): String? = prefs(ctx).getString(KEY_FILE, null)

    private fun targetFile(ctx: Context, fileName: String): File =
        File(File(ctx.getExternalFilesDir(null), "updates"), fileName)

    /**
     * Starts (or re-attaches to) the download of [fileName]. Never starts a
     * second one while the same file is downloading or already finished.
     */
    fun start(ctx: Context, url: String, fileName: String, title: String): Long {
        val id = storedId(ctx)
        if (id != -1L && storedFileName(ctx) == fileName) {
            val info = query(ctx)
            when (info["status"]) {
                "pending", "running", "paused" -> return id
                "successful" -> {
                    val path = info["path"] as? String
                    if (path != null && File(path).exists()) return id
                }
            }
        }
        if (id != -1L) {
            try {
                manager(ctx).remove(id)
            } catch (e: Exception) {
            }
        }
        try {
            targetFile(ctx, fileName).delete()
        } catch (e: Exception) {
        }

        val request = DownloadManager.Request(Uri.parse(url))
            .setDestinationInExternalFilesDir(ctx, "updates", fileName)
            .setMimeType(APK_MIME)
            .setTitle(title)
            .setDescription("Downloading update")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
        val newId = manager(ctx).enqueue(request)
        prefs(ctx).edit().putLong(KEY_ID, newId).putString(KEY_FILE, fileName).apply()
        return newId
    }

    /** State of the stored download: status, bytes, total, reason, path. */
    fun query(ctx: Context): Map<String, Any?> {
        val id = storedId(ctx)
        val fileName = storedFileName(ctx)
        val none = mapOf<String, Any?>(
            "status" to "none",
            "bytes" to 0L,
            "total" to 0L,
            "reason" to 0,
            "waitingForNetwork" to false,
            "path" to null,
            "fileName" to fileName,
        )
        if (id == -1L) return none
        try {
            manager(ctx).query(DownloadManager.Query().setFilterById(id))?.use { c ->
                if (!c.moveToFirst()) return none
                val code = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val bytes = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val reason = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                val status = when (code) {
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "successful"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "none"
                }
                val waiting = code == DownloadManager.STATUS_PAUSED &&
                    (reason == DownloadManager.PAUSED_WAITING_FOR_NETWORK ||
                        reason == DownloadManager.PAUSED_WAITING_TO_RETRY)
                var path: String? = null
                if (status == "successful") {
                    val uriString = c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                    path = uriString?.let { Uri.parse(it).path }
                }
                return mapOf(
                    "status" to status,
                    "bytes" to bytes,
                    "total" to total,
                    "reason" to reason,
                    "waitingForNetwork" to waiting,
                    "path" to path,
                    "fileName" to fileName,
                )
            }
        } catch (e: Exception) {
        }
        return none
    }

    /** Stops the stored download and forgets it, deleting any partial/finished file. */
    fun cancel(ctx: Context) {
        val id = storedId(ctx)
        val fileName = storedFileName(ctx)
        if (id != -1L) {
            try {
                manager(ctx).remove(id)
            } catch (e: Exception) {
            }
        }
        if (fileName != null) {
            try {
                targetFile(ctx, fileName).delete()
            } catch (e: Exception) {
            }
        }
        prefs(ctx).edit().clear().apply()
        cancelReadyNotification(ctx)
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "App updates", NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    private fun notify(ctx: Context, title: String, text: String, contentIntent: PendingIntent) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!nm.areNotificationsEnabled()) return
            ensureChannel(ctx)
            val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .build()
            nm.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
        }
    }

    fun postReadyNotification(ctx: Context, file: File) {
        try {
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.updates", file)
            val install = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, APK_MIME)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            val pending = PendingIntent.getActivity(
                ctx,
                0,
                install,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            notify(ctx, "CruDoc update ready", "Tap to install", pending)
        } catch (e: Exception) {
        }
    }

    fun postFailedNotification(ctx: Context) {
        try {
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val pending = PendingIntent.getActivity(
                ctx,
                1,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            notify(ctx, "CruDoc update failed", "Open CruDoc to try again", pending)
        } catch (e: Exception) {
        }
    }

    fun cancelReadyNotification(ctx: Context) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
        }
    }
}
