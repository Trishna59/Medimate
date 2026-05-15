// android/app/src/main/kotlin/com/medimate/app/MainActivity.kt
package com.medimate.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ONLY CHANGE vs original:
//   processPendingDoseActions() — the line that maps actionType to an event
//   string was:
//       val event = if (actionType == "taken") "dose_taken" else "dose_missed"
//   This silently mapped "no_action" to "dose_missed", losing the distinction.
//   It is now:
//       val event = when (actionType) {
//           "taken"     -> "dose_taken"
//           "no_action" -> "dose_no_action"   ← new
//           else        -> "dose_missed"
//       }
//   ALL other code is IDENTICAL to the original codebase.

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.medimate.app/native_alarm"
    private val EVENT_CHANNEL  = "com.medimate.app/alarm_events"

    companion object {
        /** Holds the EventChannel sink; may be null when Flutter is not listening */
        @Volatile
        var alarmEventSink: EventChannel.EventSink? = null

        // ── Existing: alarm fired ─────────────────────────────────────────
        fun sendAlarmFired(id: Int) {
            android.util.Log.d("MediMate-MainActivity", "📤 Sending alarm_fired: ID $id")
            alarmEventSink?.success(
                mapOf("event" to "alarm_fired", "id" to id)
            )
        }

        // ── NEW: dose action (taken / missed / no_action) from notification ─
        /**
         * Called by [NotificationActionReceiver] to forward a dose action to
         * Flutter via the shared EventChannel sink.
         *
         * If Flutter is not listening (app in background), the data is also
         * stored in SharedPreferences by [NotificationActionReceiver] and
         * replayed in [onResume] / [onListen].
         */
        fun sendDoseAction(
            event: String,
            notificationId: Int,
            medicineName: String,
            dosage: String,
            reminderId: String,
            scheduledTime: Long,
            retryCount: Int
        ) {
            android.util.Log.d(
                "MediMate-MainActivity",
                "📤 Sending dose action: $event | $medicineName | reminderId=$reminderId"
            )
            alarmEventSink?.success(
                mapOf(
                    "event"          to event,
                    "notificationId" to notificationId,
                    "medicineName"   to medicineName,
                    "dosage"         to dosage,
                    "reminderId"     to reminderId,
                    "scheduledTime"  to scheduledTime,
                    "retryCount"     to retryCount
                )
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Flutter engine setup
    // ─────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel: schedule / cancel native alarms ────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleAlarm" -> {
                        val id                  = call.argument<Int>("id") ?: 0
                        val medicineName        = call.argument<String>("medicineName") ?: ""
                        val dosage              = call.argument<String>("dosage") ?: ""
                        val instructions        = call.argument<String>("instructions") ?: ""
                        val triggerTimeMillis   = call.argument<Long>("triggerTimeMillis") ?: 0L
                        val reminderId          = call.argument<String>("reminderId") ?: ""
                        val scheduledTimeMillis =
                            call.argument<Long>("scheduledTimeMillis") ?: triggerTimeMillis
                        AlarmManagerHelper.scheduleExactAlarm(
                            context             = context,
                            notificationId      = id,
                            medicineName        = medicineName,
                            dosage              = dosage,
                            instructions        = instructions,
                            triggerTimeMillis   = triggerTimeMillis,
                            reminderId          = reminderId,
                            scheduledTimeMillis = scheduledTimeMillis,
                            retryCount          = 0
                        )
                        result.success(true)
                    }
                    "cancelAlarm" -> {
                        val id = call.argument<Int>("id") ?: 0
                        AlarmManagerHelper.cancelAlarm(context, id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── EventChannel: send alarm/action events to Flutter ─────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    android.util.Log.d("MediMate-MainActivity", "📡 EventChannel listener attached")
                    alarmEventSink = events
                    // Replay any actions that happened while Flutter wasn't listening
                    processPendingDoseActions(events)
                }

                override fun onCancel(arguments: Any?) {
                    android.util.Log.d("MediMate-MainActivity", "📡 EventChannel listener detached")
                    alarmEventSink = null
                }
            })
    }

    // ─────────────────────────────────────────────────────────────────────
    // Activity lifecycle – handle intents
    // ─────────────────────────────────────────────────────────────────────

    /** Called when the app is already running and a new intent arrives */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDoseIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // Process any dose actions stored while Flutter wasn't listening
        processPendingDoseActions(alarmEventSink)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Read dose action extras from an Intent and forward to Flutter.
     * Used when a notification action launches / re-focuses the app.
     */
    private fun handleDoseIntent(intent: Intent?) {
        intent ?: return
        val doseAction = intent.getStringExtra("dose_action") ?: return
        val notificationId = intent.getIntExtra(AlarmReceiver.NOTIFICATION_ID_KEY, 0)
        val medicineName   =
            intent.getStringExtra(AlarmReceiver.MEDICINE_NAME_KEY) ?: return
        val dosage        = intent.getStringExtra(AlarmReceiver.DOSAGE_KEY) ?: ""
        val reminderId    = intent.getStringExtra(AlarmReceiver.REMINDER_ID_KEY) ?: ""
        val scheduledTime = intent.getLongExtra(
            AlarmReceiver.SCHEDULED_TIME_KEY, System.currentTimeMillis()
        )
        val retryCount = intent.getIntExtra(AlarmReceiver.RETRY_COUNT_KEY, 0)
        sendDoseAction(
            doseAction, notificationId, medicineName, dosage,
            reminderId, scheduledTime, retryCount
        )
    }

    /**
     * Read pending dose actions from SharedPreferences (stored by
     * [NotificationActionReceiver] while Flutter was not running) and
     * forward each one to Flutter, then clear them.
     *
     * FIX: The original code used:
     *   val event = if (actionType == "taken") "dose_taken" else "dose_missed"
     * which incorrectly mapped "no_action" → "dose_missed", losing the
     * distinction between the user pressing ❌ vs doing nothing at all.
     *
     * Now "no_action" is correctly replayed as "dose_no_action" so Flutter
     * and Firestore can record it (still as a missed dose, but with a
     * distinguishing note).
     */
    private fun processPendingDoseActions(sink: EventChannel.EventSink?) {
        sink ?: return
        val prefs   = getSharedPreferences("medimate_dose_actions", MODE_PRIVATE)
        val allKeys = prefs.all.keys.filter { it.startsWith("pending_action_") }
        if (allKeys.isEmpty()) return

        val editor = prefs.edit()
        for (key in allKeys) {
            val value = prefs.getString(key, null) ?: continue
            try {
                // Format: "actionType|reminderId|medicineName|dosage|scheduledTime|retryCount"
                // actionType: "taken" | "missed" | "no_action"
                val parts = value.split("|")
                if (parts.size >= 6) {
                    val actionType    = parts[0]
                    val reminderId    = parts[1]
                    val medicineName  = parts[2]
                    val dosage        = parts[3]
                    val scheduledTime = parts[4].toLongOrNull() ?: System.currentTimeMillis()
                    val retryCount    = parts[5].toIntOrNull() ?: 0
                    val notificationId = key
                        .removePrefix("pending_action_")
                        .substringBefore("_") // remove the timestamp suffix
                        .toIntOrNull() ?: 0

                    // ── FIX: correctly map all three action types ──────────
                    // Original was: if (actionType == "taken") "dose_taken" else "dose_missed"
                    // which wrongly mapped "no_action" to "dose_missed".
                    val event = when (actionType) {
                        "taken"     -> "dose_taken"
                        "no_action" -> "dose_no_action"  // ← was incorrectly "dose_missed"
                        else        -> "dose_missed"      // covers "missed" and any unknown value
                    }

                    android.util.Log.d(
                        "MediMate-MainActivity",
                        "📤 Replaying pending action: $event for $medicineName"
                    )
                    sink.success(
                        mapOf(
                            "event"          to event,
                            "notificationId" to notificationId,
                            "medicineName"   to medicineName,
                            "dosage"         to dosage,
                            "reminderId"     to reminderId,
                            "scheduledTime"  to scheduledTime,
                            "retryCount"     to retryCount
                        )
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e(
                    "MediMate-MainActivity",
                    "Error replaying pending action '$key': $e"
                )
            }
            editor.remove(key)
        }
        editor.apply()
        android.util.Log.d(
            "MediMate-MainActivity",
            "✅ Pending dose actions processed (${allKeys.size} items)"
        )
    }
}