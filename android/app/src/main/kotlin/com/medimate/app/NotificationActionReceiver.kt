package com.medimate.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Handles action button taps from MediMate medicine reminder notifications.
 *
 * Actions handled:
 * ACTION_TAKEN      – user tapped the green ✅ Taken button
 * ACTION_MISSED     – user tapped the red ❌ Missed button
 * ACTION_DISMISSED  – user swiped the notification away without acting
 *
 * For TAKEN → records dose as taken, notifies Flutter via EventChannel.
 * For MISSED → records dose as missed, schedules up to 5 retry alarms
 *   (each +3 minutes from the previous trigger time), notifies Flutter.
 * For DISMISSED (no action chosen) → records dose as no_action (distinct
 *   from missed), then follows the SAME retry chain as MISSED (+3 min × 5).
 * The 5th retry notification uses a "Final Warning" TTS message.
 */
class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TAKEN     = "com.medimate.app.ACTION_TAKEN"
        const val ACTION_MISSED    = "com.medimate.app.ACTION_MISSED"
        const val ACTION_DISMISSED = "com.medimate.app.ACTION_DISMISSED"

        /** Maximum number of retry reminders after a missed/no-action dose */
        const val MAX_RETRIES = 5

        /** Minutes between each retry alarm */
        const val RETRY_INTERVAL_MINUTES = 3L

        /** SharedPreferences file name for pending dose actions */
        private const val PREFS_NAME = "medimate_dose_actions"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action         = intent.action ?: return
        val notificationId = intent.getIntExtra(AlarmReceiver.NOTIFICATION_ID_KEY, 0)
        val medicineName   = intent.getStringExtra(AlarmReceiver.MEDICINE_NAME_KEY) ?: "Medicine"
        val dosage         = intent.getStringExtra(AlarmReceiver.DOSAGE_KEY) ?: ""
        val instructions   = intent.getStringExtra(AlarmReceiver.INSTRUCTIONS_KEY) ?: ""
        val reminderId     = intent.getStringExtra(AlarmReceiver.REMINDER_ID_KEY) ?: ""
        val scheduledTime  = intent.getLongExtra(
            AlarmReceiver.SCHEDULED_TIME_KEY, System.currentTimeMillis()
        )
        val retryCount = intent.getIntExtra(AlarmReceiver.RETRY_COUNT_KEY, 0)

        Log.d("MediMate-Action",
            "📩 Action received: $action | $medicineName | retry=$retryCount")

        // Cancel the original notification immediately
        NotificationManagerCompat.from(context).cancel(notificationId)

        when (action) {
            ACTION_TAKEN -> handleTaken(
                context, notificationId, medicineName, dosage, reminderId, scheduledTime
            )
            ACTION_MISSED -> handleMissed(
                context, notificationId, medicineName, dosage, instructions,
                reminderId, scheduledTime, retryCount, isNoAction = false
            )
            ACTION_DISMISSED -> handleMissed(
                context, notificationId, medicineName, dosage, instructions,
                reminderId, scheduledTime, retryCount, isNoAction = true
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TAKEN
    // ─────────────────────────────────────────────────────────────────────────
    private fun handleTaken(
        context: Context,
        notificationId: Int,
        medicineName: String,
        dosage: String,
        reminderId: String,
        scheduledTime: Long
    ) {
        Log.d("MediMate-Action", "✅ Dose TAKEN: $medicineName (reminderId=$reminderId)")

        // 1. Notify Flutter via EventChannel (if app is active)
        MainActivity.sendDoseAction(
            event          = "dose_taken",
            notificationId = notificationId,
            medicineName   = medicineName,
            dosage         = dosage,
            reminderId     = reminderId,
            scheduledTime  = scheduledTime,
            retryCount     = 0
        )

        // 2. Persist for when app is not running
        savePendingAction(
            context        = context,
            notificationId = notificationId,
            actionType     = "taken",
            reminderId     = reminderId,
            medicineName   = medicineName,
            dosage         = dosage,
            scheduledTime  = scheduledTime,
            retryCount     = 0
        )

        // 3. Brief confirmation notification
        showConfirmation(
            context        = context,
            message        = "✅ $medicineName marked as Taken. Well done!",
            notificationId = notificationId + 50_000
        )

        Log.d("MediMate-Action", "✅ Taken flow complete")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MISSED / NO-ACTION (DISMISSED without choosing)
    // ─────────────────────────────────────────────────────────────────────────
    /**
     * Handles both ❌ Missed button taps and notification swipe-dismissals.
     *
     * @param isNoAction  true  → user did nothing (swipe-dismissed)
     *                    false → user explicitly tapped ❌ Missed
     *
     * Both paths schedule the same retry chain (+3 min × MAX_RETRIES).
     * The Flutter event differs:
     *   - isNoAction=true  → "dose_no_action"
     *   - isNoAction=false → "dose_missed"
     */
    private fun handleMissed(
        context: Context,
        notificationId: Int,
        medicineName: String,
        dosage: String,
        instructions: String,
        reminderId: String,
        scheduledTime: Long,
        retryCount: Int,
        isNoAction: Boolean
    ) {
        val logTag  = if (isNoAction) "🔕 NO-ACTION" else "❌ MISSED"
        val event   = if (isNoAction) "dose_no_action" else "dose_missed"
        val action  = if (isNoAction) "no_action" else "missed"

        Log.d("MediMate-Action", "$logTag: $medicineName (retry=$retryCount)")

        // 1. Notify Flutter via EventChannel (if app is active)
        MainActivity.sendDoseAction(
            event          = event,
            notificationId = notificationId,
            medicineName   = medicineName,
            dosage         = dosage,
            reminderId     = reminderId,
            scheduledTime  = scheduledTime,
            retryCount     = retryCount
        )

        // 2. Persist for when app is not running
        savePendingAction(
            context        = context,
            notificationId = notificationId,
            actionType     = action,
            reminderId     = reminderId,
            medicineName   = medicineName,
            dosage         = dosage,
            scheduledTime  = scheduledTime,
            retryCount     = retryCount
        )

        // 3. Schedule retry alarm (up to MAX_RETRIES times)
        if (retryCount < MAX_RETRIES) {
            val nextRetry = retryCount + 1

            // Each retry fires RETRY_INTERVAL_MINUTES after the PREVIOUS trigger,
            // i.e. nextRetry * RETRY_INTERVAL_MINUTES after the ORIGINAL scheduled time.
            val nextTriggerTime = scheduledTime +
                    (nextRetry * RETRY_INTERVAL_MINUTES * 60_000L)

            // Use an offset ID so retries don't clash with the original notification ID
            val retryId = notificationId + (nextRetry * 1_000)

            Log.d("MediMate-Action",
                "⏰ Scheduling retry $nextRetry of $MAX_RETRIES at " +
                "${java.util.Date(nextTriggerTime)}, ID=$retryId")

            AlarmManagerHelper.scheduleExactAlarm(
                context           = context,
                notificationId    = retryId,
                medicineName      = medicineName,
                dosage            = dosage,
                instructions      = instructions,
                triggerTimeMillis = nextTriggerTime,
                reminderId        = reminderId,
                // Keep original scheduled time so history records the right slot
                scheduledTimeMillis = scheduledTime,
                retryCount        = nextRetry
            )

            val minutesUntilRetry = nextRetry * RETRY_INTERVAL_MINUTES
            val actionLabel = if (isNoAction) "No action detected" else "Missed"
            showConfirmation(
                context        = context,
                message        = "⏰ $actionLabel – will remind again in " +
                        "$minutesUntilRetry min ($nextRetry of $MAX_RETRIES)",
                notificationId = notificationId + 50_000
            )

        } else {
            // All 5 retries exhausted – mark as permanently missed/no-action
            showConfirmation(
                context        = context,
                message        = "📋 $medicineName was not taken. Please consult your doctor if needed.",
                notificationId = notificationId + 50_000
            )
            Log.d("MediMate-Action",
                "📋 Max retries ($MAX_RETRIES) reached for $medicineName")
        }

        Log.d("MediMate-Action", "$logTag flow complete")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────
    /**
     * Stores the dose action in SharedPreferences so it can be processed
     * when the Flutter app opens (via MainActivity.processPendingDoseActions).
     *
     * Format: "actionType|reminderId|medicineName|dosage|scheduledTime|retryCount"
     * actionType: "taken" | "missed" | "no_action"
     */
    private fun savePendingAction(
        context: Context,
        notificationId: Int,
        actionType: String,
        reminderId: String,
        medicineName: String,
        dosage: String,
        scheduledTime: Long,
        retryCount: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        // Use notificationId + timestamp as key so multiple actions don't overwrite each other
        val key   = "pending_action_${notificationId}_${System.currentTimeMillis()}"
        val value = "$actionType|$reminderId|$medicineName|$dosage|$scheduledTime|$retryCount"
        prefs.edit().putString(key, value).apply()
        Log.d("MediMate-Action", "💾 Saved pending action: $key = $value")
    }

    /**
     * Show a small status-bar notification to confirm the action to the user.
     */
    private fun showConfirmation(
        context: Context,
        message: String,
        notificationId: Int
    ) {
        try {
            val notification = NotificationCompat.Builder(context, AlarmReceiver.CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("MediMate")
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: Exception) {
            Log.e("MediMate-Action", "Error showing confirmation notification: $e")
        }
    }
}