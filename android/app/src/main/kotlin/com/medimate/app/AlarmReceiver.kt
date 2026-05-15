// android/app/src/main/kotlin/com/medimate/app/AlarmReceiver.kt
package com.medimate.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.*

// ══════════════════════════════════════════════════════════════════════════
// CHANGES vs original:
//
// FIX 1 — Auto-dismiss (no-action timeout):
//   Added USER_ID_KEY extra so the userId travels with the alarm.
//   Added .setTimeoutAfter(autoTimeoutMs) to the notification so Android
//   automatically dismisses it after (TTS duration + 3 s), which fires
//   the deleteIntent → ACTION_DISMISSED → dose_no_action without the user
//   having to swipe. Previously the card stayed on screen forever.
//   The timeout is estimated as: (word-count / 2.5 words-per-sec × 1000) + 3000ms.
//
// FIX 2 — userId travels with the alarm:
//   Added USER_ID_KEY so ReminderRepository never has to do a Firestore
//   collectionGroup query to look up the userId. Instead it reads it directly
//   from the event map, eliminating the silent failure that prevented dose
//   logs from being written.
//
// All other code is identical to the original.
// ══════════════════════════════════════════════════════════════════════════

class AlarmReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID          = "medicine_reminders"
        const val NOTIFICATION_ID_KEY = "notification_id"
        const val MEDICINE_NAME_KEY   = "medicine_name"
        const val DOSAGE_KEY          = "dosage"
        const val INSTRUCTIONS_KEY    = "instructions"
        const val REMINDER_ID_KEY     = "reminder_id"
        const val SCHEDULED_TIME_KEY  = "scheduled_time"
        const val RETRY_COUNT_KEY     = "retry_count"
        // FIX 2: carry userId so Firestore lookup is not needed
        const val USER_ID_KEY         = "user_id"
        const val MAX_RETRIES         = 5

        // FIX 1: estimate TTS duration from message text (words / 2.5 wps × 1000 ms)
        // + 3 000 ms grace period before auto-dismiss.
        fun estimateAutoTimeoutMs(message: String): Long {
            val wordCount = message.trim().split(Regex("\\s+")).size
            val ttsDurationMs = (wordCount / 2.5 * 1000).toLong()
            return ttsDurationMs + 3_000L  // 3 s extra after TTS finishes
        }
    }

    private var tts: TextToSpeech? = null

    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra(NOTIFICATION_ID_KEY, 0)
        val medicineName   = intent.getStringExtra(MEDICINE_NAME_KEY) ?: "Medicine"
        val dosage         = intent.getStringExtra(DOSAGE_KEY) ?: ""
        val instructions   = intent.getStringExtra(INSTRUCTIONS_KEY) ?: ""
        val reminderId     = intent.getStringExtra(REMINDER_ID_KEY) ?: ""
        val userId         = intent.getStringExtra(USER_ID_KEY) ?: ""
        val scheduledTime  = intent.getLongExtra(SCHEDULED_TIME_KEY, System.currentTimeMillis())
        val retryCount     = intent.getIntExtra(RETRY_COUNT_KEY, 0)
        val isFinalWarning = retryCount >= MAX_RETRIES

        android.util.Log.d(
            "MediMate-Alarm",
            "🔔 ALARM FIRED! ID=$notificationId, Medicine=$medicineName, " +
                "Retry=$retryCount, IsFinal=$isFinalWarning, userId=$userId"
        )

        // Notify Flutter that alarm fired (for pending count refresh)
        MainActivity.sendAlarmFired(notificationId)

        // Acquire a partial wakelock so TTS can finish even if screen is off
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MediMate::AlarmWakeLock"
        )
        wakeLock.acquire(30_000L) // 30 seconds max

        try {
            createNotificationChannel(context)
            showNotification(
                context, notificationId, medicineName, dosage, instructions,
                reminderId, userId, scheduledTime, retryCount, isFinalWarning
            )
            speakReminder(context, medicineName, dosage, instructions, isFinalWarning)
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Notification Channel
    // ─────────────────────────────────────────────────────────────────────

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Medicine Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Time-sensitive medicine reminders"
                enableLights(true)
                enableVibration(true)
                setBypassDnd(true)
            }
            context.getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Build & Show Notification with ✅ / ❌ Action Buttons
    // ─────────────────────────────────────────────────────────────────────

    private fun showNotification(
        context: Context,
        notificationId: Int,
        medicineName: String,
        dosage: String,
        instructions: String,
        reminderId: String,
        userId: String,
        scheduledTime: Long,
        retryCount: Int,
        isFinalWarning: Boolean
    ) {
        // ── Main tap: open the app ────────────────────────────────────────
        val mainIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("action", "open_reminder")
            putExtra(REMINDER_ID_KEY, reminderId)
        }
        val mainPendingIntent = PendingIntent.getActivity(
            context, notificationId, mainIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ── Helper: build an intent for NotificationActionReceiver ────────
        fun actionIntent(action: String) =
            Intent(context, NotificationActionReceiver::class.java).apply {
                this.action = action
                putExtra(NOTIFICATION_ID_KEY, notificationId)
                putExtra(MEDICINE_NAME_KEY,   medicineName)
                putExtra(DOSAGE_KEY,          dosage)
                putExtra(INSTRUCTIONS_KEY,    instructions)
                putExtra(REMINDER_ID_KEY,     reminderId)
                putExtra(USER_ID_KEY,         userId)           // FIX 2
                putExtra(SCHEDULED_TIME_KEY,  scheduledTime)
                putExtra(RETRY_COUNT_KEY,     retryCount)
            }

        // ── ✅ TAKEN button ──────────────────────────────────────────────
        val takenPendingIntent = PendingIntent.getBroadcast(
            context, notificationId * 10 + 1,
            actionIntent(NotificationActionReceiver.ACTION_TAKEN),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ── ❌ MISSED button ─────────────────────────────────────────────
        val missedPendingIntent = PendingIntent.getBroadcast(
            context, notificationId * 10 + 2,
            actionIntent(NotificationActionReceiver.ACTION_MISSED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ── Delete / auto-dismiss intent ─────────────────────────────────
        val deletePendingIntent = PendingIntent.getBroadcast(
            context, notificationId * 10 + 3,
            actionIntent(NotificationActionReceiver.ACTION_DISMISSED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ── Notification body ────────────────────────────────────────────
        val title = if (isFinalWarning) "🚨 FINAL REMINDER – Take Now!" else "💊 Medicine Reminder"
        val bodyBuilder = StringBuilder()
        bodyBuilder.append("$medicineName – $dosage")
        if (instructions.isNotEmpty()) bodyBuilder.append("\n$instructions")
        if (retryCount in 1 until MAX_RETRIES) {
            bodyBuilder.append("\n⚠️ Reminder $retryCount of $MAX_RETRIES")
        }
        if (isFinalWarning) {
            bodyBuilder.append("\n🚨 This is your LAST reminder. Please take it now!")
        }
        val body = bodyBuilder.toString()

        // FIX 1: estimate how long the TTS message takes, then auto-dismiss
        // after (TTS duration + 3 s) so the user doesn't have to swipe.
        val speechMessage = buildSpeechMessage(medicineName, dosage, instructions, isFinalWarning)
        val autoTimeoutMs = estimateAutoTimeoutMs(speechMessage)
        android.util.Log.d(
            "MediMate-Alarm",
            "⏱️ Auto-dismiss timeout: ${autoTimeoutMs}ms (TTS ~${autoTimeoutMs - 3000}ms + 3s)"
        )

        // ── Assemble notification ─────────────────────────────────────────
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText("$medicineName – $dosage")
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 1000, 500, 1000))
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
            .setContentIntent(mainPendingIntent)
            .setFullScreenIntent(mainPendingIntent, true)
            .setDeleteIntent(deletePendingIntent)
            // FIX 1: auto-dismiss after TTS + 3 s; triggers deleteIntent → ACTION_DISMISSED
            .setTimeoutAfter(autoTimeoutMs)
            // ✅ Green Tick – Taken
            .addAction(
                android.R.drawable.checkbox_on_background,
                "✅ Taken",
                takenPendingIntent
            )
            // ❌ Red Cross – Missed
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "❌ Missed",
                missedPendingIntent
            )
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
        android.util.Log.d(
            "MediMate-Alarm",
            "✅ Notification shown with ✅/❌ buttons: ID $notificationId, timeout=${autoTimeoutMs}ms"
        )
    }

    // ─────────────────────────────────────────────────────────────────────
    // Text-to-Speech
    // ─────────────────────────────────────────────────────────────────────

    private fun speakReminder(
        context: Context,
        medicineName: String,
        dosage: String,
        instructions: String,
        isFinalWarning: Boolean
    ) {
        android.util.Log.d("MediMate-Alarm", "🔊 Initializing TTS...")
        tts = TextToSpeech(context) { status ->
            if (status != TextToSpeech.SUCCESS) {
                android.util.Log.e("MediMate-Alarm", "❌ TTS initialization failed")
                return@TextToSpeech
            }
            val langResult = tts?.setLanguage(Locale.US)
            if (langResult == TextToSpeech.LANG_MISSING_DATA ||
                langResult == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                android.util.Log.e("MediMate-Alarm", "❌ TTS language not supported")
                return@TextToSpeech
            }
            tts?.setSpeechRate(0.9f)
            tts?.setPitch(1.0f)
            val message = buildSpeechMessage(medicineName, dosage, instructions, isFinalWarning)
            android.util.Log.d("MediMate-Alarm", "🔊 Speaking: $message")
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    android.util.Log.d("MediMate-Alarm", "🔊 TTS started")
                }
                override fun onDone(utteranceId: String?) {
                    android.util.Log.d("MediMate-Alarm", "✅ TTS finished")
                    tts?.stop()
                    tts?.shutdown()
                    tts = null
                }
                override fun onError(utteranceId: String?) {
                    android.util.Log.e("MediMate-Alarm", "❌ TTS error")
                    tts?.shutdown()
                    tts = null
                }
            })
            val utteranceId = "reminder_${System.currentTimeMillis()}"
            val params = Bundle().apply {
                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            }
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        }
    }

    private fun buildSpeechMessage(
        medicineName: String,
        dosage: String,
        instructions: String,
        isFinalWarning: Boolean
    ): String = buildString {
        if (isFinalWarning) {
            append("Attention! This is your last and final reminder. ")
            append("You must take your medicine immediately. ")
        } else {
            append("Time to take your medicine. ")
        }
        append("$medicineName, ")
        append("${convertDosageToSpeech(dosage)}. ")
        if (instructions.isNotEmpty()) append("$instructions. ")
        if (isFinalWarning) {
            append("This is the last reminder. Please take your medicine right now before it is too late.")
        } else {
            append("Please take your medicine now.")
        }
    }

    private fun convertDosageToSpeech(dosage: String): String =
        dosage
            .replace("mg",  " milligrams", ignoreCase = true)
            .replace("ml",  " milliliters", ignoreCase = true)
            .replace("mcg", " micrograms",  ignoreCase = true)
            .replace("g",   " grams",       ignoreCase = true)
            .trim()
}