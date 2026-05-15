// lib/features/reminders/data/repositories/reminder_repository_impl.dart
// ============================================================
// UPDATED: Wires NotificationService.onDoseAction so that
//
// ✅ TAKEN      → records dose as taken in Firestore immediately
// ❌ MISSED     → records dose as missed in Firestore immediately
// 🔕 NO-ACTION  → records dose as missed in Firestore immediately (NEW FIX)
//
// and the retry chain (+3 min × 5) is driven by
// NotificationActionReceiver on the native side.
//
// ONLY CHANGE vs original:
//   _handleNotificationDoseAction() has a new 'dose_no_action' else-if
//   branch. Without it, the event arrived here but was silently ignored,
//   so nothing was ever written to Firestore for dismissed notifications.
//   ALL other code is IDENTICAL to the original codebase.
// ============================================================
// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/entities/dose_log.dart';
import '../models/reminder_model.dart';
import '../models/dose_log_model.dart';
import '../../../../core/utils/notification_service.dart';

class ReminderRepository {
  final FirebaseFirestore _firestore;
  final NotificationService _notificationService;

  ReminderRepository({
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationService = notificationService ?? NotificationService() {
    // ── Wire the dose-action callback so Firestore is updated
    // whenever the user taps ✅ Taken or ❌ Missed on a notification,
    // or dismisses it without acting (dose_no_action).
    _notificationService.onDoseAction = _handleNotificationDoseAction;
  }

  // =========================================================
  // NOTIFICATION DOSE-ACTION HANDLER
  // =========================================================

  /// Called by [NotificationService] when the user taps ✅ Taken
  /// or ❌ Missed on a notification card, OR when the app resumes
  /// and replays pending actions stored in SharedPreferences,
  /// OR when the notification is dismissed without action (dose_no_action).
  Future<void> _handleNotificationDoseAction({
    required String event, // 'dose_taken' | 'dose_missed' | 'dose_no_action'
    required int notificationId,
    required String reminderId,
    required String medicineName,
    required String dosage,
    required DateTime scheduledTime,
    required int retryCount,
  }) async {
    print('📩 ReminderRepository handling: $event | $medicineName '
        '| reminderId=$reminderId | retry=$retryCount');

    // We need the userId – fetch it from the reminder document itself.
    final userId = await _getUserIdForReminder(reminderId);
    if (userId == null) {
      print('⚠️ Cannot find userId for reminderId=$reminderId – skipping.');
      return;
    }

    if (event == 'dose_taken') {
      // ── TAKEN: record immediately; native side already cancelled retries.
      await _recordDoseIfNotExists(
        userId: userId,
        reminderId: reminderId,
        medicineName: medicineName,
        scheduledTime: scheduledTime,
        status: DoseStatus.taken,
      );
      print('✅ Dose TAKEN recorded for $medicineName');
    } else if (event == 'dose_missed') {
      // ── MISSED: record for this attempt.
      // The native NotificationActionReceiver already schedules the retry alarm.
      await _recordDoseIfNotExists(
        userId: userId,
        reminderId: reminderId,
        medicineName: medicineName,
        scheduledTime: scheduledTime,
        status: DoseStatus.missed,
        notes: retryCount > 0 ? 'Retry $retryCount of 5' : null,
      );
      print('❌ Dose MISSED recorded for $medicineName '
          '(retry $retryCount / 5)');

      // ────────────────────────────────────────────────────────────────────
      // FIX: dose_no_action — notification was dismissed without any tap.
      // Previously this branch did not exist so dose_no_action events were
      // silently ignored and the Dose Tracking page showed nothing for them.
      // We record it as missed (same adherence impact as pressing ❌ Missed).
      // The optional notes field lets you distinguish it in Firestore logs.
      // ────────────────────────────────────────────────────────────────────
    } else if (event == 'dose_no_action') {
      await _recordDoseIfNotExists(
        userId: userId,
        reminderId: reminderId,
        medicineName: medicineName,
        scheduledTime: scheduledTime,
        status: DoseStatus.missed,
        notes: retryCount > 0
            ? 'No action – retry $retryCount of 5'
            : 'No action taken',
      );
      print('🔕 Dose NO-ACTION (→ missed) recorded for $medicineName '
          '(retry $retryCount / 5)');
    }
  }

  /// Write a dose log only if no log already exists for the same
  /// reminderId + scheduledTime window (±30 min). Prevents duplicates
  /// when the app replays pending actions on resume.
  Future<void> _recordDoseIfNotExists({
    required String userId,
    required String reminderId,
    required String medicineName,
    required DateTime scheduledTime,
    required DoseStatus status,
    String? notes,
  }) async {
    try {
      // Check for an existing log within a ±30-minute window.
      final existing = await _firestore
          .collection('doseLogs')
          .doc(userId)
          .collection('logs')
          .where('reminderId', isEqualTo: reminderId)
          .where(
            'scheduledTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
                scheduledTime.subtract(const Duration(minutes: 30))),
          )
          .where(
            'scheduledTime',
            isLessThanOrEqualTo: Timestamp.fromDate(
                scheduledTime.add(const Duration(minutes: 30))),
          )
          .get();

      if (existing.docs.isNotEmpty) {
        // If there is already a "taken" record, never overwrite with "missed".
        final alreadyTaken = existing.docs.any(
          (d) => (d.data()['status'] as String?) == 'taken',
        );
        if (alreadyTaken) {
          print('ℹ️ Dose already marked as TAKEN – skipping $status write.');
          return;
        }
        // Otherwise allow overwrite (e.g. replace pending → missed).
      }

      await recordDoseLog(
        userId: userId,
        reminderId: reminderId,
        medicineName: medicineName,
        scheduledTime: scheduledTime,
        status: status,
        notes: notes,
      );
    } catch (e) {
      print('❌ _recordDoseIfNotExists error: $e');
    }
  }

  /// Look up the userId for a reminder by querying Firestore.
  /// Returns null if the reminder cannot be found.
  Future<String?> _getUserIdForReminder(String reminderId) async {
    try {
      // Reminders are stored under reminders/{userId}/userReminders/{reminderId}.
      final snap = await _firestore
          .collectionGroup('userReminders')
          .where(FieldPath.documentId, isEqualTo: reminderId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      // The parent of userReminders is the userId doc.
      return snap.docs.first.reference.parent.parent?.id;
    } catch (e) {
      print('❌ _getUserIdForReminder error: $e');
      return null;
    }
  }

  // =========================================================
  // PUBLIC CRUD METHODS
  // =========================================================

  /// Create a new reminder
  Future<Reminder> createReminder({
    required String userId,
    required String medicineName,
    required String dosage,
    String? instructions,
    required List<String> reminderTimes,
    required ReminderFrequency frequency,
    List<int>? weekdays,
    String? scanId,
  }) async {
    print('📝 Creating reminder for $medicineName');
    try {
      final reminderId = const Uuid().v4();
      final nextReminder = _calculateNextReminderTime(
        reminderTimes,
        frequency,
        weekdays,
      );
      final reminder = ReminderModel(
        id: reminderId,
        userId: userId,
        medicineName: medicineName,
        dosage: dosage,
        instructions: instructions,
        reminderTimes: reminderTimes,
        frequency: frequency,
        weekdays: weekdays,
        isActive: true,
        createdAt: DateTime.now(),
        nextReminderAt: nextReminder,
        scanId: scanId,
      );
      await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .doc(reminderId)
          .set(reminder.toFirestore());
      print('✅ Reminder saved to Firestore');
      await _scheduleNotificationsForReminder(reminder);
      final pending = await _notificationService.getPendingNotifications();
      print('✅ Total pending notifications: ${pending.length}');
      return reminder;
    } catch (e) {
      print('❌ Error creating reminder: $e');
      rethrow;
    }
  }

  /// Update a reminder
  Future<void> updateReminder({
    required String userId,
    required Reminder reminder,
  }) async {
    try {
      print('📝 Updating reminder: ${reminder.medicineName}');
      // STEP 1: Cancel ALL old notifications
      await _cancelAllNotificationsForReminder(reminder);
      print('✅ Old notifications canceled');
      // STEP 2: Convert domain entity to data model
      final reminderModel = ReminderModel.fromEntity(reminder);
      // STEP 3: Recalculate next reminder time
      final nextTime = _calculateNextReminderTime(
        reminder.reminderTimes,
        reminder.frequency,
        reminder.weekdays,
      );
      final updatedModel = reminderModel.copyWith(nextReminderAt: nextTime);
      // STEP 4: Update in Firestore
      await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .doc(reminder.id)
          .update(updatedModel.toFirestore());
      print('✅ Reminder updated in Firestore with next time: $nextTime');
      // STEP 5: Reschedule notifications if active
      if (reminder.isActive) {
        await _scheduleNotificationsForReminder(updatedModel);
        print('✅ New notifications scheduled');
        final pending = await _notificationService.getPendingNotifications();
        print('✅ Total pending: ${pending.length}');
      }
    } catch (e) {
      print('❌ Error updating reminder: $e');
      rethrow;
    }
  }

  /// Get all reminders for a user (real-time stream)
  Stream<List<Reminder>> getUserReminders(String userId) {
    return _firestore
        .collection('reminders')
        .doc(userId)
        .collection('userReminders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ReminderModel.fromFirestore(doc)).toList());
  }

  /// Get a single reminder
  Future<Reminder?> getReminder({
    required String userId,
    required String reminderId,
  }) async {
    try {
      final doc = await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .doc(reminderId)
          .get();
      if (doc.exists) return ReminderModel.fromFirestore(doc);
      return null;
    } catch (e) {
      print('❌ Error getting reminder: $e');
      return null;
    }
  }

  /// Toggle reminder active status
  Future<void> toggleReminderStatus({
    required String userId,
    required String reminderId,
    required bool isActive,
  }) async {
    try {
      await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .doc(reminderId)
          .update({'isActive': isActive});
      final reminder =
          await getReminder(userId: userId, reminderId: reminderId);
      if (reminder != null) {
        final reminderModel = ReminderModel.fromEntity(reminder);
        if (!isActive) {
          await _cancelAllNotificationsForReminder(reminderModel);
          print('✅ Reminder deactivated – notifications canceled');
        } else {
          await _scheduleNotificationsForReminder(reminderModel);
          print('✅ Reminder activated – notifications scheduled');
        }
      }
    } catch (e) {
      print('❌ Error toggling reminder: $e');
      rethrow;
    }
  }

  /// Delete a reminder
  Future<void> deleteReminder({
    required String userId,
    required String reminderId,
  }) async {
    try {
      print('🗑️ Deleting reminder: $reminderId');
      final reminder =
          await getReminder(userId: userId, reminderId: reminderId);
      if (reminder != null) {
        await _cancelAllNotificationsForReminder(reminder);
        print('✅ Notifications canceled');
      }
      await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .doc(reminderId)
          .delete();
      print('✅ Reminder deleted');
    } catch (e) {
      print('❌ Error deleting reminder: $e');
      rethrow;
    }
  }

  // =========================================================
  // DOSE LOG METHODS
  // =========================================================

  /// Record a dose log entry in Firestore.
  Future<void> recordDoseLog({
    required String userId,
    required String reminderId,
    required String medicineName,
    required DateTime scheduledTime,
    required DoseStatus status,
    String? notes,
  }) async {
    try {
      final logId = const Uuid().v4();
      final doseLog = DoseLogModel(
        id: logId,
        userId: userId,
        reminderId: reminderId,
        medicineName: medicineName,
        scheduledTime: scheduledTime,
        takenAt: status == DoseStatus.taken ? DateTime.now() : null,
        status: status,
        notes: notes,
      );
      await _firestore
          .collection('doseLogs')
          .doc(userId)
          .collection('logs')
          .doc(logId)
          .set(doseLog.toFirestore());
      print('✅ Dose log recorded: $status');
    } catch (e) {
      print('❌ Error recording dose log: $e');
      rethrow;
    }
  }

  /// Get dose logs for a specific reminder (real-time stream).
  Stream<List<DoseLog>> getDoseLogsForReminder({
    required String userId,
    required String reminderId,
  }) {
    return _firestore
        .collection('doseLogs')
        .doc(userId)
        .collection('logs')
        .where('reminderId', isEqualTo: reminderId)
        .orderBy('scheduledTime', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DoseLogModel.fromFirestore(doc)).toList());
  }

  /// Get recent dose logs (last 7 days).
  Stream<List<DoseLog>> getRecentDoseLogs(String userId) {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    return _firestore
        .collection('doseLogs')
        .doc(userId)
        .collection('logs')
        .where('scheduledTime',
            isGreaterThan: Timestamp.fromDate(sevenDaysAgo))
        .orderBy('scheduledTime', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DoseLogModel.fromFirestore(doc)).toList());
  }

  /// Calculate adherence rate for the last 7 days (0–100).
  Future<double> calculateAdherenceRate(String userId) async {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final logs = await _firestore
          .collection('doseLogs')
          .doc(userId)
          .collection('logs')
          .where('scheduledTime',
              isGreaterThan: Timestamp.fromDate(sevenDaysAgo))
          .get();
      if (logs.docs.isEmpty) return 0.0;
      final takenCount = logs.docs
          .where((doc) => (doc.data()['status'] as String?) == 'taken')
          .length;
      return (takenCount / logs.docs.length) * 100;
    } catch (e) {
      print('❌ Error calculating adherence: $e');
      return 0.0;
    }
  }

  // =========================================================
  // NEXT-REMINDER-TIME MANAGEMENT
  // =========================================================

  /// Called after an alarm fires to:
  /// 1. Auto-mark the dose as missed if the user hasn't logged it yet.
  /// 2. Advance nextReminderAt to the next scheduled slot.
  Future<void> updateNextReminderTime({
    required String userId,
    required String reminderId,
  }) async {
    try {
      print('📅 Updating next reminder time for: $reminderId');
      final reminder =
          await getReminder(userId: userId, reminderId: reminderId);
      if (reminder == null) {
        print('⚠️ Reminder not found');
        return;
      }
      final scheduledTime = reminder.nextReminderAt;
      if (scheduledTime != null) {
        // Check if user already logged this dose
        final recentLogs = await _firestore
            .collection('doseLogs')
            .doc(userId)
            .collection('logs')
            .where('reminderId', isEqualTo: reminderId)
            .where(
              'scheduledTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                  scheduledTime.subtract(const Duration(minutes: 30))),
            )
            .where(
              'scheduledTime',
              isLessThanOrEqualTo: Timestamp.fromDate(
                  scheduledTime.add(const Duration(minutes: 30))),
            )
            .get();
        if (recentLogs.docs.isEmpty) {
          print('⚠️ Dose was MISSED – recording automatically');
          await recordDoseLog(
            userId: userId,
            reminderId: reminderId,
            medicineName: reminder.medicineName,
            scheduledTime: scheduledTime,
            status: DoseStatus.missed,
          );
        } else {
          print('✅ Dose already recorded by user');
        }
      }
      // Advance to the next scheduled slot
      final nextTime = _calculateNextReminderTime(
        reminder.reminderTimes,
        reminder.frequency,
        reminder.weekdays,
      );
      if (nextTime == null) {
        print('⚠️ Could not calculate next reminder time');
        return;
      }
      print('  Old next time: ${reminder.nextReminderAt}');
      print('  New next time: $nextTime');
      await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .doc(reminderId)
          .update({'nextReminderAt': Timestamp.fromDate(nextTime)});
      print('✅ Next reminder time updated to: $nextTime');
    } catch (e) {
      print('❌ Error updating next reminder time: $e');
    }
  }

  /// On app start, scan active reminders whose nextReminderAt is >30 min
  /// in the past and automatically log them as missed if not yet recorded.
  Future<void> checkOverdueReminders(String userId) async {
    try {
      print('🔍 Checking for overdue reminders...');
      final now = DateTime.now();
      final snapshot = await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .where('isActive', isEqualTo: true)
          .get();
      int missedCount = 0;
      for (final doc in snapshot.docs) {
        try {
          final reminder = ReminderModel.fromFirestore(doc);
          if (reminder.nextReminderAt != null &&
              reminder.nextReminderAt!
                  .isBefore(now.subtract(const Duration(minutes: 30)))) {
            final logs = await _firestore
                .collection('doseLogs')
                .doc(userId)
                .collection('logs')
                .where('reminderId', isEqualTo: reminder.id)
                .where(
                  'scheduledTime',
                  isEqualTo:
                      Timestamp.fromDate(reminder.nextReminderAt!),
                )
                .get();
            if (logs.docs.isEmpty) {
              await recordDoseLog(
                userId: userId,
                reminderId: reminder.id,
                medicineName: reminder.medicineName,
                scheduledTime: reminder.nextReminderAt!,
                status: DoseStatus.missed,
              );
              missedCount++;
              print(
                  '  📝 Marked ${reminder.medicineName} as missed '
                  '(${reminder.nextReminderAt})');
            }
          }
        } catch (e) {
          print('  ⚠️ Error processing reminder: $e');
        }
      }
      print('✅ Checked overdue reminders: $missedCount missed doses recorded');
    } catch (e) {
      print('❌ Error checking overdue reminders: $e');
    }
  }

  /// Recalculate and update nextReminderAt for all active user reminders.
  Future<void> refreshAllNextReminderTimes(String userId) async {
    try {
      print('🔄 Refreshing next reminder times...');
      final snapshot = await _firestore
          .collection('reminders')
          .doc(userId)
          .collection('userReminders')
          .where('isActive', isEqualTo: true)
          .get();
      int updatedCount = 0;
      for (final doc in snapshot.docs) {
        try {
          final reminder = ReminderModel.fromFirestore(doc);
          final nextTime = _calculateNextReminderTime(
            reminder.reminderTimes,
            reminder.frequency,
            reminder.weekdays,
          );
          if (nextTime != null) {
            await _firestore
                .collection('reminders')
                .doc(userId)
                .collection('userReminders')
                .doc(reminder.id)
                .update({'nextReminderAt': Timestamp.fromDate(nextTime)});
            updatedCount++;
          }
          print('  ✅ Updated ${reminder.medicineName}: $nextTime');
        } catch (e) {
          print('  ⚠️ Error processing reminder: $e');
        }
      }
      print('✅ Refreshed $updatedCount reminder(s)');
    } catch (e) {
      print('❌ Error refreshing next reminder times: $e');
    }
  }

  // =========================================================
  // PRIVATE HELPERS
  // =========================================================

  Future<void> _scheduleNotificationsForReminder(Reminder reminder) async {
    print('🔔 Scheduling notifications for ${reminder.medicineName}');
    try {
      final baseId = _generateStableBaseId(reminder.id);
      print('  Base ID: $baseId');
      if (reminder.frequency == ReminderFrequency.daily) {
        await _notificationService.scheduleDailyReminders(
          baseId: baseId,
          medicineName: reminder.medicineName,
          dosage: reminder.dosage,
          times: reminder.reminderTimes,
          instructions: reminder.instructions,
          reminderId: reminder.id,
        );
      } else if (reminder.frequency == ReminderFrequency.weekly) {
        int notificationIndex = 0;
        for (final timeStr in reminder.reminderTimes) {
          final timeParts = timeStr.split(':');
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          for (final weekday in (reminder.weekdays ?? [])) {
            final now = DateTime.now();
            var scheduledDate = _getNextWeekday(weekday, hour, minute);
            if (scheduledDate.isBefore(now)) {
              scheduledDate = scheduledDate.add(const Duration(days: 7));
            }
            await _notificationService.scheduleReminder(
              id: baseId + notificationIndex,
              medicineName: reminder.medicineName,
              dosage: reminder.dosage,
              scheduledTime: scheduledDate,
              instructions: reminder.instructions,
              reminderId: reminder.id,
            );
            notificationIndex++;
            print(
                '  ✅ Scheduled for ${_getDayName(weekday)} at $timeStr');
          }
        }
      } else {
        for (int i = 0; i < reminder.reminderTimes.length; i++) {
          final timeParts = reminder.reminderTimes[i].split(':');
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          final now = DateTime.now();
          var scheduledDate =
              DateTime(now.year, now.month, now.day, hour, minute);
          if (scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          }
          await _notificationService.scheduleReminder(
            id: baseId + i,
            medicineName: reminder.medicineName,
            dosage: reminder.dosage,
            scheduledTime: scheduledDate,
            instructions: reminder.instructions,
            reminderId: reminder.id,
          );
        }
      }
      print('✅ All notifications scheduled');
    } catch (e) {
      print('❌ Error scheduling notifications: $e');
      rethrow;
    }
  }

  Future<void> _cancelAllNotificationsForReminder(
      Reminder reminder) async {
    try {
      final baseId = _generateStableBaseId(reminder.id);
      print(
          '🗑️ Canceling notifications for ${reminder.medicineName} '
          '(Base ID: $baseId)');
      final List<int> idsToCancel = [];
      for (int i = 0; i < 100; i++) {
        idsToCancel.add(baseId + i);
      }
      await Future.wait(
          idsToCancel.map((id) => _notificationService.cancelReminder(id)));
      print('✅ Canceled ${idsToCancel.length} potential notification IDs');
    } catch (e) {
      print('❌ Error canceling notifications: $e');
    }
  }

  int _generateStableBaseId(String reminderId) {
    final shortId = reminderId.substring(0, 8);
    return shortId.hashCode.abs() % 100000;
  }

  DateTime _getNextWeekday(int weekday, int hour, int minute) {
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    int daysToAdd;
    if (weekday >= currentWeekday) {
      daysToAdd = weekday - currentWeekday;
    } else {
      daysToAdd = 7 - (currentWeekday - weekday);
    }
    final targetDate = now.add(Duration(days: daysToAdd));
    return DateTime(
        targetDate.year, targetDate.month, targetDate.day, hour, minute);
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  /// Find the next upcoming scheduled time from today / tomorrow.
  DateTime? _calculateNextReminderTime(
    List<String> times,
    ReminderFrequency frequency,
    List<int>? weekdays,
  ) {
    if (times.isEmpty) return null;
    final now = DateTime.now();
    print('🕐 Calculating next reminder time...');
    print('   Current time: $now');
    print('   Reminder times: $times');
    final sortedTimes = List<String>.from(times)..sort();
    for (final timeStr in sortedTimes) {
      try {
        final parts = timeStr.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        var scheduledTime =
            DateTime(now.year, now.month, now.day, hour, minute);
        if (scheduledTime.isAfter(now)) {
          print('   ✅ Next reminder: $scheduledTime (today)');
          return scheduledTime;
        }
      } catch (e) {
        print('   ⚠️ Error parsing time $timeStr: $e');
      }
    }
    try {
      final firstTime = sortedTimes.first.split(':');
      final hour = int.parse(firstTime[0]);
      final minute = int.parse(firstTime[1]);
      final tomorrow =
          DateTime(now.year, now.month, now.day + 1, hour, minute);
      print('   ✅ Next reminder: $tomorrow (tomorrow)');
      return tomorrow;
    } catch (e) {
      print('   ❌ Error calculating next time: $e');
      return null;
    }
  }

  void dispose() {
    // Cleanup if needed
  }
}